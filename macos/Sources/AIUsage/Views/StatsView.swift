import Charts
import SwiftUI

/// What the provider's own CLI logged locally — sessions, messages, tokens,
/// cost, streaks — behind a disclosure, like the usage history.
///
/// Five providers fill the same `details.stats` fields, so nothing here names
/// one: a figure a provider does not report is zero, and a zero is not drawn.
/// The two per-provider forks the contract does carry are the unit of the
/// per-day series (not every CLI counts tokens) and whether the sessions are
/// grouped by repository or by workspace, and both are answered by the data.
struct StatsView: View {
    let stats: ActivityStats
    let currency: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            tiles
            if !stats.daily.isEmpty { sparkline }
            if !stats.topGroups.isEmpty { topGroups }
            if !footnote.isEmpty {
                Text(footnote)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // ── Figures ──────────────────────────────────────────────────────────

    private struct Figure: Identifiable {
        let id = UUID()
        let value: String
        let label: String
    }

    /// Only what this provider actually reported, in a fixed order so the block
    /// does not rearrange itself between refreshes.
    private var figures: [Figure] {
        var out: [Figure] = []
        func add(_ value: Double, _ label: String, formatted: String? = nil) {
            guard value > 0 else { return }
            out.append(Figure(value: formatted ?? Compact.number(value), label: label))
        }
        add(stats.totalSessions, i18n("Sessions"))
        add(stats.totalMessages, i18n("Messages"))
        add(stats.totalTokens, i18n("Tokens"))
        add(stats.totalToolCalls, i18n("Tool calls"))
        add(stats.totalFiles, i18n("Files"))
        add(stats.totalWebSearches, i18n("Web searches"))
        add(
            stats.totalCostUSD, i18n("Cost"),
            formatted: Compact.money(stats.totalCostUSD, currency: currency))
        add(stats.activeDays, i18n("Active days"))
        add(stats.currentStreak, i18n("Streak"))
        add(
            stats.longestSessionMs, i18n("Longest session"),
            formatted: Compact.duration(milliseconds: stats.longestSessionMs))
        if stats.peakHour >= 0 {
            out.append(Figure(value: Compact.hour(stats.peakHour), label: i18n("Peak hour")))
        }
        if !stats.favoriteModel.isEmpty {
            out.append(Figure(value: shortModelName(stats.favoriteModel), label: i18n("Top model")))
        }
        return out
    }

    private var tiles: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading),
                      GridItem(.flexible(), alignment: .leading)],
            alignment: .leading, spacing: 8
        ) {
            ForEach(figures) { figure in
                VStack(alignment: .leading, spacing: 1) {
                    Text(figure.value)
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(figure.label)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(figure.label): \(figure.value)")
            }
        }
    }

    /// Model names are long and the tile is narrow; the same trimming the QML
    /// does, minus its provider-specific rewrites.
    private func shortModelName(_ name: String) -> String {
        var short = name
        for prefix in ["claude-", "models/", "openai/"] where short.hasPrefix(prefix) {
            short = String(short.dropFirst(prefix.count))
        }
        // Trailing release dates carry no information at this size.
        short = short.replacingOccurrences(
            of: "-(20)?\\d{2}-?\\d{2}-?\\d{2}$", with: "", options: .regularExpression)
        return short
    }

    // ── Per-day series ───────────────────────────────────────────────────

    private var seriesTitle: String {
        switch stats.dailyUnit {
        case "messages": return i18n("Messages / day")
        case "requests": return i18n("Requests / day")
        default: return i18n("Tokens / day")
        }
    }

    private var sparkline: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(seriesTitle)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Chart(stats.daily) { point in
                BarMark(
                    x: .value("Day", point.date),
                    y: .value(seriesTitle, point.total))
                    .foregroundStyle(accent.opacity(0.75))
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 34)
            .accessibilityLabel(seriesTitle)
        }
    }

    // ── Where the sessions went ──────────────────────────────────────────

    private var topGroups: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(stats.topGroupsAreRepositories ? i18n("Top repositories") : i18n("Top workspaces"))
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            ForEach(stats.topGroups.prefix(3)) { group in
                HStack {
                    Text(group.name)
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text(i18nc("abbreviated sessions", "%1 sess", Int(group.sessions)))
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var footnote: String {
        var parts: [String] = []
        if !stats.firstDate.isEmpty { parts.append(i18n("Since %1", stats.firstDate)) }
        if !stats.computedDate.isEmpty { parts.append(i18n("computed %1", stats.computedDate)) }
        return parts.joined(separator: " · ")
    }
}
