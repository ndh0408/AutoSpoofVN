import CoreLocation
import XCTest
@testable import LocationX

/// Kiem thu tang UI moi: hop dong dieu huong, dinh dang so lieu, va logic vet duong.
///
/// Ba nhom nay deu la logic THUAN — khong can dung SwiftUI view — nen kiem thu duoc
/// truc tiep va chay nhanh.
final class UILayerTests: XCTestCase {

    // MARK: - Hop dong dieu huong

    func testEveryTabHasTitleAndDistinctSymbols() {
        let tabs = AppTab.allCases
        XCTAssertEqual(tabs.count, 4)
        for tab in tabs {
            XCTAssertFalse(tab.title.isEmpty, "\(tab) thieu tieu de")
            XCTAssertFalse(tab.symbol.isEmpty, "\(tab) thieu icon")
            XCTAssertFalse(tab.selectedSymbol.isEmpty, "\(tab) thieu icon khi duoc chon")
        }
        XCTAssertEqual(Set(tabs.map(\.rawValue)).count, tabs.count, "rawValue phai duy nhat")
        XCTAssertEqual(Set(tabs.map(\.title)).count, tabs.count, "tieu de phai duy nhat")
    }

    func testTabRawValueRoundTrips() {
        for tab in AppTab.allCases {
            XCTAssertEqual(AppTab(rawValue: tab.rawValue), tab)
        }
        XCTAssertNil(AppTab(rawValue: "khong-ton-tai"))
    }

    /// Moi man hinh modal cua ban cu phai con mot `AppSheet` tuong ung.
    ///
    /// Day la luoi an toan cho cam ket zero-feature-loss: `MainViewV2` truoc day gan 12
    /// sheet, neu ban thiet ke lai bo sot mot cai thi test nay do.
    ///
    /// Hai case da roi khoi danh sach nay, va ca hai deu co ly do — them lai chung
    /// khong phai la cach sua neu test nay do:
    ///
    /// - `.settings`: khong mat, ma **doi cho**. Tab Cai dat truoc day mo mot man Cai
    ///   dat thu hai dang sheet; gio chinh tab la Cai dat, cac nhom tuy chon la trang
    ///   con day ra tu ngan xep cua no (`SimulationSettingsScreen`, `MapSettingsScreen`,
    ///   `BackgroundSettingsScreen`, `AboutScreen`).
    /// - `.deviceManager`: **da bo that**. No mo man ghep noi DVT, ma duong DVT bien mat
    ///   cung FFI theo yeu cau cua nguoi dung. Giu lai chi la dat mot nut khong bao gio
    ///   thanh cong truoc mat ho.
    func testAllLegacyModalScreensHaveASheetCase() {
        let required: [AppSheet] = [
            .routeBuilder, .scenarioStudio, .routineStudio,
            .history, .worldTravel, .diagnostics, .shadowrocketSetup, .bookmarks,
            .bypassTroubleshoot, .telemetryDetail, .manualCoordinate,
        ]
        // Identifiable theo chinh no => Set kiem tra duoc trung lap.
        XCTAssertEqual(Set(required).count, required.count, "co case bi khai bao trung")
        for sheet in required {
            XCTAssertEqual(sheet.id, sheet, "AppSheet.id phai la chinh no")
        }
    }

    @MainActor
    func testNavigatorPresentsAndDismissesSheet() {
        let navigator = AppNavigator()
        XCTAssertNil(navigator.presentedSheet)

        navigator.present(.diagnostics)
        XCTAssertEqual(navigator.presentedSheet, .diagnostics)

        // Mo lai dung sheet dang mo thi giu nguyen, khong nhay.
        navigator.present(.diagnostics)
        XCTAssertEqual(navigator.presentedSheet, .diagnostics)

        navigator.dismissSheet()
        XCTAssertNil(navigator.presentedSheet)
    }

    // MARK: - Nac bang duoi

