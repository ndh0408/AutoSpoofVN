//
//  SimulationModels.swift
//  AutoSpoofVN
//
//  Unified models for Simulation Sessions, Motion Profiles, Scenarios, and Telemetry.
//

import CoreLocation
import Foundation

// MARK: - Simulation Source & Priority

public enum SimulationSource: String, CaseIterable, Codable, Identifiable {
    case manual
    case scenario
    case flight
    case route
    case routine
    case replay

    public var id: String { rawValue }

    public var priority: Int {
        switch self {
        case .manual:   return 100
        case .scenario: return 80
        case .flight:   return 60
        case .route:    return 50
        case .replay:   return 40
        case .routine:  return 20
        }
    }

    public var displayName: String {
        switch self {
        case .manual:   return "Thủ công (Manual)"
        case .scenario: return "Kịch bản (Scenario)"
        case .flight:   return "Chuyến bay (Flight)"
        case .route:    return "Tuyến đường (Route)"
        case .replay:   return "Phát lại (Replay)"
        case .routine:  return "Chu trình 24/7 (Routine)"
        }
    }

    public var icon: String {
        switch self {
        case .manual:   return "hand.tap.fill"
        case .scenario: return "slider.horizontal.3"
        case .flight:   return "airplane"
        case .route:    return "point.topleft.down.curvedto.point.bottomright.up.fill"
        case .replay:   return "play.circle.fill"
        case .routine:  return "clock.arrow.2.circlepath"
        }
    }
}

// MARK: - Simulation State

public enum SimulationState: String, Codable {
    case idle
    case preparing
    case running
    case paused
    case stopping
    case completed
    case failed

    public var isActive: Bool {
        self == .running || self == .paused || self == .preparing
    }

    public var statusText: String {
        switch self {
        case .idle:      return "Sẵn sàng"
        case .preparing: return "Đang chuẩn bị..."
        case .running:   return "Đang mô phỏng"
        case .paused:    return "Tạm dừng"
        case .stopping:  return "Đang dừng..."
        case .completed: return "Đã hoàn thành"
        case .failed:    return "Gặp lỗi"
        }
    }
}

// MARK: - Travel Mode & Speed Profiles

public enum TravelMode: String, CaseIterable, Codable, Identifiable {
    case walking
    case cycling
    case motorcycle
    case driving
    case train
    case flight
    case custom

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .walking:    return "Đi bộ"
        case .cycling:    return "Xe đạp"
        case .motorcycle: return "Xe máy"
        case .driving:    return "Ô tô"
        case .train:      return "Tàu hỏa"
        case .flight:     return "Máy bay"
        case .custom:     return "Tùy biến"
        }
    }

    public var icon: String {
        switch self {
        case .walking:    return "figure.walk"
        case .cycling:    return "bicycle"
        case .motorcycle: return "bicycle.circle.fill"
        case .driving:    return "car.fill"
        case .train:      return "tram.fill"
        case .flight:     return "airplane"
        case .custom:     return "speedometer"
        }
    }

    public var defaultProfile: SpeedProfile {
        switch self {
        case .walking:
            return SpeedProfile(minSpeedKmh: 3.5, maxSpeedKmh: 6.0, cruisingSpeedKmh: 4.8, accelerationMpss: 0.8, decelerationMpss: 1.2, speedVariationRatio: 0.1)
        case .cycling:
            return SpeedProfile(minSpeedKmh: 10.0, maxSpeedKmh: 22.0, cruisingSpeedKmh: 16.0, accelerationMpss: 1.2, decelerationMpss: 1.8, speedVariationRatio: 0.15)
        case .motorcycle:
            return SpeedProfile(minSpeedKmh: 15.0, maxSpeedKmh: 48.0, cruisingSpeedKmh: 35.0, accelerationMpss: 2.2, decelerationMpss: 3.0, speedVariationRatio: 0.15)
        case .driving:
            return SpeedProfile(minSpeedKmh: 20.0, maxSpeedKmh: 80.0, cruisingSpeedKmh: 50.0, accelerationMpss: 2.5, decelerationMpss: 3.5, speedVariationRatio: 0.12)
        case .train:
            return SpeedProfile(minSpeedKmh: 40.0, maxSpeedKmh: 120.0, cruisingSpeedKmh: 85.0, accelerationMpss: 0.8, decelerationMpss: 1.0, speedVariationRatio: 0.05)
        case .flight:
            return SpeedProfile(minSpeedKmh: 300.0, maxSpeedKmh: 920.0, cruisingSpeedKmh: 820.0, accelerationMpss: 1.5, decelerationMpss: 1.8, speedVariationRatio: 0.03)
        case .custom:
            return SpeedProfile(minSpeedKmh: 10.0, maxSpeedKmh: 60.0, cruisingSpeedKmh: 40.0, accelerationMpss: 2.0, decelerationMpss: 2.5, speedVariationRatio: 0.1)
        }
    }
}

