import SwiftUI

/// Content of the floating translation panel.
///
/// Standard window chrome rather than HUD vibrancy — the panel adapts to the
/// system appearance the same way the menubar popover does. Layout is
/// minimal: translation text (large, system-primary so it adapts) and a
/// tight `EN → UK` badge. No Copy button — text is selectable and the
/// menubar's Copy Last covers full-translation copies. Esc + the title-bar
/// X close the panel.
struct TranslationOverlayView: View {
    @ObservedObject var model: TranslationOverlayModel
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch model.content {
            case .translation(let text, let target, let detected):
                translationText(text)
                footerRow(target: target, detected: detected)
            case .error(let message):
                errorBody(message)
            case .empty:
                EmptyView()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        // Flexible frame so the SwiftUI content stretches with the window
        // when the user drags the panel corner. `idealWidth` / `idealHeight`
        // is what the panel opens to; the min keeps the layout sane if the
        // user drags it tiny.
        .frame(
            minWidth: 380, idealWidth: 720, maxWidth: .infinity,
            minHeight: 220, idealHeight: 360, maxHeight: .infinity,
            alignment: .topLeading
        )
        .onKeyPress(.escape) {
            onClose()
            return .handled
        }
    }

    // MARK: - Subviews

    /// Dominant element. `.title2` at the system default weight — adding
    /// `.medium` made it read noticeably heavier than native macOS title-bar
    /// text, which the user flagged as "off". Default weight tracks SF Pro
    /// exactly as the OS does. `.foregroundStyle(.primary)` resolves to
    /// black/white per system appearance, same as the menubar popover.
    private func translationText(_ text: String) -> some View {
        ScrollView {
            Text(text)
                .font(.title2)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        // ScrollView fills whatever vertical space the panel gives it. For
        // medium translations the text fits without scrolling; for very long
        // ones the user drags the panel taller and gets more visible at
        // once. `.infinity` removes the artificial cap that used to force
        // scrolling on 4+ line translations.
        .frame(minHeight: 80, maxHeight: .infinity)
    }

    private func footerRow(target: Language, detected: String?) -> some View {
        HStack {
            Text(directionLabel(target: target, detected: detected))
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func directionLabel(target: Language, detected: String?) -> String {
        if let detected, !detected.isEmpty {
            return "\(detected.uppercased())  →  \(target.deepLCode)"
        }
        return "→  \(target.deepLCode)"
    }

    private func errorBody(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(.orange)
            Text(message)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Model owned by `TranslationOverlayWindow`. Holds the currently-displayed
/// content so the SwiftUI view (which is reattached on each present) can be
/// driven by a single source of truth.
@MainActor
final class TranslationOverlayModel: ObservableObject {
    enum Content: Equatable {
        case empty
        case translation(text: String, target: Language, detected: String?)
        case error(String)
    }

    @Published var content: Content = .empty
}
