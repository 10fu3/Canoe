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
    
    
    //waterserver/get/<requestid> -> (Index,Link,FileName)
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
        url:String,//アップローダーのURL
        onFinished:@escaping (Data)->Void,//ダウンロード完了後に呼び出されるクロージャ
        onError:@escaping (Error)->Void) {//失敗したときに呼び出されるクロージャ
        //print(url)
        if(url == "NOURL"){
            return
        }
        AF.request(url)
            .responseData(completionHandler: { response in
            switch response.result{
            case .success(let data):
                onFinished(data)//うまくダウンロードできれば、クロージャにダウンロードしたデータを渡す
            case .failure(let error):
                onError(error)
            }
        })
    }
    
    //分割サーバーに向けて送信するリクエスト
    static func sendDLReq(
        targetUrl:String,//コンテンツをおいてるURL
        separateServerIP:String,//分割サーバーのURL
        onSuccess:@escaping ((String)->Void),//成功時に呼び出されるクロージャ
         onErr:@escaping ((String)->Void)) {//失敗したときに呼び出されるクロージャ
        
        //ヘッダの設定
        let headers: HTTPHeaders = [
            "Contenttype": "application/json"
        ]
        
        //分割サーバーにわたすPOSTパラメータ コンテンツをおいてるURLをパラメータに入れる
        let parameters:[String: Any] = [
            "url": targetUrl
        ]
        
        //AlamofireのPOSTメソッドを使って分割サーバーにパラメータを送信
        AF.request(
            separateServerIP,
            method: .post,
            parameters: parameters,
            encoding: JSONEncoding.default,
            headers: headers)
            .responseString(completionHandler: { data in
            switch data.result{
                case .success(let result):
                    onSuccess(result)//うまくいくと呼び出される
                    break
                case .failure(let err):
                    onErr(err.localizedDescription)
                    break
            }
        })
    }
    
    //分割サーバーの作業完了リストに、自身が発行したリクエストが完了したか、監視しに行くメソッド
    static func checkID(
        serverURL:String,//分割サーバーのURL
        targetID:String,//分割サーバーにリクエストを発行したときに、応答されるリクエストID
        onFound:@escaping (()->Void)){//作業完了リストにリクエストIDを発見したときに呼び出されるクロージャ
        
        // Alamofireで分割サーバーの作業監視リストを確認しにいく
        AF.request(serverURL+"/ended", parameters: nil)
            .responseString(completionHandler: { data in
                switch data.result{
                case .success(let line):
                    if(line.contains(targetID)){
                        onFound()//リクエストIDが見つかったときに呼び出される
                    }
                case .failure(_):
                    break
                }
        })
    }
    
    //分割サーバーに掲載される分割されたファイルがどこのURL(アップローダーのURL)にあるのか というリストを確認し取得
    static func getListOfDownloadLink(
        serverURL:String,targetID:String,
        onMoveLine:@escaping ((String,[String])->Void)){
        
        //１秒おきに確認しにいく
        Timer.scheduledTimer(withTimeInterval: 1.0,
                             repeats: true, block: { timer in
            //Alamofireを使ってリストにアクセスする
            AF.request(serverURL+"/get/"+targetID, parameters: nil)
                .responseString(completionHandler: { data in
                    switch data.result{
                    case .success(let line):
                        if(line.count > 0){
                            timer.invalidate()
                            //リストデータをHTMLの改行コードで分割して、１行ごとにonMoveLineにリストを渡していく
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
