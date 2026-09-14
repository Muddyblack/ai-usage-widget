import AppKit
import SwiftUI

/// The popover's measurements and its one colour rule.
///
/// Everything else is a system colour — `.primary`, `.secondary`,
/// `Color.accentColor` — so the popover follows light and dark mode, Increase
/// Contrast and the user's accent colour without a theme of its own, and sits
/// on the material `NSPopover` paints behind it. That is the whole difference
/// between this and the Linux popup's hard-coded slate palette.
enum Theme {
    /// Wide enough for "7-day window" beside a percentage in a long
    /// translation, narrow enough not to look like a window.
    static let popoverWidth: CGFloat = 340
    static let rowSpacing: CGFloat = 14
    static let meterHeight: CGFloat = 6

    /// The panel pill's severity rule, shared with every other frontend:
    /// amber from 70 % used, red from 90 %. Below that a quota is unremarkable
    /// and is drawn in the provider's own accent, not in a warning colour.
    static func meterColor(pct: Double, accent: Color) -> Color {
        if pct >= 90 { return .red }
        if pct >= 70 { return .orange }
        return accent
    }

    static func accent(_ hex: String) -> Color {
        hex.isEmpty ? .accentColor : Color(nsColor: NSColor(hex: hex))
    }
}

extension View {
    /// A row inset matching the system's own popover padding.
    func popoverRowInsets() -> some View {
        padding(.horizontal, 16)
    }
}
