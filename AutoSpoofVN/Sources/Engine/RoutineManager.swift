import Foundation
import CoreLocation

/// Quản lý chu trình tự động theo thói quen sinh hoạt thực tế (Đi làm, Nghỉ trưa, Đi dạo, Ngủ)
final class RoutineManager: ObservableObject {
    static let shared = RoutineManager()

    @Published var currentState: RoutineState = .working
    @Published var isAutoRoutineEnabled: Bool = false
    @Published var currentSpeedKmh: Double = 0.0
    @Published var statusDescription: String = "Sẵn sàng"

    // Địa điểm cấu hình thói quen
    @Published var homeLocation: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 21.0333, longitude: 105.8433) {
        didSet { if !isLoading { saveLocations() } }
    }
    @Published var workLocation: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 21.0245, longitude: 105.7890) {
        didSet { if !isLoading { saveLocations() } }
    }
    @Published var cafeLocation: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 21.0285, longitude: 105.8342) {
        didSet { if !isLoading { saveLocations() } }
    }
    @Published var bookmarks: [PlaceBookmark] = [] {
        didSet { if !isLoading { saveBookmarks() } }
    }

    private var routineTimer: Timer?
    private var moveStepTimer: Timer?
    private var targetRoute: [CLLocationCoordinate2D] = []
    private var currentWaypointIndex: Int = 0
    /// Khoá định danh chặng đang chạy, tránh khởi động lại lộ trình mỗi lần đánh giá lịch (60 giây/lần).
    private var activeCommuteKey: String? = nil
    /// Chặn didSet ghi ngược xuống đĩa trong lúc đang nạp dữ liệu từ đĩa.
    private var isLoading: Bool = false

    private init() {
        isLoading = true
        loadSavedLocations()
        loadSavedBookmarks()
        isLoading = false
    }

    /// Bật/Tắt chu trình mô phỏng tự động 24/7
    func toggleAutoRoutine() {
        isAutoRoutineEnabled.toggle()
        if isAutoRoutineEnabled {
            statusDescription = "Đang chạy chu trình tự động 24/7"
            // Bat chu trinh la hanh dong khoi dong ro rang -> go trang thai "da dung han".
            _ = SpoofEngine.shared.acquire(.routine)
            startScheduleMonitoring()
        } else {
            statusDescription = "Đã tạm dừng chu trình tự động"
            routineTimer?.invalidate()
            moveStepTimer?.invalidate()
            activeCommuteKey = nil
            currentSpeedKmh = 0.0
            SpoofEngine.shared.release(.routine)
        }
    }

    /// Đặt địa điểm thủ công theo loại
    func updateLocation(for type: String, coordinate: CLLocationCoordinate2D) {
        switch type {
        case "home":
            homeLocation = coordinate
        case "work":
            workLocation = coordinate
        case "cafe":
            cafeLocation = coordinate
        default:
            break
        }
    }

    /// Đánh giá khung giờ thực tế để chuyển trạng thái thói quen sinh hoạt
    func evaluateCurrentTimeSchedule() {
        let calendar = Calendar.current
        let now = Date()
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)

        switch hour {
        case 23, 0...6:
            // 23:00 - 06:59: Đang ngủ ở nhà
            applySleepingState()

        case 7:
            if minute < 30 {
                // 07:00 - 07:30: Chuẩn bị ở nhà
                applySleepingState()
            } else {
                // 07:30 - 08:30: Di chuyển đi làm từ Nhà -> Cơ quan
                startCommute(from: homeLocation, to: workLocation, speed: 30.0, stateName: .moving, label: "Đang đi làm (Nhà -> Cơ quan)")
            }

        case 8:
            if minute < 30 {
                startCommute(from: homeLocation, to: workLocation, speed: 25.0, stateName: .moving, label: "Đang đi làm (Đoạn gần tới)")
            } else {
                applyWorkingState()
            }

        case 9...11:
            // 09:00 - 11:59: Làm việc sáng tại cơ quan
            applyWorkingState()

        case 12:
            // 12:00 - 13:00: Đi ăn trưa / cà phê
            startCommute(from: workLocation, to: cafeLocation, speed: 4.5, stateName: .resting, label: "Nghỉ trưa & Cà phê")

        case 13...17:
            // 13:00 - 17:59: Làm việc chiều tại cơ quan
            applyWorkingState()

        case 18:
            // 18:00 - 19:00: Tan sở về nhà
            startCommute(from: workLocation, to: homeLocation, speed: 22.0, stateName: .moving, label: "Tan sở về nhà (Cơ quan -> Nhà)")

        case 19...22:
            // 19:00 - 22:59: Tối nghỉ ngơi / đi dạo quanh khu nhà
            applyWanderingState()

        default:
            applySleepingState()
        }
    }

    private func startScheduleMonitoring() {
        routineTimer?.invalidate()
        routineTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.evaluateCurrentTimeSchedule()
        }
        evaluateCurrentTimeSchedule()
    }

    private func applySleepingState() {
        activeCommuteKey = nil
        currentState = .sleeping
        currentSpeedKmh = 0.0
        statusDescription = "Ở Nhà (Nghỉ ngơi ban đêm)"
        moveStepTimer?.invalidate()
        _ = SpoofEngine.shared.submit(latitude: homeLocation.latitude, longitude: homeLocation.longitude, from: .routine)
    }

    private func applyWorkingState() {
        activeCommuteKey = nil
        currentState = .working
        currentSpeedKmh = 0.0
        statusDescription = "Ở Nơi làm việc (Cố định)"
        moveStepTimer?.invalidate()
        _ = SpoofEngine.shared.submit(latitude: workLocation.latitude, longitude: workLocation.longitude, from: .routine)
    }

    private func applyWanderingState() {
        activeCommuteKey = nil
        currentState = .wandering
        currentSpeedKmh = 3.8
        statusDescription = "Đi dạo tối quanh khu vực nhà (~4 km/h)"
        moveStepTimer?.invalidate()

        // Tạo toạ độ dạo quanh bán kính ~400m quanh nhà
        let deltaLat = Double.random(in: -0.003...0.003)
        let deltaLon = Double.random(in: -0.003...0.003)
        _ = SpoofEngine.shared.submit(
            latitude: homeLocation.latitude + deltaLat,
            longitude: homeLocation.longitude + deltaLon,
            from: .routine
        )
    }

    /// Di chuyển mượt theo tuyến đường giữa 2 toạ độ
    private func startCommute(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, speed: Double, stateName: RoutineState, label: String) {
        // Lịch được đánh giá mỗi 60 giây. Nếu không có khoá này, mỗi lần đánh giá sẽ dựng lại
        // lộ trình từ đầu khiến vị trí nhảy ngược về điểm xuất phát và không bao giờ tới nơi.
        let key = String(format: "%@|%.5f,%.5f|%.5f,%.5f", label, from.latitude, from.longitude, to.latitude, to.longitude)
        if activeCommuteKey == key { return }
        activeCommuteKey = key

        currentState = stateName
        currentSpeedKmh = speed
        statusDescription = "\(label) [\(Int(speed)) km/h]"

        // Tạo 40 điểm trung gian thẳng mượt
        let steps = 40
        targetRoute.removeAll()
        for i in 0...steps {
            let fraction = Double(i) / Double(steps)
            let lat = from.latitude + (to.latitude - from.latitude) * fraction
            let lon = from.longitude + (to.longitude - from.longitude) * fraction
            targetRoute.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }

        currentWaypointIndex = 0
        moveStepTimer?.invalidate()
        moveStepTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] timer in
            guard let self = self else { return }
            if self.currentWaypointIndex < self.targetRoute.count {
                let coord = self.targetRoute[self.currentWaypointIndex]
                _ = SpoofEngine.shared.submit(latitude: coord.latitude, longitude: coord.longitude, from: .routine)
                self.currentWaypointIndex += 1
            } else {
                timer.invalidate()
            }
        }
    }

    // MARK: - Chế độ Du lịch (ghi đè tạm thời địa điểm thật)

    /// Ảnh chụp địa điểm thật của người dùng, giữ lại trong lúc chế độ du lịch ghi đè.
    private struct PlacesSnapshot: Codable {
        var home: CoordinateCodable
        var work: CoordinateCodable
        var cafe: CoordinateCodable
        var bookmarks: [PlaceBookmark]
    }

    private static let travelBackupKey = "routine_places_backup"

    /// Đang ở chế độ du lịch (địa điểm hiện tại là tạm, không phải của người dùng).
    @Published private(set) var isTravelOverrideActive: Bool = false

    /// Gọi TRƯỚC khi chế độ du lịch ghi đè home/work/cafe/bookmarks.
    ///
    /// Trước đây FlightManager ghi thẳng và persist ngay, xoá vĩnh viễn địa điểm thật của
    /// người dùng mà không có đường lùi. Nay bản gốc được cất trước, và `endTravelOverride()`
    /// trả lại nguyên trạng. Gọi nhiều lần chỉ chụp một lần duy nhất.
    func beginTravelOverride() {
        guard !isTravelOverrideActive else { return }
        let snap = PlacesSnapshot(home: CoordinateCodable(homeLocation),
                                  work: CoordinateCodable(workLocation),
                                  cafe: CoordinateCodable(cafeLocation),
                                  bookmarks: bookmarks)
        if let data = try? JSONEncoder().encode(snap) {
            UserDefaults.standard.set(data, forKey: RoutineManager.travelBackupKey)
        }
        isTravelOverrideActive = true
    }

    /// Trả lại địa điểm thật sau khi kết thúc chuyến đi.
    func endTravelOverride() {
        defer { isTravelOverrideActive = false }
        guard let data = UserDefaults.standard.data(forKey: RoutineManager.travelBackupKey),
              let snap = try? JSONDecoder().decode(PlacesSnapshot.self, from: data) else { return }
        homeLocation = snap.home.clCoordinate
        workLocation = snap.work.clCoordinate
        cafeLocation = snap.cafe.clCoordinate
        bookmarks = snap.bookmarks
        UserDefaults.standard.removeObject(forKey: RoutineManager.travelBackupKey)
    }

    // MARK: - Lưu trữ Cấu hình
    private func saveLocations() {
        UserDefaults.standard.set(homeLocation.latitude, forKey: "routine_home_lat")
        UserDefaults.standard.set(homeLocation.longitude, forKey: "routine_home_lon")
        UserDefaults.standard.set(workLocation.latitude, forKey: "routine_work_lat")
        UserDefaults.standard.set(workLocation.longitude, forKey: "routine_work_lon")
        UserDefaults.standard.set(cafeLocation.latitude, forKey: "routine_cafe_lat")
        UserDefaults.standard.set(cafeLocation.longitude, forKey: "routine_cafe_lon")
    }

    /// Đọc một toạ độ đã lưu. Trả về nil nếu chưa từng lưu.
    ///
    /// Phải kiểm tra sự tồn tại của khoá chứ không so sánh với 0.0: toạ độ (0, 0) và mọi
    /// điểm trên xích đạo hay kinh tuyến gốc đều hợp lệ và sẽ bị bỏ qua nếu dùng `!= 0.0`.
    private func loadCoordinate(_ prefix: String) -> CLLocationCoordinate2D? {
        let d = UserDefaults.standard
        guard d.object(forKey: prefix + "_lat") != nil,
              d.object(forKey: prefix + "_lon") != nil else { return nil }
        let coord = CLLocationCoordinate2D(latitude: d.double(forKey: prefix + "_lat"),
                                           longitude: d.double(forKey: prefix + "_lon"))
        return CLLocationCoordinate2DIsValid(coord) ? coord : nil
    }

    private func loadSavedLocations() {
        if let c = loadCoordinate("routine_home") { self.homeLocation = c }
        if let c = loadCoordinate("routine_work") { self.workLocation = c }
        if let c = loadCoordinate("routine_cafe") { self.cafeLocation = c }
    }

    private func saveBookmarks() {
        if let data = try? JSONEncoder().encode(bookmarks) {
            UserDefaults.standard.set(data, forKey: "routine_bookmarks")
        }
    }

    private func loadSavedBookmarks() {
        if let data = UserDefaults.standard.data(forKey: "routine_bookmarks"),
           let list = try? JSONDecoder().decode([PlaceBookmark].self, from: data) {
            self.bookmarks = list
        } else {
            // Danh sách địa điểm mặc định
            self.bookmarks = [
                PlaceBookmark(name: "Hồ Hoàn Kiếm", latitude: 21.0285, longitude: 105.8542),
                PlaceBookmark(name: "Vincom Metropolis", latitude: 21.0315, longitude: 105.8166),
                PlaceBookmark(name: "Keangnam Landmark 72", latitude: 21.0172, longitude: 105.7838)
            ]
        }
    }
}
