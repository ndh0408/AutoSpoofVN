import Combine
import Foundation

/// Quản lý thiết bị kết nối — thông tin, trạng thái, diagnostics.
@MainActor
final class DeviceManager: ObservableObject {
    static let shared = DeviceManager()

    @Published private(set) var deviceName: String = ""
    @Published private(set) var deviceModel: String = ""
    @Published private(set) var deviceUDID: String = ""
    @Published private(set) var iosVersion: String = ""
    @Published private(set) var connectionState: DeviceConnectionState = .disconnected
    @Published private(set) var transportType: String = "DVT"
    @Published private(set) var lastHeartbeat: Date? = nil
    @Published private(set) var lastUpdate: Date? = nil
    @Published private(set) var lastError: String? = nil
    @Published private(set) var transportLatencyMs: Double = 0
    @Published var autoReconnect: Bool = true

    private var heartbeatTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let engine = SpoofEngine.shared
    private let pairingManager = SelfPairingManager.shared

    private init() {
        syncFromPairing()
        syncFromEngine()
    }

    // MARK: - Actions

    func connect() {
        connectionState = .connecting
        // Trigger connection through existing engine
        if let data = engine.pairingData {
            engine.connectLoopback(pairingData: data)
        } else if pairingManager.hasSavedPairing {
            if let data = try? Data(contentsOf: SelfPairingManager.pairingFileURL) {
                engine.connectLoopback(pairingData: data)
            }
        } else {
            connectionState = .error(L("device.error.no_pairing"))
        }
    }

    func disconnect() {
        engine.disconnect()
        connectionState = .disconnected
        stopHeartbeat()
    }

    func reconnect() {
        disconnect()
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            connect()
        }
    }

    func clearSimulation() {
        engine.clearDeviceLocation()
    }

    func testConnection() -> Bool {
        guard engine.isLoopbackConnected else { return false }
        let coord = engine.currentCoordinate
        let start = Date()
        engine.sendLocationToDevice(coord)
        transportLatencyMs = Date().timeIntervalSince(start) * 1000
        lastHeartbeat = Date()
        return true
    }

    // MARK: - Heartbeat

    func startHeartbeat(interval: TimeInterval = 20) {
        stopHeartbeat()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.engine.isLoopbackConnected {
                    self.lastHeartbeat = Date()
                    self.lastUpdate = Date()
                } else if self.autoReconnect {
                    self.reconnect()
                }
            }
        }
    }

    func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    // MARK: - Diagnostics

    struct DiagnosticsReport {
        let deviceConnected: Bool
        let deviceName: String
        let udid: String
        let transport: String
        let latencyMs: Double
        let lastError: String?
        let pairingAvailable: Bool
        let backgroundRunning: Bool
        let audioKeepAlive: Bool
        let locationAuth: String
        let liveActivityEnabled: Bool
    }

    func generateDiagnostics() -> DiagnosticsReport {
        let keeper = BackgroundKeeper.shared
        return DiagnosticsReport(
            deviceConnected: engine.isLoopbackConnected,
            deviceName: deviceName.isEmpty ? L("common.unknown") : deviceName,
            udid: deviceUDID.isEmpty ? L("common.unknown") : deviceUDID,
            transport: transportType,
            latencyMs: transportLatencyMs,
            lastError: lastError ?? engine.lastFFIError,
            pairingAvailable: engine.pairingData != nil || pairingManager.hasSavedPairing,
            backgroundRunning: keeper.isAudioRunning,
            audioKeepAlive: keeper.isAudioRunning,
            locationAuth: "\(keeper.authorizationStatus.rawValue)",
            liveActivityEnabled: true
        )
    }

    // MARK: - Sync

    private func syncFromPairing() {
        pairingManager.$pairedDeviceName
            .receive(on: DispatchQueue.main)
            .sink { [weak self] name in
                if !name.isEmpty { self?.deviceName = name }
            }
            .store(in: &cancellables)

        pairingManager.$pairedUDID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] udid in
                if !udid.isEmpty { self?.deviceUDID = udid }
            }
            .store(in: &cancellables)

        pairingManager.$phase
            .receive(on: DispatchQueue.main)
            .sink { [weak self] phase in
                if case .success(let name, let model, let udid) = phase {
                    self?.deviceName = name
                    self?.deviceModel = model
                    self?.deviceUDID = udid
                }
            }
            .store(in: &cancellables)
    }

    private func syncFromEngine() {
        engine.$isLoopbackConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] connected in
                guard let self else { return }
                if connected {
                    self.connectionState = .connected(transport: self.transportType)
                    self.lastUpdate = Date()
                    self.startHeartbeat()
                } else {
                    self.connectionState = .disconnected
                    self.stopHeartbeat()
                }
            }
            .store(in: &cancellables)

        engine.$lastFFIError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                self?.lastError = error
                if error != nil {
                    self?.connectionState = .error(error ?? L("common.error.unknown"))
                }
            }
            .store(in: &cancellables)
    }
}
