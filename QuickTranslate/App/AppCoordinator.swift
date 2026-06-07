import AppKit
import Combine

/// Central orchestrator. Wires the hotkey, source-text resolver (selected
/// text or clipboard fallback), DeepL service, settings, inline hotkey
/// capture, and the floating translation overlay.
///
/// Lifecycle:
/// 1. On init: register the global hotkey from `AppSettings.hotkey`.
/// 2. Hotkey press → resolve source → DeepL → store last translation → push
///    the result (or error) into the floating overlay panel.
/// 3. "Change hotkey" inline-capture: local NSEvent monitor → Esc cancels,
///    valid combo saves and re-registers globally, app-resigning-active also
///    cancels so the recorder can never get stuck.
///
/// **Re-entrancy.** `runTranslateFlow` guards on `isWorking` so a second
/// hotkey press while a DeepL request is in flight is a no-op — the user
/// can't accidentally queue two parallel requests against the same key.
@MainActor
final class AppCoordinator: ObservableObject {
    /// True while a translation request is in flight. Menu rows and the
    /// status-bar icon read this to dim/animate and to debounce repeats.
    @Published private(set) var isWorking: Bool = false
    /// Last user-facing error. Cleared at the start of the next run.
    @Published private(set) var lastError: String?
    /// True while the popover's hotkey row is waiting for the user to press
    /// a new shortcut. Drives the inline "Press shortcut…/Cancel" affordance.
    @Published private(set) var isCapturingHotkey: Bool = false

    let storage: AppSettings
    let accessibility: AccessibilityPermissionService

    private let hotkeyManager = HotkeyManager()
    private let deepL: DeepLService
    private let clipboard: ClipboardService
    private let selection: SelectedTextService
    private let overlay = TranslationOverlayWindow()

    private var captureMonitor: Any?
    private var captureResignActiveObserver: NSObjectProtocol?

    init(storage: AppSettings,
         accessibility: AccessibilityPermissionService,
         deepL: DeepLService = DeepLService(),
         clipboard: ClipboardService = ClipboardService(),
         selection: SelectedTextService = SelectedTextService()) {
        self.storage = storage
        self.accessibility = accessibility
        self.deepL = deepL
        self.clipboard = clipboard
        self.selection = selection

        hotkeyManager.onTrigger = { [weak self] in
            Task { @MainActor [weak self] in
                await self?.runTranslateFlow()
            }
        }
        if !hotkeyManager.register(storage.hotkey) {
            lastError = "Could not register \(storage.hotkey.description). The combination may already be taken by another app — set a new one from the menu."
        }
    }

    // No deinit teardown: the coordinator lives for the entire app lifetime
    // (owned by `@StateObject` in `QuickTranslateApp`). Process termination
    // reaps any in-flight NSEvent monitor or notification observer — there's
    // nothing safe to do from a nonisolated deinit that we aren't already
    // getting for free from ARC + process exit.

    // MARK: - Hotkey flow

    func runTranslateFlow() async {
        guard !isWorking else { return }
        lastError = nil

        guard let source = resolveSource() else {
            let message = "Nothing to translate — select text on screen or copy something first."
            lastError = message
            overlay.presentError(message)
            return
        }

        let apiKey = storage.apiKey
        let target = storage.targetLanguage

        isWorking = true
        defer { isWorking = false }
        accessibility.refresh()

        do {
            let result = try await deepL.translate(text: source, target: target, apiKey: apiKey)
            storage.lastSource = result.source
            storage.lastTranslation = result.translated
            storage.lastDetectedSourceCode = result.detectedSourceCode
            overlay.present(
                translation: result.translated,
                target: result.target,
                detected: result.detectedSourceCode
            )
        } catch {
            let message = errorMessage(error)
            lastError = message
            overlay.presentError(message)
        }
    }

    /// Source-text priority cascade:
    /// 1. Selected text from the focused app (requires Accessibility).
    /// 2. Clipboard contents.
    /// Returns `nil` only if both are empty.
    func resolveSource() -> String? {
        if let selected = selection.currentSelection(),
           !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return selected
        }
        if let clipboard = clipboard.currentString(),
           !clipboard.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return clipboard
        }
        return nil
    }

    // MARK: - Menu actions

    func copyLastTranslation() {
        guard let text = storage.lastTranslation, !text.isEmpty else { return }
        clipboard.copy(text)
    }

    // MARK: - Inline hotkey capture

    /// Start capturing the next keystroke as the new hotkey. The popover row
    /// switches to "Press shortcut… Cancel" while `isCapturingHotkey` is true.
    /// Esc inside the popover cancels; valid combos save+register; the app
    /// becoming inactive also cancels so the recorder can never wedge.
    func startHotkeyCapture() {
        cleanupCaptureMonitors()
        isCapturingHotkey = true

        captureMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleCaptureEvent(event)
        }
        // Popover loses key window if the user clicks elsewhere; without this
        // the recorder stays "armed" forever and never sees the next stroke.
        captureResignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.cancelHotkeyCapture() }
        }
    }

    func cancelHotkeyCapture() {
        guard isCapturingHotkey else { return }
        cleanupCaptureMonitors()
        isCapturingHotkey = false
    }

    private func handleCaptureEvent(_ event: NSEvent) -> NSEvent? {
        // Esc always cancels — by convention, regardless of modifier state.
        // Means a user genuinely wanting Cmd+Esc cannot record it; an
        // acceptable trade for a clear escape hatch from the recorder.
        if event.keyCode == 53 {
            cancelHotkeyCapture()
            return nil
        }
        let keyCode = Int64(event.keyCode)
        let flags = UInt64(event.modifierFlags.rawValue) & Hotkey.modifierMask
        guard Hotkey.isValidForGlobal(keyCode: keyCode, flags: flags) else {
            // Consume the event silently so the rejected letter doesn't leak
            // into whatever control was focused (e.g. the API-key SecureField).
            return nil
        }
        let newHotkey = Hotkey(keyCode: keyCode, flags: flags)
        cleanupCaptureMonitors()
        isCapturingHotkey = false
        applyHotkey(newHotkey)
        return nil
    }

    private func cleanupCaptureMonitors() {
        if let captureMonitor {
            NSEvent.removeMonitor(captureMonitor)
            self.captureMonitor = nil
        }
        if let observer = captureResignActiveObserver {
            NotificationCenter.default.removeObserver(observer)
            captureResignActiveObserver = nil
        }
    }

    private func applyHotkey(_ hotkey: Hotkey) {
        let previous = storage.hotkey
        if hotkeyManager.register(hotkey) {
            storage.hotkey = hotkey
            return
        }
        if !hotkeyManager.register(previous) {
            lastError = "Failed to register \(hotkey.description), and could not restore \(previous.description) either."
        } else {
            lastError = "Failed to register \(hotkey.description). It may be taken by another app — keeping \(previous.description)."
        }
    }

    // MARK: - Quit

    func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Helpers

    private func errorMessage(_ error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}
