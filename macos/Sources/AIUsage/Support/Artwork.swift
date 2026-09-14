import AppKit

/// The provider logos, which are the widget's own SVGs.
///
/// They reach the app through a compiled asset catalog (scripts/build-app.sh
/// hands `package/contents/icons/*.svg` to `actool`, which keeps the vector
/// representation), so one file draws crisply at menu bar size and at popover
/// size on any display. A `swift run` build has no catalog and falls back to a
/// symbol, which keeps the app runnable straight out of the checkout.
enum Artwork {
    // NSCache rather than a dictionary: the menu bar image is rebuilt on
    // every poll, and a static var would be shared mutable state the compiler
    // is right to complain about.
    private static let cache = NSCache<NSString, NSImage>()

    /// A provider's logo, by the bare filename the contract carries
    /// ("claude-color.svg"). nil when the provider ships no artwork.
    static func providerImage(_ filename: String) -> NSImage? {
        guard !filename.isEmpty else { return nil }
        let name = (filename as NSString).deletingPathExtension as NSString
        if let cached = cache.object(forKey: name) { return cached }
        guard let image = NSImage(named: name as String) else { return nil }
        cache.setObject(image, forKey: name)
        return image
    }

    /// The logo as the menu bar wants it: one flat silhouette, sized to the
    /// menu bar's text, drawn in whatever colour the menu bar is using.
    ///
    /// A template image is the whole trick — macOS reads only its alpha and
    /// paints it itself, so it turns white on a dark menu bar, dark on a light
    /// one, and inverts with the rest of the item while the popover is open.
    /// A brand-coloured logo would do none of that, and Apple's own menu bar
    /// items are monochrome for exactly this reason.
    static func menuBarImage(_ filename: String, height: CGFloat = 16) -> NSImage {
        let scaled = resized(filename, height: height) { _ in }
        scaled.isTemplate = true
        return scaled
    }

    /// The logo in its own brand colours, at menu bar size.
    ///
    /// Apple's guidance is that a menu bar item is a template image, and for
    /// good reason: a coloured one does not invert with the menu bar, does not
    /// dim when the app is inactive, and fights whatever wallpaper shows
    /// through. It is offered because the Plasma widget and the Hyprland pill
    /// both show brand artwork and somebody moving between them may want the
    /// same thing here — not because it is the better default. It is not the
    /// default.
    static func brandMenuBarImage(_ filename: String, height: CGFloat = 16) -> NSImage {
        resized(filename, height: height) { _ in }
    }

    /// The logo's shape filled with one colour — the panel pill's look, where
    /// "the logo contributes its shape and the backend its colour"
    /// (hyprland/PanelSlot.qml), so severity is read off the icon itself.
    ///
    /// A flat fill, unlike the Windows tray's tinted icons, which preserve a
    /// pictured logo's own lightness range. At 16 points in a menu bar that
    /// distinction is not visible, and a flat silhouette stays legible where a
    /// half-tinted picture would turn to mud.
    static func tintedMenuBarImage(_ filename: String, colour: NSColor, height: CGFloat = 16) -> NSImage {
        resized(filename, height: height) { rect in
            colour.set()
            rect.fill(using: .sourceAtop)
        }
    }

    /// The logo drawn to `height`, keeping its aspect, with `overlay` composited
    /// on top of it inside the same drawing handler.
    private static func resized(
        _ filename: String, height: CGFloat, overlay: @escaping (NSRect) -> Void
    ) -> NSImage {
        let source = providerImage(filename) ?? fallbackSymbol
        let size = source.size
        let scale = size.height > 0 ? height / size.height : 1
        return NSImage(
            size: NSSize(width: max(1, size.width * scale), height: height), flipped: false
        ) { rect in
            source.draw(in: rect)
            overlay(rect)
            return true
        }
    }

    /// Used when a provider has no artwork and when the catalog is absent.
    static let fallbackSymbol: NSImage = {
        let image = NSImage(systemSymbolName: "gauge.medium", accessibilityDescription: "AI Usage")
            ?? NSImage(size: NSSize(width: 16, height: 16))
        image.isTemplate = true
        return image
    }()
}
