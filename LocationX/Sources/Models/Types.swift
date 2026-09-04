import Foundation
import CoreLocation

/// Che do hoat dong cua lich trinh tu nhien theo nhip sinh hoat va du lich the gioi
enum RoutineState: String, CaseIterable, Identifiable, Codable {
    case working = "Đang làm việc"
    case moving = "Đang di chuyển"
    case resting = "Nghỉ ngơi / Cà phê"
    case sleeping = "Đang ngủ (Cố định)"
    case wandering = "Đi dạo tự do"
    case commutingAirport = "Ra sân bay / Về khách sạn"
    case airportDwell = "Tại sân bay (Check-in/Chờ bay)"
    case flying = "Đang bay trên không"
    case sightseeing = "Tham quan danh lam thắng cảnh"
    case dining = "Ẩm thực / Nhà hàng"
    case hotel = "Nghỉ ngơi Khách sạn"

    var id: String { self.rawValue }

    /// Nhan hien thi da ban dia hoa. `rawValue` giu nguyen vi no la khoa Codable/Identifiable;
    /// cho nao dang hien `rawValue` ra man hinh thi doi sang `displayName`.
    var displayName: String {
        switch self {
        case .working: return L("routine.state.working")
        case .moving: return L("routine.state.moving")
        case .resting: return L("routine.state.resting")
        case .sleeping: return L("routine.state.sleeping")
        case .wandering: return L("routine.state.wandering")
        case .commutingAirport: return L("routine.state.commuting_airport")
        case .airportDwell: return L("routine.state.airport_dwell")
        case .flying: return L("routine.state.flying")
        case .sightseeing: return L("routine.state.sightseeing")
        case .dining: return L("routine.state.dining")
        case .hotel: return L("routine.state.hotel")
        }
    }

    var icon: String {
        switch self {
        case .working: return "briefcase.fill"
        case .moving: return "car.fill"
        case .resting: return "cup.and.saucer.fill"
        case .sleeping: return "bed.double.fill"
        case .wandering: return "figure.walk"
        case .commutingAirport: return "car.side.fill"
        case .airportDwell: return "person.and.arrow.left.and.arrow.right"
        case .flying: return "airplane"
        case .sightseeing: return "camera.fill"
        case .dining: return "fork.knife"
        case .hotel: return "building.fill"
        }
    }

    var defaultSpeedKmh: Double {
        switch self {
        case .working, .sleeping, .hotel: return 0.0
        case .moving, .commutingAirport: return 35.0
        case .resting, .dining: return 0.0
        case .wandering: return 3.8
        case .airportDwell: return 2.5
        case .flying: return 780.0
        case .sightseeing: return 4.5
        }
    }
}

/// Cau truc toa do ho tro luu tru Codable va phep tinh cau tron
public struct CoordinateCodable: Codable, Equatable, Hashable {
    public var latitude: Double
    public var longitude: Double

    public var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    public init(_ coord: CLLocationCoordinate2D) {
        self.latitude = coord.latitude
        self.longitude = coord.longitude
    }
}

/// Dia diem yeu thich / Diem dung
struct PlaceBookmark: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var coordinate: CoordinateCodable
    var dwellMinutes: Int = 30

    init(id: UUID = UUID(), name: String, latitude: Double, longitude: Double, dwellMinutes: Int = 30) {
        self.id = id
        self.name = name
        self.coordinate = CoordinateCodable(latitude: latitude, longitude: longitude)
        self.dwellMinutes = dwellMinutes
    }
}

/// San bay quoc te
struct Airport: Identifiable, Codable, Hashable {
    var id: String { code }
    var code: String
    var name: String
    var city: String
    var country: String
    var coordinate: CoordinateCodable

    init(code: String, name: String, city: String, country: String, latitude: Double, longitude: Double) {
        self.code = code
        self.name = name
        self.city = city
        self.country = country
        self.coordinate = CoordinateCodable(latitude: latitude, longitude: longitude)
    }
}

/// Diem tham quan du lich
struct SightseeingSpot: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var category: String
    var coordinate: CoordinateCodable
    var dwellMinutes: Int = 60

    init(id: UUID = UUID(), name: String, category: String, latitude: Double, longitude: Double, dwellMinutes: Int = 60) {
        self.id = id
        self.name = name
        self.category = category
        self.coordinate = CoordinateCodable(latitude: latitude, longitude: longitude)
        self.dwellMinutes = dwellMinutes
    }
}

