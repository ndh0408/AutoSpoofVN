//
//  SimulationStudioTests.swift
//  AutoSpoofVNTests
//
//  Unit Tests for SimulationCoordinator, MotionEngine, Heading, Persistence, and Replay.
//

import CoreLocation
import XCTest
@testable import AutoSpoofVN

final class MotionEngineTests: XCTestCase {
    private let engine = MotionEngine.shared

    func testHeadingDueNorth() {
        let p1 = CLLocationCoordinate2D(latitude: 21.0, longitude: 105.0)
        let p2 = CLLocationCoordinate2D(latitude: 22.0, longitude: 105.0)
        let heading = engine.calculateHeadingDegrees(from: p1, to: p2)
        XCTAssertEqual(heading, 0.0, accuracy: 0.1)
        XCTAssertEqual(engine.cardinalDirection(for: heading), "N")
    }

    func testHeadingDueEast() {
        let p1 = CLLocationCoordinate2D(latitude: 21.0, longitude: 105.0)
        let p2 = CLLocationCoordinate2D(latitude: 21.0, longitude: 106.0)
        let heading = engine.calculateHeadingDegrees(from: p1, to: p2)
        XCTAssertEqual(heading, 90.0, accuracy: 1.0)
        XCTAssertEqual(engine.cardinalDirection(for: heading), "E")
    }

    func testHeadingSmoothingAvoids360Jump() {
        let smoothed = engine.smoothHeading(currentHeading: 355.0, targetHeading: 5.0, smoothingFactor: 0.5)
        XCTAssertEqual(smoothed, 0.0, accuracy: 1.0)
    }

    func testSpeedAccelerationAndDeceleration() {
        let profile = TravelMode.driving.defaultProfile
        let speed1 = engine.stepSpeed(currentSpeedKmh: 0, targetSpeedKmh: 50, profile: profile, deltaSeconds: 2.0)
        XCTAssertGreaterThan(speed1, 0)
        XCTAssertLessThanOrEqual(speed1, 50)

        let speed2 = engine.stepSpeed(currentSpeedKmh: 50, targetSpeedKmh: 0, profile: profile, deltaSeconds: 2.0)
        XCTAssertLessThan(speed2, 50)
        XCTAssertGreaterThanOrEqual(speed2, 0)
    }

    func testDeterministicSeed() {
        let m1 = MotionEngine(seed: 12345)
        let m2 = MotionEngine(seed: 12345)
        let c = CLLocationCoordinate2D(latitude: 21.0, longitude: 105.0)
        let j1 = m1.applyJitter(to: c, maxMeters: 10.0)
        let j2 = m2.applyJitter(to: c, maxMeters: 10.0)
        XCTAssertEqual(j1.latitude, j2.latitude, accuracy: 1e-9)
        XCTAssertEqual(j1.longitude, j2.longitude, accuracy: 1e-9)
    }
}

@MainActor
final class SimulationCoordinatorTests: XCTestCase {
    func testManualLocationUpdatesTransportAndState() async {
        let mock = MockDeviceTransport()
        _ = await mock.connect(host: "10.7.0.1", port: 62078, pairingData: Data([1, 2, 3]))
        let coordinator = SimulationCoordinator(transport: mock)
        let target = CLLocationCoordinate2D(latitude: 10.8231, longitude: 106.6297)

        _ = coordinator.setManualLocation(target)
        XCTAssertEqual(coordinator.currentCoordinate.latitude, target.latitude, accuracy: 1e-5)
        XCTAssertEqual(coordinator.activeSource, .manual)
        XCTAssertEqual(mock.sentCoordinates.count, 1)
        if let first = mock.sentCoordinates.first {
            XCTAssertEqual(first.latitude, target.latitude, accuracy: 1e-5)
        } else {
            XCTFail("Missing sent coordinate")
        }
    }

    func testStartRouteSimulationProgress() {
        let mock = MockDeviceTransport()
        let coordinator = SimulationCoordinator(transport: mock)
        let p1 = CLLocationCoordinate2D(latitude: 21.00, longitude: 105.00)
        let p2 = CLLocationCoordinate2D(latitude: 21.01, longitude: 105.01)

        coordinator.startRouteSimulation(name: "Test Route", waypoints: [p1, p2], travelMode: .driving)
        XCTAssertEqual(coordinator.state, .running)
        XCTAssertEqual(coordinator.activeSource, .route)
        XCTAssertNotNil(coordinator.currentSession)

        coordinator.pauseSimulation()
        XCTAssertEqual(coordinator.state, .paused)

        coordinator.resumeSimulation()
        XCTAssertEqual(coordinator.state, .running)

        coordinator.stopSimulation()
        XCTAssertEqual(coordinator.state, .completed)
    }
}

final class PersistenceAndReplayTests: XCTestCase {
    func testGPXExportAndImportRoundTrip() {
        let p1 = CoordinateCodable(latitude: 21.0285, longitude: 105.8542)
        let p2 = CoordinateCodable(latitude: 10.8231, longitude: 106.6297)
        let original = [p1, p2]

        let gpx = PersistenceManager.shared.exportToGPX(track: original, name: "Vietnam Tour")
        XCTAssertTrue(gpx.contains("<gpx"))
        XCTAssertTrue(gpx.contains("Vietnam Tour"))

        let imported = PersistenceManager.shared.importFromGPX(gpxContent: gpx)
        XCTAssertEqual(imported.count, 2)
        XCTAssertEqual(imported[0].latitude, p1.latitude, accuracy: 1e-4)
        XCTAssertEqual(imported[1].longitude, p2.longitude, accuracy: 1e-4)
    }
}
