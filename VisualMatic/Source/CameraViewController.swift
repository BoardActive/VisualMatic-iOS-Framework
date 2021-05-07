//
//  Copyright (c) 2018 Google Inc.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import AVFoundation
import CoreVideo
import MLKitCommon
import MLKitObjectDetectionCustom
import MLKitVision
import MLKitTextRecognition
import MLKitBarcodeScanning
import BAKit

@objc public protocol CameraViewControllerDelegate {
    @objc optional func closeButtonAction()
}

//@objc(CameraViewController)
public class CameraViewController: UIViewController {
    
    //MArK:- Outlets
    @IBOutlet var btnClose: UIButton!
    @IBOutlet private weak var cameraView: UIView!

    //MARK:- Private Variables
    private let detectors: [Detector] = [ .onDeviceObjectCustomProminentWithClassifier, .onDeviceObjectCustomMultipleWithClassifier]
    private var currentDetector: Detector = .onDeviceObjectCustomProminentWithClassifier
    private var isUsingFrontCamera = false
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private lazy var captureSession = AVCaptureSession()
    private lazy var sessionQueue = DispatchQueue(label: Constant.sessionQueueLabel)
    private var lastFrame: CMSampleBuffer?
    
    //MARK:- Public Variables
    public var delegate: CameraViewControllerDelegate?
    public var EnableScanner: ScannerType = .CustomObject

    var objects: [Object] = []
    var arrOffers: [[String: Any]]?
    var activityView: UIActivityIndicatorView?

    private lazy var previewOverlayView: UIImageView = {
        precondition(isViewLoaded)
        let previewOverlayView = UIImageView(frame: .zero)
        previewOverlayView.contentMode = UIView.ContentMode.scaleAspectFill
        previewOverlayView.translatesAutoresizingMaskIntoConstraints = false
        return previewOverlayView
    }()

    private lazy var annotationOverlayView: UIView = {
        precondition(isViewLoaded)
        let annotationOverlayView = UIView(frame: .zero)
        annotationOverlayView.translatesAutoresizingMaskIntoConstraints = false
        return annotationOverlayView
    }()

