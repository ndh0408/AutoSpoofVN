import CoreLocation
import MapKit
import SwiftUI

// MARK: - RouteShapePreview

/// Vẽ hình dạng tuyến bằng vector thuần.
///
/// Hiện **ngay lập tức** và không cần mạng — nên danh sách tuyến không bao giờ có ô trống
/// chờ ảnh. `MKMapSnapshotter` cần mạng và mất vài trăm ms; nó chỉ chồng lên trên khi xong.
struct RouteShapePreview: View {
    let coordinates: [CLLocationCoordinate2D]
    var lineWidth: CGFloat = 2.5
    var tint: Color = AppColor.mapRoute
    var showsEndpoints: Bool = true

    var body: some View {
        Canvas { context, size in
            let points = Self.normalizedPoints(coordinates, in: size, inset: lineWidth * 2 + 4)
            guard points.count >= 2 else { return }

            var path = Path()
            path.addLines(points)

            // Viền sáng phía dưới để tuyến vẫn tách khỏi nền ở cả hai chế độ sáng/tối.
            context.stroke(path, with: .color(.white.opacity(0.5)),
                           style: StrokeStyle(lineWidth: lineWidth + 1.5, lineCap: .round, lineJoin: .round))
            context.stroke(path, with: .color(tint),
                           style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))

            guard showsEndpoints, let start = points.first, let end = points.last else { return }
            let r = lineWidth * 1.6
            context.fill(Path(ellipseIn: CGRect(x: start.x - r, y: start.y - r, width: r * 2, height: r * 2)),
                         with: .color(AppColor.success))
            context.fill(Path(ellipseIn: CGRect(x: end.x - r, y: end.y - r, width: r * 2, height: r * 2)),
                         with: .color(AppColor.danger))
        }
        .accessibilityHidden(true)
    }

    /// Chiếu toạ độ vào khung vẽ, giữ đúng tỉ lệ hình dạng.
    ///
    /// Kinh độ được nhân `cos(vĩ độ)`: một độ kinh ở Hà Nội chỉ dài bằng ~93% một độ vĩ,
    /// bỏ qua thì tuyến đông–tây bị kéo dãn trông sai hẳn.
    static func normalizedPoints(_ coordinates: [CLLocationCoordinate2D],
                                 in size: CGSize,
                                 inset: CGFloat) -> [CGPoint] {
        let valid = coordinates.filter { CLLocationCoordinate2DIsValid($0) }
        guard valid.count >= 2, size.width > inset * 2, size.height > inset * 2 else { return [] }

        let midLatitude = (valid.map(\.latitude).min()! + valid.map(\.latitude).max()!) / 2
        let lonScale = max(0.05, cos(midLatitude * .pi / 180))

        let xs = valid.map { $0.longitude * lonScale }
        let ys = valid.map(\.latitude)
        let minX = xs.min()!, maxX = xs.max()!
        let minY = ys.min()!, maxY = ys.max()!

        let spanX = max(maxX - minX, 1e-9)
        let spanY = max(maxY - minY, 1e-9)

        let drawW = size.width - inset * 2
        let drawH = size.height - inset * 2
        // Một hệ số cho cả hai trục => không méo hình.
        let scale = min(drawW / spanX, drawH / spanY)

        // Căn giữa phần đã vẽ trong khung.
        let offsetX = inset + (drawW - spanX * scale) / 2
        let offsetY = inset + (drawH - spanY * scale) / 2

        return valid.map { coord in
            let x = offsetX + (coord.longitude * lonScale - minX) * scale
            // Vĩ độ tăng lên phía bắc, toạ độ màn hình tăng xuống dưới => đo từ maxY.
            let y = offsetY + (maxY - coord.latitude) * scale
            return CGPoint(x: x, y: y)
        }
    }
}

// MARK: - RouteThumbnail

