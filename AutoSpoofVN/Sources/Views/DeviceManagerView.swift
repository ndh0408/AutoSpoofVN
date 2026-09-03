import SwiftUI

/// Quản lý thiết bị — kết nối, chẩn đoán, thông tin chi tiết.
struct DeviceManagerView: View {
    @StateObject private var device = DeviceManager.shared
    @StateObject private var pairing = SelfPairingManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // Connection status
                Section {
                    HStack {
                        Image(systemName: device.connectionState.icon)
                            .font(.title2)
                            .foregroundStyle(stateColor)
                        VStack(alignment: .leading, spacing: AppSpacing.xs) {
                            Text(device.connectionState.displayName)
                                .font(AppFont.headline)
                            if let err = device.lastError {
                                Text(err)
                                    .font(AppFont.caption)
                                    .foregroundStyle(AppColor.danger)
                            }
                        }
                        Spacer()
                        StatusBadge(
                            device.connectionState.isConnected ? "Online" : "Offline",
                            color: device.connectionState.isConnected ? .green : .secondary
                        )
                    }

                    // Actions
                    HStack(spacing: AppSpacing.md) {
                        if device.connectionState.isConnected {
                            Button("Ngắt kết nối") { device.disconnect() }
                            Button("Test") { _ = device.testConnection() }
                            Button("Xoá GPS") { device.clearSimulation() }
                        } else {
                            Button("Kết nối") { device.connect() }
                                .buttonStyle(.borderedProminent)
                            Button("Ghép nối mới") { pairing.startAutoPairing() }
                        }
                    }
                    .font(AppFont.footnote.weight(.medium))
                } header: {
                    Label("Kết nối", systemImage: "antenna.radiowaves.left.and.right")
                }

                // Device info
                Section {
                    InfoRow("Tên", value: device.deviceName.isEmpty ? "—" : device.deviceName)
                    InfoRow("Model", value: device.deviceModel.isEmpty ? "—" : device.deviceModel)
                    InfoRow("UDID", value: device.deviceUDID.isEmpty ? "—" : String(device.deviceUDID.prefix(12)) + "...")
                    InfoRow("Transport", value: device.transportType)
                    if let hb = device.lastHeartbeat {
                        InfoRow("Heartbeat", value: DateFormatter.localizedString(from: hb, dateStyle: .none, timeStyle: .medium))
                    }
                    if device.transportLatencyMs > 0 {
                        InfoRow("Latency", value: String(format: "%.1f ms", device.transportLatencyMs))
                    }
                } header: {
                    Label("Thiết bị", systemImage: "iphone")
                }

                // Pairing status
                Section {
                    HStack {
                        Text("Trạng thái")
                        Spacer()
                        Text(pairing.phase.description)
                            .font(AppFont.footnote)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    if let pin = pairing.latestPin {
                        HStack {
                            Text("Mã PIN")
                            Spacer()
                            Text(pin)
                                .font(AppFont.monoBody.weight(.bold))
                                .foregroundStyle(AppColor.primary)
                        }
                    }
                    if pairing.isRunning {
                        Button("Huỷ ghép nối", role: .destructive) {
                            pairing.cancel()
                        }
                    } else {
                        Button("Bắt đầu ghép nối") {
                            pairing.startAutoPairing()
                        }
                    }
                } header: {
                    Label("RPPairing", systemImage: "link")
                }

                // Diagnostics
                Section {
                    let diag = device.generateDiagnostics()
                    DiagRow("Thiết bị", ok: diag.deviceConnected)
                    DiagRow("Pairing", ok: diag.pairingAvailable)
                    DiagRow("Background", ok: diag.backgroundRunning)
                    DiagRow("Audio", ok: diag.audioKeepAlive)
                } header: {
                    Label("Chẩn đoán nhanh", systemImage: "stethoscope")
                }
            }
            .navigationTitle("Thiết bị")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Đóng") { dismiss() }
                }
            }
        }
    }

    private var stateColor: Color {
        switch device.connectionState {
        case .connected: return .green
        case .connecting: return .orange
        case .error: return .red
        case .disconnected: return .secondary
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    init(_ label: String, value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(AppColor.textSecondary)
            Spacer()
            Text(value)
                .font(AppFont.mono)
        }
    }
}

struct DiagRow: View {
    let label: String
    let ok: Bool

    init(_ label: String, ok: Bool) {
        self.label = label
        self.ok = ok
    }

    var body: some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(ok ? .green : .red)
            Text(label)
            Spacer()
            Text(ok ? "OK" : "Lỗi")
                .font(AppFont.caption)
                .foregroundStyle(ok ? AppColor.textSecondary : .red)
        }
    }
}
