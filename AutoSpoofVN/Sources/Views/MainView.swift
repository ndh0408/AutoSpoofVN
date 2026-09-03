import SwiftUI
import MapKit
import CoreLocation
import UniformTypeIdentifiers

struct MainView: View {
    @EnvironmentObject var engine: SpoofEngine
    @EnvironmentObject var routine: RoutineManager
    @EnvironmentObject var flight: FlightManager
    @StateObject private var backgroundKeeper = BackgroundKeeper.shared

    @State private var cameraPosition: MapCameraPosition = .camera(
        MapCamera(centerCoordinate: CLLocationCoordinate2D(latitude: 21.0285, longitude: 105.8542), distance: 5000)
    )
    @State private var showingPairingSheet: Bool = false
    @State private var showingLocationsSheet: Bool = false
    @State private var showingSettingsSheet: Bool = false
    @State private var showingWorldTravelSheet: Bool = false
    @State private var showingManualInput: Bool = false
    @State private var manualLat: String = "21.0285"
    @State private var manualLon: String = "105.8542"
    @State private var copiedToast: Bool = false
    @State private var showingConnectionRequiredAlert: Bool = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // MARK: - Ban do MapKit tuong tac
                MapReader { proxy in
                    Map(position: $cameraPosition) {
                        // Duong bay dai cung Great-Circle
                        if !flight.flightPathCoordinates.isEmpty {
                            MapPolyline(coordinates: flight.flightPathCoordinates)
                                .stroke(.blue, style: StrokeStyle(lineWidth: 3, dash: [6, 3]))
                        }

                        // Vi tri GPS dang mo phong
                        if engine.isSimulating {
                            Annotation(flight.isFlying ? "Máy bay" : "Vị trí ảo", coordinate: engine.currentCoordinate) {
                                if flight.isFlying {
                                    ZStack {
                                        Circle().fill(Color.blue.opacity(0.3)).frame(width: 48, height: 48)
                                        Image(systemName: "airplane")
                                            .font(.title2)
                                            .foregroundColor(.white)
                                            .padding(8)
                                            .background(Circle().fill(Color.blue))
                                            .shadow(radius: 3)
                                    }
                                } else {
                                    ZStack {
                                        Circle().fill(Color.blue.opacity(0.25)).frame(width: 44, height: 44)
                                        Circle().fill(Color.blue).frame(width: 16, height: 16)
                                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                                    }
                                }
                            }
                        }

                        // Diem Nha hoac Khach san
                        Annotation(routine.currentState == .hotel ? "Khách sạn" : "Nhà", coordinate: routine.homeLocation) {
                            Image(systemName: routine.currentState == .hotel ? "building.fill" : "house.circle.fill")
                                .font(.title2)
                                .foregroundColor(routine.currentState == .hotel ? .purple : .green)
                        }

                        // Diem Co quan hoac Tham quan
                        Annotation(routine.currentState == .sightseeing ? "Tham quan" : "Cơ quan", coordinate: routine.workLocation) {
                            Image(systemName: routine.currentState == .sightseeing ? "camera.circle.fill" : "building.2.crop.circle.fill")
                                .font(.title2)
                                .foregroundColor(.indigo)
                        }

                        // Diem Ca phe hoac Am thuc
                        Annotation("Ăn uống / Cà phê", coordinate: routine.cafeLocation) {
                            Image(systemName: "cup.and.saucer.circle.fill")
                                .font(.title2)
                                .foregroundColor(.orange)
                        }

                        // Danh sach Bookmarks
                        ForEach(routine.bookmarks) { b in
                            Annotation(b.name, coordinate: b.coordinate.clCoordinate) {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.title3)
                                    .foregroundColor(.red)
                            }
                        }
                    }
                    .mapStyle(.standard(elevation: .realistic))
                    .onTapGesture { screenPoint in
                        if let loc = proxy.convert(screenPoint, from: .local) {
                            setManualLocation(loc)
                        }
                    }
                }
                .ignoresSafeArea(edges: .top)

                // MARK: - Banner Header Toa do & Arbiter Status
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(flight.isFlying ? "MÁY BAY:" : "GPS ẢO:")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.secondary)

                                if let source = engine.activeSource {
                                    Text("• \(source.displayName)")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.blue)
                                }
                            }

                            Text(String(format: "%.5f, %.5f", engine.currentCoordinate.latitude, engine.currentCoordinate.longitude))
                                .font(.system(.subheadline, design: .monospaced))
                                .fontWeight(.semibold)
                        }

                        Spacer()

                        if flight.isFlying, let sim = flight.activeFlight {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(Int(sim.currentSpeedKmh)) km/h")
                                    .font(.system(.subheadline, design: .monospaced))
                                    .fontWeight(.bold)
                                    .foregroundColor(.blue)
                                Text("Cao: \(Int(sim.altitudeMeters))m")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }

                        Button(action: {
                            UIPasteboard.general.string = "\(engine.currentCoordinate.latitude), \(engine.currentCoordinate.longitude)"
                            copiedToast = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedToast = false }
                        }) {
                            Image(systemName: copiedToast ? "checkmark.circle.fill" : "doc.on.doc")
                                .font(.callout)
                                .foregroundColor(.blue)
                        }

                        Button(action: {
                            manualLat = String(format: "%.5f", engine.currentCoordinate.latitude)
                            manualLon = String(format: "%.5f", engine.currentCoordinate.longitude)
                            showingManualInput = true
                        }) {
                            Image(systemName: "square.and.pencil")
                                .font(.callout)
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    #if USE_IDEVICE_FFI
                    if !engine.isLoopbackConnected {
                        HStack {
                            Image(systemName: "link.badge.plus")
                                .foregroundColor(.orange)
                            Text("Chưa kết nối DVT: chạm bản đồ chưa thể đổi GPS.")
                                .font(.caption2)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                        .padding(.horizontal, 16)
                    }
                    #else
                    HStack {
                        Image(systemName: "testtube.2")
                            .foregroundColor(.orange)
                        Text("CHẾ ĐỘ MÔ PHỎNG — GPS thật không đổi.")
                            .font(.caption2)
                            .fontWeight(.bold)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)
                    .padding(.horizontal, 16)
                    #endif

                    // Canh bao keep-alive neu co loi
                    if let err = engine.keepAliveError {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.yellow)
                            Text("Chạy ngầm cảnh báo: \(err)")
                                .font(.caption2)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                        .padding(.horizontal, 16)
                    }

                    if backgroundKeeper.authorizationStatus != .authorizedAlways {
                        HStack {
                            Image(systemName: "location.slash.fill")
                                .foregroundColor(.orange)
                            Text("Chưa có quyền vị trí Luôn luôn: app không thể tự được đánh thức lại ổn định.")
                                .font(.caption2)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                        .padding(.horizontal, 16)
                    }

                    // Flight HUD Overlay khi dang bay
                    FlightHUDView()

                    Spacer()
                }

                // MARK: - Bang dieu khien HUD ben duoi
                VStack(spacing: 10) {
                    // Trang thai chu trinh sinh hoat
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: routine.currentState.icon)
                                .font(.title3)
                                .foregroundColor(routine.currentState == .flying ? .blue : .orange)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(routine.currentState.rawValue)
                                    .font(.headline)
                                Text(routine.statusDescription)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { routine.isAutoRoutineEnabled },
                                set: { _ in routine.toggleAutoRoutine() }
                            ))
                            .labelsHidden()
                        }

                        if routine.currentSpeedKmh > 0 || !flight.destinationLocalTime.isEmpty {
                            HStack {
                                if routine.currentSpeedKmh > 0 {
                                    Text("Vận tốc:")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Text("\(Int(routine.currentSpeedKmh)) km/h")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundColor(.blue)
                                }

                                if !flight.destinationLocalTime.isEmpty {
                                    Spacer()
                                    Text(flight.destinationLocalTime)
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.purple)
                                }
                            }
                        }
                    }
                    .padding(14)
                    .background(.ultraThinMaterial)
                    .cornerRadius(16)

                    // Thanh nut cong cu thao tac
                    HStack(spacing: 8) {
                        Button(action: { showingWorldTravelSheet = true }) {
                            Label("Du lịch & Bay", systemImage: "airplane.circle.fill")
                                .font(.footnote)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.blue)
                                .cornerRadius(10)
                        }

                        Button(action: { showingLocationsSheet = true }) {
                            Label("Địa điểm", systemImage: "mappin.and.ellipse")
                                .font(.footnote)
                                .padding(.vertical, 10)
                                .padding(.horizontal, 12)
                        }
                        .buttonStyle(.bordered)

                        Button(action: { showingPairingSheet = true }) {
                            Image(systemName: engine.isLoopbackConnected ? "link.circle.fill" : "link")
                                .font(.footnote)
                                .foregroundColor(engine.isLoopbackConnected ? .green : .primary)
                                .padding(.vertical, 10)
                                .padding(.horizontal, 12)
                        }
                        .buttonStyle(.bordered)

                        Button(action: { showingSettingsSheet = true }) {
                            Image(systemName: "gearshape")
                                .font(.footnote)
                                .padding(.vertical, 10)
                                .padding(.horizontal, 12)
                        }
                        .buttonStyle(.bordered)

                        if engine.isSimulating {
                            Button(role: .destructive, action: {
                                flight.stopFlight()
                                engine.clearSimulation()
                            }) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.footnote)
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 12)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
            .navigationTitle("AutoSpoof VN")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingWorldTravelSheet) {
                WorldTravelView()
            }
            .sheet(isPresented: $showingPairingSheet) {
                PairingSetupView()
            }
            .sheet(isPresented: $showingLocationsSheet) {
                LocationsPresetView()
            }
            .sheet(isPresented: $showingSettingsSheet) {
                SettingsView()
            }
            .alert("Nhập toạ độ thủ công", isPresented: $showingManualInput) {
                TextField("Vĩ độ (Latitude)", text: $manualLat)
                    .keyboardType(.decimalPad)
                TextField("Kinh độ (Longitude)", text: $manualLon)
                    .keyboardType(.decimalPad)
                Button("Mô phỏng") {
                    if let lat = Double(manualLat), let lon = Double(manualLon) {
                        let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                        if setManualLocation(coordinate) {
                            cameraPosition = .camera(MapCamera(centerCoordinate: coordinate, distance: 3000))
                        }
                    }
                }
                Button("Huỷ", role: .cancel) {}
            }
            .alert("Chưa kết nối DVT", isPresented: $showingConnectionRequiredAlert) {
                Button("Mở ghép nối") {
                    showingPairingSheet = true
                }
                Button("Huỷ", role: .cancel) {}
            } message: {
                Text("Hãy kết nối DVT trước khi đặt vị trí. GPS thật chưa thay đổi và điểm mô phỏng chưa được kích hoạt.")
            }
        }
    }

    @discardableResult
    private func setManualLocation(_ coordinate: CLLocationCoordinate2D) -> Bool {
        #if USE_IDEVICE_FFI
        guard engine.isLoopbackConnected else {
            showingConnectionRequiredAlert = true
            return false
        }
        #endif
        engine.setLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return true
    }
}

