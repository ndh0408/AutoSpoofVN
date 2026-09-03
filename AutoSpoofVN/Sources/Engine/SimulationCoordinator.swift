//
//  SimulationCoordinator.swift
//  AutoSpoofVN
//
//  The Authoritative Master Coordinator & Single Source of Truth for GPS Simulation.
//

import Combine
import CoreLocation
import Foundation
import MapKit

@MainActor
public final class SimulationCoordinator: ObservableObject {
    public static let shared = SimulationCoordinator()

    // MARK: - Published State

    @Published public private(set) var activeSource: SimulationSource = .manual
    @Published public private(set) var state: SimulationState = .idle
    @Published public var currentCoordinate: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 21.0285, longitude: 105.8542)
    @Published public var timeWarpMultiplier: Double = 1.0 // 1x, 2x, 5x, 10x, 30x, 60x, 120x
    @Published public private(set) var telemetry: SimulationTelemetry = SimulationTelemetry()
    @Published public private(set) var currentSession: SimulationSession? = nil
    @Published public private(set) var recentTracks: [CLLocationCoordinate2D] = []
    @Published public var activeRouteCoordinates: [CLLocationCoordinate2D] = []

    // MARK: - Subsystems

    public let transport: DeviceTransport
    private let motionEngine = MotionEngine.shared
    private var currentProvider: RouteProviderProtocol = MapKitRouteProvider()

    private var simulationTimer: Timer?
    private var currentRouteWaypoints: [CLLocationCoordinate2D] = []
    private var currentWaypointIndex: Int = 0
    private var kinematicState: KinematicState
    private var activeProfile: SpeedProfile = TravelMode.driving.defaultProfile
    private var sessionStartTime: Date?
    private var maxSpeedRecorded: Double = 0.0
    private var totalDistanceTravelled: Double = 0.0
    private var targetSpeedKmh: Double = 0.0
    private var isSimulatingRealRoad: Bool = false

    public init(transport: DeviceTransport = DVTDeviceTransport()) {
        self.transport = transport
        self.kinematicState = KinematicState(
            coordinate: CLLocationCoordinate2D(latitude: 21.0285, longitude: 105.8542)
        )
    }

    // MARK: - Manual Location Control

    @discardableResult
    public func setManualLocation(_ coordinate: CLLocationCoordinate2D) -> Bool {
        guard acquireSource(.manual) else { return false }

        stopCurrentSimulation(state: .completed)
        self.currentCoordinate = coordinate
        self.kinematicState.coordinate = coordinate
        self.kinematicState.currentSpeedKmh = 0
        self.kinematicState.targetSpeedKmh = 0

        let sent = transport.sendLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        updateTelemetry(speed: 0, heading: kinematicState.headingDegrees, progress: 1.0)
        updateSpoofEngineMirror(coordinate: coordinate, isSimulating: true)
        return sent
    }

    // MARK: - Route Simulation Control

    public func startRouteSimulation(
        name: String,
        waypoints: [CLLocationCoordinate2D],
        travelMode: TravelMode,
        speedKmh: Double? = nil
    ) {
        guard acquireSource(.route) else { return }
        guard waypoints.count >= 2 else { return }

        stopCurrentSimulation(state: .idle)

        self.activeSource = .route
        self.state = .preparing
        self.activeRouteCoordinates = waypoints
        self.currentRouteWaypoints = waypoints
        self.currentWaypointIndex = 0
        self.activeProfile = travelMode.defaultProfile
        self.targetSpeedKmh = speedKmh ?? activeProfile.cruisingSpeedKmh
        self.sessionStartTime = Date()
        self.totalDistanceTravelled = 0
        self.maxSpeedRecorded = 0
        self.recentTracks = [waypoints[0]]

        self.currentCoordinate = waypoints[0]
        self.kinematicState.coordinate = waypoints[0]
        self.kinematicState.currentSpeedKmh = 0
        self.kinematicState.targetSpeedKmh = targetSpeedKmh

        let session = SimulationSession(
            name: name,
            source: .route,
            travelMode: travelMode,
            startedAt: Date(),
            state: .running,
            startCoordinate: CoordinateCodable(waypoints[0]),
            endCoordinate: CoordinateCodable(waypoints.last!),
            currentCoordinate: CoordinateCodable(waypoints[0])
        )
        self.currentSession = session

        _ = transport.sendLocation(latitude: waypoints[0].latitude, longitude: waypoints[0].longitude)
        updateSpoofEngineMirror(coordinate: waypoints[0], isSimulating: true)

        self.state = .running
        startSimulationTimer()
    }

    // MARK: - Simulation Lifecycle (Pause, Resume, Stop)

    public func pauseSimulation() {
        guard state == .running else { return }
        simulationTimer?.invalidate()
        simulationTimer = nil
        state = .paused
        currentSession?.state = .paused
        updateTelemetry(speed: 0, heading: kinematicState.headingDegrees, progress: telemetry.progressFraction)
    }

    public func resumeSimulation() {
        guard state == .paused else { return }
        state = .running
        currentSession?.state = .running
        startSimulationTimer()
    }

    public func stopSimulation() {
        stopCurrentSimulation(state: .completed)
    }

    private func stopCurrentSimulation(state finalState: SimulationState) {
        simulationTimer?.invalidate()
        simulationTimer = nil
        self.state = finalState
        if var session = currentSession {
            session.state = finalState
            session.endedAt = Date()
            session.distanceTravelledMeters = totalDistanceTravelled
            session.maxSpeedKmh = maxSpeedRecorded
            self.currentSession = session
        }
        activeRouteCoordinates = []
        currentRouteWaypoints = []
    }

    // MARK: - Simulation Tick Engine

    private func startSimulationTimer() {
        simulationTimer?.invalidate()
        let interval: TimeInterval = 0.2 // 5 Hz update rate for high precision
        simulationTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tickSimulation(deltaSeconds: interval)
            }
        }
    }

    private func tickSimulation(deltaSeconds: Double) {
        guard state == .running, currentWaypointIndex < currentRouteWaypoints.count else {
            stopSimulation()
            return
        }

        let effectiveDelta = deltaSeconds * timeWarpMultiplier
        let targetCoord = currentRouteWaypoints[currentWaypointIndex]
        let currentCoord = kinematicState.coordinate

        // Calculate distance and heading to current target waypoint
        let distToTarget = CLLocation(latitude: currentCoord.latitude, longitude: currentCoord.longitude)
            .distance(from: CLLocation(latitude: targetCoord.latitude, longitude: targetCoord.longitude))

        let rawHeading = motionEngine.calculateHeadingDegrees(from: currentCoord, to: targetCoord)
        kinematicState.headingDegrees = motionEngine.smoothHeading(
            currentHeading: kinematicState.headingDegrees,
            targetHeading: rawHeading
        )
        kinematicState.cardinalDirection = motionEngine.cardinalDirection(for: kinematicState.headingDegrees)

        // Step Speed
        kinematicState.currentSpeedKmh = motionEngine.stepSpeed(
            currentSpeedKmh: kinematicState.currentSpeedKmh,
            targetSpeedKmh: targetSpeedKmh,
            profile: activeProfile,
            deltaSeconds: effectiveDelta
        )
        maxSpeedRecorded = max(maxSpeedRecorded, kinematicState.currentSpeedKmh)

        let stepMeters = (kinematicState.currentSpeedKmh / 3.6) * effectiveDelta
        if stepMeters >= distToTarget || distToTarget < 2.0 {
            // Reached current waypoint -> advance to next
            kinematicState.coordinate = targetCoord
            currentWaypointIndex += 1
            totalDistanceTravelled += distToTarget
        } else {
            // Interpolate along heading
            let fraction = stepMeters / distToTarget
            let nextLat = currentCoord.latitude + (targetCoord.latitude - currentCoord.latitude) * fraction
            let nextLon = currentCoord.longitude + (targetCoord.longitude - currentCoord.longitude) * fraction
            kinematicState.coordinate = CLLocationCoordinate2D(latitude: nextLat, longitude: nextLon)
            totalDistanceTravelled += stepMeters
        }

        // Apply subtle correlated GPS noise before sending to device
        let jitteredCoord = motionEngine.applyJitter(to: kinematicState.coordinate, maxMeters: SpoofEngine.shared.enableJitter ? SpoofEngine.shared.jitterMeters : 0)
        self.currentCoordinate = jitteredCoord

        _ = transport.sendLocation(latitude: jitteredCoord.latitude, longitude: jitteredCoord.longitude)

        // Sample recent tracks (capped at 200 points to prevent memory growth)
        if recentTracks.count >= 200 {
            recentTracks.removeFirst(20)
        }
        recentTracks.append(jitteredCoord)

        let progress = currentRouteWaypoints.isEmpty ? 0 : Double(currentWaypointIndex) / Double(currentRouteWaypoints.count)
        updateTelemetry(
            speed: kinematicState.currentSpeedKmh,
            heading: kinematicState.headingDegrees,
            progress: min(1.0, progress)
        )
        updateSpoofEngineMirror(coordinate: jitteredCoord, isSimulating: true)
    }

    // MARK: - Source Arbitration

    private func acquireSource(_ source: SimulationSource) -> Bool {
        if state.isActive && activeSource != source && activeSource.priority > source.priority {
            return false
        }
        activeSource = source
        return true
    }

    private func updateTelemetry(speed: Double, heading: Double, progress: Double) {
        let elapsed = sessionStartTime != nil ? Date().timeIntervalSince(sessionStartTime!) : 0
        telemetry = SimulationTelemetry(
            coordinate: CoordinateCodable(currentCoordinate),
            speedKmh: speed,
            headingDegrees: heading,
            cardinalHeading: kinematicState.cardinalDirection,
            progressFraction: progress,
            distanceTravelledMeters: totalDistanceTravelled,
            distanceRemainingMeters: max(0, (telemetry.distanceRemainingMeters - totalDistanceTravelled)),
            elapsedTimeSeconds: elapsed,
            currentWaypointIndex: currentWaypointIndex,
            totalWaypoints: currentRouteWaypoints.count,
            isRealRoadRoute: isSimulatingRealRoad,
            routeProviderName: currentProvider.name,
            lastUpdated: Date()
        )
    }

    private func updateSpoofEngineMirror(coordinate: CLLocationCoordinate2D, isSimulating: Bool) {
        SpoofEngine.shared.currentCoordinate = coordinate
        SpoofEngine.shared.isSimulating = isSimulating
    }
}
