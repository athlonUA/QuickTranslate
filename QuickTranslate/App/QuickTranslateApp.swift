import SwiftUI

@main
struct QuickTranslateApp: App {
    @StateObject private var storage: AppSettings
    @StateObject private var accessibility: AccessibilityPermissionService
    @StateObject private var coordinator: AppCoordinator

    init() {
        let storage = AppSettings()
        let accessibility = AccessibilityPermissionService()
        let coordinator = AppCoordinator(storage: storage, accessibility: accessibility)
        _storage = StateObject(wrappedValue: storage)
        _accessibility = StateObject(wrappedValue: accessibility)
        _coordinator = StateObject(wrappedValue: coordinator)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(
                coordinator: coordinator,
                storage: storage,
                accessibility: accessibility
            )
        } label: {
            StatusBarLabel(isWorking: coordinator.isWorking)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Status-bar label. Uses the stock `command` SF Symbol — the same glyph that
/// sits next to "Translate:" in the popover's hotkey row. Stays crisp at
/// menu-bar sizes (16-18 px) and auto-tints with the system theme. A small
/// accent ring overlays in the corner while work is in progress.
private struct StatusBarLabel: View {
    let isWorking: Bool

    var body: some View {
        ZStack {
            Image(systemName: "command")
            if isWorking {
                Circle()
                    .stroke(Color.accentColor, lineWidth: 1.5)
                    .frame(width: 6, height: 6)
                    .offset(x: 6, y: -6)
            }
        }
    }
}
