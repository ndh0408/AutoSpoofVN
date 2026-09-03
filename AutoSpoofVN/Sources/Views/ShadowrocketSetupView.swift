import SwiftUI

/// Trung tâm bypass isSimulatedBySoftware — hướng dẫn cài Shadowrocket MITM
/// và theo dõi trạng thái realtime của CoordinateServer.
///
/// Luồng bypass (không cần jailbreak):
///   AutoSpoofVN → DVT (toạ độ) + CoordinateServer (port 8765)
///   Shadowrocket MITM intercept gs-loc.apple.com → trả toạ độ giả như WiFi position
///   iOS: isSimulatedBySoftware = false → Bump accept
struct ShadowrocketSetupView: View {
    @StateObject private var coordServer = CoordinateServer.shared
    @StateObject private var coordinator = SimulationCoordinator.shared
    @Environment(\.dismiss) private var dismiss

    // Bước cài đặt — lưu vào UserDefaults để nhớ giữa các lần mở
    @AppStorage("bypass_step1_module")   private var step1Done = false  // Đã import module
    @AppStorage("bypass_step2_https")    private var step2Done = false  // HTTPS Decryption ON
    @AppStorage("bypass_step3_cert")     private var step3Done = false  // Trust certificate
    @AppStorage("bypass_step4_vpn")      private var step4Done = false  // VPN connect
    @AppStorage("bypass_step5_airplane") private var step5Done = false  // Airplane trick

    @State private var selectedTab: Tab = .setup

    private let moduleURLLive   = "http://127.0.0.1:8765/autospoof.sgmodule"
    private let moduleURLGitHub = "https://raw.githubusercontent.com/ndh0408/AutoSpoofVN/main/Proxy/autospoof-location.sgmodule"

    private var allDone: Bool { step1Done && step2Done && step3Done && step4Done && step5Done }
    private var stepsCompleted: Int { [step1Done,step2Done,step3Done,step4Done,step5Done].filter{$0}.count }

    enum Tab: String, CaseIterable {
        case setup  = "Cài đặt"
        case server = "Server"
        case howto  = "Cơ chế"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // MARK: Hero status card
                heroCard
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.top, AppSpacing.lg)
                    .padding(.bottom, AppSpacing.md)

