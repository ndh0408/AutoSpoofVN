import CoreLocation
import MapKit
import XCTest
@testable import LocationX

/// Kiem thu tang tuyen duong: mo hinh luu tru, tinh quang duong cong don, va phep
/// chieu hinh dang tuyen len khung ve.
final class RouteLayerTests: XCTestCase {

    // MARK: - Quang duong cong don

    @MainActor
    func testCumulativeDistancesAreMonotonicAndStartAtZero() {
        let coords = [
            CLLocationCoordinate2D(latitude: 21.0000, longitude: 105.0000),
            CLLocationCoordinate2D(latitude: 21.0100, longitude: 105.0000),
            CLLocationCoordinate2D(latitude: 21.0200, longitude: 105.0000),
            CLLocationCoordinate2D(latitude: 21.0300, longitude: 105.0000),
        ]
        let cumulative = RouteSimulator.cumulativeDistances(of: coords)

        XCTAssertEqual(cumulative.count, coords.count)
        XCTAssertEqual(cumulative[0], 0, accuracy: 0.0001)
        for i in 1..<cumulative.count {
            XCTAssertGreaterThan(cumulative[i], cumulative[i - 1], "phai tang dan")
        }
        // 0.03 do vi do ~ 3.34 km
        XCTAssertEqual(cumulative.last!, 3_336, accuracy: 60)
    }

    @MainActor
    func testCumulativeDistancesHandlesDegenerateInput() {
        XCTAssertEqual(RouteSimulator.cumulativeDistances(of: []), [0])
        let single = [CLLocationCoordinate2D(latitude: 1, longitude: 1)]
        XCTAssertEqual(RouteSimulator.cumulativeDistances(of: single), [0])
    }

    /// Tong cong don phai bang tong tung chang cong lai — day la bat bien ma vong lap
    /// mo phong dua vao de tinh "con lai".
    @MainActor
    func testCumulativeMatchesSumOfLegs() {
        let coords = (0..<25).map { i in
            CLLocationCoordinate2D(latitude: 21.0 + Double(i) * 0.002,
                                   longitude: 105.8 + Double(i) * 0.003)
        }
        let cumulative = RouteSimulator.cumulativeDistances(of: coords)
        var manual: Double = 0
        for i in 1..<coords.count {
            manual += MotionEngine.haversineDistance(from: coords[i - 1], to: coords[i])
        }
        XCTAssertEqual(cumulative.last!, manual, accuracy: 0.001)
    }

    // MARK: - SavedRoute

    func testRunnableCoordinatesPrefersGeometry() {
        let waypoints = [
            RouteWaypoint(coordinate: CLLocationCoordinate2D(latitude: 21, longitude: 105)),
            RouteWaypoint(coordinate: CLLocationCoordinate2D(latitude: 22, longitude: 106)),
        ]
        let geometry = (0..<10).map { i in
            CoordinateCodable(latitude: 21 + Double(i) * 0.1, longitude: 105 + Double(i) * 0.1)
        }
        let route = SavedRoute(name: "T", waypoints: waypoints, travelMode: .driving,
                               geometry: geometry, totalDistanceMeters: 1234,
                               estimatedDurationSeconds: 600)
        XCTAssertEqual(route.runnableCoordinates.count, 10, "phai dung hinh hoc da tinh")
        XCTAssertEqual(route.totalDistanceMeters, 1234)
    }

    /// Tuyen cu (chua co hinh hoc) van chay duoc bang cach noi thang cac waypoint,
    /// thay vi khong chay duoc gi.
    func testRunnableCoordinatesFallsBackToWaypoints() {
        let route = SavedRoute(name: "Cu", waypoints: [
            RouteWaypoint(coordinate: CLLocationCoordinate2D(latitude: 21, longitude: 105)),
            RouteWaypoint(coordinate: CLLocationCoordinate2D(latitude: 22, longitude: 106)),
        ])
        XCTAssertNil(route.routeGeometry)
        XCTAssertEqual(route.runnableCoordinates.count, 2)
    }

