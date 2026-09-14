import SwiftUI

/// One quota window: what it is, how much of it is gone, and when it comes back.
///
/// The contract's `pct` is the share **used**, which is also what the colour
/// rule and every other frontend read — so the number is labelled "used"
/// outright rather than left to be guessed at.
struct QuotaRowView: View {
    let window: QuotaWindow
    let accent: Color
    /// Driven by the popover's clock so every countdown on screen ticks
    /// together, rather than each row reading the system clock on its own.
    let nowMs: Double

    private var countdown: String {
        Countdown.fromEpoch(window.resetAt, nowMs: nowMs)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.label)
                    .font(.system(size: 12, weight: .medium))
                Spacer(minLength: 8)
                if window.showMeter {
                    Text(i18n("%1% used", Int(window.pct.rounded())))
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.meterColor(pct: window.pct, accent: accent))
                } else {
                    // showMeter false means `detail` *is* the value — a
                    // balance, a credit count — and there is no percentage
                    // worth drawing a bar for.
                    Text(window.detail)
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                }
            }

            if window.showMeter {
                Meter(pct: window.pct, color: Theme.meterColor(pct: window.pct, accent: accent))
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if !countdown.isEmpty {
                    Text(i18n("Resets in %1", countdown))
                        .help(Stamp.absolute(window.resetAt))
                } else if !window.resetText.isEmpty {
                    Text(i18n("Resets %1", window.resetText))
                }
                if window.showMeter, !window.detail.isEmpty {
                    Text(window.detail)
                }
                if !window.note.isEmpty {
                    Text(window.note)
                }
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts = [window.label]
        if window.showMeter {
            parts.append("\(Int(window.pct.rounded())) percent used")
        } else if !window.detail.isEmpty {
            parts.append(window.detail)
        }
        if !countdown.isEmpty { parts.append("resets in \(countdown)") }
        return parts.joined(separator: ", ")
    }
}

/// A flat capsule rather than a gradient: it has to read at a glance on a
/// translucent popover material, in both appearances, at 6 points tall.
struct Meter: View {
    let pct: Double
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)
                Capsule()
                    .fill(color)
                    .frame(width: geometry.size.width * min(max(pct, 0), 100) / 100)
            }
        }
        .frame(height: Theme.meterHeight)
        .accessibilityHidden(true)
    }
}
