import CoreLocation
import Observation

/// Vet duong da di, do tang UI so huu.
///
/// Khac ban cu (`TrailOverlay.sampleTrail`) o mot diem quan trong: chi them diem khi da
/// **di du xa**, thay vi them moi lan toa do doi. Coordinator phat toa do ~10 Hz va co
/// nhieu GPS, nen ban cu them 10 diem/giay ngay ca khi dung yen — `MapPolyline` phai ve
/// lai ca nghin diem moi lan. Cong them nguong khoang cach, mot phien dai van muot.
@Observable
final class MapTrail {
    /// Cac diem dang duoc ve.
    private(set) var points: [CLLocationCoordinate2D] = []

    /// Khoang cach toi thieu giua hai diem lien tiep (met).
    /// 4 m lon hon bien do nhieu mac dinh (3 m) nen dung yen se khong sinh diem moi.
    private let minimumSpacingMeters: CLLocationDistance
    /// Tran so diem. Cham tran thi giam mau con mot nua. Doi duoc tu Cai dat.
    var maximumPoints: Int
    /// Nguoi dung co bat vet duong khong. Tat thi khong tich luy diem nao.
    var isEnabled: Bool = true

    init(minimumSpacingMeters: CLLocationDistance = 4, maximumPoints: Int = 1000) {
        self.minimumSpacingMeters = minimumSpacingMeters
        self.maximumPoints = maximumPoints
    }

    /// Them mot toa do. Tra ve `true` neu vet duong that su thay doi.
    @discardableResult
    func append(_ coordinate: CLLocationCoordinate2D) -> Bool {
        guard isEnabled else { return false }
        guard CLLocationCoordinate2DIsValid(coordinate) else { return false }

        if let last = points.last {
            let distance = CLLocation(latitude: last.latitude, longitude: last.longitude)
                .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
            guard distance >= minimumSpacingMeters else { return false }

            // Nhay qua nua vong Trai Dat = doi vi tri tuc thi (teleport), khong phai di chuyen.
            // Noi hai diem do bang mot duong thang la ve mot duong bay ngang qua ban do.
            if distance > 50_000 {
                points = [coordinate]
                return true
            }
        }

        points.append(coordinate)

        if points.count > maximumPoints {
            // Giu lai moi diem thu hai — hinh dang tuyen giu nguyen, so diem giam mot nua.
            points = stride(from: 0, to: points.count, by: 2).map { points[$0] }
        }
        return true
    }

    func clear() {
        points.removeAll(keepingCapacity: true)
    }

    /// Chi ve khi co it nhat hai diem.
    var isDrawable: Bool { points.count >= 2 }
}
