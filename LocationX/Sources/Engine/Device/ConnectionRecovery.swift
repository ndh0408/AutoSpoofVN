import Combine
import Foundation
import Network

/// Giám sát kết nối và tự phục hồi khi đứt.
///
/// Khi device disconnect giữa simulation:
/// 1. Simulation pause tự động
/// 2. UI hiện trạng thái thật (không giả vờ vẫn kết nối)
/// 3. Retry kết nối theo backoff
/// 4. Khi kết nối lại → validate → resume nếu safe
@MainActor
final class ConnectionRecovery: ObservableObject {
    static let shared = ConnectionRecovery()

    @Published private(set) var isRecovering = false
    @Published private(set) var retryCount = 0
    @Published private(set) var networkAvailable = true

    private var retryTask: Task<Void, Never>?
    private var networkMonitor: NWPathMonitor?
    private var cancellables = Set<AnyCancellable>()
    private let maxRetries = 5
    private let baseDelay: TimeInterval = 2.0 // exponential backoff

    private init() {
        startNetworkMonitor()
        observeConnection()
    }

    // MARK: - Network Monitor

    private func startNetworkMonitor() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.networkAvailable = path.status == .satisfied
                AppLogger.device.info("Network: \(path.status == .satisfied ? "available" : "unavailable")")
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.nguyenduchuy.locationx.network"))
        networkMonitor = monitor
    }

    // MARK: - Connection Observer

    private func observeConnection() {
        SpoofEngine.shared.$isLoopbackConnected
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] connected in
                guard let self else { return }
                if !connected && SimulationCoordinator.shared.state.isActive {
                    self.handleDisconnect()
                } else if connected && self.isRecovering {
                    self.handleReconnect()
                }
            }
            .store(in: &cancellables)
    }

    private func handleDisconnect() {
        AppLogger.device.warning("Device disconnected during active simulation")
        let coordinator = SimulationCoordinator.shared
        coordinator.pauseSession()
        isRecovering = true
        retryCount = 0
        startRetryLoop()
    }

    private func handleReconnect() {
        AppLogger.device.info("Device reconnected after recovery")
        retryTask?.cancel()
        isRecovering = false
        retryCount = 0

        let coordinator = SimulationCoordinator.shared
        let engine = SpoofEngine.shared

        // Validate: gửi heartbeat test
        if engine.isLoopbackConnected {
            engine.sendLocationToDevice(coordinator.currentCoordinate)
            // Resume nếu trước đó đang chạy
            if coordinator.state == .paused {
                coordinator.resumeSession()
                AppLogger.device.info("Simulation resumed after reconnection")
            }
        }
    }

    private func startRetryLoop() {
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled && self.retryCount < self.maxRetries && self.isRecovering {
                self.retryCount += 1
                let delay = self.baseDelay * pow(2.0, Double(self.retryCount - 1))
                AppLogger.device.info("Retry \(self.retryCount)/\(self.maxRetries) in \(delay)s")

                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled else { return }

                DeviceManager.shared.connect()
                // Đợi 3s cho kết nối
                try? await Task.sleep(nanoseconds: 3_000_000_000)

                if SpoofEngine.shared.isLoopbackConnected {
                    return // handleReconnect sẽ fire qua observer
                }
            }

            if self.isRecovering {
                AppLogger.device.error("Recovery failed after \(self.maxRetries) retries")
                self.isRecovering = false
            }
        }
    }

    func cancelRecovery() {
        retryTask?.cancel()
        isRecovering = false
        retryCount = 0
    }

    deinit {
        networkMonitor?.cancel()
    }
}
