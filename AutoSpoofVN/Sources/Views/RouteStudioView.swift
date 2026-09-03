import CoreLocation
import MapKit
import SwiftUI

/// Route Studio — tạo, chỉnh sửa, quản lý tuyến đường.
struct RouteStudioView: View {
    @StateObject private var viewModel = RouteStudioViewModel()
    @EnvironmentObject var engine: SpoofEngine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                // Map
                RouteMapView(
                    waypoints: $viewModel.waypoints,
                    routeCoordinates: viewModel.routeGeometry,
                    onTap: { coord in viewModel.addWaypoint(at: coord) }
                )
                .ignoresSafeArea(edges: .top)

                // Bottom sheet
                VStack {
                    Spacer()
                    routePanel
                }
            }
            .navigationTitle("Route Studio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Đóng") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("Đảo ngược", systemImage: "arrow.uturn.backward") { viewModel.reverseRoute() }
                        Button("Xoá tất cả", systemImage: "trash", role: .destructive) { viewModel.clearAll() }
                        Divider()
                        Button("Import GPX", systemImage: "square.and.arrow.down") { viewModel.showImport = true }
                        Button("Export GPX", systemImage: "square.and.arrow.up") { viewModel.exportGPX() }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $viewModel.showSearch) {
                LocationSearchView { result in
                    viewModel.addWaypoint(at: result.coordinate, name: result.name)
                    viewModel.showSearch = false
                }
            }
        }
    }

    private var routePanel: some View {
        VStack(spacing: AppSpacing.md) {
            // Handle bar
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, AppSpacing.sm)

            // Search button
            Button {
                viewModel.showSearch = true
            } label: {
                HStack {
                    Image(systemName: "magnifyingglass")
                    Text("Tìm địa điểm...")
                        .foregroundStyle(AppColor.textSecondary)
                    Spacer()
                }
                .padding(AppSpacing.md)
                .background(AppColor.surfaceTertiary)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
            }

            // Travel mode picker
            Picker("Phương tiện", selection: $viewModel.travelMode) {
                ForEach(TravelMode.allCases) { mode in
                    Label(mode.displayName, systemImage: mode.icon).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            // Waypoints list
            if !viewModel.waypoints.isEmpty {
                VStack(spacing: AppSpacing.xs) {
                    ForEach(Array(viewModel.waypoints.enumerated()), id: \.element.id) { index, wp in
                        HStack {
                            Circle()
                                .fill(index == 0 ? Color.green : (index == viewModel.waypoints.count - 1 ? Color.red : Color.blue))
                                .frame(width: 8, height: 8)
                            Text(wp.name ?? "Điểm \(index + 1)")
                                .font(AppFont.footnote)
                            Spacer()
                            Text(String(format: "%.4f, %.4f", wp.coordinate.latitude, wp.coordinate.longitude))
                                .font(AppFont.mono)
                                .foregroundStyle(AppColor.textTertiary)
                            Button { viewModel.removeWaypoint(at: index) } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(AppColor.textTertiary)
                            }
                        }
                        .padding(.vertical, AppSpacing.xs)
                    }
                }
            }

            // Route info
            if viewModel.routeGeometry != nil {
                HStack {
                    MetricView("Khoảng cách", value: viewModel.distanceText, icon: "ruler")
                    Spacer()
                    MetricView("Thời gian", value: viewModel.durationText, icon: "clock")
                    Spacer()
                    MetricView("Nguồn", value: viewModel.routeSourceText, icon: "map")
                }
            }

            // Action buttons
            HStack(spacing: AppSpacing.md) {
                if viewModel.waypoints.count >= 2 {
                    Button {
                        Task { await viewModel.calculateRoute() }
                    } label: {
                        Label("Tính tuyến", systemImage: "arrow.triangle.turn.up.right.diamond")
                            .font(AppFont.callout.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, AppSpacing.md)
                            .background(AppColor.surfaceTertiary)
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
                    }
                }

                if viewModel.routeGeometry != nil {
                    Button {
                        viewModel.startSimulation()
                        dismiss()
                    } label: {
                        Label("Bắt đầu", systemImage: "play.fill")
                            .font(AppFont.callout.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, AppSpacing.md)
                            .background(AppColor.primary)
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
                    }
                }
            }

            // Save button
            if !viewModel.waypoints.isEmpty {
                Button {
                    viewModel.saveRoute()
                } label: {
                    Label("Lưu tuyến đường", systemImage: "square.and.arrow.down")
                        .font(AppFont.footnote)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.bottom, AppSpacing.xl)
        .background(
            AppColor.surface
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.xl))
                .shadow(color: .black.opacity(0.1), radius: 10, y: -5)
        )
    }
}

// MARK: - ViewModel

@MainActor
final class RouteStudioViewModel: ObservableObject {
    @Published var waypoints: [RouteWaypoint] = []
    @Published var travelMode: TravelMode = .driving
    @Published var routeGeometry: [CLLocationCoordinate2D]? = nil
    @Published var routeSource: String = ""
    @Published var showSearch = false
    @Published var showImport = false

    private var totalDistanceMeters: Double = 0
    private var estimatedSeconds: TimeInterval = 0

    var distanceText: String {
        if totalDistanceMeters > 1000 {
            return String(format: "%.1f km", totalDistanceMeters / 1000)
        }
        return String(format: "%.0f m", totalDistanceMeters)
    }

    var durationText: String {
        let mins = Int(estimatedSeconds) / 60
        if mins > 60 { return String(format: "%dh%02dm", mins/60, mins%60) }
        return "\(mins) phút"
    }

