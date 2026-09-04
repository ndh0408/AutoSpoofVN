import Foundation

/// Quản lý lưu trữ — Codable files cho structured data, UserDefaults cho preferences.
final class PersistenceManager {
    static let shared = PersistenceManager()

    private let fileManager = FileManager.default
    private let documentsURL: URL

    private init() {
        documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    // MARK: - Routes

    private var routesURL: URL { documentsURL.appendingPathComponent("routes.json") }

    func saveRoutes(_ routes: [SavedRoute]) {
        save(routes, to: routesURL)
    }

    func loadRoutes() -> [SavedRoute] {
        load(from: routesURL) ?? []
    }

    /// Ghi danh sách tuyến đã được mã hoá sẵn.
    ///
    /// Cho phép nơi gọi mã hoá trên main actor rồi chuyển `Data` (Sendable) sang hàng đợi
    /// nền, thay vì đẩy `[SavedRoute]` qua ranh giới thread.
    func saveRoutesData(_ data: Data) {
        do {
            try data.write(to: routesURL, options: .atomic)
        } catch {
            AppLogger.persist.error("Khong ghi duoc routes.json: \(error.localizedDescription)")
        }
    }

    // MARK: - Scenarios

    private var scenariosURL: URL { documentsURL.appendingPathComponent("scenarios.json") }

    func saveScenarios(_ scenarios: [Scenario]) {
        save(scenarios, to: scenariosURL)
    }

    func loadScenarios() -> [Scenario] {
        load(from: scenariosURL) ?? []
    }

    // MARK: - Routines

    private var routinesURL: URL { documentsURL.appendingPathComponent("routines.json") }

    func saveRoutineSchedules(_ schedules: [RoutineSchedule]) {
        save(schedules, to: routinesURL)
    }

    func loadRoutineSchedules() -> [RoutineSchedule] {
        load(from: routinesURL) ?? []
    }

    // MARK: - Bookmarks

    private var bookmarksURL: URL { documentsURL.appendingPathComponent("bookmarks.json") }

    func saveBookmarks(_ bookmarks: [LocationBookmark]) {
        save(bookmarks, to: bookmarksURL)
    }

    func loadBookmarks() -> [LocationBookmark] {
        load(from: bookmarksURL) ?? []
    }

    // MARK: - History

    private var historyURL: URL { documentsURL.appendingPathComponent("history.json") }

    func saveHistory(_ records: [SimulationRecord]) {
        save(records, to: historyURL)
    }

    func loadHistory() -> [SimulationRecord] {
        load(from: historyURL) ?? []
    }

    func appendHistory(_ record: SimulationRecord) {
        var records = loadHistory()
        records.insert(record, at: 0)
        // Giữ tối đa 500 records
        if records.count > 500 {
            records = Array(records.prefix(500))
        }
        saveHistory(records)
    }

    // MARK: - Settings

    struct AppSettings: Codable {
        var noiseConfig: GPSNoiseConfig = .normal
        var defaultTravelMode: TravelMode = .driving
        var deviceUpdateRateHz: Double = 1.0
        var simulationTickRateHz: Double = 10.0
        var mapFollowMode: Bool = true
        var map3DEnabled: Bool = false
        var mapStyle: String = "standard"
        var trailEnabled: Bool = true
        var trailMaxPoints: Int = 1000
        var autoReconnect: Bool = true
        var heartbeatIntervalSeconds: Double = 20
        var backgroundKeepAlive: Bool = true
        var appearance: String = "system"  // light, dark, system
        var showDeveloperInfo: Bool = false
    }

    private let settingsKey = "locationx_settings_v2"

    func saveSettings(_ settings: AppSettings) {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: settingsKey)
        }
    }

    func loadSettings() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: settingsKey),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        else { return AppSettings() }
        return settings
    }

    // MARK: - GPX Import/Export

    func exportGPX(coordinates: [CoordinateCodable], name: String) -> URL? {
        var gpx = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        gpx += "<gpx version=\"1.1\" creator=\"LocationX\">\n"
        gpx += "  <trk><name>\(name)</name><trkseg>\n"
        for coord in coordinates {
            gpx += "    <trkpt lat=\"\(coord.latitude)\" lon=\"\(coord.longitude)\"/>\n"
        }
        gpx += "  </trkseg></trk>\n</gpx>"

        let url = documentsURL.appendingPathComponent("\(name).gpx")
        try? gpx.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func importGPX(from url: URL) -> [CoordinateCodable]? {
        guard let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8)
        else { return nil }

        // Simple GPX parser — extract trkpt coordinates
        var coordinates: [CoordinateCodable] = []
        let pattern = #"lat="([^"]+)"\s+lon="([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(content.startIndex..., in: content)
        regex.enumerateMatches(in: content, range: range) { match, _, _ in
            guard let match,
                  let latRange = Range(match.range(at: 1), in: content),
                  let lonRange = Range(match.range(at: 2), in: content),
                  let lat = Double(content[latRange]),
                  let lon = Double(content[lonRange]),
                  (-90...90).contains(lat),
                  (-180...180).contains(lon)
            else { return }
            coordinates.append(CoordinateCodable(latitude: lat, longitude: lon))
        }
        return coordinates.isEmpty ? nil : coordinates
    }

    // MARK: - Generic

    private func save<T: Encodable>(_ value: T, to url: URL) {
        do {
            let data = try JSONEncoder().encode(value)
            try data.write(to: url, options: .atomic)
        } catch {
            // Log error in production
        }
    }

    private func load<T: Decodable>(from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
