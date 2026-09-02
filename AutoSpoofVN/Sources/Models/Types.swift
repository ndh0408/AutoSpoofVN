import Foundation
import CoreLocation

/// Chế độ hoạt động của lịch trình tự nhiên
enum RoutineState: String, CaseIterable, Identifiable {
    case working = "Đang làm việc"
    case moving = "Đang di chuyển"
    case resting = "Nghỉ trưa / Cà phê"
    case sleeping = "Đang ngủ (Cố định)"
    case wandering = "Đi dạo tự do"

    var id: String { self.rawValue }

    var icon: String {
        switch self {
        case .working: return "briefcase.fill"
        case .moving: return "car.fill"
        case .resting: return "cup.and.saucer.fill"
        case .sleeping: return "bed.double.fill"
        case .wandering: return "figure.walk"
        }
    }
}

/// Địa điểm yêu thích / Điểm dừng
struct PlaceBookmark: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var latitude: Double
    var longitude: Double
    var dwellMinutes: Int = 30
}

/// Tuyến đường di chuyển
struct RoutePlan: Identifiable {
    var id: UUID = UUID()
    var name: String
    var waypoints: [CLLocationCoordinate2D]
    var speedKmh: Double
    var autoLoop: Bool
}
