import Foundation
import os.log

/// Hệ thống logging tập trung — thay thế print() phân tán.
enum AppLogger {
    static let simulation = Logger(subsystem: "com.nguyenduchuy.locationx", category: "Simulation")
    static let device     = Logger(subsystem: "com.nguyenduchuy.locationx", category: "Device")
    static let transport  = Logger(subsystem: "com.nguyenduchuy.locationx", category: "Transport")
    static let pairing    = Logger(subsystem: "com.nguyenduchuy.locationx", category: "Pairing")
    static let route      = Logger(subsystem: "com.nguyenduchuy.locationx", category: "Route")
    static let routine    = Logger(subsystem: "com.nguyenduchuy.locationx", category: "Routine")
    static let scenario   = Logger(subsystem: "com.nguyenduchuy.locationx", category: "Scenario")
    static let flight     = Logger(subsystem: "com.nguyenduchuy.locationx", category: "Flight")
    static let persist    = Logger(subsystem: "com.nguyenduchuy.locationx", category: "Persistence")
    static let background = Logger(subsystem: "com.nguyenduchuy.locationx", category: "Background")
    static let ui         = Logger(subsystem: "com.nguyenduchuy.locationx", category: "UI")
}
