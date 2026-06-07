import AppKit
import Carbon.HIToolbox

/// Owns the global hotkey registration via Carbon `RegisterEventHotKey`.
///
/// Why Carbon and not `CGEventTap`:
/// - `RegisterEventHotKey` does NOT require the Accessibility permission;
///   it only needs the standard app event-target hook-up. The translate flow
///   wants Accessibility anyway (to read selected text), but the hotkey itself
///   must keep working even when Accessibility is denied — so we keep the
///   registration channel independent of TCC.
/// - We don't need to consume the keystroke from focused apps — only react.
///
/// **Single-instance invariant.** The Carbon API takes a C callback, so we
/// route through a static `activeManager` slot rather than `Unmanaged`. The
/// type is intended to be owned by exactly one component at a time
/// (`AppCoordinator`); creating a second instance silently steals the slot
/// from the first. Debug builds assert this; release builds tolerate the
/// situation but only the most recent registrant receives callbacks.
@MainActor
final class HotkeyManager {
    var onTrigger: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    private static let signature: OSType = {
        // FourCharCode "QTRA" — QuickTranslate. Just an identifier for the OS
        // so it can distinguish our hotkey from other Carbon-registered apps.
        let bytes: [UInt8] = [0x51, 0x54, 0x52, 0x41]
        return bytes.reduce(0) { ($0 << 8) | OSType($1) }
    }()
    private static let hotKeyID: UInt32 = 1

    init() {
        assert(Self.activeManager == nil,
               "HotkeyManager is a single-instance type; the previous instance was not torn down before a new one was created.")
    }

    deinit {
        // ARC releases us on the thread of the last reference; that's almost
        // always main (this type is `@MainActor` and owned by a `@MainActor`
        // coordinator), but the contract isn't enforced. Use only APIs that
        // are safe from any thread:
        // - Carbon `UnregisterEventHotKey` / `RemoveEventHandler` are
        //   thread-safe per the Carbon Event Manager docs.
        // - `Self.activeManager` is declared `nonisolated(unsafe)` so we may
        //   read/write it without an actor hop. The compare-and-clear race
        //   window is harmless: the worst outcome is a one-frame callback
        //   landing on a deallocated `onTrigger`, which we nilled in
        //   `unregister()` callers already.
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
        if Self.activeManager === self {
            Self.activeManager = nil
        }
    }

    /// Registers `hotkey` globally. Replaces any previously registered combo.
    /// Returns `false` if the OS refused (most commonly because the combo is
    /// already taken by a system shortcut).
    @discardableResult
    func register(_ hotkey: Hotkey) -> Bool {
        unregister()
        installHandlerIfNeeded()

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.hotKeyID)
        let status = RegisterEventHotKey(
            UInt32(hotkey.keyCode),
            hotkey.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else {
            return false
        }
        self.hotKeyRef = ref
        assert(Self.activeManager == nil || Self.activeManager === self,
               "Two HotkeyManagers are alive at once — only the most recent will receive callbacks.")
        Self.activeManager = self
        return true
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if Self.activeManager === self {
            Self.activeManager = nil
        }
    }

    // MARK: - Event handler installation

    private func installHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        var handler: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.handlerCallback,
            1,
            &spec,
            nil,
            &handler
        )
        if status == noErr {
            eventHandlerRef = handler
        }
    }

    /// Weak pointer to the currently registered manager. Read from the Carbon
    /// handler (which runs on the main run loop, then we re-dispatch to main
    /// to satisfy `@MainActor` `onTrigger` calls); written from
    /// `register`/`unregister`/`deinit`, all on the main thread.
    ///
    /// `nonisolated(unsafe)` is correct here because every actual access lands
    /// on the main thread; the singleton invariant (see type comment) keeps
    /// the slot from being trampled.
    nonisolated(unsafe) static weak var activeManager: HotkeyManager?

    private static let handlerCallback: EventHandlerUPP = { _, _, _ in
        DispatchQueue.main.async {
            HotkeyManager.activeManager?.onTrigger?()
        }
        return noErr
    }
}
