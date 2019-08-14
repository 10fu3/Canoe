//
//  ViewController.swift
//  Router
//
//  Created by Kengo Wada on 2019/07/24.
//  Copyright © 2019 Kengo Wada. All rights reserved.
//

import UIKit
import Alamofire

class ViewController: UIViewController {

    static var Single :ViewController? = nil
    
    @IBOutlet weak var id: UILabel!
    
    @IBOutlet weak var log: UITextView!
    
    @IBOutlet weak var urlbox: UITextField!
    
    @IBOutlet weak var run: UIButton!
    
    @IBOutlet weak var serverIp: UITextField!
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if (self.urlbox.isFirstResponder) {
            self.urlbox.resignFirstResponder()
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        ViewController.Single = self
        self.id.adjustsFontSizeToFitWidth = true
        self.id.text = P2PConnectivity.manager.id
        self.serverIp.text = "https://waterserver1.herokuapp.com"
        P2PConnectivity.manager.start(
            serviceType: "canoe",
            stateChangeHandler:
            { (state,id) in
                
                if( state == .notConnected){
                    DispatchQueue.main.async {
                        self.log.text.append(
                            contentsOf: "\n"+(id?.displayName ?? "")+"との接続が解除されました")
                    }
                }
                if( state == .connected){
                    DispatchQueue.main.async {
                        self.log.text.append(
                            contentsOf: "\n"+(id?.displayName ?? "")+"と接続されました")
                    }
                }
            },
            recieveHandler:
            { mes in
                switch mes.getMessageType(){
                    
                case .DownloadRequest:
                    TaskUtil.onReciveDLRequest(mes: mes)
                    break
                case .ExportData:
                    TaskUtil.onReciveDLPart(mes: mes)
                    break
                case .Completed:
                    TaskUtil.onReciveFinishedPacket(mes: mes)
                    break
                case .ReplyYes:
                    break
                case .ReplyNo:
                    break
                case .ConvertError:
                    break
                @unknown default:
                    break
                }
            })
        // Do any additional setup after loading the view.
    }
    
    func putLog(string:String) {
        DispatchQueue.main.async {
            self.log.text.append("\n"+string)
            self.log.selectedRange = NSRange(location: self.log.text.count, length: 0)
            self.log.isScrollEnabled = true
            
            let scrollY = self.log.contentSize.height - self.log.bounds.height
            let scrollPoint = CGPoint(x: 0, y: scrollY > 0 ? scrollY : 0)
            self.log.setContentOffset(scrollPoint, animated: true)
        }
    }

    @IBAction func onRun(_ sender: Any) {
        
//        do{
//            let mes = Message.builder()
//                .setType(type: .DownloadRequest)
//                .setNowPutOutDate()
//                .setToAddressAll()
//                .setFromAddress(address: P2PConnectivity.manager.id)
//                .setBody(body: try! DownloadRequestData.init().setID(id: UUID.init().uuidString).setBody(body: "{\"a\":\"b\"}").toData())
//
//            P2PConnectivity.manager.send(message: mes.toData() ?? Data())
//        }catch{
//            print(error)
//        }
//
//        return
        
        if(P2PConnectivity.manager.connectedPair.count == 1){
            self.log.text.append(contentsOf:
                "\nペアが自分以外見つかりません 2台以上接続後、利用可能になります")
            return
        }else if(P2PConnectivity.manager.connectedPair.count == 2){
            self.log.text.append(contentsOf:"\nペアは2台以上を推奨します")
        }
        
        if (self.serverIp.text?.count ?? 0 > 0) && (self.urlbox.text?.count ?? 0 > 0){
            let checkURLServerIP = URL(string: self.serverIp.text ?? "")
            let checkURLTargetIP = URL(string: self.urlbox.text ?? "")
            
            if(checkURLServerIP == nil){
                //分割サーバーへのアドレスが無効なものだったとき
                self.log.text.append(contentsOf:"\n"+"移譲先IPアドレスが無効です")
                return
            }else if(checkURLTargetIP == nil){
                //ダウンロード対象のアドレスが無効なものだったとき
                self.log.text.append(contentsOf:"\n"+"ダウンロードする対象のURL")
                return
            }
            
            let target = self.urlbox.text!
            let serverIp = self.serverIp.text!
            
            Http.sendDLReq(targetUrl: target , separateServerIP: serverIp+"/request",
                onSuccess: { data in
                    
                    self.log.text.append(contentsOf:"\n"+data)
                    
                    //3秒おきに分割リストを確認しにいく
                    var checkTimer:Timer? = nil
                    checkTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval.init(3),
                    repeats: true, block: { timer in
                        print("onTimer")
                        DispatchQueue.global().async {
                            Http.checkID(
                                serverURL: serverIp , targetID: data, onFound: {
                                print("onFound")
                                var flag = false
                                checkTimer?.invalidate()
                                checkTimer = nil
                                
                                Http.getListOfDownloadLink(
                                    serverURL: serverIp, targetID: data,
                                    onMoveLine:{ (line,urls) in
                                    if(flag == true){
                                        return
                                    }else{
                                        flag = true
                                        print(urls)
                                        TaskUtil.onRegistryTaskEntity(id: data, maxIndex: urls.count, filename: Util.parseLine(line: line)?.2 ?? "")
                                        MinistryOfP2P.sendDLRequest(id: data, urls: urls)
                                        
                                    }
                                })
                            })
                        }
                    })
                                
            },
            onErr:{ errMes in
                self.log.text.append(contentsOf:"\n"+"エラー "+errMes)
            })
        }
    }
    
}

