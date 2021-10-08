//
//  VMConstants.swift
//  VisualMatic
//
//  Created by Indrajeet Senger on 06/05/21.
//

import Foundation
import BAKit

/**
 Constant values used through the sdk.
 */
enum Constants {
    static let circleViewAlpha: CGFloat = 0.7
    static let rectangleViewAlpha: CGFloat = 0.3
    static let shapeViewAlpha: CGFloat = 0.3
    static let rectangleViewCornerRadius: CGFloat = 10.0
    static let originalScale: CGFloat = 1.0
}

/**
 Development and production base urls with their associated end points.
 */
enum APIEndPoints {
    static let BaseURL = BoardActive.client.isDevEnv ? "https://dev-api.boardactive.com/mobile/v1" : "https://api.boardactive.com/mobile/v1"
    static let Scans = "/scans"
    static let Models = "/models"
}

enum Constant {
    static let videoDataOutputQueueLabel = "com.boardactive.visualmatic.visiondetector.VideoDataOutputQueue"
    static let sessionQueueLabel = "com.boardactive.visualmatic.visiondetector.SessionQueue"
    static let localModelFile = (name: "bird", type: "tflite")
    static let labelConfidenceThreshold: Float = 0.75
    static let smallDotRadius: CGFloat = 4.0
    static let originalScale: CGFloat = 1.0
    static let padding: CGFloat = 10.0
    static let resultsLabelHeight: CGFloat = 200.0
    static let resultsLabelLines = 5
}

enum UserdefaultKey {
    static let modelUpdateDate = "modelUdateDate"
}

/**
Types of scanner supported by the SDK
*/
public enum ScannerType: Int {
    case CustomObject = 101
    case TextRecognizer = 102
    case BarcodeScanner = 104
}

