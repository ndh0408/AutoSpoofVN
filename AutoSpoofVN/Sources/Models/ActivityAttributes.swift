//
//  ActivityAttributes.swift
//  AutoSpoofVN
//
//  Cau truc du lieu cho Live Activity va Dynamic Island.
//

import ActivityKit
import Foundation

struct SpoofActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var stateName: String
        var statusDescription: String
        var speedKmh: Double
        var coordinateText: String
        var flightNumber: String?
        var flightProgress: Double?
        var activeSource: String
        var isHalted: Bool
    }

    var appName: String
}
