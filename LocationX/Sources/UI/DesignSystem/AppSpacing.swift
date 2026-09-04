import SwiftUI

/// Thang khoang cach 4pt. Moi padding/spacing trong app lay tu day.
///
/// Khong dat so le (13, 18, 22...) trong view: mot thang nhat quan la thu phan biet
/// giao dien "co he thong" voi giao dien "moi cho mot kieu".
enum AppSpacing {
    /// 2 — khe giua nhan va gia tri trong cung mot cum.
    static let xxs: CGFloat = 2
    /// 4 — khe giua icon va chu.
    static let xs: CGFloat = 4
    /// 8 — khe giua cac phan tu lien quan chat.
    static let sm: CGFloat = 8
    /// 12 — padding trong control, khe giua cac hang.
    static let md: CGFloat = 12
    /// 16 — padding chuan cua card va le man hinh.
    static let lg: CGFloat = 16
    /// 20 — khe giua cac cum trong mot the.
    static let xl: CGFloat = 20
    /// 24 — khe giua cac section.
    static let xxl: CGFloat = 24
    /// 32 — khoang tho cho empty state.
    static let xxxl: CGFloat = 32

    // MARK: - Hang so bo cuc

    /// Le ngang chuan cua noi dung so voi canh man hinh.
    static let screenMargin: CGFloat = 16
    /// Kich thuoc cham toi thieu theo HIG (44x44pt).
    static let minTapTarget: CGFloat = 44
    /// Canh cua nut noi tren ban do.
    static let floatingControlSize: CGFloat = 44
}

/// Token bo goc.
///
/// Chi 5 gia tri. Ban kinh khong nhat quan (10 cho o nay, 13 cho o kia) la mot trong
/// nhung thu de lam giao dien trong "lam tay" nhat.
enum AppRadius {
    /// 6 — chip, badge vuong nho.
    static let sm: CGFloat = 6
    /// 10 — nut, o nhap.
    static let md: CGFloat = 10
    /// 14 — the noi dung.
    static let lg: CGFloat = 14
    /// 20 — sheet, panel lon.
    static let xl: CGFloat = 20
    /// 28 — bottom sheet keo duoc.
    static let xxl: CGFloat = 28
    /// Bo tron hoan toan (capsule).
    static let full: CGFloat = 100

    // MARK: - Bi danh theo vai tro

    static let control: CGFloat = md
    static let card: CGFloat = lg
    static let sheet: CGFloat = xxl
}

/// Token do noi (shadow).
///
/// Dung RAT tiet che: chi de tach lop noi (control tren ban do, sheet tren noi dung)
/// khoi nen. Bong do khap noi la dau hieu cua giao dien "Dribbble", khong phai iOS.
enum AppShadow {
    struct Style {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }

    /// Nut noi tren ban do — bong rat nhe, chi du de tach khoi dia hinh sang.
    static let floating = Style(color: .black.opacity(0.12), radius: 6, x: 0, y: 2)
    /// The noi dung tren nen man hinh.
    static let card = Style(color: .black.opacity(0.06), radius: 10, x: 0, y: 3)
    /// Bottom sheet — bong huong len tren.
    static let sheet = Style(color: .black.opacity(0.14), radius: 20, x: 0, y: -6)
}

extension View {
    /// Ap mot token bong do.
    func appShadow(_ style: AppShadow.Style) -> some View {
        shadow(color: style.color, radius: style.radius, x: style.x, y: style.y)
    }
}
