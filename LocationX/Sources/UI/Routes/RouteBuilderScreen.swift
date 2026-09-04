import CoreLocation
import MapKit
import SwiftUI
import UniformTypeIdentifiers

/// Trình tạo tuyến đường.
///
/// Luồng: chọn điểm → tính tuyến → xem trước → chọn phương tiện & tốc độ → lưu / chạy.
/// Các bước hiện dần (progressive disclosure): chưa đủ điểm thì chưa hiện phần tính tuyến,
/// chưa tính xong thì chưa hiện phần tốc độ.
struct RouteBuilderScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.navigator) private var navigator
    @StateObject private var model = RouteBuilderModel()

    @State private var camera: MapCameraPosition = .camera(
        MapCamera(centerCoordinate: SimulationCoordinator.shared.currentCoordinate, distance: 12_000)
    )
    @State private var showSearch = false
    @State private var showImporter = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                mapSection
                Divider()
                formSection
            }
            .navigationTitle(L("route.builder.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showImporter = true
                        } label: {
                            Label(L("route.builder.import_gpx"), systemImage: "square.and.arrow.down")
                        }
                        Button {
                            model.reverse()
                        } label: {
                            Label(L("route.reverse"), systemImage: "arrow.uturn.backward")
                        }
                        .disabled(model.waypoints.count < 2)
                        Divider()
                        Button(role: .destructive) {
                            model.clearAll()
                        } label: {
                            Label(L("route.builder.clear_all"), systemImage: "trash")
                        }
                        .disabled(model.waypoints.isEmpty)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibleButton(label: L("a11y.more_options"))
                }
            }
            .sheet(isPresented: $showSearch) {
                LocationSearchView { result in
                    model.addWaypoint(at: result.coordinate, name: result.name)
                    focusOnWaypoints()
                }
            }
            // Nút "Import GPX" cũ chỉ đặt `showImport = true` mà KHÔNG có sheet nào gắn
            // vào cờ đó — bấm vào không xảy ra chuyện gì. Đây là lần đầu nó hoạt động.
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: Self.gpxContentTypes,
                          allowsMultipleSelection: false) { result in
                model.importGPX(result: result)
                focusOnWaypoints()
            }
            .alert(L("route.builder.import_failed"), isPresented: model.importErrorBinding) {
                Button(L10n.close, role: .cancel) { model.importError = nil }
            } message: {
                Text(model.importError ?? "")
            }
        }
    }

    /// GPX không có UTType hệ thống; khai báo theo phần mở rộng và cho phép cả XML thuần.
    private static var gpxContentTypes: [UTType] {
        var types: [UTType] = [.xml, .data]
        if let gpx = UTType(filenameExtension: "gpx") { types.insert(gpx, at: 0) }
        return types
    }

    // MARK: - Bản đồ

    private var mapSection: some View {
        MapReader { proxy in
            Map(position: $camera, interactionModes: .all) {
                if model.previewGeometry.count >= 2 {
                    MapPolyline(coordinates: model.previewGeometry)
                        .stroke(AppColor.mapRoute,
                                style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }
                ForEach(Array(model.waypoints.enumerated()), id: \.element.id) { index, waypoint in
                    Annotation("", coordinate: waypoint.coordinate.clCoordinate, anchor: .center) {
                        WaypointMarker(index: index, total: model.waypoints.count)
                    }
                    .annotationTitles(.hidden)
                }
            }
            .onTapGesture { point in
                guard let coordinate = proxy.convert(point, from: .local) else { return }
                AppHaptics.selection()
                model.addWaypoint(at: coordinate)
            }
            .overlay(alignment: .top) {
                if model.waypoints.isEmpty {
                    Text(L("route.builder.map_hint"))
                        .font(AppFont.caption1)
                        .foregroundStyle(AppColor.textSecondary)
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, AppSpacing.sm)
                        .glassCapsule(material: AppMaterial.bar)
                        .padding(.top, AppSpacing.sm)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Biểu mẫu

    private var formSection: some View {
        List {
            Section {
                Button {
                    showSearch = true
                } label: {
                    Label(L("route.builder.search_place"), systemImage: "magnifyingglass")
                }

                if model.waypoints.isEmpty {
                    Text(L("route.builder.no_waypoints"))
                        .font(AppFont.footnote)
                        .foregroundStyle(AppColor.textTertiary)
                } else {
                    ForEach(Array(model.waypoints.enumerated()), id: \.element.id) { index, waypoint in
                        HStack(spacing: AppSpacing.md) {
                            WaypointMarker(index: index, total: model.waypoints.count)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(waypoint.name ?? L("route.waypoint_number", index + 1))
                                    .font(AppFont.callout)
                                    .lineLimit(1)
                                Text(AppFormat.coordinate(waypoint.coordinate.clCoordinate, precision: 5))
                                    .font(AppFont.monoFootnote)
                                    .foregroundStyle(AppColor.textTertiary)
                            }
                            Spacer()
                        }
                        .accessibilityElement(children: .combine)
                    }
                    .onDelete { model.remove(atOffsets: $0) }
                    .onMove { model.move(from: $0, to: $1) }
                }
            } header: {
                Text(L("route.builder.stops"))
            } footer: {
                Text(LocalizedStringKey(L("route.builder.stops_footer")))
            }

            Section(L("route.travel_mode")) {
                Picker(L("route.travel_mode"), selection: $model.travelMode) {
                    ForEach(TravelMode.allCases) { mode in
                        Label(mode.displayName, systemImage: mode.icon).tag(mode)
                    }
                }
                .pickerStyle(.menu)
            }

            if model.waypoints.count >= 2 {
                Section {
                    Button {
                        Task { await model.calculate() }
                    } label: {
                        HStack {
                            Label(model.hasPreview ? L("route.recalculate") : L("route.builder.calculate"),
                                  systemImage: "arrow.triangle.turn.up.right.diamond")
                            if model.isCalculating {
                                Spacer()
                                ProgressView().controlSize(.small)
                            }
                        }
                    }
                    .disabled(model.isCalculating)
                } footer: {
                    if let error = model.calculationNote {
                        Text(error)
                    }
                }
            }

            if model.hasPreview {
                Section(L("route.builder.preview")) {
                    MetricRow(L("route.total_distance"), value: AppFormat.distance(model.distanceMeters), icon: "ruler")
                    MetricRow(L("route.duration"), value: AppFormat.duration(model.durationSeconds), icon: "clock")
                    MetricRow(L("route.source"), value: model.sourceDescription, icon: "map", monospaced: false)
                    MetricRow(L("route.point_count"), value: "\(model.previewGeometry.count)", icon: "circle.grid.3x3")
                }

                Section {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        HStack {
                            Text(L("route.cruise_speed")).font(AppFont.callout)
                            Spacer()
                            Text("\(Int(model.cruiseSpeedKmh)) km/h")
                                .font(AppFont.monoFootnote)
                                .foregroundStyle(AppColor.textSecondary)
                        }
                        Slider(value: $model.cruiseSpeedKmh,
                               in: model.speedRange, step: 1)
                            .tint(AppColor.primary)
                            .accessibilityLabel(L("route.cruise_speed"))
                            .accessibilityValue(L("a11y.speed_kmh", Int(model.cruiseSpeedKmh)))
                    }
                } header: {
                    Text(L("route.speed"))
                } footer: {
                    Text(L("route.builder.estimated_duration", AppFormat.duration(model.durationAtChosenSpeed)))
                }

                Section {
                    TextField(L("route.name_placeholder"), text: $model.name)
                        .textInputAutocapitalization(.sentences)

                    Button {
                        save(andRun: false)
                    } label: {
                        Label(L("route.builder.save"), systemImage: "square.and.arrow.down")
                    }

                    Button {
                        save(andRun: true)
                    } label: {
                        Label(L("route.builder.save_and_run"), systemImage: "play.fill")
                    }
                    .fontWeight(.semibold)
                } header: {
                    Text(L("route.builder.finish"))
                }
            }
        }
        .listStyle(.insetGrouped)
        .frame(maxHeight: .infinity)
        .environment(\.editMode, .constant(.active))
    }

    // MARK: - Hành động

    private func save(andRun run: Bool) {
        guard let route = model.buildRoute() else { return }
        SavedRouteStore.shared.add(route)
        AppHaptics.start()

        if run {
            let started = RouteSimulator.shared.start(coordinates: route.runnableCoordinates,
                                                      travelMode: route.travelMode,
                                                      routeName: route.name,
                                                      routeID: route.id)
            if started {
                SavedRouteStore.shared.markUsed(id: route.id)
                dismiss()
                navigator.select(.map)
                return
            }
            AppHaptics.failure()
        }
        dismiss()
    }

    private func focusOnWaypoints() {
        let coordinates = model.previewGeometry.isEmpty
            ? model.waypoints.map { $0.coordinate.clCoordinate }
            : model.previewGeometry
        guard coordinates.count >= 1 else { return }
        if coordinates.count == 1 {
            camera = .camera(MapCamera(centerCoordinate: coordinates[0], distance: 5_000))
        } else {
            camera = .region(RouteSnapshotCache.region(fitting: coordinates))
        }
    }
}

// MARK: - Model

@MainActor
final class RouteBuilderModel: ObservableObject {
    @Published var waypoints: [RouteWaypoint] = []
    @Published var travelMode: TravelMode = .driving {
        didSet {
            guard travelMode != oldValue else { return }
            cruiseSpeedKmh = travelMode.defaultSpeed.cruise
            // Đổi phương tiện đổi cả mạng đường (đi bộ vs ô tô) nên hình học cũ không còn đúng.
            previewGeometry = []
            calculationNote = nil
        }
    }
    @Published var previewGeometry: [CLLocationCoordinate2D] = []
    @Published var distanceMeters: Double = 0
    @Published var durationSeconds: TimeInterval = 0
    @Published var sourceDescription: String = "—"
    @Published var calculationNote: String?
    @Published var isCalculating = false
    @Published var cruiseSpeedKmh: Double = TravelMode.driving.defaultSpeed.cruise
    @Published var name: String = ""
    @Published var importError: String?

    var hasPreview: Bool { previewGeometry.count >= 2 }

    var speedRange: ClosedRange<Double> {
        let profile = travelMode.defaultSpeed
        return max(1, profile.min)...max(profile.min + 1, profile.max)
    }

    /// Thời gian ước tính theo tốc độ người dùng chọn (không phải tốc độ MapKit trả về).
    var durationAtChosenSpeed: TimeInterval {
        guard cruiseSpeedKmh > 0, distanceMeters > 0 else { return durationSeconds }
        return distanceMeters / (cruiseSpeedKmh / 3.6)
    }

    var importErrorBinding: Binding<Bool> {
        Binding(get: { [weak self] in self?.importError != nil },
                set: { [weak self] in if !$0 { self?.importError = nil } })
    }

    // MARK: Waypoints

    func addWaypoint(at coordinate: CLLocationCoordinate2D, name: String? = nil) {
        guard CLLocationCoordinate2DIsValid(coordinate) else { return }
        waypoints.append(RouteWaypoint(coordinate: coordinate, name: name))
        invalidatePreview()
    }

    func remove(atOffsets offsets: IndexSet) {
        waypoints.remove(atOffsets: offsets)
        invalidatePreview()
    }

    func move(from source: IndexSet, to destination: Int) {
        waypoints.move(fromOffsets: source, toOffset: destination)
        invalidatePreview()
    }

    func reverse() {
        waypoints.reverse()
        previewGeometry.reverse()
    }

    func clearAll() {
        waypoints.removeAll()
        invalidatePreview()
        distanceMeters = 0
        durationSeconds = 0
        sourceDescription = "—"
    }

    private func invalidatePreview() {
        previewGeometry = []
        calculationNote = nil
    }

    // MARK: Tính tuyến

    func calculate() async {
        guard waypoints.count >= 2 else { return }
        isCalculating = true
        calculationNote = nil
        defer { isCalculating = false }

        let result = await RouteBuilder.build(waypoints: waypoints, travelMode: travelMode)
        guard result.geometry.count >= 2 else {
            calculationNote = result.errorDescription ?? L("route.builder.calc_failed")
            AppHaptics.failure()
            return
        }

        previewGeometry = result.geometry
        distanceMeters = result.distanceMeters
        durationSeconds = result.durationSeconds
        sourceDescription = result.sourceDescription
        if result.usedFallback {
            calculationNote = L("route.builder.fallback_note", result.fallbackLegCount, result.legCount)
        }
        if name.isEmpty { name = defaultName() }
        AppHaptics.selection()
    }

    // MARK: GPX

    func importGPX(result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importError = error.localizedDescription

        case .success(let urls):
            guard let url = urls.first else { return }
            // File do người dùng chọn nằm ngoài sandbox — phải xin quyền truy cập.
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            guard let coordinates = PersistenceManager.shared.importGPX(from: url),
                  coordinates.count >= 2 else {
                importError = L("route.builder.gpx_no_points")
                return
            }

            let clCoordinates = coordinates.map(\.clCoordinate)
            // Track GPX đã là hình học đầy đủ — dùng thẳng, chỉ giữ hai đầu làm điểm dừng
            // để người dùng còn sửa được.
            previewGeometry = clCoordinates
            waypoints = [
                RouteWaypoint(coordinate: clCoordinates.first!, name: L("route.waypoint.start")),
                RouteWaypoint(coordinate: clCoordinates.last!, name: L("route.waypoint.end")),
            ]
            let cumulative = RouteSimulator.cumulativeDistances(of: clCoordinates)
            distanceMeters = cumulative.last ?? 0
            durationSeconds = distanceMeters / max(1, cruiseSpeedKmh / 3.6)
            sourceDescription = L("route.source.gpx")
            calculationNote = L("route.import.done", clCoordinates.count, url.lastPathComponent)
            if name.isEmpty {
                name = url.deletingPathExtension().lastPathComponent
            }
            AppHaptics.selection()
        }
    }

    // MARK: Kết quả

    func buildRoute() -> SavedRoute? {
        guard previewGeometry.count >= 2 else { return nil }
        let finalName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return SavedRoute(
            name: finalName.isEmpty ? defaultName() : finalName,
            waypoints: waypoints,
            travelMode: travelMode,
            geometry: previewGeometry.map(CoordinateCodable.init),
            totalDistanceMeters: distanceMeters,
            estimatedDurationSeconds: durationAtChosenSpeed,
            cruiseSpeedKmh: cruiseSpeedKmh
        )
    }

    private func defaultName() -> String {
        let start = waypoints.first?.name
        let end = waypoints.last?.name
        if let start, let end { return "\(start) → \(end)" }
        return L("route.default_name", Date().formatted(date: .abbreviated, time: .shortened))
    }
}

// MARK: - WaypointMarker

/// Ghim điểm dừng: xanh = bắt đầu, đỏ = kết thúc, xanh dương = điểm giữa.
struct WaypointMarker: View {
    let index: Int
    let total: Int

    private var tint: Color {
        if index == 0 { return AppColor.success }
        if index == total - 1 { return AppColor.danger }
        return AppColor.primary
    }

    var body: some View {
        Text("\(index + 1)")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(tint, in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
            .accessibilityLabel(L("a11y.waypoint_index", index + 1, total))
    }
}
