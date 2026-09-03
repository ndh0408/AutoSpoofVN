import Foundation

/// Phát hiện và phục hồi phiên mô phỏng bị gián đoạn (crash, force quit, background kill).
@MainActor
final class AppRecoveryManager: ObservableObject {
    static let shared = AppRecoveryManager()

    @Published var hasPendingRecovery = false
    @Published var pendingSession: RecoveryInfo?

    struct RecoveryInfo: Codable {
        let source: SimulationSource
        let travelMode: TravelMode
        let lastCoordinate: CoordinateCodable
        let lastSpeed: Double
        let elapsedSeconds: TimeInterval
        let timestamp: Date
        let routeName: String?

        var isStale: Bool {
            // Quá 1 giờ thì coi như stale
            Date().timeIntervalSince(timestamp) > 3600
        }
    }

    private let key = "autospoof_recovery_session"

    private init() {
        checkForPendingRecovery()
    }

    /// Lưu trạng thái hiện tại để phục hồi nếu bị gián đoạn.
    func checkpoint() {
        let coordinator = SimulationCoordinator.shared
        guard coordinator.state.isActive, let source = coordinator.activeSource else {
            clearRecovery()
            return
        }

        let info = RecoveryInfo(
            source: source,
            travelMode: coordinator.session?.travelMode ?? .driving,
            lastCoordinate: CoordinateCodable(coordinator.currentCoordinate),
            lastSpeed: coordinator.telemetry.speedKmh,
            elapsedSeconds: coordinator.telemetry.elapsedTime,
            timestamp: Date(),
            routeName: coordinator.session?.routeName
        )

        if let data = try? JSONEncoder().encode(info) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// Phục hồi phiên — đặt lại vị trí cuối, không tự động chạy lại.
    func recover() {
        guard let info = pendingSession, !info.isStale else {
            clearRecovery()
            return
        }

        let coordinator = SimulationCoordinator.shared
        coordinator.setManualLocation(info.lastCoordinate.clCoordinate)
        AppLogger.simulation.info("Recovered session: \(info.source.rawValue) at \(info.lastCoordinate.latitude), \(info.lastCoordinate.longitude)")
        clearRecovery()
    }

    /// Bỏ qua phục hồi.
    func discard() {
        clearRecovery()
    }

    private func checkForPendingRecovery() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let info = try? JSONDecoder().decode(RecoveryInfo.self, from: data),
              !info.isStale
        else {
            clearRecovery()
            return
        }
        pendingSession = info
        hasPendingRecovery = true
    }

    private func clearRecovery() {
        hasPendingRecovery = false
        pendingSession = nil
        UserDefaults.standard.removeObject(forKey: key)
    }
}
