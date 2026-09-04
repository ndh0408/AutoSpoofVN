import CoreLocation
import Combine
import Foundation

/// Kho tuyến đường đã lưu — nguồn duy nhất mà giao diện quan sát.
///
/// Trước đây không tồn tại kho nào: `RouteStudioViewModel.saveRoute()` ghi thẳng vào
/// `PersistenceManager` và **không màn hình nào đọc lại**, nên nút "Lưu tuyến đường" tạo ra
/// thứ người dùng không bao giờ lấy lại được. Các view khác thì gọi
/// `PersistenceManager.loadX()` ngay trong thân view — giải mã JSON đồng bộ trên main
/// thread ở mỗi lần dựng lại view.
///
/// Kho này đọc một lần khi khởi tạo, giữ trong bộ nhớ, và **ghi trên hàng đợi nền**.
@MainActor
final class SavedRouteStore: ObservableObject {
    static let shared = SavedRouteStore()

    @Published private(set) var routes: [SavedRoute] = []

    /// Ghi file tuần tự ngoài main thread — mã hoá JSON một danh sách tuyến có hình học
    /// đầy đủ có thể tốn hàng chục ms.
    private let writeQueue = DispatchQueue(label: "com.nguyenduchuy.locationx.routestore", qos: .utility)

    private init() {
        routes = PersistenceManager.shared.loadRoutes()
    }

    // MARK: - Đọc

    /// Tuyến dùng gần đây nhất, mới nhất trước.
    var recentlyUsed: [SavedRoute] {
        routes.filter { $0.lastUsedAt != nil }
            .sorted { ($0.lastUsedAt ?? .distantPast) > ($1.lastUsedAt ?? .distantPast) }
    }

    func route(id: UUID) -> SavedRoute? {
        routes.first { $0.id == id }
    }

    // MARK: - Ghi

    func add(_ route: SavedRoute) {
        routes.insert(route, at: 0)
        persist()
    }

    func update(_ route: SavedRoute) {
        guard let index = routes.firstIndex(where: { $0.id == route.id }) else { return }
        var updated = route
        updated.updatedAt = Date()
        routes[index] = updated
        persist()
    }

    func delete(id: UUID) {
        routes.removeAll { $0.id == id }
        persist()
    }

    func delete(atOffsets offsets: IndexSet) {
        // Xoá theo id chứ không theo chỉ số: nếu danh sách hiển thị đang được lọc hoặc sắp
        // xếp khác mảng gốc thì chỉ số sẽ trỏ nhầm phần tử.
        let ids = offsets.compactMap { routes[safe: $0]?.id }
        routes.removeAll { ids.contains($0.id) }
        persist()
    }

    /// Đánh dấu tuyến vừa được chạy — nuôi mục "Gần đây" và cột "Dùng lần cuối" trên thẻ.
    func markUsed(id: UUID) {
        guard let index = routes.firstIndex(where: { $0.id == id }) else { return }
        routes[index].lastUsedAt = Date()
        persist()
    }

    func rename(id: UUID, to name: String) {
        guard let index = routes.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        routes[index].name = trimmed
        routes[index].updatedAt = Date()
        persist()
    }

    /// Đảo chiều tuyến đã lưu (đi ngược lại).
    func reverse(id: UUID) {
        guard let index = routes.firstIndex(where: { $0.id == id }) else { return }
        routes[index].waypoints.reverse()
        routes[index].routeGeometry?.reverse()
        routes[index].updatedAt = Date()
        persist()
    }

    private func persist() {
        // Mã hoá NGAY trên main actor rồi chỉ đẩy `Data` sang hàng đợi nền.
        //
        // Đẩy thẳng `[SavedRoute]` qua ranh giới thread là truyền một kiểu không Sendable:
        // mảng có thể bị sửa tiếp trong lúc thread kia đang đọc. `Data` thì bất biến nên
        // qua ranh giới an toàn, và phần tốn kém (JSONEncoder) vẫn nằm ngoài main thread
        // ở chỗ ghi file.
        guard let data = try? JSONEncoder().encode(routes) else {
            AppLogger.persist.error("Khong ma hoa duoc danh sach tuyen")
            return
        }
        writeQueue.async {
            PersistenceManager.shared.saveRoutesData(data)
        }
    }
}
