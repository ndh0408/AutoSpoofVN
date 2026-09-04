import SwiftUI

/// Token mau — nguon duy nhat cho moi mau trong app.
///
/// Nguyen tac:
/// 1. **Khong hardcode mau trong view.** Moi mau di qua `AppColor`.
/// 2. **Uu tien mau he thong.** `Color(.systemBlue)` tu dong doi theo Dark/Light,
///    theo "Increase Contrast" va theo "Smart Invert" — mot hex co dinh thi khong.
///    System Blue giai ra `#0A84FF` o Dark va `#007AFF` o Light; System Green giai ra
///    `#30D158` o Dark va `#34C759` o Light — dung hai gia tri ma brief yeu cau.
/// 3. **Dark Mode la trai nghiem chinh**, Light Mode van phai dung hoan toan.
///
/// Ten cu (`textPrimary`, `surfaceSecondary`, `divider`...) duoc giu nguyen vi 16 file
/// view hien tai dang dung; ten theo brief (`primaryText`, `secondarySurface`,
/// `separator`, `background`) la alias tro vao cung token.
enum AppColor {

    // MARK: - Brand / Semantic

    /// Mau chu dao. Dark `#0A84FF` · Light `#007AFF`.
    static let primary = Color(.systemBlue)
    /// Nhan phu — dung cho nhan nguon (source badge), khong dung cho hanh dong chinh.
    static let accent = Color(.systemIndigo)
    /// Spoof dang chay / he thong khoe. Dark `#30D158` · Light `#34C759`.
    static let success = Color(.systemGreen)
    /// Canh bao, trang thai tam dung.
    static let warning = Color(.systemOrange)
    /// Loi, hanh dong pha huy.
    static let danger = Color(.systemRed)

    // MARK: - Surfaces

    /// Nen man hinh.
    static let background = Color(.systemBackground)
    /// Nen man hinh — ten cu, giu de khong vo view hien co.
    static let surface = Color(.systemBackground)
    /// Nen the/card noi tren nen man hinh.
    static let surfaceSecondary = Color(.secondarySystemBackground)
    /// Nen lop thu ba (o nhap, chip trong card).
    static let surfaceTertiary = Color(.tertiarySystemBackground)
    /// Alias theo brief.
    static let secondarySurface = Color(.secondarySystemBackground)
    /// Nen cho noi dung dat trong Form/List.
    static let groupedBackground = Color(.systemGroupedBackground)

    // MARK: - Text

    static let textPrimary = Color(.label)
    static let textSecondary = Color(.secondaryLabel)
    static let textTertiary = Color(.tertiaryLabel)
    static let textQuaternary = Color(.quaternaryLabel)
    /// Alias theo brief.
    static let primaryText = Color(.label)
    static let secondaryText = Color(.secondaryLabel)

    // MARK: - Lines & Overlays

    static let divider = Color(.separator)
    /// Alias theo brief.
    static let separator = Color(.separator)
    /// Duong ke dam hon, dung khi can tach hai vung noi dung.
    static let separatorOpaque = Color(.opaqueSeparator)
    /// Lop phu toi sau sheet/dialog.
    static let overlay = Color.black.opacity(0.3)
    /// Vien mo cho control noi tren ban do — giu control tach khoi ban do sang.
    static let hairline = Color.primary.opacity(0.08)

    // MARK: - Trang thai (khong bao gio dung mau MOT MINH de bao trang thai)

    /// Thiet bi da ket noi.
    static let connected = Color(.systemGreen)
    /// Thiet bi chua ket noi — xam trung tinh, khong phai do.
    static let disconnected = Color(.secondaryLabel)
    /// Dang mo phong.
    static let simulating = Color(.systemBlue)
    /// Tam dung.
    static let paused = Color(.systemOrange)
    /// Loi.
    static let error = Color(.systemRed)

    // MARK: - Ban do

    /// Vet duong da di qua.
    static let mapTrail = Color(.systemBlue)
    /// Duong bay du kien.
    static let mapFlightPath = Color(.systemTeal)
    /// Tuyen duong da tinh san.
    static let mapRoute = Color(.systemIndigo)
}

// MARK: - Anh xa trang thai -> mau

extension SimulationState {
    /// Mau ngu nghia cho trang thai mo phong.
    /// Luon di kem icon + chu: khong bao gio chi dua vao mau (WCAG 1.4.1).
    var tint: Color {
        switch self {
        case .idle:      return AppColor.textSecondary
        case .preparing: return AppColor.primary
        case .running:   return AppColor.success
        case .paused:    return AppColor.warning
        case .stopping:  return AppColor.warning
        case .completed: return AppColor.success
        case .failed:    return AppColor.danger
        }
    }

    /// Icon SF Symbol di kem — phan bu cho nguoi khong phan biet duoc mau.
    var symbolName: String {
        switch self {
        case .idle:      return "circle"
        case .preparing: return "circle.dotted"
        case .running:   return "location.fill"
        case .paused:    return "pause.fill"
        case .stopping:  return "stop.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed:    return "exclamationmark.triangle.fill"
        }
    }
}

extension DeviceConnectionState {
    var tint: Color {
        switch self {
        case .disconnected: return AppColor.disconnected
        case .connecting:   return AppColor.warning
        case .connected:    return AppColor.connected
        case .error:        return AppColor.danger
        }
    }
}

extension SystemHealth.Status {
    var tint: Color {
        switch self {
        case .healthy: return AppColor.success
        case .warning: return AppColor.warning
        case .error:   return AppColor.danger
        case .unknown: return AppColor.textTertiary
        }
    }
}
