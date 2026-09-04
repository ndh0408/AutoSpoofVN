import CoreLocation
import MapKit
import SwiftUI

/// Chi tiết một tuyến đã lưu: xem trước, cấu hình phương tiện/tốc độ, chạy, xuất, xoá.
struct RouteDetailScreen: View {
    let routeID: UUID

    @Environment(\.navigator) private var navigator
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var routeStore = SavedRouteStore.shared
    @ObservedObject private var simulator = RouteSimulator.shared

    @State private var camera: MapCameraPosition = .automatic
    @State private var isRecalculating = false
    @State private var recalcMessage: String?
    @State private var showDeleteConfirm = false
    @State private var exportURL: URL?

    private var route: SavedRoute? { routeStore.route(id: routeID) }

    var body: some View {
        Group {
            if let route {
                content(route)
            } else {
                // Tuyến vừa bị xoá từ nơi khác — không để lại màn hình trắng.
                EmptyStateView(icon: "trash",
                               title: L("route.detail.missing"),
                               message: L("route.detail.missing_message"),
                               actionTitle: L("common.back")) { dismiss() }
            }
        }
        .navigationTitle(route?.name ?? L("route.title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func content(_ route: SavedRoute) -> some View {
        List {
            Section {
                RoutePreviewMap(coordinates: route.runnableCoordinates, camera: $camera)
                    .frame(height: 220)
                    .listRowInsets(EdgeInsets())
            }

            Section(L("route.detail.overview")) {
                MetricRow(L("route.total_distance"), value: AppFormat.distance(route.totalDistanceMeters), icon: "ruler")
                MetricRow(L("route.estimated_duration"), value: AppFormat.duration(route.estimatedDurationSeconds), icon: "clock")
                MetricRow(L("route.stop_count"), value: "\(route.waypoints.count)", icon: "mappin.and.ellipse")
                MetricRow(L("route.geometry_point_count"),
                          value: "\(route.routeGeometry?.count ?? 0)",
                          icon: "point.topleft.down.to.point.bottomright.curvepath")
                if let used = route.lastUsedAt {
                    MetricRow(L("route.last_used"),
                              value: used.formatted(date: .abbreviated, time: .shortened),
                              icon: "clock.arrow.circlepath", monospaced: false)
                }
            }

            Section {
                Picker(L("route.travel_mode"), selection: travelModeBinding(route)) {
                    ForEach(TravelMode.allCases) { mode in
                        Label(mode.displayName, systemImage: mode.icon).tag(mode)
                    }
                }

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    HStack {
                        Text(L("route.cruise_speed"))
                            .font(AppFont.callout)
                        Spacer()
                        Text("\(Int(route.effectiveCruiseSpeedKmh)) km/h")
                            .font(AppFont.monoFootnote)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    Slider(value: cruiseSpeedBinding(route),
                           in: speedRange(for: route.travelMode),
                           step: 1)
                        .tint(AppColor.primary)
                        .accessibilityLabel(L("route.cruise_speed"))
                        .accessibilityValue(L("a11y.speed_kmh", Int(route.effectiveCruiseSpeedKmh)))
                }
            } header: {
                Text(L("route.detail.config"))
            } footer: {
                Text(L("route.detail.config_footer"))
            }

            Section {
                Button {
                    start(route)
                } label: {
                    Label(isActive ? L("route.stop") : L("route.detail.run"),
                          systemImage: isActive ? "stop.fill" : "play.fill")
                }
                .foregroundStyle(isActive ? AppColor.danger : AppColor.primary)

                Button {
                    Task { await recalculate(route) }
                } label: {
                    HStack {
                        Label(L("route.recalculate"), systemImage: "arrow.triangle.turn.up.right.diamond")
                        if isRecalculating {
                            Spacer()
                            ProgressView().controlSize(.small)
                        }
                    }
                }
                .disabled(isRecalculating || route.waypoints.count < 2)

                Button {
                    routeStore.reverse(id: route.id)
                    AppHaptics.selection()
                } label: {
                    Label(L("route.reverse"), systemImage: "arrow.uturn.backward")
                }

                Button {
                    export(route)
                } label: {
                    Label(L("route.export_gpx"), systemImage: "square.and.arrow.up")
                }
                .disabled(route.runnableCoordinates.count < 2)
            } header: {
                Text(L("common.actions"))
            } footer: {
                if let recalcMessage {
                    Text(recalcMessage)
                } else if route.routeGeometry == nil {
                    Text(L("route.detail.no_geometry_footer"))
                }
            }

            Section {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label(L("route.delete"), systemImage: "trash")
                }
            }
        }
        .listStyle(.insetGrouped)
        .confirmationDialog(L("route.delete_confirm"), isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button(L10n.delete, role: .destructive) {
                routeStore.delete(id: route.id)
                dismiss()
            }
            Button(L10n.cancel, role: .cancel) {}
        } message: {
            Text(L("route.delete_message", route.name))
        }
        .sheet(isPresented: exportBinding) {
            if let exportURL {
                ShareSheet(items: [exportURL])
            }
        }
    }

    private var isActive: Bool { simulator.activeRouteID == routeID }

    // MARK: - Binding

    private func travelModeBinding(_ route: SavedRoute) -> Binding<TravelMode> {
        Binding(
            get: { route.travelMode },
            set: { mode in
                var updated = route
                updated.travelMode = mode
                // Đổi phương tiện thì tốc độ cũ không còn hợp lý — trả về mặc định.
                updated.cruiseSpeedKmh = nil
                routeStore.update(updated)
                AppHaptics.selection()
            }
        )
    }

    private func cruiseSpeedBinding(_ route: SavedRoute) -> Binding<Double> {
        Binding(
            get: { route.effectiveCruiseSpeedKmh },
            set: { speed in
                var updated = route
                updated.cruiseSpeedKmh = speed
                // Thời gian ước tính phải đi theo tốc độ, nếu không thẻ tuyến nói dối.
                if updated.totalDistanceMeters > 0, speed > 0 {
                    updated.estimatedDurationSeconds = updated.totalDistanceMeters / (speed / 3.6)
                }
                routeStore.update(updated)
            }
        )
    }

    private func speedRange(for mode: TravelMode) -> ClosedRange<Double> {
        let profile = mode.defaultSpeed
        return max(1, profile.min)...max(profile.min + 1, profile.max)
    }

    private var exportBinding: Binding<Bool> {
        Binding(get: { exportURL != nil }, set: { if !$0 { exportURL = nil } })
    }

    // MARK: - Hành động

    private func start(_ route: SavedRoute) {
        if isActive {
            AppHaptics.stop()
            simulator.stop()
            return
        }
        let coordinates = route.runnableCoordinates
        guard coordinates.count >= 2 else {
            AppHaptics.failure()
            recalcMessage = L("route.detail.not_enough_points")
            return
        }
        AppHaptics.start()
        if simulator.start(coordinates: coordinates,
                           travelMode: route.travelMode,
                           routeName: route.name,
                           routeID: route.id) {
            routeStore.markUsed(id: route.id)
            navigator.select(.map)
        } else {
            AppHaptics.failure()
            recalcMessage = simulator.lastFailure
        }
    }

    /// Tính lại hình học qua **tất cả** waypoint và lưu lại đầy đủ.
    private func recalculate(_ route: SavedRoute) async {
        isRecalculating = true
        recalcMessage = nil
        defer { isRecalculating = false }

        let result = await RouteBuilder.build(waypoints: route.waypoints, travelMode: route.travelMode)
        guard result.geometry.count >= 2 else {
            recalcMessage = result.errorDescription ?? L("route.recalc_failed")
            AppHaptics.failure()
            return
        }

        var updated = route
        updated.routeGeometry = result.geometry.map(CoordinateCodable.init)
        updated.totalDistanceMeters = result.distanceMeters
        updated.estimatedDurationSeconds = result.durationSeconds
        routeStore.update(updated)

        recalcMessage = L("route.detail.updated", result.sourceDescription)
        AppHaptics.selection()
    }

    private func export(_ route: SavedRoute) {
        let coordinates = route.runnableCoordinates.map(CoordinateCodable.init)
        let safeName = route.name.replacingOccurrences(of: "/", with: "-")
        guard let url = PersistenceManager.shared.exportGPX(coordinates: coordinates, name: safeName) else {
            AppHaptics.failure()
            recalcMessage = L("route.export_failed")
            return
        }
        exportURL = url
    }
}

// MARK: - RoutePreviewMap

/// Bản đồ xem trước tuyến, tự khớp khung nhìn vào toàn tuyến.
struct RoutePreviewMap: View {
    let coordinates: [CLLocationCoordinate2D]
    @Binding var camera: MapCameraPosition

