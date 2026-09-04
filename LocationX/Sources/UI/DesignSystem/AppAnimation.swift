import SwiftUI

/// Token chuyen dong.
///
/// Chuyen dong phai **noi mot dieu gi do**: trang thai vua doi, thu bac vua thay doi,
/// tien do dang chay. Khong animate moi thu — chuyen dong khap noi lam giao dien
/// cham chap va on ao.
///
/// Moi token deu ton trong "Reduce Motion" khi goi qua `.appAnimation(_:value:)`.
enum AppAnimation {
    /// Doi trang thai tuc thi (nut bam, badge doi mau).
    static let snappy = Animation.snappy(duration: 0.25, extraBounce: 0)
    /// Chuyen canh muot (sheet mo rong, panel xuat hien).
    static let smooth = Animation.smooth(duration: 0.35)
    /// Nhan nha — dung cho thay doi it quan trong (camera ban do troi).
    static let gentle = Animation.easeInOut(duration: 0.45)
    /// Co do nay nhe — chi cho hanh dong chinh (Start/Stop) de tao cam giac vat ly.
    static let spring = Animation.spring(response: 0.38, dampingFraction: 0.78)
    /// Keo bottom sheet.
    static let sheetDrag = Animation.interactiveSpring(response: 0.32, dampingFraction: 0.86)
    /// Nhip dap cua chi bao "dang chay".
    static let pulse = Animation.easeInOut(duration: 1.1).repeatForever(autoreverses: true)
}

extension View {
    /// Animation co ton trong Reduce Motion.
    ///
    /// Doc `UIAccessibility.isReduceMotionEnabled` tai thoi diem dung view. Voi cac cho
    /// can phan ung ngay khi nguoi dung doi cai dat giua chung, dung
    /// `@Environment(\.accessibilityReduceMotion)` truc tiep trong view.
    func appAnimation<V: Equatable>(_ animation: Animation, value: V) -> some View {
        self.animation(UIAccessibility.isReduceMotionEnabled ? nil : animation, value: value)
    }
}

/// Chay mot khoi thay doi state kem animation, tu dong bo qua khi Reduce Motion bat.
@MainActor
func withAppAnimation<Result>(_ animation: Animation = AppAnimation.snappy,
                              _ body: () throws -> Result) rethrows -> Result {
    if UIAccessibility.isReduceMotionEnabled {
        return try body()
    }
    return try withAnimation(animation, body)
}

// MARK: - Haptics

/// Phan hoi rung — dung cho hanh dong CO HAU QUA, khong dung cho moi cham.
///
/// Bo qua im lang khi thiet bi khong ho tro (iPad/simulator) — `UIFeedbackGenerator`
/// tu xu ly, khong can kiem tra.
enum AppHaptics {
    /// Bat dau mo phong — hanh dong chinh.
    @MainActor static func start() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Dung mo phong.
    @MainActor static func stop() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }

    /// Tam dung / tiep tuc.
    @MainActor static func toggle() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Hanh dong that bai hoac bi tu choi.
    @MainActor static func failure() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    /// Canh bao — hanh dong se ghi de mot phien dang chay.
    @MainActor static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    /// Chon mot muc trong danh sach / doi che do.
    @MainActor static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
