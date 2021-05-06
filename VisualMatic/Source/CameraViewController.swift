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
import BAKit


@objc(CameraViewController)
public class CameraViewController: UIViewController {
    private let detectors: [Detector] = [ .onDeviceObjectCustomProminentWithClassifier, .onDeviceObjectCustomMultipleWithClassifier]
    @IBOutlet var imgv: UIImageView!
    @IBOutlet var btnClose: UIButton!
    @IBOutlet var btnText: UIButton!
    @IBOutlet var btnObject: UIButton!
    @IBOutlet var tblObj: UITableView!
    private var currentDetector: Detector = .onDeviceObjectCustomMultipleWithClassifier
    private var isUsingFrontCamera = false
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private lazy var captureSession = AVCaptureSession()
    private lazy var sessionQueue = DispatchQueue(label: Constant.sessionQueueLabel)
    private var lastFrame: CMSampleBuffer?
    var objects: [Object] = []
    var arrOffers: [[String: Any]]?
    let APP_ID = "242"
    let APP_KEY = "79eb70da-4162-4cc6-a9a7-689459fa8484"
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

  // MARK: - IBOutlets

  @IBOutlet private weak var cameraView: UIView!

  // MARK: - UIViewController

    override public func viewDidLoad() {
        super.viewDidLoad()
        tblObj.isHidden = true
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        setUpPreviewOverlayView()
        setUpAnnotationOverlayView()
        setUpCaptureSessionOutput()
        setUpCaptureSessionInput()
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

  // MARK: On-Device Detections

  private func recognizeTextOnDevice(in image: VisionImage, width: CGFloat, height: CGFloat) {
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
        let points = self.convertedPoints(from: block.cornerPoints, width: width, height: height)
        UIUtilities.addShape(
          withPoints: points,
          to: self.annotationOverlayView,
          color: UIColor.purple
        )

        // Lines.
        for line in block.lines {
          let points = self.convertedPoints(from: line.cornerPoints, width: width, height: height)
          UIUtilities.addShape(
            withPoints: points,
            to: self.annotationOverlayView,
            color: UIColor.orange
          )

          // Elements.
          for element in line.elements {
            let normalizedRect = CGRect(
              x: element.frame.origin.x / width,
              y: element.frame.origin.y / height,
              width: element.frame.size.width / width,
              height: element.frame.size.height / height
            )
            let convertedRect = self.previewLayer.layerRectConverted(
              fromMetadataOutputRect: normalizedRect
            )
            UIUtilities.addRectangle(
              convertedRect,
              to: self.annotationOverlayView,
              color: UIColor.green
            )
            let label = UILabel(frame: convertedRect)
            label.text = element.text
            label.adjustsFontSizeToFitWidth = true
            self.annotationOverlayView.addSubview(label)
          }
        }
      }
    }
  }

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

  // MARK: - Private

  private func setUpCaptureSessionOutput() {
    sessionQueue.async {
      self.captureSession.beginConfiguration()
      // When performing latency tests to determine ideal capture settings,
      // run the app in 'release' mode to get accurate performance metrics
      self.captureSession.sessionPreset = AVCaptureSession.Preset.medium

      let output = AVCaptureVideoDataOutput()
      output.videoSettings = [
        (kCVPixelBufferPixelFormatTypeKey as String): kCVPixelFormatType_32BGRA,
      ]
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
          previewOverlayView.topAnchor.constraint(equalTo: cameraView.topAnchor)
      ])
  }

    private func setUpAnnotationOverlayView() {
        cameraView.addSubview(annotationOverlayView)
        NSLayoutConstraint.activate([
            annotationOverlayView.topAnchor.constraint(equalTo: cameraView.topAnchor),
            annotationOverlayView.leadingAnchor.constraint(equalTo: cameraView.leadingAnchor),
            annotationOverlayView.trailingAnchor.constraint(equalTo: cameraView.trailingAnchor),
            annotationOverlayView.bottomAnchor.constraint(equalTo: cameraView.bottomAnchor),
        ])
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
                imgv.image =  image3.croppedInRect(rect: fr)
                self.postLocal(brand: "Rolex")
                break
            }
        }
    }
    
    
