import SwiftUI

/// Khung dieu huong goc: bon tab.
///
/// ```
/// Bản đồ      — man hinh chinh, ban do toan khung
/// Tuyến đường — tuyen, kich ban, chu trinh, dia diem, lich su
/// Chuyến bay  — chuyen bay va World Odyssey
/// Cài đặt     — thiet bi, mo phong, chay nen, chan doan, gioi thieu
/// ```
///
/// Sheet duoc trinh bay o **cap TabView** chu khong o trong tung tab: nho vay modal phu
/// len ca tab bar (dung quy uoc iOS) va bat ky man hinh nao cung mo duoc bat ky sheet nao
/// qua `AppNavigator`.
struct RootTabView: View {
    @State private var navigator = AppNavigator()

    var body: some View {
        TabView(selection: tabSelection) {
            MapScreen()
                .tabItem {
                    Label(AppTab.map.title,
                          systemImage: navigator.selectedTab == .map ? AppTab.map.selectedSymbol : AppTab.map.symbol)
                }
                .tag(AppTab.map)

            NavigationStack(path: $navigator.routesPath) {
                RoutesScreen()
            }
            .tabItem {
                Label(AppTab.routes.title,
                      systemImage: navigator.selectedTab == .routes ? AppTab.routes.selectedSymbol : AppTab.routes.symbol)
            }
            .tag(AppTab.routes)

            NavigationStack(path: $navigator.flightPath) {
                FlightHubScreen()
            }
            .tabItem {
                Label(AppTab.flight.title, systemImage: AppTab.flight.symbol)
            }
            .tag(AppTab.flight)

            NavigationStack(path: $navigator.settingsPath) {
                SettingsHubScreen()
            }
            .tabItem {
                Label(AppTab.settings.title,
                      systemImage: navigator.selectedTab == .settings ? AppTab.settings.selectedSymbol : AppTab.settings.symbol)
            }
            .tag(AppTab.settings)
        }
        .tint(AppColor.primary)
        .environment(\.navigator, navigator)
        .sheet(item: Binding(get: { navigator.presentedSheet },
                             set: { navigator.presentedSheet = $0 })) { sheet in
            AppSheetDestination(sheet: sheet)
        }
    }

    /// Bam vao chinh tab dang mo se thu gon duong dan dieu huong cua tab do — hanh vi
    /// nguoi dung iOS mong doi ("bam lai de ve dau").
    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { navigator.selectedTab },
            set: { newTab in
                if newTab == navigator.selectedTab {
                    popToRoot(of: newTab)
                } else {
                    navigator.select(newTab)
                }
            }
        )
    }

    private func popToRoot(of tab: AppTab) {
        switch tab {
        case .routes:   if !navigator.routesPath.isEmpty { navigator.routesPath = .init() }
        case .flight:   if !navigator.flightPath.isEmpty { navigator.flightPath = .init() }
        case .settings: if !navigator.settingsPath.isEmpty { navigator.settingsPath = .init() }
        case .map:      break
        }
    }
}

// MARK: - Hang mo sheet dung chung

/// Mot hang trong danh sach mo ra mot man hinh modal.
///
/// Dung chung cho ca ba tab hub, nen ba man hinh do khong bi lech nhau ve cach trinh bay.
struct HubRow: View {
    let title: String
    var subtitle: String?
    let symbol: String
    var tint: Color = AppColor.primary
    var badge: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 29, height: 29)
                    .background(tint, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(AppFont.body)
                        .foregroundStyle(AppColor.textPrimary)
                    if let subtitle {
                        Text(subtitle)
                            .font(AppFont.caption1)
                            .foregroundStyle(AppColor.textSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }

                Spacer(minLength: AppSpacing.sm)

                if let badge {
                    Text(badge)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColor.textQuaternary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(subtitle.map { "\(title). \($0)" } ?? title)
        .accessibilityAddTraits(.isButton)
    }
}
