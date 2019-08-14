//
//  P2P.swift
//  Router
//
//  Created by Kengo Wada on 2019/07/24.
//  Copyright © 2019 Kengo Wada. All rights reserved.
//
import MultipeerConnectivity
import Foundation

extension TimeZone {
    static let gmt = TimeZone(secondsFromGMT: 0)!
    static let jst = TimeZone(identifier: "Asia/Tokyo")!
}

extension NSObjectProtocol where Self: NSObject {
    var description: String {
        let mirror = Mirror(reflecting: self)
        return mirror.children
            .map { (element) -> String in
                let key = element.label ?? "Undefined"
                let value = element.value
                return "\(key): \(value)"
            }
            .joined(separator: "\n")
    }
}

//Iteratorのnext実行時に最後に来たらNilではなく最初の要素に戻るように改良したもの
class LoopIterator<T>{
    var array = [T]()
    var it:IndexingIterator<[T]>
    init(Array:[T]) {
        self.array = Array
        it = Array.makeIterator()
    }
    func next() -> T {
        //Iteratorのカレントを一つすすめる
        var value:T? = it.next()
        //もし最後だったら
        if(value == nil){
            //最初からに戻す
            it = array.makeIterator()
            value = it.next()
        }
        return value!
    }
}

class MinistryOfP2P {
    
    static let Single = MinistryOfP2P()
    
    var roopData: [String:[Timer]]
    
    
    
    init() {
        roopData = Dictionary()
    }
    
    static func doLinkList(jsonDlList:String) {
        do{
            
            //LinkListをJSONオブジェクトに変換する
            let json = try JSONSerialization
                        .jsonObject(
                                    with: jsonDlList.data(using: .utf8) ?? Data(),
                                    options: [])
                        as! Dictionary<String,String>
            //JSONから自分のIDを含むキーを探す
            let data = Util.searchKey(dic: json, doIt: {$0 == P2PConnectivity.manager.id})
            data.forEach{ lineData in
                //seplatedDataに含まれる値が自分がダウンロードする分のリンクとインデックス
                let seplatedData = Util.parseLine(line: lineData)
                DispatchQueue.main.async {
                    ViewController.Single?.putLog(string: seplatedData!.1+" "+seplatedData!.2+" "+String.init(seplatedData!.0))
                }
                Http.downloadData(url: seplatedData?.1 ?? "", onFinished: { data in
                    //dataにダウンロード済みデータが格納される
                    //これを他のP2P接続されている端末に一斉送信する
                    let message = Packet
                                 .builder()
                                 .setType(type: .ExportData)
                                 .setNowPutOutDate()
                                 .setFromAddress(address: P2PConnectivity.manager.id)
                                 .setToAddressAll()
 
                    var count = 0
                    Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true, block: { timer in
                        if(count > 5){
                            timer.invalidate()
                            return
                        }
                        count += 1
                        P2PConnectivity.manager.send(message: message.toData() ?? Data())
                    })

                }, onError: {
                    print($0)
                })
            }
            
        }
        catch{
            
        }
    }
    
    static func parseAddressAndUrl(pairs:[String],urls: [String]) ->([(String,String)]){
        var url = urls
        var copyPairs = pairs.map{$0}
        let itPairs = LoopIterator.init(Array: pairs)
        if(urls.count < pairs.count){
            while url.count < pairs.count {
                url.append("NOURL")
            }
        }else if(urls.count > pairs.count){
            while url.count > copyPairs.count {
                copyPairs.append(itPairs.next())
            }
        }
        return zip(copyPairs, url).map{$0}
    }
    
    static func toJSON(array:([(String,String)])) -> String {
        return "{"+array.map{"\""+$0.1+"\""+":"+"\""+$0.0+"\""}.joined(separator: ",")+"}"
    }
    
    //返す値は各ペア端末に送信したJSONデータ
    static func sendDLRequest(id:String,urls: [String])->String{
        let jsonData = toJSON(array: parseAddressAndUrl(pairs: P2PConnectivity.manager.connectedPair, urls: urls))
        let selfID = P2PConnectivity.manager.id
        do{
            let items = try JSONSerialization.jsonObject(with: jsonData.data(using: .utf8) ?? Data()) as! Dictionary<String,String>
            TaskUtil.selfDownloadTask(id: id, list: items)
            let body = DownloadRequestPacket.init().setID(id: id).setBody(body: jsonData)
            if(items.count > 0){
                let mes = Packet.builder()
                                 .setType(type: .DownloadRequest)
                                 .setNowPutOutDate()
                                 .setToAddressAll()
                                 .setFromAddress(address: selfID)
                                 .setBody(body: try! body.toData())
                P2PConnectivity.manager.send(message: mes.toData() ?? Data())
                //P2PConnectivity.manager.send(message: .DownloadRequest, body: jsonData.data(using: .utf8) ?? Data())
            }
        }catch{
            print(error)
        }
        return jsonData
    }
}

