import SwiftUI

/// Thiết lập Shadowrocket.
///
/// Bản trước là năm ô tick người dùng **tự đánh dấu** (`bypass_step1..5` trong
/// `@AppStorage`). App tin lời khai đó, kể cả khi bước ấy thất bại — nên checklist xanh
/// hết mà spoof vẫn không chạy, và không có gì chỉ ra chỗ hỏng.
///
/// Bản này chỉ hiển thị thứ **kiểm chứng được**:
///
/// | Tín hiệu | Bằng chứng |
/// |---|---|
/// | Đã cài Shadowrocket | `canOpenURL("shadowrocket://")` |
/// | Server toạ độ đang chạy | `CoordinateServer.isRunning` |
/// | Module đã nạp | Shadowrocket **tự tìm tới** CoordinateServer lấy module/script |
/// | Toàn tuyến đang chạy | Shadowrocket vừa fetch script trong vài phút gần đây |
///
/// Tín hiệu cuối là quan trọng nhất: Shadowrocket chỉ fetch được script khi VPN đã bật,
/// HTTPS Decryption đã mở **và** chứng chỉ đã được tin cậy. Một tín hiệu đó chứng minh cả
/// ba bước mà app không thể kiểm tra trực tiếp.
struct ShadowrocketSetupScreen: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var manager = ShadowrocketManager.shared
    @ObservedObject private var coordServer = CoordinateServer.shared

    @State private var copied: String?
    @State private var showTroubleshoot = false

    private let moduleURLGitHub = "https://raw.githubusercontent.com/ndh0408/LocationX/main/Proxy/locationx.sgmodule"

    var body: some View {
        NavigationStack {
            List {
                statusSection
                stepsSection
                endpointsSection
                troubleshootSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle(L("shadowrocket.setup"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("action.close")) { dismiss() }
                }
            }
            .sheet(isPresented: $showTroubleshoot) {
                BypassTroubleshootView()
            }
        }
    }

    // MARK: - Trạng thái tổng

    private var statusSection: some View {
        Section {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: overall.symbol)
                        .font(.system(size: 22))
                        .foregroundStyle(overall.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(overall.title)
                            .font(AppFont.headlineEmphasized)
                            .foregroundStyle(AppColor.textPrimary)
                        Text(manager.statusMessage)
                            .font(AppFont.caption1)
                            .foregroundStyle(AppColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }

                // Bốn tín hiệu, mỗi cái là một sự thật kiểm chứng được.
                VStack(spacing: AppSpacing.xs) {
                    SignalRow(label: L("shadowrocket.signal.installed"),
                              isOn: manager.isInstalled)
                    SignalRow(label: L("shadowrocket.signal.server"),
                              isOn: coordServer.isRunning)
                    SignalRow(label: L("shadowrocket.signal.module"),
                              isOn: manager.isModuleImported)
                    SignalRow(label: L("shadowrocket.signal.traffic"),
                              isOn: manager.isPipelineFresh,
                              detail: coordServer.requestCount > 0
                                  ? L("shadowrocket.signal.requests", coordServer.requestCount)
                                  : nil)
                }
            }
            .padding(.vertical, AppSpacing.xs)
        } header: {
            Text(L("shadowrocket.section.status"))
        } footer: {
            Text(L("shadowrocket.status.footer"))
        }
    }

    private enum Overall {
        case notInstalled, needModule, noTraffic, running

        var title: String {
            switch self {
            case .notInstalled: return L("shadowrocket.overall.not_installed")
            case .needModule:   return L("shadowrocket.overall.need_module")
            case .noTraffic:    return L("shadowrocket.overall.no_traffic")
            case .running:      return L("shadowrocket.overall.running")
            }
        }

        var symbol: String {
            switch self {
            case .notInstalled: return "arrow.down.app"
            case .needModule:   return "puzzlepiece.extension"
            case .noTraffic:    return "exclamationmark.triangle.fill"
            case .running:      return "checkmark.shield.fill"
            }
        }

        var tint: Color {
            switch self {
            case .notInstalled: return AppColor.danger
            case .needModule:   return AppColor.warning
            case .noTraffic:    return AppColor.warning
            case .running:      return AppColor.success
            }
        }
    }

    private var overall: Overall {
        if !manager.isInstalled { return .notInstalled }
        if !manager.isModuleImported { return .needModule }
        return manager.isPipelineFresh ? .running : .noTraffic
    }

    // MARK: - Các bước

    private var stepsSection: some View {
        Section {
            // 1 — kiểm chứng được
            SetupStep(number: 1,
                      title: L("shadowrocket.step1.title"),
                      detail: L("shadowrocket.step1.detail"),
                      state: manager.isInstalled ? .done : .todo,
                      actionTitle: manager.isInstalled ? nil : L("shadowrocket.step1.action")) {
                manager.openAppStore()
            }

            // 2 — kiểm chứng được
            SetupStep(number: 2,
                      title: L("shadowrocket.step2.title"),
                      detail: L("shadowrocket.step2.detail"),
                      state: manager.isModuleImported ? .done
                          : (manager.didAttemptImport ? .waiting : .todo),
                      actionTitle: L("shadowrocket.step2.action"),
                      isEnabled: manager.isInstalled) {
                manager.importModule()
            }

            // 3–5 — app KHÔNG kiểm tra trực tiếp được, nên trình bày là hướng dẫn.
            // Chúng được chứng minh gián tiếp bởi tín hiệu "có lưu lượng" ở trên.
            SetupStep(number: 3,
                      title: L("shadowrocket.step3.title"),
                      detail: L("shadowrocket.step3.detail"),
                      state: .instruction,
                      actionTitle: L("shadowrocket.action.open_app"),
                      isEnabled: manager.isInstalled) {
                manager.openShadowrocketToConnect()
            }

            SetupStep(number: 4,
                      title: L("shadowrocket.step4.title"),
                      detail: L("shadowrocket.step4.detail"),
                      state: .instruction,
                      actionTitle: L("shadowrocket.step4.action")) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }

            SetupStep(number: 5,
                      title: L("shadowrocket.step5.title"),
                      detail: L("shadowrocket.step5.detail"),
                      state: manager.isPipelineFresh ? .done : .instruction,
                      actionTitle: L("shadowrocket.action.open_app"),
                      isEnabled: manager.isInstalled) {
                manager.openShadowrocketToConnect()
            }
            // 6 — meo bat buoc khi o ngoai troi. Man hinh cu co buoc nay ("Airplane
            // trick"); bo di la mat mot thu that su can, vi ngoai troi tin hieu GPS ve tinh
            // lan at va vi tri that se thang.
            SetupStep(number: 6,
                      title: L("shadowrocket.step6.title"),
                      detail: L("shadowrocket.step6.detail"),
                      state: .instruction,
                      actionTitle: nil) {}
        } header: {
            Text(L("shadowrocket.section.steps"))
        } footer: {
            Text(L("shadowrocket.steps.footer"))
        }
    }

    // MARK: - Endpoint

    private var endpointsSection: some View {
        Section {
            EndpointRow(path: "/coord", desc: L("shadowrocket.endpoint.coord"),
                        copied: $copied)
            EndpointRow(path: "/location-spoofer.js", desc: L("shadowrocket.endpoint.spoofer"),
                        copied: $copied)
            EndpointRow(path: "/locationx.sgmodule", desc: L("shadowrocket.endpoint.module"),
                        copied: $copied)
            EndpointRow(path: "/status", desc: L("shadowrocket.endpoint.status"),
                        copied: $copied)

            Button {
                UIPasteboard.general.string = moduleURLGitHub
                copied = moduleURLGitHub
                AppHaptics.selection()
            } label: {
                Label(L("shadowrocket.copy_github_url"), systemImage: "doc.on.doc")
            }
        } header: {
            Text(L("shadowrocket.section.endpoints"))
        } footer: {
            Text(L("shadowrocket.endpoints.footer"))
        }
    }

    // MARK: - Khắc phục

    private var troubleshootSection: some View {
        Section {
            Button {
                // Sheet CỤC BỘ, không đi qua navigator: navigator chỉ giữ một sheet tại một
                // thời điểm, nên mở qua nó sẽ ĐÓNG chính màn hình này rồi mới mở màn kia.
                showTroubleshoot = true
            } label: {
                Label(L("shadowrocket.troubleshoot"), systemImage: "questionmark.circle")
            }

            Button(role: .destructive) {
                manager.resetSetup()
                AppHaptics.warning()
            } label: {
                Label(L("shadowrocket.reset"), systemImage: "arrow.counterclockwise")
            }
        } header: {
            Text(L("shadowrocket.section.help"))
        } footer: {
            Text(L("shadowrocket.help.footer"))
        }
    }
}

