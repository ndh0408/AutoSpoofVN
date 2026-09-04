import SwiftUI

/// Diagnostics 2.0 — dashboard chẩn đoán toàn diện + self-diagnostic.
struct DiagnosticsV2View: View {
    @StateObject private var coordinator = SimulationCoordinator.shared
    @StateObject private var device = DeviceManager.shared
    @StateObject private var keeper = BackgroundKeeper.shared
    @State private var diagnosticResults: [(String, SystemHealth.Status, String)] = []
    @State private var isRunningDiag = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // Self-Diagnostic button
                Section {
                    Button {
                        runSelfDiagnostic()
                    } label: {
                        HStack {
                            Image(systemName: "stethoscope")
                                .foregroundStyle(AppColor.primary)
                            Text(L("diagnostics.run"))
                                .font(AppFont.body.weight(.medium))
                            Spacer()
                            if isRunningDiag {
                                ProgressView()
                            }
                        }
                    }

                    if !diagnosticResults.isEmpty {
                        ForEach(Array(diagnosticResults.enumerated()), id: \.offset) { _, result in
                            HStack {
                                Image(systemName: result.1.icon)
                                    .foregroundStyle(statusColor(result.1))
                                Text(result.0)
                                    .font(AppFont.body)
                                Spacer()
                                VStack(alignment: .trailing) {
                                    Text(result.1.rawValue)
                                        .font(AppFont.caption.weight(.medium))
                                        .foregroundStyle(statusColor(result.1))
                                    Text(result.2)
                                        .font(AppFont.mono)
                                        .foregroundStyle(AppColor.textTertiary)
                                }
                            }
                        }
                    }
                } header: {
                    Label(L("diagnostics.self_check"), systemImage: "waveform.path.ecg")
                }

                // Device
                Section {
                    DiagField(L("device.connection"), value: coordinator.deviceState.displayName)
                    DiagField("UDID", value: device.deviceUDID.isEmpty ? "—" : device.deviceUDID)
                    DiagField("Model", value: device.deviceModel.isEmpty ? "—" : device.deviceModel)
                    DiagField("Transport", value: device.transportType)
                    DiagField("Latency", value: device.transportLatencyMs > 0 ? String(format: "%.1f ms", device.transportLatencyMs) : "—")
                    if let err = device.lastError {
                        DiagField(L("diagnostics.last_error"), value: err, isError: true)
                    }
                } header: { Label(L("settings.device"), systemImage: "iphone") }

                // Simulation
                Section {
                    DiagField(L("common.status"), value: coordinator.state.displayName)
                    DiagField(L("diagnostics.source"), value: coordinator.activeSource?.displayName ?? L("common.none"))
                    DiagField(L("diagnostics.coordinate"), value: String(format: "%.6f, %.6f", coordinator.currentCoordinate.latitude, coordinator.currentCoordinate.longitude))
                    DiagField(L("diagnostics.speed"), value: String(format: "%.1f km/h", coordinator.telemetry.speedKmh))
                    DiagField("Heading", value: coordinator.telemetry.formattedHeading)
                    DiagField("Noise", value: String(format: "%.1f m", coordinator.noiseConfig.radiusMeters))
                    DiagField("Multiplier", value: String(format: "%.1fx", coordinator.timeMultiplier))
                    DiagField("Halted", value: coordinator.isHalted ? L("common.yes") : L("common.no"))
                } header: { Label(L("settings.simulation"), systemImage: "location") }

                // Background
                Section {
                    DiagField("Audio", value: keeper.isAudioRunning ? L("common.running") : L("common.off"))
                    if let err = keeper.audioError {
                        DiagField(L("diagnostics.audio_error"), value: err, isError: true)
                    }
                    DiagField("Location", value: keeper.isLocationUpdating ? L("diagnostics.updating") : L("common.off"))
                    DiagField("Auth", value: "\(keeper.authorizationStatus.rawValue)")
                    DiagField("Interruptions", value: "\(keeper.interruptionCount)")
                } header: { Label(L("settings.background"), systemImage: "moon.fill") }

