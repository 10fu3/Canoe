//
//  HttpBridge.swift
//  Router
//
//  Created by Kengo Wada on 2019/08/05.
//  Copyright © 2019 Kengo Wada. All rights reserved.
//

import Foundation
import Alamofire
import UIKit

class Util {
    static func searchKey(dic:[String:String],doIt:((String)->Bool)) -> [String] {
        return dic.filter({doIt($0.value)}).map{$0.key}
    }
    
    
    //waterserver/get/<requestid> -> Index,Link,FileName
    static func parseLine(line:String) -> (Int,String,String)? {
        let sepaleted = line.components(separatedBy: "§")
        if(sepaleted.count == 3){
            return (Int.init(sepaleted[0]) ?? 0,sepaleted[1],sepaleted[2])
        }else{
            return nil
        }
    }
    
//    //Data ↔ 値 を変換するメソッド
//    //https://codeday.me/jp/qa/20190312/400107.html 参照
//    static func toByteArray<T>(_ value: T) -> Data {
//        var value = value
//        var array = Data.init()
//        withUnsafeBytes(of: &value) { Array($0) }.forEach{array.append($0)}
//        return array
//    }
//
//    //Data ↔ 値 を変換するメソッド
//    //https://codeday.me/jp/qa/20190312/400107.html 参照
//    static func fromByteArray<T>(_ value: Data, _: T.Type) -> T {
//        return value.map{$0}.withUnsafeBytes {
//            $0.baseAddress!.load(as: T.self)
//        }
//    }
}

class Http{
    
    //データのダウンロード
    static func downloadData(
        url:String,
        onFinished:@escaping (Data)->Void,
        onError:@escaping (Error)->Void) {
        print(url)
        AF.request(url)
            .responseData(completionHandler: { response in
            switch response.result{
            case .success(let data):
                onFinished(data)
            case .failure(let error):
                onError(error)
            }
        })
    }
    
    //分割サーバーに向けて送信するリクエスト
    static func sendDLReq(
        targetUrl:String,
        separateServerIP:String,
        onSuccess:@escaping ((String)->Void),
         onErr:@escaping ((String)->Void)) {
        
        let headers: HTTPHeaders = [
            "Contenttype": "application/json"
        ]
        
        let parameters:[String: Any] = [
            "url": targetUrl
        ]
        
        AF.request(
            separateServerIP,
            method: .post,
            parameters: parameters,
            encoding: JSONEncoding.default,
            headers: headers)
            .responseString(completionHandler: { data in
            switch data.result{
                case .success(let result):
                    onSuccess(result)
                    break
                case .failure(let err):
                    onErr(err.localizedDescription)
                    break
            }
        })
    }
    
    static func checkID(
        serverURL:String,targetID:String
        ,onFound:@escaping (()->Void)){
        
        // When
        AF.request(serverURL+"/ended", parameters: nil)
            .responseString(completionHandler: { data in
                switch data.result{
                case .success(let line):
                    if(line.contains(targetID)){
                        onFound()
                    }
                case .failure(_):
                    break
                }
        })
    }
    
    static func getListOfDownloadLink(
        serverURL:String,targetID:String,
        onMoveLine:@escaping ((String,[String])->Void)){
        
        Timer.scheduledTimer(withTimeInterval: 1.0,
                             repeats: true, block: { timer in
            AF.request(serverURL+"/get/"+targetID, parameters: nil)
                .responseString(completionHandler: { data in
                    switch data.result{
                    case .success(let line):
                        if(line.count > 0){
                            timer.invalidate()
                            let urls = line.components(separatedBy: "<br>")
                            urls.forEach{
                                onMoveLine($0,urls)
                            }
                        }
                    case .failure(_):
                        break
                    }
                }
            )
        })
    }
}
