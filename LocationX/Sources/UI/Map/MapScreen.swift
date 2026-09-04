import CoreLocation
import MapKit
import SwiftUI

/// Man hinh chinh cua app: ban do chiem toan bo khung, moi thu khac noi ben tren.
///
/// Kien truc trang thai — ban do KHONG so huu trang thai mo phong nao:
/// ```
/// SimulationCoordinator.state            -> SimulationStatusBar, PrimarySimulationButton
/// SimulationCoordinator.activeSource     -> SourceBadge
/// SimulationCoordinator.telemetry        -> TelemetryGrid, MetricView
/// SimulationCoordinator.deviceState      -> ConnectionBadge
/// SimulationCoordinator.currentCoordinate-> vi tri camera, dau vi tri, MapTrail
/// FlightManager.flightPathCoordinates    -> duong bay
/// RoutineManager.home/work/cafeLocation  -> ghim dia diem co dinh
/// ```
/// Chi `MapTrail`, camera, kieu ban do va nac cua bang duoi la do UI so huu.
struct MapScreen: View {
    @EnvironmentObject private var engine: SpoofEngine
    @EnvironmentObject private var routine: RoutineManager
    @EnvironmentObject private var flight: FlightManager
    @Environment(\.navigator) private var navigator

    @ObservedObject private var coordinator = SimulationCoordinator.shared
    @ObservedObject private var shadowrocket = ShadowrocketManager.shared
    @ObservedObject private var appSettings = AppSettingsStore.shared

    // Trang thai thuan UI
    @State private var camera: MapCameraPosition = .camera(
        MapCamera(centerCoordinate: SimulationCoordinator.shared.currentCoordinate, distance: 3_000)
    )
    @State private var styleKind: MapStyleKind = .standard
    @State private var followMode = true
    @State private var isPitched = false
    @State private var trail = MapTrail()
    @State private var sheetDetent: BottomSheetDetent = .collapsed

    /// Toa do dang cho xac nhan ghi de mot nguon dang chay.
    @State private var pendingOverride: CLLocationCoordinate2D?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                mapLayer

                // Thanh trang thai — bam dinh, tren cung.
                SimulationStatusBar(coordinator: coordinator) {
                    navigator.present(.diagnostics)
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.top, AppSpacing.sm)

                // Cum dieu khien ban do — canh phai, duoi thanh trang thai.
                // Day xuong khi banner Shadowrocket dang hien de hai lop khong chong nhau.
                HStack {
                    Spacer()
                    MapFloatingControls(followMode: $followMode,
                                        styleKind: $styleKind,
                                        isPitched: $isPitched,
                                        onRecenter: recenter,
                                        onOpenSheet: { navigator.present($0) })
                        .padding(.trailing, AppSpacing.lg)
                }
                .padding(.top, shadowrocket.showSetupBanner ? 150 : 58)
                .appAnimation(AppAnimation.smooth, value: shadowrocket.showSetupBanner)