// MARK: - Man hinh Ghep noi DVT Loopback
struct PairingSetupView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var engine: SpoofEngine
    @State private var showingFileImporter = false
    @State private var textInput = ""
    @State private var pairingData: Data?
    @State private var pairingFileName: String?
    @State private var pairingFormat: String?
    @State private var importError: String?

    private var isConnecting: Bool {
        engine.connectionStatus.hasPrefix("Đang kết nối")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Trạng thái")) {
                    HStack {
                        Text("Trạng thái:")
                        Spacer()
                        Text(engine.connectionStatus)
                            .foregroundColor(engine.isLoopbackConnected ? .green : .secondary)
                            .font(.callout)
                    }

                    if isConnecting {
                        ProgressView("Đang mở tunnel và kết nối dtservicehub…")
                            .font(.caption)
                    }

                    if let error = engine.lastFFIError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                Section(header: Text("Hướng dẫn thiết lập LocalDevVPN")) {
                    Text("1. Cài đặt app **LocalDevVPN** từ App Store trên thiết bị.")
                    Text("2. Mở LocalDevVPN và gạt bật kết nối VPN Loopback (10.7.0.1).")
                    Text("3. Xuất file ghép nối `.mobiledevicepairing` từ máy đã Trust thiết bị.")
                    Text("4. Chọn trực tiếp file bên dưới. File có thể là Binary Plist nên không thể dán dưới dạng văn bản.")
                }

                Section(header: Text("File ghép nối thiết bị")) {
                    Button {
                        showingFileImporter = true
                    } label: {
                        Label(pairingFileName == nil ? "Chọn file .mobiledevicepairing" : "Chọn file khác", systemImage: "doc.badge.plus")
                    }

                    if let pairingFileName, let pairingData {
                        LabeledContent("Tên file", value: pairingFileName)
                        LabeledContent("Kích thước", value: ByteCountFormatter.string(fromByteCount: Int64(pairingData.count), countStyle: .file))
                        if let pairingFormat {
                            LabeledContent("Định dạng", value: pairingFormat)
                        }
                    }

                    Text(engine.pairingSummary)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let importError {
                        Label(importError, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                Section(header: Text("Dự phòng: Plist dạng XML")) {
                    TextEditor(text: $textInput)
                        .frame(minHeight: 120)
                        .font(.system(.caption, design: .monospaced))

                    Text("Chỉ dùng ô này nếu pairing record là plist XML thuần văn bản. File binary phải chọn bằng nút phía trên.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button("Kết nối từ Plist XML") {
                        engine.connectLoopback(plistContent: textInput)
                    }
                    .disabled(textInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isConnecting)
                }

                Section {
                    if engine.isLoopbackConnected {
                        Button("Ngắt kết nối", role: .destructive) {
                            engine.disconnect()
                        }
                    }
                }
            }
            .navigationTitle("Ghép nối DVT")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
            .onAppear {
                textInput = engine.pairingPlist
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.propertyList, .data],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    importPairingFile(from: url)
                case .failure(let error):
                    importError = error.localizedDescription
                }
            }
        }
    }

    private func importPairingFile(from url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            guard !data.isEmpty else {
                importError = "File ghép nối đang rỗng."
                pairingData = nil
                pairingFileName = nil
                pairingFormat = nil
                return
            }

            var format = PropertyListSerialization.PropertyListFormat.binary
            _ = try PropertyListSerialization.propertyList(from: data, options: [], format: &format)

            pairingData = data
            pairingFileName = url.lastPathComponent
            pairingFormat = format == .binary ? "Binary Plist" : "XML Plist"
            importError = nil
            engine.connectLoopback(pairingData: data)
        } catch {
            pairingData = nil
            pairingFileName = nil
            pairingFormat = nil
            importError = "Không đọc được pairing file: \(error.localizedDescription)"
        }
    }
}

