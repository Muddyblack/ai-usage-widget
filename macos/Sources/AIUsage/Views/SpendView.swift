import SwiftUI

/// The optional Usage & Spend view: the spend figures each provider already
/// reported, with the range each covers. Ranges differ by source (30-day,
/// all-time, lifetime) — the same caveat the Linux Spend tabs print.
/// Tapping a row opens that provider.
struct SpendView: View {
    @ObservedObject var model: AppModel

    private var rows: [SpendRow] { model.spendRows }
    private var total: Double { SpendRows.totalUSD(rows) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(FeatureView.spend.title).font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 8)
                if total > 0 {
                    Text("Σ " + Compact.money(total, currency: "USD"))
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.green)
                }
            }
            Text(i18n("Totals come from each provider's own usage APIs and local CLI logs. Ranges differ (30-day, all-time, lifetime)."))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            if rows.isEmpty {
                FeatureViews.message(detail: i18n("No cost figures yet. Enable providers that report spend, or use them until local logs appear."))
            }
            ForEach(rows) { row in
                Button { model.showFeature(nil); model.selectedID = row.provider.id } label: {
                    HStack(spacing: 8) {
                        Circle().fill(Theme.accent(row.provider.accent)).frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.provider.label).font(.system(size: 12, weight: .semibold))
                            Text(row.note).font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Text(Compact.money(row.cost, currency: row.currency))
                            .font(.system(size: 12, weight: .semibold))
                            .monospacedDigit()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