/// Diem den du lich the gioi (Thanh pho, Khach san, Danh sach diem tham quan)
struct WorldDestination: Identifiable, Codable, Hashable {
    var id: String { name }
    var name: String
    var country: String
    var timeZoneOffsetHours: Double
    var airport: Airport
    var hotelName: String
    var hotelCoordinate: CoordinateCodable
    var spots: [SightseeingSpot]
    var stayDays: Int = 3
}

/// Trang thai chuyen bay mo phong
enum FlightPhase: String, Codable {
    case taxiToAirport = "Di chuyển ra sân bay"
    case airportCheckin = "Thủ tục tại sân bay & Chờ cất cánh"
    case scheduled = "Chuẩn bị cất cánh"
    case taxi = "Lăn bánh ra đường băng"
    case takeoff = "Cất cánh & Leo cao"
    case cruising = "Bay hành trình (Cruising)"
    case descent = "Hạ độ cao & Tiếp cận sân bay"
    case landed = "Đã hạ cánh an toàn"
    case taxiToHotel = "Di chuyển về khách sạn nhận phòng"

    /// Nhan hien thi da ban dia hoa. `rawValue` giu nguyen vi no la khoa Codable;
    /// cho nao dang hien `rawValue` ra man hinh thi doi sang `displayName`.
    var displayName: String {
        switch self {
        case .taxiToAirport: return L("flight.phase.taxi_to_airport")
        case .airportCheckin: return L("flight.phase.airport_checkin")
        case .scheduled: return L("flight.phase.scheduled")
        case .taxi: return L("flight.phase.taxi")
        case .takeoff: return L("flight.phase.takeoff")
        case .cruising: return L("flight.phase.cruising")
        case .descent: return L("flight.phase.descent")
        case .landed: return L("flight.phase.landed")
        case .taxiToHotel: return L("flight.phase.taxi_to_hotel")
        }
    }
}

/// Chuyen bay mo phong
struct FlightSimulation: Identifiable, Codable {
    var id: UUID = UUID()
    var flightNumber: String
    var origin: Airport
    var destination: Airport
    var cruisingSpeedKmh: Double
    var currentSpeedKmh: Double
    var phase: FlightPhase
    var progressFraction: Double
    var totalDistanceKm: Double
    var remainingDistanceKm: Double
    var estimatedMinutesRemaining: Double
    var altitudeMeters: Double
}

/// Tuyen duong di chuyen dinh san
struct RoutePlan: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var waypoints: [CoordinateCodable]
    var speedKmh: Double
    var autoLoop: Bool

    init(id: UUID = UUID(), name: String, waypoints: [CoordinateCodable] = [], speedKmh: Double = 25.0, autoLoop: Bool = false) {
        self.id = id
        self.name = name
        self.waypoints = waypoints
        self.speedKmh = speedKmh
        self.autoLoop = autoLoop
    }
}

/// Tien ich tinh toan cau tron dai cung (Great-Circle Slerp)
enum GeodesicMath {
    static let earthRadiusKm: Double = 6371.0

    static func distanceKm(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let lat1 = from.latitude * .pi / 180.0
        let lon1 = from.longitude * .pi / 180.0
        let lat2 = to.latitude * .pi / 180.0
        let lon2 = to.longitude * .pi / 180.0

        let dlat = lat2 - lat1
        let dlon = lon2 - lon1

        let a = sin(dlat / 2) * sin(dlat / 2) + cos(lat1) * cos(lat2) * sin(dlon / 2) * sin(dlon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadiusKm * c
    }

    static func interpolateGreatCircle(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, fraction: Double) -> CLLocationCoordinate2D {
        if fraction <= 0 { return from }
        if fraction >= 1 { return to }

        let lat1 = from.latitude * .pi / 180.0
        let lon1 = from.longitude * .pi / 180.0
        let lat2 = to.latitude * .pi / 180.0
        let lon2 = to.longitude * .pi / 180.0

        let d = 2 * asin(sqrt(pow(sin((lat1 - lat2) / 2), 2) + cos(lat1) * cos(lat2) * pow(sin((lon1 - lon2) / 2), 2)))
        if d == 0 { return from }

        let a = sin((1 - fraction) * d) / sin(d)
        let b = sin(fraction * d) / sin(d)

        let x = a * cos(lat1) * cos(lon1) + b * cos(lat2) * cos(lon2)
        let y = a * cos(lat1) * sin(lon1) + b * cos(lat2) * sin(lon2)
        let z = a * sin(lat1) + b * sin(lat2)

        let latInterp = atan2(z, sqrt(x * x + y * y))
        let lonInterp = atan2(y, x)

        return CLLocationCoordinate2D(
            latitude: latInterp * 180.0 / .pi,
            longitude: lonInterp * 180.0 / .pi
        )
    }
}
