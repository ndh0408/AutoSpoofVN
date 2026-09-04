import CoreLocation
import SwiftUI

/// Đích điều hướng bên trong tab Tuyến đường.
enum RoutesDestination: Hashable {
    case routeDetail(UUID)
}

/// Tab "Tuyến đường" — nhà chung của mọi cách di chuyển trên mặt đất.
///
/// Đây là lần đầu tuyến đã lưu **hiện ra được**: `saveRoute()` vẫn ghi vào `routes.json`
/// từ trước, nhưng không màn hình nào đọc lại, nên nút "Lưu tuyến đường" tạo ra thứ người
/// dùng không bao giờ lấy lại được.
struct RoutesScreen: View {
    @Environment(\.navigator) private var navigator
    @ObservedObject private var routeStore = SavedRouteStore.shared
    @ObservedObject private var simulator = RouteSimulator.shared
    @ObservedObject private var scenarioEngine = ScenarioEngine.shared
    @ObservedObject private var routine = RoutineManager.shared
    @ObservedObject private var history = HistoryManager.shared
    @ObservedObject private var coordinator = SimulationCoordinator.shared

    @State private var showBuilder = false
    @State private var renameTarget: SavedRoute?
    @State private var renameText = ""
    @State private var deleteTarget: SavedRoute?
    @State private var failureMessage: String?

