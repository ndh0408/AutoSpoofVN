import SwiftUI

/// Token vat lieu (translucent / "Liquid Glass").
///
/// Nguyen tac: **kinh phai co muc dich**. Chi dung khi co thu that su nam BEN DUOI
/// can duoc cam nhan — control noi tren ban do, thanh trang thai de ban do troi qua.
/// Dat kinh len nen dac chi lam giam do tuong phan ma khong them thong tin gi.
enum AppMaterial {
    /// Control noi tren ban do. Mong nhat — ban do van doc duoc phia sau.
    static let floating: Material = .ultraThinMaterial
    /// Thanh trang thai tren cung, panel phu tren ban do.
    static let bar: Material = .thinMaterial
    /// Bottom sheet — day hon vi chua noi dung can doc ky.
    static let sheet: Material = .regularMaterial
    /// Lop chan tuong tac phia sau dialog.
    static let scrim: Material = .ultraThinMaterial
}

extension View {
    /// Nen vat lieu + bo goc + vien toc — hinh dang chuan cua moi control noi tren ban do.
    ///
    /// Vien toc (`hairline`) quan trong hon ve ngoai: tren anh ve tinh sang, mot the
    /// `.ultraThinMaterial` khong vien gan nhu bien mat.
    func glassSurface(radius: CGFloat = AppRadius.control,
                      material: Material = AppMaterial.floating,
                      shadow: AppShadow.Style? = AppShadow.floating) -> some View {
        background(material, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(AppColor.hairline, lineWidth: 0.5)
            )
            .modifier(OptionalShadow(style: shadow))
    }

    /// Bien the capsule cua `glassSurface`.
    func glassCapsule(material: Material = AppMaterial.floating,
                      shadow: AppShadow.Style? = AppShadow.floating) -> some View {
        background(material, in: Capsule(style: .continuous))
            .overlay(Capsule(style: .continuous).strokeBorder(AppColor.hairline, lineWidth: 0.5))
            .modifier(OptionalShadow(style: shadow))
    }
}

/// Cho phep truyen `nil` de tat bong ma khong can hai nhanh view rieng.
private struct OptionalShadow: ViewModifier {
    let style: AppShadow.Style?

    func body(content: Content) -> some View {
        if let style {
            content.shadow(color: style.color, radius: style.radius, x: style.x, y: style.y)
        } else {
            content
        }
    }
}