  // MARK: - View Life Cycle
    override public func viewDidLoad() {
        super.viewDidLoad()
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        setUpPreviewOverlayView()
        setUpAnnotationOverlayView()
        setUpCaptureSessionInput()
        setUpCaptureSessionOutput()
    }

    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startSession()
    }

    override public func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        stopSession()
    }

    override public func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = cameraView.frame
    }

    // MARK: - Private methods
    // MARK: On-Device Detections
    
    private func detectObjectsOnDevice(in image: VisionImage, width: CGFloat, height: CGFloat, options: CommonObjectDetectorOptions) {
        let detector = ObjectDetector.objectDetector(options: options)
        do {
            objects = try detector.results(in: image)
        } catch let error {
            print("Failed to detect objects with error: \(error.localizedDescription).")
            return
        }

        DispatchQueue.main.sync {
            self.updatePreviewOverlayView()
            self.removeDetectionAnnotations()
        }
        guard !objects.isEmpty else {
            print("On-Device object detector returned no results.")
            return
        }

        DispatchQueue.main.sync {
            for object in objects {
                let normalizedRect = CGRect(x: object.frame.origin.x / width, y: object.frame.origin.y / height, width: object.frame.size.width / width, height: object.frame.size.height / height)
                let standardizedRect = self.previewLayer.layerRectConverted( fromMetadataOutputRect: normalizedRect).standardized
                UIUtilities.addRectangle(standardizedRect, to: self.annotationOverlayView, color: UIColor.green)
                let label = UILabel(frame: standardizedRect)
                var description = ""
                if let trackingID = object.trackingID {
                    description += "Object ID: " + trackingID.stringValue + "\n"
                }
                description += object.labels.enumerated().map { (index, label) in
                  "Label \(index): \(label.text), \(label.confidence), \(label.index)"
                }.joined(separator: "\n")

                label.text = description
                label.numberOfLines = 0
                label.adjustsFontSizeToFitWidth = true
                self.annotationOverlayView.addSubview(label)
            }
        }
    }

    private func setUpCaptureSessionOutput() {
        sessionQueue.async {
            self.captureSession.beginConfiguration()
            // When performing latency tests to determine ideal capture settings,
            // run the app in 'release' mode to get accurate performance metrics
            self.captureSession.sessionPreset = AVCaptureSession.Preset.medium
            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [(kCVPixelBufferPixelFormatTypeKey as String): kCVPixelFormatType_32BGRA]
            output.alwaysDiscardsLateVideoFrames = true
            let outputQueue = DispatchQueue(label: Constant.videoDataOutputQueueLabel)
            output.setSampleBufferDelegate(self, queue: outputQueue)
            guard self.captureSession.canAddOutput(output) else {
                print("Failed to add capture session output.")
                return
            }
            self.captureSession.addOutput(output)
            self.captureSession.commitConfiguration()
        }
    }

    private func setUpCaptureSessionInput() {
        sessionQueue.async {
            let cameraPosition: AVCaptureDevice.Position = self.isUsingFrontCamera ? .front : .back
            guard let device = self.captureDevice(forPosition: cameraPosition) else {
                print("Failed to get capture device for camera position: \(cameraPosition)")
                return
            }
            do {
                self.captureSession.beginConfiguration()
                let currentInputs = self.captureSession.inputs
                for input in currentInputs {
                    self.captureSession.removeInput(input)
                }
    
                let input = try AVCaptureDeviceInput(device: device)
                guard self.captureSession.canAddInput(input) else {
                    print("Failed to add capture session input.")
                    return
                }
                self.captureSession.addInput(input)
                self.captureSession.commitConfiguration()
            } catch {
                print("Failed to create capture device input: \(error.localizedDescription)")
            }
        }
    }

    private func startSession() {
        sessionQueue.async {
            self.captureSession.startRunning()
        }
    }

    private func stopSession() {
        sessionQueue.async {
            self.captureSession.stopRunning()
        }
    }

    private func setUpPreviewOverlayView() {
        cameraView.addSubview(previewOverlayView)
        NSLayoutConstraint.activate([
            previewOverlayView.centerXAnchor.constraint(equalTo: cameraView.centerXAnchor),
            previewOverlayView.centerYAnchor.constraint(equalTo: cameraView.centerYAnchor),
            previewOverlayView.leadingAnchor.constraint(equalTo: cameraView.leadingAnchor),
            previewOverlayView.trailingAnchor.constraint(equalTo: cameraView.trailingAnchor),
            previewOverlayView.topAnchor.constraint(equalTo: cameraView.topAnchor)])
    }

    private func setUpAnnotationOverlayView() {
        cameraView.addSubview(annotationOverlayView)
        NSLayoutConstraint.activate([
            annotationOverlayView.topAnchor.constraint(equalTo: cameraView.topAnchor),
            annotationOverlayView.leadingAnchor.constraint(equalTo: cameraView.leadingAnchor),
            annotationOverlayView.trailingAnchor.constraint(equalTo: cameraView.trailingAnchor),
            annotationOverlayView.bottomAnchor.constraint(equalTo: cameraView.bottomAnchor)])
    }
    
    
    override public func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let touch = touches.first!
        let location = touch.location(in: self.annotationOverlayView)
        
        for annotationView in annotationOverlayView.subviews {
            if annotationView.frame.contains(location) {
                print("GOT")
                btnClose.isHidden = false
                stopSession()
                let image3 = self.previewOverlayView.image!
                var fr = annotationView.frame
                if isiPhoneNotHaveHomeButton() {
                    fr.origin.y =  fr.origin.y-110
                } else {
                    fr.origin.y =  fr.origin.y-40
                }
                self.postLocal(brand: "Rolex")
                break
            }
        }
    }
    
    func postLocal(brand: String) {
        activityView = UIActivityIndicatorView(style: .white)
        activityView?.center = self.view.center
        activityView?.startAnimating()
        if activityView != nil {
            self.view.addSubview(activityView!)
            self.view.bringSubviewToFront(activityView!)
        }
        self.activityView?.startAnimating()
        let finalDict = ["brandName": brand, "deviceTime": ""]
        VMAPIService.sharedVMAPIService.sendScanResult(body: finalDict) { (response, error) in
            if (response != nil) {
                self.arrOffers = (response?["messages"] as! [[String : Any]])
                print(self.arrOffers)
                DispatchQueue.main.async {
                    if (self.arrOffers != nil) && self.arrOffers!.count > 0 {
                    }
                }
            }
            DispatchQueue.main.async {
                self.activityView?.stopAnimating()
            }
        }
    }
    
    func isiPhoneNotHaveHomeButton() -> Bool {
        if #available(iOS 11.0, *), let keyWindow = UIApplication.shared.keyWindow,
            keyWindow.safeAreaInsets.bottom > 0 {
            return true
        }
        return false
    }

  private func captureDevice(forPosition position: AVCaptureDevice.Position) -> AVCaptureDevice? {
    if #available(iOS 10.0, *) {
      let discoverySession = AVCaptureDevice.DiscoverySession(
        deviceTypes: [.builtInWideAngleCamera],
        mediaType: .video,
        position: .unspecified
      )
      return discoverySession.devices.first { $0.position == position }
    }
    return nil
  }

  private func presentDetectorsAlertController() {
    let alertController = UIAlertController(
      title: Constant.alertControllerTitle,
      message: Constant.alertControllerMessage,
      preferredStyle: .alert
    )
    detectors.forEach { detectorType in
      let action = UIAlertAction(title: detectorType.rawValue, style: .default) {
        [unowned self] (action) in
        guard let value = action.title else { return }
        guard let detector = Detector(rawValue: value) else { return }
        self.currentDetector = detector
        self.removeDetectionAnnotations()
      }
      if detectorType.rawValue == currentDetector.rawValue { action.isEnabled = false }
      alertController.addAction(action)
    }
    alertController.addAction(UIAlertAction(title: Constant.cancelActionTitleText, style: .cancel))
    present(alertController, animated: true)
  }

  private func removeDetectionAnnotations() {
    for annotationView in annotationOverlayView.subviews {
      annotationView.removeFromSuperview()
    }
  }

  private func updatePreviewOverlayView() {
    guard let lastFrame = lastFrame,
          let imageBuffer = CMSampleBufferGetImageBuffer(lastFrame)
    else {
        return
    }
    
    let ciImage = CIImage(cvPixelBuffer: imageBuffer)
    let context = CIContext(options: nil)
    guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
        return
    }
    let rotatedImage = UIImage(cgImage: cgImage, scale: Constant.originalScale, orientation: .right)
    if isUsingFrontCamera {
        guard let rotatedCGImage = rotatedImage.cgImage else {
            return
        }
        let mirroredImage = UIImage(
        cgImage: rotatedCGImage, scale: Constant.originalScale, orientation: .leftMirrored)
        previewOverlayView.image = mirroredImage
        
    } else {
        previewOverlayView.image = rotatedImage
    }
  }

  private func convertedPoints( from points: [NSValue]?, width: CGFloat, height: CGFloat) -> [NSValue]? {
    return points?.map {
      let cgPointValue = $0.cgPointValue
      let normalizedPoint = CGPoint(x: cgPointValue.x / width, y: cgPointValue.y / height)
      let cgPoint = previewLayer.layerPointConverted(fromCaptureDevicePoint: normalizedPoint)
      let value = NSValue(cgPoint: cgPoint)
      return value
    }
  }

    private func normalizedPoint(fromVisionPoint point: VisionPoint, width: CGFloat, height: CGFloat) -> CGPoint {
        let cgPoint = CGPoint(x: point.x, y: point.y)
        var normalizedPoint = CGPoint(x: cgPoint.x / width, y: cgPoint.y / height)
        normalizedPoint = previewLayer.layerPointConverted(fromCaptureDevicePoint: normalizedPoint)
        return normalizedPoint
    }
    
    @IBAction func btnClose(_ sender: Any) {
        stopSession()
        delegate?.closeButtonAction?()
    }
}