    func testEffectiveCruiseSpeedFallsBackToTravelMode() {
        var route = SavedRoute(name: "T", waypoints: [], travelMode: .walking)
        XCTAssertEqual(route.effectiveCruiseSpeedKmh, TravelMode.walking.defaultSpeed.cruise)
        route.cruiseSpeedKmh = 3.0
        XCTAssertEqual(route.effectiveCruiseSpeedKmh, 3.0)
    }

    /// File `routes.json` cu KHONG co khoa `lastUsedAt`/`cruiseSpeedKmh`. Neu them truong
    /// khong-optional thi toan bo tuyen da luu cua nguoi dung se khong giai ma duoc nua.
    func testSavedRouteDecodesLegacyJSONWithoutNewFields() throws {
        let legacy = """
        {
          "id": "3F2504E0-4F89-11D3-9A0C-0305E82C3301",
          "name": "Tuyến cũ",
          "createdAt": 700000000,
          "updatedAt": 700000000,
          "waypoints": [],
          "travelMode": "driving",
          "totalDistanceMeters": 0,
          "estimatedDurationSeconds": 0
        }
        """
        let route = try JSONDecoder().decode(SavedRoute.self, from: Data(legacy.utf8))
        XCTAssertEqual(route.name, "Tuyến cũ")
        XCTAssertNil(route.lastUsedAt)
        XCTAssertNil(route.cruiseSpeedKmh)
        XCTAssertEqual(route.effectiveCruiseSpeedKmh, TravelMode.driving.defaultSpeed.cruise)
    }

    func testSavedRouteRoundTripsThroughCodable() throws {
        let original = SavedRoute(
            name: "Hà Nội → Hải Phòng",
            waypoints: [RouteWaypoint(coordinate: CLLocationCoordinate2D(latitude: 21, longitude: 105))],
            travelMode: .motorcycle,
            geometry: [CoordinateCodable(latitude: 21, longitude: 105),
                       CoordinateCodable(latitude: 20.86, longitude: 106.68)],
            totalDistanceMeters: 102_000,
            estimatedDurationSeconds: 7_200,
            cruiseSpeedKmh: 51
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SavedRoute.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.travelMode, .motorcycle)
        XCTAssertEqual(decoded.routeGeometry?.count, 2)
        XCTAssertEqual(decoded.totalDistanceMeters, 102_000)
        XCTAssertEqual(decoded.cruiseSpeedKmh, 51)
    }

    // MARK: - Anh xa phuong tien

    func testTravelModeDirectionsMapping() {
        XCTAssertEqual(TravelMode.walking.directionsTransportType, .walking)
        XCTAssertEqual(TravelMode.cycling.directionsTransportType, .walking)
        XCTAssertEqual(TravelMode.driving.directionsTransportType, .automobile)
        XCTAssertEqual(TravelMode.motorcycle.directionsTransportType, .automobile)
        XCTAssertEqual(TravelMode.train.directionsTransportType, .automobile)
    }

    // MARK: - Chieu hinh dang tuyen

    func testNormalizedPointsStayInsideCanvas() {
        let coords = (0..<50).map { i in
            CLLocationCoordinate2D(latitude: 21.0 + sin(Double(i) / 6) * 0.02,
                                   longitude: 105.8 + Double(i) * 0.004)
        }
        let size = CGSize(width: 200, height: 120)
        let inset: CGFloat = 8
        let points = RouteShapePreview.normalizedPoints(coords, in: size, inset: inset)

        XCTAssertEqual(points.count, coords.count)
        for p in points {
            XCTAssertGreaterThanOrEqual(p.x, inset - 0.01)
            XCTAssertLessThanOrEqual(p.x, size.width - inset + 0.01)
            XCTAssertGreaterThanOrEqual(p.y, inset - 0.01)
            XCTAssertLessThanOrEqual(p.y, size.height - inset + 0.01)
        }
    }

