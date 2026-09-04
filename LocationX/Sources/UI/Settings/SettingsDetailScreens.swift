import SwiftUI

/// Các trang con của tab Cài đặt.
///
/// Trước đây toàn bộ tuỳ chọn nằm trong `SettingsView` — một `Form` dài được **tab Cài đặt
/// mở ra dưới dạng sheet**. Tức là người dùng vào tab Cài đặt rồi phải mở thêm một màn
/// "Cài đặt" nữa. Nay mỗi nhóm là một trang con đẩy ra từ chính tab, đúng cách iOS làm.
///
/// Mọi ràng buộc ghi thẳng vào `AppSettingsStore`, nên thay đổi có hiệu lực ngay.

// MARK: - Mô phỏng

struct SimulationSettingsScreen: View {
    @ObservedObject private var store = AppSettingsStore.shared

    var body: some View {
        Form {
            Section {
                Picker(L("settings.gps_noise"), selection: $store.settings.noiseConfig.radiusMeters) {
                    Text(L("common.off")).tag(0.0)
                    ForEach([1.0, 3.0, 5.0, 10.0, 20.0], id: \.self) { radius in
                        Text("\(Int(radius))m").tag(radius)
                    }
                }
                Toggle(L("settings.correlated_drift"), isOn: $store.settings.noiseConfig.drift)
            } header: {
                Text(L("settings.gps_noise"))
            } footer: {
                Text(L("settings.gps_noise.footer"))
            }

            Section {
                Picker(L("settings.default_travel_mode"), selection: $store.settings.defaultTravelMode) {
                    ForEach(TravelMode.allCases) { mode in
                        Label(mode.displayName, systemImage: mode.icon).tag(mode)
                    }
                }
            }

            Section {
                sliderRow(label: L("settings.device_update_rate"),
                          value: $store.settings.deviceUpdateRateHz,
                          range: 0.5...5, step: 0.5,
                          display: "\(String(format: "%.1f", store.settings.deviceUpdateRateHz)) Hz")
                sliderRow(label: L("settings.simulation_rate"),
                          value: $store.settings.simulationTickRateHz,
                          range: 1...30, step: 1,
                          display: "\(Int(store.settings.simulationTickRateHz)) Hz")
            } header: {
                Text(L("settings.rates"))
            } footer: {
                Text(L("settings.rates.footer"))
            }
        }
        .navigationTitle(L("settings.simulation"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sliderRow(label: String, value: Binding<Double>,
                           range: ClosedRange<Double>, step: Double,
                           display: String) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            LabeledContent(label, value: display)
            Slider(value: value, in: range, step: step)
                .tint(AppColor.primary)
                .accessibilityValue(display)
        }
    }
}

// MARK: - Bản đồ

struct MapSettingsScreen: View {
    @ObservedObject private var store = AppSettingsStore.shared

    var body: some View {
        Form {
            Section {
                // Lấy danh sách từ chính enum — gõ cứng chuỗi ở đây từng làm lựa chọn
                // "Vệ tinh" âm thầm không có tác dụng.
                Picker(L("settings.map_style"), selection: $store.settings.mapStyle) {
                    ForEach(MapStyleKind.allCases) { kind in
                        Label(kind.title, systemImage: kind.symbol).tag(kind.rawValue)
                    }
                }
                Toggle(L("settings.follow_location"), isOn: $store.settings.mapFollowMode)
                Toggle(L("settings.map_3d"), isOn: $store.settings.map3DEnabled)
            }

            Section {
                Toggle(L("settings.trail"), isOn: $store.settings.trailEnabled)
                if store.settings.trailEnabled {
                    Stepper(value: $store.settings.trailMaxPoints, in: 100...5000, step: 100) {
                        LabeledContent(L("settings.trail_points"),
                                       value: "\(store.settings.trailMaxPoints)")
                    }
                }
            } header: {
                Text(L("settings.trail"))
            } footer: {
                Text(L("settings.trail.footer"))
            }
        }
        .navigationTitle(L("settings.map"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Thiết bị & chạy nền

struct BackgroundSettingsScreen: View {
    @ObservedObject private var store = AppSettingsStore.shared
    @ObservedObject private var keeper = BackgroundKeeper.shared

    var body: some View {
        Form {
            Section {
                Toggle(L("settings.background_keep_alive"), isOn: $store.settings.backgroundKeepAlive)
                LabeledContent(L("common.status")) {
                    StatusBadge(keeper.isAudioRunning ? L("common.running") : L("common.off"),
                                color: keeper.isAudioRunning ? AppColor.success : AppColor.textSecondary,
                                icon: keeper.isAudioRunning ? "waveform" : "pause")
                }
                if let error = keeper.audioError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(AppFont.caption1)
                        .foregroundStyle(AppColor.warning)
                }
            } header: {
                Text(L("settings.background"))
            } footer: {
                Text(L("settings.background.footer"))
            }

            Section {
                Toggle(L("settings.auto_reconnect"), isOn: $store.settings.autoReconnect)
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    LabeledContent(L("settings.heartbeat"),
                                   value: "\(Int(store.settings.heartbeatIntervalSeconds))s")
                    Slider(value: $store.settings.heartbeatIntervalSeconds, in: 10...60, step: 5)
                        .tint(AppColor.primary)
                }
            } header: {
                Text(L("settings.device"))
            } footer: {
                Text(L("settings.heartbeat.footer"))
            }
        }
        .navigationTitle(L("settings.background"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Giới thiệu

struct AboutScreen: View {
    @ObservedObject private var store = AppSettingsStore.shared

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: AppSpacing.md) {
                    Image(systemName: "location.north.circle.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(AppColor.primary)
                    Text("LocationX")
                        .font(AppFont.title2.weight(.bold))
                    Text(L("about.tagline"))
                        .font(AppFont.footnote)
                        .foregroundStyle(AppColor.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.lg)
                .listRowBackground(Color.clear)
            }

            Section {
                LabeledContent(L("settings.version"), value: appVersion)
                LabeledContent(L("settings.build"), value: buildNumber)
                LabeledContent(L("settings.spoof_method"), value: "Shadowrocket MITM")
                LabeledContent(L("about.author"), value: "Nguyễn Đức Huy")
                LabeledContent(L("about.license"), value: "Apache-2.0")
            }

            Section {
                Toggle(L("settings.show_technical_info"), isOn: $store.settings.showDeveloperInfo)
            } footer: {
                Text(L("settings.developer.footer"))
            }

            Section {
                Text(L("about.disclaimer"))
                    .font(AppFont.caption1)
                    .foregroundStyle(AppColor.textSecondary)
            } header: {
                Text(L("about.disclaimer.title"))
            }
        }
        .navigationTitle(L("settings.about"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
