import CoreLocation
import MapKit
import SwiftUI

/// Dashboard v2 — refactored từ MainView 856 dòng.
/// Map là hero. Bottom sheet telemetry. Quick actions. Modular.
struct MainViewV2: View {
    @EnvironmentObject var engine: SpoofEngine
    @EnvironmentObject var routine: RoutineManager
    @EnvironmentObject var flight: FlightManager
    @StateObject private var coordinator = SimulationCoordinator.shared
    @StateObject private var deviceManager = DeviceManager.shared
    @StateObject private var historyManager = HistoryManager.shared

    // Map
    @State private var cameraPosition: MapCameraPosition = .camera(
        MapCamera(centerCoordinate: CLLocationCoordinate2D(latitude: 21.0285, longitude: 105.8542), distance: 5000)
    )
    // MapStyle (MapKit) khong conform Equatable nen khong switch/so sanh truc tiep duoc -
    // dung enum rieng theo doi trang thai, suy ra MapStyle tu do.
    private enum MapStyleKind: Equatable { case standard, imagery, hybrid }
    @State private var mapStyleKind: MapStyleKind = .standard
    private var mapStyle: MapStyle {
        switch mapStyleKind {
        case .standard: return .standard
        case .imagery: return .imagery
        case .hybrid: return .hybrid
        }
    }
    @State private var trail: [CLLocationCoordinate2D] = []
    @State private var followMode = true

    // Sheets
    @State private var showRouteStudio = false
    @State private var showScenarioStudio = false
    @State private var showRoutineStudio = false
    @State private var showDeviceManager = false
    @State private var showSettings = false
    @State private var showHistory = false
    @State private var showWorldTravel = false
    @State private var showDiagnostics = false
    @State private var showBookmarks = false
    @State private var showManualInput = false
    @State private var showTelemetryDetail = false

    // Manual input
    @State private var manualLat = "21.0285"
    @State private var manualLon = "105.8542"

