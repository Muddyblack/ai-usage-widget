import Charts
import SwiftUI

/// The provider's own history, over the ranges the backend says it has.
///
/// The ranges are not a table in this file: `chartWindows` carries them, so a
/// provider whose ranges change — or a provider added to the backend — changes
/// what this draws without a line of Swift.
struct HistoryChartView: View {
    let provider: Provider
    @ObservedObject var history: HistoryStore
    let accent: Color

    @State private var windowID = ""

    private var windows: [ChartWindow] { provider.chartWindows }

    private var selected: ChartWindow? {
        windows.first { $0.id == windowID } ?? windows.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if windows.count > 1 {
                Picker("", selection: Binding(
                    get: { selected?.id ?? "" },
                    set: { windowID = $0 }
                )) {
                    ForEach(windows) { window in
                        Text(window.label).tag(window.id)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
            }

            if let window = selected {
                chart(window)
            }
        }
        .onAppear { if windowID.isEmpty { windowID = windows.first?.id ?? "" } }
    }

    /// Plain Swift rather than a view builder, so the series is walked once
    /// and the two outcomes are obvious.
    private func chart(_ window: ChartWindow) -> AnyView {
        let points = history.series(for: window)
        guard points.count >= 2 else {
            return AnyView(
                Text(i18n("Not enough history yet — it builds up as the widget polls."))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(height: 72, alignment: .center)
                    .frame(maxWidth: .infinity))
        }
        return AnyView(plot(points, window: window))
    }

    /// A percentage series is pinned to 0–100 so its shape means the same
    /// thing between refreshes; an absolute one — a balance, a spend — is
    /// scaled to whatever it reached, with headroom so the line is not drawn
    /// along the top edge.
    private func domain(_ window: ChartWindow, points: [SeriesPoint]) -> ClosedRange<Double> {
        guard window.raw else { return 0...100 }
        return 0...max((points.map(\.v).max() ?? 0) * 1.1, 1)
    }

    private func plot(_ points: [SeriesPoint], window: ChartWindow) -> some View {
        Chart(points) { point in
            AreaMark(x: .value("Time", point.date), y: .value("Used", point.v))
                .foregroundStyle(accent.opacity(0.18))
            LineMark(x: .value("Time", point.date), y: .value("Used", point.v))
                .foregroundStyle(accent)
                .interpolationMethod(.monotone)
        }
        .chartYScale(domain: domain(window, points: points))
        .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) }
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) }
        .frame(height: 88)
        .accessibilityLabel(Text(i18n("Usage over the last %1", window.label)))
    }
}
