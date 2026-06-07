import AppKit
import ApplicationServices

/// Reads the text currently selected in whichever app holds keyboard focus.
///
/// Uses the system-wide `AXUIElement` rather than per-app accessibility trees
/// so we can pull selection from any focused element across the desktop. The
/// service quietly returns `nil` whenever:
/// - Accessibility is not granted (the `AXUIElementCopyAttributeValue` calls
///   succeed but return an empty string under TCC restriction),
/// - the focused element doesn't expose `AXSelectedText`,
/// - the user has nothing selected.
///
/// All three are normal states for the priority cascade in `AppCoordinator`:
/// a `nil` here is the signal to fall back to clipboard, not an error to
/// surface to the user.
struct SelectedTextService {
    func currentSelection() -> String? {
        // System-wide root element. Cheap to create; no need to cache.
        let systemWide = AXUIElementCreateSystemWide()

        var focusedRef: AnyObject?
        let focusedError = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        )
        guard focusedError == .success, let focusedElement = focusedRef else { return nil }
        // Defensive type check — Electron, Java AWT, and some Catalyst surfaces
        // have been observed returning non-`AXUIElement` values for the
        // focused-element attribute. A force-cast there would crash the app
        // every time those apps were focused at hotkey time.
        guard CFGetTypeID(focusedElement) == AXUIElementGetTypeID() else { return nil }
        let focused = focusedElement as! AXUIElement

        var selectedRef: AnyObject?
        let selectedError = AXUIElementCopyAttributeValue(
            focused,
            kAXSelectedTextAttribute as CFString,
            &selectedRef
        )
        guard selectedError == .success, let text = selectedRef as? String else {
            return nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
