import SwiftUI

/// Trung tâm bypass isSimulatedBySoftware — hướng dẫn cài Shadowrocket MITM
/// và theo dõi trạng thái realtime của CoordinateServer.
///
/// Luồng bypass (không cần jailbreak):
///   LocationX → DVT (toạ độ) + CoordinateServer (port 8765)
///   Shadowrocket MITM intercept gs-loc.apple.com → trả toạ độ giả như WiFi position
///   iOS: isSimulatedBySoftware = false → Bump accept
struct ShadowrocketSetupView: View {
    @StateObject private var coordServer = CoordinateServer.shared
    @StateObject private var manager = ShadowrocketManager.shared
    @StateObject private var coordinator = SimulationCoordinator.shared
    @Environment(\.dismiss) private var dismiss

    // Bước cài đặt — lưu vào UserDefaults để nhớ giữa các lần mở
    @AppStorage("bypass_step1_module")   private var step1Done = false  // Đã import module
    @AppStorage("bypass_step2_https")    private var step2Done = false  // HTTPS Decryption ON
    @AppStorage("bypass_step3_cert")     private var step3Done = false  // Trust certificate
    @AppStorage("bypass_step4_vpn")      private var step4Done = false  // VPN connect
    @AppStorage("bypass_step5_airplane") private var step5Done = false  // Airplane trick

    @State private var selectedTab: Tab = .setup

    private let moduleURLLive   = "http://127.0.0.1:8765/locationx.sgmodule"
    private let moduleURLGitHub = "https://raw.githubusercontent.com/ndh0408/LocationX/main/Proxy/locationx.sgmodule"

    private var allDone: Bool { step1Done && step2Done && step3Done && step4Done && step5Done }
    private var stepsCompleted: Int { [step1Done,step2Done,step3Done,step4Done,step5Done].filter{$0}.count }

    enum Tab: String, CaseIterable {
        case setup
        case server
        case howto

