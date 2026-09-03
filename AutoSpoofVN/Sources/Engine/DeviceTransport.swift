//
//  DeviceTransport.swift
//  AutoSpoofVN
//
//  Transport abstraction for real DVT/RPPairing and deterministic mock testing.
//

import CoreLocation
import Foundation

#if USE_IDEVICE_FFI
import idevice
#endif

public enum DeviceTransportType: String, Codable {
    case dvtLoopback = "DVT Loopback (10.7.0.1:62078)"
    case rpPairing = "RPPairing Remote (10.7.0.1:49152)"
    case mock = "Chế độ Kiểm thử (Mock)"
}

public protocol DeviceTransport: AnyObject {
    var transportType: DeviceTransportType { get }
    var isConnected: Bool { get }
    var lastError: String? { get }
    var lastLatencyMs: Double { get }

    func connect(host: String, port: UInt16, pairingData: Data) async -> Bool
    func sendLocation(latitude: Double, longitude: Double) -> Bool
    func clearLocation() -> Bool
    func disconnect()
}

/// Real Hardware DVT Transport interacting with Rust staticlib FFI on a dedicated serial queue.
public final class DVTDeviceTransport: DeviceTransport {
    public private(set) var transportType: DeviceTransportType = .dvtLoopback
    public private(set) var isConnected: Bool = false
    public private(set) var lastError: String? = nil
    public private(set) var lastLatencyMs: Double = 0.0

    private let queue = DispatchQueue(label: "com.autospoof.vn.transport.dvt", qos: .userInitiated)
    private var handle: UnsafeMutableRawPointer? = nil

    public init() {}

    public func connect(host: String, port: UInt16, pairingData: Data) async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: false)
                    return
                }
                let startTime = DispatchTime.now()
                #if USE_IDEVICE_FFI
                let isRPPairing = (try? PropertyListSerialization.propertyList(from: pairingData, options: [], format: nil) as? [String: Any])?["public_key"] != nil
                self.transportType = isRPPairing ? .rpPairing : .dvtLoopback

                let deviceHandle: UnsafeMutableRawPointer? = pairingData.withUnsafeBytes { raw in
                    guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return nil }
                    if isRPPairing {
                        return idevice_connect_dvt_remote(host, port > 0 ? port : 49152, base, raw.count, "000000")
                    } else {
                        return idevice_connect_dvt(host, port > 0 ? port : 62078, base, raw.count)
                    }
                }
                self.handle = deviceHandle
                let elapsed = Double(DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000.0
                self.lastLatencyMs = elapsed

                if deviceHandle != nil {
                    self.isConnected = true
                    self.lastError = nil
                    continuation.resume(returning: true)
                } else {
                    self.isConnected = false
                    let reason = self.readFFIError()
                    self.lastError = reason ?? "Kết nối DVT thất bại"
                    continuation.resume(returning: false)
                }
                #else
                self.isConnected = false
                self.lastError = "Bản build thiếu thư viện libidevice_ffi.a"
                continuation.resume(returning: false)
                #endif
            }
        }
    }

    public func sendLocation(latitude: Double, longitude: Double) -> Bool {
        #if USE_IDEVICE_FFI
        guard isConnected, let handle else { return false }
        let startTime = DispatchTime.now()
        var result = false
        queue.sync {
            result = idevice_set_location(handle, latitude, longitude)
        }
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000.0
        self.lastLatencyMs = elapsed
        return result
        #else
        return false
        #endif
    }

    public func clearLocation() -> Bool {
        #if USE_IDEVICE_FFI
        guard isConnected, let handle else { return false }
        var result = false
        queue.sync {
            result = idevice_clear_location(handle)
        }
        return result
        #else
        return false
        #endif
    }

    public func disconnect() {
        #if USE_IDEVICE_FFI
        queue.async { [weak self] in
            guard let self, let handle = self.handle else { return }
            idevice_disconnect(handle)
            self.handle = nil
            self.isConnected = false
        }
        #else
        isConnected = false
        #endif
    }

    #if USE_IDEVICE_FFI
    private func readFFIError() -> String? {
        guard let pointer = idevice_last_error() else { return nil }
        return String(cString: pointer)
    }
    #endif
}

/// Mock Transport for deterministic unit tests and simulated runs.
public final class MockDeviceTransport: DeviceTransport {
    public private(set) var transportType: DeviceTransportType = .mock
    public private(set) var isConnected: Bool = false
    public private(set) var lastError: String? = nil
    public private(set) var lastLatencyMs: Double = 0.5
    public private(set) var sentCoordinates: [CLLocationCoordinate2D] = []

    public init() {}

    public func connect(host: String, port: UInt16, pairingData: Data) async -> Bool {
        isConnected = true
        lastError = nil
        return true
    }

    public func sendLocation(latitude: Double, longitude: Double) -> Bool {
        guard isConnected else { return false }
        sentCoordinates.append(CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
        return true
    }

    public func clearLocation() -> Bool {
        sentCoordinates.removeAll()
        return true
    }

    public func disconnect() {
        isConnected = false
    }
}
