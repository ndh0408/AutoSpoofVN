import SwiftUI

/// Cài đặt toàn diện — simulation, map, device, background, appearance, developer.
struct SettingsView: View {
    @State private var settings = PersistenceManager.shared.loadSettings()
    @StateObject private var coordinator = SimulationCoordinator.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Simulation
                Section {
                    Picker("Nhiễu GPS", selection: $settings.noiseConfig.radiusMeters) {
                        Text("Tắt").tag(0.0)
                        Text("1m").tag(1.0)
                        Text("3m").tag(3.0)
                        Text("5m").tag(5.0)
                        Text("10m").tag(10.0)
                        Text("20m").tag(20.0)
                    }
                    Toggle("Drift tương quan", isOn: $settings.noiseConfig.drift)

                    Picker("Phương tiện mặc định", selection: $settings.defaultTravelMode) {
                        ForEach(TravelMode.allCases) { mode in
                            Label(mode.displayName, systemImage: mode.icon).tag(mode)
                        }
                    }

                    HStack {
                        Text("Tần suất cập nhật thiết bị")
                        Spacer()
                        Text("\(String(format: "%.0f", settings.deviceUpdateRateHz)) Hz")
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    Slider(value: $settings.deviceUpdateRateHz, in: 0.5...5, step: 0.5)
                } header: {
                    Label("Mô phỏng", systemImage: "location.fill")
                }

                // MARK: - Map
                Section {
                    Picker("Kiểu bản đồ", selection: $settings.mapStyle) {
                        Text("Tiêu chuẩn").tag("standard")
                        Text("Vệ tinh").tag("satellite")
                        Text("Hỗn hợp").tag("hybrid")
                    }
                    Toggle("Theo dõi vị trí", isOn: $settings.mapFollowMode)
                    Toggle("3D", isOn: $settings.map3DEnabled)
                    Toggle("Vẽ vết di chuyển", isOn: $settings.trailEnabled)
                } header: {
                    Label("Bản đồ", systemImage: "map")
                }

                // MARK: - Device
                Section {
                    Toggle("Tự kết nối lại", isOn: $settings.autoReconnect)
                    HStack {
                        Text("Heartbeat")
                        Spacer()
                        Text("\(Int(settings.heartbeatIntervalSeconds))s")
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    Slider(value: $settings.heartbeatIntervalSeconds, in: 10...60, step: 5)
                } header: {
                    Label("Thiết bị", systemImage: "iphone")
                }

                // MARK: - Background
                Section {
                    Toggle("Giữ app sống nền", isOn: $settings.backgroundKeepAlive)
                    HStack {
                        Text("Trạng thái")
                        Spacer()
                        StatusBadge(
                            BackgroundKeeper.shared.isAudioRunning ? "Đang chạy" : "Tắt",
                            color: BackgroundKeeper.shared.isAudioRunning ? .green : .secondary
                        )
                    }
                } header: {
                    Label("Chạy nền", systemImage: "moon.fill")
                }

                // MARK: - Appearance
                Section {
                    Picker("Giao diện", selection: $settings.appearance) {
                        Text("Hệ thống").tag("system")
                        Text("Sáng").tag("light")
                        Text("Tối").tag("dark")
                    }
                } header: {
                    Label("Giao diện", systemImage: "paintbrush")
                }

                // MARK: - Developer
                Section {
                    Toggle("Hiện thông tin kỹ thuật", isOn: $settings.showDeveloperInfo)
                    NavigationLink("Chẩn đoán hệ thống") {
                        DiagnosticsView()
                    }
                    NavigationLink("Lịch sử mô phỏng") {
                        HistoryView()
                    }
                } header: {
                    Label("Nhà phát triển", systemImage: "wrench")
                }

                // MARK: - About
                Section {
                    HStack {
                        Text("Phiên bản")
                        Spacer()
                        Text("2.0.0")
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    HStack {
                        Text("FFI ABI")
                        Spacer()
                        Text("v3")
                            .font(AppFont.mono)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                } header: {
                    Label("Thông tin", systemImage: "info.circle")
                }
            }
            .navigationTitle("Cài đặt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Đóng") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Lưu") {
                        PersistenceManager.shared.saveSettings(settings)
                        coordinator.noiseConfig = settings.noiseConfig
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
