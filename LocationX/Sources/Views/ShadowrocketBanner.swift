import SwiftUI

/// Banner hiện trên MainViewV2 khi Shadowrocket chưa setup hoặc VPN chưa bật.
///
/// Trạng thái:
/// - Chưa cài Shadowrocket → "Cài Shadowrocket" + link App Store
/// - Cài rồi, chưa import module → "Cài module" + one-tap import
/// - Module imported, VPN tắt → "Bật VPN" + auto-open Shadowrocket
/// - VPN bật → banner tự ẩn
struct ShadowrocketBanner: View {
    @ObservedObject var manager: ShadowrocketManager
    let onOpenSetup: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(iconColor)
                .frame(width: 32)

            // Cham vao vung chu -> mo huong dan day du. Truoc day `onOpenSetup` duoc
            // khai bao va truyen vao nhung khong noi nao trong banner goi den, nen
            // duong vao ShadowrocketSetupView tu banner la duong chet.
            Button(action: onOpenSetup) {
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text(title)
                        .font(AppFont.callout.weight(.semibold))
                        .foregroundStyle(AppColor.textPrimary)
                    Text(manager.statusMessage)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(L("a11y.shadowrocket.open_setup"))

            Button(action: primaryAction) {
                Text(buttonTitle)
                    .font(AppFont.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, AppSpacing.sm)
                    .background(buttonColor)
                    .clipShape(Capsule())
            }
        }
        .padding(AppSpacing.md)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
    }

    // MARK: - Computed

    private var title: String {
        if !manager.isInstalled { return L("shadowrocket.banner.need_app") }
        if !manager.isModuleImported { return L("shadowrocket.banner.import_module") }
        if !manager.isVPNActive { return L("shadowrocket.banner.enable_vpn") }
        return L("shadowrocket.banner.ready")
    }

    private var icon: String {
        if !manager.isInstalled { return "arrow.down.app" }
        if !manager.isModuleImported { return "puzzlepiece.extension" }
        if !manager.isVPNActive { return "bolt.horizontal" }
        return "checkmark.shield"
    }

    private var iconColor: Color {
        if manager.isReady { return .green }
        if !manager.isInstalled { return .red }
        return .orange
    }

    private var buttonTitle: String {
        if !manager.isInstalled { return L("shadowrocket.banner.action.install") }
        if !manager.isModuleImported { return L("shadowrocket.banner.action.import") }
        if !manager.isVPNActive { return L("shadowrocket.banner.enable_vpn") }
        return "OK"
    }

    private var buttonColor: Color {
        if !manager.isInstalled { return .blue }
        return AppColor.primary
    }

    private func primaryAction() {
        if !manager.isInstalled {
            manager.openAppStore()
        } else if !manager.isModuleImported {
            manager.importModule()
        } else if !manager.isVPNActive {
            manager.openShadowrocketToConnect()
        } else {
            manager.markSetupCompleted()
        }
    }
}
