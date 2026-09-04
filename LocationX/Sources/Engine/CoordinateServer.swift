import Foundation
import Network

/// Cong HTTP cua CoordinateServer.
///
/// Khai bao o tam file (nonisolated) vi callback cua NWListener/NWConnection chay tren
/// hang doi network chu khong tren main actor — mot `let` cua class @MainActor khong
/// doc duoc tu do.
private let coordinateServerPort: UInt16 = 8765

/// Anh chup toa do dung chung giua main actor va hang doi network.
///
/// `CoordinateServer` la `@MainActor` (no la `ObservableObject` cho SwiftUI), nhung
/// `newConnectionHandler` va completion cua `NWConnection.receive` duoc goi tren `queue`
/// — mot context nonisolated. Doc thang stored property cua main actor tu do vua khong
/// bien dich duoc, vua la data race that (toa do bi ghi tu main actor moi lan
/// SimulationCoordinator.submit chay). Hop nay giu ban sao co khoa rieng nen ca hai
/// phia deu doc/ghi an toan.
private final class CoordinateSnapshotBox: @unchecked Sendable {
    struct Snapshot {
        var latitude: Double = 21.0285
        var longitude: Double = 105.8542
        var accuracy: Int = 39
        var speed: Double = 0
        var heading: Double = 0
    }

    private let lock = NSLock()
    private var value = Snapshot()
    private var requests = 0

    var snapshot: Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    /// So request da phuc vu. `/status` doc tu hang doi network nen phai qua khoa,
    /// con `CoordinateServer.requestCount` (@Published) la ban sao cho SwiftUI.
    var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    /// Tang bo dem va tra ve gia tri moi.
    @discardableResult
    func incrementRequests() -> Int {
        lock.lock()
        defer { lock.unlock() }
        requests += 1
        return requests
    }

    func update(latitude: Double, longitude: Double, accuracy: Int, speed: Double, heading: Double) {
        lock.lock()
        value = Snapshot(latitude: latitude, longitude: longitude,
                         accuracy: accuracy, speed: speed, heading: heading)
        lock.unlock()
    }
}

/// HTTP server cục bộ trên iPhone — phục vụ toạ độ giả realtime cho Shadowrocket MITM.
///
/// Luồng:
/// ```
/// LocationX di chuyển (route/flight/manual)
///     ↓
/// CoordinateServer cập nhật toạ độ
///     ↓
/// Shadowrocket MITM script fetch http://127.0.0.1:8765/coord
///     ↓
/// Script nhận toạ độ mới nhất → rewrite Apple location response
///     ↓
/// Bump nhận toạ độ giả, isSimulatedBySoftware = false
/// ```
@MainActor
final class CoordinateServer: ObservableObject {
    static let shared = CoordinateServer()

    @Published private(set) var isRunning = false
    @Published private(set) var requestCount = 0
    /// Đường dẫn của request gần nhất. Đây là bằng chứng THẬT rằng Shadowrocket đang
    /// chạy script của ta — mạnh hơn nhiều so với đoán qua tên network interface.
    @Published private(set) var lastRequestedPath: String?
    /// Thời điểm nhận request gần nhất, để biết pipeline còn "tươi" hay đã chết.
    @Published private(set) var lastRequestAt: Date?

    /// Lý do gắn cổng thất bại gần nhất, để màn Chẩn đoán nói được vì sao.
    @Published private(set) var lastError: String?

    private var retryTask: Task<Void, Never>?
    private var retryCount = 0
    private static let maxRetries = 6

    private var listener: NWListener?
    /// Cong dang phuc vu — UI/log doc duoc tu bat ky context nao.
    nonisolated var port: UInt16 { coordinateServerPort }
    private let queue = DispatchQueue(label: "com.nguyenduchuy.locationx.coordserver", qos: .userInitiated)

    /// Toạ độ hiện tại — cập nhật bởi SimulationCoordinator, doc boi hang doi network.
    private let box = CoordinateSnapshotBox()

    private init() {}

