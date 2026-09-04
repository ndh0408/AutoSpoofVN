import MapKit
import SwiftUI

/// Kieu ban do.
///
/// Ton tai vi `MapStyle` cua MapKit **khong conform `Equatable`** — khong the so sanh,
/// khong the luu vao `@State` roi switch. Enum nay theo doi lua chon, `mapStyle` suy ra tu no.
enum MapStyleKind: String, CaseIterable, Identifiable, Hashable {
    case standard
    case hybrid
    case imagery

    var id: String { rawValue }

    var mapStyle: MapStyle {
        switch self {
        case .standard: return .standard(elevation: .realistic)
        case .hybrid:   return .hybrid(elevation: .realistic)
        case .imagery:  return .imagery(elevation: .realistic)
        }
    }

    var title: String {
        switch self {
        case .standard: return L("map.style.standard")
        case .hybrid:   return L("map.style.hybrid")
        case .imagery:  return L("map.style.imagery")
        }
    }

    var symbol: String {
        switch self {
        case .standard: return "map"
        case .hybrid:   return "globe.americas"
        case .imagery:  return "globe.americas.fill"
        }
    }
}

/// Khoang cach camera theo boi canh — bay thi lui ra rat xa, di bo thi ap sat.
enum MapCameraDistance {
    static let flight: CLLocationDistance = 250_000
    static let driving: CLLocationDistance = 3_000
    static let walking: CLLocationDistance = 1_200
    static let pitched: CLLocationDistance = 1_600

    /// Chon khoang cach hop ly tu toc do hien tai.
    static func forSpeed(_ kmh: Double, isFlying: Bool) -> CLLocationDistance {
        if isFlying { return flight }
        if kmh > 90 { return 8_000 }
        if kmh > 25 { return driving }
        return walking
    }
}
