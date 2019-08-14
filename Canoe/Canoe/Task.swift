//
//  Task.swift
//  Router
//
//  Created by Kengo Wada on 2019/08/11.
//  Copyright © 2019 10fu3. All rights reserved.
//

import Foundation

class TaskEntity {
    var maxIndex = 0
    var id = ""
    var filename = ""
    var partOfData = [Data]()
    
    func isFinished() -> Bool {
        return partOfData.count == maxIndex
    }
    func joinData() -> Data {
        var value = Data()
        partOfData.forEach{value.append($0)}
        return value
    }
    
    static func create() -> TaskEntity {
        return TaskEntity()
    }
    
    func setMaxIndex(index:Int) -> TaskEntity {
        self.maxIndex = index
        partOfData = [Data](repeating: Data(), count: index)
        return self
    }
    
    func setID(id:String) -> TaskEntity {
        self.id = id
        return self
    }
    
    func setFileName(name:String) -> TaskEntity {
        self.filename = name
        return self
    }
}

class Task {
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
        //分割数
        if(self.tasks[id] != nil &&
            self.tasks[id]!.maxIndex == self.tasks[id]!.partOfData.filter{$0.count > 0}.count){
            outPutFileOnDocument(data: self.tasks[id]!.joinData(), fileName: self.tasks[id]!.filename)
            let name = String.init(self.tasks[id]!.filename)
            self.tasks[id] = nil
            ViewController.Single?.putLog(string: "ファイル名: "+name+"のダウンロードが完了しました")
            
            do{
                let compMesData = Packet.builder()
                    .setType(type: .Completed)
                    .setNowPutOutDate()
                    .setToAddressAll()
                    .setFromAddress(address: P2PConnectivity.manager.id)
                    .setBody(body: try! DownloadCompletePacket().setID(id: id).toData()).toData() ?? Data()
                
                var counter = 1
                
                //まれに送信しても受信されないことがあるので繰り返し送る
                Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true, block: { timer in
                    if counter > 5{
                        timer.invalidate()
                        return
                    }
                    counter += 1
                    P2PConnectivity.manager.send(message: compMesData)
                })
                
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
    
    //IDを登録する
    static var waitingQueue = [String]()
    
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
    
    static func onReciveDLRequest(mes:Packet) {
        do{
            let req = try! DownloadRequestPacket.parseDownloadRequestData(body: mes.getBody())
            if( TaskUtil.waitingQueue.contains(req.requestID)){
                return
            }
            TaskUtil.waitingQueue.append(req.requestID)
//            print(req.body)
//            print("recivedID: "+req.requestID)
            let json = try JSONSerialization.jsonObject(with: req.body.data(using: .utf8) ?? Data(), options: []) as? [String: String] ?? [:]
            ViewController.Single?.putLog(string: req.body)
            
            Util.searchKey(dic: json, doIt: {$0 == P2PConnectivity.manager.id}).forEach{ part in
                let dataPlate = Util.parseLine(line: part)
                let link = dataPlate?.1
                Http.downloadData(url: link ?? "", onFinished: { dlData in
                    let dlBody = ExportData.init().setIndex(index: dataPlate?.0 ?? -1).setBody(body: dlData).setID(id: req.requestID)
                    ViewController.Single?.putLog(string: link ?? ""+"のダウンロードを行いました")

                    do{
                        
                        let task = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true, block: { timer in
                            
                            
                            let dlPack = Packet
                            .builder()
                            .setType(type: .ExportData)
                            .setNowPutOutDate()
                            .setFromAddress(address: P2PConnectivity.manager.id)
                            .setToAddress(address: mes.getFromAddress())
                            .setBody(body: try! dlBody.toData())
                            P2PConnectivity.manager.send(message: dlPack.toData() ?? Data())
                        })
                        
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
    
    static func onReciveDLPart(mes:Packet) {
        do{
            let importdata = try! ExportData.parseExportData(body: mes.getBody())
            print("recivedDL: "+importdata.id)
            if(Task.single.has(id: importdata.id)){
                Task.single.addData(id: importdata.id, index: importdata.index, data: importdata.body)
            }else{
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
    
    static func onReciveFinishedPacket(mes:Packet) {
        do{
            let compPacket = try! DownloadCompletePacket.parseDownloadCompletePacket(body: mes.getBody())
            TaskUtil.waitingQueue.removeAll(where: {$0 == compPacket.requestID})
            if let timerArray = MinistryOfP2P.Single.roopData[compPacket.requestID]{
                timerArray.forEach{$0.invalidate()}
            }
        }catch{
            ViewController.Single?.putLog(string: error.localizedDescription)
        }
    }
}
