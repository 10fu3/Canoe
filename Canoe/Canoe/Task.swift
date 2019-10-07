//
//  Task.swift
//  Router
//
//  Created by Kengo Wada on 2019/08/11.
//  Copyright © 2019 10fu3. All rights reserved.
//

import Foundation

class TaskEntity {
    //ダウンロード中のコンテンツを管理するためのメソッド
    
    //ファイルをいくつ切断したものを用意するのか
    var maxIndex = 0
    //ファイル分割サーバーから送信されてくる管理用ID
    var id = ""
    //ダウンロードするファイルの名前
    var filename = ""
    //ファイルの断片を管理するための配列
    var partOfData = [Data]()
    
    func isFinished() -> Bool {
        return partOfData.count == maxIndex
    }
    //バラバラのデータを接合して一つのバイト配列にする
    func joinData() -> Data {
        var value = Data()
        partOfData.forEach{value.append($0)}
        return value
    }
    
    //newと一緒
    static func create() -> TaskEntity {
        return TaskEntity()
    }
    
    //ファイルをいくつ切断したものを用意するのか
    func setMaxIndex(index:Int) -> TaskEntity {
        self.maxIndex = index
        partOfData = [Data](repeating: Data(), count: index)
        return self
    }
    
    //ファイル分割サーバーから送信されてくる管理用ID
    func setID(id:String) -> TaskEntity {
        self.id = id
        return self
    }
    
    //ダウンロードするファイルの名前
    func setFileName(name:String) -> TaskEntity {
        self.filename = name
        return self
    }
}

class Task {
    //ダウンロードと分割されたデータの接合といった処理中のリストを扱う管理用のクラス
    static let single = Task()
    
    //tasksのkeyとTaskEntity.id は同一
    var tasks = [String:TaskEntity]()
    
    func add(id:String,entity:TaskEntity){
        //entity.id = id
        if !has(id: id){
            tasks[id] = entity
            print("registry :"+id)
        }
    }
    
    func addData(id:String,index:Int,data:Data) {
        if(self.tasks[id] != nil){
            self.tasks[id]!.partOfData[index] = data
        }
        let count = self.tasks[id]!.partOfData.filter{$0.count > 0}.count
        ViewController.Single?.putLog(string:"最大:"+String.init(self.tasks[id]!.maxIndex))
        ViewController.Single?.putLog(string:"現在:"+String.init(count))
        ViewController.Single?.putLog(string:"残り"+String.init(self.tasks[id]!.maxIndex - self.tasks[id]!.partOfData.filter{$0.count > 0}.count)+"ダウンロード必要")
        
//        Timer.scheduledTimer(withTimeInterval: 15, repeats: false, block: { timer in
//            var task :((Int)->Void) = {old in}
//            task = { old in
//                Timer.scheduledTimer(withTimeInterval: 15, repeats: false, block: { timer1 in
//                    if(old == self.tasks[id]!.partOfData.filter{$0.count > 0}.count){
//
//
//
//                        task(self.tasks[id]!.partOfData.filter{$0.count > 0}.count)
//                    }
//                })
//            }
//
//            if(count == self.tasks[id]!.partOfData.filter{$0.count > 0}.count){
//
//            }
//        })
//
        //分割数と分割されたデータをいくつ受信したのかという数が一致すれば、完了処理へ
        if(self.tasks[id] != nil &&
            self.tasks[id]!.maxIndex == self.tasks[id]!.partOfData.filter{$0.count > 0}.count){
            outPutFileOnDocument(data: self.tasks[id]!.joinData(), fileName: self.tasks[id]!.filename)
            let name = String.init(self.tasks[id]!.filename)
            self.tasks[id] = nil
            ViewController.Single?.putLog(string: "ファイル名: "+name+"のダウンロードが完了しました")
            
            do{
                //周りの端末に反復送信をやめるようにパケットを送信
                let compMesData = Packet.builder()
                    .setType(type: .Completed)
                    .setNowPutOutDate()
                    .setToAddressAll()
                    .setFromAddress(address: P2PConnectivity.manager.id)
                    .setBody(body: try! DownloadCompletePacket().setID(id: id).toData()).toData() ?? Data()
                
                var counter = 1
                
                //まれに送信しても受信されないことがあるので5回繰り返し送る
                Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true, block: { timer in
                    if counter > 5{
                        timer.invalidate()
                        return
                    }
                    counter += 1
                    //ここで送信
                    P2PConnectivity.manager.send(message: compMesData)
                })
            
            //エラーがおきないので握りつぶす
            }catch{
                print("")
            }
        }
    }
    
    func has(id:String) -> Bool {
        return tasks[id] != nil
    }
    
    func finishedList() -> [String:TaskEntity] {
        return tasks.filter{$0.value.isFinished()}
    }
    
    func outPutFileOnDocument(data:Data,fileName:String) {
        let documentPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].absoluteString
        do{
            try data.write(to: URL.init(fileURLWithPath: documentPath).appendingPathComponent(fileName, isDirectory: false))
        }catch{
            ViewController.Single?.putLog(string: error.localizedDescription)
        }
    }
}

class TaskUtil {
    //処理の寄せ集め
    //IDを登録する
    //すでにダウンロードリクエストが受理済みの場合、反復送信のせいで２重３重にダウンロードしてしまう可能性があるので、パケットに含まれるパケットのUUIDにて区別し、受理済み(リストに入ってる)の場合、無視するように処理を書く
    static var waitingQueue = [String]()
    