enum PeerProtocolError: Error {
    
    //サイズが十分ではない
    case NotEnoughArraySize(Int)
    //何かしらの理由によって以下に定める通信プロトコルに適合しない
    case NotConformProtocol(String)
    
}

class ExportData {
    
    //Messageに格納するBodyを更に加工
    //
    // +--Data Array Index ------------------------------------------------+------------------------------|
    // |                |                    |                             |                              |
    // |        0       |       1  ~  8      |           9 ~ 44            | 45~(45+Download byte size)   |
    // |_____________________________________|_____________________________|______________________________|
    // |   UInt 8 raw   |         Int        |           String            |        Data(Byte Array)      |
    // | Download Index | Download byte size |     DL要請側が発行したUUID     |          送受信内容            |
    // |     (1byte)    |        (8byte)     |          (36byte)           |        (制限なしbyte)       　 |
    // +----------------+--------------------+-----------------------------+------------------------------|
    var dataSize = 0
    var body = Data()
    var index = -1
    var id = ""
    
    static func parseExportData(body:Data) throws -> ExportData {
        let ed = ExportData()
        if(body.count > 44){
            ed.setIndex(index: Int.init(String.init(body[0])) ?? -1)
            ed.dataSize = Data(bytes: body[1...8])
                .withUnsafeBytes{ (p: UnsafePointer<Int>) in    //-- 引数を取得したい数値データ型のUnsafePointerとして指定
                    p.pointee
            }
            ed.id = String.init(data: body[9...44], encoding: .utf8) ?? ""
            ed.body = Data.init(body[45...body.count-1].map{$0})
        }else{
            throw PeerProtocolError
                  .NotEnoughArraySize(body.count)
        }
        return ed
    }
    
    func toData() throws -> Data {
        var data = Data.init()
        if(index < 0){
            throw PeerProtocolError
                  .NotConformProtocol("Not allowed minus number on download index")
        }else{
            var count = body.count
            data.append(UInt8.init(exactly: index)!)
            data.append(Data(bytes: &count, count: MemoryLayout.size(ofValue: count)))
            data.append(self.id.data(using: .utf8) ?? Data())
            data.append(body)
        }
        return data
    }
    
    func setIndex(index:Int) -> ExportData {
        self.index = index
        return self
    }
    
    func setBody(body:Data) -> ExportData {
        self.body = body
        return self
    }
    
    func setID(id:String) -> ExportData {
        self.id = id
        return self
    }
}

class DownloadCompletePacket{
    var requestID = ""
    
    //+Data Array Index
    //|              |
    //|   0 ~ 35     |
    //|______________|
    //| String raw   |
    //|  MessageType |
    //|   (36byte)   |
    //+---------------
    
    func setID(id:String) -> DownloadCompletePacket {
        self.requestID = id
        return self
    }
    
    func toData() throws -> Data {
        var data = Data.init()
        let idData = requestID.data(using: .utf8) ?? Data()
        if(idData.count == 36){
            data.append(requestID.data(using: .utf8) ?? Data())
        }else{
            PeerProtocolError.NotConformProtocol("Completed packet error")
        }
        return data
    }
    
    static func parseDownloadCompletePacket(body:Data) throws -> DownloadCompletePacket {
        if(body.count == 36){
            let value = DownloadCompletePacket()
            let id = String.init(data: body[0...35], encoding: .utf8)
            value.requestID = id ?? ""
            return value
        }
        throw PeerProtocolError.NotConformProtocol("DLComplete error")
    }
}

