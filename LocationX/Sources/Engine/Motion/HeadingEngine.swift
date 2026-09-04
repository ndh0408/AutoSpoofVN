import CoreLocation
import Foundation

/// Quản lý heading riêng — mượt, không giật, xử lý 0°/360° và dateline.
struct HeadingEngine {
    private(set) var currentHeading: Double = 0
    private var previousCoordinate: CLLocationCoordinate2D?
    private let smoothingFactor: Double

    init(smoothingFactor: Double = 0.15) {
        self.smoothingFactor = smoothingFactor
    }

    /// Cập nhật heading từ vị trí mới. Trả về heading mượt.
    mutating func update(with coordinate: CLLocationCoordinate2D) -> Double {
        defer { previousCoordinate = coordinate }

        guard let prev = previousCoordinate else {
            return currentHeading
        }

        let distance = MotionEngine.haversineDistance(from: prev, to: coordinate)
        guard distance > 0.5 else { return currentHeading } // bỏ qua nếu quá gần

        let target = MotionEngine.bearing(from: prev, to: coordinate)
        currentHeading = MotionEngine.smoothHeading(from: currentHeading, to: target, factor: smoothingFactor)
        return currentHeading
    }

    mutating func reset() {
        currentHeading = 0
        previousCoordinate = nil
    }

    var cardinalDirection: String {
        // Chu cai huong khac nhau theo ngon ngu: B/Đ/N/T so voi N/E/S/W.
        let directions = [L("cardinal.n"), L("cardinal.ne"), L("cardinal.e"), L("cardinal.se"),
                          L("cardinal.s"), L("cardinal.sw"), L("cardinal.w"), L("cardinal.nw")]
        let index = Int((currentHeading + 22.5).truncatingRemainder(dividingBy: 360) / 45)
        return directions[max(0, min(index, 7))]
    }
}
