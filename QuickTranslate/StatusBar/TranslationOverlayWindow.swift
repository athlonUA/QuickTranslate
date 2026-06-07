import AppKit
import SwiftUI

/// Floating panel that displays the latest translation (or an error) above
/// every other window.
///
/// Why an `NSPanel` instead of a SwiftUI scene or a popover:
/// - The user explicitly wants the result "поверх всех окон" / above all
///   windows — `NSPanel.level = .floating` does that natively.
/// - Esc must close it. `onKeyPress(.escape)` in the SwiftUI body works only
///   once the panel is key, which is why we call `makeKeyAndOrderFront` plus
///   `NSApp.activate` on present.
/// - Re-presenting with new data only updates the published `model.content`;
///   the panel itself is recycled, so opening/closing/opening again costs
///   nothing.
///
/// Lifetime: the panel is created lazily on first `present`, lives until the
/// app quits, and is shown/hidden via `orderOut(_:)`.
@MainActor
final class TranslationOverlayWindow {
    private var panel: NSPanel?
    private let model = TranslationOverlayModel()

    func present(translation text: String, target: Language, detected: String?) {
        model.content = .translation(text: text, target: target, detected: detected)
        show()
    }

    func presentError(_ message: String) {
        model.content = .error(message)
        show()
    }

    func dismiss() {
        panel?.orderOut(nil)
    }

    // MARK: - Private

    private func show() {
        ensurePanel()
        // Activating the app lets the panel take key status so SwiftUI's
        // `onKeyPress(.escape)` fires on the first Esc press.
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }

    private func ensurePanel() {
        guard panel == nil else { return }

        let view = TranslationOverlayView(
            model: model,
            onClose: { [weak self] in self?.dismiss() }
        )
        let hosting = NSHostingController(rootView: view)

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 200),
            // No `.utilityWindow` — that style mask gives a slim title bar
            // with miniature traffic-light buttons. Standard panel chrome
            // here so the close/minimize/zoom controls match the rest of
            // macOS at normal size.
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.contentViewController = hosting
        p.title = "Quick Translate"
        p.level = .floating
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = false
        p.collectionBehavior = [.canJoinAllSpaces, .stationary]
        p.isReleasedWhenClosed = false
        // No `appearance` override — the panel inherits the system effective
        // appearance, so it auto-tracks light/dark mode like the menubar
        // popover does.
        p.center()

        panel = p
    }
}
