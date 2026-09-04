import XCTest
import CoreLocation
@testable import LocationX

/// Kiểm thử phần logic thuần, chạy được không cần thiết bị và không cần thư viện FFI.
///
/// Ba nhóm dưới đây bám đúng ba lỗi từng lọt qua mà compiler không bắt được:
/// header WAV sai, phân xử nguồn toạ độ, và nội suy cầu tròn.
final class SilentWavTests: XCTestCase {

    private func u32(_ d: Data, _ o: Int) -> UInt32 {
        UInt32(d[o]) | UInt32(d[o + 1]) << 8 | UInt32(d[o + 2]) << 16 | UInt32(d[o + 3]) << 24
    }
    private func u16(_ d: Data, _ o: Int) -> UInt16 {
        UInt16(d[o]) | UInt16(d[o + 1]) << 8
    }

    /// Bản đầu để trống bốn trường này, khiến AVAudioPlayer ném lỗi 1685348671 và
    /// toàn bộ cơ chế chạy ngầm im lặng không hoạt động.
    func testHeaderFieldsAreFilledIn() {
        let d = SpoofEngine.makeSilentWavData(seconds: 1.0)
        XCTAssertGreaterThan(d.count, 44, "phải có cả header lẫn dữ liệu mẫu")

        XCTAssertEqual(Array(d[0..<4]), Array("RIFF".utf8))
        XCTAssertEqual(Array(d[8..<12]), Array("WAVE".utf8))
        XCTAssertEqual(Array(d[12..<16]), Array("fmt ".utf8))
        XCTAssertEqual(Array(d[36..<40]), Array("data".utf8))

        XCTAssertEqual(u32(d, 4), UInt32(d.count - 8), "ChunkSize")
        XCTAssertEqual(u32(d, 16), 16, "Subchunk1Size cho PCM")
        XCTAssertEqual(u16(d, 20), 1, "AudioFormat = PCM")
        XCTAssertEqual(u16(d, 22), 1, "mono")
        XCTAssertEqual(u32(d, 24), 44_100, "SampleRate")
        XCTAssertEqual(u32(d, 28), 88_200, "ByteRate = 44100 * 1 * 16/8")
        XCTAssertEqual(u16(d, 32), 2, "BlockAlign = 1 * 16/8")
        XCTAssertEqual(u16(d, 34), 16, "BitsPerSample")
        XCTAssertEqual(u32(d, 40), UInt32(d.count - 44), "Subchunk2Size")
    }

    func testAllSamplesAreSilent() {
        let d = SpoofEngine.makeSilentWavData(seconds: 0.25)
        XCTAssertTrue(d[44...].allSatisfy { $0 == 0 }, "mọi mẫu phải bằng 0")
    }

    func testDurationScalesWithSeconds() {
        let quarter = SpoofEngine.makeSilentWavData(seconds: 0.25)
        let one = SpoofEngine.makeSilentWavData(seconds: 1.0)
        XCTAssertEqual(one.count - 44, (quarter.count - 44) * 4)
    }

    /// Thời lượng 0 hoặc âm phải vẫn sinh ra file hợp lệ, không phải header cụt.
    func testDegenerateDurationStillValid() {
        for seconds in [0.0, -5.0] {
            let d = SpoofEngine.makeSilentWavData(seconds: seconds)
            XCTAssertGreaterThan(d.count, 44)
            XCTAssertEqual(u32(d, 4), UInt32(d.count - 8))
        }
    }
}

final class SpoofSourceTests: XCTestCase {

    /// Thứ tự ưu tiên là hợp đồng giữa Engine và FlightManager. Đổi thứ tự này mà
    /// không đổi cả hai bên sẽ gây tranh chấp ghi toạ độ.
    func testPriorityOrder() {
        XCTAssertGreaterThan(SpoofSource.manual.priority, SpoofSource.flight.priority)
        XCTAssertGreaterThan(SpoofSource.flight.priority, SpoofSource.routine.priority)
    }

    func testEverySourceHasDistinctPriority() {
        let priorities = SpoofSource.allCases.map(\.priority)
        XCTAssertEqual(Set(priorities).count, SpoofSource.allCases.count)
    }

    func testDisplayNamesAreNotEmpty() {
        for s in SpoofSource.allCases {
            XCTAssertFalse(s.displayName.isEmpty, "\(s.rawValue) thiếu tên hiển thị")
        }
    }
}

final class GeodesicMathTests: XCTestCase {

