//
//  SelfPairingManager.swift
//  AutoSpoofVN
//
//  Tu dong ghep noi RPPairing tren iOS 27+ truc tiep tren thiet bi.
//

import BackgroundTasks
import Combine
import Foundation
import Network
import UIKit
import UserNotifications

#if USE_IDEVICE_FFI
import idevice
#endif

@MainActor
final class SelfPairingManager: ObservableObject {
    static let shared = SelfPairingManager()
    static let taskIdentifier = (Bundle.main.bundleIdentifier ?? "com.autospoof.vn") + ".pairing"

    enum Phase: Equatable {
        case idle
        case requestingPermission
        case advertising
        case showPin(String)
        case connectingTunnel
        case success(name: String, model: String, udid: String)
        case failed(String)

        var description: String {
            switch self {
            case .idle:
                return "Sẵn sàng tự động ghép nối"
            case .requestingPermission:
                return "Đang xin quyền mạng cục bộ..."
            case .advertising:
                return "Đang phát Bonjour. Mở Cài đặt > Quyền riêng tư & Bảo mật > Chế độ Nhà phát triển."
            case .showPin(let pin):
                return "Mã ghép nối: \(pin)"
            case .connectingTunnel:
                return "Ghép nối xong, đang mở đường hầm DVT..."
            case .success(let name, _, _):
                return "Đã ghép nối thành công với \(name)"
            case .failed(let error):
                return "Ghép nối thất bại: \(error)"
            }
        }
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var latestPin: String? = nil
    @Published private(set) var pairedUDID: String = ""
    @Published private(set) var pairedDeviceName: String = ""

    private var netService: NetService?
    private var probeBrowser: NWBrowser?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var taskFinished: Bool = false

    private init() {
        pairedUDID = UserDefaults.standard.string(forKey: "autospoof_paired_udid") ?? ""
        pairedDeviceName = UserDefaults.standard.string(forKey: "autospoof_paired_device_name") ?? ""
    }

    nonisolated static var pairingFileURL: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("autospoof_rppairing.plist")
    }

    var hasSavedPairing: Bool {
        FileManager.default.fileExists(atPath: Self.pairingFileURL.path)
    }

    nonisolated func registerBackgroundTask() {
    }

    func startAutoPairing() {
        guard !isRunning else { return }
        isRunning = true
        phase = .requestingPermission
        latestPin = nil

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        BackgroundKeeper.shared.start()

        Task {
            let authorized = await requestLocalNetworkAccess()
            guard authorized else {
                self.finishRun(with: .failed("Cần cấp quyền Mạng cục bộ trong Cài đặt > AutoSpoof VN."))
                return
            }
            self.beginBackgroundTaskAndRun()
        }
    }

    func cancel() {
        stopAdvertising()
        finishRun(with: .idle)
    }

    private func beginBackgroundTaskAndRun() {
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "AutoSpoofSelfPairing") { [weak self] in
            guard let self else { return }
            self.finishRun(with: .failed("Hết thời gian chờ ghép nối chạy ngầm. Hãy thử lại."))
        }
        taskFinished = false
        phase = .advertising

        #if USE_IDEVICE_FFI
        let bindAddress = "0.0.0.0"
        let hostName = "AutoSpoofVN"
        let model = "Mac17,7"
        let outputPath = Self.pairingFileURL.path
        let contextPointer = UInt(bitPattern: Unmanaged.passRetained(self).toOpaque())

