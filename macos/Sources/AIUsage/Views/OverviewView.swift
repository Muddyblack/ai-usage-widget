import SwiftUI

/// The optional Overview view: every enabled provider's headline meter.
/// Tapping a row opens that provider, like the Linux Overview tabs do.
struct OverviewView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FeatureViews.header(title: FeatureView.overview.title, count: model.providers.count)
            if model.providers.isEmpty {
                FeatureViews.message(detail: i18n("Enable a provider in Settings to see it here."))
            }
            ForEach(model.providers) { provider in
                Button { model.showFeature(nil); model.selectedID = provider.id } label: {
                    HStack(spacing: 10) {
                        if let image = Artwork.providerImage(provider.icon) {
                            Image(nsImage: image).resizable().frame(width: 16, height: 16)
                        } else {
                            Circle().fill(Theme.accent(provider.accent)).frame(width: 8, height: 8)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(provider.label).font(.system(size: 12, weight: .semibold))
                                Spacer(minLength: 8)
                                Text(i18n("%1%", Int(provider.summary.pct.rounded())))
                                    .font(.system(size: 12, weight: .semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.accent(provider.accent))
                            }
                            ProgressView(value: min(max(provider.summary.pct, 0), 100), total: 100)
                                .progressViewStyle(.linear)
                                .tint(Theme.accent(provider.accent))
                            if !provider.summary.detail.isEmpty {
                                Text(provider.summary.detail)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
