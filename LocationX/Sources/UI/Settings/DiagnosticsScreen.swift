import SwiftUI

/// Chẩn đoán hệ thống.
///
/// Bản trước dựng quanh đường DVT: nó hiển thị UDID, transport "DVT", độ trễ, và trạng
/// thái ghép nối RPPairing. Sau khi bỏ FFI thì tất cả những trường đó hoặc rỗng hoặc
/// vĩnh viễn báo lỗi — màn hình càng làm người dùng hoang mang chứ không giúp gì.
///
/// Bản này đo đúng cái đang chạy: CoordinateServer, Shadowrocket, và bằng chứng trực
/// tiếp rằng MITM có thật sự fetch script hay không.
struct DiagnosticsScreen: View {
    @ObservedObject private var coordinator = SimulationCoordinator.shared
    @ObservedObject private var shadowrocket = ShadowrocketManager.shared
    @ObservedObject private var server = CoordinateServer.shared
    @ObservedObject private var keeper = BackgroundKeeper.shared

    @State private var storage = StorageCounts()
    @State private var results: [(String, SystemHealth.Status, String)] = []
    @Environment(\.dismiss) private var dismiss

    private struct StorageCounts {
        var routes = 0
        var scenarios = 0
        var bookmarks = 0
        var history = 0
    }

    var body: some View {
        NavigationStack {
            List {
                healthSection
                pipelineSection
                simulationSection
                backgroundSection
                storageSection
                exportSection
            }
            .navigationTitle(L("diagnostics.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(L("action.close")) { dismiss() }
                }
            }
            .task {
                // Chạy ngay khi mở: bắt người dùng bấm một nút để biết app có khoẻ không
                // là bắt họ làm việc của app.
                results = coordinator.runDiagnostics()
                // Giải mã JSON ngoài main thread — history.json có thể nặng hàng chục MB.
                storage = await Task.detached(priority: .utility) {
                    StorageCounts(
                        routes: PersistenceManager.shared.loadRoutes().count,
                        scenarios: PersistenceManager.shared.loadScenarios().count,
                        bookmarks: PersistenceManager.shared.loadBookmarks().count,
                        history: PersistenceManager.shared.loadHistory().count
                    )
                }.value
            }
        }
    }

    // MARK: - Tổng quan sức khoẻ

