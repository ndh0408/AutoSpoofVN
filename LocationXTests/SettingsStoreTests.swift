import XCTest
@testable import LocationX

/// Kiểm thử lớp cài đặt.
///
/// Trọng tâm là phép đổi Hz → chu kỳ: đây là chỗ dễ sai âm thầm nhất, vì một giá trị 0
/// hoặc quá lớn sẽ tạo ra timer chạy vô hạn hoặc không bao giờ chạy, mà không có lỗi nào
/// hiện ra.
final class SettingsStoreTests: XCTestCase {

    private func makeSettings() -> PersistenceManager.AppSettings {
        PersistenceManager.AppSettings()
    }

    // MARK: - Nhịp gửi thiết bị

    func testDeviceUpdateIntervalConvertsHzToSeconds() {
        var s = makeSettings()
        s.deviceUpdateRateHz = 1.0
        XCTAssertEqual(s.deviceUpdateIntervalSeconds, 1.0, accuracy: 0.0001)
        s.deviceUpdateRateHz = 0.5
        XCTAssertEqual(s.deviceUpdateIntervalSeconds, 2.0, accuracy: 0.0001)
        s.deviceUpdateRateHz = 5.0
        XCTAssertEqual(s.deviceUpdateIntervalSeconds, 0.2, accuracy: 0.0001)
    }

    /// 0 Hz nghĩa là "chia cho 0" — phải trả mặc định an toàn chứ không phải vô cực.
    func testDeviceUpdateIntervalHandlesZeroAndNegative() {
        var s = makeSettings()
        s.deviceUpdateRateHz = 0
        XCTAssertEqual(s.deviceUpdateIntervalSeconds, 20)
        s.deviceUpdateRateHz = -3
        XCTAssertEqual(s.deviceUpdateIntervalSeconds, 20)
    }

    func testDeviceUpdateIntervalIsClamped() {
        var s = makeSettings()
        s.deviceUpdateRateHz = 10_000       // rất nhanh -> phải bị chặn ở 0.2s
        XCTAssertEqual(s.deviceUpdateIntervalSeconds, 0.2, accuracy: 0.0001)
        s.deviceUpdateRateHz = 0.0001       // rất chậm -> phải bị chặn ở 60s
        XCTAssertEqual(s.deviceUpdateIntervalSeconds, 60, accuracy: 0.0001)
    }

    // MARK: - Nhịp tick mô phỏng

    func testSimulationTickIntervalConvertsAndClamps() {
        var s = makeSettings()
        s.simulationTickRateHz = 10
        XCTAssertEqual(s.simulationTickIntervalSeconds, 0.1, accuracy: 0.0001)
        s.simulationTickRateHz = 0
        XCTAssertEqual(s.simulationTickIntervalSeconds, 0.1, accuracy: 0.0001)
        s.simulationTickRateHz = 1000       // chặn ở 50 Hz
        XCTAssertEqual(s.simulationTickIntervalSeconds, 0.02, accuracy: 0.0001)
        s.simulationTickRateHz = 0.1        // chặn ở 1 Hz
        XCTAssertEqual(s.simulationTickIntervalSeconds, 1.0, accuracy: 0.0001)
    }

    /// Chu kỳ tick phải luôn dương — một giá trị 0 sẽ biến vòng lặp 10 Hz thành vòng lặp
    /// bận, treo main actor.
    func testTickIntervalIsAlwaysPositive() {
        var s = makeSettings()
        for hz in [-100.0, -1.0, 0.0, 0.001, 1.0, 60.0, 1e9] {
            s.simulationTickRateHz = hz
            XCTAssertGreaterThan(s.simulationTickIntervalSeconds, 0, "hz=\(hz)")
            XCTAssertLessThanOrEqual(s.simulationTickIntervalSeconds, 1.0, "hz=\(hz)")
        }
    }

    // MARK: - Giao diện

    @MainActor
    func testAppearanceMapsToColorScheme() {
        let store = AppSettingsStore.shared
        let original = store.settings

        store.settings.appearance = "light"
        XCTAssertEqual(store.preferredColorScheme, .light)
        store.settings.appearance = "dark"
        XCTAssertEqual(store.preferredColorScheme, .dark)
        store.settings.appearance = "system"
        XCTAssertNil(store.preferredColorScheme)
        store.settings.appearance = "gia-tri-la"
        XCTAssertNil(store.preferredColorScheme, "giá trị lạ phải lùi về theo hệ thống")

        store.settings = original
    }

    // MARK: - Lưu trữ

    func testAppSettingsRoundTripsThroughCodable() throws {
        var s = makeSettings()
        s.appearance = "dark"
        s.trailMaxPoints = 250
        s.deviceUpdateRateHz = 2.5
        s.defaultTravelMode = .motorcycle
        s.noiseConfig = .heavy

        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(PersistenceManager.AppSettings.self, from: data)

        XCTAssertEqual(back.appearance, "dark")
        XCTAssertEqual(back.trailMaxPoints, 250)
        XCTAssertEqual(back.deviceUpdateRateHz, 2.5)
        XCTAssertEqual(back.defaultTravelMode, .motorcycle)
        XCTAssertEqual(back.noiseConfig.radiusMeters, GPSNoiseConfig.heavy.radiusMeters)
    }

    /// Mặc định phải hợp lý ngay cả khi chưa ai chỉnh gì.
    func testDefaultsAreSane() {
        let s = makeSettings()
        XCTAssertGreaterThan(s.deviceUpdateIntervalSeconds, 0)
        XCTAssertGreaterThan(s.simulationTickIntervalSeconds, 0)
        XCTAssertGreaterThan(s.trailMaxPoints, 0)
        XCTAssertGreaterThan(s.heartbeatIntervalSeconds, 0)
        XCTAssertTrue(s.noiseConfig.enabled)
    }
}
