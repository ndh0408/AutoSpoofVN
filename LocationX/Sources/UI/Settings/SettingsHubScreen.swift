import SwiftUI

/// Tab "Cài đặt".
///
/// Trước đây tab này chỉ là một danh sách lối tắt, và hàng "Tuỳ chọn mô phỏng" của nó lại
/// **mở ra một màn Cài đặt thứ hai dưới dạng sheet** — người dùng vào Cài đặt để rồi phải
/// mở Cài đặt lần nữa. Nay các nhóm tuỳ chọn là trang con đẩy ra từ chính tab này, còn
/// những màn thực sự là tác vụ (quản lý thiết bị, chẩn đoán, Shadowrocket) vẫn là sheet.
struct SettingsHubScreen: View {
    @Environment(\.navigator) private var navigator
    @ObservedObject private var coordinator = SimulationCoordinator.shared
    @ObservedObject private var shadowrocket = ShadowrocketManager.shared
    @ObservedObject private var localization = LocalizationManager.shared
    @ObservedObject private var store = AppSettingsStore.shared

    var body: some View {
        List {
            // Đường truyền lên đầu: đây là thứ quyết định app có chạy được hay không.
            // Hàng "Quản lý thiết bị" cũ đã bỏ — nó mở màn ghép nối DVT, một đường đã
            // chết cùng FFI, và badge của nó vĩnh viễn báo "Chưa kết nối".
            Section {
                HubRow(title: L("settings.shadowrocket"),
                       subtitle: L("settings.shadowrocket.subtitle"),
                       symbol: "bolt.horizontal.fill",
                       tint: shadowrocket.isReady ? AppColor.success : AppColor.warning,
                       badge: shadowrocket.isReady ? L("settings.shadowrocket.ready") : L("settings.shadowrocket.pending")) {
                    navigator.present(.shadowrocketSetup)
                }
                HubRow(title: L("settings.diagnostics"),
                       subtitle: L("settings.diagnostics.subtitle"),
                       symbol: "stethoscope",
                       tint: coordinator.deviceState.tint,
                       badge: coordinator.deviceState.displayName) {
                    navigator.present(.diagnostics)
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

            // Trang con, không phải sheet: chúng thuộc về ngăn xếp của tab Cài đặt.
            Section(L("settings.section.preferences")) {
                NavigationLink {
                    SimulationSettingsScreen()
                } label: {
                    HubRowLabel(title: L("settings.simulation_options"),
                                subtitle: L("settings.simulation_options.subtitle"),
                                symbol: "slider.horizontal.3",
                                tint: AppColor.primary)
                }
                NavigationLink {
                    MapSettingsScreen()
                } label: {
                    HubRowLabel(title: L("settings.map"),
                                subtitle: L("settings.map.subtitle"),
                                symbol: "map.fill",
                                tint: AppColor.info)
                }
                NavigationLink {
                    BackgroundSettingsScreen()
                } label: {
                    HubRowLabel(title: L("settings.background"),
                                subtitle: L("settings.background.subtitle"),
                                symbol: "moon.fill",
                                tint: AppColor.purple)
                }
            }

            Section {
                Picker(L("settings.appearance"), selection: $store.settings.appearance) {
                    Text(L("settings.appearance.system")).tag("system")
                    Text(L("settings.appearance.light")).tag("light")
                    Text(L("settings.appearance.dark")).tag("dark")
                }
                Picker(L("language.title"), selection: languageBinding) {
                    ForEach(AppLanguage.allCases) { lang in
                        Label(lang.displayName, systemImage: lang.symbol).tag(lang)
                    }
                }
            } header: {
                Text(L("settings.section.appearance"))
            } footer: {
                Text(L("language.footer"))
            }

            Section {
                NavigationLink {
                    AboutScreen()
                } label: {
                    HubRowLabel(title: L("settings.about"),
                                subtitle: "LocationX \(appVersion) (\(buildNumber))",
                                symbol: "info.circle.fill",
                                tint: AppColor.textSecondary)
                }
                HubRow(title: L("settings.simulation_history"),
                       subtitle: L("settings.simulation_history.subtitle"),
                       symbol: "clock.arrow.circlepath",
                       tint: AppColor.warning) {
                    navigator.present(.history)
                }
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
