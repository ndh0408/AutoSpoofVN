//
//  SelfPairingManager.swift
//  LocationX
//
//  Tu dong ghep noi RPPairing tren iOS 27+ truc tiep tren thiet bi.
//

import BackgroundTasks
import Combine
import Foundation
import Network
import UIKit
import UserNotifications


@MainActor
final class SelfPairingManager: ObservableObject {
    static let shared = SelfPairingManager()
    static let taskIdentifier = (Bundle.main.bundleIdentifier ?? "com.nguyenduchuy.locationx") + ".pairing"

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
                return L("device.pairing.idle")
            case .requestingPermission:
                return L("device.pairing.requesting_permission")
            case .advertising:
                return L("device.pairing.advertising")
            case .showPin(let pin):
                return L("device.pairing.pin", pin)
            case .connectingTunnel:
                return L("device.pairing.connecting_tunnel")
            case .success(let name, _, _):
                return L("device.pairing.success", name)
            case .failed(let error):
                return L("device.pairing.failed", error)
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
        pairedUDID = UserDefaults.standard.string(forKey: "locationx_paired_udid") ?? ""
        pairedDeviceName = UserDefaults.standard.string(forKey: "locationx_paired_device_name") ?? ""
    }

    nonisolated static var pairingFileURL: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("locationx_rppairing.plist")
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
                self.finishRun(with: .failed(L("device.pairing.error.local_network")))
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
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "LocationXSelfPairing") { [weak self] in
            guard let self else { return }
            self.finishRun(with: .failed(L("device.pairing.error.background_timeout")))
        }
        taskFinished = false
        phase = .advertising

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            self.finishRun(with: .failed(L("device.pairing.error.simulation_build")))
        }
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
            identifier: "locationx.pairing.pin",
            title: L("device.pairing.notification.title"),
            body: L("device.pairing.notification.body", pin)
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
            let descriptor = NWBrowser.Descriptor.bonjour(type: "_locationxprobe._tcp", domain: nil)
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

