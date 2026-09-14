import Foundation

/// Countdowns and timestamps, formatted the way every other frontend of this
/// widget formats them.
///
/// The arithmetic is a port of `package/contents/code/Format.js`, which the two
/// QML frontends share — the same quota should not read "2h 14m" in one place
/// and "2.2 hours" in another.
enum Countdown {
    /// "2d 4h 13m" until `target`, "" when there is no target, and the
    /// resetting state once the deadline has passed.
    static func text(targetMs: Double, nowMs: Double = Date().timeIntervalSince1970 * 1000) -> String {
        guard targetMs > 0 else { return "" }
        let remaining = targetMs - nowMs
        guard remaining > 0 else { return i18n("resetting…") }

        let totalMinutes = Int(remaining / 60_000)
        let days = totalMinutes / 1440
        let hours = (totalMinutes % 1440) / 60
        let minutes = totalMinutes % 60

        var parts: [String] = []
        if days > 0 { parts.append("\(days)d") }
        if hours > 0 || days > 0 { parts.append("\(hours)h") }
        parts.append("\(minutes)m")
        return parts.joined(separator: " ")
    }

    /// Same, for the epoch-*seconds* timestamps the provider contract uses.
    static func fromEpoch(_ resetAt: Double, nowMs: Double = Date().timeIntervalSince1970 * 1000) -> String {
        text(targetMs: resetAt > 0 ? resetAt * 1000 : 0, nowMs: nowMs)
    }
}

enum Stamp {
    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    /// "just now" / "3 minutes ago", in the user's language. The menu bar's
    /// footer line, where the exact second never matters.
    static func ago(_ epochSeconds: Double, now: Date = Date()) -> String {
        guard epochSeconds > 0 else { return "" }
        let date = Date(timeIntervalSince1970: epochSeconds)
        if now.timeIntervalSince(date) < 60 { return i18n("just now") }
        return relative.localizedString(for: date, relativeTo: now)
    }

    /// The reset instant as a date and time in the user's own locale, for the
    /// tooltip behind a countdown.
    static func absolute(_ epochSeconds: Double) -> String {
        guard epochSeconds > 0 else { return "" }
        return Date(timeIntervalSince1970: epochSeconds)
            .formatted(date: .abbreviated, time: .shortened)
    }
}


/// Big numbers, shortened the way every other frontend shortens them
/// (hyprland/StatsSection.qml: formatTokens).
enum Compact {
    static func number(_ value: Double) -> String {
        guard value > 0 else { return "0" }
        if value >= 1_000_000 { return String(format: "%.2fM", value / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fK", value / 1_000) }
        return String(Int(value.rounded()))
    }

    static func money(_ value: Double, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency.isEmpty ? "USD" : currency
        formatter.maximumFractionDigits = value < 10 ? 2 : 0
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }

    /// "2d 4h" / "45m" / "<1m" — the abbreviations are separate msgids because
    /// not every language shortens the same way.
    static func duration(milliseconds: Double) -> String {
        guard milliseconds > 0 else { return "—" }
        let totalMinutes = Int(milliseconds / 60_000)
        let days = totalMinutes / 1440
        let hours = (totalMinutes % 1440) / 60
        let minutes = totalMinutes % 60

        var parts: [String] = []
        if days > 0 { parts.append(i18nc("duration in days, abbreviated", "%1d", days)) }
        if hours > 0 { parts.append(i18nc("duration in hours, abbreviated", "%1h", hours)) }
        if days == 0, minutes > 0 { parts.append(i18nc("duration in minutes, abbreviated", "%1m", minutes)) }
        return parts.isEmpty ? i18n("<1m") : parts.joined(separator: " ")
    }

    /// "14:00" for the hour of day a provider was busiest, in the user's clock.
    static func hour(_ hour: Double) -> String {
        guard hour >= 0, hour <= 23 else { return "" }
        var components = DateComponents()
        components.hour = Int(hour)
        components.minute = 0
        guard let date = Calendar.current.date(from: components) else { return "" }
        return date.formatted(date: .omitted, time: .shortened)
    }
}
