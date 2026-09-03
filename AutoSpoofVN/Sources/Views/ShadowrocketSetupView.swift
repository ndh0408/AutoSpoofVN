import SwiftUI

/// Tích hợp Shadowrocket — cài đặt tự động, hướng dẫn, trạng thái.
struct ShadowrocketSetupView: View {
    @StateObject private var coordServer = CoordinateServer.shared
    @StateObject private var coordinator = SimulationCoordinator.shared
    @State private var setupStep = 0
    @State private var showManualGuide = false
    @Environment(\.dismiss) private var dismiss

    private let moduleURL = "http://127.0.0.1:8765/autospoof.sgmodule"
    private let moduleGitURL = "https://raw.githubusercontent.com/ndh0408/AutoSpoofVN/main/Proxy/autospoof-location.sgmodule"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.xl) {
                    // Status header
                    statusCard

                    // Auto-setup button
                    setupButtons

                    // Steps guide
                    stepsGuide

                    // Coordinate server status
                    serverStatus

                    // Test section
                    if coordServer.isRunning {
                        testSection
                    }
                }
                .padding(AppSpacing.lg)
            }
            .navigationTitle("Shadowrocket")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Đóng") { dismiss() }
                }
            }
            .onAppear {
                // Auto-start coordinate server
                if !coordServer.isRunning {
                    coordServer.start()
                }
            }
        }
    }

    // MARK: - Status Card

    private var statusCard: some View {
        AppCard {
            VStack(spacing: AppSpacing.md) {
                HStack {
                    Image(systemName: coordServer.isRunning ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                        .font(.title2)
                        .foregroundStyle(coordServer.isRunning ? .green : .secondary)
                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Text(coordServer.isRunning ? "Coordinate Server đang chạy" : "Coordinate Server tắt")
                            .font(AppFont.headline)
                        Text("Port 8765 — Shadowrocket đọc toạ độ realtime từ đây")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    Spacer()
                }

                HStack {
                    MetricView("Toạ độ", value: String(format: "%.4f, %.4f",
                        coordinator.currentCoordinate.latitude,
                        coordinator.currentCoordinate.longitude), icon: "mappin")
                    Spacer()
                    MetricView("Requests", value: "\(coordServer.requestCount)", icon: "number")
                }
            }
        }
    }

    // MARK: - Setup Buttons

    private var setupButtons: some View {
        VStack(spacing: AppSpacing.md) {
            // One-tap install module (live)
            Button {
                installModuleLive()
            } label: {
                HStack {
                    Image(systemName: "bolt.fill")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cài module Live (tự động)")
                            .font(AppFont.callout.weight(.semibold))
                        Text("Toạ độ cập nhật realtime khi di chuyển")
                            .font(AppFont.caption)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    Spacer()
                    Image(systemName: "arrow.up.forward.app")
                }
                .foregroundStyle(.white)
                .padding(AppSpacing.lg)
                .background(Color.blue)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
            }

            // Install from GitHub (static, fallback)
            Button {
                installModuleGitHub()
            } label: {
                HStack {
                    Image(systemName: "icloud.and.arrow.down")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cài module Static (từ GitHub)")
                            .font(AppFont.callout.weight(.medium))
                        Text("Toạ độ cố định, cần sửa thủ công khi đổi")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.forward.app")
                }
                .padding(AppSpacing.lg)
                .background(AppColor.surfaceSecondary)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
            }
            .foregroundStyle(AppColor.textPrimary)

            // Server toggle
            HStack {
                Button(coordServer.isRunning ? "Dừng server" : "Khởi động server") {
                    if coordServer.isRunning { coordServer.stop() }
                    else { coordServer.start() }
                }
                .font(AppFont.footnote.weight(.medium))
                .foregroundStyle(coordServer.isRunning ? AppColor.danger : AppColor.primary)
            }
        }
    }

    // MARK: - Steps Guide

    private var stepsGuide: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            Text("Hướng dẫn cài đặt")
                .font(AppFont.headline)

            StepRow(number: 1, title: "Cài module", detail: "Bấm nút bên trên → Shadowrocket mở → Import module", done: false)
            StepRow(number: 2, title: "Bật HTTPS Decryption", detail: "Shadowrocket → Settings → HTTPS Decryption → ON → Generate Certificate → Install", done: false)
            StepRow(number: 3, title: "Trust certificate", detail: "Settings → General → About → Certificate Trust Settings → Bật CA Shadowrocket", done: false)
            StepRow(number: 4, title: "Bật VPN", detail: "Shadowrocket → bật toggle Connect", done: false)
            StepRow(number: 5, title: "Buộc WiFi positioning", detail: "Airplane Mode → tắt Location → Restart → tắt Airplane → bật WiFi → bật VPN → bật Location", done: false)
            StepRow(number: 6, title: "Mở Bump", detail: "Vị trí giả sẽ hiện, isSimulatedBySoftware = false", done: false)

            Text("Sau khi setup lần đầu, lần sau chỉ cần bật Shadowrocket VPN + mở AutoSpoofVN.")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textTertiary)
        }
        .padding(AppSpacing.lg)
        .background(AppColor.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
    }

    // MARK: - Server Status

    private var serverStatus: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("Endpoints")
                .font(AppFont.headline)

            Group {
                EndpointRow(path: "/coord", desc: "JSON toạ độ hiện tại")
                EndpointRow(path: "/location-spoofer.js", desc: "MITM script với toạ độ live")
                EndpointRow(path: "/autospoof.sgmodule", desc: "Shadowrocket module")
                EndpointRow(path: "/status", desc: "Server status")
            }
        }
        .padding(AppSpacing.lg)
        .background(AppColor.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
    }

    // MARK: - Test

    private var testSection: some View {
        VStack(spacing: AppSpacing.md) {
            Text("Kiểm tra")
                .font(AppFont.headline)

            Button {
                // Open Safari to verify
                if let url = URL(string: "http://127.0.0.1:8765/coord") {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label("Mở /coord trong Safari", systemImage: "safari")
                    .font(AppFont.footnote)
            }

            Button {
                if let url = URL(string: "http://127.0.0.1:8765/status") {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label("Mở /status trong Safari", systemImage: "safari")
                    .font(AppFont.footnote)
            }
        }
    }

    // MARK: - Actions

    private func installModuleLive() {
        // Module lấy script từ local server → toạ độ luôn mới nhất
        let encoded = moduleURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? moduleURL
        if let url = URL(string: "shadowrocket://install?module=\(encoded)") {
            UIApplication.shared.open(url)
        }
    }

    private func installModuleGitHub() {
        let encoded = moduleGitURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? moduleGitURL
        if let url = URL(string: "shadowrocket://install?module=\(encoded)") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Supporting Views

struct StepRow: View {
    let number: Int
    let title: String
    let detail: String
    let done: Bool

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            ZStack {
                Circle()
                    .fill(done ? Color.green : AppColor.primary)
                    .frame(width: 24, height: 24)
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(number)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(title)
                    .font(AppFont.body.weight(.medium))
                Text(detail)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
    }
}

struct EndpointRow: View {
    let path: String
    let desc: String

    var body: some View {
        HStack {
            Text("GET")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.green)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 3))
            Text("127.0.0.1:8765\(path)")
                .font(AppFont.mono)
                .foregroundStyle(AppColor.textPrimary)
            Spacer()
            Text(desc)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textTertiary)
        }
    }
}
