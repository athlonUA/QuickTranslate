# Quick Translate

<img src="QuickTranslate/Resources/Assets.xcassets/AppIcon.appiconset/icon_128x128.png" alt="Quick Translate icon" width="128" align="right" />

A lightweight menu-bar-only macOS app that translates **selected text or
clipboard contents** with a single global hotkey via the
[DeepL API](https://www.deepl.com/docs-api). The translated result appears in
a floating panel above your current window — press **Esc** to dismiss and
keep working. The panel is resizable and remembers your last size between
translations.

- **One-tap translation.** Hotkey → DeepL → floating result. No window
  switching, no tab juggling.
- **Selected-text priority.** Reads what's highlighted in any app via
  Accessibility; falls back to the clipboard when nothing is selected.
- **Auto-detect source.** DeepL identifies the source language for you; pick
  only the target.
- **Secure key storage.** The DeepL API key lives in your login Keychain, not
  in `UserDefaults`.
- **No dependencies.** Only stock Apple frameworks.

## Requirements

- macOS 14 Sonoma or newer (for SwiftUI `MenuBarExtra(.window)` and
  `onKeyPress`).
- Xcode 15 or newer to build.
- A [DeepL API account](https://www.deepl.com/pro-api). The free tier
  (`:fx`-suffixed key) is sufficient.
- [xcodegen](https://github.com/yonaskolb/XcodeGen) — `project.yml` is the
  source of truth; the `.xcodeproj` is committed for convenience.

## Build & run

```bash
# Option A — open the committed project
open QuickTranslate.xcodeproj

# Option B — regenerate the project first
xcodegen generate
open QuickTranslate.xcodeproj

# Option C — pure CLI build
xcodebuild -project QuickTranslate.xcodeproj \
           -scheme QuickTranslate \
           -configuration Debug \
           -destination 'platform=macOS' build
```

The built `.app` lands in
`~/Library/Developer/Xcode/DerivedData/QuickTranslate-*/Build/Products/Debug/QuickTranslate.app`.
Run it with `open` and look for the **⌘** icon in your menu bar.

## Usage

1. Click the menu-bar **⌘** icon.
2. Expand **Translation Settings** and paste your DeepL API key. Pick the
   target language (default `EN-US`).
3. Anywhere on your Mac, either select some text **or** copy it to the
   clipboard, then press the global hotkey (default `⌃⌥⌘T`).
4. A floating panel pops up with the translation (default 720×360, drag the
   corner to resize). **Esc** or the close button dismisses it.

The popover also offers:

- **Copy Last** — copies the most recent translation to the clipboard.
- **Translation Settings** — DeepL API key (Keychain-backed) and target
  language picker.
- **Change hotkey** — inline shortcut recorder; press a new combination, **Esc** cancels.
- **Quit**.

### Permissions

- **Accessibility (optional).** Lets Quick Translate read the **currently
  selected text** in any app. Without it the app still works, but only via
  the clipboard. The popover surfaces an inline banner with a *Grant Access*
  button the first time the popover opens; click it once to bring up the
  standard system prompt.
- **No Screen Recording / Microphone / Apple Events permissions** are
  requested or needed.

Global hotkeys use Carbon `RegisterEventHotKey` (not a `CGEventTap`), so
they keep working even when Accessibility is denied.

## Supported target languages

`Language.allCases` (`QuickTranslate/Translate/Language.swift`) ships with
every DeepL target language at the time of writing:

| Code     | Display name           |
|----------|------------------------|
| `EN-US`  | English (US)           |
| `EN-GB`  | English (UK)           |
| `DE`     | German                 |
| `ES`     | Spanish                |
| `FR`     | French                 |
| `IT`     | Italian                |
| `NL`     | Dutch                  |
| `PL`     | Polish                 |
| `PT-BR`  | Portuguese (Brazil)    |
| `PT-PT`  | Portuguese (Portugal)  |
| `RU`     | Russian                |
| `UK`     | Ukrainian              |
| `JA`     | Japanese               |
| `KO`     | Korean                 |
| `ZH`     | Chinese (Simplified)   |
| `TR`     | Turkish                |
| `CS`     | Czech                  |
| `DA`     | Danish                 |
| `FI`     | Finnish                |
| `EL`     | Greek                  |
| `HU`     | Hungarian              |
| `NB`     | Norwegian              |
| `RO`     | Romanian               |
| `SK`     | Slovak                 |
| `SV`     | Swedish                |
| `BG`     | Bulgarian              |
| `ID`     | Indonesian             |
| `LT`     | Lithuanian             |
| `LV`     | Latvian                |

The source language is always auto-detected; DeepL surfaces its guess as a
small `EN → UK`-style badge in the floating panel.

## Architecture

```
QuickTranslateApp                 // @main, MenuBarExtra(.window)
└── AppCoordinator                // @MainActor orchestrator
    ├── HotkeyManager             // Carbon RegisterEventHotKey
    ├── (inline hotkey recorder)  // NSEvent local monitor in the coordinator
    ├── SelectedTextService       // AXUIElementCopyAttributeValue(...)
    ├── ClipboardService          // NSPasteboard wrapper
    ├── DeepLService              // POST api(-free).deepl.com/v2/translate
    ├── AppSettings               // UserDefaults + Keychain @Published store
    ├── AccessibilityPermissionService
    └── TranslationOverlayWindow  // floating NSPanel HUD
```

- **Hotkey-triggered translation flow** lives in
  `AppCoordinator.runTranslateFlow()`. Cascade is: selected text →
  clipboard. Result is sent to `TranslationOverlayWindow`.
- **Inline hotkey recorder** is integrated directly into the menu-bar popover,
  not a separate window (matches the sibling `Transcribr` UX).
- **API key** is persisted in the login Keychain via
  `KeychainAPIKeyStore` (production) / `InMemoryAPIKeyStore` (tests).
- **Translation overlay** is a floating `NSPanel` at `.floating` level with
  the standard window chrome — auto-adapts to system light/dark mode, opens
  at 720×360, and is freely resizable (the new size persists across
  subsequent translations in the same run).

## Development

### Tests

```bash
xcodebuild -project QuickTranslate.xcodeproj \
           -scheme QuickTranslate \
           -configuration Debug \
           -destination 'platform=macOS' test
```

68 unit tests cover `Hotkey` / `AppSettings` / `Clipboard` / `KeyCodeNames` /
`Language` / `DeepLService` (request building, response parsing, end-to-end
via `URLProtocol` stub) / `KeychainAPIKeyStore` (round-trip against an
isolated test keychain service).

### Project regeneration

```bash
xcodegen generate
```

`project.yml` is the source of truth; the generated `.xcodeproj` is committed
so contributors without `xcodegen` can still build, but it should be
considered read-only — edit `project.yml`, then regenerate.

### Keychain prompts during development

Because debug builds are **ad-hoc-signed**, macOS prompts for keychain access
on every rebuild (the binary's signature changes each time). Click **Always
Allow** to whitelist for the current build. Production / Developer-ID
distribution would not see these prompts.

## Related apps

Quick Translate is part of a sibling family of menu-bar tools that share
visual style and project conventions:

- [ScreenshotOCR](../ScreenshotOCR) — drag a region, get the text on your
  clipboard.
- [Transcribr](../Transcribr) — record system + microphone audio and
  transcribe via OpenAI.

## License

[MIT](LICENSE) © 2026 Alex Garmatenko
