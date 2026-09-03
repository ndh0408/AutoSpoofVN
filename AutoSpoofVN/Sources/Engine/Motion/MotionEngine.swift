import CoreLocation
import Foundation

/// Động cơ chuyển động — tạo chuyển động mượt giữa các waypoint.
/// Hỗ trợ tăng tốc / giữ tốc / giảm tốc / dừng, heading mượt, và speed profile.
actor MotionEngine {
    private var speedProfile: SpeedProfile
    private var currentSpeedKmh: Double = 0
    private var currentHeading: Double = 0
    private var phase: MotionPhase = .stopped
    private var totalDistanceTravelled: Double = 0

    init(speedProfile: SpeedProfile = TravelMode.driving.defaultSpeed) {
        self.speedProfile = speedProfile
    }

    func setSpeedProfile(_ profile: SpeedProfile) {
        self.speedProfile = profile
    }

    /// Tính vị trí kế tiếp dựa trên vị trí hiện tại, waypoint đích, và delta time.
    func nextPosition(
        from current: CLLocationCoordinate2D,
        toward target: CLLocationCoordinate2D,
        deltaTime: TimeInterval,
        distanceToEnd: Double
    ) -> MotionResult {
        let distanceToTarget = Self.haversineDistance(from: current, to: target)

        // Quyết định phase
        if distanceToTarget < 5 {
            phase = .stopped
            currentSpeedKmh = 0
            return MotionResult(
                coordinate: target,
                speedKmh: 0,
                headingDegrees: currentHeading,
                phase: .stopped,
                distanceMoved: 0,
                reachedTarget: true
            )
        }

        // Khoảng cách cần để giảm tốc từ tốc độ hiện tại về 0
        let brakingDistance = brakingDistanceMeters()

        if distanceToEnd < brakingDistance * 1.2 {
            phase = .decelerating
            let decel = speedProfile.deceleration * deltaTime
            currentSpeedKmh = max(speedProfile.min, currentSpeedKmh - decel)
        } else if currentSpeedKmh < speedProfile.cruise {
            phase = .accelerating
            let accel = speedProfile.acceleration * deltaTime
            currentSpeedKmh = min(speedProfile.cruise, currentSpeedKmh + accel)
        } else {
            phase = .cruising
            // Dao động nhẹ quanh cruise
            let variation = speedProfile.cruise * speedProfile.randomVariation
            let target = speedProfile.cruise + Double.random(in: -variation...variation)
            currentSpeedKmh += (target - currentSpeedKmh) * 0.1
        }

        currentSpeedKmh = max(0, min(currentSpeedKmh, speedProfile.max))

        // Khoảng cách di chuyển trong delta time
        let speedMs = currentSpeedKmh / 3.6
        let distanceMoved = speedMs * deltaTime

        // Heading
        let targetHeading = Self.bearing(from: current, to: target)
        currentHeading = Self.smoothHeading(from: currentHeading, to: targetHeading, factor: 0.15)

        // Vị trí mới
        let newCoord = Self.moveCoordinate(current, distanceMeters: min(distanceMoved, distanceToTarget), bearingDegrees: currentHeading)
        totalDistanceTravelled += min(distanceMoved, distanceToTarget)

        let reached = distanceMoved >= distanceToTarget

        return MotionResult(
            coordinate: reached ? target : newCoord,
            speedKmh: currentSpeedKmh,
            headingDegrees: currentHeading,
            phase: phase,
            distanceMoved: min(distanceMoved, distanceToTarget),
            reachedTarget: reached
        )
    }

    func reset() {
        currentSpeedKmh = 0
        currentHeading = 0
        phase = .stopped
        totalDistanceTravelled = 0
    }

    // MARK: - Math

    private func brakingDistanceMeters() -> Double {
        // v² / (2a), đổi từ km/h sang m/s
        let v = currentSpeedKmh / 3.6
        let a = speedProfile.deceleration / 3.6
        guard a > 0 else { return 0 }
        return (v * v) / (2 * a)
    }

    /// Khoảng cách Haversine giữa hai toạ độ (mét).
    static func haversineDistance(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let R = 6_371_000.0  // bán kính trái đất, mét
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * R * atan2(sqrt(h), sqrt(1 - h))
    }

    /// Bearing (góc) từ a đến b, đơn vị độ.
    static func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        var bearing = atan2(y, x) * 180 / .pi
        if bearing < 0 { bearing += 360 }
        return bearing
    }

    /// Heading mượt — tránh nhảy 0°/360°.
    static func smoothHeading(from current: Double, to target: Double, factor: Double) -> Double {
        var diff = target - current
        if diff > 180 { diff -= 360 }
        if diff < -180 { diff += 360 }
        var result = current + diff * factor
        if result < 0 { result += 360 }
        if result >= 360 { result -= 360 }
        return result
    }

    /// Di chuyển toạ độ theo khoảng cách và hướng.
    static func moveCoordinate(_ coord: CLLocationCoordinate2D, distanceMeters: Double, bearingDegrees: Double) -> CLLocationCoordinate2D {
        let R = 6_371_000.0
        let d = distanceMeters / R
        let brng = bearingDegrees * .pi / 180
        let lat1 = coord.latitude * .pi / 180
        let lon1 = coord.longitude * .pi / 180

        let lat2 = asin(sin(lat1) * cos(d) + cos(lat1) * sin(d) * cos(brng))
        let lon2 = lon1 + atan2(sin(brng) * sin(d) * cos(lat1), cos(d) - sin(lat1) * sin(lat2))

        return CLLocationCoordinate2D(
            latitude: lat2 * 180 / .pi,
            longitude: lon2 * 180 / .pi
        )
    }
}

struct MotionResult {
    let coordinate: CLLocationCoordinate2D
    let speedKmh: Double
    let headingDegrees: Double
    let phase: MotionPhase
    let distanceMoved: Double
    let reachedTarget: Bool
}
