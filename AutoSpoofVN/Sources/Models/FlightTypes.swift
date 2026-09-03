import CoreLocation
import Foundation

/// Giai đoạn chuyến bay — accessible từ cả FlightManager và FlightHUDView.
/// Nếu FlightManager đã define FlightPhase, file này là alias/extension.
/// Nếu chưa, đây là canonical definition.
///
/// FlightManager.swift hiện tại define FlightPhase inline.
/// File này thêm conformance và helper methods.

// Extension cho existing types nếu cần
extension Airport {
    /// Khoảng cách giữa hai sân bay.
    func distance(to other: Airport) -> Double {
        MotionEngine.haversineDistanceSync(from: coordinate.clCoordinate, to: other.coordinate.clCoordinate)
    }
}

/// Destination du lịch — tách từ FlightManager.
/// Giữ backward compatible với WorldDestination đã có trong FlightManager.
struct DestinationInfo: Identifiable, Codable {
    let id: UUID
    var name: String
    var country: String
    var timezone: String
    var airport: Airport
    var hotelCoordinate: CoordinateCodable
    var spots: [SightseeingSpotInfo]
    var stayDays: Int

    init(name: String, country: String, timezone: String, airport: Airport,
         hotel: CLLocationCoordinate2D, spots: [SightseeingSpotInfo], stayDays: Int = 2) {
        self.id = UUID()
        self.name = name
        self.country = country
        self.timezone = timezone
        self.airport = airport
        self.hotelCoordinate = CoordinateCodable(hotel)
        self.spots = spots
        self.stayDays = stayDays
    }
}

struct SightseeingSpotInfo: Identifiable, Codable {
    let id: UUID
    var name: String
    var category: String
    var coordinate: CoordinateCodable
    var dwellMinutes: Int

    init(name: String, category: String, coordinate: CLLocationCoordinate2D, dwellMinutes: Int = 60) {
        self.id = UUID()
        self.name = name
        self.category = category
        self.coordinate = CoordinateCodable(coordinate)
        self.dwellMinutes = dwellMinutes
    }
}
