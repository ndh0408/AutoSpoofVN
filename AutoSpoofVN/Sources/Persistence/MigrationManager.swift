import Foundation

/// Quản lý migration dữ liệu khi nâng cấp schema.
/// Không bao giờ xoá data cũ mà không migrate.
struct MigrationManager {
    static let currentVersion = 2
    private static let versionKey = "autospoof_data_version"

    static func runIfNeeded() {
        let stored = UserDefaults.standard.integer(forKey: versionKey)
        guard stored < currentVersion else { return }

        AppLogger.persist.info("Running migration from v\(stored) to v\(currentVersion)")

        if stored < 1 {
            migrateV0toV1()
        }
        if stored < 2 {
            migrateV1toV2()
        }

        UserDefaults.standard.set(currentVersion, forKey: versionKey)
        AppLogger.persist.info("Migration complete")
    }

    /// v0 → v1: migrate legacy pairing string to Data
    private static func migrateV0toV1() {
        if let legacy = UserDefaults.standard.string(forKey: "autospoof_pairing_plist"),
           !legacy.isEmpty {
            let data = Data(legacy.utf8)
            UserDefaults.standard.set(data, forKey: "autospoof_pairing_data")
            AppLogger.persist.info("Migrated legacy pairing plist to Data (\(data.count) bytes)")
        }
    }

    /// v1 → v2: migrate PlaceBookmark array to LocationBookmark
    private static func migrateV1toV2() {
        // Migrate old bookmarks format
        if let data = UserDefaults.standard.data(forKey: "autospoof_bookmarks"),
           let oldBookmarks = try? JSONDecoder().decode([PlaceBookmark].self, from: data) {
            let newBookmarks = oldBookmarks.map { old in
                LocationBookmark(
                    name: old.name,
                    coordinate: old.coordinate.clCoordinate,
                    category: .custom
                )
            }
            PersistenceManager.shared.saveBookmarks(newBookmarks)
            AppLogger.persist.info("Migrated \(oldBookmarks.count) bookmarks to v2 format")
        }

        // Migrate routine locations
        if let homeData = UserDefaults.standard.data(forKey: "autospoof_home_location"),
           let workData = UserDefaults.standard.data(forKey: "autospoof_work_location") {
            AppLogger.persist.info("Routine locations preserved (UserDefaults, no schema change)")
            _ = homeData; _ = workData // acknowledge existence
        }
    }
}
