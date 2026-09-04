import CoreLocation
import XCTest
@testable import LocationX

final class SimulationTests: XCTestCase {

    // MARK: - Coordinate Math

    func testHaversineDistance() async {
        let hanoi = CLLocationCoordinate2D(latitude: 21.0285, longitude: 105.8542)
        let hcm = CLLocationCoordinate2D(latitude: 10.8231, longitude: 106.6297)
        let distance = await MotionEngine.haversineDistance(from: hanoi, to: hcm)
        // HN-HCM ~1140km
        XCTAssertGreaterThan(distance, 1_100_000)
        XCTAssertLessThan(distance, 1_200_000)
    }

    func testHaversineZeroDistance() async {
        let coord = CLLocationCoordinate2D(latitude: 21.0285, longitude: 105.8542)
        let distance = await MotionEngine.haversineDistance(from: coord, to: coord)
        XCTAssertEqual(distance, 0, accuracy: 0.001)
    }

    func testBearing() async {
        let a = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let b = CLLocationCoordinate2D(latitude: 1, longitude: 0) // due north
        let bearing = await MotionEngine.bearing(from: a, to: b)
        XCTAssertEqual(bearing, 0, accuracy: 1)
    }

    func testBearingEast() async {
        let a = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let b = CLLocationCoordinate2D(latitude: 0, longitude: 1) // due east
        let bearing = await MotionEngine.bearing(from: a, to: b)
        XCTAssertEqual(bearing, 90, accuracy: 1)
    }

    func testMoveCoordinate() async {
        let start = CLLocationCoordinate2D(latitude: 21.0285, longitude: 105.8542)
        let moved = await MotionEngine.moveCoordinate(start, distanceMeters: 1000, bearingDegrees: 0) // north
        XCTAssertGreaterThan(moved.latitude, start.latitude)
        XCTAssertEqual(moved.longitude, start.longitude, accuracy: 0.0001)
    }

    func testSmoothHeadingNoJump() async {
        // 350° → 10° should not go through 180°.
        // Nua duong theo chieu ngan la 350 + 20*0.5 = 360, chuan hoa ve 0. So sanh
        // truc tiep voi 340 la sai: no tu choi dung ket qua dung ngay cho wraparound.
        // Phai do khoang cach GOC toi 0/360 thay vi so sanh gia tri tho.
        let result = await MotionEngine.smoothHeading(from: 350, to: 10, factor: 0.5)
        XCTAssertTrue((0..<360).contains(result), "heading phai duoc chuan hoa ve [0,360)")
        let distanceFromZero = min(result, 360 - result)
        XCTAssertLessThan(distanceFromZero, 20, "phai o gan 0/360, khong duoc vong qua 180")
    }

    func testSmoothHeadingTakesShortestArc() async {
        // 10° → 350° cung phai di nguoc chieu kim dong ho qua 0, khong qua 180.
        let result = await MotionEngine.smoothHeading(from: 10, to: 350, factor: 0.5)
        let distanceFromZero = min(result, 360 - result)
        XCTAssertLessThan(distanceFromZero, 20)

        // Truong hop khong wrap: 90° → 180° o factor 0.5 phai ra dung 135°.
        let midway = await MotionEngine.smoothHeading(from: 90, to: 180, factor: 0.5)
        XCTAssertEqual(midway, 135, accuracy: 0.001)
    }

    // MARK: - Speed Profile

    func testSpeedProfileDefaults() {
        let walking = TravelMode.walking.defaultSpeed
        XCTAssertEqual(walking.cruise, 4.5)
        XCTAssertLessThan(walking.max, 10)

        let driving = TravelMode.driving.defaultSpeed
        XCTAssertGreaterThan(driving.cruise, 30)
        XCTAssertLessThan(driving.max, 200)
    }

    func testSpeedProfileEase() {
        let profile = TravelMode.driving.defaultSpeed

        let stopped = profile.speed(at: .stopped, progress: 0)
        XCTAssertEqual(stopped, 0)

        let cruising = profile.speed(at: .cruising, progress: 0.5)
        XCTAssertGreaterThan(cruising, 30)
    }

    // MARK: - Simulation State Machine

    func testStateTransitions() {
        var state: SimulationState = .idle
        XCTAssertTrue(state.canStart)
        XCTAssertFalse(state.canPause)
        XCTAssertFalse(state.canStop)

        state = .running
        XCTAssertFalse(state.canStart)
        XCTAssertTrue(state.canPause)
        XCTAssertTrue(state.canStop)
        XCTAssertTrue(state.isActive)

        state = .paused
        XCTAssertFalse(state.canPause)
        XCTAssertTrue(state.canResume)
        XCTAssertTrue(state.canStop)
        XCTAssertTrue(state.isActive)

        state = .completed
        XCTAssertTrue(state.canStart)
        XCTAssertFalse(state.isActive)
    }

    // MARK: - Source Priority

    func testSourcePriority() {
        XCTAssertGreaterThan(SimulationSource.manual.priority, SimulationSource.flight.priority)
        XCTAssertGreaterThan(SimulationSource.flight.priority, SimulationSource.routine.priority)
        XCTAssertGreaterThan(SimulationSource.scenario.priority, SimulationSource.route.priority)
    }

    // MARK: - GPS Noise

    func testNoiseOff() {
        let config = GPSNoiseConfig.off
        XCTAssertFalse(config.enabled)
        XCTAssertEqual(config.radiusMeters, 0)
    }

    func testNoisePresets() {
        XCTAssertEqual(GPSNoiseConfig.light.radiusMeters, 1.0)
        XCTAssertEqual(GPSNoiseConfig.normal.radiusMeters, 3.0)
        XCTAssertEqual(GPSNoiseConfig.heavy.radiusMeters, 10.0)
    }

