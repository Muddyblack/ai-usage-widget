import Charts
import SwiftUI

/// One provider's spend over time, shown inside an expanded Spend row.
///
/// Deliberately per-provider rather than one merged chart: providers report on
/// wildly different ranges (a 30-day API window vs. all-time local logs), so a
/// combined line was mostly flat with a single misleading spike.
///
/// Cost is linear, tokens are logarithmic — token counts swing by orders of
/// magnitude across days while cost rarely does. Both series come from the
/// same session rows, so they always cover the same days.
struct SpendChartView: View {
    let dailyCost: [DailyCostPoint]
    let dailyTokens: [DailyPoint]
    let accent: String

    @State private var showCost = true
    @State private var showTokens = true

    private var hasCost: Bool { dailyCost.contains { $0.usd > 0 } }
    private var hasTokens: Bool { dailyTokens.contains { $0.total > 0 } }
    private var drawCost: Bool { hasCost && showCost }
    private var drawTokens: Bool { hasTokens && showTokens }

    /// Tokens are clipped to the cost window. The two series can come from
    /// stores with different retention, and plotting the union drew a token
    /// line that stopped exactly where the cost line started.
    private var tokenPoints: [DailyPoint] {
        guard let first = dailyCost.first?.date, let last = dailyCost.last?.date else { return dailyTokens }
        return dailyTokens.filter { $0.date >= first && $0.date <= last }
    }

    var body: some View {
        if !hasCost && !hasTokens {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 6) {
                legend
                charts
            }
            .padding(.top, 2)
        }
    }

    @ViewBuilder private var legend: some View {
        HStack(spacing: 10) {
            if hasCost {
                legendButton(
                    label: i18n("Cost"),
                    color: Theme.accent(accent),
                    on: showCost,
                    // Never let both series be hidden at once.
                    disabled: showCost && !drawTokens) { showCost.toggle() }
            }
            if hasTokens {
                legendButton(
                    label: i18n("Tokens (log)"),
                    color: Theme.accent("#7dd3fc"),
                    on: showTokens,
                    disabled: showTokens && !drawCost) { showTokens.toggle() }
            }
            if !hasCost || !hasTokens {
                Text(hasCost ? i18n("· no token history") : i18n("· no cost history"))
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
    }

    private func legendButton(
        label: String,
        color: Color,
        on: Bool,
        disabled: Bool,
        toggle: @escaping () -> Void) -> some View {
        Button(action: { if !disabled { toggle() } }) {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 8, height: 8).opacity(on ? 1 : 0.3)
                Text(label).font(.system(size: 10)).opacity(on ? 0.75 : 0.3)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var charts: some View {
        VStack(alignment: .leading, spacing: 8) {
            if drawCost {
                Chart(dailyCost) { point in
                    LineMark(
                        x: .value(i18n("Day"), day(point.date)),
                        y: .value(i18n("Cost"), point.usd))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Theme.accent(accent))
                    AreaMark(
                        x: .value(i18n("Day"), day(point.date)),
                        y: .value(i18n("Cost"), point.usd))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(
                            .linearGradient(
                                colors: [Theme.accent(accent).opacity(0.25), .clear],
                                startPoint: .top,
                                endPoint: .bottom))
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let usd = value.as(Double.self) {
                                Text(Compact.money(usd, currency: "USD")).font(.system(size: 8))
                            }
                        }
                    }
                }
                .chartXAxis { dateAxis }
                .frame(height: 90)
            }

            if drawTokens {
                Chart(tokenPoints) { point in
                    LineMark(
                        x: .value(i18n("Day"), day(point.date)),
                        y: .value(i18n("Tokens"), max(point.total, 1)))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Theme.accent("#7dd3fc"))
                }
                // Built-in log scale rather than plotting log10 by hand, so
                // the axis labels stay in real token counts.
                .chartYScale(type: .log)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let tokens = value.as(Double.self) {
                                Text(Compact.number(tokens)).font(.system(size: 8))
                            }
                        }
                    }
                }
                .chartXAxis { dateAxis }
                .frame(height: 70)
            }
        }
    }

    private var dateAxis: some AxisContent {
        AxisMarks(values: .automatic(desiredCount: 4)) { value in
            AxisGridLine()
            AxisValueLabel {
                if let date = value.as(Date.self) {
                    Text(date, format: .dateTime.month(.abbreviated).day()).font(.system(size: 8))
                }
            }
        }
    }

    private func day(_ date: String) -> Date {
        SpendChartView.formatter.date(from: date) ?? Date(timeIntervalSince1970: 0)
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
