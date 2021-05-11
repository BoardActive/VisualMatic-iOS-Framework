//
//  VMExtensions.swift
//  VisualMatic
//
//  Created by Indrajeet Senger on 06/05/21.
//

import Foundation
import CoreGraphics

extension String {
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
        static let DeviceType = UIDevice.modelName
    }
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
    
    public func scaledImage(with size: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        defer { UIGraphicsEndImageContext() }
        draw(in: CGRect(origin: .zero, size: size))
        return UIGraphicsGetImageFromCurrentImageContext()?.data.flatMap(UIImage.init)
    }
    
    private var data: Data? {
        return self.pngData() ?? self.jpegData(compressionQuality: 0.8)
    }
}

