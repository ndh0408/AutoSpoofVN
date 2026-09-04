import SwiftUI

// MARK: - AppCard

/// The noi dung dac tren nen man hinh. API giu nguyen tu ban dau.
struct AppCard<Content: View>: View {
    var padding: CGFloat = AppSpacing.lg
    var radius: CGFloat = AppRadius.card
    let content: Content

    init(padding: CGFloat = AppSpacing.lg,
         radius: CGFloat = AppRadius.card,
         @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.radius = radius
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(AppColor.surfaceSecondary,
                        in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

// MARK: - GlassCard

/// The trong suot cho noi dung noi TREN ban do.
///
/// Chi dung khi thuc su co ban do phia sau — dat len nen dac thi kinh khong them gi
/// ngoai viec lam chu kho doc hon.
struct GlassCard<Content: View>: View {
    var padding: CGFloat = AppSpacing.lg
    var radius: CGFloat = AppRadius.card
    var material: Material = AppMaterial.sheet
    let content: Content

    init(padding: CGFloat = AppSpacing.lg,
         radius: CGFloat = AppRadius.card,
         material: Material = AppMaterial.sheet,
         @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.radius = radius
        self.material = material
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .glassSurface(radius: radius, material: material, shadow: AppShadow.card)
    }
}

// MARK: - SectionHeader

/// Tieu de nhom, kem hanh dong phu tuy chon o ben phai.
struct SectionHeader<Accessory: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(title)
                    .font(AppFont.headlineEmphasized)
                    .foregroundStyle(AppColor.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(AppFont.footnote)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
            Spacer(minLength: AppSpacing.sm)
            accessory
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isHeader)
    }
}

extension SectionHeader where Accessory == EmptyView {
    init(_ title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

// MARK: - Divider

/// Duong ke mong dung trong the — mong hon `Divider()` mac dinh.
struct HairlineDivider: View {
    var inset: CGFloat = 0

    /// `displayScale` tu environment — `UIScreen.main` da deprecated va sai tren
    /// man hinh ngoai/Stage Manager.
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle()
            .fill(AppColor.separator)
            .frame(height: 1 / max(1, displayScale))
            .padding(.leading, inset)
            .accessibilityHidden(true)
    }
}

#Preview("Cards") {
    VStack(spacing: AppSpacing.lg) {
        AppCard {
            SectionHeader("Phiên hiện tại", subtitle: "Tuyến đường · Ô tô")
        }
        GlassCard {
            Text("Nổi trên bản đồ").font(AppFont.body)
        }
    }
    .padding()
    .background(AppColor.background)
}