                // MARK: Tab bar
                tabBar
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.bottom, AppSpacing.sm)

                Divider()

                // MARK: Content
                ScrollView {
                    VStack(spacing: AppSpacing.xl) {
                        switch selectedTab {
                        case .setup:  setupTab
                        case .server: serverTab
                        case .howto:  howtoTab
                        }
                    }
                    .padding(AppSpacing.lg)
                }
            }
            .navigationTitle("Bypass GPS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Đóng") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if allDone {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
            .onAppear {
                if !coordServer.isRunning { coordServer.start() }
            }
        }
    }

    // MARK: - Hero Card

    private var heroCard: some View {
        AppCard {
            VStack(spacing: AppSpacing.md) {
                // Top row: icon + status
                HStack(spacing: AppSpacing.md) {
                    ZStack {
                        Circle()
                            .fill(bypassColor.opacity(0.15))
                            .frame(width: 52, height: 52)
                        Image(systemName: bypassIcon)
                            .font(.title2)
                            .foregroundStyle(bypassColor)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(bypassTitle)
                            .font(AppFont.headline)
                        Text(bypassSubtitle)
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    }

                    Spacer()

                    // Progress ring
                    ZStack {
                        Circle()
                            .stroke(AppColor.surfaceSecondary, lineWidth: 3)
                            .frame(width: 40, height: 40)
                        Circle()
                            .trim(from: 0, to: CGFloat(stepsCompleted) / 5.0)
                            .stroke(bypassColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .frame(width: 40, height: 40)
                            .rotationEffect(.degrees(-90))
                        Text("\(stepsCompleted)/5")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(bypassColor)
                    }
                }

                Divider()

                // Bottom row: live coord + server
                HStack {
                    LiveMetric(
                        icon: "location.fill",
                        label: "Toạ độ giả",
                        value: coordServer.isRunning
                            ? String(format: "%.4f, %.4f",
                                     coordinator.currentCoordinate.latitude,
                                     coordinator.currentCoordinate.longitude)
                            : "—"
                    )
                    Spacer()
                    LiveMetric(
                        icon: "server.rack",
                        label: "Server",
                        value: coordServer.isRunning ? "Port 8765 ▲" : "Tắt",
                        valueColor: coordServer.isRunning ? .green : .secondary
                    )
                    Spacer()
                    LiveMetric(
                        icon: "arrow.down.circle",
                        label: "Requests",
                        value: "\(coordServer.requestCount)"
                    )
                }
            }
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedTab = tab }
                } label: {
                    Text(tab.rawValue)
                        .font(AppFont.callout.weight(selectedTab == tab ? .semibold : .regular))
                        .foregroundStyle(selectedTab == tab ? AppColor.primary : AppColor.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.sm)
                        .background(
                            selectedTab == tab
                                ? AppColor.primary.opacity(0.08)
                                : Color.clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
                }
            }
        }
        .padding(4)
        .background(AppColor.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
    }

    // MARK: - Setup Tab

    private var setupTab: some View {
        VStack(spacing: AppSpacing.lg) {

            // One-tap install
            installButtons

            // Steps
            VStack(spacing: AppSpacing.md) {
                SectionLabel("5 bước cài đặt")

                TrackableStep(
                    number: 1,
                    title: "Import module vào Shadowrocket",
                    detail: "Bấm \"Cài Live\" ở trên → Shadowrocket mở tự động → tap Import.",
                    done: $step1Done
                )
                TrackableStep(
                    number: 2,
                    title: "Bật HTTPS Decryption",
                    detail: "Shadowrocket → Settings → HTTPS Decryption → ON → Generate Certificate → Install Profile.",
                    done: $step2Done,
                    action: { openURL("shadowrocket://") },
                    actionLabel: "Mở Shadowrocket"
                )
                TrackableStep(
                    number: 3,
                    title: "Trust Certificate",
                    detail: "Settings → General → About → Certificate Trust Settings → Bật CA Shadowrocket.",
                    done: $step3Done,
                    action: { openURL("App-Prefs:root=General&path=About") },
                    actionLabel: "Mở Settings"
                )
                TrackableStep(
                    number: 4,
                    title: "Kết nối VPN Shadowrocket",
                    detail: "Mở Shadowrocket → bật toggle Connect ở trang chủ.",
                    done: $step4Done,
                    action: { openURL("shadowrocket://") },
                    actionLabel: "Mở Shadowrocket"
                )
                TrackableStep(
                    number: 5,
                    title: "Airplane Mode trick",
                    detail: "Bật Airplane → Tắt Location → Restart iPhone → Tắt Airplane → Bật WiFi → Bật VPN → Bật Location.\nBuộc iOS dùng WiFi positioning thay vì GPS.",
                    done: $step5Done
                )
            }

            // Reset
            if stepsCompleted > 0 {
                Button(role: .destructive) { resetSteps() } label: {
                    Label("Reset tiến trình", systemImage: "arrow.counterclockwise")
                        .font(AppFont.footnote)
                        .foregroundStyle(AppColor.textTertiary)
                }
                .padding(.top, AppSpacing.sm)
            }

            // Done banner
            if allDone {
                doneBanner
            }
        }
    }

    // MARK: - Install Buttons

    private var installButtons: some View {
        VStack(spacing: AppSpacing.sm) {
            // Live (recommended)
            Button { installLive() } label: {
                HStack {
                    Image(systemName: "bolt.fill")
                        .font(.body)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cài Module Live")
                            .font(AppFont.callout.weight(.semibold))
                        Text("Toạ độ tự cập nhật realtime khi di chuyển")
                            .font(AppFont.caption)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    Spacer()
                    Image(systemName: "arrow.up.forward.app")
                }
                .foregroundStyle(.white)
                .padding(AppSpacing.lg)
                .background(
                    LinearGradient(
                        colors: [AppColor.primary, AppColor.primary.opacity(0.8)],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
            }

            // GitHub (fallback)
            Button { installGitHub() } label: {
                HStack {
                    Image(systemName: "icloud.and.arrow.down")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cài Module Static (GitHub)")
                            .font(AppFont.callout.weight(.medium))
                        Text("Toạ độ cố định — cần cài lại khi đổi vị trí")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.forward.app")
                        .foregroundStyle(AppColor.textTertiary)
                }
                .foregroundStyle(AppColor.textPrimary)
                .padding(AppSpacing.lg)
                .background(AppColor.surfaceSecondary)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
            }

            // Server control row
            HStack {
                Circle()
                    .fill(coordServer.isRunning ? .green : .secondary)
                    .frame(width: 8, height: 8)
                Text(coordServer.isRunning ? "CoordinateServer chạy" : "CoordinateServer tắt")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                Spacer()
                Button(coordServer.isRunning ? "Dừng" : "Khởi động") {
                    coordServer.isRunning ? coordServer.stop() : coordServer.start()
                }
                .font(AppFont.caption.weight(.medium))
                .foregroundStyle(coordServer.isRunning ? AppColor.danger : AppColor.primary)
            }
            .padding(.horizontal, AppSpacing.sm)
        }
    }

    // MARK: - Done Banner

    private var doneBanner: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: "checkmark.shield.fill")
                .font(.title2)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("Bypass đã sẵn sàng")
                    .font(AppFont.callout.weight(.semibold))
                Text("Mở Bump → vị trí GPS giả sẽ hiện, isSimulatedBySoftware = false")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
        .padding(AppSpacing.lg)
        .background(Color.green.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.lg)
                .stroke(Color.green.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
    }

    // MARK: - Server Tab

    private var serverTab: some View {
        VStack(spacing: AppSpacing.lg) {
            SectionLabel("Endpoints")

            VStack(spacing: AppSpacing.xs) {
                EndpointCard(
                    method: "GET",
                    path: "/coord",
                    desc: "Toạ độ hiện tại (JSON)",
                    action: { openURL("http://127.0.0.1:8765/coord") }
                )
                EndpointCard(
                    method: "GET",
                    path: "/location-spoofer.js",
                    desc: "MITM script với toạ độ live",
                    action: { openURL("http://127.0.0.1:8765/location-spoofer.js") }
                )
                EndpointCard(
                    method: "GET",
                    path: "/autospoof.sgmodule",
                    desc: "Shadowrocket module definition",
                    action: { openURL("http://127.0.0.1:8765/autospoof.sgmodule") }
                )
                EndpointCard(
                    method: "GET",
                    path: "/status",
                    desc: "Server health + stats (JSON)",
                    action: { openURL("http://127.0.0.1:8765/status") }
                )
            }

            SectionLabel("Kiểm tra")

            VStack(spacing: AppSpacing.sm) {
                TestButton(label: "Xem toạ độ hiện tại (/coord)",
                           icon: "location.circle") {
                    openURL("http://127.0.0.1:8765/coord")
                }
                TestButton(label: "Xem trạng thái server (/status)",
                           icon: "info.circle") {
                    openURL("http://127.0.0.1:8765/status")
                }
                TestButton(label: "Mở Shadowrocket",
                           icon: "network") {
                    openURL("shadowrocket://")
                }
            }
        }
    }

    // MARK: - How It Works Tab

    private var howtoTab: some View {
        VStack(spacing: AppSpacing.lg) {
            SectionLabel("Vấn đề")
            problemCard

            SectionLabel("Giải pháp")
            solutionFlow

            SectionLabel("Tại sao không cần jailbreak")
            noJailbreakCard
        }
    }

    private var problemCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                HStack {
                    Image(systemName: "xmark.shield.fill").foregroundStyle(.red)
                    Text("DVT LocationSimulation").font(AppFont.callout.weight(.medium))
                }
                Text("Mọi toạ độ đi qua DVT đều bị iOS daemon (locationd) tự động gắn cờ isSimulatedBySoftware = true. Bump đọc cờ này và từ chối. Đây là cơ chế hệ thống — không phải lỗi code.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var solutionFlow: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                FlowStep(icon: "iphone", color: .blue,
                         title: "AutoSpoofVN gửi toạ độ qua DVT")
                FlowArrow()
                FlowStep(icon: "server.rack", color: .indigo,
                         title: "CoordinateServer (port 8765) phục vụ toạ độ realtime")
                FlowArrow()
                FlowStep(icon: "network", color: .orange,
                         title: "Shadowrocket MITM intercept gs-loc.apple.com")
                FlowArrow()
                FlowStep(icon: "doc.text", color: .purple,
                         title: "location-spoofer.js rewrite binary response")
                FlowArrow()
                FlowStep(icon: "wifi", color: .teal,
                         title: "iOS nhận kết quả như WiFi positioning (không phải DVT)")
                FlowArrow()
                FlowStep(icon: "checkmark.shield.fill", color: .green,
                         title: "isSimulatedBySoftware = false → Bump accept ✓",
                         highlight: true)
            }
        }
    }

    private var noJailbreakCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Label("Shadowrocket là app có thể mua trên App Store ($2.99) — không cần jailbreak.", systemImage: "cart")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                Label("MITM certificate được trust qua Settings → General (cơ chế hợp lệ của iOS).", systemImage: "key.fill")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                Label("Module intercept chỉ target Apple WiFi location API, không ảnh hưởng traffic khác.", systemImage: "shield")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
    }

    // MARK: - Computed bypass state

    private var bypassColor: Color {
        if allDone && coordServer.isRunning { return .green }
        if stepsCompleted >= 3 { return .orange }
        return AppColor.primary
    }
    private var bypassIcon: String {
        if allDone && coordServer.isRunning { return "checkmark.shield.fill" }
        if stepsCompleted >= 3 { return "shield.lefthalf.fill" }
        return "shield"
    }
    private var bypassTitle: String {
        if allDone && coordServer.isRunning { return "Bypass hoạt động" }
        if stepsCompleted == 0 { return "Chưa cài Bypass" }
        return "Đang cài đặt (\(stepsCompleted)/5)"
    }
    private var bypassSubtitle: String {
        if allDone && coordServer.isRunning { return "isSimulatedBySoftware = false · GPS giả như GPS thật" }
        if stepsCompleted == 0 { return "Làm theo 5 bước để bypass phát hiện GPS giả" }
        return "Hoàn thành các bước còn lại để kích hoạt bypass"
    }

    // MARK: - Actions

    private func installLive() {
        step1Done = true
        let enc = moduleURLLive.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? moduleURLLive
        openURL("shadowrocket://install?module=\(enc)")
    }

    private func installGitHub() {
        step1Done = true
        let enc = moduleURLGitHub.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? moduleURLGitHub
        openURL("shadowrocket://install?module=\(enc)")
    }

    private func resetSteps() {
        step1Done = false; step2Done = false; step3Done = false
        step4Done = false; step5Done = false
    }

    private func openURL(_ string: String) {
        guard let url = URL(string: string) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - TrackableStep

/// Step với checkbox người dùng có thể tap để đánh dấu hoàn thành.
struct TrackableStep: View {
    let number: Int
    let title: String
    let detail: String
    @Binding var done: Bool
    var action: (() -> Void)? = nil
    var actionLabel: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            // Số / tick
            Button { withAnimation { done = true } } label: {
                ZStack {
                    Circle()
                        .fill(done ? Color.green : AppColor.primary.opacity(0.15))
                        .frame(width: 28, height: 28)
                    if done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    } else {
                        Text("\(number)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppColor.primary)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(done)

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(title)
                    .font(AppFont.body.weight(.medium))
                    .strikethrough(done)
                    .foregroundStyle(done ? AppColor.textTertiary : AppColor.textPrimary)

                Text(detail)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let action, let label = actionLabel, !done {
                    Button(action: action) {
                        Label(label, systemImage: "arrow.up.forward.app")
                            .font(AppFont.caption.weight(.medium))
                            .foregroundStyle(AppColor.primary)
                    }
                    .padding(.top, 2)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(AppSpacing.md)
        .background(done ? Color.green.opacity(0.05) : AppColor.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md)
                .stroke(done ? Color.green.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.2), value: done)
    }
}

// MARK: - EndpointCard

struct EndpointCard: View {
    let method: String
    let path: String
    let desc: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.md) {
                Text(method)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                VStack(alignment: .leading, spacing: 1) {
                    Text("127.0.0.1:8765\(path)")
                        .font(AppFont.mono)
                        .foregroundStyle(AppColor.textPrimary)
                    Text(desc)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textTertiary)
                }

                Spacer()

                Image(systemName: "safari")
                    .font(.footnote)
                    .foregroundStyle(AppColor.textTertiary)
            }
            .padding(AppSpacing.md)
            .background(AppColor.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - TestButton

struct TestButton: View {
    let label: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(AppColor.primary)
                Text(label)
                    .font(AppFont.callout)
                    .foregroundStyle(AppColor.textPrimary)
                Spacer()
                Image(systemName: "arrow.up.forward.app")
                    .font(.footnote)
                    .foregroundStyle(AppColor.textTertiary)
            }
            .padding(AppSpacing.md)
            .background(AppColor.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Flow components

private struct FlowStep: View {
    let icon: String
    let color: Color
    let title: String
    var highlight: Bool = false

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(color)
                .frame(width: 24)
            Text(title)
                .font(AppFont.callout)
                .foregroundStyle(highlight ? AppColor.textPrimary : AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(highlight ? AppSpacing.sm : 0)
        .background(highlight ? color.opacity(0.08) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
    }
}

private struct FlowArrow: View {
    var body: some View {
        Image(systemName: "arrow.down")
            .font(.caption2)
            .foregroundStyle(AppColor.textTertiary)
            .padding(.leading, 8)
    }
}

// MARK: - Shared helpers

private struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        HStack {
            Text(text)
                .font(AppFont.footnote.weight(.semibold))
                .foregroundStyle(AppColor.textTertiary)
                .textCase(.uppercase)
                .tracking(0.5)
            Spacer()
        }
    }
}

private struct LiveMetric: View {
    let icon: String
    let label: String
    let value: String
    var valueColor: Color = AppColor.textPrimary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .foregroundStyle(AppColor.textTertiary)
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(AppColor.textTertiary)
            }
            Text(value)
                .font(AppFont.mono)
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}
