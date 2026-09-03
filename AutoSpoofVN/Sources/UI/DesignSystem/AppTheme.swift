import CoreLocation
import SwiftUI

// MARK: - Button styles

/// Nut co phan hoi cham: thu nho nhe va giam do dam khi giu.
///
/// SwiftUI khong cho phan hoi nay san cho `Button` co nhan tuy bien, ma thieu no thi
/// nut cam giac "chet". Ap cho moi control tuy bien trong app.
struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.96
    var dimsOnPress: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed && dimsOnPress ? 0.75 : 1)
            .animation(UIAccessibility.isReduceMotionEnabled ? nil : AppAnimation.snappy,
                       value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
    /// Bien the cho nut lon (hanh dong chinh) — thu nho it hon de khong giat.
    static var pressableLarge: PressableButtonStyle { PressableButtonStyle(scale: 0.98) }
}

// MARK: - Surface modifiers

extension View {
    /// The noi dung chuan: padding + nen phu + bo goc.
    func appCard(padding: CGFloat = AppSpacing.lg,
                 radius: CGFloat = AppRadius.card,
                 background: Color = AppColor.surfaceSecondary) -> some View {
        self.padding(padding)
            .background(background, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    /// Vung cham toi thieu 44x44pt theo HIG — bat buoc cho moi nut chi co icon.
    func minimumTapTarget() -> some View {
        frame(minWidth: AppSpacing.minTapTarget, minHeight: AppSpacing.minTapTarget)
            .contentShape(Rectangle())
    }

    /// Gan nhan VoiceOver cho nut chi co icon.
    func accessibleButton(label: String, hint: String = "") -> some View {
        accessibilityLabel(label)
            .accessibilityHint(hint)
            .accessibilityAddTraits(.isButton)
    }

    /// Animation ton trong Reduce Motion — ten cu, giu cho code hien co.
    func safeAnimation<V: Equatable>(_ value: V, _ animation: Animation = .easeInOut) -> some View {
        self.animation(UIAccessibility.isReduceMotionEnabled ? nil : animation, value: value)
    }
}

// MARK: - Dinh dang so lieu

/// Bo dinh dang dung chung.
///
/// Truoc day moi view tu viet `String(format:)` rieng, nen cung mot quang duong hien
/// "1.2 km" o cho nay va "1234 m" o cho khac. Tap trung vao mot cho de app noi mot giong.
enum AppFormat {

    /// Quang duong: duoi 1 km hien met tron, tu 1 km hien mot chu so thap phan.
    static func distance(_ meters: Double) -> String {
        guard meters.isFinite else { return "—" }
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        }
        return String(format: "%.0f m", max(0, meters))
    }

    /// Toc do.
    static func speed(_ kmh: Double) -> String {
        guard kmh.isFinite else { return "—" }
        return String(format: "%.1f", max(0, kmh))
    }

    /// Do cao.
    static func altitude(_ meters: Double) -> String {
        guard meters.isFinite else { return "—" }
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        }
        return String(format: "%.0f m", max(0, meters))
    }

    /// Thoi luong: `m:ss` duoi mot gio, `h:mm:ss` tu mot gio.
    static func duration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// Toa do dang gon cho thanh trang thai.
    static func coordinate(_ coord: CLLocationCoordinate2D, precision: Int = 5) -> String {
        String(format: "%.\(precision)f, %.\(precision)f", coord.latitude, coord.longitude)
    }

    /// Huong kem chu cai phuong huong tieng Viet.
    static func heading(_ degrees: Double) -> String {
        String(format: "%.0f° %@", degrees, cardinal(degrees))
    }

    /// Phuong huong 8 huong, ky hieu tieng Viet (Bac / Dong / Nam / Tay).
    static func cardinal(_ degrees: Double) -> String {
        let names = ["B", "ĐB", "Đ", "ĐN", "N", "TN", "T", "TB"]
        let normalized = degrees.truncatingRemainder(dividingBy: 360)
        let positive = normalized < 0 ? normalized + 360 : normalized
        let index = Int((positive + 22.5) / 45) % 8
        return names[index]
    }

    /// Gio den du kien.
    static func arrivalTime(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .omitted, time: .shortened)
    }

    /// Phan tram tien do.
    static func percent(_ fraction: Double) -> String {
        guard fraction.isFinite else { return "—" }
        return String(format: "%.0f%%", max(0, min(1, fraction)) * 100)
    }
}

// MARK: - Chuoi hien thi

/// Khoa chuoi tap trung.
///
/// Luu y: app hien **chua** dung `NSLocalizedString` o bat ky dau — `en.lproj`/`vi.lproj`
/// ton tai nhung khong file Swift nao doc chung (xem `docs/UI_AUDIT.md`). Enum nay giu
/// nguyen hanh vi hien tai (chuoi tieng Viet co dinh) va la cho de gan `String(localized:)`
/// khi thuc su da ngon ngu hoa.
enum L10n {
    // Simulation
    static let simulationRunning = "Đang mô phỏng"
    static let simulationPaused = "Tạm dừng"
    static let simulationIdle = "Sẵn sàng"

    // Device
    static let deviceConnected = "Đã kết nối"
    static let deviceDisconnected = "Chưa kết nối"

    // Route
    static let routeDistance = "Khoảng cách"
    static let routeETA = "Dự kiến đến"
    static let routeSource = "Nguồn tuyến"

    // Actions
    static let start = "Bắt đầu"
    static let stop = "Dừng"
    static let pause = "Tạm dừng"
    static let resume = "Tiếp tục"
    static let retry = "Thử lại"
    static let diagnostics = "Chẩn đoán"
    static let cancel = "Huỷ"
    static let close = "Đóng"
    static let done = "Xong"

    // Empty states
    static let noRoutes = "Chưa có tuyến đường"
    static let noRoutesMessage = "Tạo tuyến đường đầu tiên để bắt đầu mô phỏng."
    static let createRoute = "Tạo tuyến"
    static let noDevice = "Chưa kết nối thiết bị"
    static let noDeviceMessage = "Ghép nối iPhone để bắt đầu mô phỏng GPS."

    // Tabs
    static let tabMap = "Bản đồ"
    static let tabRoutes = "Tuyến đường"
    static let tabFlight = "Chuyến bay"
    static let tabSettings = "Cài đặt"
}
