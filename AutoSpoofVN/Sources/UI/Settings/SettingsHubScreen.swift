import SwiftUI

/// Tab "Cài đặt".
///
/// **Giai doan 1**: duong vao cho cac man hinh hien co, chua phai ban thiet ke lai
/// (Giai doan 8). Nhung no da lam mot viec that: gom bon man hinh truoc day chi vao duoc
/// bang cach doan dung mot trong muoi nut icon xep doc ben phai ban do
/// (thiet bi, chan doan, Shadowrocket, khac phuc su co) thanh mot cau truc doc duoc.
struct SettingsHubScreen: View {
    @Environment(\.navigator) private var navigator
    @ObservedObject private var coordinator = SimulationCoordinator.shared
    @ObservedObject private var device = DeviceManager.shared
    @ObservedObject private var shadowrocket = ShadowrocketManager.shared

    var body: some View {
        List {
            Section("Thiết bị") {
                HubRow(title: "Quản lý thiết bị",
                       subtitle: device.deviceName.isEmpty ? "Ghép nối, kết nối lại, kiểm tra kênh DVT" : device.deviceName,
                       symbol: coordinator.deviceState.icon,
                       tint: coordinator.deviceState.tint,
                       badge: coordinator.deviceState.isConnected ? "Đã kết nối" : "Chưa kết nối") {
                    navigator.present(.deviceManager)
                }
                HubRow(title: "Chẩn đoán hệ thống",
                       subtitle: "Trạng thái transport, chạy nền, Live Activity",
                       symbol: "stethoscope",
                       tint: AppColor.accent) {
                    navigator.present(.diagnostics)
                }
            }

            Section {
                HubRow(title: "Thiết lập Shadowrocket",
                       subtitle: "Module MITM giúp vượt kiểm tra vị trí phía máy chủ",
                       symbol: "bolt.horizontal.fill",
                       tint: shadowrocket.isReady ? AppColor.success : AppColor.warning,
                       badge: shadowrocket.isReady ? "Sẵn sàng" : "Chưa xong") {
                    navigator.present(.shadowrocketSetup)
                }
                HubRow(title: "Khắc phục sự cố",
                       subtitle: "Vì sao ứng dụng vẫn nhận ra vị trí giả",
                       symbol: "questionmark.circle.fill",
                       tint: AppColor.textSecondary) {
                    navigator.present(.bypassTroubleshoot)
                }
            } header: {
                Text("Vượt kiểm tra")
            } footer: {
                if !shadowrocket.statusMessage.isEmpty {
                    Text(shadowrocket.statusMessage)
                }
            }

            Section("Mô phỏng") {
                HubRow(title: "Tuỳ chọn mô phỏng",
                       subtitle: "Nhiễu GPS, bản đồ, chạy nền, giao diện",
                       symbol: "slider.horizontal.3",
                       tint: AppColor.primary) {
                    navigator.present(.settings)
                }
            }

            Section {
                LabeledContent("Phiên bản", value: appVersion)
                LabeledContent("Build", value: buildNumber)
                LabeledContent("Nguồn ưu tiên") {
                    Text(coordinator.activeSource?.displayName ?? "Không có")
                        .foregroundStyle(AppColor.textSecondary)
                }
            } header: {
                Text("Ứng dụng")
            } footer: {
                Text("AutoSpoofVN mô phỏng vị trí GPS trên thiết bị của chính bạn thông qua kênh DVT của Apple. Cần bật Developer Mode.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(L10n.tabSettings)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }
}

#Preview {
    NavigationStack { SettingsHubScreen() }
}
