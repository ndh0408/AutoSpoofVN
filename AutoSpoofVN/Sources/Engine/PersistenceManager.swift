//
//  PersistenceManager.swift
//  AutoSpoofVN
//
//  Codable file-based persistence for Routes, Scenarios, Bookmarks, and Sessions.
//

import Foundation

public final class PersistenceManager {
    public static let shared = PersistenceManager()

    private let fileManager = FileManager.default
    private let documentsDirectory: URL

    private init() {
        self.documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    // MARK: - Generic Codable Storage

    public func save<T: Encodable>(_ object: T, to filename: String) throws {
        let url = documentsDirectory.appendingPathComponent(filename)
        let data = try JSONEncoder().encode(object)
        try data.write(to: url, options: [.atomicWrite])
    }

    public func load<T: Decodable>(_ type: T.Type, from filename: String) throws -> T {
        let url = documentsDirectory.appendingPathComponent(filename)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(type, from: data)
    }

    // MARK: - Scenarios

    public func loadScenarios() -> [Scenario] {
        (try? load([Scenario].self, from: "autospoof_scenarios.json")) ?? defaultScenarios()
    }

    public func saveScenarios(_ scenarios: [Scenario]) {
        try? save(scenarios, to: "autospoof_scenarios.json")
    }

    // MARK: - History Sessions

    public func loadHistory() -> [SimulationSession] {
        (try? load([SimulationSession].self, from: "autospoof_history.json")) ?? []
    }

    public func saveHistory(_ sessions: [SimulationSession]) {
        try? save(sessions, to: "autospoof_history.json")
    }

    // MARK: - GPX Export & Import

    public func exportToGPX(track: [CoordinateCodable], name: String) -> String {
        var gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="AutoSpoofVN" xmlns="http://www.topografix.com/GPX/1/1">
          <metadata>
            <name>\(name)</name>
            <time>\(ISO8601DateFormatter().string(from: Date()))</time>
          </metadata>
          <trk>
            <name>\(name)</name>
            <trkseg>
        """
        for coord in track {
            gpx += "\n      <trkpt lat=\"\(coord.latitude)\" lon=\"\(coord.longitude)\"></trkpt>"
        }
        gpx += """

            </trkseg>
          </trk>
        </gpx>
        """
        return gpx
    }

    public func importFromGPX(gpxContent: String) -> [CoordinateCodable] {
        var coordinates: [CoordinateCodable] = []
        let lines = gpxContent.components(separatedBy: .newlines)
        for line in lines {
            if let latRange = line.range(of: "lat=\"([^\"]+)\"", options: .regularExpression),
               let lonRange = line.range(of: "lon=\"([^\"]+)\"", options: .regularExpression) {
                let latSub = String(line[latRange])
                    .replacingOccurrences(of: "lat=\"", with: "")
                    .replacingOccurrences(of: "\"", with: "")
                let lonSub = String(line[lonRange])
                    .replacingOccurrences(of: "lon=\"", with: "")
                    .replacingOccurrences(of: "\"", with: "")
                if let lat = Double(latSub), let lon = Double(lonSub) {
                    coordinates.append(CoordinateCodable(latitude: lat, longitude: lon))
                }
            }
        }
        return coordinates
    }

    private func defaultScenarios() -> [Scenario] {
        [
            Scenario(
                name: "Thử nghiệm đi làm buổi sáng",
                summary: "Khởi hành từ nhà, dừng đèn đỏ, tăng tốc lên 45 km/h và đến cơ quan.",
                steps: [
                    ScenarioStep(title: "Xuất phát tại Nhà riêng", actionType: .setLocation, targetCoordinate: CoordinateCodable(latitude: 21.0333, longitude: 105.8433)),
                    ScenarioStep(title: "Chờ chuẩn bị xe", actionType: .waitSeconds, waitDurationSeconds: 5),
                    ScenarioStep(title: "Di chuyển ra phố chính", actionType: .changeSpeed, targetSpeedKmh: 35),
                    ScenarioStep(title: "Dừng chân quán Cafe sáng", actionType: .dwellArea, targetCoordinate: CoordinateCodable(latitude: 21.0285, longitude: 105.8342), dwellRadiusMeters: 50)
                ]
            )
        ]
    }
}