/// Ảnh thu nhỏ của tuyến: nền bản đồ thật (khi tải được) + hình tuyến vẽ chồng lên.
struct RouteThumbnail: View {
    let coordinates: [CLLocationCoordinate2D]
    var cacheKey: String
    var cornerRadius: CGFloat = AppRadius.md

    @Environment(\.colorScheme) private var colorScheme
    @State private var snapshot: UIImage?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let snapshot {
                    Image(uiImage: snapshot)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                } else {
                    AppColor.surfaceTertiary
                }
                RouteShapePreview(coordinates: coordinates)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(AppColor.hairline, lineWidth: 0.5)
            )
            .task(id: taskID(size: geo.size)) {
                snapshot = await RouteSnapshotCache.shared.snapshot(
                    for: coordinates, size: geo.size, key: cacheKey, dark: colorScheme == .dark
                )
            }
        }
        .accessibilityHidden(true)
    }

    private func taskID(size: CGSize) -> String {
        "\(cacheKey)-\(Int(size.width))x\(Int(size.height))-\(colorScheme == .dark ? "d" : "l")"
    }
}

// MARK: - Snapshot cache

/// Bộ nhớ đệm ảnh bản đồ.
///
/// `MKMapSnapshotter` tốn mạng và CPU; nếu không đệm thì mỗi lần cuộn danh sách lại chụp
/// lại toàn bộ. `NSCache` tự nhả khi máy thiếu bộ nhớ.
@MainActor
final class RouteSnapshotCache {
    static let shared = RouteSnapshotCache()

    private let cache = NSCache<NSString, UIImage>()
    /// Các key đang chụp dở — chặn hai thẻ cùng key chụp song song.
    private var inFlight: Set<String> = []

    private init() {
        cache.countLimit = 60
    }

    func snapshot(for coordinates: [CLLocationCoordinate2D],
                  size: CGSize,
                  key: String,
                  dark: Bool) async -> UIImage? {
        guard size.width > 8, size.height > 8 else { return nil }
        let valid = coordinates.filter { CLLocationCoordinate2DIsValid($0) }
        guard valid.count >= 2 else { return nil }

        let fullKey = "\(key)-\(Int(size.width))x\(Int(size.height))-\(dark ? "d" : "l")" as NSString
        if let cached = cache.object(forKey: fullKey) { return cached }
        guard !inFlight.contains(fullKey as String) else { return nil }
        inFlight.insert(fullKey as String)
        defer { inFlight.remove(fullKey as String) }

        let options = MKMapSnapshotter.Options()
        options.region = Self.region(fitting: valid)
        options.size = size
        options.traitCollection = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
        options.pointOfInterestFilter = .excludingAll
        options.showsBuildings = false

        do {
            let snapshot = try await MKMapSnapshotter(options: options).start()
            cache.setObject(snapshot.image, forKey: fullKey)
            return snapshot.image
        } catch {
            // Không mạng / không Metal: giữ nguyên bản vẽ vector, không coi là lỗi.
            return nil
        }
    }

    /// Vùng bản đồ bao trọn tuyến, chừa lề để tuyến không chạm mép.
    static func region(fitting coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        let lats = coordinates.map(\.latitude)
        let lons = coordinates.map(\.longitude)
        let minLat = lats.min()!, maxLat = lats.max()!
        let minLon = lons.min()!, maxLon = lons.max()!

        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                            longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.35, 0.004),
            longitudeDelta: max((maxLon - minLon) * 1.35, 0.004)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}

#Preview("Route shape") {
    let coords: [CLLocationCoordinate2D] = (0..<40).map { i in
        let t = Double(i) / 39
        return CLLocationCoordinate2D(latitude: 21.02 + t * 0.05 + sin(t * 8) * 0.006,
                                      longitude: 105.84 + t * 0.07)
    }
    return RouteShapePreview(coordinates: coords)
        .frame(width: 200, height: 120)
        .background(AppColor.surfaceTertiary)
        .padding()
}