//    fileprivate func getHeaders() -> [String: String]? {
//
//        /*
//        guard let tokenString = UserDefaults.standard.object(forKey: String.HeaderValues.FCMToken) as? String else {
//            return nil
//        }*/
//
//
//        let headers: [String: String] = [
//            String.HeaderKeys.AcceptEncodingHeader: String.HeaderValues.GzipDeflate,
//            String.HeaderKeys.AcceptHeader: String.HeaderValues.WildCards,
//            String.HeaderKeys.AppKeyHeader:APP_KEY,
//            String.HeaderKeys.AppIdHeader: APP_ID,
//            String.HeaderKeys.AppVersionHeader: String.HeaderValues.AppVersion,
//            String.HeaderKeys.CacheControlHeader: String.HeaderValues.NoCache,
//            String.HeaderKeys.ConnectionHeader: String.HeaderValues.KeepAlive,
//            String.HeaderKeys.ContentTypeHeader: String.HeaderValues.ApplicationJSON,
//            String.HeaderKeys.DeviceOSHeader: String.HeaderValues.iOS,
//            String.HeaderKeys.DeviceOSVersionHeader: String.HeaderValues.DeviceOSVersion,
//            String.HeaderKeys.IsTestApp: "1",
//            String.HeaderKeys.UUIDHeader: UIDevice.current.identifierForVendor!.uuidString,
//        ]
//        return headers
//    }
    
    
    func postLocal(brand: String) {
        activityView = UIActivityIndicatorView(style: .white)
        activityView?.center = self.view.center
        activityView?.startAnimating()
        if activityView != nil {
            self.view.addSubview(activityView!)
            self.view.bringSubviewToFront(activityView!)
        }
        self.activityView?.startAnimating()
        let headers = BoardActive.client.getHeaders()
        print(headers)
        let Url = String(format: "https://dev-api.boardactive.com/mobile/v1/scans")
        ////print(Url)
        let escapedString = Url.addingPercentEncoding(withAllowedCharacters:NSCharacterSet.urlQueryAllowed)
        let serviceUrl = URL(string: escapedString!)
        ////print(serviceUrl)
        var request = URLRequest(url: serviceUrl!)
        request.httpMethod = "POST"
        request.setValue("Application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(headers?["X-BoardActive-App-Key"] ?? "", forHTTPHeaderField: "X-BoardActive-App-Key")
        request.addValue(headers?["X-BoardActive-App-Id"] ?? "", forHTTPHeaderField: "X-BoardActive-App-Id")
        request.addValue(headers?["X-BoardActive-App-Version"] ?? "", forHTTPHeaderField: "X-BoardActive-App-Version")
        request.addValue(headers?["X-BoardActive-Device-Token"] ?? "", forHTTPHeaderField: "X-BoardActive-Device-Token")//*
        request.addValue(headers?["X-BoardActive-Device-OS"] ?? "", forHTTPHeaderField: "X-BoardActive-Device-OS")
        request.addValue(headers?["X-BoardActive-Device-OS-Version"] ?? "", forHTTPHeaderField: "X-BoardActive-Device-OS-Version")
        request.addValue(headers?["X-BoardActive-Is-Test-App"] ?? "", forHTTPHeaderField: "X-BoardActive-Is-Test-App")
        request.addValue("0", forHTTPHeaderField: "X-BoardActive-Latitude")
        request.addValue("0", forHTTPHeaderField: "X-BoardActive-Longitude")

        let finalDict = ["brandName": brand, "deviceTime": ""]
        guard let httpBody = try? JSONSerialization.data(withJSONObject: finalDict, options: []) else {
           return
        }
        print(finalDict)
        request.httpBody = httpBody

        let session = URLSession.shared
        session.dataTask(with: request) { (data, response, error) in
           if response != nil {
               ////print(response)
               
           }
           if let data = data {
               do {
                   let json = try JSONSerialization.jsonObject(with: data, options: []) as! [String : Any]
                   //print(json)
                   print(brand)
                   self.arrOffers = (json["messages"] as! [[String : Any]])
                   print(self.arrOffers)
                   DispatchQueue.main.async {
                       if (self.arrOffers != nil) && self.arrOffers!.count > 0 {
                            self.tblObj.isHidden = false
                           self.tblObj.reloadData()
                       }
                  
                   }
               } catch {
                   ////print(error)
               }
               DispatchQueue.main.async {
               self.activityView?.stopAnimating()
               }
           }
        }.resume()
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

  private func convertedPoints(
    from points: [NSValue]?,
    width: CGFloat,
    height: CGFloat
  ) -> [NSValue]? {
    return points?.map {
      let cgPointValue = $0.cgPointValue
      let normalizedPoint = CGPoint(x: cgPointValue.x / width, y: cgPointValue.y / height)
      let cgPoint = previewLayer.layerPointConverted(fromCaptureDevicePoint: normalizedPoint)
      let value = NSValue(cgPoint: cgPoint)
      return value
    }
  }

  private func normalizedPoint(
    fromVisionPoint point: VisionPoint,
    width: CGFloat,
    height: CGFloat
  ) -> CGPoint {
    let cgPoint = CGPoint(x: point.x, y: point.y)
    var normalizedPoint = CGPoint(x: cgPoint.x / width, y: cgPoint.y / height)
    normalizedPoint = previewLayer.layerPointConverted(fromCaptureDevicePoint: normalizedPoint)
    return normalizedPoint
  }
    
     @IBAction func btnClose(_ sender: Any) {
         tblObj.isHidden = true
         imgv.image = UIImage.init()
         btnClose.isHidden = true
         startSession()
     }
    
    

    @IBAction func objectClick(_ sender: Any) {
    }
    
     @IBAction func textClick(_ sender: Any) {
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
        let imageWidth = CGFloat(CVPixelBufferGetWidth(imageBuffer))
        let imageHeight = CGFloat(CVPixelBufferGetHeight(imageBuffer))
        var shouldEnableClassification = false
        var shouldEnableMultipleObjects = false
        switch currentDetector {
            case .onDeviceObjectCustomProminentWithClassifier, .onDeviceObjectCustomMultipleWithClassifier:
              shouldEnableClassification = true
        }
        
        switch currentDetector {
            case .onDeviceObjectCustomMultipleWithClassifier:
              shouldEnableMultipleObjects = true
            default:
              break
        }

        switch currentDetector {
            case .onDeviceObjectCustomProminentWithClassifier, .onDeviceObjectCustomMultipleWithClassifier:
                guard let localModelFilePath = Bundle.main.path( forResource: Constant.localModelFile.name, ofType: Constant.localModelFile.type)
                else {
                    print("Failed to find custom local model file.")
                    return
                }
                
                let localModel = LocalModel(path: localModelFilePath)
                let options = CustomObjectDetectorOptions(localModel: localModel)
                options.shouldEnableClassification = shouldEnableClassification
                options.shouldEnableMultipleObjects = shouldEnableMultipleObjects
                options.detectorMode = .stream
                detectObjectsOnDevice(in: visionImage, width: imageWidth, height: imageHeight, options: options)
        }
    }
}

// MARK: - Constants

public enum Detector: String {
    case onDeviceObjectCustomProminentWithClassifier = "ODT, custom, single, labeling"
    case onDeviceObjectCustomMultipleWithClassifier = "ODT, custom, multiple, labeling"
}

private enum Constant {
    static let alertControllerTitle = "Vision Detectors"
    static let alertControllerMessage = "Select a detector"
    static let cancelActionTitleText = "Cancel"
    static let videoDataOutputQueueLabel = "com.google.mlkit.visiondetector.VideoDataOutputQueue"
    static let sessionQueueLabel = "com.google.mlkit.visiondetector.SessionQueue"
    static let noResultsMessage = "No Results"
    static let localModelFile = (name: "bird", type: "tflite")
    static let labelConfidenceThreshold: Float = 0.75
    static let smallDotRadius: CGFloat = 4.0
    static let originalScale: CGFloat = 1.0
    static let padding: CGFloat = 10.0
    static let resultsLabelHeight: CGFloat = 200.0
    static let resultsLabelLines = 5
}


extension UIImage {
    func croppedInRect(rect: CGRect) -> UIImage {
        
        ////print(rect)
        func rad(_ degree: Double) -> CGFloat {
            return CGFloat(degree / 180.0 * .pi)
        }
        
        var rectTransform: CGAffineTransform

        switch imageOrientation {
        case .left:
            //print("left")
            rectTransform = CGAffineTransform(rotationAngle: rad(90)).translatedBy(x: 0, y: -self.size.height)
        case .right:
            //print("right")
            rectTransform = CGAffineTransform(rotationAngle: rad(-90)).translatedBy(x: -self.size.width, y: 0)
        case .down:
            //print("down")
            rectTransform = CGAffineTransform(rotationAngle: rad(-180)).translatedBy(x: -self.size.width, y: -self.size.height)
        default:
            //print("default")
            rectTransform = .identity
        }
        let imageRef = self.cgImage!.cropping(to: rect.applying(rectTransform))
        let result = UIImage(cgImage: imageRef!, scale: 1.0, orientation: self.imageOrientation)
        
        return result
    }
}


public extension String {
    enum HeaderKeys {
        static let AccessControlHeader = "Access-Control-Allow-Origin"
        static let AppIdHeader = "X-BoardActive-App-Id"
        static let AppKeyHeader = "X-BoardActive-App-Key"
        static let AppVersionHeader = "X-BoardActive-App-Version"
        static let DeviceOSHeader = "X-BoardActive-Device-OS"
        static let DeviceOSVersionHeader = "X-BoardActive-Device-OS-Version"
        static let DeviceTokenHeader = "X-BoardActive-Device-Token"
        static let DeviceTypeHeader = "X-BoardActive-Device-Type"
        static let IsTestApp = "X-BoardActive-Is-Test-App"
        static let UUIDHeader = "X-BoardActive-Device-UUID"
        static let ContentTypeHeader = "Content-Type"
        static let AcceptHeader = "Accept"
        static let CacheControlHeader = "Cache-Control"
        static let HostHeader = "Host"
        static let AcceptEncodingHeader = "accept-encoding"
        static let ConnectionHeader = "Connection"
    }

    enum HeaderValues {
        static let WildCards = "*/*"
        static let AppVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
        static let NoCache = "no-cache"
        static let ApplicationJSON = "application/json"
        static let GzipDeflate = "gzip, deflate"
        static let KeepAlive = "keep-alive"
        static let DevHostKey = "springer-api.boardactive.com"
        static let ProdHostKey = "api.boardactive.com"
        static let iOS = "iOS"
        static let DeviceOSVersion = UIDevice.current.systemVersion
        static let UUID = UIDevice.current.identifierForVendor!.uuidString
        static let FCMToken = "deviceToken"
    }
}

extension CameraViewController: UITableViewDelegate, UITableViewDataSource  {
    
    public func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.arrOffers?.count ?? 0
    }
    
    public func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 100
    }
    
    public func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return "   \(self.arrOffers?.count ?? 0) matche(s) found"
    }
    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    var cell = tableView.dequeueReusableCell(withIdentifier: "CELL")
    if cell == nil {
        cell = UITableViewCell(style: UITableViewCell.CellStyle.value1,
                               reuseIdentifier: "CELL")
    }
        
        let dict = (self.arrOffers?[indexPath.row]["notification"] as! [String: Any])
        let img = cell?.viewWithTag(1) as! UIImageView
        let lblTitle = cell?.viewWithTag(2) as! UILabel
        let lblSubTitle = cell?.viewWithTag(3) as! UILabel
        
        let url = URL(string: (dict["imageUrl"] as? String) ?? "")
        if url != nil {
        let data = try? Data(contentsOf: url!)
        img.image = UIImage(data: data!)
        }
        img.contentMode = .scaleAspectFit
        lblTitle.text = self.arrOffers?[indexPath.row]["name"] as? String
        lblSubTitle.text = (self.arrOffers?[indexPath.row]["notification"] as! [String: Any])["contents"] as? String
        return cell!
    }
    
    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
        
          print(self.arrOffers?[indexPath.row])
        
       
        
         let str =  (self.arrOffers?[indexPath.row]["notification"] as! [String: Any])["messageData"] as! String
        
        let dict = convertStringToDictionary(text: str)
        
        let storyboardBundle = Bundle(for: CameraViewController.self)
               let storyboard = UIStoryboard(name: "Main_Framework", bundle: storyboardBundle)
               let vc = storyboard.instantiateViewController(withIdentifier: "DetailsViewController") as! DetailsViewController
               vc.modalPresentationStyle = .fullScreen
        vc.dictDetails = dict
        let dict2 = (self.arrOffers?[indexPath.row]["notification"] as! [String: Any])
        
        vc.strName = self.arrOffers?[indexPath.row]["name"] as? String
        vc.strMessage =    dict2["contents"] as? String
        
        
     
        
        
        
               vc.strURL = (dict2["imageUrl"] as? String)
               self.present(vc, animated: true)
        
        
        print(dict)
    }
    
     func convertStringToDictionary(text: String) -> [String:AnyObject]? {
        if let data = text.data(using: .utf8) {
            do {
                let json = try JSONSerialization.jsonObject(with: data, options: .mutableContainers) as? [String:AnyObject]
                return json
            } catch {
                print("Something went wrong")
            }
        }
        return nil
    }
}