        DispatchQueue.global(qos: .userInitiated).async {
            let context = UnsafeMutableRawPointer(bitPattern: contextPointer)
            var result = IdevicePairingResult()
            let returnCode = bindAddress.withCString { bindC in
                hostName.withCString { hostC in
                    model.withCString { modelC in
                        outputPath.withCString { outC in
                            idevice_pairing_host_run(
                                bindC,
                                hostC,
                                modelC,
                                outC,
                                180,
                                selfPairingReadyCallback,
                                selfPairingPinCallback,
                                context,
                                &result
                            )
                        }
                    }
                }
            }

            let deviceName = result.device_name.map { String(cString: $0) } ?? "iPhone"
            let deviceModel = result.device_model.map { String(cString: $0) } ?? ""
            let deviceUDID = result.device_udid.map { String(cString: $0) } ?? ""
            let errorMessage = result.error.map { String(cString: $0) } ?? ""
            idevice_pairing_result_free(&result)
            if let context {
                Unmanaged<SelfPairingManager>.fromOpaque(context).release()
            }

            DispatchQueue.main.async {
                self.stopAdvertising()
                if returnCode == 0 {
                    self.pairedUDID = deviceUDID
                    self.pairedDeviceName = deviceName
                    UserDefaults.standard.set(deviceUDID, forKey: "autospoof_paired_udid")
                    UserDefaults.standard.set(deviceName, forKey: "autospoof_paired_device_name")
                    if let pairingData = try? Data(contentsOf: Self.pairingFileURL) {
                        SpoofEngine.shared.connectLoopback(pairingData: pairingData)
                    }
                    self.finishRun(with: .success(name: deviceName, model: deviceModel, udid: deviceUDID))
                } else {
                    let failure = errorMessage.isEmpty ? "Ghép nối thất bại (mã \(returnCode))" : errorMessage
                    self.finishRun(with: .failed(failure))
                }
            }
        }
        #else
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            self.finishRun(with: .failed("Bản build hiện tại đang chạy chế độ mô phỏng, chưa bật FFI thật."))
        }
        #endif
    }

    private func finishRun(with outcome: Phase) {
        phase = outcome
        isRunning = false
        stopAdvertising()
        if !taskFinished {
            taskFinished = true
            if backgroundTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTaskID)
                backgroundTaskID = .invalid
            }
        }
    }

    fileprivate func startAdvertising(serviceID: String, port: Int32, txtRecords: [String: Data]) {
        stopAdvertising()
        let service = NetService(
            domain: "",
            type: "_remotepairing-pairable-host._tcp.",
            name: serviceID,
            port: port
        )
        service.setTXTRecord(NetService.data(fromTXTRecord: txtRecords))
        service.publish()
        netService = service
        phase = .advertising
    }

    fileprivate func handleReceivedPin(_ pin: String) {
        latestPin = pin
        phase = .showPin(pin)
        sendNotification(
            identifier: "autospoof.pairing.pin",
            title: "Mã ghép nối AutoSpoof VN",
            body: "Nhập mã \(pin) vào mục Pair with AutoSpoofVN trong Developer Mode."
        )
    }

    private func stopAdvertising() {
        netService?.stop()
        netService = nil
    }

    private func sendNotification(identifier: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func requestLocalNetworkAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            let descriptor = NWBrowser.Descriptor.bonjour(type: "_autospoofprobe._tcp", domain: nil)
            let parameters = NWParameters()
            let browser = NWBrowser(for: descriptor, using: parameters)
            self.probeBrowser = browser

            var resumed = false
            let resumeOnce: (Bool) -> Void = { allowed in
                guard !resumed else { return }
                resumed = true
                browser.cancel()
                self.probeBrowser = nil
                continuation.resume(returning: allowed)
            }

            browser.stateUpdateHandler = { state in
                switch state {
                case .ready, .failed:
                    resumeOnce(true)
                case .waiting(let error):
                    if case .posix(let code) = error, code == .ENODATA || code == .EHOSTUNREACH {
                        resumeOnce(true)
                    } else {
                        resumeOnce(true)
                    }
                case .cancelled:
                    break
                default:
                    break
                }
            }
            browser.start(queue: .main)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                resumeOnce(true)
            }
        }
    }
}

#if USE_IDEVICE_FFI
private let selfPairingReadyCallback: IdevicePairingReadyCallback = { context, serviceID, port, keys, values, count in
    guard let context, let serviceID else { return }
    let manager = Unmanaged<SelfPairingManager>.fromOpaque(context).takeUnretainedValue()
    let id = String(cString: serviceID)

    var records: [String: Data] = [:]
    if let keys, let values {
        for index in 0..<Int(count) {
            guard let key = keys[index], let value = values[index] else { continue }
            records[String(cString: key)] = Data(String(cString: value).utf8)
        }
    }
    DispatchQueue.main.async {
        manager.startAdvertising(serviceID: id, port: Int32(port), txtRecords: records)
    }
}

private let selfPairingPinCallback: IdevicePairingPinCallback = { pin, context in
    guard let context, let pin else { return }
    let manager = Unmanaged<SelfPairingManager>.fromOpaque(context).takeUnretainedValue()
    let pinString = String(cString: pin)
    DispatchQueue.main.async {
        manager.handleReceivedPin(pinString)
    }
}
#endif
