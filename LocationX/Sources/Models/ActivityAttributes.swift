//
//  ActivityAttributes.swift
//  LocationX
//
//  Cau truc du lieu cho Live Activity va Dynamic Island.
//

import ActivityKit
import Foundation

/// Dữ liệu Live Activity.
///
/// **Mọi chuỗi ở đây đã được bản địa hoá sẵn bởi ứng dụng.** Widget extension chỉ biên
/// dịch file này chứ không có `LocalizationManager` hay thư mục `.lproj`, nên nếu widget
/// tự viết chữ thì chữ đó vĩnh viễn một thứ tiếng. Cho app tính sẵn rồi truyền sang là
/// cách duy nhất để Live Activity đổi theo ngôn ngữ người dùng chọn.
struct SpoofActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // MARK: Trạng thái

        /// Ví dụ "Đang mô phỏng" / "Simulating". Đã bản địa hoá.
        var stateName: String
        /// Dòng mô tả phụ. Đã bản địa hoá.
        var statusDescription: String
        /// Nhãn ngắn cho chấm trạng thái: "HOẠT ĐỘNG" / "TẠM DỪNG". Đã bản địa hoá.
        var statusLabel: String = ""
        /// Nguồn đang giữ quyền, đã bản địa hoá.
        var activeSource: String
        /// Người dùng đã khôi phục GPS thật.
        var isHalted: Bool
        /// Đang thực sự di chuyển (khác với tạm dừng).
        var isRunning: Bool = true

        // MARK: Số liệu

        var speedKmh: Double
        var coordinateText: String
        /// Độ cao, chỉ có khi đang bay.
        var altitudeMeters: Double?
        /// Giờ đến dự kiến, đã định dạng theo locale của app.
        var etaText: String?

        // MARK: Chuyến bay / tuyến đường

        var flightNumber: String?
        var flightProgress: Double?
        /// "HAN → NRT" hoặc tên tuyến đường đang chạy.
        var routeText: String?

        /// Tiến độ dạng chữ, ví dụ "68%". Widget không tự định dạng để tránh lệch locale.
        var progressText: String?
    }

    var appName: String
}