    func testBottomSheetDetentHeightsAreOrderedAndBounded() {
        let available: CGFloat = 800
        let collapsed = BottomSheetDetent.collapsed.height(in: available)
        let expanded = BottomSheetDetent.expanded.height(in: available)

        XCTAssertLessThan(collapsed, expanded)
        XCTAssertLessThanOrEqual(expanded, available, "nac mo rong khong duoc cao hon khung")
        XCTAssertGreaterThan(collapsed, 0)

        // Man hinh rat thap van phai cho nac mo rong mot chieu cao dung duoc.
        XCTAssertGreaterThanOrEqual(BottomSheetDetent.expanded.height(in: 100), 320)
    }

    func testMapStyleKindCoversAllCases() {
        XCTAssertEqual(MapStyleKind.allCases.count, 3)
        for kind in MapStyleKind.allCases {
            XCTAssertFalse(kind.title.isEmpty)
            XCTAssertFalse(kind.symbol.isEmpty)
            XCTAssertEqual(MapStyleKind(rawValue: kind.rawValue), kind)
        }
    }

    // MARK: - Anh xa trang thai -> hinh anh

    /// Moi trang thai phai co CA icon lan mau: khong duoc chi dua vao mau de bao trang thai.
    func testEverySimulationStateHasSymbolAndTint() {
        let states: [SimulationState] = [
            .idle, .preparing, .running, .paused, .stopping, .completed, .failed("loi"),
        ]
        for state in states {
            XCTAssertFalse(state.symbolName.isEmpty, "\(state) thieu icon")
            XCTAssertFalse(state.displayName.isEmpty, "\(state) thieu nhan chu")
            _ = state.tint
        }
        // Chay va tam dung phai khac icon — day la khac biet nguoi dung doc nhanh nhat.
        XCTAssertNotEqual(SimulationState.running.symbolName, SimulationState.paused.symbolName)
    }

    func testDeviceStateTintsAreDefinedForAllCases() {
        let states: [DeviceConnectionState] = [
            .disconnected, .connecting, .connected(transport: "DVT"), .error("x"),
        ]
        for state in states {
            XCTAssertFalse(state.icon.isEmpty)
            XCTAssertFalse(state.displayName.isEmpty)
            _ = state.tint
        }
    }

    // MARK: - Dinh dang

    func testDistanceFormatting() {
        XCTAssertEqual(AppFormat.distance(0), "0 m")
        XCTAssertEqual(AppFormat.distance(950), "950 m")
        XCTAssertEqual(AppFormat.distance(1000), "1.0 km")
        XCTAssertEqual(AppFormat.distance(15_400), "15.4 km")
        // Gia tri am (do tru sai o dau nguon) khong duoc hien "-42 m".
        XCTAssertEqual(AppFormat.distance(-5), "0 m")
        XCTAssertEqual(AppFormat.distance(.nan), "—")
        XCTAssertEqual(AppFormat.distance(.infinity), "—")
    }

    func testDurationFormatting() {
        XCTAssertEqual(AppFormat.duration(0), "0:00")
        XCTAssertEqual(AppFormat.duration(65), "1:05")
        XCTAssertEqual(AppFormat.duration(3661), "1:01:01")
        XCTAssertEqual(AppFormat.duration(-10), "0:00")
        XCTAssertEqual(AppFormat.duration(.nan), "0:00")
    }

    func testPercentClampsToRange() {
        XCTAssertEqual(AppFormat.percent(0), "0%")
        XCTAssertEqual(AppFormat.percent(0.42), "42%")
        // Tranh gia tri roi dung .5: 0.685*100 ra 68.4999... trong nhi phan, va `%.0f`
        // lam tron half-to-even, nen ky vong "69%" la sai chu khong phai code sai.
        XCTAssertEqual(AppFormat.percent(0.5), "50%")
        XCTAssertEqual(AppFormat.percent(1), "100%")
        XCTAssertEqual(AppFormat.percent(2.5), "100%", "tien do > 1 phai bi kep lai")
        XCTAssertEqual(AppFormat.percent(-1), "0%")
    }

    /// Phuong huong phai dung o ca hai phia diem gap 0/360 va voi goc am.
    func testCardinalDirectionWrapsCorrectly() {
        XCTAssertEqual(AppFormat.cardinal(0), "B")
        XCTAssertEqual(AppFormat.cardinal(359), "B")
        XCTAssertEqual(AppFormat.cardinal(360), "B")
        XCTAssertEqual(AppFormat.cardinal(90), "Đ")
        XCTAssertEqual(AppFormat.cardinal(180), "N")
        XCTAssertEqual(AppFormat.cardinal(270), "T")
        XCTAssertEqual(AppFormat.cardinal(-90), "T", "goc am phai duoc chuan hoa")
        XCTAssertEqual(AppFormat.cardinal(720), "B")
    }