    var body: some View {
        ZStack(alignment: .top) {
            // MARK: - Map
            mapLayer

            // MARK: - Header
            VStack(spacing: 0) {
                ConnectionHeader(
                    deviceState: coordinator.deviceState,
                    isSimulating: coordinator.state.isActive
                )

                Spacer()

                // Quick actions (khi idle)
                if !coordinator.state.isActive {
                    QuickActionsBar(
                        onSetLocation: { showManualInput = true },
                        onStartRoute: { showRouteStudio = true },
                        onCreateRoute: { showRouteStudio = true },
                        onScenario: { showScenarioStudio = true },
                        onDevices: { showDeviceManager = true }
                    )
                    .padding(.bottom, AppSpacing.sm)
                }

                // Telemetry panel (khi đang chạy)
                if coordinator.state.isActive || coordinator.state == .paused {
                    TelemetryPanel(
                        coordinator: coordinator,
                        onPause: { coordinator.pauseSession() },
                        onStop: {
                            coordinator.stopSession()
                            if let record = historyManager.stopRecording() { _ = record }
                        },
                        onResume: { coordinator.resumeSession() }
                    )
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.bottom, AppSpacing.sm)
                    .onTapGesture { showTelemetryDetail.toggle() }
                }
            }

            // MARK: - Map controls overlay
            mapControls
        }
        .onChange(of: coordinator.currentCoordinate.latitude) { _, _ in
            updateTrailAndCamera()
        }
        .sheet(isPresented: $showRouteStudio) { RouteStudioView() }
        .sheet(isPresented: $showScenarioStudio) { ScenarioStudioView() }
        .sheet(isPresented: $showRoutineStudio) { RoutineStudioView() }
        .sheet(isPresented: $showDeviceManager) { DeviceManagerView() }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showHistory) { HistoryView() }
        .sheet(isPresented: $showWorldTravel) { WorldTravelViewV2() }
        .sheet(isPresented: $showDiagnostics) { DiagnosticsView() }
        .sheet(isPresented: $showBookmarks) { BookmarksView() }
        .sheet(isPresented: $showTelemetryDetail) {
            NavigationStack {
                TelemetryDetailView(telemetry: coordinator.telemetry, coordinator: coordinator)
                    .navigationTitle("Telemetry")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Đóng") { showTelemetryDetail = false }
                        }
                    }
            }
            .presentationDetents([.medium])
        }
        .alert("Nhập toạ độ", isPresented: $showManualInput) {
            TextField("Latitude", text: $manualLat)
                .keyboardType(.decimalPad)
            TextField("Longitude", text: $manualLon)
                .keyboardType(.decimalPad)
            Button("Đặt") {
                if let lat = Double(manualLat), let lon = Double(manualLon),
                   (-90...90).contains(lat), (-180...180).contains(lon) {
                    coordinator.setManualLocation(CLLocationCoordinate2D(latitude: lat, longitude: lon))
                }
            }
            Button("Huỷ", role: .cancel) {}
        }
    }

    // MARK: - Map Layer

    private var mapLayer: some View {
        MapReader { proxy in
            Map(position: $cameraPosition, interactionModes: .all) {
                // Trail
                if trail.count >= 2 {
                    MapPolyline(coordinates: trail)
                        .stroke(.blue.opacity(0.4), lineWidth: 2)
                }

                // Flight path
                if !flight.flightPathCoordinates.isEmpty {
                    MapPolyline(coordinates: flight.flightPathCoordinates)
                        .stroke(.blue, style: StrokeStyle(lineWidth: 3, dash: [6, 3]))
                }

                // Current position
                if coordinator.state.isActive || engine.isSimulating {
                    Annotation("", coordinate: coordinator.currentCoordinate) {
                        currentPositionMarker
                    }
                }

                // Routine locations
                Annotation("Nhà", coordinate: routine.homeLocation) {
                    Image(systemName: "house.circle.fill")
                        .font(.title2).foregroundColor(.green)
                }
                Annotation("Công ty", coordinate: routine.workLocation) {
                    Image(systemName: "building.2.crop.circle.fill")
                        .font(.title2).foregroundColor(.indigo)
                }
                Annotation("Cà phê", coordinate: routine.cafeLocation) {
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.title2).foregroundColor(.orange)
                }
            }
            .mapStyle(mapStyle)
            .onTapGesture { screenCoord in
                if let coord = proxy.convert(screenCoord, from: .local) {
                    coordinator.setManualLocation(coord)
                }
            }
        }
        .ignoresSafeArea(edges: .top)
    }

    private var currentPositionMarker: some View {
        ZStack {
            if flight.isFlying {
                Circle().fill(Color.blue.opacity(0.3)).frame(width: 48, height: 48)
                Image(systemName: "airplane")
                    .font(.title2).foregroundColor(.white)
                    .padding(8)
                    .background(Circle().fill(Color.blue))
                    .rotationEffect(.degrees(coordinator.telemetry.headingDegrees))
            } else {
                Circle().fill(Color.blue.opacity(0.25)).frame(width: 44, height: 44)
                Circle().fill(Color.blue).frame(width: 16, height: 16)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
            }
        }
        .shadow(radius: 3)
    }

    // MARK: - Map Controls

    private var mapControls: some View {
        VStack {
            HStack {
                Spacer()
                VStack(spacing: AppSpacing.sm) {
                    mapButton("location.fill") {
                        followMode = true
                        updateCamera()
                    }
                    mapButton("map") {
                        switch mapStyleKind {
                        case .standard: mapStyleKind = .imagery
                        case .imagery: mapStyleKind = .hybrid
                        case .hybrid: mapStyleKind = .standard
                        }
                    }
                    mapButton("cube") {
                        // Toggle 3D pitch
                        cameraPosition = .camera(MapCamera(
                            centerCoordinate: coordinator.currentCoordinate,
                            distance: 2000,
                            heading: coordinator.telemetry.headingDegrees,
                            pitch: 45
                        ))
                    }

                    Divider().frame(width: 30)

                    // Navigation buttons
                    mapButton("gearshape") { showSettings = true }
                    mapButton("clock.arrow.circlepath") { showHistory = true }
                    mapButton("airplane") { showWorldTravel = true }
                    mapButton("bookmark") { showBookmarks = true }
                    mapButton("stethoscope") { showDiagnostics = true }
                }
                .padding(.trailing, AppSpacing.md)
                .padding(.top, 100)
            }
            Spacer()
        }
    }

    private func mapButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
                .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
        }
        .foregroundStyle(AppColor.textPrimary)
    }

    // MARK: - Helpers

    private func updateTrailAndCamera() {
        let coord = coordinator.currentCoordinate
        TrailOverlay.sampleTrail(&trail, newPoint: coord, maxPoints: 1000)
        if followMode { updateCamera() }
    }

    private func updateCamera() {
        withAnimation(.easeInOut(duration: 0.3)) {
            cameraPosition = .camera(MapCamera(
                centerCoordinate: coordinator.currentCoordinate,
                distance: flight.isFlying ? 50000 : 3000
            ))
        }
    }
}
