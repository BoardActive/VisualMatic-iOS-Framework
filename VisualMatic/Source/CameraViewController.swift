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
    @IBOutlet var btnCameraMode: UIButton!
    @IBOutlet private weak var cameraView: UIView!
    @IBOutlet private weak var tabBar: UIView!
    @IBOutlet private weak var imgObject: UIImageView!

    //MARK:- Private Variables
    private let detectors: [Detector] = [ .onDeviceObjectCustomProminentWithClassifier, .onDeviceObjectCustomMultipleWithClassifier]
    private var currentDetector: Detector = .onDeviceObjectCustomProminentWithClassifier
    private var isUsingFrontCamera = false
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private lazy var captureSession = AVCaptureSession()
    private lazy var sessionQueue = DispatchQueue(label: Constant.sessionQueueLabel)
    private var lastFrame: CMSampleBuffer?
    private var imagePicker = UIImagePickerController()

    //MARK:- Public Variables
    public var delegate: CameraViewControllerDelegate?
    public var EnableScanner: ScannerType = .CustomObject
    public var EnableTabBar: Bool? = true

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
        selectScanner()
    }

    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startSession()
        setupSDK()
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
                let tapGesture = ObjectTapEvent(target: self, action: #selector(self.cameraObject(sender:)))
                tapGesture.objectId = object.labels.first?.index
                tapGesture.objectName = object.labels.first?.text ?? ""

                let normalizedRect = CGRect(x: object.frame.origin.x / width, y: object.frame.origin.y / height, width: object.frame.size.width / width, height: object.frame.size.height / height)
                let standardizedRect = self.previewLayer.layerRectConverted( fromMetadataOutputRect: normalizedRect).standardized
                let box = UIUtilities.addRectangle(standardizedRect, borderColor: .white)
                self.annotationOverlayView.addGestureRecognizer(tapGesture)
                self.annotationOverlayView.addSubview(box)
                
                
       /*         let normalizedRect = CGRect(x: object.frame.origin.x / width, y: object.frame.origin.y / height, width: object.frame.size.width / width, height: object.frame.size.height / height)
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
                self.annotationOverlayView.addSubview(label)*/
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
    
    
  /*  override public func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
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
    }*/
    
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
        guard let lastFrame = lastFrame, let imageBuffer = CMSampleBufferGetImageBuffer(lastFrame) else {
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
    
    
    private func setupSDK(){
        if (EnableTabBar!) {
            tabBar.isHidden = false
        }
    }
    
    
    @IBAction func btnClose(_ sender: Any) {
        stopSession()
        delegate?.closeButtonAction?()
    }
    
    @IBAction func btnChangeScanner(sender: UIButton) {
        switch sender.tag {
            case 101:
                EnableScanner = .CustomObject
                
            case 102:
                EnableScanner = .TextRecognizer

            case 103:
                EnableScanner = .DigitalInkRecognizer

            case 104:
                EnableScanner = .BarcodeScanner
                
            default:
                print("Scanner not exist")
        }
        selectScanner()
    }
    
    
    //This action change image capture mode.
    @IBAction func btnCaptureOption(sender: UIButton) {
        stopSession()
        let actionSheet = UIAlertController(title: "Mode", message: nil, preferredStyle: .actionSheet)
        let cameraAction = UIAlertAction(title: "Camera", style: .default) { (action) in
            DispatchQueue.main.async {
                self.removeBoxFromImageView()
                self.startSession()
                self.cameraView.isHidden = false
                self.imgObject.isHidden = true
                self.imgObject.image = nil
            }
        }
        
        let galleryAction = UIAlertAction(title: "Gallery", style: .default) { (action) in
            self.imagePicker.sourceType = .photoLibrary
            self.imagePicker.delegate = self
            DispatchQueue.main.async {
                self.removeBoxFromImageView()
                self.stopSession()
                self.cameraView.isHidden = true
                self.imgObject.isHidden = false
                self.present(self.imagePicker, animated: true, completion: nil)
            }
        }
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .destructive, handler: nil)
        
        actionSheet.addAction(cameraAction)
        actionSheet.addAction(galleryAction)
        actionSheet.addAction(cancelAction)
        
        present(actionSheet, animated: true, completion: nil)
    }
    
    private func selectScanner() {
        if let selectedButton = tabBar.viewWithTag(EnableScanner.rawValue) as? UIButton {
            selectedButton.backgroundColor = UIColor(displayP3Red: 52.0/255.0, green: 199.0/255.0, blue: 89.0/255.0, alpha: 1.0)
            selectedButton.setTitleColor(UIColor.white, for: .normal)
            
            for i in 101...104 {
                if let btnTemp = tabBar.viewWithTag(i) as? UIButton {
                    if (EnableScanner.rawValue != i) {
                        btnTemp.backgroundColor = UIColor.white
                        btnTemp.setTitleColor(UIColor(displayP3Red: 9.0/255.0, green: 145.0/255.0, blue: 255.0/255.0, alpha: 1.0), for: .normal)
                    }
                }
            }
        }
    }
    
    private func updateImageView(with image: UIImage) {
        let orientation = UIApplication.shared.statusBarOrientation
        var scaledImageWidth: CGFloat = 0.0
        var scaledImageHeight: CGFloat = 0.0
        switch orientation {
            case .portrait, .portraitUpsideDown, .unknown:
                scaledImageWidth = imgObject.bounds.size.width
                scaledImageHeight = image.size.height * scaledImageWidth / image.size.width
            case .landscapeLeft, .landscapeRight:
                scaledImageWidth = image.size.width * scaledImageHeight / image.size.height
                scaledImageHeight = imgObject.bounds.size.height
            @unknown default:
            fatalError()
        }
        weak var weakSelf = self
        DispatchQueue.global(qos: .userInitiated).async {
            var scaledImage = image.scaledImage( with: CGSize(width: scaledImageWidth, height: scaledImageHeight))
            scaledImage = scaledImage ?? image
            guard let finalImage = scaledImage else { return }
            DispatchQueue.main.async {
                weakSelf?.imgObject.image = finalImage
                self.processGalleryImages(image: finalImage)
            }
        }
    }
    
    private func processGalleryImages(image: UIImage) {
        let visionImage = VisionImage(image: image)
        visionImage.orientation = image.imageOrientation
        
        switch EnableScanner {
            case .CustomObject:
                scanCustomObject(image: visionImage)
                
            case .TextRecognizer:
                recognizeText(image: visionImage)
                
            case .BarcodeScanner:
                scanBarcodes(image: visionImage)
                
        case .DigitalInkRecognizer:
            print("in development")
        }
    }
    
    private func transformMatrix() -> CGAffineTransform {
        guard let image = imgObject.image else { return CGAffineTransform() }
        let imageViewWidth = imgObject.frame.size.width
        let imageViewHeight = imgObject.frame.size.height
        let imageWidth = image.size.width
        let imageHeight = image.size.height

        let imageViewAspectRatio = imageViewWidth / imageViewHeight
        let imageAspectRatio = imageWidth / imageHeight
        let scale = (imageViewAspectRatio > imageAspectRatio) ? imageViewHeight / imageHeight : imageViewWidth / imageWidth

        // Image view's `contentMode` is `scaleAspectFit`, which scales the image to fit the size of the
        // image view by maintaining the aspect ratio. Multiple by `scale` to get image's original size.
        let scaledImageWidth = imageWidth * scale
        let scaledImageHeight = imageHeight * scale
        let xValue = (imageViewWidth - scaledImageWidth) / CGFloat(2.0)
        let yValue = (imageViewHeight - scaledImageHeight) / CGFloat(2.0)

        var transform = CGAffineTransform.identity.translatedBy(x: xValue, y: yValue)
        transform = transform.scaledBy(x: scale, y: scale)
        return transform
    }

    
    private func removeBoxFromImageView() {
        for view in imgObject.subviews {
            view.removeFromSuperview()
        }
    }
    
    
    private func showAlert(message: String) {
        let alert = UIAlertController(title: "VisualMatic", message: message, preferredStyle: .alert)
        let okAction = UIAlertAction(title: "OK", style: .default, handler: nil)
        alert.addAction(okAction)
        present(alert, animated: true, completion: nil)
    }

}

