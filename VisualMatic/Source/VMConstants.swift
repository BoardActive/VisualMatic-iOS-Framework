//
//  VMConstants.swift
//  VisualMatic
//
//  Created by Indrajeet Senger on 06/05/21.
//

import Foundation


enum Constants {
    static let circleViewAlpha: CGFloat = 0.7
    static let rectangleViewAlpha: CGFloat = 0.3
    static let shapeViewAlpha: CGFloat = 0.3
    static let rectangleViewCornerRadius: CGFloat = 10.0
    static let originalScale: CGFloat = 1.0
}

enum APIEndPoints {
    static let BaseURL = "https://dev-api.boardactive.com/mobile/v1"
    static let Scans = "/scans"
}

public enum Detector: String {
    case onDeviceObjectCustomProminentWithClassifier = "ODT, custom, single, labeling"
    case onDeviceObjectCustomMultipleWithClassifier = "ODT, custom, multiple, labeling"
}

enum Constant {
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

public enum ScannerType: Int {
    case CustomObject = 101
    case TextRecognizer = 102
    case DigitalInkRecognizer = 103
    case BarcodeScanner = 104
}
