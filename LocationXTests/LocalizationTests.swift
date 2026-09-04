import XCTest
@testable import LocationX

/// Kiểm thử lớp song ngữ.
///
/// Đây là lưới an toàn cho việc dịch: thêm chuỗi mới mà quên bản tiếng Anh, hoặc để lệch
/// định dạng `%d`/`%@` giữa hai ngôn ngữ, đều bị bắt ở đây thay vì hiện ra thành khoá thô
/// hoặc làm app crash lúc chạy.
final class LocalizationTests: XCTestCase {

    /// Nạp một `Localizable.strings` thành từ điển.
    private func strings(for code: String) throws -> [String: String] {
        let bundle = Bundle(for: type(of: self))
        // Test chạy hosted trong app nên chuỗi nằm ở bundle của app.
        let searchBundles = [Bundle.main, bundle]
        for b in searchBundles {
            if let lproj = b.path(forResource: code, ofType: "lproj"),
               let file = Bundle(path: lproj)?.path(forResource: "Localizable", ofType: "strings"),
               let dict = NSDictionary(contentsOfFile: file) as? [String: String] {
                return dict
            }
        }
        throw XCTSkip("Không tìm thấy \(code).lproj trong bundle")
    }

    // MARK: - Tính đầy đủ

    func testBothLanguagesHaveIdenticalKeySets() throws {
        let vi = try strings(for: "vi")
        let en = try strings(for: "en")

        XCTAssertFalse(vi.isEmpty, "vi.lproj rỗng")
        XCTAssertFalse(en.isEmpty, "en.lproj rỗng")

        let missingInEnglish = Set(vi.keys).subtracting(en.keys).sorted()
        let missingInVietnamese = Set(en.keys).subtracting(vi.keys).sorted()

        XCTAssertTrue(missingInEnglish.isEmpty,
                      "Thiếu bản tiếng Anh cho: \(missingInEnglish.prefix(20).joined(separator: ", "))")
        XCTAssertTrue(missingInVietnamese.isEmpty,
                      "Thiếu bản tiếng Việt cho: \(missingInVietnamese.prefix(20).joined(separator: ", "))")
    }

    func testNoEmptyTranslations() throws {
        for code in ["vi", "en"] {
            let table = try strings(for: code)
            let empty = table.filter { $0.value.trimmingCharacters(in: .whitespaces).isEmpty }
            XCTAssertTrue(empty.isEmpty,
                          "\(code): chuỗi rỗng ở \(empty.keys.sorted().prefix(10).joined(separator: ", "))")
        }
    }

    /// Bản dịch không được trùng y hệt khoá — đó là dấu hiệu quên dịch.
    func testNoTranslationEqualsItsKey() throws {
        for code in ["vi", "en"] {
            let table = try strings(for: code)
            let unresolved = table.filter { $0.key == $0.value }
            XCTAssertTrue(unresolved.isEmpty,
                          "\(code): chưa dịch \(unresolved.keys.sorted().prefix(10).joined(separator: ", "))")
        }
    }

    // MARK: - Định dạng

    /// `%d`, `%@`, `%.1f` phải khớp giữa hai ngôn ngữ.
    ///
    /// Lệch số lượng specifier là lỗi crash thật: `String(format:)` sẽ đọc tham số không
    /// tồn tại trên stack.
    func testFormatSpecifiersMatchAcrossLanguages() throws {
        let vi = try strings(for: "vi")
        let en = try strings(for: "en")

        var problems: [String] = []
        for (key, viValue) in vi {
            guard let enValue = en[key] else { continue }
            let viSpecs = Self.specifiers(in: viValue)
            let enSpecs = Self.specifiers(in: enValue)
            if viSpecs.sorted() != enSpecs.sorted() {
                problems.append("\(key): vi=\(viSpecs) en=\(enSpecs)")
            }
        }
        XCTAssertTrue(problems.isEmpty,
                      "Lệch định dạng:\n" + problems.prefix(15).joined(separator: "\n"))
    }

    private static func specifiers(in text: String) -> [String] {
        // %% là ký tự phần trăm thật, không phải specifier.
        let cleaned = text.replacingOccurrences(of: "%%", with: "")
        let pattern = "%[0-9.$]*[@dfsxu]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(cleaned.startIndex..., in: cleaned)
        return regex.matches(in: cleaned, range: range).compactMap {
            Range($0.range, in: cleaned).map { String(cleaned[$0]) }
        }
    }

    // MARK: - Tra chuỗi lúc chạy

    @MainActor
    func testLookupSwitchesWithSelectedLanguage() throws {
        let manager = LocalizationManager.shared
        let original = manager.language
        defer { manager.setLanguage(original) }

        manager.setLanguage(.vietnamese)
        let viStart = L("action.start")
        manager.setLanguage(.english)
        let enStart = L("action.start")

        XCTAssertFalse(viStart.isEmpty)
        XCTAssertFalse(enStart.isEmpty)
        XCTAssertNotEqual(viStart, "action.start", "không tra được chuỗi tiếng Việt")
        XCTAssertNotEqual(enStart, "action.start", "không tra được chuỗi tiếng Anh")
        XCTAssertNotEqual(viStart, enStart, "đổi ngôn ngữ nhưng chuỗi không đổi")
    }

    /// Khoá không tồn tại phải trả về chính nó — để lỗi lộ ra trên màn hình,
    /// thay vì âm thầm mất chữ.
    func testUnknownKeyFallsBackToKey() {
        let key = "khong.ton.tai.chac.chan.\(UUID().uuidString)"
        XCTAssertEqual(L(key), key)
    }

    func testEveryLanguageResolvesToARealBundleCode() {
        for language in AppLanguage.allCases {
            XCTAssertTrue(["vi", "en"].contains(language.resolvedCode),
                          "\(language) giải ra mã lạ: \(language.resolvedCode)")
        }
    }
}
