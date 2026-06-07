import XCTest
import Carbon.HIToolbox
import CoreGraphics
@testable import QuickTranslate

@MainActor
final class AppSettingsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var keychain: InMemoryAPIKeyStore!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "test.quicktranslate.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        keychain = InMemoryAPIKeyStore()
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        keychain = nil
        suiteName = nil
        try await super.tearDown()
    }

    // MARK: - Hotkey

    func test_init_withoutStoredValues_usesDefaults() {
        let settings = AppSettings(defaults: defaults, keychain: keychain)
        XCTAssertEqual(settings.hotkey, .default)
        XCTAssertEqual(settings.targetLanguage, .englishUS)
        XCTAssertNil(settings.lastSource)
        XCTAssertNil(settings.lastTranslation)
        XCTAssertNil(settings.lastDetectedSourceCode)
        XCTAssertEqual(settings.apiKey, "")
    }

    func test_init_loadsStoredHotkey() throws {
        let custom = Hotkey(
            keyCode: Int64(kVK_ANSI_K),
            flags: CGEventFlags.maskCommand.rawValue | CGEventFlags.maskAlternate.rawValue
        )
        let data = try JSONEncoder().encode(custom)
        defaults.set(data, forKey: AppSettings.hotkeyKey)

        let settings = AppSettings(defaults: defaults, keychain: keychain)
        XCTAssertEqual(settings.hotkey, custom)
    }

    func test_updatingHotkey_persistsToDefaults() throws {
        let settings = AppSettings(defaults: defaults, keychain: keychain)
        let updated = Hotkey(
            keyCode: Int64(kVK_F5),
            flags: CGEventFlags.maskCommand.rawValue
        )
        settings.hotkey = updated

        let raw = try XCTUnwrap(defaults.data(forKey: AppSettings.hotkeyKey))
        let decoded = try JSONDecoder().decode(Hotkey.self, from: raw)
        XCTAssertEqual(decoded, updated)
    }

    // MARK: - Target language

    func test_targetLanguage_persistsAcrossInit() {
        let settings = AppSettings(defaults: defaults, keychain: keychain)
        settings.targetLanguage = .russian

        let reopened = AppSettings(defaults: defaults, keychain: keychain)
        XCTAssertEqual(reopened.targetLanguage, .russian)
    }

    func test_targetLanguage_fallsBackToEnglishUSWhenStoredValueIsUnknown() {
        defaults.set("ZZ", forKey: AppSettings.targetLanguageKey)
        let settings = AppSettings(defaults: defaults, keychain: keychain)
        XCTAssertEqual(settings.targetLanguage, .englishUS)
    }

    // MARK: - API key

    func test_apiKey_persistsThroughKeychain() {
        let settings = AppSettings(defaults: defaults, keychain: keychain)
        settings.apiKey = "deepl-key:fx"

        XCTAssertEqual(keychain.loadKey(), "deepl-key:fx")

        let reopened = AppSettings(defaults: defaults, keychain: keychain)
        XCTAssertEqual(reopened.apiKey, "deepl-key:fx")
    }

    func test_apiKey_clearingRemovesFromKeychain() {
        keychain.saveKey("pre-existing:fx")
        let settings = AppSettings(defaults: defaults, keychain: keychain)
        XCTAssertEqual(settings.apiKey, "pre-existing:fx")

        settings.apiKey = ""
        XCTAssertNil(keychain.loadKey())
    }

    // MARK: - Last source / translation

    func test_updatingLastTranslation_persists() {
        let settings = AppSettings(defaults: defaults, keychain: keychain)
        settings.lastTranslation = "Привет"
        XCTAssertEqual(defaults.string(forKey: AppSettings.lastTranslationKey), "Привет")
    }

    func test_clearingLastTranslation_removesValue() {
        defaults.set("stale", forKey: AppSettings.lastTranslationKey)
        let settings = AppSettings(defaults: defaults, keychain: keychain)
        settings.lastTranslation = nil
        XCTAssertNil(defaults.string(forKey: AppSettings.lastTranslationKey))
    }

    func test_emptyLastTranslation_removesValue() {
        let settings = AppSettings(defaults: defaults, keychain: keychain)
        settings.lastTranslation = "non-empty"
        settings.lastTranslation = ""
        XCTAssertNil(defaults.string(forKey: AppSettings.lastTranslationKey))
    }

    func test_oversizedLastTranslation_isTruncatedByteBudget() {
        let settings = AppSettings(defaults: defaults, keychain: keychain)
        let huge = String(repeating: "a", count: AppSettings.lastTextMaxBytes + 2048)
        settings.lastTranslation = huge

        let stored = defaults.string(forKey: AppSettings.lastTranslationKey)
        XCTAssertNotNil(stored)
        XCTAssertLessThanOrEqual(stored!.utf8.count, AppSettings.lastTextMaxBytes)
    }

    func test_lastSource_persists() {
        let settings = AppSettings(defaults: defaults, keychain: keychain)
        settings.lastSource = "Hello"
        XCTAssertEqual(defaults.string(forKey: AppSettings.lastSourceKey), "Hello")
    }

    func test_lastDetectedSourceCode_persists() {
        let settings = AppSettings(defaults: defaults, keychain: keychain)
        settings.lastDetectedSourceCode = "EN"
        XCTAssertEqual(defaults.string(forKey: AppSettings.lastDetectedSourceCodeKey), "EN")
    }

    func test_lastDetectedSourceCode_nilClearsValue() {
        defaults.set("EN", forKey: AppSettings.lastDetectedSourceCodeKey)
        let settings = AppSettings(defaults: defaults, keychain: keychain)
        settings.lastDetectedSourceCode = nil
        XCTAssertNil(defaults.string(forKey: AppSettings.lastDetectedSourceCodeKey))
    }
}
