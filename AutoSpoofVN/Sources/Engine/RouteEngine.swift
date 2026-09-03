//
//  RouteEngine.swift
//  AutoSpoofVN
//
//  Unified Route Provider abstraction (MapKit, OSRM, Direct Fallback) and Route Studio services.
//

import CoreLocation
import Foundation
import MapKit

public protocol RouteProviderProtocol: AnyObject {
    var name: String { get }
    func calculateRoute(
        origin: CLLocationCoordinate2D,
        destination: CLLocationCoordinate2D,
        travelMode: TravelMode
    ) async throws -> RouteCalculationResult
}

public struct RouteCalculationResult {
    public var coordinates: [CLLocationCoordinate2D]
    public var distanceMeters: CLLocationDistance
    public var expectedDurationSeconds: TimeInterval
    public var isRealRoad: Bool
    public var providerName: String

    public init(
        coordinates: [CLLocationCoordinate2D],
        distanceMeters: CLLocationDistance,
        expectedDurationSeconds: TimeInterval,
        isRealRoad: Bool,
        providerName: String
    ) {
        self.coordinates = coordinates
        self.distanceMeters = distanceMeters
        self.expectedDurationSeconds = expectedDurationSeconds
        self.isRealRoad = isRealRoad
        self.providerName = providerName
    }
}

public final class MapKitRouteProvider: RouteProviderProtocol {
    public let name = "Apple Maps (MKDirections)"

    public init() {}

    public func calculateRoute(
        origin: CLLocationCoordinate2D,
        destination: CLLocationCoordinate2D,
        travelMode: TravelMode
    ) async throws -> RouteCalculationResult {
        let result = await RouteProvider.shared.resolveRoute(
            named: "Lộ trình di chuyển",
            from: origin,
            to: destination,
            transportType: .automobile,
            speedKmh: travelMode.defaultProfile.cruisingSpeedKmh,
            sampleSpacingMeters: travelMode == .walking ? 15.0 : 35.0
        )
        let coords: [CLLocationCoordinate2D] = result.plan.waypoints.map { $0.clCoordinate }
        let isReal = result.source == .mapKit
        return RouteCalculationResult(
            coordinates: coords,
            distanceMeters: result.distanceMeters,
            expectedDurationSeconds: result.expectedTravelTime ?? (result.distanceMeters / 12.0),
            isRealRoad: isReal,
            providerName: isReal ? "Apple Maps" : "Nội suy đường thẳng (Fallback)"
        )
    }
}

public final class OfflineDirectRouteProvider: RouteProviderProtocol {
    public let name = "Nội suy đường thẳng trực tiếp"

    public init() {}

    public func calculateRoute(
        origin: CLLocationCoordinate2D,
        destination: CLLocationCoordinate2D,
        travelMode: TravelMode
    ) async throws -> RouteCalculationResult {
        let spacing: Double = travelMode == .walking ? 10.0 : 30.0
        let coords = RouteProvider.straightLineCoordinates(from: origin, to: destination, spacingMeters: spacing)
        let dist = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
            .distance(from: CLLocation(latitude: destination.latitude, longitude: destination.longitude))
        let speedMps = max(1.0, travelMode.defaultProfile.cruisingSpeedKmh / 3.6)
        return RouteCalculationResult(
            coordinates: coords,
            distanceMeters: dist,
            expectedDurationSeconds: dist / speedMps,
            isRealRoad: false,
            providerName: name
        )
    }
}

public struct LocationSearchResult: Identifiable, Hashable {
    public var id = UUID()
    public var title: String
    public var subtitle: String
    public var coordinate: CLLocationCoordinate2D

    public func hash(into hasher: inout Hasher) {
        hasher.combine(title)
        hasher.combine(coordinate.latitude)
        hasher.combine(coordinate.longitude)
    }

    public static func == (lhs: LocationSearchResult, rhs: LocationSearchResult) -> Bool {
        lhs.title == rhs.title &&
        abs(lhs.coordinate.latitude - rhs.coordinate.latitude) < 1e-6 &&
        abs(lhs.coordinate.longitude - rhs.coordinate.longitude) < 1e-6
    }
}

@MainActor
public final class RouteSearchService: ObservableObject {
    public static let shared = RouteSearchService()

    @Published public var searchResults: [LocationSearchResult] = []
    @Published public var isSearching: Bool = false

    private var completer: MKLocalSearchCompleter?

    public init() {}

    public func search(query: String, near coordinate: CLLocationCoordinate2D? = nil) async {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchResults = []
            return
        }
        isSearching = true
        defer { isSearching = false }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        if let coordinate {
            request.region = MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: 50_000,
                longitudinalMeters: 50_000
            )
        }

        let search = MKLocalSearch(request: request)
        do {
            let response = try await search.start()
            self.searchResults = response.mapItems.map { item in
                LocationSearchResult(
                    title: item.name ?? "Địa điểm",
                    subtitle: item.placemark.title ?? "",
                    coordinate: item.placemark.coordinate
                )
            }
        } catch {
            self.searchResults = []
        }
    }
}
