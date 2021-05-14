//
//  VMAPIService.swift
//  VisualMatic
//
//  Created by Indrajeet Senger on 06/05/21.
//

import Foundation

@objc public protocol VMAPIServiceDelegate {
    @objc optional func downloadProgress(downloadPercent: Int64)
    @objc optional func downloadCompleted()
    @objc optional func downloadError(error: Error)
}

public class VMAPIService: NSObject {
    
    public static let sharedVMAPIService = VMAPIService()
    public var delegate: VMAPIServiceDelegate?
    public var modelPath: String?
    
    private var APP_ID = ""
    private var APP_KEY = ""
    private var fileName = ""
    
    private override init(){
        
    }

    public func setupVisualMatic(appId id: String, appkey key: String){
        APP_ID = id
        APP_KEY = key
    }
    
    func getHeaders() -> [String: String]? {
    
        let headers: [String: String] = [
            String.HeaderKeys.AcceptEncodingHeader: String.HeaderValues.GzipDeflate,
            String.HeaderKeys.AcceptHeader: String.HeaderValues.WildCards,
            String.HeaderKeys.AppKeyHeader: APP_KEY,
            String.HeaderKeys.AppIdHeader: APP_ID,
            String.HeaderKeys.AppVersionHeader: String.HeaderValues.AppVersion,
            String.HeaderKeys.CacheControlHeader: String.HeaderValues.NoCache,
            String.HeaderKeys.ConnectionHeader: String.HeaderValues.KeepAlive,
            String.HeaderKeys.ContentTypeHeader: String.HeaderValues.ApplicationJSON,
            String.HeaderKeys.DeviceOSHeader: String.HeaderValues.iOS,
            String.HeaderKeys.DeviceOSVersionHeader: String.HeaderValues.DeviceOSVersion,
            String.HeaderKeys.DeviceTokenHeader: "abc",
            String.HeaderKeys.DeviceTypeHeader: String.HeaderValues.DeviceType,
            String.HeaderKeys.IsTestApp: "0",
            String.HeaderKeys.UUIDHeader: UIDevice.current.identifierForVendor!.uuidString,
        ]
        return headers
    }
    
    func sendScanResult(body parameters: [String: String], completionHandler: @escaping ([String: Any]?, Error?) -> Void){
        let UrlString = APIEndPoints.BaseURL + APIEndPoints.Scans
        guard let escapedString = UrlString.addingPercentEncoding(withAllowedCharacters:NSCharacterSet.urlQueryAllowed) else {
            completionHandler(nil, nil)
            return
        }
        let serviceUrl = URL(string: escapedString)
        var request = URLRequest(url: serviceUrl!)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = getHeaders()
        guard let httpBody = try? JSONSerialization.data(withJSONObject: parameters, options: []) else {
            completionHandler(nil, nil)
            return
        }
        request.httpBody = httpBody
        let session = URLSession.shared
        session.dataTask(with: request) { (data, response, error) in
            if (error != nil) {
                let error = NSError(domain: "", code: 401, userInfo: ["errorMessage": error?.localizedDescription as Any])
                completionHandler(nil, error)
            }
            
            if let data = data {
                do {
                    let json = try JSONSerialization.jsonObject(with: data, options: []) as! [String : Any]
                    completionHandler(json, nil)
                } catch {
                    completionHandler(nil, nil)
               }
            }
        }.resume()
    }
    
    public func loadMLModel() {
        let urlString = APIEndPoints.BaseURL + APIEndPoints.Models
        guard let escapedString = urlString.addingPercentEncoding(withAllowedCharacters:NSCharacterSet.urlQueryAllowed) else {
            let error = NSError(domain: "", code: 401, userInfo: ["errorMessage": "API url is invalid."])
            delegate?.downloadError?(error: error)
            return
        }
        if let serviceUrl = URL(string: escapedString) {
            var request = URLRequest(url: serviceUrl)
            request.httpMethod = "GET"
            request.allHTTPHeaderFields = getHeaders()
            URLSession.shared.dataTask(with: request) { [self] (data, response, error) in
                if (error != nil) {
                    let error = NSError(domain: "", code: 1000, userInfo: ["errorMessage": error?.localizedDescription as Any])
                    self.delegate?.downloadError?(error: error)
                }
                
                if let responseData = data {
                    do {
                        let jsonData = try JSONSerialization.jsonObject(with: responseData, options: []) as! [String: Any]
                        if let downloadURL = jsonData["url"] as? String {
                            self.startDownload(url: downloadURL)
                        } else {
                            let error = NSError(domain: "", code: 1000, userInfo: ["errorMessage": "Download url is not exist."])
                            self.delegate?.downloadError?(error: error)
                        }
                    } catch {
                        let error = NSError(domain: "", code: 1000, userInfo: ["errorMessage": "Response data is not in proper format."])
                        self.delegate?.downloadError?(error: error)
                    }
                }
            }.resume()
        }
    }
    
    private func startDownload(url: String) {
        if let downloadURL = URL(string: url) {
            fileName = downloadURL.lastPathComponent
            if (!isModelExist()) {
                let configuration = URLSessionConfiguration.default
                let operationQueue = OperationQueue()
                let session = URLSession(configuration: configuration, delegate: self, delegateQueue: operationQueue)
                let downloadTask = session.downloadTask(with: URL(string: url)!)
                downloadTask.resume()
            }
        } else {
            let error = NSError(domain: "", code: 1000, userInfo: ["errorMessage": "Download url is not a valid url."])
            delegate?.downloadError?(error: error)
        }
    }
    
    private func isModelExist() -> Bool {
        let appPaths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let documentDirPath = appPaths[0]
        let filePath = documentDirPath.appendingPathComponent(fileName)
        print(filePath)

        if (!FileManager.default.fileExists(atPath: filePath.path)) {
            modelPath = nil
            return false
        } else {
            modelPath = filePath.path
            delegate?.downloadCompleted?()
            return true
        }

    }
}

extension VMAPIService: URLSessionDownloadDelegate {
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        print(fileName)
        
        let appPaths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let documentDirPath = appPaths[0]
        let filePath = documentDirPath.appendingPathComponent(fileName)
        print(filePath)
        
        do {
            try FileManager.default.copyItem(at: location, to: filePath)
            modelPath = filePath.path
            self.delegate?.downloadCompleted?()
            
        } catch {
            let error = NSError(domain: "", code: 1000, userInfo: ["errorMessage": "Downloaded file cannot be copied into document directory."])
            delegate?.downloadError?(error: error)
            print("file could not be copied")
        }
    }
    
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let percentDownloaded = (totalBytesWritten * 100) / totalBytesExpectedToWrite
        DispatchQueue.main.async {
            self.delegate?.downloadProgress!(downloadPercent: percentDownloaded)
        }
    }
}