// MARK: - Man hinh Cai dat Dia diem Thoi quen
struct LocationsPresetView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var routine: RoutineManager
    @EnvironmentObject var engine: SpoofEngine

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Địa điểm thói quen")) {
                    LocationRow(title: "Nhà riêng / Khách sạn", icon: "house.fill", color: .green, coordinate: routine.homeLocation) {
                        routine.homeLocation = engine.currentCoordinate
                    }

                    LocationRow(title: "Cơ quan / Điểm đến chính", icon: "building.2.fill", color: .indigo, coordinate: routine.workLocation) {
                        routine.workLocation = engine.currentCoordinate
                    }

                    LocationRow(title: "Quán Cà phê / Ẩm thực", icon: "cup.and.saucer.fill", color: .orange, coordinate: routine.cafeLocation) {
                        routine.cafeLocation = engine.currentCoordinate
                    }
                }

                Section(header: Text("Điểm đến yêu thích (Bookmarks)")) {
                    ForEach(routine.bookmarks) { bookmark in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(bookmark.name)
                                    .font(.headline)
                                Text(String(format: "%.5f, %.5f", bookmark.coordinate.latitude, bookmark.coordinate.longitude))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("Đến") {
                                engine.setLocation(latitude: bookmark.coordinate.latitude, longitude: bookmark.coordinate.longitude)
                                dismiss()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .onDelete { indices in
                        routine.bookmarks.remove(atOffsets: indices)
                    }

                    Button("+ Thêm vị trí hiện tại vào Bookmark") {
                        let newBookmark = PlaceBookmark(
                            name: "Điểm \(routine.bookmarks.count + 1)",
                            latitude: engine.currentCoordinate.latitude,
                            longitude: engine.currentCoordinate.longitude
                        )
                        routine.bookmarks.append(newBookmark)
                    }
                }
            }
            .navigationTitle("Địa điểm & Lộ trình")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
        }
    }
}

