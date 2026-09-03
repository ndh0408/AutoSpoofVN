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
    private let moduleImportedKey = "autospoof_shadowrocket_module_imported"
    private let setupCompletedKey = "autospoof_shadowrocket_setup_done"

    private let appStoreURL = "https://apps.apple.com/app/shadowrocket/id932747118"
    private let moduleURL = "http://127.0.0.1:8765/autospoof.sgmodule"
    private let moduleGitURL = "https://raw.githubusercontent.com/ndh0408/AutoSpoofVN/main/Proxy/autospoof-location.sgmodule"

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

    /// Import module vào Shadowrocket — one-tap
    func importModule() {
        // Đảm bảo CoordinateServer đang chạy
        if !coordServer.isRunning { coordServer.start() }

        // Thử local module trước (realtime), fallback GitHub (static)
        let urlString: String
        if coordServer.isRunning {
            urlString = moduleURL
        } else {
            urlString = moduleGitURL
        }

        let encoded = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlString
        if let url = URL(string: "shadowrocket://install?module=\(encoded)") {
            UIApplication.shared.open(url) { [weak self] success in
                if success {
                    self?.markModuleImported()
                }
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

        // Monitor request count — nếu tăng = Shadowrocket đang fetch
        coordServer.$requestCount
            .receive(on: DispatchQueue.main)
            .sink { [weak self] count in
                guard let self else { return }
                if count > self.lastRequestCount && count > 0 {
                    // Shadowrocket đang fetch → VPN hoạt động
                    self.isVPNActive = true
                    self.updateStatus()
                }
                self.lastRequestCount = count
            }
            .store(in: &cancellables)
    }

    // MARK: - VPN Monitor

    /// Kiểm tra VPN gián tiếp qua network interface
    private func startVPNMonitor() {
        vpnCheckTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkVPNStatus()
            }
        }
    }

    private func checkVPNStatus() {
        // Cách 1: check request count tăng (Shadowrocket fetch từ CoordinateServer)
        // Đã handle trong observeCoordinateServer

        // Cách 2: check network interfaces cho utun (VPN tunnel)
        var isVPN = false
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&ifaddr) == 0 {
            var ptr = ifaddr
            while ptr != nil {
                let name = String(cString: ptr!.pointee.ifa_name)
                if name.hasPrefix("utun") || name.hasPrefix("ipsec") || name.hasPrefix("ppp") {
                    isVPN = true
                    break
                }
                ptr = ptr?.pointee.ifa_next
            }
            freeifaddrs(ifaddr)
        }

        if isVPN != isVPNActive {
            isVPNActive = isVPN
            updateStatus()
        }
    }

    // MARK: - State

    private func loadSetupState() {
        isModuleImported = UserDefaults.standard.bool(forKey: moduleImportedKey)
        let setupDone = UserDefaults.standard.bool(forKey: setupCompletedKey)
        showSetupBanner = !setupDone && isInstalled
    }

    private func updateStatus() {
        if !isInstalled {
            statusMessage = "Cài Shadowrocket để bypass phát hiện GPS giả"
            isReady = false
            showSetupBanner = true
        } else if !isModuleImported {
            statusMessage = "Bấm để import module vào Shadowrocket"
            isReady = false
            showSetupBanner = true
        } else if !isServerRunning {
            statusMessage = "CoordinateServer chưa chạy"
            isReady = false
        } else if !isVPNActive {
            statusMessage = "Bật VPN Shadowrocket để bắt đầu"
            isReady = false
        } else {
            statusMessage = "Sẵn sàng — GPS fake không bị phát hiện"
            isReady = true
            showSetupBanner = false
        }
    }

    deinit {
        vpnCheckTimer?.invalidate()
    }
}
