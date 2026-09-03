import SwiftUI

/// Tab "Tuyến đường" — nha chung cua moi cach di chuyen tren mat dat.
///
/// **Giai doan 1**: man hinh nay la duong VAO cho cac man hinh hien co, chua phai ban
/// thiet ke lai cua chung (Route/Scenario la Giai doan 5, Routine la Giai doan 7).
/// Muc dich la khong mat kha nang nao trong luc doi:
///
/// - `RouteStudioView` truoc day chi vao duoc tu QuickActionsBar cua man hinh chinh,
///   ma thanh do bi AN khi mo phong dang chay — nghia la dang chay thi khong mo duoc.
/// - `RoutineStudioView` truoc day **khong co duong vao nao**: sheet duoc khai bao o
///   `MainViewV2` nhung `showRoutineStudio` khong bao gio duoc dat `true`. Toan bo
///   chuc nang chu trinh 24/7 la mot man hinh chet. Day la lan dau no vao duoc.
struct RoutesHubScreen: View {
    @Environment(\.navigator) private var navigator
    @ObservedObject private var routine = RoutineManager.shared
    @ObservedObject private var history = HistoryManager.shared
    @ObservedObject private var coordinator = SimulationCoordinator.shared

    var body: some View {
        List {
            if coordinator.state.isActive, let source = coordinator.activeSource {
                Section {
                    activeSessionRow(source: source)
                }
            }

            Section("Lộ trình") {
                HubRow(title: "Tuyến đường",
                       subtitle: "Vẽ tuyến giữa hai điểm, chọn phương tiện và tốc độ",
                       symbol: SimulationSource.route.icon,
                       tint: AppColor.primary) {
                    navigator.present(.routeStudio)
                }
                HubRow(title: "Kịch bản",
                       subtitle: "Chuỗi hành động: di chuyển, chờ, dừng chân, lặp lại",
                       symbol: SimulationSource.scenario.icon,
                       tint: AppColor.accent) {
                    navigator.present(.scenarioStudio)
                }
            }

            Section {
                HubRow(title: "Chu trình 24/7",
                       subtitle: "Lịch sinh hoạt tự động giữa nhà, công ty và quán cà phê",
                       symbol: SimulationSource.routine.icon,
                       tint: AppColor.warning,
                       badge: routine.isAutoRoutineEnabled ? "Đang bật" : nil) {
                    navigator.present(.routineStudio)
                }
            } header: {
                Text("Tự động")
            } footer: {
                Text(routine.isAutoRoutineEnabled
                     ? "Đang chạy: \(routine.statusDescription)"
                     : "Mô phỏng nhịp sinh hoạt cả ngày mà không cần thao tác.")
            }

            Section("Địa điểm & lịch sử") {
                HubRow(title: "Địa điểm đã lưu",
                       subtitle: "Nhà, công ty, quán cà phê và các điểm tuỳ chỉnh",
                       symbol: "bookmark.fill",
                       tint: AppColor.success) {
                    navigator.present(.bookmarks)
                }
                HubRow(title: "Lịch sử & phát lại",
                       subtitle: "Xem lại và phát lại các phiên đã chạy",
                       symbol: "clock.arrow.circlepath",
                       tint: AppColor.textSecondary,
                       badge: history.records.isEmpty ? nil : "\(history.records.count)") {
                    navigator.present(.history)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(L10n.tabRoutes)
    }

    /// Phien dang chay hien ngay tren cung — de tu day quay lai ban do bang mot cham.
    private func activeSessionRow(source: SimulationSource) -> some View {
        Button {
            navigator.select(.map)
        } label: {
            HStack(spacing: AppSpacing.md) {
                StatusIndicatorDot(color: coordinator.state.tint,
                                   isPulsing: coordinator.state == .running, size: 9)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(source.displayName) · \(coordinator.state.displayName)")
                        .font(AppFont.callout)
                        .foregroundStyle(AppColor.textPrimary)
                    Text("\(AppFormat.speed(coordinator.telemetry.speedKmh)) km/h · \(AppFormat.coordinate(coordinator.currentCoordinate, precision: 4))")
                        .font(AppFont.monoFootnote)
                        .foregroundStyle(AppColor.textSecondary)
                }
                Spacer()
                Text("Xem")
                    .font(AppFont.footnoteEmphasized)
                    .foregroundStyle(AppColor.primary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Chuyển sang tab bản đồ để xem phiên đang chạy")
    }
}

#Preview {
    NavigationStack { RoutesHubScreen() }
}
