import Combine
import Foundation
import SwiftUI

/// Kho cài đặt ứng dụng — nguồn duy nhất mà cả giao diện lẫn engine đọc.
///
/// Trước đây `AppSettings` chỉ được `SettingsView` nạp vào một `@State` cục bộ rồi ghi
/// xuống UserDefaults. **Không engine nào đọc lại.** Kết quả: 11 trong 13 tuỳ chọn là
/// công tắc giả — người dùng bật/tắt, giá trị được lưu, và không có gì thay đổi. Kho này
/// vừa giữ giá trị, vừa **áp** chúng xuống các hệ thống thật.
///
/// Lưu ý về thứ tự khởi tạo: `init` chỉ đọc UserDefaults, **không** chạm singleton nào
/// khác. Việc áp cấu hình nằm ở `apply()` và được gọi tường minh lúc bootstrap — chạm
/// singleton chéo trong `init` là cách nhanh nhất để tạo khoá chết `swift_once`.
@MainActor
final class AppSettingsStore: ObservableObject {
    static let shared = AppSettingsStore()

    @Published var settings: PersistenceManager.AppSettings {
        didSet {
            PersistenceManager.shared.saveSettings(settings)
            apply()
        }
    }

    private init() {
        settings = PersistenceManager.shared.loadSettings()
    }

    // MARK: - Áp cấu hình xuống hệ thống

    /// Đẩy mọi tuỳ chọn tới nơi thực sự dùng chúng.
    ///
    /// Gọi lúc bootstrap và mỗi lần người dùng đổi cài đặt.
    func apply() {
        let s = settings

        // Nhiễu GPS — coordinator sở hữu, áp một lần lúc gửi toạ độ ra thiết bị.
        SimulationCoordinator.shared.noiseConfig = s.noiseConfig

        // Nhịp gửi lại toạ độ xuống thiết bị.
        SimulationCoordinator.shared.setDeviceUpdateInterval(s.deviceUpdateIntervalSeconds)

        // Tần số tick của vòng lặp mô phỏng tuyến.
        RouteSimulator.shared.setTickInterval(s.simulationTickIntervalSeconds)

        // Đường truyền: tự bật lại VPN và nhịp đo trạng thái Shadowrocket.
        ShadowrocketManager.shared.configureMonitoring(
            autoReactivateVPN: s.autoReconnect,
            pollInterval: max(5, s.heartbeatIntervalSeconds))

        // Chạy nền.
        if s.backgroundKeepAlive {
            BackgroundKeeper.shared.start()
        } else {
            BackgroundKeeper.shared.stop()
        }
    }

    // MARK: - Truy cập tiện lợi

    /// Giao diện sáng/tối do người dùng chọn. `nil` = theo hệ thống.
    var preferredColorScheme: ColorScheme? {
        switch settings.appearance {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }

    var showsDeveloperInfo: Bool { settings.showDeveloperInfo }

    var mapStyleKind: MapStyleKind {
        get { MapStyleKind(rawValue: settings.mapStyle) ?? .standard }
        set { settings.mapStyle = newValue.rawValue }
    }

    var defaultTravelMode: TravelMode {
        TravelMode(rawValue: settings.defaultTravelMode.rawValue) ?? .driving
    }
}

// MARK: - Đổi Hz sang khoảng thời gian

extension PersistenceManager.AppSettings {
    /// Khoảng cách giữa hai lần gửi lại toạ độ xuống thiết bị, tính bằng giây.
    ///
    /// Giá trị lưu là Hz. Kẹp trong 0.2–60 s: nhanh hơn nữa thì spam kênh DVT, chậm hơn
    /// nữa thì phiên bị coi là chết.
    var deviceUpdateIntervalSeconds: TimeInterval {
        guard deviceUpdateRateHz > 0 else { return 20 }
        return min(60, max(0.2, 1.0 / deviceUpdateRateHz))
    }

    /// Khoảng cách giữa hai tick của vòng lặp mô phỏng, tính bằng giây.
    /// Kẹp trong 0.02–1 s (tức 1–50 Hz).
    var simulationTickIntervalSeconds: TimeInterval {
        guard simulationTickRateHz > 0 else { return 0.1 }
        return min(1.0, max(0.02, 1.0 / simulationTickRateHz))
    }
}