                // Bang duoi — keo duoc. KHONG bo qua safe area duoi: trong TabView,
                // vung an toan duoi chinh la cho tab bar dung. Bo qua no thi bang de len tab bar.
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    SimulationBottomSheet(
                        coordinator: coordinator,
                        flight: flight,
                        detent: $sheetDetent,
                        availableHeight: geo.size.height,
                        onStart: startSimulation,
                        onPause: { coordinator.pauseSession() },
                        onResume: { coordinator.resumeSession() },
                        onStop: stopSimulation,
                        onHalt: { coordinator.halt() },
                        onOpenSheet: { navigator.present($0) },
                        onSelectTab: { navigator.select($0) }
                    )
                }

                shadowrocketBanner
            }
        }
        // Mot khoa Equatable cho ca hai truc. Ban cu chi theo doi `latitude`, nen
        // chuyen dong thuan dong-tay khong cap nhat vet duong lan camera.
        .onChange(of: CoordinateKey(coordinator.currentCoordinate)) { _, new in
            handleCoordinateChange(new.coordinate)
        }
        .onChange(of: isPitched) { _, _ in
            if followMode { recenter() }
        }
        .onAppear {
            // Áp tuỳ chọn bản đồ do người dùng đặt. Trước đây toàn bộ nhóm cài đặt "Bản đồ"
            // được lưu nhưng không màn hình nào đọc, nên chúng không có tác dụng gì.
            let s = appSettings.settings
            trail.maximumPoints = max(50, s.trailMaxPoints)
            trail.isEnabled = s.trailEnabled
            styleKind = MapStyleKind(rawValue: s.mapStyle) ?? .standard
            followMode = s.mapFollowMode
            isPitched = s.map3DEnabled
            trail.append(coordinator.currentCoordinate)
        }
        // Ghi ngược lựa chọn của người dùng để lần mở sau giữ nguyên.
        .onChange(of: styleKind) { _, new in appSettings.settings.mapStyle = new.rawValue }
        .onChange(of: followMode) { _, new in appSettings.settings.mapFollowMode = new }
        .onChange(of: isPitched) { _, new in appSettings.settings.map3DEnabled = new }
        .confirmationDialog(L("map.override.title"),
                            isPresented: overrideDialogBinding,
                            titleVisibility: .visible) {
            Button(L("map.override.confirm"), role: .destructive) { applyPendingOverride() }
            Button(L10n.cancel, role: .cancel) { pendingOverride = nil }
        } message: {
            Text(L("map.override.message",
                   coordinator.activeSource?.displayName ?? L("map.override.other_source")))
        }
    }

    // MARK: - Lop ban do

    private var mapLayer: some View {
        MapReader { proxy in
            Map(position: $camera, interactionModes: .all) {
                // Vet duong da di.
                if trail.isDrawable, trail.isEnabled {
                    MapPolyline(coordinates: trail.points)
                        .stroke(AppColor.mapTrail.opacity(0.55),
                                style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                }

                // Duong bay du kien.
                if !flight.flightPathCoordinates.isEmpty {
                    MapPolyline(coordinates: flight.flightPathCoordinates)
                        .stroke(AppColor.mapFlightPath,
                                style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [7, 5]))
                }

                // Dia diem co dinh cua chu trinh 24/7.
                ForEach(RoutinePlace.all(from: routine)) { place in
                    Annotation(place.title, coordinate: place.coordinate, anchor: .center) {
                        SavedPlaceMarker(symbol: place.symbol, tint: place.tint)
                    }
                    .annotationTitles(.hidden)
                }

                // Dau vi tri dang mo phong. Dieu kien OR duoc giu nguyen: FlightManager va
                // RoutineManager ghi toa do thang qua SpoofEngine, nen chi doc
                // `coordinator.state` se lam dau vi tri bien mat trong luc chung dang chay.
                if coordinator.state.isActive || engine.isSimulating {
                    Annotation("", coordinate: coordinator.currentCoordinate, anchor: .center) {
                        CurrentPositionMarker(isFlying: flight.isFlying,
                                              headingDegrees: coordinator.telemetry.headingDegrees,
                                              isRunning: coordinator.state == .running)
                    }
                    .annotationTitles(.hidden)
                }

                if let pending = pendingOverride {
                    Annotation("", coordinate: pending, anchor: .bottom) {
                        TargetPinMarker()
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(styleKind.mapStyle)
            // Khong dung `.mapControls`: la ban cua MapKit nam san o goc tren phai —
            // dung cho cum dieu khien cua app dang dung. Man hinh nay dieu khien ban do
            // hoan toan bang control rieng.
            .onTapGesture { screenPoint in
                guard let coordinate = proxy.convert(screenPoint, from: .local) else { return }
                handleMapTap(coordinate)
            }
        }
        // Tran len tren (chui duoi thanh trang thai he thong) va ra hai canh, nhung
        // KHONG tran xuong duoi: canh duoi cua vung an toan chinh la dinh tab bar.
        // Tran xuong duoi thi lop ban do phu len tab bar va tab bar bien mat.
        .ignoresSafeArea(edges: [.top, .horizontal])
    }

    // MARK: - Banner Shadowrocket

    @ViewBuilder
    private var shadowrocketBanner: some View {
        if shadowrocket.showSetupBanner {
            VStack {
                ShadowrocketBanner(manager: shadowrocket) {
                    navigator.present(.shadowrocketSetup)
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.top, 56)
                Spacer()
            }
            .transition(.move(edge: .top).combined(with: .opacity))
            .appAnimation(AppAnimation.smooth, value: shadowrocket.showSetupBanner)
        }
    }

    // MARK: - Hanh dong

    /// Bat dau mo phong tai vi tri hien tai.
    ///
    /// `setManualLocation` la duong that su cua app: khi dang `.idle` no tao session
    /// `.manual`, gianh quyen (uu tien 100), roi gui toa do xuong thiet bi.
    private func startSimulation() {
        coordinator.setManualLocation(coordinator.currentCoordinate)
        followMode = true
        recenter()
    }

    /// Dung phien. Ghi lich su TRUOC khi dung, vi `stopSession()` giai phong
    /// `activeSource` va xoa telemetry — goi sau se ghi nham nguon thanh `.manual`.
    private func stopSimulation() {
        _ = HistoryManager.shared.stopRecording()
        coordinator.stopSession()
    }

    /// Cham ban do.
    ///
    /// Khi dang ranh (hoac chinh `.manual` dang giu quyen) thi dat vi tri ngay — giu
    /// nguyen hanh vi cu. Khi mot nguon KHAC dang chay thi hoi truoc: mot cu cham lac
    /// tay dang le khong duoc am tham giet mot tuyen dang chay do dai.
    private func handleMapTap(_ coordinate: CLLocationCoordinate2D) {
        let ownedByOther = coordinator.state.isActive
            && coordinator.activeSource != nil
            && coordinator.activeSource != .manual

        if ownedByOther {
            AppHaptics.warning()
            pendingOverride = coordinate
        } else {
            AppHaptics.selection()
            coordinator.setManualLocation(coordinate)
        }
    }

    private func applyPendingOverride() {
        guard let coordinate = pendingOverride else { return }
        pendingOverride = nil
        AppHaptics.start()
        coordinator.setManualLocation(coordinate)
    }

    private var overrideDialogBinding: Binding<Bool> {
        Binding(get: { pendingOverride != nil },
                set: { if !$0 { pendingOverride = nil } })
    }

    // MARK: - Camera & vet duong

    private func handleCoordinateChange(_ coordinate: CLLocationCoordinate2D) {
        // `append` chi nhan diem khi da di du 4 m, nen camera cung chi doi khi that su
        // di chuyen — thay vi 10 lan/giay theo nhip phat toa do cua coordinator.
        let moved = trail.append(coordinate)
        if followMode && moved {
            updateCamera(to: coordinate, animated: true)
        }
    }

    private func recenter() {
        followMode = true
        updateCamera(to: coordinator.currentCoordinate, animated: true)
    }

    private func updateCamera(to coordinate: CLLocationCoordinate2D, animated: Bool) {
        let distance = isPitched
            ? MapCameraDistance.pitched
            : MapCameraDistance.forSpeed(coordinator.telemetry.speedKmh, isFlying: flight.isFlying)

        let newCamera = MapCamera(
            centerCoordinate: coordinate,
            distance: distance,
            heading: isPitched ? coordinator.telemetry.headingDegrees : 0,
            pitch: isPitched ? 55 : 0
        )

        if animated && !UIAccessibility.isReduceMotionEnabled {
            withAnimation(AppAnimation.gentle) { camera = .camera(newCamera) }
        } else {
            camera = .camera(newCamera)
        }
    }
}

// MARK: - Khoa toa do

/// `CLLocationCoordinate2D` khong conform `Equatable`, ma `.onChange` thi doi hoi.
/// Boc lai de theo doi duoc CA HAI truc bang mot lan `.onChange`.
private struct CoordinateKey: Equatable {
    let latitude: Double
    let longitude: Double

    init(_ coordinate: CLLocationCoordinate2D) {
        latitude = coordinate.latitude
        longitude = coordinate.longitude
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