    private let hanoi = CLLocationCoordinate2D(latitude: 21.0285, longitude: 105.8542)
    private let saigon = CLLocationCoordinate2D(latitude: 10.8231, longitude: 106.6297)

    func testDistanceHanoiToSaigon() {
        let km = GeodesicMath.distanceKm(from: hanoi, to: saigon)
        // Khoảng cách đường chim bay thực tế ~1140 km.
        XCTAssertEqual(km, 1140, accuracy: 30)
    }

    func testDistanceToSelfIsZero() {
        XCTAssertEqual(GeodesicMath.distanceKm(from: hanoi, to: hanoi), 0, accuracy: 1e-6)
    }

    func testInterpolationEndpoints() {
        let a = GeodesicMath.interpolateGreatCircle(from: hanoi, to: saigon, fraction: 0)
        XCTAssertEqual(a.latitude, hanoi.latitude, accuracy: 1e-9)
        XCTAssertEqual(a.longitude, hanoi.longitude, accuracy: 1e-9)

        let b = GeodesicMath.interpolateGreatCircle(from: hanoi, to: saigon, fraction: 1)
        XCTAssertEqual(b.latitude, saigon.latitude, accuracy: 1e-9)
        XCTAssertEqual(b.longitude, saigon.longitude, accuracy: 1e-9)
    }

    /// Điểm giữa phải cách đều hai đầu — đây là điều nội suy tuyến tính theo kinh vĩ độ
    /// KHÔNG bảo đảm trên quãng đường dài.
    func testMidpointIsEquidistant() {
        let mid = GeodesicMath.interpolateGreatCircle(from: hanoi, to: saigon, fraction: 0.5)
        let d1 = GeodesicMath.distanceKm(from: hanoi, to: mid)
        let d2 = GeodesicMath.distanceKm(from: mid, to: saigon)
        XCTAssertEqual(d1, d2, accuracy: 1.0)
    }

    /// Nội suy phải bám cung lớn, nên tổng hai chặng bằng đúng chặng thẳng.
    func testInterpolationStaysOnGreatCircle() {
        let total = GeodesicMath.distanceKm(from: hanoi, to: saigon)
        var walked = 0.0
        var previous = hanoi
        for step in 1...20 {
            let p = GeodesicMath.interpolateGreatCircle(
                from: hanoi, to: saigon, fraction: Double(step) / 20.0)
            walked += GeodesicMath.distanceKm(from: previous, to: p)
            previous = p
        }
        XCTAssertEqual(walked, total, accuracy: 1.0)
    }

    /// Bay qua kinh tuyến đổi ngày: kinh độ phải nằm trong [-180, 180] và không
    /// nhảy vòng ngược qua nửa kia địa cầu.
    func testCrossingAntimeridian() {
        let tokyo = CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503)
        let losAngeles = CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437)
        let total = GeodesicMath.distanceKm(from: tokyo, to: losAngeles)
        XCTAssertEqual(total, 8815, accuracy: 100)

        for step in 0...10 {
            let p = GeodesicMath.interpolateGreatCircle(
                from: tokyo, to: losAngeles, fraction: Double(step) / 10.0)
            XCTAssertTrue(CLLocationCoordinate2DIsValid(p))
            XCTAssertLessThanOrEqual(abs(p.longitude), 180.0)
        }
    }
}

final class CoordinateCodableTests: XCTestCase {

    func testRoundTrip() throws {
        let original = CoordinateCodable(latitude: 21.0285, longitude: 105.8542)
        let decoded = try JSONDecoder().decode(
            CoordinateCodable.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(original, decoded)
    }

    /// Toạ độ (0, 0) là hợp lệ. Bản cũ dùng `!= 0.0` để dò "chưa lưu" nên
    /// mọi điểm trên xích đạo và kinh tuyến gốc đều bị bỏ qua.
    func testZeroCoordinateIsValid() {
        let zero = CoordinateCodable(latitude: 0, longitude: 0)
        XCTAssertTrue(CLLocationCoordinate2DIsValid(zero.clCoordinate))
    }

    func testBookmarkCarriesCoordinate() {
        let b = PlaceBookmark(name: "Hồ Hoàn Kiếm", latitude: 21.0285, longitude: 105.8542)
        XCTAssertEqual(b.coordinate.latitude, 21.0285, accuracy: 1e-9)
        XCTAssertEqual(b.coordinate.longitude, 105.8542, accuracy: 1e-9)
    }
}
