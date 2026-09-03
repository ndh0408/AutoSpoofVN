import SwiftUI
import CoreLocation
import Network
import UIKit

enum OnboardingCheckState {
    case complete
    case incomplete
    case unknown

    var icon: String {
        switch self {
        case .complete: return "checkmark.circle.fill"
        case .incomplete: return "xmark.circle.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .complete: return .green
        case .incomplete: return .orange
        case .unknown: return .secondary
        }
    }

    var label: String {
        switch self {
        case .complete: return "Đã xong"
        case .incomplete: return "Chưa xong"
        case .unknown: return "Không kiểm tra được"
        }
    }
}

@MainActor
final class LoopbackProbe: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case reachable
        case unreachable(String)
    }

    @Published private(set) var state: State = .idle

    private let queue = DispatchQueue(label: "com.autospoof.vn.loopback-probe")
    private var connection: NWConnection?
    private var timeoutTask: Task<Void, Never>?
    private var generation = UUID()

    deinit {
        connection?.cancel()
        timeoutTask?.cancel()
    }

    func check() {
        connection?.cancel()
        timeoutTask?.cancel()

        let generation = UUID()
        self.generation = generation
        state = .checking

        let connection = NWConnection(host: "10.7.0.1", port: 62078, using: .tcp)
        self.connection = connection

        connection.stateUpdateHandler = { [weak self] connectionState in
            Task { @MainActor [weak self] in
                guard let self, self.generation == generation else { return }
                switch connectionState {
                case .ready:
                    self.finish(.reachable, generation: generation)
                case .failed(let error):
                    self.finish(.unreachable(error.localizedDescription), generation: generation)
                case .cancelled:
                    break
                default:
                    break
                }
            }
        }

        connection.start(queue: queue)
        timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled, let self, self.generation == generation else { return }
            self.finish(.unreachable("Hết thời gian chờ sau 2 giây"), generation: generation)
        }
    }

    private func finish(_ result: State, generation: UUID) {
        guard self.generation == generation else { return }
        timeoutTask?.cancel()
        timeoutTask = nil
        connection?.cancel()
        connection = nil
        state = result
    }
}

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var engine: SpoofEngine
    @StateObject private var backgroundKeeper = BackgroundKeeper.shared
    @StateObject private var loopbackProbe = LoopbackProbe()
    @AppStorage("autospoof_onboarding_completed") private var hasCompletedOnboarding = false

    let isReviewMode: Bool

    @State private var showingPairingSetup = false
    @State private var showingDDIHelp = false

    init(isReviewMode: Bool = false) {
        self.isReviewMode = isReviewMode
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    computerRequirementNotice

                    VStack(spacing: 10) {
                        OnboardingCheckRow(
                            number: 1,
                            title: "Thiết bị chạy iOS 17.4 trở lên",
                            detail: operatingSystemDescription,
                            state: meetsMinimumOS ? .complete : .incomplete
                        )

                        OnboardingCheckRow(
                            number: 2,
                            title: "Đã bật Developer Mode",
                            detail: "Không có API công khai để kiểm tra. Mở Settings > Privacy & Security > Developer Mode.",
                            state: .unknown,
                            actionTitle: "Mở Settings",
                            action: openSystemSettings
                        )

                        OnboardingCheckRow(
                            number: 3,
                            title: "Đã cài và bật VPN loopback",
                            detail: loopbackDescription,
                            state: loopbackCheckState,
                            actionTitle: loopbackProbe.state == .checking ? nil : "Kiểm tra lại",
                            action: { loopbackProbe.check() }
                        )

                        OnboardingCheckRow(
                            number: 4,
                            title: "Đã nạp pairing file",
                            detail: engine.pairingSummary,
                            state: hasPairingData ? .complete : .incomplete,
                            actionTitle: "Chọn file",
                            action: { showingPairingSetup = true }
                        )

                        OnboardingCheckRow(
                            number: 5,
                            title: "Đã cấp quyền vị trí Luôn luôn",
                            detail: locationAuthorizationDescription,
                            state: backgroundKeeper.authorizationStatus == .authorizedAlways ? .complete : .incomplete,
                            actionTitle: locationPermissionActionTitle,
                            action: locationPermissionAction
                        )

                        OnboardingCheckRow(
                            number: 6,
                            title: "Đã mount Developer Disk Image",
                            detail: ddiDescription,
                            state: ddiCheckState,
                            actionTitle: "Xem lưu ý",
                            action: { showingDDIHelp = true }
                        )

                        OnboardingCheckRow(
                            number: 7,
                            title: "Đã kết nối DVT thành công",
                            detail: engine.isLoopbackConnected ? "Kết nối DVT đang hoạt động." : engine.connectionStatus,
                            state: engine.isLoopbackConnected ? .complete : .incomplete,
                            actionTitle: engine.isLoopbackConnected ? nil : "Kết nối",
                            action: connectDVT
                        )
                    }

                    Button {
                        hasCompletedOnboarding = true
                        if isReviewMode {
                            dismiss()
                        }
                    } label: {
                        Text(isReviewMode ? "Đóng hướng dẫn" : "Tôi hiểu, tiếp tục vào ứng dụng")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)

                    Text("Bạn có thể mở lại checklist này bất kỳ lúc nào trong Cài đặt.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
                .padding()
            }
            .navigationTitle("Thiết lập AutoSpoof VN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isReviewMode {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Đóng") { dismiss() }
                    }
                }
            }
            .sheet(isPresented: $showingPairingSetup) {
                PairingSetupView()
            }
            .alert("Developer Disk Image", isPresented: $showingDDIHelp) {
                Button("Đã hiểu", role: .cancel) {}
            } message: {
                Text("DDI phải được mount từ máy tính trước khi dịch vụ dtservicehub xuất hiện. DDI sẽ mất sau mỗi lần iPhone khởi động lại, vì vậy bước này phải thực hiện lại sau mỗi lần reboot.")
            }
            .onAppear {
                loopbackProbe.check()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "location.viewfinder")
                .font(.system(size: 42))
                .foregroundColor(.blue)
            Text("Kiểm tra trước khi bắt đầu")
                .font(.title2.bold())
            Text("Checklist này đọc trạng thái thật khi iOS cho phép. Các mục không có API kiểm tra sẽ được đánh dấu rõ là không xác định.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private var computerRequirementNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Cần máy tính cho lần thiết lập đầu tiên", systemImage: "desktopcomputer")
                .font(.headline)
            Text("Bạn phải cắm iPhone vào PC hoặc Mac một lần để Trust thiết bị, xuất file `.mobiledevicepairing` bằng pymobiledevice3 hoặc công cụ tương đương, và mount Developer Disk Image.")
                .font(.subheadline)
            Text("Sau khi thiết lập xong, app có thể vận hành không cần cắm máy tính. Tuy nhiên DDI mất sau mỗi lần iPhone khởi động lại và phải được mount lại từ máy tính.")
                .font(.subheadline)
                .fontWeight(.semibold)
        }
        .padding()
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var operatingSystemDescription: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "Thiết bị hiện tại: iOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    private var meetsMinimumOS: Bool {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return version.majorVersion > 17 || (version.majorVersion == 17 && version.minorVersion >= 4)
    }

    private var hasPairingData: Bool {
        guard let data = engine.pairingData else { return false }
        return !data.isEmpty
    }

    private var loopbackCheckState: OnboardingCheckState {
        switch loopbackProbe.state {
        case .reachable: return .complete
        case .unreachable: return .incomplete
        case .idle, .checking: return .unknown
        }
    }

    private var loopbackDescription: String {
        switch loopbackProbe.state {
        case .idle:
            return "Chưa kiểm tra cổng TCP 10.7.0.1:62078."
        case .checking:
            return "Đang thử kết nối TCP 10.7.0.1:62078 trong tối đa 2 giây…"
        case .reachable:
            return "Cổng TCP 10.7.0.1:62078 đang phản hồi."
        case .unreachable(let reason):
            return "Không kết nối được 10.7.0.1:62078: \(reason)"
        }
    }

    private var locationAuthorizationDescription: String {
        switch backgroundKeeper.authorizationStatus {
        case .authorizedAlways:
            return "Đã cấp quyền Luôn luôn."
        case .authorizedWhenInUse:
            return "Hiện chỉ có quyền Khi dùng app."
        case .denied:
            return "Quyền vị trí đã bị từ chối."
        case .restricted:
            return "Quyền vị trí bị hệ thống hạn chế."
        case .notDetermined:
            return "Chưa chọn quyền vị trí."
        @unknown default:
            return "Không xác định được quyền vị trí."
        }
    }

    private var locationPermissionActionTitle: String? {
        if backgroundKeeper.authorizationStatus == .authorizedAlways {
            return nil
        }
        return backgroundKeeper.needsSettingsForLocation ? "Mở Settings" : "Xin quyền Luôn luôn"
    }

    private func locationPermissionAction() {
        if backgroundKeeper.needsSettingsForLocation {
            openSystemSettings()
        } else {
            _ = backgroundKeeper.requestLocationPermission()
        }
    }

    private var ddiCheckState: OnboardingCheckState {
        if engine.isLoopbackConnected {
            return .complete
        }
        if engine.lastFFIError?.localizedCaseInsensitiveContains("dtservicehub") == true {
            return .incomplete
        }
        return .unknown
    }

    private var ddiDescription: String {
        if engine.isLoopbackConnected {
            return "Dịch vụ dtservicehub đã xuất hiện và DVT kết nối được."
        }
        if engine.lastFFIError?.localizedCaseInsensitiveContains("dtservicehub") == true {
            return engine.lastFFIError ?? "Thiết bị chưa quảng bá dtservicehub."
        }
        return "Không có API kiểm tra trực tiếp. Trạng thái được suy ra sau lần thử kết nối DVT."
    }

    private func connectDVT() {
        if let data = engine.pairingData, !data.isEmpty {
            engine.connectLoopback(pairingData: data)
        } else {
            showingPairingSetup = true
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

private struct OnboardingCheckRow: View {
    let number: Int
    let title: String
    let detail: String
    let state: OnboardingCheckState
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: state.icon)
                    .font(.title3)
                    .foregroundColor(state.color)

                VStack(alignment: .leading, spacing: 3) {
                    Text("\(number). \(title)")
                        .font(.headline)
                    Text(detail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                Text(state.label)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(state.color)
            }

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
