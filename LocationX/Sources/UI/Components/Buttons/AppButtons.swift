import SwiftUI

/// Ba kich thuoc nut dung chung.
enum AppButtonSize {
    /// Cao 50pt — hanh dong chinh cua man hinh.
    case prominent
    /// Cao 44pt — hanh dong thu cap.
    case regular
    /// Cao 36pt — trong the, trong empty state.
    case compact

    var minHeight: CGFloat {
        switch self {
        case .prominent: return 50
        case .regular:   return AppSpacing.minTapTarget
        case .compact:   return 36
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .prominent: return AppSpacing.xl
        case .regular:   return AppSpacing.lg
        case .compact:   return AppSpacing.lg
        }
    }

    var font: Font {
        switch self {
        case .prominent: return AppFont.headlineEmphasized
        case .regular:   return AppFont.calloutEmphasized
        case .compact:   return AppFont.footnoteEmphasized
        }
    }

    var radius: CGFloat {
        switch self {
        case .prominent: return AppRadius.lg
        case .regular:   return AppRadius.md
        case .compact:   return AppRadius.md
        }
    }
}

// MARK: - PrimaryButton

/// Nut hanh dong chinh — nen dac mau chu dao.
struct PrimaryButtonStyle: ButtonStyle {
    var size: AppButtonSize = .regular
    var tint: Color = AppColor.primary
    var fillsWidth: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(size.font)
            .foregroundStyle(.white)
            .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: size.minHeight)
            .padding(.horizontal, size.horizontalPadding)
            .background(tint, in: RoundedRectangle(cornerRadius: size.radius, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(UIAccessibility.isReduceMotionEnabled ? nil : AppAnimation.snappy,
                       value: configuration.isPressed)
    }
}

/// Nut thu cap — nen mo cua mau chu dao, chu mau chu dao.
struct SecondaryButtonStyle: ButtonStyle {
    var size: AppButtonSize = .regular
    var tint: Color = AppColor.primary
    var fillsWidth: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(size.font)
            .foregroundStyle(tint)
            .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: size.minHeight)
            .padding(.horizontal, size.horizontalPadding)
            .background(tint.opacity(0.14),
                        in: RoundedRectangle(cornerRadius: size.radius, style: .continuous))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(UIAccessibility.isReduceMotionEnabled ? nil : AppAnimation.snappy,
                       value: configuration.isPressed)
    }
}

/// Nut pha huy.
struct DestructiveButtonStyle: ButtonStyle {
    var size: AppButtonSize = .regular
    var filled: Bool = false
    var fillsWidth: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(size.font)
            .foregroundStyle(filled ? .white : AppColor.danger)
            .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: size.minHeight)
            .padding(.horizontal, size.horizontalPadding)
            .background(filled ? AppColor.danger : AppColor.danger.opacity(0.14),
                        in: RoundedRectangle(cornerRadius: size.radius, style: .continuous))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(UIAccessibility.isReduceMotionEnabled ? nil : AppAnimation.snappy,
                       value: configuration.isPressed)
    }
}

// MARK: - Cach dung tien loi

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var appPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
    static func appPrimary(_ size: AppButtonSize, fillsWidth: Bool = false) -> PrimaryButtonStyle {
        PrimaryButtonStyle(size: size, fillsWidth: fillsWidth)
    }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var appSecondary: SecondaryButtonStyle { SecondaryButtonStyle() }
    static func appSecondary(_ size: AppButtonSize, fillsWidth: Bool = false) -> SecondaryButtonStyle {
        SecondaryButtonStyle(size: size, fillsWidth: fillsWidth)
    }
}

extension ButtonStyle where Self == DestructiveButtonStyle {
    static var appDestructive: DestructiveButtonStyle { DestructiveButtonStyle() }
    static func appDestructive(_ size: AppButtonSize, filled: Bool = false,
                               fillsWidth: Bool = false) -> DestructiveButtonStyle {
        DestructiveButtonStyle(size: size, filled: filled, fillsWidth: fillsWidth)
    }
}

// MARK: - IconButton

/// Nut chi co icon, nen kinh — hinh dang chuan cua control noi tren ban do.
///
/// **Bat buoc co `label`**: day la text VoiceOver doc. Mot nut chi co icon khong nhan
/// la mot nut nguoi dung VoiceOver khong dung duoc.
struct IconButton: View {
    let systemImage: String
    let label: String
    var hint: String = ""
    var tint: Color = AppColor.textPrimary
    var isActive: Bool = false
    var size: CGFloat = AppSpacing.floatingControlSize
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(isActive ? AppColor.primary : tint)
                .frame(width: size, height: size)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibleButton(label: label, hint: hint)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}

#Preview("Buttons") {
    VStack(spacing: AppSpacing.lg) {
        Button("Bắt đầu mô phỏng") {}
            .buttonStyle(.appPrimary(.prominent, fillsWidth: true))
        Button("Tạm dừng") {}
            .buttonStyle(.appSecondary(.regular, fillsWidth: true))
        Button("Dừng hẳn") {}
            .buttonStyle(.appDestructive(.regular, fillsWidth: true))
        HStack(spacing: AppSpacing.sm) {
            IconButton(systemImage: "location.fill", label: "Về vị trí hiện tại") {}
                .glassSurface()
            IconButton(systemImage: "map", label: "Đổi kiểu bản đồ", isActive: true) {}
                .glassSurface()
        }
    }
    .padding()
}
