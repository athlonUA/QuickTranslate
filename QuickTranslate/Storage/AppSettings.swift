import Foundation
import Combine

/// Persistent app state.
///
/// Three stores are coordinated:
/// - `UserDefaults` for the hotkey, target language, and last translation;
/// - Keychain (`KeychainAPIKeyStore`) for the DeepL API key;
/// - in-memory cache for everything `@Published` so SwiftUI reflects changes
///   without a `UserDefaults` round-trip on every read.
///
/// The `apiKey` setter mirrors writes into the Keychain via `didSet`, so the
/// in-memory cache and the secure store never drift apart.
@MainActor
final class AppSettings: ObservableObject {
    static let hotkeyKey = "quicktranslate.hotkey"
    static let targetLanguageKey = "quicktranslate.targetLanguage"
    static let lastSourceKey = "quicktranslate.lastSourceText"
    static let lastTranslationKey = "quicktranslate.lastTranslation"
    static let lastDetectedSourceCodeKey = "quicktranslate.lastDetectedSourceCode"

    /// Hard cap on persisted text size, applied symmetrically to source and
    /// translation. Anything longer than this is still translated in full —
    /// only the "show on next launch" cache is bounded.
    static let lastTextMaxBytes = 256 * 1024

    @Published var hotkey: Hotkey {
        didSet { persistHotkey(hotkey) }
    }

    @Published var targetLanguage: Language {
        didSet {
            defaults.set(targetLanguage.rawValue, forKey: Self.targetLanguageKey)
        }
    }

    @Published var apiKey: String {
        didSet { _ = keychain.saveKey(apiKey) }
    }

    @Published var lastSource: String? {
        didSet { persistText(lastSource, forKey: Self.lastSourceKey) }
    }

    @Published var lastTranslation: String? {
        didSet { persistText(lastTranslation, forKey: Self.lastTranslationKey) }
    }

    @Published var lastDetectedSourceCode: String? {
        didSet {
            if let code = lastDetectedSourceCode, !code.isEmpty {
                defaults.set(code, forKey: Self.lastDetectedSourceCodeKey)
            } else {
                defaults.removeObject(forKey: Self.lastDetectedSourceCodeKey)
            }
        }
    }

    private let defaults: UserDefaults
    private let keychain: APIKeyStore

    init(defaults: UserDefaults = .standard,
         keychain: APIKeyStore = KeychainAPIKeyStore()) {
        self.defaults = defaults
        self.keychain = keychain

        if let data = defaults.data(forKey: Self.hotkeyKey),
           let stored = try? JSONDecoder().decode(Hotkey.self, from: data) {
            self.hotkey = stored
        } else {
            self.hotkey = .default
        }

        if let raw = defaults.string(forKey: Self.targetLanguageKey),
           let lang = Language(rawValue: raw) {
            self.targetLanguage = lang
        } else {
            self.targetLanguage = .englishUS
        }

        self.apiKey = keychain.loadKey() ?? ""

        self.lastSource = Self.readTrimmedString(from: defaults, key: Self.lastSourceKey)
        self.lastTranslation = Self.readTrimmedString(from: defaults, key: Self.lastTranslationKey)
        self.lastDetectedSourceCode = Self.readTrimmedString(from: defaults, key: Self.lastDetectedSourceCodeKey)
    }

    private static func readTrimmedString(from defaults: UserDefaults, key: String) -> String? {
        guard let stored = defaults.string(forKey: key), !stored.isEmpty else {
            return nil
        }
        return stored
    }

    private func persistHotkey(_ hotkey: Hotkey) {
        if let data = try? JSONEncoder().encode(hotkey) {
            defaults.set(data, forKey: Self.hotkeyKey)
        }
    }

    private func persistText(_ text: String?, forKey key: String) {
        guard let text, !text.isEmpty else {
            defaults.removeObject(forKey: key)
            return
        }
        // Single forward pass over grapheme clusters: append while under
        // budget, stop at the first cluster that would overflow. Replaces a
        // `while-removeLast` loop that recomputed `utf8.count` over the
        // entire string on every iteration (O(n²) worst case).
        if text.utf8.count <= Self.lastTextMaxBytes {
            defaults.set(text, forKey: key)
            return
        }
        var truncated = ""
        truncated.reserveCapacity(Self.lastTextMaxBytes)
        var byteCount = 0
        for character in text {
            let characterBytes = String(character).utf8.count
            if byteCount + characterBytes > Self.lastTextMaxBytes { break }
            truncated.append(character)
            byteCount += characterBytes
        }
        defaults.set(truncated, forKey: key)
    }
}