    func testCoordinateFormattingPrecision() {
        let coord = CLLocationCoordinate2D(latitude: 21.028500, longitude: 105.854200)
        XCTAssertEqual(AppFormat.coordinate(coord, precision: 4), "21.0285, 105.8542")
        XCTAssertEqual(AppFormat.coordinate(coord, precision: 2), "21.03, 105.85")
    }

    // MARK: - Vet duong tren ban do

    func testTrailIgnoresPointsCloserThanThreshold() {
        let trail = MapTrail(minimumSpacingMeters: 10, maximumPoints: 100)
        let origin = CLLocationCoordinate2D(latitude: 21.0285, longitude: 105.8542)

        XCTAssertTrue(trail.append(origin), "diem dau tien luon duoc nhan")
        XCTAssertEqual(trail.points.count, 1)

        // Xe dich ~1 m — duoi nguong, phai bi bo qua.
        let tiny = CLLocationCoordinate2D(latitude: 21.028509, longitude: 105.8542)
        XCTAssertFalse(trail.append(tiny))
        XCTAssertEqual(trail.points.count, 1, "nhieu GPS khong duoc sinh diem moi")

        // Xe dich ~55 m — tren nguong.
        let far = CLLocationCoordinate2D(latitude: 21.0290, longitude: 105.8542)
        XCTAssertTrue(trail.append(far))
        XCTAssertEqual(trail.points.count, 2)
    }

    func testTrailResetsOnTeleport() {
        let trail = MapTrail(minimumSpacingMeters: 4, maximumPoints: 100)
        trail.append(CLLocationCoordinate2D(latitude: 21.0285, longitude: 105.8542)) // Ha Noi
        trail.append(CLLocationCoordinate2D(latitude: 21.0300, longitude: 105.8560))
        XCTAssertEqual(trail.points.count, 2)

        // Nhay sang Tokyo: khong duoc noi mot duong thang vat ngang ban do.
        trail.append(CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503))
        XCTAssertEqual(trail.points.count, 1, "teleport phai bat dau vet moi")
        XCTAssertFalse(trail.isDrawable)
    }

    func testTrailDecimatesWhenExceedingCap() {
        let trail = MapTrail(minimumSpacingMeters: 0, maximumPoints: 10)
        for i in 0..<11 {
            trail.append(CLLocationCoordinate2D(latitude: 21.0 + Double(i) * 0.001, longitude: 105.0))
        }
        XCTAssertLessThanOrEqual(trail.points.count, 10, "phai giam mau khi cham tran")
        XCTAssertGreaterThan(trail.points.count, 1)
    }

    func testTrailRejectsInvalidCoordinates() {
        let trail = MapTrail()
        XCTAssertFalse(trail.append(CLLocationCoordinate2D(latitude: 999, longitude: 999)))
        XCTAssertTrue(trail.points.isEmpty)
    }

    func testTrailClear() {
        let trail = MapTrail(minimumSpacingMeters: 0)
        trail.append(CLLocationCoordinate2D(latitude: 1, longitude: 1))
        trail.append(CLLocationCoordinate2D(latitude: 1.001, longitude: 1))
        XCTAssertTrue(trail.isDrawable)
        trail.clear()
        XCTAssertTrue(trail.points.isEmpty)
        XCTAssertFalse(trail.isDrawable)
    }

    // MARK: - Khoang cach camera

    func testCameraDistanceScalesWithSpeed() {
        let walking = MapCameraDistance.forSpeed(3, isFlying: false)
        let driving = MapCameraDistance.forSpeed(50, isFlying: false)
        let highway = MapCameraDistance.forSpeed(110, isFlying: false)
        let flying = MapCameraDistance.forSpeed(850, isFlying: true)

        XCTAssertLessThan(walking, driving)
        XCTAssertLessThan(driving, highway)
        XCTAssertLessThan(highway, flying)
    }
}
