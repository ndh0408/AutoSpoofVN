import Combine
import Foundation
import UIKit

/// Quản lý tích hợp Shadowrocket — detect, setup, auto-connect, sync.
///
/// Lifecycle:
/// ```
/// App launch → detect Shadowrocket installed?
///     → YES: check module imported? check VPN active?
///         → Module missing: hiện banner setup
///         → VPN off: khi start simulation → auto-open Shadowrocket bật VPN
///     → NO: hiện banner "Cài Shadowrocket từ App Store"
/// ```
@MainActor
final class ShadowrocketManager: ObservableObject {
    static let shared = ShadowrocketManager()

    // MARK: - Published State

    /// Shadowrocket có cài trên máy không
    @Published private(set) var isInstalled = false

    /// Module MITM đã import vào Shadowrocket chưa
    @Published private(set) var isModuleImported = false

    /// VPN Shadowrocket đang bật không (kiểm tra gián tiếp)
    @Published private(set) var isVPNActive = false

    /// CoordinateServer đang chạy không
    @Published private(set) var isServerRunning = false

    /// Toàn bộ pipeline sẵn sàng
    @Published private(set) var isReady = false

    /// Hiện banner setup không
    @Published var showSetupBanner = false

    /// Lý do chưa sẵn sàng
    @Published private(set) var statusMessage = ""

    /// Đếm requests tới CoordinateServer (chứng tỏ Shadowrocket đang fetch)
    @Published private(set) var lastRequestCount = 0

    // MARK: - Private

    private let coordServer = CoordinateServer.shared
    private var cancellables = Set<AnyCancellable>()
    private var vpnCheckTimer: Timer?
    /// Người dùng đã bấm nút import (đã nhảy sang Shadowrocket) nhưng CHƯA có bằng chứng
    /// module thực sự được nạp. Dùng để hiển thị trạng thái trung gian cho đúng.
    @Published private(set) var didAttemptImport = false
    private let moduleImportedKey = "locationx_shadowrocket_module_imported"
    private let setupCompletedKey = "locationx_shadowrocket_setup_done"

    private let appStoreURL = "https://apps.apple.com/app/shadowrocket/id932747118"
    private let moduleURL = "http://127.0.0.1:8765/locationx.sgmodule"
    private let moduleGitURL = "https://raw.githubusercontent.com/ndh0408/LocationX/main/Proxy/locationx.sgmodule"

    private init() {
        detectInstallation()
        loadSetupState()
        startCoordinateServer()
        observeCoordinateServer()
        startVPNMonitor()
    }

    // MARK: - Detection

    /// Kiểm tra Shadowrocket có cài không qua URL scheme
    func detectInstallation() {
        isInstalled = UIApplication.shared.canOpenURL(URL(string: "shadowrocket://")!)
        updateStatus()
    }

    // MARK: - Setup Actions

    /// Mở App Store cài Shadowrocket
    func openAppStore() {
        if let url = URL(string: appStoreURL) {
            UIApplication.shared.open(url)
        }
    }

    /// Kết quả kiểm tra một URL module trước khi giao cho Shadowrocket.
    enum ModuleAvailability: Equatable {
        case reachable(String)
        case unreachable(String)
    }

    /// Lỗi gần nhất khi chuẩn bị import, để giao diện nói thật thay vì im lặng.
    @Published private(set) var importError: String?