        var title: String {
            switch self {
            case .setup:  return L("shadowrocket.tab.setup")
            case .server: return L("shadowrocket.tab.server")
            case .howto:  return L("shadowrocket.tab.howto")
            }
        }
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
            .navigationTitle(L("shadowrocket.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(L("action.close")) { dismiss() }
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
                        label: L("shadowrocket.metric.fake_coord"),
                        value: coordServer.isRunning
                            ? String(format: "%.4f, %.4f",
                                     coordinator.currentCoordinate.latitude,
                                     coordinator.currentCoordinate.longitude)
                            : "—"
                    )
                    Spacer()
                    LiveMetric(
                        icon: "server.rack",
                        label: L("shadowrocket.metric.server"),
                        value: coordServer.isRunning ? "Port 8765 ▲" : L("shadowrocket.metric.server.off"),
                        valueColor: coordServer.isRunning ? .green : .secondary
                    )
                    Spacer()
                    LiveMetric(
                        icon: "arrow.down.circle",
                        label: L("shadowrocket.metric.requests"),
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
                    Text(tab.title)
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
                SectionLabel(L("shadowrocket.setup.steps_title"))

                TrackableStep(
                    number: 1,
                    title: L("shadowrocket.step1.title"),
                    detail: L("shadowrocket.step1.detail"),
                    done: $step1Done
                )
                TrackableStep(
                    number: 2,
                    title: L("shadowrocket.step2.title"),
                    detail: L("shadowrocket.step2.detail"),
                    done: $step2Done,
                    action: { openURL("shadowrocket://") },
                    actionLabel: L("shadowrocket.action.open_app")
                )
                TrackableStep(
                    number: 3,
                    title: L("shadowrocket.step3.title"),
                    detail: L("shadowrocket.step3.detail"),
                    done: $step3Done,
                    action: { openURL("App-Prefs:root=General&path=About") },
                    actionLabel: L("shadowrocket.action.open_settings")
                )
                TrackableStep(
                    number: 4,
                    title: L("shadowrocket.step4.title"),
                    detail: L("shadowrocket.step4.detail"),
                    done: $step4Done,
                    action: { openURL("shadowrocket://") },
                    actionLabel: L("shadowrocket.action.open_app")
                )
                TrackableStep(
                    number: 5,
                    title: L("shadowrocket.step5.title"),
                    detail: L("shadowrocket.step5.detail"),
                    done: $step5Done
                )
            }

            // Reset
            if stepsCompleted > 0 {
                Button(role: .destructive) { resetSteps() } label: {
                    Label(L("shadowrocket.action.reset_progress"), systemImage: "arrow.counterclockwise")
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
                        Text(L("shadowrocket.install.live.title"))
                            .font(AppFont.callout.weight(.semibold))
                        Text(L("shadowrocket.install.live.subtitle"))
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
                        Text(L("shadowrocket.install.static.title"))
                            .font(AppFont.callout.weight(.medium))
                        Text(L("shadowrocket.install.static.subtitle"))
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
                Text(coordServer.isRunning ? L("shadowrocket.server.running") : L("shadowrocket.server.stopped"))
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                Spacer()
                Button(coordServer.isRunning ? L("action.stop") : L("shadowrocket.server.start")) {
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
                Text(L("shadowrocket.done.title"))
                    .font(AppFont.callout.weight(.semibold))
                Text(L("shadowrocket.done.message"))
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
            SectionLabel(L("shadowrocket.section.endpoints"))

            VStack(spacing: AppSpacing.xs) {
                EndpointCard(
                    method: "GET",
                    path: "/coord",
                    desc: L("shadowrocket.endpoint.coord"),
                    action: { openURL("http://127.0.0.1:8765/coord") }
                )
                EndpointCard(
                    method: "GET",
                    path: "/location-spoofer.js",
                    desc: L("shadowrocket.endpoint.spoofer"),
                    action: { openURL("http://127.0.0.1:8765/location-spoofer.js") }
                )
                EndpointCard(
                    method: "GET",
                    path: "/locationx.sgmodule",
                    desc: L("shadowrocket.endpoint.module"),
                    action: { openURL("http://127.0.0.1:8765/locationx.sgmodule") }
                )
                EndpointCard(
                    method: "GET",
                    path: "/status",
                    desc: L("shadowrocket.endpoint.status"),
                    action: { openURL("http://127.0.0.1:8765/status") }
                )
            }

            SectionLabel(L("shadowrocket.section.test"))

            VStack(spacing: AppSpacing.sm) {
                TestButton(label: L("shadowrocket.test.coord"),
                           icon: "location.circle") {
                    openURL("http://127.0.0.1:8765/coord")
                }
                TestButton(label: L("shadowrocket.test.status"),
                           icon: "info.circle") {
                    openURL("http://127.0.0.1:8765/status")
                }
                TestButton(label: L("shadowrocket.action.open_app"),
                           icon: "network") {
                    openURL("shadowrocket://")
                }
            }
        }
    }

    // MARK: - How It Works Tab

    private var howtoTab: some View {
        VStack(spacing: AppSpacing.lg) {
            SectionLabel(L("shadowrocket.section.problem"))
            problemCard

            SectionLabel(L("shadowrocket.section.solution"))
            solutionFlow

            SectionLabel(L("shadowrocket.section.no_jailbreak"))
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
                Text(L("shadowrocket.problem.detail"))
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
                         title: L("shadowrocket.flow.dvt"))
                FlowArrow()
                FlowStep(icon: "server.rack", color: .indigo,
                         title: L("shadowrocket.flow.server"))
                FlowArrow()
                FlowStep(icon: "network", color: .orange,
                         title: L("shadowrocket.flow.mitm"))
                FlowArrow()
                FlowStep(icon: "doc.text", color: .purple,
                         title: L("shadowrocket.flow.script"))
                FlowArrow()
                FlowStep(icon: "wifi", color: .teal,
                         title: L("shadowrocket.flow.wifi"))
                FlowArrow()
                FlowStep(icon: "checkmark.shield.fill", color: .green,
                         title: L("shadowrocket.flow.result"),
                         highlight: true)
            }
        }
    }

    private var noJailbreakCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Label(L("shadowrocket.nojb.appstore"), systemImage: "cart")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                Label(L("shadowrocket.nojb.cert"), systemImage: "key.fill")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                Label(L("shadowrocket.nojb.scope"), systemImage: "shield")
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
        if allDone && coordServer.isRunning { return L("shadowrocket.state.active") }
        if stepsCompleted == 0 { return L("shadowrocket.state.not_setup") }
        return L("shadowrocket.state.progress", stepsCompleted)
    }
    private var bypassSubtitle: String {
        if allDone && coordServer.isRunning { return L("shadowrocket.state.active.detail") }
        if stepsCompleted == 0 { return L("shadowrocket.state.not_setup.detail") }
        return L("shadowrocket.state.progress.detail")
    }

    // MARK: - Actions

    // Ca hai ham deu di qua ShadowrocketManager.importModule().
    //
    // Truoc day chung chi dat `step1Done` (@AppStorage "bypass_step1_module") roi tu mo
    // URL. Nghia la co HAI nguon su that rieng biet ve cung mot viec: checklist o man hinh
    // nay, va `ShadowrocketManager.isModuleImported` o banner. Lam xong ca 5 buoc thi
    // checklist tick het, nhung banner ngoai man hinh chinh VAN keu "Import module" va
    // `isReady` khong bao gio thanh true.
    private func installLive() {
        step1Done = true
        manager.importModule()
    }

    private func installGitHub() {
        step1Done = true
        let enc = moduleURLGitHub.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? moduleURLGitHub
        openURL("shadowrocket://install?module=\(enc)")
        manager.noteImportAttempted()
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
