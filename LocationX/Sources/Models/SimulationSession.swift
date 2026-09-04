import CoreLocation
import Foundation

/// Phiên mô phỏng — mỗi lần Start tạo một session mới.
/// Session giữ toàn bộ trạng thái cần thiết để pause/resume/replay.
struct SimulationSession: Identifiable, Codable {
    let id: UUID
    let createdAt: Date
    var startedAt: Date?
    var endedAt: Date?
    var source: SimulationSource
    var travelMode: TravelMode
    var speedProfile: SpeedProfile
    var noiseConfig: GPSNoiseConfig

    // Route info
    var routeWaypoints: [CoordinateCodable] = []
    var routeName: String?

    // Position state
    var startCoordinate: CoordinateCodable?
    var endCoordinate: CoordinateCodable?
    var currentCoordinate: CoordinateCodable?
    var currentSegmentIndex: Int = 0
    var segmentProgress: Double = 0

    // Telemetry
    var distanceTravelledMeters: Double = 0
    var distanceRemainingMeters: Double = 0
    var elapsedSeconds: TimeInterval = 0
    var averageSpeedKmh: Double = 0
    var maxSpeedKmh: Double = 0
    var currentSpeedKmh: Double = 0
    var currentHeadingDegrees: Double = 0

    // State
    var status: SimulationState = .idle

    // Flight-specific
    var flightNumber: String?
    var originAirport: String?
    var destinationAirport: String?
    var altitudeMeters: Double = 0

    init(source: SimulationSource, travelMode: TravelMode = .driving) {
        self.id = UUID()
        self.createdAt = Date()
        self.source = source
        self.travelMode = travelMode
        self.speedProfile = travelMode.defaultSpeed
        self.noiseConfig = .normal
    }

    var durationFormatted: String {
        let minutes = Int(elapsedSeconds) / 60
        let seconds = Int(elapsedSeconds) % 60
        if minutes > 60 {
            return String(format: "%dh%02dm", minutes / 60, minutes % 60)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    var distanceFormatted: String {
        if distanceTravelledMeters > 1000 {
            return String(format: "%.1f km", distanceTravelledMeters / 1000)
        }
        return String(format: "%.0f m", distanceTravelledMeters)
    }
}

// MARK: - Route Models

struct RouteWaypoint: Identifiable, Codable, Equatable {
    let id: UUID
    var coordinate: CoordinateCodable
    var name: String?
    var dwellSeconds: TimeInterval = 0

    init(coordinate: CLLocationCoordinate2D, name: String? = nil, dwellSeconds: TimeInterval = 0) {
        self.id = UUID()
        self.coordinate = CoordinateCodable(coordinate)
        self.name = name
        self.dwellSeconds = dwellSeconds
    }
}

struct RouteSegment: Codable {
    var startIndex: Int
    var endIndex: Int
    var coordinates: [CoordinateCodable]
    var distanceMeters: Double
    var estimatedSeconds: TimeInterval
}

struct SavedRoute: Identifiable, Codable {
    let id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var waypoints: [RouteWaypoint]
    var travelMode: TravelMode
    var totalDistanceMeters: Double
    var estimatedDurationSeconds: TimeInterval
    /// Hình học đầy đủ đã tính (đã resample), dùng để chạy lại đúng con đường đã xem trước.
    ///
    /// **Bắt buộc lưu.** Trước đây trường này không bao giờ được gán ở bất kỳ đâu, nên
    /// `ScenarioAction.followRoute` — vốn đọc chính nó — là no-op vĩnh viễn, và mọi tuyến
    /// đã lưu hiện 0 m / 0 phút.
    var routeGeometry: [CoordinateCodable]?
    /// Lần gần nhất tuyến được chạy. `nil` = chưa chạy lần nào.
    /// Optional nên file routes.json cũ (không có khoá này) vẫn giải mã được.
    var lastUsedAt: Date?
    /// Tốc độ hành trình người dùng chọn, km/h. `nil` = dùng mặc định của phương tiện.
    var cruiseSpeedKmh: Double?

    /// Tốc độ thực sẽ dùng khi chạy tuyến này.
    var effectiveCruiseSpeedKmh: Double {
        cruiseSpeedKmh ?? travelMode.defaultSpeed.cruise
    }

    /// Toạ độ dùng để chạy: ưu tiên hình học đã tính, nếu chưa có thì nối thẳng waypoint.
    var runnableCoordinates: [CLLocationCoordinate2D] {
        if let geometry = routeGeometry, geometry.count >= 2 {
            return geometry.map(\.clCoordinate)
        }
        return waypoints.map { $0.coordinate.clCoordinate }
    }

    init(name: String, waypoints: [RouteWaypoint], travelMode: TravelMode = .driving) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.updatedAt = Date()
        self.waypoints = waypoints
        self.travelMode = travelMode
        self.totalDistanceMeters = 0
        self.estimatedDurationSeconds = 0
    }

    /// Khởi tạo đầy đủ — dùng khi đã tính xong tuyến, để thẻ tuyến hiện đúng số liệu.
    init(name: String,
         waypoints: [RouteWaypoint],
         travelMode: TravelMode,
         geometry: [CoordinateCodable],
         totalDistanceMeters: Double,
         estimatedDurationSeconds: TimeInterval,
         cruiseSpeedKmh: Double? = nil) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.updatedAt = Date()
        self.waypoints = waypoints
        self.travelMode = travelMode
        self.totalDistanceMeters = totalDistanceMeters
        self.estimatedDurationSeconds = estimatedDurationSeconds
        self.routeGeometry = geometry
        self.cruiseSpeedKmh = cruiseSpeedKmh
    }
}

