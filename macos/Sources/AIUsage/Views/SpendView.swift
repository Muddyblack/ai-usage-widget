import SwiftUI

struct SpendView: View {
    @ObservedObject var model: AppModel
    /// Matches SessionsView's expansion idiom rather than introducing
    /// DisclosureGroup, which this app does not use anywhere.
    @State private var expandedIDs: Set<String> = []

    private var rows: [SpendRow] { model.spendRows }
    private var meteredTotal: Double { SpendRows.meteredTotalUSD(rows) }
    private var planTotal: Double { SpendRows.planTotalUSD(rows) }
    private var allTotal: Double { SpendRows.allTotalUSD(rows) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(FeatureView.spend.title).font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 8)
                if meteredTotal > 0 && planTotal > 0 {
                    Text(i18n("Metered: %1 · Incl. plan: %2", Compact.money(meteredTotal, currency: "USD"), Compact.money(allTotal, currency: "USD")))
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.accent("#34d399"))
                } else if planTotal > 0 {
                    Text(i18n("Incl. plan: %1", Compact.money(planTotal, currency: "USD")))
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.accent("#34d399"))
                } else if meteredTotal > 0 {
                    Text(i18n("Metered: %1", Compact.money(meteredTotal, currency: "USD")))
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.accent("#34d399"))
                }
            }
            Text(i18n("Provider totals come from each provider's own usage APIs. Local source rows show actual, estimated, or mixed provenance and coverage separately."))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            if rows.isEmpty {
                FeatureViews.message(detail: i18n("No cost figures yet. Enable providers that report spend, or use them until local logs appear."))
            }
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 6) {
                    spendRow(row)
                    if row.canExpand, expandedIDs.contains(row.id) {
                        SpendChartView(dailyCost: row.dailyCost, dailyTokens: row.dailyTokens, accent: row.accent)
                            .padding(.leading, 16)
                    }
                }
            }
        }
    }

    /// The row label and the expand chevron are two independent buttons rather
    /// than a tap gesture nested inside the label's button: a gesture inside a
    /// Button's label is not reliably delivered on its own.
    private func spendRow(_ row: SpendRow) -> some View {
        HStack(spacing: 8) {
            if let provider = row.provider {
                Button { model.showFeature(nil); model.selectedID = provider.id } label: {
                    rowLabel(row)
                }
                .buttonStyle(.plain)
            } else {
                rowLabel(row)
            }
            Spacer(minLength: 8)
            if row.canExpand {
                Button { toggle(row.id) } label: {
                    Image(systemName: expandedIDs.contains(row.id) ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(expandedIDs.contains(row.id) ? i18n("Hide history") : i18n("Show history"))
            }
            Text(Compact.money(row.cost, currency: row.currency))
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
        }
        .contentShape(Rectangle())
    }

    private func rowLabel(_ row: SpendRow) -> some View {
        HStack(spacing: 8) {
            Circle().fill(Theme.accent(row.accent)).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.label).font(.system(size: 12, weight: .semibold))
                Text(row.note)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .contentShape(Rectangle())
    }

    private func toggle(_ id: String) {
        if expandedIDs.contains(id) { expandedIDs.remove(id) } else { expandedIDs.insert(id) }
    }
}