class DownloadRequestPacket {
    var body = ""
    var requestID = ""
    
    //+Data Array Index --------------+
    //|                               |
    //|   0 ~ 35       36 ~ Data.size |
    //|_______________________________|
    //| String raw   |    String      |
    //|  MessageType |    送受信内容    |
    //|   (36byte)   |                |
    //+-------------------------------+
    
    func setID(id:String) -> DownloadRequestPacket {
        self.requestID = id
        return self
    }
    
    func setBody(body:String) -> DownloadRequestPacket {
        self.body = body
        return self
    }
    
    func toData() throws -> Data {
        var data = Data.init()
        let idData = requestID.data(using: .utf8) ?? Data()
        if(idData.count == 36){
            data.append(requestID.data(using: .utf8) ?? Data())
            data.append(body.data(using: .utf8) ?? Data())
        }else{
            PeerProtocolError.NotConformProtocol("DLRequest error")
        }
        return data
    }
    
    static func parseDownloadRequestData(body:Data) throws -> DownloadRequestPacket {
        if(body.count > 35){
            let value = DownloadRequestPacket()
            let id = String.init(data: body[0...35], encoding: .utf8)
            let body = String.init(data: body[36...body.count-1],encoding: .utf8)
            value.requestID = id ?? ""
            value.body = body ?? ""
            return value
        }
        throw PeerProtocolError.NotConformProtocol("DLRequest error")
    }
}

class Packet:NSObject{
    //一次的なMultipeerContactivity 通信プロトコル仕様書（？）
    
    // Data Array Index ----------------------------------------------------------------------------------|
    //                                                                                                    |
    //      0           1~17      18~53        54~89       90~125      126 ~ (127+Download byte size)     |
    //____________________________________________________________________________________________________|
    //| UInt8 raw   | String  |  String   |   String　　 |  String   |           Data(Byte Array) 　　　    |
    //| MessageType | 発信時刻　|ReciverUUID|SenderAddress| MessageID |               送受信内容      　　　   |
    //|   (1byte)   | (17byte)| (36byte)  |   (36byte)  |  (36byte) |              (制限なしbyte)　　　　    |
    //----------------------------------------------------------------------------------------------------|

    private override init() {
        //非推奨
        self.type = .ConvertError
        putOutDate = Date.init(timeIntervalSince1970: 0)
        from = ""
        to = ""
        body = Data()
        id = UUID.init().uuidString
    }
    
    private var type:MessageType
    private var putOutDate:Date
    private var from:String
    private var to:String
    private var body:Data
    private var id:String
    
    func getMessageType() -> MessageType {
        return type
    }
    
    func getPutOutDate() -> Date {
        return putOutDate
    }
    
    func getFromAddress() -> String {
        return from
    }
    
    func getToAddress() -> String {
        return to
    }
    
    func getBody() -> Data {
        return body
    }
    
    func getId() -> String {
        return id
    }
    
    private static func getMessageType(data:Data) -> MessageType {
        //フォーマットエラーを弾く
        if(data.count < 127){
            return .ConvertError
        }
        switch data[0] {
        case 0:
            return .DownloadRequest
        case 1:
            return .ExportData
        case 2:
            return .Completed
        case 3:
            return .ReplyYes
        case 4:
            return .ReplyNo
        case 5:
            fallthrough
        default:
            return .ConvertError
        }
    }
    
    //1970年からのミリ秒文字列をDate型に変換 ここでは日本時間にはせず、現在時刻生成メソッドの中で日本時間に直す
    private static func getDatePutout(data:Data) -> Date? {
        //フォーマットエラーを弾く
        if(data.count >= 127){
            let time = String.init(data: data[1...17], encoding: .utf8)
            if(time == nil){
                return nil
            }
            return Date.init(timeIntervalSince1970: Double.init(time!) ?? 0)
        }else{
            return nil
        }
    }
    //送信先・受信元UUIDの取得 すべて未処理のデータを投入すること
    private static func getReciverAddress(data:Data) -> String? {
        //フォーマットエラーを弾く
        if(data.count >= 127){
            return String.init(data: data[18...53], encoding: .utf8)
        }else{
            return nil
        }
    }
    //送信元UUIDの取得 すべて未処理のデータを投入すること
    private static func getSenderAddress(data:Data) -> String? {
        //フォーマットエラーを弾く
        if(data.count >= 127){
            return String.init(data: data[54...89], encoding: .utf8)
        }else{
            return nil
        }
    }
    
