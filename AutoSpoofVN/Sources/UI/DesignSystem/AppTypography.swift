import SwiftUI

/// Token chu — tat ca deu la text style ngu nghia cua Apple nen **Dynamic Type chay san**.
///
/// Khong dat co chu bang so o tang view. Neu can co khac, them token o day.
/// SF Pro Display/Text duoc he thong chon tu dong theo co chu, khong can khai bao font family.
enum AppFont {

    // MARK: - Thang bac chuan

    static let largeTitle = Font.largeTitle
    static let title = Font.title
    static let title2 = Font.title2
    static let title3 = Font.title3
    static let headline = Font.headline
    static let subheadline = Font.subheadline
    static let body = Font.body
    static let callout = Font.callout
    static let footnote = Font.footnote
    /// Luu y: token nay anh xa vao `.caption2` tu ban dau va 56 cho dang dung.
    /// Giu nguyen de khong doi kich thuoc chu tren toan app.
    static let caption = Font.caption2
    /// `.caption` that su cua Apple — lon hon `AppFont.caption` mot bac.
    static let caption1 = Font.caption

    // MARK: - Bien the nhan

    static let headlineEmphasized = Font.headline.weight(.semibold)
    static let calloutEmphasized = Font.callout.weight(.medium)
    static let footnoteEmphasized = Font.footnote.weight(.medium)

    // MARK: - Monospace

    /// Cho chuoi ky thuat (toa do, log).
    static let mono = Font.system(.caption, design: .monospaced)
    static let monoBody = Font.system(.body, design: .monospaced)
    static let monoFootnote = Font.system(.footnote, design: .monospaced)

    // MARK: - So lieu telemetry
    //
    // `monospacedDigit` la chi tiet quan trong: khong co no, con so doi lien tuc
    // (42.1 -> 42.8 -> 43.0) lam ca hang so nhay ngang vi moi chu so mot be rong.

    /// So lieu chinh tren bang telemetry.
    static let metricValue = Font.title2.weight(.semibold).monospacedDigit()
    /// So lieu phu / trong o nho.
    static let metricValueCompact = Font.headline.weight(.semibold).monospacedDigit()
    /// Nhan cua so lieu.
    static let metricLabel = Font.caption2.weight(.medium)
    /// Dong ho, bo dem thoi gian.
    static let timer = Font.subheadline.weight(.medium).monospacedDigit()
}

// MARK: - Tien ich

extension View {
    /// Gioi han bac Dynamic Type cho vung dac biet chat (vi du hang so lieu tren ban do),
    /// nhung VAN cho phong to den `.accessibility1` de khong pha vo kha nang tiep can.
    func constrainedDynamicType() -> some View {
        dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }
}
