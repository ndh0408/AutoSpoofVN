import Foundation
import os.log

/// Hệ thống logging tập trung — thay thế print() phân tán.
enum AppLogger {
    static let simulation = Logger(subsystem: "com.autospoof.vn", category: "Simulation")
    static let device     = Logger(subsystem: "com.autospoof.vn", category: "Device")
    static let transport  = Logger(subsystem: "com.autospoof.vn", category: "Transport")
    static let pairing    = Logger(subsystem: "com.autospoof.vn", category: "Pairing")
    static let route      = Logger(subsystem: "com.autospoof.vn", category: "Route")
    static let routine    = Logger(subsystem: "com.autospoof.vn", category: "Routine")
    static let scenario   = Logger(subsystem: "com.autospoof.vn", category: "Scenario")
    static let flight     = Logger(subsystem: "com.autospoof.vn", category: "Flight")
    static let persist    = Logger(subsystem: "com.autospoof.vn", category: "Persistence")
    static let background = Logger(subsystem: "com.autospoof.vn", category: "Background")
    static let ui         = Logger(subsystem: "com.autospoof.vn", category: "UI")
}