    private static func getMessageID(data:Data) -> String? {
        //フォーマットエラーを弾く
        if(data.count >= 127){
            return String.init(data: data[90...125], encoding: .utf8)
        }else{
            return nil
        }
    }
    
    //送受信内容(電文本体) すべて未処理のデータを投入すること
    private static func getBody(data:Data) -> Data {
        print(String.init(data: data, encoding: .utf8) ?? "")
        if(data.count >= 127){
            return Data.init(data[126...data.count-1].map{$0})
        }else{
            return Data()
        }
    }
    
    
    
    private static func toData(type:MessageType) -> Data {
        switch type {
        case .DownloadRequest:
            return Data([0])
        case .ExportData:
            return Data([1])
        case .Completed:
            return Data([2])
        case .ReplyYes:
            return Data([3])
        case .ReplyNo:
            return Data([4])
        case .ConvertError:
            return Data([5])
        }
    }
    
    static func parseFromData(data:Data) throws -> Packet {
        let mes = Packet()
        mes.type = Packet.getMessageType(data: data)
        //error
        if let date = Packet.getDatePutout(data: data){
            mes.putOutDate = date
        }else{
            throw PeerProtocolError.NotConformProtocol("date")
        }
        if let to = Packet.getReciverAddress(data: data){
            mes.to = to
        }else{
            throw PeerProtocolError.NotConformProtocol("to (Reciver address is not conform communication protocol)")
        }
        if let from = Packet.getSenderAddress(data: data){
            mes.from = from
        }else{
            throw PeerProtocolError.NotConformProtocol("from (Sender address is not conform communication protocol)")
        }
        if let id = Packet.getMessageID(data: data){
            mes.id = id
        }else{
            throw PeerProtocolError.NotConformProtocol("id (message id is not conform communication protocol)")
        }
        mes.body = Packet.getBody(data: data)
        return mes
    }
    
    func toData() -> Data? {
        return try? Packet.parseToData(mes: self)
    }
    
    static func parseToData(mes:Packet) throws -> Data {
        //送信用バイト配列
        var value = Data()
        if(mes.type == .ConvertError || mes.from.count == 0 || mes.to.count == 0){
            throw PeerProtocolError.NotConformProtocol("One of the stored variables is not conform with the communication protocol.")
        }
        
        let timeByte = String.init(mes.putOutDate.timeIntervalSince1970).data(using: .utf8) ?? Data()
        let toByte = mes.to.data(using: .utf8) ?? Data()
        let fromByte = mes.from.data(using: .utf8) ?? Data()
        let idByte = mes.id.data(using: .utf8) ?? Data()
        if(timeByte.count == 17 && toByte.count == 36 && fromByte.count == 36 && idByte.count == 36){
            value.append(toData(type: (mes.type)))
            value.append(timeByte)
            value.append(toByte)
            value.append(fromByte)
            value.append(idByte)
            value.append(mes.body)
        }else{
            throw PeerProtocolError.NotEnoughArraySize(1+timeByte.count+toByte.count+fromByte.count+idByte.count)
        }
        return value
        
    }
    
    static func builder() -> Packet {
        return Packet()
    }
    
    func setType(type:MessageType) -> Packet {
        self.type = type
        return self
    }
    func setPutOutDate(date:Double) -> Packet {
        self.putOutDate = Date.init(timeIntervalSince1970: date)
        return self
    }
    
    func setNowPutOutDate() -> Packet {
        self.putOutDate = Date.init(timeIntervalSinceNow: TimeInterval.init(TimeZone.jst.secondsFromGMT()))
        return self
    }
    
    func setFromAddress(address:String) -> Packet {
        self.from = address
        return self
    }
    
    func setToAddress(address:String) -> Packet {
        self.to = address
        return self
    }
    
    func setToAddressAll() -> Packet {
        self.to = "-----------------ALL----------------"
        return self
    }
    