public struct SpeedProfile: Codable, Equatable {
    public var minSpeedKmh: Double
    public var maxSpeedKmh: Double
    public var cruisingSpeedKmh: Double
    public var accelerationMpss: Double
    public var decelerationMpss: Double
    public var speedVariationRatio: Double

    public init(
        minSpeedKmh: Double,
        maxSpeedKmh: Double,
        cruisingSpeedKmh: Double,
        accelerationMpss: Double,
        decelerationMpss: Double,
        speedVariationRatio: Double
    ) {
        self.minSpeedKmh = minSpeedKmh
        self.maxSpeedKmh = maxSpeedKmh
        self.cruisingSpeedKmh = cruisingSpeedKmh
        self.accelerationMpss = accelerationMpss
        self.decelerationMpss = decelerationMpss
        self.speedVariationRatio = speedVariationRatio
    }
}

// MARK: - Live Simulation Telemetry

public struct SimulationTelemetry: Codable, Equatable {
    public var coordinate: CoordinateCodable
    public var speedKmh: Double
    public var headingDegrees: Double
    public var cardinalHeading: String
    public var altitudeMeters: Double
    public var verticalSpeedMps: Double
    public var progressFraction: Double
    public var distanceTravelledMeters: Double
    public var distanceRemainingMeters: Double
    public var elapsedTimeSeconds: TimeInterval
    public var estimatedTimeRemainingSeconds: TimeInterval
    public var currentWaypointIndex: Int
    public var totalWaypoints: Int
    public var isRealRoadRoute: Bool
    public var routeProviderName: String
    public var lastUpdated: Date

    public init(
        coordinate: CoordinateCodable = CoordinateCodable(latitude: 21.0285, longitude: 105.8542),
        speedKmh: Double = 0,
        headingDegrees: Double = 0,
        cardinalHeading: String = "N",
        altitudeMeters: Double = 12.0,
        verticalSpeedMps: Double = 0,
        progressFraction: Double = 0,
        distanceTravelledMeters: Double = 0,
        distanceRemainingMeters: Double = 0,
        elapsedTimeSeconds: TimeInterval = 0,
        estimatedTimeRemainingSeconds: TimeInterval = 0,
        currentWaypointIndex: Int = 0,
        totalWaypoints: Int = 0,
        isRealRoadRoute: Bool = false,
        routeProviderName: String = "Sẵn sàng",
        lastUpdated: Date = Date()
    ) {
        self.coordinate = coordinate
        self.speedKmh = speedKmh
        self.headingDegrees = headingDegrees
        self.cardinalHeading = cardinalHeading
        self.altitudeMeters = altitudeMeters
        self.verticalSpeedMps = verticalSpeedMps
        self.progressFraction = progressFraction
        self.distanceTravelledMeters = distanceTravelledMeters
        self.distanceRemainingMeters = distanceRemainingMeters
        self.elapsedTimeSeconds = elapsedTimeSeconds
        self.estimatedTimeRemainingSeconds = estimatedTimeRemainingSeconds
        self.currentWaypointIndex = currentWaypointIndex
        self.totalWaypoints = totalWaypoints
        self.isRealRoadRoute = isRealRoadRoute
        self.routeProviderName = routeProviderName
        self.lastUpdated = lastUpdated
    }
}

// MARK: - Simulation Session Record

public struct SimulationSession: Identifiable, Codable, Equatable {
    public var id: UUID
    public var name: String
    public var source: SimulationSource
    public var travelMode: TravelMode
    public var createdAt: Date
    public var startedAt: Date?
    public var endedAt: Date?
    public var state: SimulationState
    public var startCoordinate: CoordinateCodable
    public var endCoordinate: CoordinateCodable?
    public var currentCoordinate: CoordinateCodable
    public var totalDistanceMeters: Double
    public var distanceTravelledMeters: Double
    public var averageSpeedKmh: Double
    public var maxSpeedKmh: Double
    public var recordedTrack: [CoordinateCodable]
    public var failureReason: String?