    //ダウンロードリクエスト発行者である自分自身もファイルの断片をダウンロードする
    static func selfDownloadTask(id:String,list:[String:String]) {
        DispatchQueue.global().async {
            //index url name
            let taples = list.filter{$0.value == P2PConnectivity.manager.id}
                .map{Util.parseLine(line: $0.key)}
            taples.forEach{ taple in
                Http.downloadData(url: taple?.1 ?? "", onFinished: { data in
                    if(Task.single.has(id: id)){
                        Task.single.addData(id: id, index: taple?.0 ?? -1, data: data)
                    }
                }, onError: {
                    print($0)
                })
            }
        }
    }
    
    //ダウンロードを要請するパケットを受信したとき
    static func onReciveDLRequest(mes:Packet) {
        do{
            let req = try! DownloadRequestPacket.parseDownloadRequestData(body: mes.getBody())
            //すでに受理済みの場合は無視する
            if(TaskUtil.waitingQueue.contains(req.requestID)){
                return
            }
            print("RequestID: "+req.requestID+"のダウンロードリクエストを受理しました")
            //リクエストを受理したリストについかして重複リクエストを弾くようにする
            TaskUtil.waitingQueue.append(req.requestID)
//            print(req.body)
//            print("recivedID: "+req.requestID)
            //リクエストを１度JSON化
            let json = try JSONSerialization.jsonObject(with: req.body.data(using: .utf8) ?? Data(), options: []) as? [String: String] ?? [:]
            ViewController.Single?.putLog(string: req.body)
            
            //自分の端末が担当するファイル（の断片）のダウンロードの開始
            Util.searchKey(dic: json, doIt: {$0 == P2PConnectivity.manager.id}).forEach{ part in
                //もしこの端末IDに割り当てられたリストがない場合
                if(part == "NOURL"){
                    return
                }
                //分割されたファイルのうち、何番目のどこのアップローダーに、なんていう名前なのかという情報を分離し、タプルに格納
                let dataPlate = Util.parseLine(line: part)
                //ここでリンクを取得
                let link = dataPlate?.1
                //ダウンロード開始
                Http.downloadData(url: link ?? "", onFinished: { dlData in
                    //ダウンロードしたデータを送信用のパケットに詰める
                    let dlBody = ExportData.init().setIndex(index: dataPlate?.0 ?? -1).setBody(body: dlData).setID(id: req.requestID)
                    ViewController.Single?.putLog(string: link ?? ""+"のダウンロードを行いました")

                    do{
                        //なぜか送信しても、無線環境のせいで受信されないことがある
                        //なので繰り返し送信して、2,3回目に受信してもらえるように複数回、時間をおいて送信する
                        let task = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true, block: { timer in
                            
                            //ダウンロードパケットを、さらに通常規格のパケットに詰める
                            let dlPack = Packet
                            .builder()
                            .setType(type: .ExportData)
                            .setNowPutOutDate()
                            .setFromAddress(address: P2PConnectivity.manager.id)
                            .setToAddress(address: mes.getFromAddress())
                            .setBody(body: try! dlBody.toData())
                            //送信
                            P2PConnectivity.manager.send(message: dlPack.toData() ?? Data())
                        })
                        
                        //反復送信する対象リスト(正確には辞書)に処理を詰め込む
                        MinistryOfP2P.Single.roopData[req.requestID] = []
                        MinistryOfP2P.Single.roopData[req.requestID]?.append(task)
                        
                    }catch{
                        ViewController.Single?.putLog(string: error.localizedDescription)
                    }

                }, onError: {
                    ViewController.Single?.putLog(string: $0.localizedDescription)
                })
            }
            
        }catch{
            ViewController.Single?.putLog(string: error.localizedDescription)
        }
    }
    
    //ダウンロードする前にダウンロードを管理するクラスを待機リストに追加する
    static func onRegistryTaskEntity(id:String,maxIndex:Int,filename:String) -> Bool {
        //すでに登録済みの場合はFalse
        if(Task.single.tasks[id] != nil){
            return false
        }
        let DlEntity = TaskEntity.create()
                                 .setID(id: id)
                                 .setMaxIndex(index: maxIndex)
                                 .setFileName(name: filename)
        
        Task.single.add(id: id, entity: DlEntity)
        return true
    }
    
    //分割されたファイルの断片を意味するパケットを受信したとき
    static func onReciveDLPart(mes:Packet) {
        do{
            let importdata = try! ExportData.parseExportData(body: mes.getBody())
            print("recivedDL: "+importdata.id)
            if(Task.single.has(id: importdata.id)){
                //ダウンロードの接合処理を管理するクラスに投げる
                Task.single.addData(id: importdata.id, index: importdata.index, data: importdata.body)
            }else{
                //もし関係なければStopするように発信元に要求
                let stopPacket = Packet.builder()
                    .setToAddress(address: mes.getFromAddress())
                    .setFromAddress(address: P2PConnectivity.manager.id)
                    .setNowPutOutDate().setBody(body: try! DownloadCompletePacket().setID(id: importdata.id).toData())
                P2PConnectivity.manager.send(message: stopPacket.toData() ?? Data())
            }
        }catch{
            print(error)
        }
    }
    
    //ダウンロードが終わったことを意味するパケットを受信したとき
    static func onReciveFinishedPacket(mes:Packet) {
        do{
            let compPacket = try! DownloadCompletePacket.parseDownloadCompletePacket(body: mes.getBody())
            //反復送信をストップさせる
            TaskUtil.waitingQueue.removeAll(where: {$0 == compPacket.requestID})
            if let timerArray = MinistryOfP2P.Single.roopData[compPacket.requestID]{
                timerArray.forEach{$0.invalidate()}
            }
            //終わり
        }catch{
            ViewController.Single?.putLog(string: error.localizedDescription)
        }
    }
}