// MARK: - Scenario Models

struct Scenario: Identifiable, Codable {
    let id: UUID
    var name: String
    var steps: [ScenarioStep]
    var createdAt: Date
    var isLoop: Bool = false

    init(name: String, steps: [ScenarioStep] = []) {
        self.id = UUID()
        self.name = name
        self.steps = steps
        self.createdAt = Date()
    }
}

struct ScenarioStep: Identifiable, Codable {
    let id: UUID
    var action: ScenarioAction
    var order: Int

    init(action: ScenarioAction, order: Int) {
        self.id = UUID()
        self.action = action
        self.order = order
    }
}

enum ScenarioAction: Codable {
    case setLocation(CoordinateCodable)
    case moveTo(CoordinateCodable, speedKmh: Double)
    case followRoute(routeId: UUID)
    case wait(seconds: TimeInterval)
    case changeSpeed(kmh: Double)
    case changeTravelMode(TravelMode)
    case pause
    case resume
    case loop(times: Int)
    case dwell(seconds: TimeInterval)
    case randomNearby(radiusMeters: Double, durationSeconds: TimeInterval)

    var displayName: String {
        switch self {
        case .setLocation:     return L("scenario.action.set_location")
        case .moveTo:          return L("scenario.action.move_to")
        case .followRoute:     return L("scenario.action.follow_route")
        case .wait:            return L("scenario.action.wait")
        case .changeSpeed:     return L("scenario.action.change_speed")
        case .changeTravelMode: return L("scenario.action.change_travel_mode")
        case .pause:           return L("action.pause")
        case .resume:          return L("action.resume")
        case .loop:            return L("scenario.action.loop")
        case .dwell:           return L("scenario.action.dwell")
        case .randomNearby:    return L("scenario.action.random_nearby")
        }
    }
}

// MARK: - Routine Models

struct RoutineSchedule: Identifiable, Codable {
    let id: UUID
    var name: String
    var timeString: String  // "07:30"
    var days: Set<Int>      // 1=Mon, 7=Sun
    var startLocation: CoordinateCodable
    var endLocation: CoordinateCodable
    var travelMode: TravelMode
    var isEnabled: Bool = true

    init(name: String, time: String, days: Set<Int>, start: CLLocationCoordinate2D, end: CLLocationCoordinate2D) {
        self.id = UUID()
        self.name = name
        self.timeString = time
        self.days = days
        self.startLocation = CoordinateCodable(start)
        self.endLocation = CoordinateCodable(end)
        self.travelMode = .driving
    }

    var hour: Int { Int(timeString.prefix(2)) ?? 0 }
    var minute: Int { Int(timeString.suffix(2)) ?? 0 }
}

// MARK: - History

struct SimulationRecord: Identifiable, Codable {
    let id: UUID
    let sessionId: UUID
    let source: SimulationSource
    let startedAt: Date
    let endedAt: Date
    let startCoordinate: CoordinateCodable
    let endCoordinate: CoordinateCodable
    let distanceMeters: Double
    let durationSeconds: TimeInterval
    let travelMode: TravelMode
    let routeName: String?
    let replayData: [TimestampedCoordinate]?
}

struct TimestampedCoordinate: Codable {
    let timestamp: TimeInterval  // seconds since session start
    let coordinate: CoordinateCodable
    let speedKmh: Double
    let headingDegrees: Double
}

// MARK: - Bookmark

struct LocationBookmark: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var coordinate: CoordinateCodable
    var address: String?
    var category: BookmarkCategory
    var createdAt: Date
    var lastUsedAt: Date?

    init(name: String, coordinate: CLLocationCoordinate2D, category: BookmarkCategory = .custom) {
        self.id = UUID()
        self.name = name
        self.coordinate = CoordinateCodable(coordinate)
        self.category = category
        self.createdAt = Date()
    }
}

enum BookmarkCategory: String, Codable, CaseIterable {
    case home
    case work
    case cafe
    case airport
    case custom

    var icon: String {
        switch self {
        case .home:    return "house.fill"
        case .work:    return "briefcase.fill"
        case .cafe:    return "cup.and.saucer.fill"
        case .airport: return "airplane.circle.fill"
        case .custom:  return "mappin"
        }
    }

    var displayName: String {
        switch self {
        case .home:    return L("bookmarks.category.home")
        case .work:    return L("bookmarks.category.work")
        case .cafe:    return L("bookmarks.category.cafe")
        case .airport: return L("bookmarks.category.airport")
        case .custom:  return L("bookmarks.category.custom")
        }
    }
}