    var body: some View {
        List {
            if coordinator.state.isActive, let source = coordinator.activeSource {
                Section { activeSessionRow(source: source) }
            }

            savedRoutesSection
            scenariosSection
            automationSection
            placesSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(L10n.tabRoutes)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showBuilder = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibleButton(label: L("a11y.create_route"), hint: L("a11y.create_route_hint"))
            }
        }
        .navigationDestination(for: RoutesDestination.self) { destination in
            switch destination {
            case .routeDetail(let id):
                RouteDetailScreen(routeID: id)
            }
        }
        .fullScreenCover(isPresented: $showBuilder) {
            RouteBuilderScreen()
        }
        .alert(L("route.rename"), isPresented: renameBinding) {
            TextField(L("route.name_placeholder"), text: $renameText)
            Button(L10n.save) {
                if let target = renameTarget { routeStore.rename(id: target.id, to: renameText) }
                renameTarget = nil
            }
            Button(L10n.cancel, role: .cancel) { renameTarget = nil }
        }
        .confirmationDialog(L("route.delete_confirm"),
                            isPresented: deleteBinding,
                            titleVisibility: .visible) {
            Button(L10n.delete, role: .destructive) {
                if let target = deleteTarget { routeStore.delete(id: target.id) }
                deleteTarget = nil
            }
            Button(L10n.cancel, role: .cancel) { deleteTarget = nil }
        } message: {
            Text(deleteTarget.map { L("route.delete_message", $0.name) } ?? "")
        }
        .alert(L("route.start_failed"), isPresented: failureBinding) {
            Button(L10n.close, role: .cancel) { failureMessage = nil }
        } message: {
            Text(failureMessage ?? "")
        }
    }

    // MARK: - Tuyến đã lưu

    @ViewBuilder
    private var savedRoutesSection: some View {
        Section {
            if routeStore.routes.isEmpty {
                EmptyStateView(icon: "point.topleft.down.to.point.bottomright.curvepath",
                               title: L10n.noRoutes,
                               message: L10n.noRoutesMessage,
                               actionTitle: L10n.createRoute) { showBuilder = true }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            } else {
                ForEach(routeStore.routes) { route in
                    RouteCard(route: route,
                              isActive: simulator.activeRouteID == route.id,
                              onOpen: { navigator.routesPath.append(RoutesDestination.routeDetail(route.id)) },
                              onQuickStart: { toggle(route) })
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) { deleteTarget = route } label: {
                                Label(L10n.delete, systemImage: "trash")
                            }
                            Button {
                                renameText = route.name
                                renameTarget = route
                            } label: {
                                Label(L("common.rename"), systemImage: "pencil")
                            }
                            .tint(AppColor.accent)
                        }
                        .contextMenu {
                            Button { toggle(route) } label: {
                                Label(simulator.activeRouteID == route.id ? L10n.stop : L("routes.run_now"),
                                      systemImage: simulator.activeRouteID == route.id ? "stop.fill" : "play.fill")
                            }
                            Button { routeStore.reverse(id: route.id) } label: {
                                Label(L("route.reverse"), systemImage: "arrow.uturn.backward")
                            }
                            Button {
                                renameText = route.name
                                renameTarget = route
                            } label: {
                                Label(L("common.rename"), systemImage: "pencil")
                            }
                            Divider()
                            Button(role: .destructive) { deleteTarget = route } label: {
                                Label(L10n.delete, systemImage: "trash")
                            }
                        }
                }
            }
        } header: {
            Text(L("routes.saved"))
        } footer: {
            if !routeStore.routes.isEmpty {
                Text(L("routes.saved_footer"))
            }
        }
    }

    // MARK: - Kịch bản

    @ViewBuilder
    private var scenariosSection: some View {
        Section {
            if scenarioEngine.scenarios.isEmpty {
                HubRow(title: L("scenario.title"),
                       subtitle: L("scenario.subtitle"),
                       symbol: SimulationSource.scenario.icon,
                       tint: AppColor.accent) {
                    navigator.present(.scenarioStudio)
                }
            } else {
                ForEach(scenarioEngine.scenarios) { scenario in
                    ScenarioCard(scenario: scenario,
                                 isActive: scenarioEngine.isRunning && scenarioEngine.currentScenarioID == scenario.id,
                                 progress: scenarioEngine.progress,
                                 onOpen: { navigator.present(.scenarioStudio) },
                                 onQuickStart: { toggle(scenario) })
                }
                HubRow(title: L("scenario.manage"),
                       subtitle: L("scenario.manage_subtitle"),
                       symbol: "slider.horizontal.3",
                       tint: AppColor.textSecondary) {
                    navigator.present(.scenarioStudio)
                }
            }
        } header: {
            Text(L("scenario.title"))
        }
    }

    // MARK: - Tự động

    private var automationSection: some View {
        Section {
            HubRow(title: L("routine.title"),
                   subtitle: L("routine.subtitle"),
                   symbol: SimulationSource.routine.icon,
                   tint: AppColor.warning,
                   badge: routine.isAutoRoutineEnabled ? L("routine.enabled_badge") : nil) {
                navigator.present(.routineStudio)
            }
        } header: {
            Text(L("routes.automation"))
        } footer: {
            Text(routine.isAutoRoutineEnabled
                 ? L("routine.running_status", routine.statusDescription)
                 : L("routine.footer"))
        }
    }

    // MARK: - Địa điểm & lịch sử

    private var placesSection: some View {
        Section(L("routes.places_history")) {
            HubRow(title: L("bookmarks.title"),
                   subtitle: L("bookmarks.subtitle"),
                   symbol: "bookmark.fill",
                   tint: AppColor.success) {
                navigator.present(.bookmarks)
            }
            HubRow(title: L("history.title"),
                   subtitle: L("history.subtitle"),
                   symbol: "clock.arrow.circlepath",
                   tint: AppColor.textSecondary,
                   badge: history.records.isEmpty ? nil : "\(history.records.count)") {
                navigator.present(.history)
            }
        }
    }

    // MARK: - Phiên đang chạy

    private func activeSessionRow(source: SimulationSource) -> some View {
        Button {
            navigator.select(.map)
        } label: {
            HStack(spacing: AppSpacing.md) {
                StatusIndicatorDot(color: coordinator.state.tint,
                                   isPulsing: coordinator.state == .running, size: 9)
                VStack(alignment: .leading, spacing: 1) {
                    Text(activeTitle(source: source))
                        .font(AppFont.callout)
                        .foregroundStyle(AppColor.textPrimary)
                        .lineLimit(1)
                    Text("\(AppFormat.speed(coordinator.telemetry.speedKmh)) km/h · \(AppFormat.coordinate(coordinator.currentCoordinate, precision: 4))")
                        .font(AppFont.monoFootnote)
                        .foregroundStyle(AppColor.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(L("common.view"))
                    .font(AppFont.footnoteEmphasized)
                    .foregroundStyle(AppColor.primary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(L("a11y.open_map_session"))
    }

    private func activeTitle(source: SimulationSource) -> String {
        if let name = simulator.activeRouteName {
            return "\(name) · \(coordinator.state.displayName)"
        }
        return "\(source.displayName) · \(coordinator.state.displayName)"
    }

    // MARK: - Hành động

    /// Chạy nhanh / dừng một tuyến, rồi nhảy sang bản đồ để thấy nó đang chạy.
    private func toggle(_ route: SavedRoute) {
        if simulator.activeRouteID == route.id {
            AppHaptics.stop()
            simulator.stop()
            return
        }

        let coordinates = route.runnableCoordinates
        guard coordinates.count >= 2 else {
            AppHaptics.failure()
            failureMessage = L("routes.no_geometry", route.name)
            return
        }

        AppHaptics.start()
        let started = simulator.start(coordinates: coordinates,
                                      travelMode: route.travelMode,
                                      routeName: route.name,
                                      routeID: route.id)
        if started {
            routeStore.markUsed(id: route.id)
            navigator.select(.map)
        } else {
            AppHaptics.failure()
            failureMessage = simulator.lastFailure ?? L("routes.start_failed_message")
        }
    }

    private func toggle(_ scenario: Scenario) {
        if scenarioEngine.isRunning && scenarioEngine.currentScenarioID == scenario.id {
            AppHaptics.stop()
            scenarioEngine.stop()
        } else {
            AppHaptics.start()
            scenarioEngine.start(scenario: scenario)
            navigator.select(.map)
        }
    }

    // MARK: - Binding phụ trợ

    private var renameBinding: Binding<Bool> {
        Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })
    }

    private var failureBinding: Binding<Bool> {
        Binding(get: { failureMessage != nil }, set: { if !$0 { failureMessage = nil } })
    }
}

#Preview {
    NavigationStack { RoutesScreen() }
}
