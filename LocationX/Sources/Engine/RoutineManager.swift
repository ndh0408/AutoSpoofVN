import Foundation
import CoreLocation
import MapKit

/// Quản lý chu trình tự động theo thói quen sinh hoạt thực tế (Đi làm, Nghỉ trưa, Đi dạo, Ngủ)
final class RoutineManager: ObservableObject {
    static let shared = RoutineManager()

    @Published var currentState: RoutineState = .working
    @Published var isAutoRoutineEnabled: Bool = false
    @Published var currentSpeedKmh: Double = 0.0
    @Published var statusDescription: String = L("simulation.idle")

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

    /// `moveStepTimer` đang phục vụ việc gì.
    private enum MoveMode { case idle, commute, walk }
    private var moveMode: MoveMode = .idle

    /// Tuyến đang chạy là đường thật hay đường thẳng nội suy. Hiển thị được trên UI
    /// để người dùng biết mô phỏng đang ở mức nào.
    @Published private(set) var isFollowingRealRoad: Bool = false
    /// Số lần phải lùi về nội suy thẳng vì MKDirections không trả được tuyến.
    @Published private(set) var routeFallbackCount: Int = 0

    /// Tác vụ đang lấy tuyến đường thật. Huỷ khi đổi chặng.
    private var routeTask: Task<Void, Never>? = nil
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
        if isAutoRoutineEnabled {
            stopAutoRoutine()
        } else {
            isAutoRoutineEnabled = true
            statusDescription = L("routine.status.auto_running")
            // Bat chu trinh la hanh dong khoi dong ro rang -> go trang thai "da dung han".
            _ = SpoofEngine.shared.acquire(.routine)
            startScheduleMonitoring()
        }
    }

    /// Dừng hẳn chu trình 24/7.
    ///
    /// Tách khỏi `toggleAutoRoutine()` vì đó là công tắc đảo trạng thái: gọi nó để dừng
    /// mà chu trình đang tắt thì lại BẬT lên. `SimulationCoordinator.stopSession()` cần
    /// một lệnh dừng dứt khoát — đây là lý do nút Dừng trước đây không dừng được chu trình.
    func stopAutoRoutine() {
        isAutoRoutineEnabled = false
        statusDescription = L("routine.status.auto_paused")
        routineTimer?.invalidate()
        routineTimer = nil
        moveStepTimer?.invalidate()
        moveStepTimer = nil
        routeTask?.cancel()
        routeTask = nil
        activeCommuteKey = nil
        moveMode = .idle
        isFollowingRealRoad = false
        currentSpeedKmh = 0.0
        SpoofEngine.shared.release(.routine)
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
                startCommute(from: homeLocation, to: workLocation, speed: 30.0, stateName: .moving, labelKey: "routine.commute.to_work")
            }

        case 8:
            if minute < 30 {
                startCommute(from: homeLocation, to: workLocation, speed: 25.0, stateName: .moving, labelKey: "routine.commute.to_work_near")
            } else {
                applyWorkingState()
            }

        case 9...11:
            // 09:00 - 11:59: Làm việc sáng tại cơ quan
            applyWorkingState()

        case 12:
            // 12:00 - 13:00: Đi ăn trưa / cà phê
            startCommute(from: workLocation, to: cafeLocation, speed: 4.5, stateName: .resting, labelKey: "routine.commute.lunch_cafe")

        case 13...17:
            // 13:00 - 17:59: Làm việc chiều tại cơ quan
            applyWorkingState()

        case 18:
            // 18:00 - 19:00: Tan sở về nhà
            startCommute(from: workLocation, to: homeLocation, speed: 22.0, stateName: .moving, labelKey: "routine.commute.to_home")

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
        moveMode = .idle
        currentState = .sleeping
        currentSpeedKmh = 0.0
        statusDescription = L("routine.status.sleeping")
        moveStepTimer?.invalidate()
        _ = SpoofEngine.shared.submit(latitude: homeLocation.latitude, longitude: homeLocation.longitude, from: .routine)
    }

    private func applyWorkingState() {
        activeCommuteKey = nil
        moveMode = .idle
        currentState = .working
        currentSpeedKmh = 0.0
        statusDescription = L("routine.status.working")
        moveStepTimer?.invalidate()
        _ = SpoofEngine.shared.submit(latitude: workLocation.latitude, longitude: workLocation.longitude, from: .routine)
    }

    private func applyWanderingState() {
        activeCommuteKey = nil
        currentState = .wandering
        currentSpeedKmh = 3.8
        statusDescription = L("routine.status.wandering")

        // Bản cũ mỗi lần đánh giá lịch lại nhảy tới một điểm ngẫu nhiên trong bán kính
        // ~330 m. Với chu kỳ 60 giây, đó là những cú dịch chuyển tức thời tới 660 m —
        // tương đương 40 km/h mà trạng thái lại ghi "đi bộ 4 km/h".
        // Nay đi bộ liên tục: mỗi 3 giây một bước, hướng đi đổi từ từ.
        // Đang đi dạo rồi thì để yên; nhưng nếu timer đang phục vụ chặng đi làm thì
        // phải dừng nó lại, nếu không buổi tối vẫn tiếp tục "lái xe".
        if moveMode == .walk, let t = moveStepTimer, t.isValid { return }
        startWalk()
    }

    /// Đi bộ liên tục quanh nhà với hướng đi biến thiên chậm.
    private func startWalk() {
        moveStepTimer?.invalidate()
        moveMode = .walk
        var position = SpoofEngine.shared.currentCoordinate
        // Nếu đang ở quá xa nhà thì bắt đầu lại từ nhà.
        if GeodesicMath.distanceKm(from: position, to: homeLocation) > 0.6 {
            position = homeLocation
        }
        var headingRadians = Double.random(in: 0..<(2 * .pi))

        let stepSeconds = 3.0
        let timer = Timer(timeInterval: stepSeconds, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            // Tốc độ đi bộ dao động nhẹ quanh 4 km/h.
            let speedKmh = Double.random(in: 3.2...4.6)
            self.currentSpeedKmh = speedKmh
            let metres = speedKmh * 1000.0 / 3600.0 * stepSeconds

            // Đổi hướng từ từ; người đi bộ không quay ngoắt.
            headingRadians += Double.random(in: -0.35...0.35)

            let cosLat = cos(position.latitude * .pi / 180.0)
            let lonScale = abs(cosLat) < 1e-6 ? 1e-6 : abs(cosLat)

            // Ra quá xa nhà thì bẻ dần hướng quay về.
            let distanceKm = GeodesicMath.distanceKm(from: position, to: self.homeLocation)
            if distanceKm > 0.45 {
                // Chênh lệch kinh độ phải quy về cùng đơn vị mét với vĩ độ, nếu không
                // hướng tính ra sẽ lệch theo vĩ độ nơi đang đứng.
                let toHome = atan2(
                    (self.homeLocation.longitude - position.longitude) * lonScale,
                    self.homeLocation.latitude - position.latitude
                )
                // Đưa chênh lệch góc về [-pi, pi]. Không có bước này thì khi hướng hiện tại
                // và hướng về nhà nằm hai bên mốc +/-pi, người đi bộ sẽ quay vòng đường xa.
                var delta = toHome - headingRadians
                delta = atan2(sin(delta), cos(delta))
                headingRadians += delta * 0.4
            }
            position = CLLocationCoordinate2D(
                latitude: position.latitude + (metres * cos(headingRadians)) / 111_320.0,
                longitude: position.longitude + (metres * sin(headingRadians)) / (111_320.0 * lonScale)
            )
            _ = SpoofEngine.shared.submit(latitude: position.latitude,
                                          longitude: position.longitude,
                                          from: .routine)
        }
        RunLoop.main.add(timer, forMode: .common)
        moveStepTimer = timer
    }

    /// Di chuyển mượt theo tuyến đường giữa 2 toạ độ
    private func startCommute(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, speed: Double, stateName: RoutineState, labelKey: String) {
        // Lịch được đánh giá mỗi 60 giây. Nếu không có khoá này, mỗi lần đánh giá sẽ dựng lại
        // lộ trình từ đầu khiến vị trí nhảy ngược về điểm xuất phát và không bao giờ tới nơi.
        // Khoá dựng từ `labelKey` (bất biến) chứ không phải nhãn đã dịch: đổi ngôn ngữ giữa
        // chừng không được coi là một chặng mới.
        let key = String(format: "%@|%.5f,%.5f|%.5f,%.5f", labelKey, from.latitude, from.longitude, to.latitude, to.longitude)
        if activeCommuteKey == key { return }
        activeCommuteKey = key

        currentState = stateName
        currentSpeedKmh = speed
        statusDescription = L("routine.status.commuting", L(labelKey), Int(speed))

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
        moveMode = .commute
        isFollowingRealRoad = false

        // Bắt đầu ngay bằng đường thẳng, rồi thay bằng đường thật khi lấy được.
        //
        // Cố tình không chờ MKDirections trước khi khởi hành: nó cần mạng, có hạn mức
        // gọi, và trong một ứng dụng phải chạy 24/7 thì một lần gọi mạng hỏng không được
        // phép làm đứng cả chu trình.
        requestRealRoad(from: from, to: to, speed: speed, key: key)

        // Xe thật không chạy đều một tốc độ từ đầu tới cuối. Ba yếu tố dưới đây khiến
        // vệt di chuyển bớt lộ: tăng tốc lúc rời đi, giảm tốc lúc gần tới, và dừng
        // ngẫu nhiên như gặp đèn đỏ.
        var stoppedTicksRemaining = 0
        let timer = Timer(timeInterval: 2.5, repeats: true) { [weak self] timer in
            guard let self = self else { return }

            if stoppedTicksRemaining > 0 {
                stoppedTicksRemaining -= 1
                self.currentSpeedKmh = 0
                // Vẫn gửi lại toạ độ hiện tại: đứng yên không có nghĩa là mất tín hiệu.
                // Chỉ số phải kẹp cả hai đầu — `count - 1` bằng -1 khi mảng rỗng, và
                // một lần treo chỉ số ở đây là crash cho app phải sống 24/7.
                if let coord = self.targetRoute[safe: min(self.currentWaypointIndex, self.targetRoute.count - 1)] {
                    _ = SpoofEngine.shared.submit(latitude: coord.latitude, longitude: coord.longitude, from: .routine)
                }
                return
            }

            guard self.currentWaypointIndex < self.targetRoute.count else {
                timer.invalidate()
                self.currentSpeedKmh = 0
                return
            }

            let progress = Double(self.currentWaypointIndex) / Double(max(1, self.targetRoute.count - 1))
            // Hệ số hình thang: chậm ở hai đầu, đủ tốc ở giữa.
            let ramp = min(1.0, min(progress, 1.0 - progress) / 0.15)
            self.currentSpeedKmh = speed * (0.25 + 0.75 * ramp)

            let coord = self.targetRoute[self.currentWaypointIndex]
            _ = SpoofEngine.shared.submit(latitude: coord.latitude, longitude: coord.longitude, from: .routine)
            self.currentWaypointIndex += 1

            // Dừng đèn đỏ: chỉ ở đoạn giữa, và chỉ khi đang di chuyển bằng xe.
            if speed > 10, progress > 0.15, progress < 0.85, Double.random(in: 0...1) < 0.08 {
                stoppedTicksRemaining = Int.random(in: 4...12)   // 10 - 30 giây
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        moveStepTimer = timer
    }

    /// Hỏi đường đi thật rồi thay tuyến đang chạy, giữ nguyên phần đã đi được.
    private func requestRealRoad(from: CLLocationCoordinate2D,
                                 to: CLLocationCoordinate2D,
                                 speed: Double,
                                 key: String) {
        routeTask?.cancel()
        // Đi bộ dưới 8 km/h, còn lại coi như đi xe.
        let transport: MKDirectionsTransportType = speed < 8.0 ? .walking : .automobile
        // Khoảng cách lấy mẫu tính từ tốc độ, sao cho mỗi nhịp 2,5 giây đi được một điểm.
        let spacing = max(5.0, speed * 1000.0 / 3600.0 * 2.5)

        routeTask = Task { [weak self] in
            let result = await RouteProvider.shared.resolveRoute(
                named: key,
                from: from,
                to: to,
                transportType: transport,
                speedKmh: speed,
                sampleSpacingMeters: spacing
            )
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                // Chặng có thể đã đổi trong lúc chờ mạng.
                guard self.activeCommuteKey == key, self.moveMode == .commute else { return }
                self.applyRoute(result)
            }
        }
    }

    private func applyRoute(_ result: RouteProvider.RouteResult) {
        let coords = result.plan.waypoints.map(\.clCoordinate)
        guard coords.count >= 2 else {
            routeFallbackCount += 1
            return
        }

        if result.usedFallback {
            routeFallbackCount += 1
            isFollowingRealRoad = false
            return   // tuyến thẳng đang chạy đã tương đương, không cần thay
        }

        // Giữ nguyên tỉ lệ quãng đường đã đi khi đổi sang tuyến mới, nếu không người
        // dùng ảo sẽ nhảy ngược về đầu đúng lúc đường thật vừa tới.
        let progress = targetRoute.isEmpty
            ? 0.0
            : min(1.0, Double(currentWaypointIndex) / Double(max(1, targetRoute.count - 1)))

        targetRoute = coords
        currentWaypointIndex = min(coords.count - 1, Int(progress * Double(coords.count - 1)))
        isFollowingRealRoad = true
        statusDescription += " · " + L("routine.real_road")
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

extension Array {
    /// Truy cập theo chỉ số an toàn: trả về `nil` thay vì dừng chương trình.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
