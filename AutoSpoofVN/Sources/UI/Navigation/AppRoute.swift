import Observation
import SwiftUI

// MARK: - Tab

/// Bon tab goc. `rawValue` duoc luu lai de app mo lai dung tab cu.
enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case map
    case routes
    case flight
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .map:      return L10n.tabMap
        case .routes:   return L10n.tabRoutes
        case .flight:   return L10n.tabFlight
        case .settings: return L10n.tabSettings
        }
    }

    /// Icon o trang thai khong chon.
    var symbol: String {
        switch self {
        case .map:      return "map"
        case .routes:   return "point.topleft.down.to.point.bottomright.curvepath"
        case .flight:   return "airplane"
        case .settings: return "gearshape"
        }
    }

    /// Icon o trang thai duoc chon — ban to (fill) theo quy uoc tab bar cua iOS.
    var selectedSymbol: String {
        switch self {
        case .map:      return "map.fill"
        case .routes:   return "point.topleft.down.to.point.bottomright.curvepath.fill"
        case .flight:   return "airplane"
        case .settings: return "gearshape.fill"
        }
    }
}

// MARK: - Sheet

/// Moi man hinh trinh bay dang modal.
///
/// Gom vao mot enum thay vi 12 co `@State private var showX = false` rai rac: cach cu
/// cho phep hai sheet cung bat mot luc (SwiftUI se nuot mot cai im lang) va khong cho
/// phep mo sheet tu mot man hinh khac.
enum AppSheet: Identifiable, Hashable {
    case routeStudio
    case scenarioStudio
    case routineStudio
    case deviceManager
    case settings
    case history
    case worldTravel
    case diagnostics
    case shadowrocketSetup
    case bookmarks
    case bypassTroubleshoot
    case telemetryDetail
    case manualCoordinate

    var id: Self { self }
}

// MARK: - Navigator

/// Trang thai dieu huong do UI so huu.
///
/// Day la state **thuan UI** (tab nao dang mo, sheet nao dang hien) nen dung
/// `@Observable`. Khong chua bat ky trang thai mo phong nao —
/// `SimulationCoordinator` van la nguon su that duy nhat cho phan do.
@Observable
final class AppNavigator {
    /// Tab dang chon.
    var selectedTab: AppTab = .map {
        didSet {
            guard selectedTab != oldValue else { return }
            UserDefaults.standard.set(selectedTab.rawValue, forKey: Self.lastTabKey)
        }
    }

    /// Sheet dang trinh bay (toi da mot).
    var presentedSheet: AppSheet?

    /// Duong dan dieu huong rieng cho tung tab — chuyen tab khong lam mat vi tri cu.
    var routesPath = NavigationPath()
    var flightPath = NavigationPath()
    var settingsPath = NavigationPath()

    private static let lastTabKey = "autospoof_last_tab"

    init() {
        if let raw = UserDefaults.standard.string(forKey: Self.lastTabKey),
           let tab = AppTab(rawValue: raw) {
            selectedTab = tab
        }
    }

    /// Mo mot sheet. Neu dang co sheet khac, dong truoc roi mo — SwiftUI khong xu ly
    /// duoc hai lenh present lien tiep trong cung mot vong cap nhat.
    func present(_ sheet: AppSheet) {
        if presentedSheet != nil, presentedSheet != sheet {
            presentedSheet = nil
            DispatchQueue.main.async { [weak self] in
                self?.presentedSheet = sheet
            }
        } else {
            presentedSheet = sheet
        }
    }

    func dismissSheet() {
        presentedSheet = nil
    }

    /// Chuyen tab kem haptic nhe.
    @MainActor
    func select(_ tab: AppTab) {
        guard tab != selectedTab else { return }
        AppHaptics.selection()
        selectedTab = tab
    }
}

// MARK: - Environment

private struct AppNavigatorKey: EnvironmentKey {
    @MainActor static let defaultValue = AppNavigator()
}

extension EnvironmentValues {
    var navigator: AppNavigator {
        get { self[AppNavigatorKey.self] }
        set { self[AppNavigatorKey.self] = newValue }
    }
}

// MARK: - Sheet destination

/// Anh xa `AppSheet` -> view that.
///
/// Mot cho duy nhat, nen them mot man hinh modal la sua mot cho — khong con nguy co
/// mot sheet duoc khai bao nhung khong bao gio hien (loi da xay ra voi RoutineStudioView).
struct AppSheetDestination: View {
    let sheet: AppSheet

    var body: some View {
        switch sheet {
        case .routeStudio:        RouteStudioView()
        case .scenarioStudio:     ScenarioStudioView()
        case .routineStudio:      RoutineStudioView()
        case .deviceManager:      DeviceManagerView()
        case .settings:           SettingsView()
        case .history:            HistoryView()
        case .worldTravel:        WorldTravelViewV2()
        case .diagnostics:        DiagnosticsV2View()
        case .shadowrocketSetup:  ShadowrocketSetupView()
        case .bookmarks:          BookmarksView()
        case .bypassTroubleshoot: BypassTroubleshootView()
        case .telemetryDetail:    TelemetryDetailSheet()
        case .manualCoordinate:   ManualCoordinateSheet()
        }
    }
}