//MARK: Public methods
extension CameraViewController {
    
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
                
        case .DigitalInkRecognizer:
            print("in development")
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
    
    private func scanCustomObject(image: VisionImage) {
        guard let localModelFilePath = Bundle.main.path( forResource: Constant.localModelFile.name, ofType: Constant.localModelFile.type)
        else {
            print("Failed to find custom local model file.")
            return
        }

        let localModel = LocalModel(path: localModelFilePath)
        let options = CustomObjectDetectorOptions(localModel: localModel)
        options.shouldEnableClassification = true
        options.shouldEnableMultipleObjects = true
        options.detectorMode = .singleImage
                
        let detector = ObjectDetector.objectDetector(options: options)
        detector.process(image) { (objects, error) in
            
            if (error != nil) {
                print(error!.localizedDescription)
                return
            }
            
            DispatchQueue.main.async {
                self.removeDetectionAnnotations()
            }

            guard let detectedObjects = objects, !detectedObjects.isEmpty else {
                print("On-Device object detector returned no results.")
                return
            }
            
            for object in objects! {
                let tapGesture = ObjectTapEvent(target: self, action: #selector(self.galleryObject(sender:)))
                tapGesture.objectId = object.labels.first?.index ?? 0
                tapGesture.objectName = object.labels.first?.text ?? ""

                let transform = self.transformMatrix()
                let standardizedRect = object.frame.applying(transform)
                let box = UIUtilities.addRectangle(standardizedRect, borderColor: .white)
                box.addGestureRecognizer(tapGesture)
                self.imgObject.addSubview(box)
            }
        }
    }
    
    @objc func galleryObject(sender: ObjectTapEvent) {
        if (EnableScanner == .CustomObject) {
            if let message = sender.objectName, sender.objectId != 0 {
                showAlert(message: message)
            } else {
                showAlert(message: "The details of the object is not available in the model.")
            }
        } else {
            if let message = sender.objectName {
                showAlert(message: message)
            }
        }
        print(sender.objectName)
    }
    
    
    @objc func cameraObject(sender: ObjectTapEvent) {
        stopSession()
        
        if (EnableScanner == .CustomObject) {
            if let message = sender.objectName, sender.objectId != 0 {
                showAlert(message: message)
            } else {
                showAlert(message: "The details of the object is not available in the model.")
            }
        } else {
            if let message = sender.objectName {
                showAlert(message: message)
            }
        }
        print(sender.objectName)

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
                        let tapGesture = ObjectTapEvent(target: self, action: #selector(self.cameraObject(sender:)))
                        tapGesture.objectName = element.text

                        let normalizedRect = CGRect(x: element.frame.origin.x / width, y: element.frame.origin.y / height, width: element.frame.size.width / width, height: element.frame.size.height / height)
                        let standardizedRect = self.previewLayer.layerRectConverted( fromMetadataOutputRect: normalizedRect).standardized
                        let box = UIUtilities.addRectangle(standardizedRect, borderColor: .white)
                        self.annotationOverlayView.addGestureRecognizer(tapGesture)
                        self.annotationOverlayView.addSubview(box)

                        
//                        let normalizedRect = CGRect(x: element.frame.origin.x / width, y: element.frame.origin.y / height, width: element.frame.size.width / width, height: element.frame.size.height / height)
//                        let convertedRect = self.previewLayer.layerRectConverted(fromMetadataOutputRect: normalizedRect)
//                        UIUtilities.addRectangle(convertedRect, to: self.annotationOverlayView, color: UIColor.green)
//                        let label = UILabel(frame: convertedRect)
//                        label.text = element.text
//                        label.adjustsFontSizeToFitWidth = true
//                        self.annotationOverlayView.addSubview(label)
                    }
                }
            }
        }
    }
    
    
    private func recognizeText(image: VisionImage) {
        let textRecognizer = TextRecognizer.textRecognizer()
        textRecognizer.process(image) { result, error in
            guard error == nil, let result = result else {
                // Error handling
                return
            }
            
            DispatchQueue.main.async {
//                self.removeBoxFromImageView()
                self.removeDetectionAnnotations()
            }
            
            for block in result.blocks {
                // Lines.
                for line in block.lines {
                    // Elements.
                    for element in line.elements {
                        let tapGesture = ObjectTapEvent(target: self, action: #selector(self.galleryObject(sender:)))
                        tapGesture.objectId = 0
                        tapGesture.objectName = element.text

                        let transform = self.transformMatrix()
                        let standardizedRect = element.frame.applying(transform)
                        let box = UIUtilities.addRectangle(standardizedRect, borderColor: .white)
                        box.addGestureRecognizer(tapGesture)
                        self.imgObject.addSubview(box)
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
                let tapGesture = ObjectTapEvent(target: self, action: #selector(self.cameraObject(sender:)))
                tapGesture.objectName = barcode.rawValue

                let normalizedRect = CGRect(x: barcode.frame.origin.x / width, y: barcode.frame.origin.y / height, width: barcode.frame.size.width / width, height: barcode.frame.size.height / height)
                let standardizedRect = self.previewLayer.layerRectConverted( fromMetadataOutputRect: normalizedRect).standardized
                let box = UIUtilities.addRectangle(standardizedRect, borderColor: .white)
                self.annotationOverlayView.addGestureRecognizer(tapGesture)
                self.annotationOverlayView.addSubview(box)


                
                
            /*    let normalizedRect = CGRect(x: barcode.frame.origin.x / width, y: barcode.frame.origin.y / height, width: barcode.frame.size.width / width, height: barcode.frame.size.height / height)
                let convertedRect = strongSelf.previewLayer.layerRectConverted(fromMetadataOutputRect: normalizedRect)
                UIUtilities.addRectangle(convertedRect, to: strongSelf.annotationOverlayView, color: UIColor.green)
                let label = UILabel(frame: convertedRect)
                label.text = barcode.rawValue
                label.adjustsFontSizeToFitWidth = true
                strongSelf.rotate(label, orientation: image.orientation)
                strongSelf.annotationOverlayView.addSubview(label)
                print("Barcode value: \(barcode.rawValue)")*/
            }
        }
    }
    
    
    private func scanBarcodes(image: VisionImage) {
       
        let format = BarcodeFormat.all
        let barcodeOptions = BarcodeScannerOptions(formats: format)
        let barcodeScanner = BarcodeScanner.barcodeScanner(options: barcodeOptions)

        barcodeScanner.process(image) { features, error in
          guard error == nil, let features = features, !features.isEmpty else {
            print(error.debugDescription)
            return
          }
          // Recognized barcodes
            DispatchQueue.main.async {
                self.removeDetectionAnnotations()
            }
            
            for barcode in features {
                let tapGesture = ObjectTapEvent(target: self, action: #selector(self.galleryObject(sender:)))
                tapGesture.objectName = barcode.rawValue
                
                let transform = self.transformMatrix()
                let standardizedRect = barcode.frame.applying(transform)
                let box = UIUtilities.addRectangle(standardizedRect, borderColor: .systemGreen)
                box.addGestureRecognizer(tapGesture)
                self.imgObject.addSubview(box)

//                let normalizedRect = CGRect(x: barcode.frame.origin.x / width, y: barcode.frame.origin.y / height, width: barcode.frame.size.width / width, height: barcode.frame.size.height / height)
//                let standardizedRect = self.previewLayer.layerRectConverted( fromMetadataOutputRect: normalizedRect).standardized
//                let box = UIUtilities.addRectangle(standardizedRect, borderColor: .white)
//                self.annotationOverlayView.addGestureRecognizer(tapGesture)
//                self.annotationOverlayView.addSubview(box)

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

// MARK: - UIImagePickerControllerDelegate
extension CameraViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {

    public func imagePickerController( _ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        removeDetectionAnnotations()
        if let pickedImage = info[UIImagePickerController.InfoKey.originalImage] as? UIImage {
            updateImageView(with: pickedImage)
        }
        dismiss(animated: true)
    }
}



