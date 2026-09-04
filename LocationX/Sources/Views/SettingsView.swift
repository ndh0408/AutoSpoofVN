import SwiftUI

/// Cài đặt toàn diện — simulation, map, device, background, appearance, developer.
struct SettingsView: View {
    @State private var settings = PersistenceManager.shared.loadSettings()
    @StateObject private var coordinator = SimulationCoordinator.shared
    @Environment(\.dismiss) private var dismiss

    // Doc that tu bundle (MARKETING_VERSION/CURRENT_PROJECT_VERSION trong project.yml) thay
    // vi ghi cung chuoi - truoc day ghi cung "2.0.0" nen lan bump ke tiep se bi le, man hinh
    // Cai dat van hien so cu du app da cai ban moi.
    private var appVersionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Simulation
                Section {
                    Picker(L("settings.gps_noise"), selection: $settings.noiseConfig.radiusMeters) {
                        Text(L("common.off")).tag(0.0)
                        Text("1m").tag(1.0)
                        Text("3m").tag(3.0)
                        Text("5m").tag(5.0)
                        Text("10m").tag(10.0)
                        Text("20m").tag(20.0)
                    }
                    Toggle(L("settings.correlated_drift"), isOn: $settings.noiseConfig.drift)

                    Picker(L("settings.default_travel_mode"), selection: $settings.defaultTravelMode) {
                        ForEach(TravelMode.allCases) { mode in
                            Label(mode.displayName, systemImage: mode.icon).tag(mode)
                        }
                    }

                    HStack {
                        Text(L("settings.device_update_rate"))
                        Spacer()
                        Text("\(String(format: "%.0f", settings.deviceUpdateRateHz)) Hz")
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    Slider(value: $settings.deviceUpdateRateHz, in: 0.5...5, step: 0.5)
                } header: {
                    Label(L("settings.simulation"), systemImage: "location.fill")
                }

                // MARK: - Map
                Section {
                    Picker(L("settings.map_style"), selection: $settings.mapStyle) {
                        Text(L("settings.map_style.standard")).tag("standard")
                        Text(L("settings.map_style.satellite")).tag("satellite")
                        Text(L("settings.map_style.hybrid")).tag("hybrid")
                    }
                    Toggle(L("settings.follow_location"), isOn: $settings.mapFollowMode)
                    Toggle("3D", isOn: $settings.map3DEnabled)
                    Toggle(L("settings.trail"), isOn: $settings.trailEnabled)
                } header: {
                    Label(L("settings.map"), systemImage: "map")
                }

                // MARK: - Device
                Section {
                    Toggle(L("settings.auto_reconnect"), isOn: $settings.autoReconnect)
                    HStack {
                        Text("Heartbeat")
                        Spacer()
                        Text("\(Int(settings.heartbeatIntervalSeconds))s")
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    Slider(value: $settings.heartbeatIntervalSeconds, in: 10...60, step: 5)
                } header: {
                    Label(L("settings.device"), systemImage: "iphone")
                }

                // MARK: - Background
                Section {
                    Toggle(L("settings.background_keep_alive"), isOn: $settings.backgroundKeepAlive)
                    HStack {
                        Text(L("common.status"))
                        Spacer()
                        StatusBadge(
                            BackgroundKeeper.shared.isAudioRunning ? L("common.running") : L("common.off"),
                            color: BackgroundKeeper.shared.isAudioRunning ? .green : .secondary
                        )
                    }
                } header: {
                    Label(L("settings.background"), systemImage: "moon.fill")
                }

                // MARK: - Appearance
                Section {
                    Picker(L("settings.appearance"), selection: $settings.appearance) {
                        Text(L("settings.appearance.system")).tag("system")
                        Text(L("settings.appearance.light")).tag("light")
                        Text(L("settings.appearance.dark")).tag("dark")
                    }
                } header: {
                    Label(L("settings.appearance"), systemImage: "paintbrush")
                }

                // MARK: - Bypass
                Section {
                    NavigationLink {
                        ShadowrocketSetupView()
                    } label: {
                        HStack {
                            Label("Shadowrocket MITM", systemImage: "bolt.horizontal")
                            Spacer()
                            if CoordinateServer.shared.isRunning {
                                Text(L("common.running"))
                                    .font(AppFont.caption)
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    NavigationLink {
                        BypassTroubleshootView()
                    } label: {
                        Label(L("settings.bypass.troubleshoot"), systemImage: "questionmark.circle")
                    }
                } header: {
                    Label(L("settings.bypass"), systemImage: "shield")
                } footer: {
                    Text(L("settings.bypass.footer"))
                }

                // MARK: - Developer
                Section {
                    Toggle(L("settings.show_technical_info"), isOn: $settings.showDeveloperInfo)
                    NavigationLink(L("settings.system_diagnostics")) {
                        DiagnosticsV2View()
                    }
                    NavigationLink(L("settings.simulation_history")) {
                        HistoryView()
                    }
                } header: {
                    Label(L("settings.developer"), systemImage: "wrench")
                }

                // MARK: - About
                Section {
                    HStack {
                        Text(L("settings.version"))
                        Spacer()
                        Text(appVersionText)
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
                    Label(L("settings.about"), systemImage: "info.circle")
                }
            }
            .navigationTitle(L("tab.settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(L("action.close")) { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L("action.save")) {
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
