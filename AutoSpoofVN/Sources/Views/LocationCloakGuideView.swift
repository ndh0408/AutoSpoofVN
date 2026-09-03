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
            .navigationTitle("Xử lý sự cố")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Đóng") { dismiss() }
                }
            }
        }
    }

    // MARK: - Live Checks

    private var liveChecks: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            SectionHeader("Kiểm tra realtime")

            CheckItem(
                title: "CoordinateServer chạy",
                ok: coordServer.isRunning,
                okText: "Port 8765 đang lắng nghe",
                failText: "Server tắt — mở AutoSpoofVN và đảm bảo app chạy foreground"
            )

            CheckItem(
                title: "Đang mô phỏng GPS",
                ok: coordinator.state.isActive,
                okText: "Đang gửi toạ độ \(String(format: "%.4f, %.4f", coordinator.currentCoordinate.latitude, coordinator.currentCoordinate.longitude))",
                failText: "Chưa bật simulation — bấm nút trên dashboard"
            )

            CheckItem(
                title: "DVT kết nối",
                ok: coordinator.deviceState == .connected,
                okText: "Thiết bị iOS kết nối thành công",
                failText: "Thiết bị chưa kết nối — cắm cáp và kết nối trong Device Manager"
            )
        }
    }

    // MARK: - Common Issues

    private var commonIssues: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            SectionHeader("Lỗi thường gặp")

            IssueCard(
                issue: "Shadowrocket không intercept",
                cause: "HTTPS Decryption chưa ON hoặc Certificate chưa được Trust.",
                fix: "Shadowrocket → Settings → HTTPS Decryption → ON.\nSettings → General → About → Certificate Trust Settings → Bật CA Shadowrocket.",
                action: { openURL("App-Prefs:root=General&path=About") },
                actionLabel: "Mở Certificate Trust"
            )

            IssueCard(
                issue: "Bump vẫn thấy isSimulatedBySoftware = true",
                cause: "Chưa thực hiện Airplane trick → iOS dùng GPS hardware thay vì WiFi positioning.",
                fix: "Bật Airplane Mode → Tắt Location Services → Khởi động lại iPhone → Tắt Airplane → Bật WiFi → Bật VPN Shadowrocket → Bật Location Services.\nPhải đúng thứ tự này.",
                action: nil, actionLabel: nil
            )

            IssueCard(
                issue: "Module báo lỗi timeout",
                cause: "CoordinateServer không phản hồi khi script chạy.",
                fix: "AutoSpoofVN phải đang chạy foreground hoặc ít nhất background. Bật Background Keep-Alive trong Settings.",
                action: nil, actionLabel: nil
            )

            IssueCard(
                issue: "Module cài được nhưng không active",
                cause: "Cần chọn đúng config profile trong Shadowrocket.",
                fix: "Shadowrocket → Config → Chọn file autospoof → Use Config.",
                action: { openURL("shadowrocket://") },
                actionLabel: "Mở Shadowrocket"
            )
        }
    }

    // MARK: - Technical Detail

    private var technicalDetail: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            SectionHeader("Chi tiết kỹ thuật")

            AppCard {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    TechRow(key: "Target API",
                            value: "gs-loc.apple.com/clls/wloc\n(Apple WiFi Positioning Service)")
                    Divider()
                    TechRow(key: "Script",
                            value: "location-spoofer.js\nRewrite binary protobuf response")
                    Divider()
                    TechRow(key: "Cơ chế",
                            value: "iOS nhận kết quả từ WiFi positioning\n→ isSimulatedBySoftware = false")
                    Divider()
                    TechRow(key: "Yêu cầu",
                            value: "Shadowrocket $2.99 · HTTPS MiTM · WiFi")
                    Divider()
                    TechRow(key: "Server status",
                            value: coordServer.isRunning
                                ? "Running · \(coordServer.requestCount) requests"
                                : "Stopped")
                }
            }

            // Verify endpoint
            Button {
                openURL("http://127.0.0.1:8765/coord")
            } label: {
                Label("Verify /coord endpoint trong Safari", systemImage: "safari")
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

private struct SectionHeader: View {
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
