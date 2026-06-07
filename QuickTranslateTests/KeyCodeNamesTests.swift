import XCTest
@testable import QuickTranslate

final class KeyCodeNamesTests: XCTestCase {

    func test_name_letters() {
        XCTAssertEqual(KeyCodeNames.name(for: 0), "A")
        XCTAssertEqual(KeyCodeNames.name(for: 17), "T")
        XCTAssertEqual(KeyCodeNames.name(for: 6), "Z")
    }

    func test_name_digits() {
        XCTAssertEqual(KeyCodeNames.name(for: 29), "0")
        XCTAssertEqual(KeyCodeNames.name(for: 18), "1")
        XCTAssertEqual(KeyCodeNames.name(for: 25), "9")
    }

    func test_name_functionKeys() {
        XCTAssertEqual(KeyCodeNames.name(for: 122), "F1")
        XCTAssertEqual(KeyCodeNames.name(for: 111), "F12")
    }

    func test_name_specialKeys() {
        XCTAssertEqual(KeyCodeNames.name(for: 49), "Space")
        XCTAssertEqual(KeyCodeNames.name(for: 36), "Return")
        XCTAssertEqual(KeyCodeNames.name(for: 53), "Escape")
    }

    func test_name_arrows() {
        XCTAssertEqual(KeyCodeNames.name(for: 123), "←")
        XCTAssertEqual(KeyCodeNames.name(for: 124), "→")
        XCTAssertEqual(KeyCodeNames.name(for: 125), "↓")
        XCTAssertEqual(KeyCodeNames.name(for: 126), "↑")
    }

    func test_name_unknownFallback() {
        XCTAssertEqual(KeyCodeNames.name(for: 12345), "Key 12345")
    }

    func test_isAlphanumeric_letters() {
        XCTAssertTrue(KeyCodeNames.isAlphanumeric(0))   // A
        XCTAssertTrue(KeyCodeNames.isAlphanumeric(17))  // T
    }

    func test_isAlphanumeric_digits() {
        XCTAssertTrue(KeyCodeNames.isAlphanumeric(18))  // 1
    }

    func test_isAlphanumeric_specialKeys() {
        XCTAssertFalse(KeyCodeNames.isAlphanumeric(49))   // Space
        XCTAssertFalse(KeyCodeNames.isAlphanumeric(122))  // F1
        XCTAssertFalse(KeyCodeNames.isAlphanumeric(53))   // Escape
    }
}
