import SwiftUI

/// Xử lý sự cố bypass — hiển thị khi Shadowrocket MITM đã cài nhưng
/// Bump vẫn từ chối. Hướng dẫn kiểm tra từng điểm thất bại.
struct BypassTroubleshootView: View {
    @StateObject private var coordServer = CoordinateServer.shared
    @StateObject private var coordinator = SimulationCoordinator.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.xl) {

                    // MARK: - Live check
                    liveChecks

                    // MARK: - Common issues
                    commonIssues

                    // MARK: - Technical detail
                    technicalDetail
                }
                .padding(AppSpacing.lg)
            }
            .navigationTitle(L("shadowrocket.troubleshoot.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(L("action.close")) { dismiss() }
                }
            }
        }
    }

    // MARK: - Live Checks

    private var liveChecks: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            CloakSectionHeader(L("shadowrocket.troubleshoot.live_checks"))

            CheckItem(
                title: L("shadowrocket.server.running"),
                ok: coordServer.isRunning,
                okText: L("shadowrocket.check.server.ok"),
                failText: L("shadowrocket.check.server.fail")
            )

            CheckItem(
                title: L("shadowrocket.check.sim.title"),
                ok: coordinator.state.isActive,
                okText: L("shadowrocket.check.sim.ok",
                          String(format: "%.4f, %.4f", coordinator.currentCoordinate.latitude, coordinator.currentCoordinate.longitude)),
                failText: L("shadowrocket.check.sim.fail")
            )

            CheckItem(
                title: L("shadowrocket.check.dvt.title"),
                ok: coordinator.deviceState.isConnected,
                okText: L("shadowrocket.check.dvt.ok"),
                failText: L("shadowrocket.check.dvt.fail")
            )
        }
    }

    // MARK: - Common Issues

    private var commonIssues: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            CloakSectionHeader(L("shadowrocket.troubleshoot.common_issues"))

            IssueCard(
                issue: L("shadowrocket.issue.intercept.title"),
                cause: L("shadowrocket.issue.intercept.cause"),
                fix: L("shadowrocket.issue.intercept.fix"),
                action: { openURL("App-Prefs:root=General&path=About") },
                actionLabel: L("shadowrocket.action.open_cert_trust")
            )

            IssueCard(
                issue: L("shadowrocket.issue.flag.title"),
                cause: L("shadowrocket.issue.flag.cause"),
                fix: L("shadowrocket.issue.flag.fix"),
                action: nil, actionLabel: nil
            )

            IssueCard(
                issue: L("shadowrocket.issue.timeout.title"),
                cause: L("shadowrocket.issue.timeout.cause"),
                fix: L("shadowrocket.issue.timeout.fix"),
                action: nil, actionLabel: nil
            )

            IssueCard(
                issue: L("shadowrocket.issue.inactive.title"),
                cause: L("shadowrocket.issue.inactive.cause"),
                fix: L("shadowrocket.issue.inactive.fix"),
                action: { openURL("shadowrocket://") },
                actionLabel: L("shadowrocket.action.open_app")
            )
        }
    }

    // MARK: - Technical Detail

    private var technicalDetail: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            CloakSectionHeader(L("shadowrocket.troubleshoot.technical"))

            AppCard {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    TechRow(key: L("shadowrocket.tech.target_api"),
                            value: "gs-loc.apple.com/clls/wloc\n(Apple WiFi Positioning Service)")
                    Divider()
                    TechRow(key: L("shadowrocket.tech.script"),
                            value: "location-spoofer.js\nRewrite binary protobuf response")
                    Divider()
                    TechRow(key: L("shadowrocket.tech.mechanism"),
                            value: L("shadowrocket.tech.mechanism.value"))
                    Divider()
                    TechRow(key: L("shadowrocket.tech.requirements"),
                            value: "Shadowrocket $2.99 · HTTPS MiTM · WiFi")
                    Divider()
                    TechRow(key: L("shadowrocket.tech.server_status"),
                            value: coordServer.isRunning
                                ? L("shadowrocket.tech.server.running", coordServer.requestCount)
                                : L("shadowrocket.tech.server.stopped"))
                }
            }

            // Verify endpoint
            Button {
                openURL("http://127.0.0.1:8765/coord")
            } label: {
                Label(L("shadowrocket.troubleshoot.verify"), systemImage: "safari")
                    .font(AppFont.caption.weight(.medium))
                    .foregroundStyle(AppColor.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func openURL(_ string: String) {
        guard let url = URL(string: string) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - Supporting Views

private struct CloakSectionHeader: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(AppFont.footnote.weight(.semibold))
            .foregroundStyle(AppColor.textTertiary)
            .textCase(.uppercase)
            .tracking(0.5)
    }
}

private struct CheckItem: View {
    let title: String
    let ok: Bool
    let okText: String
    let failText: String

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(ok ? .green : .red)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFont.callout.weight(.medium))
                Text(ok ? okText : failText)
                    .font(AppFont.caption)
                    .foregroundStyle(ok ? AppColor.textSecondary : .red.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(AppSpacing.md)
        .background(ok ? Color.green.opacity(0.05) : Color.red.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
    }
}

private struct IssueCard: View {
    let issue: String
    let cause: String
    let fix: String
    let action: (() -> Void)?
    let actionLabel: String?

    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.callout)
                    Text(issue)
                        .font(AppFont.callout.weight(.medium))
                        .foregroundStyle(AppColor.textPrimary)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(AppColor.textTertiary)
                }
                .padding(AppSpacing.md)
            }
            .buttonStyle(.plain)

            if expanded {
                Divider()
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Label(cause, systemImage: "questionmark.circle")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                    Label(fix, systemImage: "wrench.and.screwdriver")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let action, let label = actionLabel {
                        Button(action: action) {
                            Label(label, systemImage: "arrow.up.forward.app")
                                .font(AppFont.caption.weight(.medium))
                                .foregroundStyle(AppColor.primary)
                        }
                    }
                }
                .padding(AppSpacing.md)
            }
        }
        .background(AppColor.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
    }
}

private struct TechRow: View {
    let key: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(key)
                .font(AppFont.caption.weight(.medium))
                .foregroundStyle(AppColor.textTertiary)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
