import AppKit

/// What the menu bar item says.
///
/// macOS is the one platform where this widget's panel pill can be itself: a
/// status item draws text, so "93% 82%" goes up there in the system font
/// beside the provider's mark, instead of being faked with separate 16-pixel
/// icons the way Windows needs.
enum MenuBarTitle {
    /// Amber from 70 %, red from 90 % — the panel pill's rule
    /// (hyprland/PanelSlot.qml), so a glance means the same thing on every
    /// platform. Below that the number stays in the menu bar's own colour,
    /// which is what keeps a healthy reading quiet.
    static func colour(forPercent value: Double, slotColour: NSColor?, coloured: Bool) -> NSColor {
        if value >= 90 { return .systemRed }
        if value >= 70 { return .systemOrange }
        return coloured ? (slotColour ?? .labelColor) : .labelColor
    }

    /// The values a provider contributes to the menu bar, at most `limit` of
    /// them, already formatted. Empty when the provider has nothing to say.
    struct Reading {
        let text: String
        let pct: Double
        /// The colour the panel pill gives this value, when the user asked for
        /// coloured percentages.
        let slotColour: NSColor?
    }

    static func readings(for provider: Provider, limit: Int) -> [Reading] {
        provider.slots.prefix(limit).map { slot in
            // A slot whose text is null wants a meter rather than a number;
            // there is no meter in a menu bar, so its percentage is printed.
            Reading(
                text: slot.text ?? "\(Int(slot.pct.rounded()))%",
                pct: slot.pct,
                slotColour: slot.color.isEmpty ? nil : NSColor(hex: slot.color))
        }
    }

    static func attributedTitle(
        for provider: Provider?, style: MenuBarStyle, slots: Int, coloured: Bool,
        icon: MenuBarIcon = .monochrome
    ) -> NSAttributedString {
        guard style != .iconOnly, let provider else { return NSAttributedString(string: "") }

        let readings = readings(for: provider, limit: slots)
        guard !readings.isEmpty else { return NSAttributedString(string: "") }

        // Monospaced digits: without them every poll re-measures the item and
        // the whole right-hand side of the menu bar twitches sideways.
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize(for: .small), weight: .regular)
        // A logo beside every value, rather than one at the far left, is what
        // makes two readings read as two things — the panel pill's layout.
        let perValueIcons = icon.isPerValue && style != .percentOnly && !provider.icon.isEmpty

        // Two spaces between icon-and-value groups, one between bare numbers:
        // with a logo in front of each value the gap has to read as wider than
        // the gap inside a group, or "93% 61%" becomes one four-part smear.
        let separator = perValueIcons ? "  " : " "

        let title = NSMutableAttributedString()
        for (index, reading) in readings.enumerated() {
            if index > 0 { title.append(NSAttributedString(string: separator, attributes: [.font: font])) }
            if perValueIcons {
                title.append(attachment(provider.icon, reading: reading, icon: icon, font: font))
                title.append(NSAttributedString(string: " ", attributes: [.font: font]))
            }
            title.append(
                NSAttributedString(
                    string: reading.text,
                    attributes: [
                        .font: font,
                        .foregroundColor: colour(
                            forPercent: reading.pct, slotColour: reading.slotColour, coloured: coloured),
                    ]))
        }
        return title
    }

    /// One logo, inline with the text.
    ///
    /// An attachment rather than the button's own image, because the button
    /// has one image and this layout wants one per value. Its bounds are
    /// dropped below the baseline by a couple of points so the logo sits
    /// centred on the digits rather than on their feet.
    private static func attachment(
        _ filename: String, reading: Reading, icon: MenuBarIcon, font: NSFont
    ) -> NSAttributedString {
        let height = round(font.pointSize * 1.15)
        let image: NSImage
        switch icon {
        case .tinted:
            image = Artwork.tintedMenuBarImage(
                filename,
                colour: colour(forPercent: reading.pct, slotColour: reading.slotColour, coloured: true),
                height: height)
        case .brand:
            image = Artwork.brandMenuBarImage(filename, height: height)
        case .monochrome:
            image = Artwork.menuBarImage(filename, height: height)
        }

        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = NSRect(
            x: 0, y: font.descender / 2, width: image.size.width, height: image.size.height)
        return NSAttributedString(attachment: attachment)
    }

    /// What VoiceOver reads, and what the tooltip says. The menu bar's own text
    /// is terse by necessity; this is the sentence behind it.
    static func accessibilityLabel(for provider: Provider?) -> String {
        guard let provider else { return "AI Usage" }
        if !provider.error.isEmpty { return "\(provider.label): \(provider.error)" }
        let rows = provider.quotaWindows
            .filter(\.available)
            .map { "\($0.label) \(Int($0.pct.rounded()))% used" }
        if rows.isEmpty { return "\(provider.label): \(provider.summary.text)" }
        return "\(provider.label): " + rows.joined(separator: ", ")
    }
}

extension NSColor {
    /// A "#rrggbb" from the provider contract. nil-safe by falling back to the
    /// label colour: the accent is decoration, never information on its own.
    convenience init(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else {
            self.init(white: 0.5, alpha: 1)
            return
        }
        self.init(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1)
    }
}