    /// Kiểm tra một URL có tải được không.
    ///
    /// Đây là mấu chốt của lỗi "Shadowrocket báo import thành công nhưng chẳng có gì":
    /// trước đây ta mở `shadowrocket://install?module=...` mà KHÔNG hề kiểm tra URL đó có
    /// tồn tại. URL GitHub thì 404 (repo chưa đổi tên), còn URL nội bộ thì chỉ sống khi
    /// ứng dụng chưa bị iOS treo. Shadowrocket nhận một URL hỏng, báo thành công theo cách
    /// của nó, và người dùng không có cách nào biết.
    private func checkReachable(_ urlString: String) async -> Bool {
        guard let url = URL(string: urlString) else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 4
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return false
            }
            // Module rỗng cũng vô dụng như module 404.
            return data.count > 32
        } catch {
            return false
        }
    }

    /// Chọn URL module dùng được: ưu tiên bản nội bộ (toạ độ realtime), lùi về GitHub.
    func resolveModuleURL() async -> ModuleAvailability {
        if !coordServer.isRunning { coordServer.start() }
        // Cho listener một nhịp để lên sóng.
        try? await Task.sleep(nanoseconds: 250_000_000)

        if coordServer.isRunning, await checkReachable(moduleURL) {
            return .reachable(moduleURL)
        }
        if await checkReachable(moduleGitURL) {
            return .reachable(moduleGitURL)
        }
        return .unreachable(moduleGitURL)
    }

    /// Import module vào Shadowrocket — one-tap
    func importModule() {
        Task { await performImport() }
    }

    private func performImport() async {
        importError = nil
        let availability = await resolveModuleURL()

        guard case .reachable(let urlString) = availability else {
            // Nói thẳng ra là hỏng, thay vì đẩy sang Shadowrocket rồi để nó im lặng.
            importError = L("shadowrocket.error.module_unreachable")
            updateStatus()
            return
        }

        let encoded = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlString
        if let url = URL(string: "shadowrocket://install?module=\(encoded)") {
            UIApplication.shared.open(url) { [weak self] opened in
                // KHÔNG đánh dấu "đã import" ở đây. `opened == true` chỉ nghĩa là iOS
                // chuyển được sang Shadowrocket, hoàn toàn không nói gì về việc người dùng
                // có bấm Import hay không. Ta chờ bằng chứng thật: Shadowrocket tự tìm tới
                // CoordinateServer lấy module/script (xem `observeCoordinateServer`).
                self?.didAttemptImport = opened
                self?.updateStatus()
            }
        }
    }

    /// Mở Shadowrocket để bật VPN
    func openShadowrocketToConnect() {
        if let url = URL(string: "shadowrocket://") {
            UIApplication.shared.open(url)
        }
    }

    /// Gọi khi bắt đầu simulation — tự mở Shadowrocket nếu VPN chưa bật
    func ensureVPNActive() {
        guard isInstalled else {
            showSetupBanner = true
            return
        }

        if !isModuleImported {
            importModule()
            return
        }

        if !isVPNActive {
            openShadowrocketToConnect()
        }
    }

    /// Mark setup hoàn thành
    /// Nguoi dung vua bam mot nut import o man hinh huong dan.
    ///
    /// Chua phai bang chung module da duoc nap — chi de giao dien hien trang thai cho.
    /// Xac nhan that su den tu `observeCoordinateServer()` khi Shadowrocket tu tim toi
    /// CoordinateServer lay module/script.
    func noteImportAttempted() {
        didAttemptImport = true
        updateStatus()
    }

    func markSetupCompleted() {
        UserDefaults.standard.set(true, forKey: setupCompletedKey)
        showSetupBanner = false
        updateStatus()
    }

    func markModuleImported() {
        isModuleImported = true
        UserDefaults.standard.set(true, forKey: moduleImportedKey)
        updateStatus()
    }

    /// Reset setup state
    func resetSetup() {
        UserDefaults.standard.removeObject(forKey: moduleImportedKey)
        UserDefaults.standard.removeObject(forKey: setupCompletedKey)
        isModuleImported = false
        showSetupBanner = true
        updateStatus()
    }

    // MARK: - CoordinateServer

    private func startCoordinateServer() {
        if !coordServer.isRunning {
            coordServer.start()
        }
        isServerRunning = coordServer.isRunning
    }

    private func observeCoordinateServer() {
        coordServer.$isRunning
            .receive(on: DispatchQueue.main)
            .sink { [weak self] running in
                self?.isServerRunning = running
                self?.updateStatus()
            }
            .store(in: &cancellables)

        // Đường dẫn vừa được yêu cầu cho biết Shadowrocket đang làm gì.
        coordServer.$lastRequestedPath
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] path in
                guard let self else { return }
                // Fetch module hoặc script = Shadowrocket ĐÃ nạp cấu hình của ta.
                // Đây là bằng chứng thật thay cho việc đoán từ `UIApplication.open`.
                if path.contains("sgmodule") || path.contains("location-spoofer") || path.contains("/js") {
                    self.markModuleImported()
                }
                self.isVPNActive = true
                self.updateStatus()
            }
            .store(in: &cancellables)

        coordServer.$requestCount
            .receive(on: DispatchQueue.main)
            .sink { [weak self] count in
                self?.lastRequestCount = count
            }
            .store(in: &cancellables)
    }

    // MARK: - VPN Monitor

    /// Kiểm tra VPN gián tiếp qua network interface
    private func startVPNMonitor() {
        vpnCheckTimer = CommonTimer.scheduled(every: 5) { [weak self] _ in
            Task { @MainActor in
                self?.checkVPNStatus()
            }
        }
    }

    private func checkVPNStatus() {
        let tunnelPresent = Self.hasTunnelInterface()
        // Pipeline chỉ được coi là sống khi CHÍNH Shadowrocket vừa fetch script của ta.
        let proven = isPipelineFresh

        let newValue = proven || tunnelPresent
        if newValue != isVPNActive {
            isVPNActive = newValue
        }
        // updateStatus() luôn chạy: độ "tươi" hết hạn theo thời gian chứ không theo sự kiện.
        updateStatus()
    }

    /// Có đường hầm VPN đang hoạt động không.
    ///
    /// Bản trước duyệt `getifaddrs` và coi là có VPN nếu thấy `utun*`. Nhưng iOS **luôn**
    /// tạo sẵn `utun0..2` cho Handoff/AirDrop/Sidecar, nên kết quả gần như luôn `true` —
    /// app báo "Sẵn sàng" cả khi Shadowrocket đang tắt. `__SCOPED__` của
    /// `CFNetworkCopySystemProxySettings` chỉ liệt kê interface đang thực sự định tuyến,
    /// nên chính xác hơn nhiều.
    private nonisolated static func hasTunnelInterface() -> Bool {
        guard let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue()
                as? [String: Any],
              let scoped = settings["__SCOPED__"] as? [String: Any] else { return false }
        for key in scoped.keys {
            if key.hasPrefix("tap") || key.hasPrefix("tun") ||
               key.hasPrefix("ppp") || key.hasPrefix("ipsec") || key.hasPrefix("utun") {
                return true
            }
        }
        return false
    }

    /// Shadowrocket có fetch script của ta trong thời gian gần đây không.
    /// Đây là bằng chứng trực tiếp rằng MITM đang chạy — không phải suy đoán.
    var isPipelineFresh: Bool {
        guard let last = coordServer.lastRequestAt else { return false }
        return Date().timeIntervalSince(last) < Self.freshnessWindow
    }

    /// Quá ngưỡng này mà không có request nào thì coi như pipeline đã chết.
    private static let freshnessWindow: TimeInterval = 180

    // MARK: - State

    private func loadSetupState() {
        isModuleImported = UserDefaults.standard.bool(forKey: moduleImportedKey)
        let setupDone = UserDefaults.standard.bool(forKey: setupCompletedKey)
        showSetupBanner = !setupDone && isInstalled
    }

    private func updateStatus() {
        // Lỗi chuẩn bị import được ưu tiên hiển thị — người dùng cần biết vì sao hỏng,
        // chứ không phải một dòng trạng thái chung chung.
        if let importError {
            statusMessage = importError
            isReady = false
            showSetupBanner = true
            return
        }
        if !isInstalled {
            statusMessage = L("shadowrocket.status.not_installed")
            isReady = false
            showSetupBanner = true
        } else if !isModuleImported {
            statusMessage = didAttemptImport
                ? L("shadowrocket.status.awaiting_import")
                : L("shadowrocket.status.need_import")
            isReady = false
            showSetupBanner = true
        } else if !isServerRunning {
            statusMessage = L("shadowrocket.status.server_down")
            isReady = false
        } else if isPipelineFresh {
            // Trạng thái DUY NHẤT được coi là chạy thật: Shadowrocket vừa fetch script
            // của ta, nghĩa là cả VPN, MITM lẫn chứng chỉ đều đang hoạt động.
            statusMessage = L("shadowrocket.status.ready")
            isReady = true
            showSetupBanner = false
        } else if isVPNActive {
            // Có đường hầm nhưng chưa thấy request nào — thường là chưa bật HTTPS
            // Decryption, chưa tin cậy chứng chỉ, hoặc chưa có app nào xin định vị.
            statusMessage = L("shadowrocket.status.no_traffic")
            isReady = false
        } else {
            statusMessage = L("shadowrocket.status.need_vpn")
            isReady = false
        }
    }

    deinit {
        vpnCheckTimer?.invalidate()
    }
}
