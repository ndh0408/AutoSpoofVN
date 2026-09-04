import Combine
import Foundation
import SwiftUI

// MARK: - AppLanguage

/// Ngôn ngữ hiển thị của ứng dụng.
enum AppLanguage: String, CaseIterable, Identifiable {
    /// Theo ngôn ngữ hệ thống của thiết bị.
    case system
    case vietnamese = "vi"
    case english = "en"

    var id: String { rawValue }

    /// Tên hiển thị — viết bằng chính ngôn ngữ đó, đúng quy ước của Apple: người dùng
    /// đang để máy tiếng Anh vẫn nhận ra dòng "Tiếng Việt".
    var displayName: String {
        switch self {
        case .system:     return L("language.system")
        case .vietnamese: return "Tiếng Việt"
        case .english:    return "English"
        }
    }

    var symbol: String {
        switch self {
        case .system:     return "iphone.gen3"
        case .vietnamese: return "character.bubble"
        case .english:    return "character.bubble"
        }
    }

    /// Mã `.lproj` thực sự dùng để tra chuỗi.
    var resolvedCode: String {
        switch self {
        case .system:
            // Ngôn ngữ ưa thích đầu tiên mà app có hỗ trợ; mặc định tiếng Việt.
            let preferred = Bundle.main.preferredLocalizations.first ?? "vi"
            return preferred.hasPrefix("en") ? "en" : "vi"
        case .vietnamese: return "vi"
        case .english:    return "en"
        }
    }
}

// MARK: - Kho bundle dùng chung

/// Giữ bundle ngôn ngữ hiện hành, đọc được từ **bất kỳ thread nào**.
///
/// Đây là lý do `L(...)` không phải `@MainActor`: chuỗi hiển thị nằm cả trong các enum
/// model (`SimulationSource.displayName`, `TravelMode.displayName`, `FlightPhase`...) vốn
/// được đọc từ nhiều ngữ cảnh — timer nền, Live Activity, engine. Nếu bắt tra chuỗi phải
/// ở main actor thì `@MainActor` sẽ lan ra khắp tầng model.
private final class LocalizedBundleBox: @unchecked Sendable {
    static let shared = LocalizedBundleBox()

    private let lock = NSLock()
    private var current: Bundle?
    private var fallback: Bundle?

    private init() {
        fallback = Self.bundle(for: "vi")
    }

    func set(code: String) {
        let resolved = Self.bundle(for: code)
        lock.lock()
        current = resolved
        lock.unlock()
    }

    /// Tra chuỗi: ngôn ngữ đang chọn → tiếng Việt (ngôn ngữ gốc dự án) → chính key.
    ///
    /// Trả về key khi thiếu bản dịch là cố ý: chuỗi lạ kiểu `route.detail.title` hiện
    /// trên màn hình thì lỗi lộ ra ngay, còn trả chuỗi rỗng thì âm thầm mất chữ.
    func string(_ key: String) -> String {
        lock.lock()
        let active = current
        let backup = fallback
        lock.unlock()

        if let active {
            let value = active.localizedString(forKey: key, value: Self.missing, table: nil)
            if value != Self.missing { return value }
        }
        if let backup {
            let value = backup.localizedString(forKey: key, value: Self.missing, table: nil)
            if value != Self.missing { return value }
        }
        return key
    }

    private static func bundle(for code: String) -> Bundle? {
        guard let path = Bundle.main.path(forResource: code, ofType: "lproj") else { return nil }
        return Bundle(path: path)
    }

    private static let missing = "\u{0}__missing__"
}

// MARK: - LocalizationManager

/// Quản lý ngôn ngữ hiển thị, độc lập với ngôn ngữ hệ thống.
///
/// `NSLocalizedString` chỉ đọc theo ngôn ngữ hệ thống nên **không** đổi được ngôn ngữ
/// trong app. Ở đây ta nạp thẳng bundle `.lproj` tương ứng, nhờ vậy người dùng chọn
/// Tiếng Việt / English ngay trong Cài đặt mà không phải đổi cài đặt máy.
@MainActor
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    private static let storageKey = "locationx_language"

    @Published private(set) var language: AppLanguage {
        didSet {
            guard language != oldValue else { return }
            UserDefaults.standard.set(language.rawValue, forKey: Self.storageKey)
            LocalizedBundleBox.shared.set(code: language.resolvedCode)
        }
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: Self.storageKey)
        let initial = saved.flatMap(AppLanguage.init(rawValue:)) ?? .system
        language = initial
        LocalizedBundleBox.shared.set(code: initial.resolvedCode)
    }

    func setLanguage(_ newValue: AppLanguage) {
        guard newValue != language else { return }
        AppHaptics.selection()
        language = newValue
    }
}

// MARK: - Hàm tra chuỗi

/// Tra chuỗi đã bản địa hoá. Dùng thay cho mọi chuỗi cứng: `Text(L("map.start_spoof"))`.
func L(_ key: String) -> String {
    LocalizedBundleBox.shared.string(key)
}

/// Bản có tham số, ví dụ `L("route.leg_count", 3)` với chuỗi `"%d chặng"`.
func L(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: LocalizedBundleBox.shared.string(key), arguments: arguments)
}

// MARK: - Đổi ngôn ngữ tức thì

private struct LanguageReloadModifier: ViewModifier {
    @ObservedObject private var manager = LocalizationManager.shared

    func body(content: Content) -> some View {
        content
            // Đổi `id` buộc SwiftUI dựng lại toàn bộ cây view, nên mọi lời gọi `L(...)`
            // được tính lại. Đổi ngôn ngữ là việc hiếm nên chi phí dựng lại không đáng kể,
            // đổi lại không phải cho từng view quan sát manager.
            .id(manager.language)
            .environment(\.locale, Locale(identifier: manager.language.resolvedCode))
    }
}

extension View {
    /// Gắn ở gốc app: đổi ngôn ngữ là toàn bộ giao diện đổi theo ngay lập tức.
    func localized() -> some View {
        modifier(LanguageReloadModifier())
    }
}
