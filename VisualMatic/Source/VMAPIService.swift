//
//  VMAPIService.swift
//  VisualMatic
//
//  Created by Indrajeet Senger on 06/05/21.
//

import Foundation

public class VMAPIService {
    
    public static let sharedVMAPIService = VMAPIService()
    private var APP_ID = ""
    private var APP_KEY = ""
    
    private init(){
        
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
                completionHandler(nil, nil)
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
    
}