// MARK: - Thành phần

/// Một tín hiệu kiểm chứng được: bật/tắt, kèm icon và chữ (không chỉ dựa vào màu).
private struct SignalRow: View {
    let label: String
    let isOn: Bool
    var detail: String?

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 15))
                .foregroundStyle(isOn ? AppColor.success : AppColor.textQuaternary)
            Text(label)
                .font(AppFont.footnote)
                .foregroundStyle(isOn ? AppColor.textPrimary : AppColor.textSecondary)
            Spacer(minLength: AppSpacing.sm)
            if let detail {
                Text(detail)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(isOn ? L("common.yes") : L("common.no"))")
    }
}

/// Một bước hướng dẫn.
private struct SetupStep: View {
    enum State {
        /// Chưa làm, và app kiểm chứng được khi xong.
        case todo
        /// Đã xong, có bằng chứng.
        case done
        /// Đã bấm nhưng chưa có bằng chứng.
        case waiting
        /// App không kiểm tra trực tiếp được — chỉ là hướng dẫn.
        case instruction
    }

    let number: Int
    let title: String
    let detail: String
    let state: State
    var actionTitle: String?
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(alignment: .top, spacing: AppSpacing.md) {
                badge
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppFont.calloutEmphasized)
                        .foregroundStyle(AppColor.textPrimary)
                    Text(detail)
                        .font(AppFont.caption1)
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            if let actionTitle {
                Button(actionTitle, action: action)
                    .buttonStyle(.appSecondary(.compact))
                    .disabled(!isEnabled)
                    .padding(.leading, 34)
            }
        }
        .padding(.vertical, AppSpacing.xxs)
        .accessibilityElement(children: .contain)
    }

    private var badge: some View {
        ZStack {
            Circle()
                .fill(state == .done ? AppColor.success : AppColor.surfaceTertiary)
                .frame(width: 24, height: 24)
            if state == .done {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            } else if state == .waiting {
                ProgressView().controlSize(.mini)
            } else {
                Text("\(number)")
                    .font(AppFont.caption.weight(.bold))
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
    }
}

/// Một endpoint của CoordinateServer: chạm để mở, giữ để chép URL.
private struct EndpointRow: View {
    let path: String
    let desc: String
    @Binding var copied: String?

    private var url: String { "http://127.0.0.1:8765" + path }

    var body: some View {
        Button {
            if let link = URL(string: url) { UIApplication.shared.open(link) }
        } label: {
            HStack(spacing: AppSpacing.md) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(path)
                        .font(AppFont.monoFootnote)
                        .foregroundStyle(AppColor.primary)
                    Text(desc)
                        .font(AppFont.caption1)
                        .foregroundStyle(AppColor.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                if copied == url {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColor.success)
                } else {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 13))
                        .foregroundStyle(AppColor.textQuaternary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                UIPasteboard.general.string = url
                copied = url
            } label: {
                Label(L("common.copy"), systemImage: "doc.on.doc")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(path). \(desc)")
    }
}
