//
//  MotionEngine.swift
//  AutoSpoofVN
//
//  Kinematic motion calculator for realistic acceleration, deceleration, heading and speed interpolation.
//

import CoreLocation
import Foundation

public struct KinematicState: Equatable {
    public var coordinate: CLLocationCoordinate2D
    public var currentSpeedKmh: Double
    public var targetSpeedKmh: Double
    public var headingDegrees: Double
    public var cardinalDirection: String
    public var altitudeMeters: Double

    public static func == (lhs: KinematicState, rhs: KinematicState) -> Bool {
        abs(lhs.coordinate.latitude - rhs.coordinate.latitude) < 1e-7 &&
        abs(lhs.coordinate.longitude - rhs.coordinate.longitude) < 1e-7 &&
        abs(lhs.currentSpeedKmh - rhs.currentSpeedKmh) < 1e-4 &&
        abs(lhs.targetSpeedKmh - rhs.targetSpeedKmh) < 1e-4 &&
        abs(lhs.headingDegrees - rhs.headingDegrees) < 1e-4 &&
        lhs.cardinalDirection == rhs.cardinalDirection &&
        abs(lhs.altitudeMeters - rhs.altitudeMeters) < 1e-4
    }
    public init(
        coordinate: CLLocationCoordinate2D,
        currentSpeedKmh: Double = 0,
        targetSpeedKmh: Double = 0,
        headingDegrees: Double = 0,
        cardinalDirection: String = "N",
        altitudeMeters: Double = 12.0
    ) {
        self.coordinate = coordinate
        self.currentSpeedKmh = currentSpeedKmh
        self.targetSpeedKmh = targetSpeedKmh
        self.headingDegrees = headingDegrees
        self.cardinalDirection = cardinalDirection
        self.altitudeMeters = altitudeMeters
    }
}

public final class MotionEngine {
    public static let shared = MotionEngine()

    public var seed: UInt64? = nil
    private var currentJitterNorth: Double = 0
    private var currentJitterEast: Double = 0

    public init(seed: UInt64? = nil) {
        self.seed = seed
    }

    // MARK: - Speed Interpolation (Acceleration / Deceleration)

    public func stepSpeed(
        currentSpeedKmh: Double,
        targetSpeedKmh: Double,
        profile: SpeedProfile,
        deltaSeconds: Double
    ) -> Double {
        let currentMps = currentSpeedKmh / 3.6
        let targetMps = targetSpeedKmh / 3.6

        var nextMps = currentMps
        if currentMps < targetMps {
            let step = profile.accelerationMpss * deltaSeconds
            nextMps = min(targetMps, currentMps + step)
        } else if currentMps > targetMps {
            let step = profile.decelerationMpss * deltaSeconds
            nextMps = max(targetMps, currentMps - step)
        }

        // Apply subtle realistic speed variation if cruising
        if abs(nextMps - targetMps) < 0.5 && targetMps > 1.0 && profile.speedVariationRatio > 0 {
            let factor = 1.0 + (pseudoRandomDouble() * 2.0 - 1.0) * profile.speedVariationRatio
            nextMps = max(profile.minSpeedKmh / 3.6, min(profile.maxSpeedKmh / 3.6, nextMps * factor))
        }

        return max(0, nextMps * 3.6)
    }

    // MARK: - Heading & Cardinal Calculations

    public func calculateHeadingDegrees(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> Double {
        let lat1 = start.latitude * .pi / 180.0
        let lon1 = start.longitude * .pi / 180.0
        let lat2 = end.latitude * .pi / 180.0
        let lon2 = end.longitude * .pi / 180.0

        let dLon = lon2 - lon1
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let radians = atan2(y, x)
        let degrees = (radians * 180.0 / .pi + 360.0).truncatingRemainder(dividingBy: 360.0)
        return degrees
    }

    public func smoothHeading(currentHeading: Double, targetHeading: Double, smoothingFactor: Double = 0.25) -> Double {
        let cur = currentHeading.truncatingRemainder(dividingBy: 360.0)
        let tgt = targetHeading.truncatingRemainder(dividingBy: 360.0)
        var diff = tgt - cur
        while diff < -180.0 { diff += 360.0 }
        while diff > 180.0 { diff -= 360.0 }
        let next = cur + diff * smoothingFactor
        return (next + 360.0).truncatingRemainder(dividingBy: 360.0)
    }

    public func cardinalDirection(for degrees: Double) -> String {
        let normalized = (degrees.truncatingRemainder(dividingBy: 360.0) + 360.0).truncatingRemainder(dividingBy: 360.0)
        let directions = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let index = Int(((normalized + 11.25) / 22.5).rounded(.down)) % 16
        return directions[index]
    }

    // MARK: - Correlated GPS Jitter

    public func applyJitter(
        to coordinate: CLLocationCoordinate2D,
        maxMeters: Double,
        correlation: Double = 0.8
    ) -> CLLocationCoordinate2D {
        guard maxMeters > 0 else { return coordinate }

        let randomNorth = (pseudoRandomDouble() * 2.0 - 1.0) * maxMeters
        let randomEast = (pseudoRandomDouble() * 2.0 - 1.0) * maxMeters

        currentJitterNorth = currentJitterNorth * correlation + randomNorth * (1.0 - correlation)
        currentJitterEast = currentJitterEast * correlation + randomEast * (1.0 - correlation)

        let latDegreesPerMeter = 1.0 / 111_132.954
        let lonDegreesPerMeter = 1.0 / (111_412.877 * cos(coordinate.latitude * .pi / 180.0))

        let finalLat = coordinate.latitude + currentJitterNorth * latDegreesPerMeter
        let finalLon = coordinate.longitude + currentJitterEast * lonDegreesPerMeter
        return CLLocationCoordinate2D(latitude: finalLat, longitude: finalLon)
    }

    private func pseudoRandomDouble() -> Double {
        if let s = seed {
            let next = (s &* 6364136223846793005) &+ 1442695040888963407
            seed = next
            return Double(next >> 11) / Double(1 << 53)
        } else {
            return Double.random(in: 0...1)
        }
    }
}