    func isMesToMe() -> Bool {
//        print(P2PConnectivity.manager.id)
//        print(self.to)
        
        if(self.to == "-----------------ALL----------------"){
            return true
        }else{
            return self.to == P2PConnectivity.manager.id
        }
    }
    
    func setBody(body:Data) -> Packet {
        self.body = body
        return self
    }
    
}

enum MessageType{
    case DownloadRequest //URLを発行する際に発せられるメッセージ
    case ExportData//ダウンロードしたデータを送信する・受信したときに発せられるメッセージ
    case Completed//ファイル本体の結合が完了したときに発せられるメッセージ
    case ReplyYes//特定のメッセージに応答する際のメッセージ
    case ReplyNo//特定のメッセージに応答する際のメッセージ
    case ConvertError//内部エラー・送信時のエラーを表すメッセージ
}
//  P2PConnectivity
//  https://mike-neko.github.io/blog/multipeer/
//  Copyright © 2019 M.Ike
//
class P2PConnectivity: NSObject, MCSessionDelegate,MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {
    
    static let manager = P2PConnectivity()
    
    var state :(MCSessionState,MCPeerID?) = (.notConnected,nil){
        didSet{
            stateChangeHandler?(state.0,state.1)
            if(state.0 == .connected){
                connectedPair.append(state.1?.displayName ?? "")
            }else if(state.0 == .notConnected){
                connectedPair.removeAll(where: {$0 == state.1?.displayName ?? ""})
            }
            connectedPair.forEach{print($0)}
        }
    }
    
    var connectedPair = [String]()
    
    var id = UUID.init().uuidString
    private var stateChangeHandler: ((MCSessionState,MCPeerID?) -> Void)? = nil
    private var recieveHandler: ((Packet) -> Void)? = nil
    
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser!
    private var browser: MCNearbyServiceBrowser!
    
    private override init() {
    }
    
    func start(serviceType: String, stateChangeHandler: @escaping ((MCSessionState,MCPeerID?) -> Void),
               recieveHandler: ((Packet) -> Void)? = nil) {
        self.stateChangeHandler = stateChangeHandler
        self.recieveHandler = recieveHandler

        let peerID = MCPeerID(displayName: id)
        
        self.connectedPair = [id]
        
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .none)
        session.delegate = self
        
        advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: serviceType)
        advertiser.delegate = self
        
        browser = MCNearbyServiceBrowser(peer: peerID, serviceType: serviceType)
        browser.delegate = self
        
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
    }
    
    func stop() {
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        session.disconnect()
    }
    
    @discardableResult
    func send(message: Data) -> Bool {
        guard case .connected = state.0 else { return false }
        
        let data = message
        do {
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
        } catch {
            print(error.localizedDescription)
            return false
        }
        
        return true
    }
    
    // MARK: - MCSessionDelegate
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        do{
            let convertedData = try! Packet.parseFromData(data: data)
            if(convertedData != nil && convertedData.isMesToMe()){
                recieveHandler?(convertedData)
            }
        }catch{
            print(error)
        }
    }
    
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        print(#function)
        assertionFailure("Not support")
    }
    
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        print(#function)
        assertionFailure("Not support")
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        print(#function)
        assertionFailure("Not support")
    }
    
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        print(#function)
        
        switch state {
        case .notConnected:
            print("state: notConnected")
            // 再度検索を開始
            //advertiser.startAdvertisingPeer()
            //browser.startBrowsingForPeers()
        case .connected:
            print("state: connected")
        case .connecting:
            print("state: connecting")
            // 接続開始されたので一旦停止
            //advertiser.stopAdvertisingPeer()
            //browser.stopBrowsingForPeers()
        }
        self.state = (state,peerID)
    }
    
    // MARK: - MCNearbyServiceAdvertiserDelegate
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        print(#function)
        
        print("InvitationFrom: \(peerID)")
        // 招待は常に受ける
        invitationHandler(true, session)
    }
    
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        print(#function)
        print(error)
    }
    
    // MARK: - MCNearbyServiceBrowserDelegate
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        print(#function)
        print("lost: \(peerID)")
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        print(#function)
        print("found: \(peerID)")
        // 見つけたら即招待
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 0)
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        print(#function)
        print(error)
    }
    
}