    public init(
        id: UUID = UUID(),
        name: String,
        source: SimulationSource,
        travelMode: TravelMode = .driving,
        createdAt: Date = Date(),
        startedAt: Date? = nil,
        endedAt: Date? = nil,
        state: SimulationState = .idle,
        startCoordinate: CoordinateCodable,
        endCoordinate: CoordinateCodable? = nil,
        currentCoordinate: CoordinateCodable,
        totalDistanceMeters: Double = 0,
        distanceTravelledMeters: Double = 0,
        averageSpeedKmh: Double = 0,
        maxSpeedKmh: Double = 0,
        recordedTrack: [CoordinateCodable] = [],
        failureReason: String? = nil
    ) {
        self.id = id
        self.name = name
        self.source = source
        self.travelMode = travelMode
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.state = state
        self.startCoordinate = startCoordinate
        self.endCoordinate = endCoordinate
        self.currentCoordinate = currentCoordinate
        self.totalDistanceMeters = totalDistanceMeters
        self.distanceTravelledMeters = distanceTravelledMeters
        self.averageSpeedKmh = averageSpeedKmh
        self.maxSpeedKmh = maxSpeedKmh
        self.recordedTrack = recordedTrack
        self.failureReason = failureReason
    }
}

// MARK: - Scenario Automation Models

public enum ScenarioActionType: String, Codable, CaseIterable {
    case setLocation
    case moveTo
    case followRoute
    case waitSeconds
    case changeSpeed
    case changeTravelMode
    case dwellArea
    case randomJitter

    public var displayName: String {
        switch self {
        case .setLocation:      return "Đặt vị trí tức thì"
        case .moveTo:           return "Di chuyển tới điểm"
        case .followRoute:      return "Đi theo tuyến đường"
        case .waitSeconds:      return "Chờ thời gian"
        case .changeSpeed:      return "Đổi vận tốc"
        case .changeTravelMode: return "Đổi phương tiện"
        case .dwellArea:        return "Dừng chân & khám phá"
        case .randomJitter:     return "Mô phỏng nhiễu GPS"
        }
    }

    public var icon: String {
        switch self {
        case .setLocation:      return "mappin.circle.fill"
        case .moveTo:           return "arrow.triangle.turn.up.right.diamond.fill"
        case .followRoute:      return "point.topleft.down.curvedto.point.bottomright.up.fill"
        case .waitSeconds:      return "timer"
        case .changeSpeed:      return "speedometer"
        case .changeTravelMode: return "car.fill"
        case .dwellArea:        return "figure.walk.circle.fill"
        case .randomJitter:     return "waveform.path.ecg"
        }
    }
}

public struct ScenarioStep: Identifiable, Codable, Equatable {
    public var id: UUID
    public var title: String
    public var actionType: ScenarioActionType
    public var targetCoordinate: CoordinateCodable?
    public var targetSpeedKmh: Double?
    public var waitDurationSeconds: Double?
    public var travelMode: TravelMode?
    public var dwellRadiusMeters: Double?

    public init(
        id: UUID = UUID(),
        title: String,
        actionType: ScenarioActionType,
        targetCoordinate: CoordinateCodable? = nil,
        targetSpeedKmh: Double? = nil,
        waitDurationSeconds: Double? = nil,
        travelMode: TravelMode? = nil,
        dwellRadiusMeters: Double? = nil
    ) {
        self.id = id
        self.title = title
        self.actionType = actionType
        self.targetCoordinate = targetCoordinate
        self.targetSpeedKmh = targetSpeedKmh
        self.waitDurationSeconds = waitDurationSeconds
        self.travelMode = travelMode
        self.dwellRadiusMeters = dwellRadiusMeters
    }
}

public struct Scenario: Identifiable, Codable, Equatable {
    public var id: UUID
    public var name: String
    public var summary: String
    public var steps: [ScenarioStep]
    public var isLooping: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        summary: String = "",
        steps: [ScenarioStep] = [],
        isLooping: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.steps = steps
        self.isLooping = isLooping
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