    var routeSourceText: String { routeSource.isEmpty ? "—" : routeSource }

    func addWaypoint(at coordinate: CLLocationCoordinate2D, name: String? = nil) {
        waypoints.append(RouteWaypoint(coordinate: coordinate, name: name))
    }

    func removeWaypoint(at index: Int) {
        guard waypoints.indices.contains(index) else { return }
        waypoints.remove(at: index)
        routeGeometry = nil
    }

    func reverseRoute() {
        waypoints.reverse()
        routeGeometry = nil
    }

    func clearAll() {
        waypoints.removeAll()
        routeGeometry = nil
        totalDistanceMeters = 0
        estimatedSeconds = 0
    }

    func calculateRoute() async {
        guard waypoints.count >= 2 else { return }
        let start = waypoints.first!.coordinate.clCoordinate
        let end = waypoints.last!.coordinate.clCoordinate

        let result = await RouteProvider.shared.route(
            from: start, to: end,
            transportType: travelMode == .walking ? .walking : .automobile
        )

        routeGeometry = result.plan.coordinates.map { $0.clCoordinate }
        totalDistanceMeters = result.distanceMeters
        estimatedSeconds = result.expectedTravelTime ?? (result.distanceMeters / (travelMode.defaultSpeed.cruise / 3.6))
        routeSource = result.source.displayName
    }

    func startSimulation() {
        guard let geometry = routeGeometry else { return }
        let coords = geometry
        let simulator = RouteSimulator()
        simulator.start(coordinates: coords, travelMode: travelMode)
    }

    func saveRoute() {
        let route = SavedRoute(
            name: "Tuyến \(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short))",
            waypoints: waypoints,
            travelMode: travelMode
        )
        var routes = PersistenceManager.shared.loadRoutes()
        routes.insert(route, at: 0)
        PersistenceManager.shared.saveRoutes(routes)
    }

    func exportGPX() {
        guard let geometry = routeGeometry else { return }
        let coords = geometry.map { CoordinateCodable($0) }
        _ = PersistenceManager.shared.exportGPX(coordinates: coords, name: "route_\(Date().timeIntervalSince1970)")
    }
}

// MARK: - Route Map View

struct RouteMapView: UIViewRepresentable {
    @Binding var waypoints: [RouteWaypoint]
    let routeCoordinates: [CLLocationCoordinate2D]?
    let onTap: (CLLocationCoordinate2D) -> Void

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        map.addGestureRecognizer(tap)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        map.removeAnnotations(map.annotations)
        map.removeOverlays(map.overlays)

        // Waypoint annotations
        for (i, wp) in waypoints.enumerated() {
            let ann = MKPointAnnotation()
            ann.coordinate = wp.coordinate.clCoordinate
            ann.title = wp.name ?? "Điểm \(i + 1)"
            map.addAnnotation(ann)
        }

        // Route polyline
        if let coords = routeCoordinates, coords.count >= 2 {
            let polyline = MKPolyline(coordinates: coords, count: coords.count)
            map.addOverlay(polyline)
            map.setVisibleMapRect(
                polyline.boundingMapRect,
                edgePadding: UIEdgeInsets(top: 60, left: 40, bottom: 200, right: 40),
                animated: true
            )
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap)
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        let onTap: (CLLocationCoordinate2D) -> Void

        init(onTap: @escaping (CLLocationCoordinate2D) -> Void) {
            self.onTap = onTap
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let mapView = gesture.view as? MKMapView else { return }
            let point = gesture.location(in: mapView)
            let coord = mapView.convert(point, toCoordinateFrom: mapView)
            onTap(coord)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor.systemBlue
                renderer.lineWidth = 4
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}

// MARK: - Location Search View

struct LocationSearchView: View {
    let onSelect: (SearchResult) -> Void
    @State private var query = ""
    @State private var results: [SearchResult] = []
    @Environment(\.dismiss) private var dismiss

    struct SearchResult: Identifiable {
        let id = UUID()
        let name: String
        let address: String
        let coordinate: CLLocationCoordinate2D
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(AppColor.textTertiary)
                    TextField("Tìm địa điểm...", text: $query)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(AppColor.textTertiary)
                        }
                    }
                }
                .padding(AppSpacing.md)
                .background(AppColor.surfaceTertiary)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
                .padding()

                // Results
                if results.isEmpty && !query.isEmpty {
                    EmptyStateView(
                        icon: "mappin.slash",
                        title: "Không tìm thấy",
                        message: "Thử từ khoá khác"
                    )
                } else {
                    List(results) { result in
                        Button {
                            onSelect(result)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                                Text(result.name)
                                    .font(AppFont.body)
                                Text(result.address)
                                    .font(AppFont.caption)
                                    .foregroundStyle(AppColor.textSecondary)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Tìm địa điểm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Đóng") { dismiss() }
                }
            }
            .onChange(of: query) { _, newValue in
                Task { await search(newValue) }
            }
        }
    }

    private func search(_ text: String) async {
        guard text.count >= 2 else { results = []; return }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.resultTypes = .pointOfInterest

        do {
            let response = try await MKLocalSearch(request: request).start()
            results = response.mapItems.map { item in
                SearchResult(
                    name: item.name ?? "Không tên",
                    address: [item.placemark.thoroughfare, item.placemark.locality, item.placemark.country]
                        .compactMap { $0 }.joined(separator: ", "),
                    coordinate: item.placemark.coordinate
                )
            }
        } catch {
            results = []
        }
    }
}
