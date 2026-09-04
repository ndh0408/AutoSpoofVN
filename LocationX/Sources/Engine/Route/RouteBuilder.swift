import CoreLocation
import Foundation
import MapKit

extension TravelMode {
    /// Loại phương tiện tương ứng của MKDirections.
    ///
    /// MKDirections chỉ hiểu ba loại. Xe đạp bám đường đi bộ sát hơn đường ô tô (được vào
    /// đường một chiều, ngõ nhỏ), còn xe máy/tàu thì đi theo mạng đường ô tô.
    var directionsTransportType: MKDirectionsTransportType {
        switch self {
        case .walking, .cycling: return .walking
        case .motorcycle, .driving, .train, .flight: return .automobile
        }
    }
}

/// Dựng hình học tuyến đường qua **tất cả** waypoint.
///
/// Bản trước chỉ giải `waypoints.first -> waypoints.last` và **âm thầm vứt bỏ mọi điểm ở
/// giữa**, dù giao diện khuyến khích người dùng thêm chúng (chạm bản đồ, tìm địa điểm, và
/// còn vẽ chấm màu riêng cho điểm giữa). Người dùng mất dữ liệu mà không có cảnh báo nào.
enum RouteBuilder {

    struct BuildResult {
        let geometry: [CLLocationCoordinate2D]
        let distanceMeters: CLLocationDistance
        let durationSeconds: TimeInterval
        /// Số chặng phải rơi về nội suy đường thẳng vì MKDirections không trả được tuyến.
        let fallbackLegCount: Int
        let legCount: Int
        let errorDescription: String?

        var usedFallback: Bool { fallbackLegCount > 0 }

        /// Mô tả nguồn tuyến cho giao diện.
        var sourceDescription: String {
            if legCount == 0 { return "—" }
            if fallbackLegCount == 0 { return "MKDirections" }
            if fallbackLegCount == legCount { return L("route.source.fallback") }
            return L("route.source.partial_fallback", fallbackLegCount, legCount)
        }

        static let empty = BuildResult(geometry: [], distanceMeters: 0, durationSeconds: 0,
                                       fallbackLegCount: 0, legCount: 0, errorDescription: nil)
    }

    /// Giải tuyến theo từng chặng liên tiếp rồi nối lại.
    ///
    /// - Parameter spacingMeters: khoảng cách lấy mẫu. Nhỏ thì mượt nhưng nhiều điểm hơn.
    static func build(waypoints: [RouteWaypoint],
                      travelMode: TravelMode,
                      spacingMeters: CLLocationDistance = 25) async -> BuildResult {
        let coordinates = waypoints.map { $0.coordinate.clCoordinate }
            .filter { CLLocationCoordinate2DIsValid($0) }
        guard coordinates.count >= 2 else { return .empty }

        let transport = travelMode.directionsTransportType
        let cruise = travelMode.defaultSpeed.cruise

        var geometry: [CLLocationCoordinate2D] = []
        var totalDistance: CLLocationDistance = 0
        var totalDuration: TimeInterval = 0
        var fallbackLegs = 0
        var firstError: String?

        for index in 0..<(coordinates.count - 1) {
            let result = await RouteProvider.shared.resolveRoute(
                named: L("route.leg", index + 1),
                from: coordinates[index],
                to: coordinates[index + 1],
                transportType: transport,
                speedKmh: cruise,
                sampleSpacingMeters: spacingMeters
            )

            if result.usedFallback { fallbackLegs += 1 }
            if firstError == nil { firstError = result.errorDescription }

            totalDistance += result.distanceMeters
            totalDuration += result.expectedTravelTime
                ?? (result.distanceMeters / max(1, cruise / 3.6))

            let legCoordinates = result.plan.waypoints.map(\.clCoordinate)
            if geometry.isEmpty {
                geometry.append(contentsOf: legCoordinates)
            } else {
                // Bỏ điểm đầu của chặng sau: nó trùng điểm cuối của chặng trước.
                geometry.append(contentsOf: legCoordinates.dropFirst())
            }
        }

        return BuildResult(
            geometry: geometry,
            distanceMeters: totalDistance,
            durationSeconds: totalDuration,
            fallbackLegCount: fallbackLegs,
            legCount: coordinates.count - 1,
            errorDescription: firstError
        )
    }
}
