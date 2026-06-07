import SwiftUI

/// Popover content shown by `MenuBarExtra` with `.menuBarExtraStyle(.window)`.
///
/// The popover no longer displays the translation itself — that lives in the
/// floating overlay panel opened by `AppCoordinator` after a successful hotkey
/// run. The popover is now a thin control surface: Copy Last (single
/// full-width action), inline translation settings, inline hotkey row that
/// captures keystrokes when armed, and Quit.
struct MenuBarContent: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var storage: AppSettings
    @ObservedObject var accessibility: AccessibilityPermissionService

    @State private var settingsExpanded: Bool = false
    @FocusState private var apiKeyFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            accessibilityBanner

            if let error = coordinator.lastError {
                errorBanner(error)
            }

            copyButton

            Divider()

            settingsDisclosure

            Divider()

            hotkeyRow

            Divider()

            quitRow
        }
        .padding(12)
        .frame(width: 320)
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture().onEnded {
                apiKeyFocused = false
            }
        )
        .onAppear {
            accessibility.refresh()
        }
        // Popover closing mid-capture would leave the local NSEvent monitor
        // dangling and the row stuck on "Press shortcut…". Cancel cleanly.
        .onDisappear {
            if coordinator.isCapturingHotkey {
                coordinator.cancelHotkeyCapture()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "command")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.primary)
            Text("Quick Translate")
                .font(.headline)
            Spacer()
            if coordinator.isWorking {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    // MARK: - Copy button (single full-width action)

    /// `.bordered` (not `.borderedProminent`) so the button reads as a soft
    /// translucent blue chip, matching the ScreenshotOCR "Copy Last" / "Choose
    /// File" pair in the reference screenshot.
    private var copyButton: some View {
        Button {
            coordinator.copyLastTranslation()
        } label: {
            Label("Copy Last", systemImage: "doc.on.clipboard")
                .frame(maxWidth: .infinity)
        }
        .controlSize(.regular)
        .buttonStyle(.bordered)
        .tint(.blue)
        .disabled((storage.lastTranslation ?? "").isEmpty)
    }

    // MARK: - Inline settings disclosure

    private var settingsDisclosure: some View {
        DisclosureGroup(isExpanded: $settingsExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("DeepL API Key")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        SecureField("xxxxxxxx-…-xxxxxxxx:fx", text: $storage.apiKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption.monospaced())
                            .focused($apiKeyFocused)
                        Button("Clear") {
                            storage.apiKey = ""
                            apiKeyFocused = false
                        }
                        .controlSize(.small)
                        .disabled(storage.apiKey.isEmpty)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Target Language")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $storage.targetLanguage) {
                        ForEach(Language.allCases) { language in
                            Text("\(language.displayName) — \(language.deepLCode)").tag(language)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .font(.caption)
                }
            }
            .padding(.top, 6)
        } label: {
            Label("Translation Settings", systemImage: "key")
                .font(.caption.bold())
        }
    }

    // MARK: - Hotkey row with inline capture

    /// While armed, the row reads "Press shortcut… [Cancel]"; otherwise it
    /// shows the current binding plus a "Change hotkey" button. Matches the
    /// Transcribr `MicMuteService` UI pattern so the three sibling apps share
    /// muscle memory.
    @ViewBuilder
    private var hotkeyRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "command")
                .foregroundStyle(.primary)
                .frame(width: 14)
            Text("Translate:")
                .font(.caption)
            if coordinator.isCapturingHotkey {
                Text("Press shortcut…")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") {
                    coordinator.cancelHotkeyCapture()
                }
                .controlSize(.small)
            } else {
                Text(storage.hotkey.description)
                    .font(.caption.monospaced())
                Spacer()
                Button("Change hotkey") {
                    coordinator.startHotkeyCapture()
                }
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
    }

    // MARK: - Accessibility banner

    /// Accessibility is optional — without it the clipboard fallback still
    /// works, but the user loses the "selected text" priority path. The
    /// `notDetermined` branch is the entry into the documented permission
    /// flow: clicking "Grant Access" triggers the system prompt and flips
    /// the cached status to `.denied` if the user dismisses it, after which
    /// the second branch's deep-link to Settings takes over.
    @ViewBuilder
    private var accessibilityBanner: some View {
        switch accessibility.status {
        case .granted:
            EmptyView()
        case .notDetermined:
            permissionBanner(
                title: "Enable selected-text translation",
                detail: "Grant Accessibility access to translate text selected in any app. Without it Quick Translate falls back to the clipboard.",
                actions: [
                    .init(label: "Grant Access") { accessibility.request() },
                ]
            )
        case .denied:
            permissionBanner(
                title: "Accessibility access disabled",
                detail: "Quick Translate currently falls back to the clipboard. Enable it in System Settings → Privacy & Security → Accessibility for selected-text priority.",
                actions: [
                    .init(label: "Open System Settings") { accessibility.openSettings() },
                ]
            )
        }
    }

    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.red)
            .lineLimit(5)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Quit

    private var quitRow: some View {
        HStack {
            Button("Quit") { coordinator.quit() }
                .keyboardShortcut("q")
            Spacer()
        }
    }

    // MARK: - Banner helper

    private struct BannerAction: Identifiable {
        var id: String { label }
        let label: String
        let action: () -> Void
    }

    private func permissionBanner(title: String, detail: String, actions: [BannerAction]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.red)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                ForEach(actions) { entry in
                    Button(entry.label, action: entry.action)
                        .controlSize(.small)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.08))
        .cornerRadius(6)
    }
}
