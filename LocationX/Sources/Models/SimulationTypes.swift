import CoreLocation
import Foundation

// MARK: - Simulation Source

/// Tất cả nguồn có thể điều khiển GPS. Mỗi thời điểm chỉ MỘT nguồn hoạt động.
enum SimulationSource: String, CaseIterable, Codable, Identifiable {
    case manual
    case route
    case scenario
    case routine
    case flight
    case replay

    var id: String { rawValue }

    /// Ưu tiên cao hơn = thắng khi tranh chấp. Manual luôn thắng.
    var priority: Int {
        switch self {
        case .manual:   return 100
        case .scenario: return 80
        case .flight:   return 60
        case .route:    return 50
        case .routine:  return 40
        case .replay:   return 20
        }
    }

    var displayName: String {
        switch self {
        case .manual:   return L("simulation.source.manual")
        case .route:    return L("simulation.source.route")
        case .scenario: return L("simulation.source.scenario")
        case .routine:  return L("simulation.source.routine")
        case .flight:   return L("simulation.source.flight")
        case .replay:   return L("simulation.source.replay")
        }
    }

    var icon: String {
        switch self {
        case .manual:   return "hand.tap"
        case .route:    return "map"
        case .scenario: return "list.bullet.clipboard"
        case .routine:  return "clock.arrow.2.circlepath"
        case .flight:   return "airplane"
        case .replay:   return "arrow.counterclockwise"
        }
    }
}

// MARK: - Simulation State Machine

/// Trạng thái mô phỏng — enum duy nhất, không phải đống Bool.
enum SimulationState: Equatable, Codable {
    case idle
    case preparing
    case running
    case paused
    case stopping
    case completed
    case failed(String)

    var isActive: Bool {
        switch self {
        case .running, .paused: return true
        default: return false
        }
    }

    var canStart: Bool { self == .idle || self == .completed || self == .failed("") || isFailed }

    var canPause: Bool { self == .running }

    var canResume: Bool { self == .paused }

    var canStop: Bool {
        switch self {
        case .running, .paused, .preparing: return true
        default: return false
        }
    }

    private var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }

    var displayName: String {
        switch self {
        case .idle:        return L("simulation.idle")
        case .preparing:   return L("simulation.preparing")
        case .running:     return L("simulation.running")
        case .paused:      return L("simulation.paused")
        case .stopping:    return L("simulation.stopping")
        case .completed:   return L("simulation.completed")
        case .failed(let msg): return L("common.error_detail", msg)
        }
    }
}

// MARK: - Travel Mode

enum TravelMode: String, CaseIterable, Codable, Identifiable {
    case walking
    case cycling
    case motorcycle
    case driving
    case train
    case flight

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .walking:    return L("travel.walking")
        case .cycling:    return L("travel.cycling")
        case .motorcycle: return L("travel.motorcycle")
        case .driving:    return L("travel.driving")
        case .train:      return L("travel.train")
        case .flight:     return L("travel.flight")
        }
    }

    var icon: String {
        switch self {
        case .walking:    return "figure.walk"
        case .cycling:    return "bicycle"
        case .motorcycle: return "scooter"
        case .driving:    return "car.fill"
        case .train:      return "tram.fill"
        case .flight:     return "airplane"
        }
    }

    var defaultSpeed: SpeedProfile {
        switch self {
        case .walking:    return SpeedProfile(min: 2, cruise: 4.5, max: 6, acceleration: 0.5, deceleration: 0.8)
        case .cycling:    return SpeedProfile(min: 5, cruise: 18, max: 30, acceleration: 1.5, deceleration: 2.0)
        case .motorcycle: return SpeedProfile(min: 10, cruise: 40, max: 80, acceleration: 4.0, deceleration: 5.0)
        case .driving:    return SpeedProfile(min: 5, cruise: 45, max: 120, acceleration: 3.0, deceleration: 4.0)
        case .train:      return SpeedProfile(min: 0, cruise: 80, max: 160, acceleration: 1.0, deceleration: 1.5)
        case .flight:     return SpeedProfile(min: 0, cruise: 850, max: 950, acceleration: 5.0, deceleration: 3.0)
        }
    }
}

// MARK: - Speed Profile

struct SpeedProfile: Codable, Equatable {
    var min: Double       // km/h
    var cruise: Double    // km/h
    var max: Double       // km/h
    var acceleration: Double  // km/h mỗi giây
    var deceleration: Double  // km/h mỗi giây
    var randomVariation: Double = 0.08 // phần trăm dao động

    /// Tốc độ tại thời điểm t dựa trên trạng thái motion.
    func speed(at phase: MotionPhase, progress: Double) -> Double {
        switch phase {
        case .accelerating:
            return min + (cruise - min) * ease(progress)
        case .cruising:
            let variation = cruise * randomVariation
            return cruise + Double.random(in: -variation...variation)
        case .decelerating:
            return cruise * (1.0 - ease(progress))
        case .stopped:
            return 0
        }
    }

    private func ease(_ t: Double) -> Double {
        // Smooth ease-in-out
        t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
    }
}

enum MotionPhase: String, Codable {
    case accelerating
    case cruising
    case decelerating
    case stopped

    var displayName: String {
        switch self {
        case .accelerating: return L("motion.accelerating")
        case .cruising:     return L("motion.cruising")
        case .decelerating: return L("motion.decelerating")
        case .stopped:      return L("motion.stopped")
        }
    }
}

// MARK: - GPS Noise Configuration

