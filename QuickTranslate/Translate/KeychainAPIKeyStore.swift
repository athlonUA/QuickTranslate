import Foundation
import Security

/// Read/write contract for the DeepL API key. The production implementation
/// hits the user's Keychain; tests substitute an in-memory fake so they don't
/// pollute the real keychain.
protocol APIKeyStore {
    func loadKey() -> String?
    @discardableResult
    func saveKey(_ key: String) -> Bool
    @discardableResult
    func deleteKey() -> Bool
}

/// In-memory `APIKeyStore` used by unit tests. Lives in the production module
/// (rather than the test target) so any future preview / debug UI can also
/// opt out of touching the real keychain without copy-pasting the impl.
final class InMemoryAPIKeyStore: APIKeyStore {
    private var value: String?

    init(initial: String? = nil) {
        self.value = initial
    }

    func loadKey() -> String? {
        guard let v = value, !v.isEmpty else { return nil }
        return v
    }

    @discardableResult
    func saveKey(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            value = nil
        } else {
            value = trimmed
        }
        return true
    }

    @discardableResult
    func deleteKey() -> Bool {
        value = nil
        return true
    }
}

/// Persists the DeepL API key as a generic password in the user's login
/// keychain. The service uses a single fixed account so the entry is unique;
/// callers don't need to pass an account identifier.
///
/// Why Keychain instead of `UserDefaults`:
/// - API key is a paid credential — leaking it via a plist backup is a real
///   cost, not just a theoretical risk.
/// - The login keychain is unlocked the same way the user already unlocks
///   their Mac, so this is a free UX improvement.
///
/// All methods are synchronous: the Security framework calls run in
/// microseconds and don't merit an async hop.
struct KeychainAPIKeyStore: APIKeyStore {
    /// Default service identifier used by the production app.
    static let defaultService = "com.alexgarmatenko.QuickTranslate.DeepLKey"
    /// Fixed account name — there's only one DeepL key per user.
    static let account = "deepl"

    private let service: String

    init(service: String = KeychainAPIKeyStore.defaultService) {
        self.service = service
    }

    /// Returns the stored key, or `nil` if no entry exists. Any other error
    /// (corrupt entry, kSec read failure) is mapped to `nil` so callers can
    /// treat "couldn't read" identically to "no key set" — the UI banner
    /// telling the user to add a key is the same either way.
    func loadKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8) else {
            return nil
        }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Writes the key, replacing any existing entry. Passing an empty string
    /// deletes the entry instead, so the "Clear" button in the popover can
    /// route through a single setter.
    @discardableResult
    func saveKey(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return deleteKey()
        }
        guard let data = trimmed.data(using: .utf8) else { return false }

        // Update if present, otherwise add. We don't pre-check existence —
        // SecItemUpdate returning errSecItemNotFound is the trigger to add.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.account,
        ]
        let attributesToUpdate: [String: Any] = [
            kSecValueData as String: data,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        if updateStatus != errSecItemNotFound { return false }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        return addStatus == errSecSuccess
    }

    /// Removes the entry. `errSecItemNotFound` counts as success because the
    /// post-condition (no key in keychain) is satisfied either way.
    @discardableResult
    func deleteKey() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