//MARK: Public methods
extension CameraViewController {
    public func setupSDK(){
    }
    
    public func modifyCloseButton(image butttonImage: UIImage?, title buttonTitle: String?) {
        if (buttonTitle != nil) {
            btnClose.setTitle(buttonTitle!, for: .normal)
        }
        
        if (butttonImage != nil) {
            btnClose.setImage(butttonImage!, for: .normal)
        }
    }
}

// MARK: AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraViewController: AVCaptureVideoDataOutputSampleBufferDelegate {

    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            print("Failed to get image buffer from sample buffer.")
            return
        }
        lastFrame = sampleBuffer
        let visionImage = VisionImage(buffer: sampleBuffer)
        let orientation = UIUtilities.imageOrientation(
          fromDevicePosition: isUsingFrontCamera ? .front : .back
        )
        visionImage.orientation = orientation
        
        switch EnableScanner {
            case .CustomObject:
                scanCustomObject(image: visionImage, imageBuffer: imageBuffer)
                
            case .TextRecognizer:
                recognizeText(image: visionImage, imageBuffer: imageBuffer)
                
            case .BarcodeScanner:
                scanBarcodes(image: visionImage, imageBuffer: imageBuffer)
        }
    }
    
    private func scanCustomObject(image: VisionImage, imageBuffer: CVImageBuffer) {
        let imageWidth = CGFloat(CVPixelBufferGetWidth(imageBuffer))
        let imageHeight = CGFloat(CVPixelBufferGetHeight(imageBuffer))
        
        guard let localModelFilePath = Bundle.main.path( forResource: Constant.localModelFile.name, ofType: Constant.localModelFile.type)
        else {
            print("Failed to find custom local model file.")
            return
        }
        
        let localModel = LocalModel(path: localModelFilePath)
        let options = CustomObjectDetectorOptions(localModel: localModel)
        options.shouldEnableClassification = true
        options.shouldEnableMultipleObjects = true
        options.detectorMode = .stream
        detectObjectsOnDevice(in: image, width: imageWidth, height: imageHeight, options: options)
    }
    
    private func recognizeText(image: VisionImage, imageBuffer: CVImageBuffer) {
        let width = CGFloat(CVPixelBufferGetWidth(imageBuffer))
        let height = CGFloat(CVPixelBufferGetHeight(imageBuffer))

        var recognizedText: Text
        do {
            recognizedText = try TextRecognizer.textRecognizer().results(in: image)
        } catch let error {
            print("Failed to recognize text with error: \(error.localizedDescription).")
            return
        }
        
        DispatchQueue.main.sync {
            self.updatePreviewOverlayView()
            self.removeDetectionAnnotations()

            // Blocks.
            for block in recognizedText.blocks {
//                let points = self.convertedPoints(from: block.cornerPoints, width: width, height: height)
//                UIUtilities.addShape(withPoints: points, to: self.annotationOverlayView, color: UIColor.purple)

                // Lines.
                for line in block.lines {
//                    let points = self.convertedPoints(from: line.cornerPoints, width: width, height: height)
//                    UIUtilities.addShape(withPoints: points, to: self.annotationOverlayView, color: UIColor.orange)

                    // Elements.
                    for element in line.elements {
                        let normalizedRect = CGRect(x: element.frame.origin.x / width, y: element.frame.origin.y / height, width: element.frame.size.width / width, height: element.frame.size.height / height)
                        let convertedRect = self.previewLayer.layerRectConverted(fromMetadataOutputRect: normalizedRect)
                        UIUtilities.addRectangle(convertedRect, to: self.annotationOverlayView, color: UIColor.green)
                        let label = UILabel(frame: convertedRect)
                        label.text = element.text
                        label.adjustsFontSizeToFitWidth = true
                        self.annotationOverlayView.addSubview(label)
                    }
                }
            }
        }
    }
    
    private func scanBarcodes(image: VisionImage, imageBuffer: CVImageBuffer) {
        let width = CGFloat(CVPixelBufferGetWidth(imageBuffer))
        let height = CGFloat(CVPixelBufferGetHeight(imageBuffer))

        let format = BarcodeFormat.all
        let barcodeOptions = BarcodeScannerOptions(formats: format)
        let barcodeScanner = BarcodeScanner.barcodeScanner(options: barcodeOptions)

        var barcodes: [Barcode]
        do {
            barcodes = try barcodeScanner.results(in: image)
        } catch let error {
            print("Failed to scan barcodes with error: \(error.localizedDescription).")
            return
        }
        weak var weakSelf = self
        DispatchQueue.main.sync {
            guard let strongSelf = weakSelf else {
                print("Self is nil!")
                return
            }
            strongSelf.updatePreviewOverlayViewWithLastFrame()
            strongSelf.removeDetectionAnnotations()
        }
        
        guard !barcodes.isEmpty else {
          print("Barcode scanner returned no results.")
          return
        }
        
        DispatchQueue.main.sync {
            guard let strongSelf = weakSelf else {
                print("Self is nil!")
                return
            }
            for barcode in barcodes {
                let normalizedRect = CGRect(x: barcode.frame.origin.x / width, y: barcode.frame.origin.y / height, width: barcode.frame.size.width / width, height: barcode.frame.size.height / height)
                let convertedRect = strongSelf.previewLayer.layerRectConverted(fromMetadataOutputRect: normalizedRect)
                UIUtilities.addRectangle(convertedRect, to: strongSelf.annotationOverlayView, color: UIColor.green)
                let label = UILabel(frame: convertedRect)
                label.text = barcode.rawValue
                label.adjustsFontSizeToFitWidth = true
                strongSelf.rotate(label, orientation: image.orientation)
                strongSelf.annotationOverlayView.addSubview(label)
                print("Barcode value: \(barcode.rawValue)")
            }
        }
    }
    
    
    private func rotate(_ view: UIView, orientation: UIImage.Orientation) {
        var degree: CGFloat = 0.0
        switch orientation {
            case .up, .upMirrored:
              degree = 90.0
            case .rightMirrored, .left:
              degree = 180.0
            case .down, .downMirrored:
              degree = 270.0
            case .leftMirrored, .right:
              degree = 0.0
             default:
                print("no orientation")
        }
        view.transform = CGAffineTransform.init(rotationAngle: degree * 3.141592654 / 180)
    }
    
    private func updatePreviewOverlayViewWithLastFrame() {
      guard let lastFrame = lastFrame,
        let imageBuffer = CMSampleBufferGetImageBuffer(lastFrame)
      else {
        return
      }
      self.updatePreviewOverlayViewWithImageBuffer(imageBuffer)
    }

    private func updatePreviewOverlayViewWithImageBuffer(_ imageBuffer: CVImageBuffer?) {
      guard let imageBuffer = imageBuffer else {
        return
      }
      let orientation: UIImage.Orientation = isUsingFrontCamera ? .leftMirrored : .right
      let image = UIUtilities.createUIImage(from: imageBuffer, orientation: orientation)
      previewOverlayView.image = image
    }

}