    // MARK: - Coordinate Validation

    func testCoordinateValidation() {
        let valid = CoordinateCodable(latitude: 21.0285, longitude: 105.8542)
        XCTAssertTrue((-90...90).contains(valid.latitude))
        XCTAssertTrue((-180...180).contains(valid.longitude))
    }

    func testCoordinateRoundtrip() throws {
        let original = CoordinateCodable(latitude: 21.0285, longitude: 105.8542)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CoordinateCodable.self, from: data)
        XCTAssertEqual(original.latitude, decoded.latitude, accuracy: 0.0001)
        XCTAssertEqual(original.longitude, decoded.longitude, accuracy: 0.0001)
    }

    // MARK: - Telemetry

    /// Huong la bat, chu cai la ban dich.
    ///
    /// Ban truoc so voi "N"/"E"/"S"/"W" — dung khi ham nay tra ve chu cai tieng Anh go
    /// cung, nhung dieu do co nghia la nguoi dung chon Tiếng Việt van thay "NE".
    /// Gio no di qua L(), nen test so voi chinh khoa dich: dung o CA HAI ngon ngu, va
    /// van do neu bang tra cuu bi lech chi so.
    func testCardinalDirection() {
        var tel = SimulationTelemetry()

        tel.headingDegrees = 0
        XCTAssertEqual(tel.cardinalDirection, L("cardinal.n"))

        tel.headingDegrees = 90
        XCTAssertEqual(tel.cardinalDirection, L("cardinal.e"))

        tel.headingDegrees = 180
        XCTAssertEqual(tel.cardinalDirection, L("cardinal.s"))

        tel.headingDegrees = 270
        XCTAssertEqual(tel.cardinalDirection, L("cardinal.w"))

        tel.headingDegrees = 135
        XCTAssertEqual(tel.cardinalDirection, L("cardinal.se"))

        // Tam huong phai ra tam chu khac nhau — neu khong, bang tra cuu co o trung.
        let all = Set((0..<8).map { i -> String in
            tel.headingDegrees = Double(i) * 45
            return tel.cardinalDirection
        })
        XCTAssertEqual(all.count, 8)
    }

    // MARK: - Session

    func testSessionCreation() {
        let session = SimulationSession(source: .route, travelMode: .driving)
        XCTAssertEqual(session.source, .route)
        XCTAssertEqual(session.travelMode, .driving)
        XCTAssertEqual(session.status, .idle)
        XCTAssertEqual(session.distanceTravelledMeters, 0)
    }

    // MARK: - Heading Engine

    func testHeadingEngineSmooth() {
        var engine = HeadingEngine()
        _ = engine.update(with: CLLocationCoordinate2D(latitude: 0, longitude: 0))
        let heading = engine.update(with: CLLocationCoordinate2D(latitude: 0.001, longitude: 0))
        // Moving north
        XCTAssertLessThan(abs(heading), 30) // roughly north
    }

    // MARK: - Persistence

    func testSettingsRoundtrip() throws {
        var settings = PersistenceManager.AppSettings()
        settings.noiseConfig = .heavy
        settings.defaultTravelMode = .cycling

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(PersistenceManager.AppSettings.self, from: data)
        XCTAssertEqual(decoded.noiseConfig.radiusMeters, 10.0)
        XCTAssertEqual(decoded.defaultTravelMode, .cycling)
    }

    // MARK: - Scenario Model

    func testScenarioCodable() throws {
        var scenario = Scenario(name: "Test")
        scenario.steps.append(ScenarioStep(action: .wait(seconds: 60), order: 0))
        scenario.steps.append(ScenarioStep(action: .setLocation(CoordinateCodable(latitude: 21, longitude: 105)), order: 1))

        let data = try JSONEncoder().encode(scenario)
        let decoded = try JSONDecoder().decode(Scenario.self, from: data)
        XCTAssertEqual(decoded.name, "Test")
        XCTAssertEqual(decoded.steps.count, 2)
    }

    // MARK: - Route Model

    func testSavedRouteCodable() throws {
        let wp1 = RouteWaypoint(coordinate: CLLocationCoordinate2D(latitude: 21, longitude: 105), name: "Start")
        let wp2 = RouteWaypoint(coordinate: CLLocationCoordinate2D(latitude: 21.01, longitude: 105.01), name: "End")
        let route = SavedRoute(name: "Test Route", waypoints: [wp1, wp2], travelMode: .motorcycle)

        let data = try JSONEncoder().encode(route)
        let decoded = try JSONDecoder().decode(SavedRoute.self, from: data)
        XCTAssertEqual(decoded.name, "Test Route")
        XCTAssertEqual(decoded.waypoints.count, 2)
        XCTAssertEqual(decoded.travelMode, .motorcycle)
    }

    // MARK: - Edge Cases

    func testDatelineCoordinate() async {
        let near180 = CLLocationCoordinate2D(latitude: 0, longitude: 179.999)
        let past180 = CLLocationCoordinate2D(latitude: 0, longitude: -179.999)
        let distance = await MotionEngine.haversineDistance(from: near180, to: past180)
        // Should be ~222m, not ~40000km
        XCTAssertLessThan(distance, 1000)
    }

    func testZeroDistanceRoute() {
        let coord = CLLocationCoordinate2D(latitude: 21, longitude: 105)
        let wp = RouteWaypoint(coordinate: coord)
        let route = SavedRoute(name: "Zero", waypoints: [wp, wp])
        XCTAssertEqual(route.totalDistanceMeters, 0)
    }
}
