import SwiftUI

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
                    Text(i18n("Provider/API total") + " " + Compact.money(total, currency: "USD"))
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
                if let provider = row.provider {
                    Button { model.showFeature(nil); model.selectedID = provider.id } label: {
                        spendRow(row)
                    }
                    .buttonStyle(.plain)
                } else {
                    spendRow(row)
                }
            }
        }
    }

    private func spendRow(_ row: SpendRow) -> some View {
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
            Spacer(minLength: 8)
            Text(Compact.money(row.cost, currency: row.currency))
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
        }
        .contentShape(Rectangle())
    }
}
