import CoreLocation
import Foundation
import MapKit

actor RouteProvider {
    static let shared = RouteProvider()

    struct RouteResult {
        enum Source: Equatable {
            case mapKit
            case straightLineFallback

            var displayName: String {
                switch self {
                case .mapKit:
                    return "MKDirections"
                case .straightLineFallback:
                    return "Nội suy đường thẳng"
                }
            }
        }

        let plan: RoutePlan
        let source: Source
        let distanceMeters: CLLocationDistance
        let expectedTravelTime: TimeInterval?
        let errorDescription: String?

        var usedFallback: Bool {
            source == .straightLineFallback
        }

        var segmentDistancesMeters: [CLLocationDistance] {
            plan.segmentDistancesMeters
        }
    }

    struct DiagnosticsSnapshot {
        let lastSource: RouteResult.Source?
        let mapKitRouteCount: Int
        let fallbackCount: Int
        let lastErrorDescription: String?
        let lastUpdatedAt: Date?
        let cacheEntryCount: Int

        static let empty = DiagnosticsSnapshot(
            lastSource: nil,
            mapKitRouteCount: 0,
            fallbackCount: 0,
            lastErrorDescription: nil,
            lastUpdatedAt: nil,
            cacheEntryCount: 0
        )
    }

    private struct CacheKey: Hashable {
        let fromLatitude: Int
        let fromLongitude: Int
        let toLatitude: Int
        let toLongitude: Int
        let transportType: UInt

        init(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, transportType: MKDirectionsTransportType) {
            fromLatitude = Self.quantize(from.latitude)
            fromLongitude = Self.quantize(from.longitude)
            toLatitude = Self.quantize(to.latitude)
            toLongitude = Self.quantize(to.longitude)
            self.transportType = transportType.rawValue
        }

        private static func quantize(_ value: Double) -> Int {
            Int((value * 100_000).rounded())
        }
    }

    private struct RouteGeometry {
        let coordinates: [CLLocationCoordinate2D]
        let distanceMeters: CLLocationDistance
        let expectedTravelTime: TimeInterval
    }

    private enum CachedValue {
        case route(RouteGeometry)
        case failure(String)
    }

    private struct CacheEntry {
        let value: CachedValue
        let expiresAt: Date
    }

    private enum RouteProviderError: LocalizedError {
        case noRoute

        var errorDescription: String? {
            "MapKit không trả về tuyến đường phù hợp."
        }
    }

    private let maximumCacheEntries = 64
    private let successfulRouteLifetime: TimeInterval = 24 * 60 * 60
    private let failedRouteLifetime: TimeInterval = 60
    private var cache: [CacheKey: CacheEntry] = [:]
    private var cacheAccessOrder: [CacheKey] = []
    private var pendingRequests: [CacheKey: Task<RouteGeometry, Error>] = [:]
    private var lastRouteSource: RouteResult.Source?
    private var mapKitRouteCount = 0
    private var fallbackCount = 0
    private var lastRouteErrorDescription: String?
    private var lastRouteUpdatedAt: Date?

    func routePlan(
        named name: String,
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        transportType: MKDirectionsTransportType,
        speedKmh: Double,
        sampleSpacingMeters: CLLocationDistance,
        autoLoop: Bool = false
    ) async -> RoutePlan {
        let result = await resolveRoute(
            named: name,
            from: from,
            to: to,
            transportType: transportType,
            speedKmh: speedKmh,
            sampleSpacingMeters: sampleSpacingMeters,
            autoLoop: autoLoop
        )
        return result.plan
    }

    func resolveRoute(
        named name: String,
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        transportType: MKDirectionsTransportType,
        speedKmh: Double,
        sampleSpacingMeters: CLLocationDistance,
        autoLoop: Bool = false
    ) async -> RouteResult {
        let spacing = max(1, sampleSpacingMeters)
        guard CLLocationCoordinate2DIsValid(from), CLLocationCoordinate2DIsValid(to) else {
            return record(Self.fallbackResult(
                named: name,
                from: from,
                to: to,
                speedKmh: speedKmh,
                spacingMeters: spacing,
                autoLoop: autoLoop,
                errorDescription: "Tọa độ đầu hoặc cuối không hợp lệ."
            ))
        }

        if Self.distance(from: from, to: to) < 0.5 {
            return record(RouteResult(
                plan: RoutePlan(
                    name: name,
                    waypoints: [CoordinateCodable(from)],
                    speedKmh: speedKmh,
                    autoLoop: autoLoop
                ),
                source: .straightLineFallback,
                distanceMeters: 0,
                expectedTravelTime: 0,
                errorDescription: nil
            ))
        }

        let key = CacheKey(from: from, to: to, transportType: transportType)
        if let cachedValue = cachedValue(for: key) {
            return record(Self.makeResult(
                named: name,
                from: from,
                to: to,
                cachedValue: cachedValue,
                speedKmh: speedKmh,
                spacingMeters: spacing,
                autoLoop: autoLoop
            ))
        }

        let requestTask: Task<RouteGeometry, Error>
        if let pendingRequest = pendingRequests[key] {
            requestTask = pendingRequest
        } else {
            requestTask = Task {
                try await Self.calculateRoute(from: from, to: to, transportType: transportType)
            }
            pendingRequests[key] = requestTask
        }

        do {
            let geometry = try await requestTask.value
            pendingRequests[key] = nil
            store(.route(geometry), for: key, lifetime: successfulRouteLifetime)
            return record(Self.result(
                named: name,
                from: geometry,
                speedKmh: speedKmh,
                spacingMeters: spacing,
                autoLoop: autoLoop
            ))
        } catch {
            pendingRequests[key] = nil
            let errorDescription = error.localizedDescription
            if !(error is CancellationError) {
                store(.failure(errorDescription), for: key, lifetime: failedRouteLifetime)
            }
            return record(Self.fallbackResult(
                named: name,
                from: from,
                to: to,
                speedKmh: speedKmh,
                spacingMeters: spacing,
                autoLoop: autoLoop,
                errorDescription: errorDescription
            ))
        }
    }

    nonisolated func fetchRoutePlan(
        named name: String,
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        transportType: MKDirectionsTransportType,
        speedKmh: Double,
        sampleSpacingMeters: CLLocationDistance,
        autoLoop: Bool = false,
        completion: @escaping (RoutePlan) -> Void
    ) {
        Task {
            let plan = await routePlan(
                named: name,
                from: from,
                to: to,
                transportType: transportType,
                speedKmh: speedKmh,
                sampleSpacingMeters: sampleSpacingMeters,
                autoLoop: autoLoop
            )
            await MainActor.run {
                completion(plan)
            }
        }
    }

    func clearCache() {
        cache.removeAll()
        cacheAccessOrder.removeAll()
    }

    func diagnosticsSnapshot() -> DiagnosticsSnapshot {
        DiagnosticsSnapshot(
            lastSource: lastRouteSource,
            mapKitRouteCount: mapKitRouteCount,
            fallbackCount: fallbackCount,
            lastErrorDescription: lastRouteErrorDescription,
            lastUpdatedAt: lastRouteUpdatedAt,
            cacheEntryCount: cache.count
        )
    }

    func resetDiagnostics() {
        lastRouteSource = nil
        mapKitRouteCount = 0
        fallbackCount = 0
        lastRouteErrorDescription = nil
        lastRouteUpdatedAt = nil
    }

    static func resample(
        _ coordinates: [CLLocationCoordinate2D],
        spacingMeters: CLLocationDistance,
        maximumPointCount: Int = 20_000
    ) -> [CLLocationCoordinate2D] {
        let validCoordinates = coordinates.filter { CLLocationCoordinate2DIsValid($0) }
        guard let firstCoordinate = validCoordinates.first else { return [] }

        var normalizedCoordinates = [firstCoordinate]
        for coordinate in validCoordinates.dropFirst() {
            if distance(from: normalizedCoordinates[normalizedCoordinates.count - 1], to: coordinate) >= 0.05 {
                normalizedCoordinates.append(coordinate)
            }
        }

        guard normalizedCoordinates.count > 1 else { return normalizedCoordinates }

        var cumulativeDistances: [CLLocationDistance] = [0]
        cumulativeDistances.reserveCapacity(normalizedCoordinates.count)
        for index in 1..<normalizedCoordinates.count {
            cumulativeDistances.append(
                cumulativeDistances[index - 1]
                    + distance(from: normalizedCoordinates[index - 1], to: normalizedCoordinates[index])
            )
        }

        guard let totalDistance = cumulativeDistances.last, totalDistance > 0 else {
            return [firstCoordinate]
        }

        let pointLimit = max(2, maximumPointCount)
        let requestedSpacing = max(1, spacingMeters)
        let effectiveSpacing = max(requestedSpacing, totalDistance / Double(pointLimit - 1))
        var sampledCoordinates = [firstCoordinate]
        sampledCoordinates.reserveCapacity(min(pointLimit, Int(ceil(totalDistance / effectiveSpacing)) + 1))

        var targetDistance = effectiveSpacing
        var segmentIndex = 1
        while targetDistance < totalDistance, sampledCoordinates.count < pointLimit - 1 {
            while segmentIndex < cumulativeDistances.count - 1,
                  cumulativeDistances[segmentIndex] < targetDistance {
                segmentIndex += 1
            }

            let segmentStartDistance = cumulativeDistances[segmentIndex - 1]
            let segmentEndDistance = cumulativeDistances[segmentIndex]
            let segmentLength = segmentEndDistance - segmentStartDistance
            if segmentLength > 0 {
                let fraction = (targetDistance - segmentStartDistance) / segmentLength
                sampledCoordinates.append(
                    GeodesicMath.interpolateGreatCircle(
                        from: normalizedCoordinates[segmentIndex - 1],
                        to: normalizedCoordinates[segmentIndex],
                        fraction: fraction
                    )
                )
            }
            targetDistance += effectiveSpacing
        }

        if let lastCoordinate = normalizedCoordinates.last,
           distance(from: sampledCoordinates[sampledCoordinates.count - 1], to: lastCoordinate) >= 0.05 {
            sampledCoordinates.append(lastCoordinate)
        }
        return sampledCoordinates
    }

    static func straightLineCoordinates(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        spacingMeters: CLLocationDistance
    ) -> [CLLocationCoordinate2D] {
        guard CLLocationCoordinate2DIsValid(from), CLLocationCoordinate2DIsValid(to) else {
            return [from, to].filter { CLLocationCoordinate2DIsValid($0) }
        }
        return resample([from, to], spacingMeters: spacingMeters)
    }

    private func cachedValue(for key: CacheKey) -> CachedValue? {
        guard let entry = cache[key] else { return nil }
        guard entry.expiresAt > Date() else {
            cache[key] = nil
            cacheAccessOrder.removeAll { $0 == key }
            return nil
        }
        cacheAccessOrder.removeAll { $0 == key }
        cacheAccessOrder.append(key)
        return entry.value
    }

    private func store(_ value: CachedValue, for key: CacheKey, lifetime: TimeInterval) {
        cache[key] = CacheEntry(value: value, expiresAt: Date().addingTimeInterval(lifetime))
        cacheAccessOrder.removeAll { $0 == key }
        cacheAccessOrder.append(key)

        while cacheAccessOrder.count > maximumCacheEntries {
            let oldestKey = cacheAccessOrder.removeFirst()
            cache[oldestKey] = nil
        }
    }

    private func record(_ result: RouteResult) -> RouteResult {
        lastRouteSource = result.source
        lastRouteUpdatedAt = Date()
        if result.source == .mapKit {
            mapKitRouteCount += 1
            lastRouteErrorDescription = nil
        } else if let errorDescription = result.errorDescription {
            fallbackCount += 1
            lastRouteErrorDescription = errorDescription
        }
        return result
    }

    private static func calculateRoute(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        transportType: MKDirectionsTransportType
    ) async throws -> RouteGeometry {
        let request = MKDirections.Request()
        request.source = mapItem(for: from)
        request.destination = mapItem(for: to)
        request.transportType = transportType
        request.requestsAlternateRoutes = false

        let directions = MKDirections(request: request)
        let response: MKDirections.Response = try await withTaskCancellationHandler(operation: {
            // Phải chú thích kiểu continuation tường minh: lồng trong
            // withTaskCancellationHandler thì trình biên dịch không suy ra được tham số
            // generic, và báo "generic parameter 'T' could not be inferred".
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<MKDirections.Response, Error>) in
                directions.calculate { response, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let response {
                        continuation.resume(returning: response)
                    } else {
                        continuation.resume(throwing: RouteProviderError.noRoute)
                    }
                }
            }
        }, onCancel: {
            directions.cancel()
        })

        guard let route = response.routes.min(by: { $0.expectedTravelTime < $1.expectedTravelTime }) else {
            throw RouteProviderError.noRoute
        }

        let coordinates = coordinates(from: route.polyline, exactStart: from, exactEnd: to)
        guard coordinates.count >= 2 else {
            throw RouteProviderError.noRoute
        }
        return RouteGeometry(
            coordinates: coordinates,
            distanceMeters: route.distance,
            expectedTravelTime: route.expectedTravelTime
        )
    }

    private static func mapItem(for coordinate: CLLocationCoordinate2D) -> MKMapItem {
        if #available(iOS 26.0, *) {
            return MKMapItem(
                location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
                address: nil
            )
        }
        return legacyMapItem(for: coordinate)
    }

    @available(iOS, introduced: 6.0, obsoleted: 26.0)
    private static func legacyMapItem(for coordinate: CLLocationCoordinate2D) -> MKMapItem {
        MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
    }

    private static func coordinates(
        from polyline: MKPolyline,
        exactStart: CLLocationCoordinate2D,
        exactEnd: CLLocationCoordinate2D
    ) -> [CLLocationCoordinate2D] {
        guard polyline.pointCount > 0 else { return [] }
        var coordinates = [CLLocationCoordinate2D](
            repeating: kCLLocationCoordinate2DInvalid,
            count: polyline.pointCount
        )
        polyline.getCoordinates(
            &coordinates,
            range: NSRange(location: 0, length: polyline.pointCount)
        )
        coordinates = coordinates.filter { CLLocationCoordinate2DIsValid($0) }
        guard !coordinates.isEmpty else { return [] }

        if distance(from: exactStart, to: coordinates[0]) >= 0.05 {
            coordinates.insert(exactStart, at: 0)
        } else {
            coordinates[0] = exactStart
        }

        if let lastCoordinate = coordinates.last,
           distance(from: lastCoordinate, to: exactEnd) >= 0.05 {
            coordinates.append(exactEnd)
        } else {
            coordinates[coordinates.count - 1] = exactEnd
        }
        return coordinates
    }

    private static func result(
        named name: String,
        from geometry: RouteGeometry,
        speedKmh: Double,
        spacingMeters: CLLocationDistance,
        autoLoop: Bool
    ) -> RouteResult {
        let coordinates = resample(geometry.coordinates, spacingMeters: spacingMeters)
        return RouteResult(
            plan: RoutePlan(
                name: name,
                waypoints: coordinates.map { CoordinateCodable($0) },
                speedKmh: speedKmh,
                autoLoop: autoLoop
            ),
            source: .mapKit,
            distanceMeters: geometry.distanceMeters,
            expectedTravelTime: geometry.expectedTravelTime,
            errorDescription: nil
        )
    }

    private static func makeResult(
        named name: String,
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        cachedValue: CachedValue,
        speedKmh: Double,
        spacingMeters: CLLocationDistance,
        autoLoop: Bool
    ) -> RouteResult {
        switch cachedValue {
        case .route(let geometry):
            return result(
                named: name,
                from: geometry,
                speedKmh: speedKmh,
                spacingMeters: spacingMeters,
                autoLoop: autoLoop
            )
        case .failure(let errorDescription):
            return fallbackResult(
                named: name,
                from: from,
                to: to,
                speedKmh: speedKmh,
                spacingMeters: spacingMeters,
                autoLoop: autoLoop,
                errorDescription: errorDescription
            )
        }
    }

    private static func fallbackResult(
        named name: String,
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        speedKmh: Double,
        spacingMeters: CLLocationDistance,
        autoLoop: Bool,
        errorDescription: String?
    ) -> RouteResult {
        let coordinates = straightLineCoordinates(from: from, to: to, spacingMeters: spacingMeters)
        return RouteResult(
            plan: RoutePlan(
                name: name,
                waypoints: coordinates.map { CoordinateCodable($0) },
                speedKmh: speedKmh,
                autoLoop: autoLoop
            ),
            source: .straightLineFallback,
            distanceMeters: distance(from: from, to: to),
            expectedTravelTime: nil,
            errorDescription: errorDescription
        )
    }

    private static func distance(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D
    ) -> CLLocationDistance {
        guard CLLocationCoordinate2DIsValid(from), CLLocationCoordinate2DIsValid(to) else {
            return 0
        }
        return CLLocation(latitude: from.latitude, longitude: from.longitude)
            .distance(from: CLLocation(latitude: to.latitude, longitude: to.longitude))
    }
}

extension RoutePlan {
    var segmentDistancesMeters: [CLLocationDistance] {
        zip(waypoints, waypoints.dropFirst()).map { first, second in
            let from = first.clCoordinate
            let to = second.clCoordinate
            guard CLLocationCoordinate2DIsValid(from), CLLocationCoordinate2DIsValid(to) else {
                return 0
            }
            return CLLocation(latitude: from.latitude, longitude: from.longitude)
                .distance(from: CLLocation(latitude: to.latitude, longitude: to.longitude))
        }
    }

    var totalDistanceMeters: CLLocationDistance {
        segmentDistancesMeters.reduce(0, +)
    }
}
