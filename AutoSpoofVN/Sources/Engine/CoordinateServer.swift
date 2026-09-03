import Foundation
import Network

/// HTTP server cục bộ trên iPhone — phục vụ toạ độ giả realtime cho Shadowrocket MITM.
///
/// Luồng:
/// ```
/// AutoSpoofVN di chuyển (route/flight/manual)
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

    private var listener: NWListener?
    private let port: UInt16 = 8765
    private let queue = DispatchQueue(label: "com.autospoof.vn.coordserver", qos: .userInitiated)

    // Toạ độ hiện tại — cập nhật bởi SimulationCoordinator
    private var latitude: Double = 21.0285
    private var longitude: Double = 105.8542
    private var accuracy: Int = 39
    private var speed: Double = 0
    private var heading: Double = 0

    private init() {}

    // MARK: - Control

    func start() {
        guard !isRunning else { return }

        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true

            let listener = try NWListener(using: params, on: NWEndpoint.Port(integerLiteral: port))
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready:
                        self?.isRunning = true
                        AppLogger.device.info("CoordinateServer listening on port \(self?.port ?? 0)")
                    case .failed(let error):
                        self?.isRunning = false
                        AppLogger.device.error("CoordinateServer failed: \(error)")
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
            AppLogger.device.error("CoordinateServer start error: \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    // MARK: - Update Coordinate

    /// Gọi bởi SimulationCoordinator mỗi khi toạ độ thay đổi.
    func updateCoordinate(latitude: Double, longitude: Double, accuracy: Int = 39, speed: Double = 0, heading: Double = 0) {
        self.latitude = latitude
        self.longitude = longitude
        self.accuracy = accuracy
        self.speed = speed
        self.heading = heading
    }

    // MARK: - HTTP Handler

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }

            let response: String

            if request.contains("GET /coord") {
                // Trả toạ độ JSON
                response = self.coordResponse()
            } else if request.contains("GET /js") || request.contains("GET /location-spoofer.js") {
                // Trả JS script với toạ độ baked in
                response = self.jsResponse()
            } else if request.contains("GET /module") || request.contains("GET /autospoof.sgmodule") {
                // Trả Shadowrocket module
                response = self.moduleResponse()
            } else if request.contains("GET /status") {
                response = self.statusResponse()
            } else {
                response = self.httpResponse(200, contentType: "text/plain", body: "AutoSpoofVN CoordinateServer")
            }

            let responseData = Data(response.utf8)
            connection.send(content: responseData, completion: .contentProcessed { _ in
                connection.cancel()
            })

            Task { @MainActor in
                self.requestCount += 1
            }
        }
    }

    // MARK: - Responses

    private func coordResponse() -> String {
        let json = """
        {"lat":\(latitude),"lon":\(longitude),"acc":\(accuracy),"spd":\(speed),"hdg":\(heading),"ts":\(Int(Date().timeIntervalSince1970))}
        """
        return httpResponse(200, contentType: "application/json", body: json)
    }

    private func jsResponse() -> String {
        let js = """
        // AutoSpoofVN Dynamic Location Script
        // Toạ độ: \(latitude), \(longitude) @ \(Date())
        const SCALE = 1e8;
        const TARGET_LAT = Math.round(\(latitude) * SCALE);
        const TARGET_LON = Math.round(\(longitude) * SCALE);
        const ACCURACY = \(accuracy) * 1000;

        function run() {
            const body = $response.body;
            if (!body || body.byteLength < 10) { $done({}); return; }
            const data = new Uint8Array(body);
            const view = new DataView(data.buffer);
            let modified = false;
            let offset = 0;
            while (offset + 8 <= data.byteLength) {
                try {
                    const val1 = view.getInt32(offset, false);
                    const val2 = view.getInt32(offset + 4, false);
                    const lat = val1 / SCALE;
                    const lon = val2 / SCALE;
                    if (lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180 && Math.abs(lat) > 0.001 && Math.abs(lon) > 0.001) {
                        view.setInt32(offset, TARGET_LAT, false);
                        view.setInt32(offset + 4, TARGET_LON, false);
                        if (offset + 12 <= data.byteLength) {
                            const a = view.getInt32(offset + 8, false);
                            if (a > 0 && a < 1000000000) view.setInt32(offset + 8, ACCURACY, false);
                        }
                        modified = true;
                        offset += 12;
                        continue;
                    }
                } catch(e) {}
                offset += 1;
            }
            $done({ body: data.buffer });
        }
        run();
        """
        return httpResponse(200, contentType: "application/javascript", body: js)
    }

    private func moduleResponse() -> String {
        let module = """
        #!name=AutoSpoofVN Live
        #!desc=GPS spoof realtime từ AutoSpoofVN app

        [Script]
        AutoSpoofVN = type=http-response,pattern=^https?:\\/\\/(?:gs-loc(?:-cn)?\\.apple\\.com|gsp-ssl\\.ls\\.apple\\.com|bluedot\\.is\\.autonavi\\.com(?:\\.gds\\.alibabadns\\.com)?)\\/clls\\/wloc,requires-body=1,binary-body-mode=1,max-size=0,timeout=30,script-path=http://127.0.0.1:\(port)/location-spoofer.js

        [MITM]
        hostname = %APPEND% gs-loc.apple.com, gs-loc-cn.apple.com, gsp-ssl.ls.apple.com, bluedot.is.autonavi.com, bluedot.is.autonavi.com.gds.alibabadns.com
        """
        return httpResponse(200, contentType: "text/plain", body: module)
    }

    private func statusResponse() -> String {
        let json = """
        {"running":true,"lat":\(latitude),"lon":\(longitude),"requests":\(requestCount),"port":\(port)}
        """
        return httpResponse(200, contentType: "application/json", body: json)
    }

    private func httpResponse(_ code: Int, contentType: String, body: String) -> String {
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