    /// Vi do cang lon thi cang len phia BAC, ma truc y man hinh tang xuong duoi.
    func testNormalizedPointsFlipLatitudeAxis() {
        let south = CLLocationCoordinate2D(latitude: 21.00, longitude: 105.0)
        let north = CLLocationCoordinate2D(latitude: 21.10, longitude: 105.0)
        let points = RouteShapePreview.normalizedPoints([south, north],
                                                        in: CGSize(width: 100, height: 100),
                                                        inset: 5)
        XCTAssertEqual(points.count, 2)
        XCTAssertGreaterThan(points[0].y, points[1].y, "diem phia nam phai nam thap hon tren man hinh")
    }

    func testNormalizedPointsRejectsDegenerateInput() {
        XCTAssertTrue(RouteShapePreview.normalizedPoints([], in: CGSize(width: 100, height: 100), inset: 4).isEmpty)
        let one = [CLLocationCoordinate2D(latitude: 1, longitude: 1)]
        XCTAssertTrue(RouteShapePreview.normalizedPoints(one, in: CGSize(width: 100, height: 100), inset: 4).isEmpty)
        // Khung nho hon le hai ben => khong ve duoc
        let two = [CLLocationCoordinate2D(latitude: 1, longitude: 1),
                   CLLocationCoordinate2D(latitude: 2, longitude: 2)]
        XCTAssertTrue(RouteShapePreview.normalizedPoints(two, in: CGSize(width: 6, height: 6), inset: 4).isEmpty)
    }

    /// Tuyen thuan dong-tay va thuan bac-nam cung do dai goc phai ra hinh khong bi meo:
    /// mot he so ti le duy nhat cho ca hai truc.
    func testNormalizedPointsPreserveAspect() {
        let horizontal = [CLLocationCoordinate2D(latitude: 0, longitude: 0),
                          CLLocationCoordinate2D(latitude: 0, longitude: 1)]
        let size = CGSize(width: 200, height: 100)
        let points = RouteShapePreview.normalizedPoints(horizontal, in: size, inset: 0)
        XCTAssertEqual(points.count, 2)
        // Tuyen ngang thuan tuy => y hai diem bang nhau, chiem het be ngang.
        XCTAssertEqual(points[0].y, points[1].y, accuracy: 0.001)
        XCTAssertEqual(abs(points[1].x - points[0].x), size.width, accuracy: 0.5)
    }

    // MARK: - Vung ban do bao tuyen

    @MainActor
    func testRegionFittingCoversAllCoordinates() {
        let coords = [
            CLLocationCoordinate2D(latitude: 21.00, longitude: 105.80),
            CLLocationCoordinate2D(latitude: 21.05, longitude: 105.90),
            CLLocationCoordinate2D(latitude: 20.98, longitude: 105.85),
        ]
        let region = RouteSnapshotCache.region(fitting: coords)

        let minLat = region.center.latitude - region.span.latitudeDelta / 2
        let maxLat = region.center.latitude + region.span.latitudeDelta / 2
        let minLon = region.center.longitude - region.span.longitudeDelta / 2
        let maxLon = region.center.longitude + region.span.longitudeDelta / 2

        for c in coords {
            XCTAssertTrue((minLat...maxLat).contains(c.latitude), "vi do \(c.latitude) ngoai vung")
            XCTAssertTrue((minLon...maxLon).contains(c.longitude), "kinh do \(c.longitude) ngoai vung")
        }
    }

    /// Hai diem trung nhau van phai cho ra mot vung nhin duoc, khong phai span = 0.
    @MainActor
    func testRegionFittingHasMinimumSpan() {
        let same = CLLocationCoordinate2D(latitude: 21, longitude: 105)
        let region = RouteSnapshotCache.region(fitting: [same, same])
        XCTAssertGreaterThan(region.span.latitudeDelta, 0)
        XCTAssertGreaterThan(region.span.longitudeDelta, 0)
    }
}