                // Pairing
                Section {
                    DiagField("Phase", value: SelfPairingManager.shared.phase.description)
                    DiagField(L("common.running"), value: SelfPairingManager.shared.isRunning ? L("common.yes") : L("common.no"))
                    DiagField("Paired UDID", value: SelfPairingManager.shared.pairedUDID.isEmpty ? "—" : SelfPairingManager.shared.pairedUDID)
                    DiagField("Saved pairing", value: SelfPairingManager.shared.hasSavedPairing ? L("common.yes") : L("common.no"))
                } header: { Label("RPPairing", systemImage: "link") }

                // Route
                Section {
                    DiagField("Routes saved", value: "\(PersistenceManager.shared.loadRoutes().count)")
                    DiagField("Scenarios", value: "\(PersistenceManager.shared.loadScenarios().count)")
                    DiagField("Bookmarks", value: "\(PersistenceManager.shared.loadBookmarks().count)")
                    DiagField("History", value: "\(PersistenceManager.shared.loadHistory().count)")
                } header: { Label(L("diagnostics.data"), systemImage: "internaldrive") }

                // Export
                Section {
                    Button("Export diagnostics (JSON)") { exportDiagnosticsJSON() }
                    Button("Export diagnostics (CSV)") { exportDiagnosticsCSV() }
                } header: { Label(L("diagnostics.export"), systemImage: "square.and.arrow.up") }
            }
            .navigationTitle(L("diagnostics.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button(L("action.close")) { dismiss() } }
            }
        }
    }

    private func runSelfDiagnostic() {
        isRunningDiag = true
        diagnosticResults = coordinator.runDiagnostics()
        // Additional checks
        diagnosticResults.append((
            "Pairing file",
            SelfPairingManager.shared.hasSavedPairing ? .healthy : .warning,
            SelfPairingManager.shared.hasSavedPairing ? L("diagnostics.pairing.available") : L("diagnostics.pairing.missing")
        ))
        diagnosticResults.append((
            "Permissions",
            keeper.authorizationStatus == .authorizedAlways ? .healthy : .warning,
            keeper.authorizationStatus == .authorizedAlways ? "Always" : L("diagnostics.permission.need_always")
        ))
        isRunningDiag = false
    }

    private func statusColor(_ status: SystemHealth.Status) -> Color {
        switch status {
        case .healthy: return .green
        case .warning: return .orange
        case .error: return .red
        case .unknown: return .secondary
        }
    }

    private func exportDiagnosticsJSON() {
        let diag = device.generateDiagnostics()
        let dict: [String: Any] = [
            "device_connected": diag.deviceConnected,
            "device_name": diag.deviceName,
            "udid": diag.udid,
            "transport": diag.transport,
            "latency_ms": diag.latencyMs,
            "background_running": diag.backgroundRunning,
            "pairing_available": diag.pairingAvailable,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted) {
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("diagnostics_\(Int(Date().timeIntervalSince1970)).json")
            try? data.write(to: url)
            AppLogger.persist.info("Diagnostics exported to \(url.lastPathComponent)")
        }
    }

    private func exportDiagnosticsCSV() {
        let diag = device.generateDiagnostics()
        var csv = "key,value\n"
        csv += "device_connected,\(diag.deviceConnected)\n"
        csv += "device_name,\(diag.deviceName)\n"
        csv += "udid,\(diag.udid)\n"
        csv += "transport,\(diag.transport)\n"
        csv += "latency_ms,\(diag.latencyMs)\n"
        csv += "background,\(diag.backgroundRunning)\n"
        csv += "pairing,\(diag.pairingAvailable)\n"
        csv += "timestamp,\(ISO8601DateFormatter().string(from: Date()))\n"
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("diagnostics_\(Int(Date().timeIntervalSince1970)).csv")
        try? csv.write(to: url, atomically: true, encoding: .utf8)
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
        }
    }
}
