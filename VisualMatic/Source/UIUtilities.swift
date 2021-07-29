//
//  UIUtilities.swift
//  VisualMatic
//
//  Created by Indrajeet Senger on 12/05/21.
//

import AVFoundation
import UIKit

/// Defines UI-related utilitiy methods for vision detection.
public class UIUtilities {

  // MARK: - Public
    public static func addRectangle(_ rectangle: CGRect, to view: UIView, color: UIColor) {
        guard rectangle.isValid() else { return }
        let rectangleView = UIView(frame: rectangle)
        rectangleView.layer.cornerRadius = Constants.rectangleViewCornerRadius
        rectangleView.alpha = Constants.rectangleViewAlpha
        rectangleView.backgroundColor = color
        view.addSubview(rectangleView)
    }
    
    public static func addRectangle(_ rectangle: CGRect, borderColor: UIColor) -> UIView {
        let rectangleView = UIView(frame: rectangle)
        rectangleView.isUserInteractionEnabled = true
        rectangleView.layer.cornerRadius = Constants.rectangleViewCornerRadius
        rectangleView.layer.borderWidth = 2
        rectangleView.layer.borderColor = borderColor.cgColor
        rectangleView.backgroundColor = .clear
        return rectangleView
    }

    public static func imageOrientation( fromDevicePosition devicePosition: AVCaptureDevice.Position = .back) -> UIImage.Orientation {
        var deviceOrientation = UIDevice.current.orientation
        if deviceOrientation == .faceDown || deviceOrientation == .faceUp || deviceOrientation == .unknown
        {
          deviceOrientation = currentUIOrientation()
        }
        switch deviceOrientation {
            case .portrait:
                return devicePosition == .front ? .leftMirrored : .right
            case .landscapeLeft:
                return devicePosition == .front ? .downMirrored : .up
            case .portraitUpsideDown:
                return devicePosition == .front ? .rightMirrored : .left
            case .landscapeRight:
                return devicePosition == .front ? .upMirrored : .down
            case .faceDown, .faceUp, .unknown:
                return .up
            @unknown default:
                fatalError()
        }
    }
    
    public static func createUIImage(from imageBuffer: CVImageBuffer, orientation: UIImage.Orientation) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage, scale: Constants.originalScale, orientation: orientation)
    }


  // MARK: - Private

    private static func currentUIOrientation() -> UIDeviceOrientation {
        let deviceOrientation = { () -> UIDeviceOrientation in
          switch UIApplication.shared.statusBarOrientation {
            case .landscapeLeft:
                return .landscapeRight
                
            case .landscapeRight:
                return .landscapeLeft
                
            case .portraitUpsideDown:
                return .portraitUpsideDown
                
            case .portrait, .unknown:
                return .portrait
                
            @unknown default:
                fatalError()
          }
        }
        guard Thread.isMainThread else {
            var currentOrientation: UIDeviceOrientation = .portrait
            DispatchQueue.main.sync {
                currentOrientation = deviceOrientation()
            }
            return currentOrientation
        }
        return deviceOrientation()
    }
}