    private var healthSection: some View {
        Section {
            ForEach(Array(results.enumerated()), id: \.offset) { _, item in
                HStack(spacing: AppSpacing.md) {
                    Image(systemName: item.1.icon)
                        .foregroundStyle(color(for: item.1))
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.0)
                            .font(AppFont.body)
                        Text(item.2)
                            .font(AppFont.caption1)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    Spacer()
                    Text(item.1.displayName)
                        .font(AppFont.caption.weight(.semibold))
                        .foregroundStyle(color(for: item.1))
                }
                .accessibilityElement(children: .combine)
            }
            Button {
                AppHaptics.selection()
                results = coordinator.runDiagnostics()
            } label: {
                Label(L("diagnostics.run"), systemImage: "arrow.clockwise")
            }
        } header: {
            Text(L("diagnostics.self_check"))
        } footer: {
            Text(L("diagnostics.self_check.footer"))
        }
    }

    // MARK: - Đường truyền

    private var pipelineSection: some View {
        Section {
            DiagField(L("device.connection"), value: coordinator.deviceState.displayName)
            DiagField(L("diagnostics.server_port"),
                      value: server.isRunning ? "127.0.0.1:\(server.port)" : L("common.off"),
                      isError: !server.isRunning)
            if let err = server.lastError {
                DiagField(L("diagnostics.last_error"), value: err, isError: true)
            }
            DiagField(L("diagnostics.requests"), value: "\(server.requestCount)")
            DiagField(L("diagnostics.last_request"), value: lastRequestText)
            DiagField(L("diagnostics.last_path"), value: server.lastRequestedPath ?? "—")
            DiagField("Shadowrocket",
                      value: shadowrocket.isInstalled ? L("common.installed") : L("common.not_installed"),
                      isError: !shadowrocket.isInstalled)
            DiagField(L("settings.shadowrocket.module"),
                      value: shadowrocket.isModuleImported ? L("common.imported") : L("common.not_imported"))
            DiagField("VPN", value: shadowrocket.isVPNActive ? L("common.on") : L("common.off"))
            if !shadowrocket.statusMessage.isEmpty {
                Text(shadowrocket.statusMessage)
                    .font(AppFont.caption1)
                    .foregroundStyle(AppColor.textSecondary)
            }
        } header: {
            Text(L("diagnostics.item.pipeline"))
        } footer: {
            Text(L("diagnostics.pipeline.footer"))
        }
    }

    // MARK: - Mô phỏng

    private var simulationSection: some View {
        Section {
            DiagField(L("common.status"), value: coordinator.state.displayName)
            DiagField(L("diagnostics.source"),
                      value: coordinator.activeSource?.displayName ?? L("common.none"))
            DiagField(L("diagnostics.coordinate"),
                      value: String(format: "%.6f, %.6f",
                                    coordinator.currentCoordinate.latitude,
                                    coordinator.currentCoordinate.longitude))
            // Toạ độ THẬT SỰ báo ra khác toạ độ mô phỏng đúng bằng phần nhiễu — hiển thị
            // cả hai để phân biệt "nhiễu" với "sai".
            if let reported = coordinator.lastReportedCoordinate {
                DiagField(L("diagnostics.reported"),
                          value: String(format: "%.6f, %.6f", reported.latitude, reported.longitude))
            }
            DiagField(L("diagnostics.speed"),
                      value: String(format: "%.1f km/h", coordinator.telemetry.speedKmh))
            DiagField(L("diagnostics.heading"), value: coordinator.telemetry.formattedHeading)
            DiagField(L("settings.gps_noise"),
                      value: String(format: "%.1f m", coordinator.noiseConfig.radiusMeters))
            DiagField(L("diagnostics.multiplier"),
                      value: String(format: "%.1fx", coordinator.timeMultiplier))
            DiagField(L("diagnostics.halted"),
                      value: coordinator.isHalted ? L("common.yes") : L("common.no"))
        } header: {
            Text(L("settings.simulation"))
        }
    }

    // MARK: - Chạy nền

    private var backgroundSection: some View {
        Section {
            DiagField(L("diagnostics.audio"),
                      value: keeper.isAudioRunning ? L("common.running") : L("common.off"))
            if let err = keeper.audioError {
                DiagField(L("diagnostics.audio_error"), value: err, isError: true)
            }
            DiagField(L("diagnostics.location_updates"),
                      value: keeper.isLocationUpdating ? L("diagnostics.updating") : L("common.off"))
            DiagField(L("diagnostics.authorization"), value: authorizationText)
            DiagField(L("diagnostics.interruptions"), value: "\(keeper.interruptionCount)")
        } header: {
            Text(L("settings.background"))
        }
    }

    // MARK: - Dữ liệu

    private var storageSection: some View {
        Section {
            DiagField(L("routes.title"), value: "\(storage.routes)")
            DiagField(L("scenario.title"), value: "\(storage.scenarios)")
            DiagField(L("bookmarks.title"), value: "\(storage.bookmarks)")
            DiagField(L("history.title"), value: "\(storage.history)")
        } header: {
            Text(L("diagnostics.data"))
        }
    }

    // MARK: - Xuất

    private var exportSection: some View {
        Section {
            // ShareLink thay cho hai nút cũ: chúng ghi file vào Documents rồi chỉ log
            // đường dẫn ra console — người dùng không có cách nào lấy được file đó.
            ShareLink(item: report) {
                Label(L("diagnostics.share"), systemImage: "square.and.arrow.up")
            }
            Button {
                UIPasteboard.general.string = report
                AppHaptics.success()
            } label: {
                Label(L("action.copy"), systemImage: "doc.on.doc")
            }
        } header: {
            Text(L("diagnostics.export"))
        } footer: {
            Text(L("diagnostics.export.footer"))
        }
    }

    // MARK: - Trợ giúp

    private var report: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        var lines: [String] = []
        lines.append("LocationX \(version) (\(build))")
        lines.append("iOS \(UIDevice.current.systemVersion) · \(UIDevice.current.model)")
        lines.append(ISO8601DateFormatter().string(from: Date()))
        lines.append("")
        for item in results {
            lines.append("[\(item.1.rawValue)] \(item.0): \(item.2)")  // bao cao ky thuat: giu khoa on dinh
        }
        lines.append("")
        lines.append("server=\(server.isRunning ? "127.0.0.1:\(server.port)" : "off")")
        lines.append("requests=\(server.requestCount) lastPath=\(server.lastRequestedPath ?? "-")")
        lines.append("shadowrocket installed=\(shadowrocket.isInstalled) module=\(shadowrocket.isModuleImported) vpn=\(shadowrocket.isVPNActive)")
        lines.append("state=\(coordinator.state.displayName) source=\(coordinator.activeSource?.displayName ?? "-")")
        lines.append(String(format: "coord=%.6f,%.6f", coordinator.currentCoordinate.latitude, coordinator.currentCoordinate.longitude))
        lines.append("background audio=\(keeper.isAudioRunning) location=\(keeper.isLocationUpdating) auth=\(keeper.authorizationStatus.rawValue)")
        lines.append("storage routes=\(storage.routes) scenarios=\(storage.scenarios) bookmarks=\(storage.bookmarks) history=\(storage.history)")
        return lines.joined(separator: "\n")
    }

    private var lastRequestText: String {
        guard let at = server.lastRequestAt else { return "—" }
        let seconds = Int(Date().timeIntervalSince(at))
        return seconds < 60 ? L("diagnostics.seconds_ago", seconds) : AppFormat.time(at)
    }

    private var authorizationText: String {
        switch keeper.authorizationStatus {
        case .authorizedAlways:    return L("permission.always")
        case .authorizedWhenInUse: return L("permission.when_in_use")
        case .denied:              return L("permission.denied")
        case .restricted:          return L("permission.restricted")
        default:                   return L("permission.not_determined")
        }
    }

    private func color(for status: SystemHealth.Status) -> Color {
        switch status {
        case .healthy: return AppColor.success
        case .warning: return AppColor.warning
        case .error:   return AppColor.danger
        case .unknown: return AppColor.textSecondary
        }
    }
}

struct DiagField: View {
    let label: String
    let value: String
    var isError: Bool = false

    init(_ label: String, value: String, isError: Bool = false) {
        self.label = label
        self.value = value
        self.isError = isError
    }

    var body: some View {
        HStack {
            Text(label)
                .font(AppFont.footnote)
                .foregroundStyle(AppColor.textSecondary)
            Spacer()
            Text(value)
                .font(AppFont.mono)
                .foregroundStyle(isError ? AppColor.danger : AppColor.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}
