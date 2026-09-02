import Foundation
import CoreLocation

/// Quản lý chu trình tự động theo thói quen sinh hoạt thực tế (Đi làm, Nghỉ trưa, Đi dạo, Ngủ)
final class RoutineManager: ObservableObject {
    static let shared = RoutineManager()

    @Published var currentState: RoutineState = .working
    @Published var isAutoRoutineEnabled: Bool = false
    @Published var currentSpeedKmh: Double = 0.0
    @Published var statusDescription: String = "Sẵn sàng"

    // Các điểm cố định mặc định (Ví dụ khu vực Hoàn Kiếm / Cầu Giấy, Hà Nội)
    @Published var homeLocation = CLLocationCoordinate2D(latitude: 21.0333, longitude: 105.8433)
    @Published var workLocation = CLLocationCoordinate2D(latitude: 21.0245, longitude: 105.7890)
    @Published var cafeLocation = CLLocationCoordinate2D(latitude: 21.0285, longitude: 105.8342)

    private var routineTimer: Timer?
    private var moveStepTimer: Timer?
    private var targetRoute: [CLLocationCoordinate2D] = []
    private var currentWaypointIndex: Int = 0

    private init() {}

    /// Bật/Tắt chu trình mô phỏng tự động cả ngày
    func toggleAutoRoutine() {
        isAutoRoutineEnabled.toggle()
        if isAutoRoutineEnabled {
            statusDescription = "Đang chạy chu trình tự động 24/7"
            startScheduleMonitoring()
        } else {
            statusDescription = "Đã tạm dừng chu trình tự động"
            routineTimer?.invalidate()
            moveStepTimer?.invalidate()
        }
    }

    /// Kiểm tra khung giờ thực tế để tự chuyển trạng thái phù hợp
    private func startScheduleMonitoring() {
        routineTimer?.invalidate()
        routineTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.evaluateCurrentTimeSchedule()
        }
        evaluateCurrentTimeSchedule()
    }

    /// Phân tích giờ trong ngày để mô phỏng tự nhiên
    func evaluateCurrentTimeSchedule() {
        let hour = Calendar.current.component(.hour, from: Date())
        let minute = Calendar.current.component(.minute, from: Date())

        switch hour {
        case 23...24, 0...6:
            // 23:00 - 06:59: Đi ngủ tại nhà (Đứng yên, GPS Jitter nhẹ)
            applySleepingState()

        case 7...8:
            // 07:00 - 08:30: Đi làm từ Nhà -> Công ty
            startCommute(from: homeLocation, to: workLocation, speed: 25.0, stateName: .moving)

        case 9...11:
            // 09:00 - 11:59: Làm việc tại công ty
            applyWorkingState()

        case 12:
            // 12:00 - 13:00: Nghỉ trưa, đi ăn / cà phê
            startCommute(from: workLocation, to: cafeLocation, speed: 4.5, stateName: .resting)

        case 13...17:
            // 13:00 - 17:30: Chiều làm việc
            applyWorkingState()

        case 18...19:
            // 18:00 - 19:30: Tan làm về nhà
            startCommute(from: workLocation, to: homeLocation, speed: 20.0, stateName: .moving)

        default:
            // Buổi tối: Đi dạo loanh quanh hoặc nghỉ ngơi
            applyWanderingState()
        }
    }

    private func applySleepingState() {
        currentState = .sleeping
        currentSpeedKmh = 0.0
        statusDescription = "Đang ở Nhà (Chế độ ngủ đêm)"
        SpoofEngine.shared.setLocation(latitude: homeLocation.latitude, longitude: homeLocation.longitude)
    }

    private func applyWorkingState() {
        currentState = .working
        currentSpeedKmh = 0.0
        statusDescription = "Đang ở Nơi làm việc (Cố định)"
        SpoofEngine.shared.setLocation(latitude: workLocation.latitude, longitude: workLocation.longitude)
    }

    private func applyWanderingState() {
        currentState = .wandering
        currentSpeedKmh = 3.5
        statusDescription = "Đang đi dạo tối quanh khu vực"
        // Tạo bước di chuyển bán kính 500m quanh nhà
        let deltaLat = Double.random(in: -0.002...0.002)
        let deltaLon = Double.random(in: -0.002...0.002)
        SpoofEngine.shared.setLocation(latitude: homeLocation.latitude + deltaLat, longitude: homeLocation.longitude + deltaLon)
    }

    /// Bắt đầu di chuyển dọc theo các bước lộ trình giữa 2 điểm
    private func startCommute(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, speed: Double, stateName: RoutineState) {
        currentState = stateName
        currentSpeedKmh = speed
        statusDescription = "\(stateName.rawValue) (Tốc độ: \(speed) km/h)"

        // Tạo 30 điểm trung gian thẳng mượt
        let steps = 30
        targetRoute.removeAll()
        for i in 0...steps {
            let fraction = Double(i) / Double(steps)
            let lat = from.latitude + (to.latitude - from.latitude) * fraction
            let lon = from.longitude + (to.longitude - from.longitude) * fraction
            targetRoute.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }

        currentWaypointIndex = 0
        moveStepTimer?.invalidate()
        moveStepTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
            guard let self = self else { return }
            if self.currentWaypointIndex < self.targetRoute.count {
                let coord = self.targetRoute[self.currentWaypointIndex]
                SpoofEngine.shared.setLocation(latitude: coord.latitude, longitude: coord.longitude)
                self.currentWaypointIndex += 1
            } else {
                timer.invalidate()
            }
        }
    }
}
