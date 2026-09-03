import CoreLocation
import XCTest
@testable import AutoSpoofVN

final class RouteProviderTests: XCTestCase {
    private let start = CLLocationCoordinate2D(latitude: 21.0285, longitude: 105.8542)
    private let end = CLLocationCoordinate2D(latitude: 21.0335, longitude: 105.8542)

    func testStraightLineKeepsExactEndpoints() throws {
        let coordinates = RouteProvider.straightLineCoordinates(
            from: start,
            to: end,
            spacingMeters: 25
        )
        let first = try XCTUnwrap(coordinates.first)
        let last = try XCTUnwrap(coordinates.last)

        XCTAssertEqual(first.latitude, start.latitude, accuracy: 1e-9)
        XCTAssertEqual(first.longitude, start.longitude, accuracy: 1e-9)
        XCTAssertEqual(last.latitude, end.latitude, accuracy: 1e-9)
        XCTAssertEqual(last.longitude, end.longitude, accuracy: 1e-9)
    }

    func testResampleUsesNearlyEvenSpacing() {
        let coordinates = RouteProvider.resample([start, end], spacingMeters: 50)
        XCTAssertGreaterThan(coordinates.count, 5)

        let distances = zip(coordinates, coordinates.dropFirst()).map { first, second in
            CLLocation(latitude: first.latitude, longitude: first.longitude)
                .distance(from: CLLocation(latitude: second.latitude, longitude: second.longitude))
        }
        for distance in distances.dropLast() {
            XCTAssertEqual(distance, 50, accuracy: 1)
        }
        XCTAssertLessThanOrEqual(distances.last ?? 0, 50.5)
    }

    func testResampleHonorsPointLimit() throws {
        let farEnd = CLLocationCoordinate2D(latitude: 22.0285, longitude: 105.8542)
        let coordinates = RouteProvider.resample(
            [start, farEnd],
            spacingMeters: 1,
            maximumPointCount: 100
        )
        let first = try XCTUnwrap(coordinates.first)
        let last = try XCTUnwrap(coordinates.last)

        XCTAssertLessThanOrEqual(coordinates.count, 100)
        XCTAssertEqual(first.latitude, start.latitude, accuracy: 1e-9)
        XCTAssertEqual(last.latitude, farEnd.latitude, accuracy: 1e-9)
    }

    func testRoutePlanExposesEverySegmentLength() {
        let middle = CLLocationCoordinate2D(latitude: 21.0305, longitude: 105.8542)
        let plan = RoutePlan(
            name: "Test",
            waypoints: [CoordinateCodable(start), CoordinateCodable(middle), CoordinateCodable(end)],
            speedKmh: 30
        )

        XCTAssertEqual(plan.segmentDistancesMeters.count, plan.waypoints.count - 1)
        XCTAssertTrue(plan.segmentDistancesMeters.allSatisfy { $0 > 0 })
        XCTAssertEqual(plan.totalDistanceMeters, plan.segmentDistancesMeters.reduce(0, +), accuracy: 1e-9)
    }
}
