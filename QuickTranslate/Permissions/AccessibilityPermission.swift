import AppKit
import ApplicationServices

enum AccessibilityAuthorization: Equatable {
    case notDetermined
    case granted
    case denied
}

/// Coordinates the Accessibility permission — required to read selected text
/// from the focused app via `AXUIElement`.
///
/// macOS does not push permission changes to a running process, so this class
/// caches the last-known status, exposes `refresh()` for explicit re-checks
/// (e.g. when the popover opens), and tracks a `didRequest` flag so we can
/// distinguish "user has never been asked" from "user denied".
///
/// Note: Quick Translate degrades gracefully without Accessibility — the
/// clipboard fallback still works. The permission only unlocks the
/// higher-priority "selected text" source.
@MainActor
final class AccessibilityPermissionService: ObservableObject {
    static let didRequestKey = "quicktranslate.didRequestAccessibility"

    @Published private(set) var status: AccessibilityAuthorization = .notDetermined

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        refresh()
    }

    func refresh() {
        if AXIsProcessTrusted() {
            status = .granted
            return
        }
        let didRequest = defaults.bool(forKey: Self.didRequestKey)
        status = didRequest ? .denied : .notDetermined
    }

    /// Triggers the standard macOS prompt the first time. Subsequent calls
    /// will silently no-op — the user must enable the toggle in System Settings.
    @discardableResult
    func request() -> Bool {
        defaults.set(true, forKey: Self.didRequestKey)
        // The system prompt is shown lazily by `AXIsProcessTrustedWithOptions`
        // when `kAXTrustedCheckOptionPrompt` is true. It also returns the
        // current trust state — but we still call `refresh()` to keep the
        // single source of truth in `status`.
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        let granted = AXIsProcessTrustedWithOptions(options)
        refresh()
        return granted
    }

    func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
