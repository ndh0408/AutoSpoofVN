import SwiftUI

/// Tab "Cài đặt".
///
/// **Giai doan 1**: duong vao cho cac man hinh hien co, chua phai ban thiet ke lai
/// (Giai doan 8). Nhung no da lam mot viec that: gom bon man hinh truoc day chi vao duoc
/// bang cach doan dung mot trong muoi nut icon xep doc ben phai ban do
/// (thiet bi, chan doan, Shadowrocket, khac phuc su co) thanh mot cau truc doc duoc.
struct SettingsHubScreen: View {
    @Environment(\.navigator) private var navigator
    @ObservedObject private var coordinator = SimulationCoordinator.shared
    @ObservedObject private var device = DeviceManager.shared
    @ObservedObject private var shadowrocket = ShadowrocketManager.shared
    @ObservedObject private var localization = LocalizationManager.shared

    var body: some View {
        List {
            Section(L("settings.device")) {
                HubRow(title: L("settings.device_manager"),
                       subtitle: device.deviceName.isEmpty ? L("settings.device_manager.subtitle") : device.deviceName,
                       symbol: coordinator.deviceState.icon,
                       tint: coordinator.deviceState.tint,
                       badge: coordinator.deviceState.isConnected ? L("device.connected") : L("device.disconnected")) {
                    navigator.present(.deviceManager)
                }
                HubRow(title: L("settings.diagnostics"),
                       subtitle: L("settings.diagnostics.subtitle"),
                       symbol: "stethoscope",
                       tint: AppColor.accent) {
                    navigator.present(.diagnostics)
                }
            }

            Section {
                HubRow(title: L("settings.shadowrocket"),
                       subtitle: L("settings.shadowrocket.subtitle"),
                       symbol: "bolt.horizontal.fill",
                       tint: shadowrocket.isReady ? AppColor.success : AppColor.warning,
                       badge: shadowrocket.isReady ? L("settings.shadowrocket.ready") : L("settings.shadowrocket.pending")) {
                    navigator.present(.shadowrocketSetup)
                }
                HubRow(title: L("settings.troubleshoot"),
                       subtitle: L("settings.troubleshoot.subtitle"),
                       symbol: "questionmark.circle.fill",
                       tint: AppColor.textSecondary) {
                    navigator.present(.bypassTroubleshoot)
                }
            } header: {
                Text(L("settings.section.bypass"))
            } footer: {
                if !shadowrocket.statusMessage.isEmpty {
                    Text(shadowrocket.statusMessage)
                }
            }

            Section(L("settings.simulation")) {
                HubRow(title: L("settings.simulation_options"),
                       subtitle: L("settings.simulation_options.subtitle"),
                       symbol: "slider.horizontal.3",
                       tint: AppColor.primary) {
                    navigator.present(.settings)
                }
            }

            Section {
                Picker(L("language.title"), selection: languageBinding) {
                    ForEach(AppLanguage.allCases) { lang in
                        Label(lang.displayName, systemImage: lang.symbol).tag(lang)
                    }
                }
                .pickerStyle(.inline)
            } header: {
                Text(L("language.title"))
            } footer: {
                Text(L("language.footer"))
            }

            Section {
                LabeledContent(L("settings.version"), value: appVersion)
                LabeledContent(L("settings.build"), value: buildNumber)
                LabeledContent(L("settings.preferred_source")) {
                    Text(coordinator.activeSource?.displayName ?? L("common.none"))
                        .foregroundStyle(AppColor.textSecondary)
                }
            } header: {
                Text(L("settings.section.app"))
            } footer: {
                Text(L("settings.app.footer"))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(L10n.tabSettings)
    }

    /// Ghi thẳng vào `LocalizationManager` — nguồn sự thật duy nhất về ngôn ngữ.
    private var languageBinding: Binding<AppLanguage> {
        Binding(get: { localization.language },
                set: { localization.setLanguage($0) })
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }
}

#Preview {
    NavigationStack { SettingsHubScreen() }
}
