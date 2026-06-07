import AppKit
import CoreGraphics
import CoreText

/// Renders the bundle app icon — a centred `⌘` glyph on a violet→magenta
/// gradient. The menu-bar template icon is owned by SwiftUI now
/// (`Image(systemName: "command")`), so the template render path is unused;
/// the colour path is the only consumer.
///
/// Geometry is normalised against a 1.0 canvas and scaled by `size`.
enum AppIconRenderer {
    /// Full-colour rounded-square icon (for `AppIcon.appiconset`).
    static func renderColor(size: CGFloat) -> CGImage? {
        let pixels = Int(size)
        guard pixels > 0 else { return nil }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: pixels,
            height: pixels,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        let radius = size * 0.225
        let bg = CGPath(
            roundedRect: CGRect(origin: .zero, size: CGSize(width: size, height: size)),
            cornerWidth: radius, cornerHeight: radius, transform: nil
        )
        ctx.addPath(bg)
        ctx.clip()

        // Deep blue → bright blue, mirroring the Transcribr / ScreenshotOCR
        // family palette. The trio reads as a related app suite in the menu
        // bar; the ⌘ glyph is what tells them apart at a glance.
        let colors = [
            CGColor(red: 0.30, green: 0.36, blue: 0.85, alpha: 1.0),
            CGColor(red: 0.20, green: 0.55, blue: 0.95, alpha: 1.0),
        ] as CFArray
        if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 1]) {
            ctx.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: size),
                end: CGPoint(x: 0, y: 0),
                options: []
            )
        }

        drawCommandGlyph(in: ctx, size: size, foreground: CGColor.white)

        return ctx.makeImage()
    }

    static func nsImage(size: CGFloat) -> NSImage? {
        guard let cg = renderColor(size: size) else { return nil }
        return NSImage(cgImage: cg, size: CGSize(width: size, height: size))
    }

    // MARK: - Drawing

    /// Draws the `⌘` glyph (Unicode U+2318) centred on the canvas. We use
    /// CoreText rather than path-drawing because the glyph has subtle joinery
    /// (the four corner loops) that's hard to reproduce by hand and would
    /// drift from the system look across macOS versions.
    private static func drawCommandGlyph(in ctx: CGContext, size: CGFloat, foreground: CGColor) {
        let fontSize = size * 0.62
        let font = CTFontCreateUIFontForLanguage(.system, fontSize, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: foreground,
        ]
        let string = NSAttributedString(string: "⌘", attributes: attrs)
        let line = CTLineCreateWithAttributedString(string)

        // `CTLineGetImageBounds` is the visual ink rect — what's actually
        // painted. Using it (instead of typographic bounds) is what makes the
        // glyph land in the geometric centre regardless of the system font's
        // baseline metrics.
        let inkBounds = CTLineGetImageBounds(line, ctx)
        let textX = (size - inkBounds.width) / 2 - inkBounds.minX
        let textY = (size - inkBounds.height) / 2 - inkBounds.minY

        ctx.saveGState()
        ctx.textPosition = CGPoint(x: textX, y: textY)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }
}