struct LocationRow: View {
    let title: String
    let icon: String
    let color: Color
    let coordinate: CLLocationCoordinate2D
    let onSetCurrent: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.headline)
            }
            HStack {
                Text(String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                Button("Gán vị trí hiện tại") {
                    onSetCurrent()
                }
                .font(.caption)
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Man hinh Cai dat Nang cao
struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var engine: SpoofEngine
    @StateObject private var backgroundKeeper = BackgroundKeeper.shared
    @State private var showingOnboarding = false

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Tự nhiên hoá GPS (Chống phát hiện)")) {
                    Toggle("Bật GPS Jitter (Dao động tự nhiên)", isOn: $engine.enableJitter)
                    if engine.enableJitter {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Bán kính dao động: \(Int(engine.jitterMeters)) mét")
                                .font(.callout)
                            Slider(value: $engine.jitterMeters, in: 1.0...10.0, step: 1.0)
                        }
                    }
                }

                Section(header: Text("Duy trì chạy ngầm (Keep-Alive)")) {
                    HStack {
                        Image(systemName: "waveform")
                            .foregroundColor(engine.isKeepAliveRunning ? .green : .red)
                        Text("Silent Audio Playback")
                        Spacer()
                        Text(engine.isKeepAliveRunning ? "Đang chạy" : "Tạm dừng")
                            .foregroundColor(engine.isKeepAliveRunning ? .green : .secondary)
                            .font(.caption)
                    }
                    if let err = engine.keepAliveError {
                        Text("Lỗi: \(err)")
                            .font(.caption2)
                            .foregroundColor(.red)
                    }
                    HStack {
                        Image(systemName: "heart.fill")
                            .foregroundColor(.red)
                        Text("DVT Heartbeat Interval")
                        Spacer()
                        Text("20 giây")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Image(systemName: "location.fill")
                            .foregroundColor(backgroundKeeper.authorizationStatus == .authorizedAlways ? .green : .orange)
                        Text("Quyền vị trí nền")
                        Spacer()
                        Text(locationAuthorizationLabel)
                            .font(.caption)
                            .foregroundColor(backgroundKeeper.authorizationStatus == .authorizedAlways ? .green : .orange)
                    }

                    HStack {
                        Image(systemName: backgroundKeeper.isLocationUpdating ? "location.circle.fill" : "location.slash.circle")
                            .foregroundColor(backgroundKeeper.isLocationUpdating ? .green : .secondary)
                        Text("Cập nhật vị trí nền")
                        Spacer()
                        Text(backgroundKeeper.isLocationUpdating ? "Đang chạy" : "Không chạy")
                            .font(.caption)
                            .foregroundColor(backgroundKeeper.isLocationUpdating ? .green : .secondary)
                    }

                    HStack {
                        Image(systemName: "waveform.badge.exclamationmark")
                            .foregroundColor(.orange)
                        Text("Lần audio bị gián đoạn")
                        Spacer()
                        Text("\(backgroundKeeper.interruptionCount)")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                    }

                    if backgroundKeeper.authorizationStatus != .authorizedAlways {
                        Label(
                            "Không có quyền Luôn luôn thì iOS không thể dùng cập nhật vị trí nền để đánh thức lại app.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.caption)
                        .foregroundColor(.orange)
                    }
                }

                Section(header: Text("Thông tin ứng dụng")) {
                    Button {
                        showingOnboarding = true
                    } label: {
                        Label("Mở lại checklist thiết lập", systemImage: "checklist")
                    }

                    HStack {
                        Text("Phiên bản")
                        Spacer()
                        Text("1.0.0 (World Travel Edition)")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Nền tảng")
                        Spacer()
                        Text("iOS 17.4+ Native SwiftUI")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Cài đặt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
            .sheet(isPresented: $showingOnboarding) {
                OnboardingView(isReviewMode: true)
            }
        }
    }

    private var locationAuthorizationLabel: String {
        switch backgroundKeeper.authorizationStatus {
        case .authorizedAlways:
            return "Luôn luôn"
        case .authorizedWhenInUse:
            return "Khi dùng app"
        case .denied:
            return "Đã từ chối"
        case .restricted:
            return "Bị hạn chế"
        case .notDetermined:
            return "Chưa quyết định"
        @unknown default:
            return "Không xác định"
        }
    }
}