    // MARK: - Control

    func start() {
        guard !isRunning, listener == nil else { return }
        retryCount = 0
        bind()
    }

    /// Thử gắn vào cổng, tự thử lại nếu hỏng.
    ///
    /// Cổng 8765 có thể đang bị chiếm ngay lúc khởi động — thường là phiên trước của
    /// chính app chưa kịp đóng hẳn sau khi bị iOS thu hồi. Bản trước chỉ ghi log rồi bỏ
    /// cuộc: máy chủ nằm im suốt phiên, Shadowrocket không lấy được toạ độ nào, và cách
    /// duy nhất để thoát là tắt hẳn app rồi mở lại — mà không chỗ nào nói cho người
    /// dùng biết điều đó.
    private func bind() {
        listener?.cancel()
        listener = nil

        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true

            let listener = try NWListener(using: params, on: NWEndpoint.Port(integerLiteral: coordinateServerPort))
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        self.isRunning = true
                        self.retryCount = 0
                        self.lastError = nil
                        AppLogger.device.info("CoordinateServer listening on port \(coordinateServerPort)")
                    case .failed(let error):
                        self.isRunning = false
                        self.lastError = error.localizedDescription
                        AppLogger.device.error("CoordinateServer failed: \(error)")
                        self.scheduleRetry()
                    case .cancelled:
                        self.isRunning = false
                    default:
                        break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            isRunning = false
            lastError = error.localizedDescription
            AppLogger.device.error("CoordinateServer start error: \(error)")
            scheduleRetry()
        }
    }

    private func scheduleRetry() {
        guard retryCount < Self.maxRetries else {
            AppLogger.device.error("CoordinateServer bo cuoc sau \(Self.maxRetries) lan thu")
            return
        }
        retryCount += 1
        let delay = min(30, pow(2.0, Double(retryCount)))
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.bind() }
        }
    }

    /// Gắn lại ngay lập tức, không đợi hết nhịp chờ.
    ///
    /// Dùng khi người dùng quay lại app: nếu họ vừa tắt thứ đang chiếm cổng, không có
    /// lý do bắt họ chờ thêm.
    func restartIfNeeded() {
        guard !isRunning else { return }
        retryTask?.cancel()
        retryCount = 0
        bind()
    }

    func stop() {
        retryTask?.cancel()
        retryTask = nil
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    // MARK: - Update Coordinate

    /// Gọi bởi SimulationCoordinator mỗi khi toạ độ thay đổi.
    func updateCoordinate(latitude: Double, longitude: Double, accuracy: Int = 39, speed: Double = 0, heading: Double = 0) {
        box.update(latitude: latitude, longitude: longitude,
                   accuracy: accuracy, speed: speed, heading: heading)
    }

    // MARK: - HTTP Handler

    /// Chay tren `queue`, khong phai main actor.
    private nonisolated func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }

            let snapshot = self.box.snapshot
            let response: String

            if request.contains("GET /coord") {
                // Trả toạ độ JSON
                response = self.coordResponse(snapshot)
            } else if request.contains("GET /js") || request.contains("GET /location-spoofer.js") {
                // Trả JS script với toạ độ baked in
                response = self.jsResponse(snapshot)
            } else if request.contains("GET /module") || request.contains("GET /locationx.sgmodule") {
                // Trả Shadowrocket module
                response = self.moduleResponse()
            } else if request.contains("GET /status") {
                response = self.statusResponse(snapshot)
            } else {
                response = self.httpResponse(200, contentType: "text/plain", body: "LocationX CoordinateServer")
            }

            let responseData = Data(response.utf8)
            connection.send(content: responseData, completion: .contentProcessed { _ in
                connection.cancel()
            })

            let served = self.box.incrementRequests()
            let path = Self.requestPath(from: request)
            Task { @MainActor in
                self.requestCount = served
                self.lastRequestedPath = path
                self.lastRequestAt = Date()
            }
        }
    }

    /// Lay duong dan tu dong dau cua request HTTP ("GET /coord HTTP/1.1").
    ///
    /// Tach theo ky tu xuong dong roi cat khoang trang: khong dung chuoi escape de
    /// tranh phu thuoc vao viec CR/LF duoc viet the nao trong ma nguon.
    private nonisolated static func requestPath(from request: String) -> String? {
        guard let line = request.split(whereSeparator: { $0.isNewline }).first else { return nil }
        let parts = line.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2 else { return nil }
        return String(parts[1])
    }

    // MARK: - Responses

    private nonisolated func coordResponse(_ s: CoordinateSnapshotBox.Snapshot) -> String {
        let json = """
        {"lat":\(s.latitude),"lon":\(s.longitude),"acc":\(s.accuracy),"spd":\(s.speed),"hdg":\(s.heading),"ts":\(Int(Date().timeIntervalSince1970))}
        """
        return httpResponse(200, contentType: "application/json", body: json)
    }

    /// Nội dung `location-spoofer.js` nạp từ bundle, đọc một lần.
    ///
    /// Script được đóng gói thành **tài nguyên** chứ không nhúng chuỗi trong Swift: trước
    /// đây có hai bản JS song song (một trong `Proxy/`, một viết cứng ở đây) và chúng đã
    /// trôi khỏi nhau — bản trong app vẫn là thuật toán quét int32 sai.
    private nonisolated static let scriptTemplate: String = {
        guard let url = Bundle.main.url(forResource: "location-spoofer", withExtension: "js"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return ""
        }
        return text
    }()

    private nonisolated func jsResponse(_ s: CoordinateSnapshotBox.Snapshot) -> String {
        let template = Self.scriptTemplate
        guard !template.isEmpty else {
            return httpResponse(500, contentType: "text/plain",
                                body: "location-spoofer.js khong co trong bundle")
        }
        // Chèn sẵn `$argument` để bản chạy nội bộ dùng toạ độ realtime, còn bản import
        // từ GitHub vẫn nhận tham số tĩnh do Shadowrocket truyền vào.
        let prelude = """
        var $argument = "latitude=\(s.latitude)&longitude=\(s.longitude)&horizontalAccuracy=\(s.accuracy)";

        """
        return httpResponse(200, contentType: "application/javascript", body: prelude + template)
    }

    private nonisolated func moduleResponse() -> String {
        let module = """
        #!name=LocationX Live
        #!desc=GPS spoof realtime từ LocationX app

        [Script]
        LocationX = type=http-response,pattern=^https?:\\/\\/(?:gs-loc(?:-cn)?\\.apple\\.com|gsp-ssl\\.ls\\.apple\\.com|bluedot\\.is\\.autonavi\\.com(?:\\.gds\\.alibabadns\\.com)?)\\/clls\\/wloc,requires-body=1,binary-body-mode=1,max-size=0,timeout=30,script-path=http://127.0.0.1:\(coordinateServerPort)/location-spoofer.js

        [MITM]
        hostname = %APPEND% gs-loc.apple.com, gs-loc-cn.apple.com, gsp-ssl.ls.apple.com, bluedot.is.autonavi.com, bluedot.is.autonavi.com.gds.alibabadns.com
        """
        return httpResponse(200, contentType: "text/plain", body: module)
    }

    private nonisolated func statusResponse(_ s: CoordinateSnapshotBox.Snapshot) -> String {
        let json = """
        {"running":true,"lat":\(s.latitude),"lon":\(s.longitude),"requests":\(box.requestCount),"port":\(coordinateServerPort)}
        """
        return httpResponse(200, contentType: "application/json", body: json)
    }

    private nonisolated func httpResponse(_ code: Int, contentType: String, body: String) -> String {
        let status = code == 200 ? "OK" : "Error"
        return """
        HTTP/1.1 \(code) \(status)\r
        Content-Type: \(contentType)\r
        Content-Length: \(body.utf8.count)\r
        Access-Control-Allow-Origin: *\r
        Connection: close\r
        \r
        \(body)
        """
    }
}
