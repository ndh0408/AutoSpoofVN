import Foundation

/// Timer vẫn chạy trong lúc người dùng đang cuộn.
///
/// `Timer.scheduledTimer(...)` gắn vào RunLoop ở mode `.default`. Khi người dùng kéo bản
/// đồ hoặc cuộn danh sách, UIKit chuyển RunLoop sang mode `.tracking`, và mọi timer
/// `.default` **ngừng chạy** cho tới khi ngón tay nhấc lên. Với ứng dụng này hậu quả rất
/// cụ thể: vị trí mô phỏng đóng băng đúng lúc người dùng đang xem bản đồ, chuyến bay
/// đứng yên giữa trời, và chu trình 24/7 bỏ nhịp.
///
/// `.common` gồm cả `.default` lẫn `.tracking`, nên timer chạy liên tục.
enum CommonTimer {
    /// Tạo và lên lịch một timer ở mode `.common`.
    @discardableResult
    static func scheduled(every interval: TimeInterval,
                          repeats: Bool = true,
                          _ block: @escaping (Timer) -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: repeats, block: block)
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
}
