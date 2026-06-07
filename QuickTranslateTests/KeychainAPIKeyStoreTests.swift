import XCTest
@testable import QuickTranslate

/// These tests hit the actual login Keychain but under a unique per-run
/// service identifier, so they don't collide with the production app's entry
/// or with other test runs in parallel.
final class KeychainAPIKeyStoreTests: XCTestCase {
    private var service: String!
    private var store: KeychainAPIKeyStore!

    override func setUp() {
        super.setUp()
        service = "test.quicktranslate.keychain.\(UUID().uuidString)"
        store = KeychainAPIKeyStore(service: service)
    }

    override func tearDown() {
        _ = store.deleteKey()
        store = nil
        service = nil
        super.tearDown()
    }

    func test_loadKey_returnsNilForEmptyStore() {
        XCTAssertNil(store.loadKey())
    }

    func test_saveThenLoad_roundTrip() {
        XCTAssertTrue(store.saveKey("test-key:fx"))
        XCTAssertEqual(store.loadKey(), "test-key:fx")
    }

    func test_saveTwice_overwritesPriorValue() {
        XCTAssertTrue(store.saveKey("first"))
        XCTAssertTrue(store.saveKey("second"))
        XCTAssertEqual(store.loadKey(), "second")
    }

    func test_saveEmpty_deletesEntry() {
        XCTAssertTrue(store.saveKey("non-empty"))
        XCTAssertTrue(store.saveKey(""))
        XCTAssertNil(store.loadKey())
    }

    func test_deleteKey_isIdempotent() {
        XCTAssertTrue(store.deleteKey()) // nothing to delete
        XCTAssertTrue(store.saveKey("x:fx"))
        XCTAssertTrue(store.deleteKey())
        XCTAssertTrue(store.deleteKey()) // double-delete is a no-op
        XCTAssertNil(store.loadKey())
    }

    func test_saveKey_trimsWhitespace() {
        XCTAssertTrue(store.saveKey("  padded:fx  "))
        XCTAssertEqual(store.loadKey(), "padded:fx")
    }
}