struct GPSNoiseConfig: Codable, Equatable {
    var enabled: Bool = true
    var radiusMeters: Double = 3.0
    var drift: Bool = true
    var inertia: Double = 0.82

    static let off = GPSNoiseConfig(enabled: false, radiusMeters: 0)
    static let light = GPSNoiseConfig(radiusMeters: 1.0)
    static let normal = GPSNoiseConfig(radiusMeters: 3.0)
    static let heavy = GPSNoiseConfig(radiusMeters: 10.0)

    /// Computed chứ không phải `static let`: nhãn preset đã bản địa hoá nên phải tính lại
    /// mỗi lần đọc, nếu không thì đổi ngôn ngữ trong app sẽ vẫn hiện nhãn cũ.
    static var presets: [(String, GPSNoiseConfig)] {
        [
            (L("common.off"), .off),
            ("1m", GPSNoiseConfig(radiusMeters: 1.0)),
            ("3m", .normal),
            ("5m", GPSNoiseConfig(radiusMeters: 5.0)),
            ("10m", .heavy),
            ("20m", GPSNoiseConfig(radiusMeters: 20.0)),
        ]
    }
}

// MARK: - Simulation Telemetry

struct SimulationTelemetry: Equatable {
    var coordinate: CLLocationCoordinate2D = .init(latitude: 0, longitude: 0)
    var speedKmh: Double = 0
    var headingDegrees: Double = 0
    var altitudeMeters: Double = 0
    var distanceTravelledMeters: Double = 0
    var distanceRemainingMeters: Double = 0
    var elapsedTime: TimeInterval = 0
    var estimatedArrival: Date? = nil
    var routeProgress: Double = 0  // 0.0 - 1.0
    var motionPhase: MotionPhase = .stopped
    var updateRate: Double = 0  // Hz

    var cardinalDirection: String {
        // Cung mot bang chu voi HeadingEngine — truoc day mot ben ra "NE" con ben kia
        // ra "ĐB", nen cung mot huong hien hai kieu o hai man hinh khac nhau.
        let directions = [L("cardinal.n"), L("cardinal.ne"), L("cardinal.e"), L("cardinal.se"),
                          L("cardinal.s"), L("cardinal.sw"), L("cardinal.w"), L("cardinal.nw")]
        let index = Int((headingDegrees + 22.5).truncatingRemainder(dividingBy: 360) / 45)
        return directions[max(0, min(index, 7))]
    }

    var formattedSpeed: String {
        String(format: "%.1f km/h", speedKmh)
    }

    var formattedHeading: String {
        String(format: "%.0f° %@", headingDegrees, cardinalDirection)
    }

    static func == (lhs: SimulationTelemetry, rhs: SimulationTelemetry) -> Bool {
        lhs.coordinate.latitude == rhs.coordinate.latitude &&
        lhs.coordinate.longitude == rhs.coordinate.longitude &&
        lhs.speedKmh == rhs.speedKmh &&
        lhs.headingDegrees == rhs.headingDegrees
    }
}

// MARK: - Device State

enum DeviceConnectionState: Equatable {
    case disconnected
    case connecting
    case connected(transport: String)
    case error(String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var displayName: String {
        switch self {
        case .disconnected: return L("device.disconnected")
        case .connecting:   return L("device.connecting")
        case .connected(let t): return L("device.connected_transport", t)
        case .error(let e): return L("common.error_detail", e)
        }
    }

    var icon: String {
        switch self {
        case .disconnected: return "iphone.slash"
        case .connecting:   return "iphone.radiowaves.left.and.right"
        case .connected:    return "iphone"
        // "exclamationmark.iphone" khong ton tai trong SF Symbols - Xcode bao "No symbol
        // named 'exclamationmark.iphone' found in system symbol set" luc runtime.
        case .error:        return "exclamationmark.triangle.fill"
        }
    }

    var color: String {
        switch self {
        case .disconnected: return "secondary"
        case .connecting:   return "orange"
        case .connected:    return "green"
        case .error:        return "red"
        }
    }
}

// MARK: - System Health

struct SystemHealth {
    enum Status: String {
        // `rawValue` la khoa on dinh, KHONG phai chuoi hien thi — truoc day man Chan
        // doan hien thang rawValue, nen chon English van ra chu tieng Viet.
        case healthy
        case warning
        case error
        case unknown

        var icon: String {
            switch self {
            case .healthy: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .error:   return "xmark.circle.fill"
            case .unknown: return "questionmark.circle"
            }
        }

        /// Nhãn hiển thị đã bản địa hoá. `rawValue` giữ nguyên vì nó là khoá định danh,
        /// chỗ nào đang hiện `rawValue` ra màn hình thì đổi sang `displayName`.
        var displayName: String {
            switch self {
            case .healthy: return L("diagnostics.status.healthy")
            case .warning: return L("diagnostics.status.warning")
            case .error:   return L("diagnostics.status.error")
            case .unknown: return L("diagnostics.status.unknown")
            }
        }
    }

    var device: Status = .unknown
    var transport: Status = .unknown
    var simulation: Status = .unknown
    var background: Status = .unknown
    var routing: Status = .unknown
    var liveActivity: Status = .unknown

    var overall: Status {
        let all = [device, transport, simulation, background, routing, liveActivity]
        if all.contains(.error) { return .error }
        if all.contains(.warning) { return .warning }
        if all.allSatisfy({ $0 == .healthy }) { return .healthy }
        return .unknown
    }
}
