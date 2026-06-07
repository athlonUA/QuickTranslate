import XCTest
@testable import QuickTranslate

final class LanguageTests: XCTestCase {

    func test_allCases_haveDistinctDeepLCodes() {
        let codes = Language.allCases.map { $0.deepLCode }
        XCTAssertEqual(codes.count, Set(codes).count, "DeepL codes must be unique across the picker")
    }

    func test_allCases_haveNonEmptyDisplayNames() {
        for language in Language.allCases {
            XCTAssertFalse(language.displayName.isEmpty, "\(language.deepLCode) has no display name")
        }
    }

    func test_from_rawCode_directHit() {
        XCTAssertEqual(Language.from(rawCode: "EN-US"), .englishUS)
        XCTAssertEqual(Language.from(rawCode: "RU"), .russian)
        XCTAssertEqual(Language.from(rawCode: "PT-BR"), .portugueseBR)
    }

    func test_from_rawCode_isCaseInsensitive() {
        XCTAssertEqual(Language.from(rawCode: "en-us"), .englishUS)
        XCTAssertEqual(Language.from(rawCode: "ru"), .russian)
    }

    func test_from_rawCode_mapsBareEnglishToUS() {
        // DeepL's `detected_source_language` returns plain `EN`/`PT`. The
        // mapping keeps the badge in the popover non-empty when DeepL reports
        // the non-regional shorthand.
        XCTAssertEqual(Language.from(rawCode: "EN"), .englishUS)
        XCTAssertEqual(Language.from(rawCode: "PT"), .portuguesePT)
    }

    func test_from_rawCode_unknownReturnsNil() {
        XCTAssertNil(Language.from(rawCode: "ZZ"))
    }

    func test_codable_roundTrip() throws {
        let original = Language.russian
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Language.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
