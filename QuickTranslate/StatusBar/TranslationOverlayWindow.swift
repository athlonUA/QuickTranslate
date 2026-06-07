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
        // Recover from a stale off-screen frame (e.g. the user resized the
        // panel on an external display, disconnected it, and now the saved
        // frame intersects no live screen). Recentre rather than leaving the
        // panel invisible.
        if let panel,
           !NSScreen.screens.contains(where: { $0.frame.intersects(panel.frame) }) {
            panel.center()
        }
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
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 360),
            // `.resizable` lets the user drag the corner to fit longer
            // translations — without it the panel was stuck at the initial
            // size and forced scrolling on 4+ line results. No
            // `.utilityWindow` because that gives miniature traffic-light
            // buttons; standard panel chrome reads as a normal macOS window.
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.contentViewController = hosting
        // Assigning `contentViewController` makes the panel auto-fit the
        // SwiftUI view's intrinsic content size, which overrides the
        // `contentRect` we passed to the initializer. Force the size back
        // explicitly so the FIRST present opens at the configured default.
        // Subsequent presents reuse whatever size the user dragged the panel
        // to last — that "sticky" behaviour is deliberate (translation-tool
        // muscle memory) rather than re-applying the default each show.
        p.setContentSize(NSSize(width: 720, height: 360))
        p.title = "Quick Translate"
        p.level = .floating
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = false
        p.collectionBehavior = [.canJoinAllSpaces, .stationary]
        p.isReleasedWhenClosed = false
        // Prevents macOS from restoring a smaller saved size between runs.
        p.isRestorable = false
        // Floor on resize so the user can't accidentally drag the panel
        // into uselessness. No `maxSize` — long technical translations may
        // legitimately want a large panel.
        p.minSize = NSSize(width: 380, height: 220)
        // No `appearance` override — the panel inherits the system effective
        // appearance, so it auto-tracks light/dark mode like the menubar
        // popover does.
        p.center()

        panel = p
    }
}