    var body: some View {
        Map(position: $camera, interactionModes: [.pan, .zoom]) {
            if coordinates.count >= 2 {
                MapPolyline(coordinates: coordinates)
                    .stroke(AppColor.mapRoute,
                            style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                if let start = coordinates.first {
                    Annotation(L("route.waypoint.start"), coordinate: start, anchor: .center) {
                        SavedPlaceMarker(symbol: "flag.fill", tint: AppColor.success)
                    }
                    .annotationTitles(.hidden)
                }
                if let end = coordinates.last {
                    Annotation(L("route.waypoint.end"), coordinate: end, anchor: .center) {
                        SavedPlaceMarker(symbol: "flag.checkered", tint: AppColor.danger)
                    }
                    .annotationTitles(.hidden)
                }
            }
        }
        .onAppear { fit() }
        .onChange(of: coordinates.count) { _, _ in fit() }
        .accessibilityLabel(L("a11y.route_preview"))
    }

    private func fit() {
        guard coordinates.count >= 2 else { return }
        camera = .region(RouteSnapshotCache.region(fitting: coordinates))
    }
}

// MARK: - ShareSheet

/// Bọc `UIActivityViewController` — SwiftUI `ShareLink` không nhận `URL` file tạm
/// một cách đáng tin trên mọi phiên bản, còn đây thì luôn được.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
