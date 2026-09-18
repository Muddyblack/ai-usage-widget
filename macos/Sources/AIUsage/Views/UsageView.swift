import AppKit
import SwiftUI

/// What the popover shows.
///
/// One provider at a time, picked from the title rather than from a row of
/// tabs: with fourteen providers the Linux popup wraps its tab bar onto three
/// lines, which is a lot of chrome above two numbers. The detail — charts,
/// per-provider statistics — stays one click away, so the thing the popover is
/// opened for is the thing it opens on.
struct UsageView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .popoverRowInsets()
                .padding(.top, 12)
                .padding(.bottom, 10)

            Divider()

            content
                .popoverRowInsets()
                .padding(.vertical, 12)

            Divider()

            footer
                .popoverRowInsets()
                .padding(.vertical, 8)
        }
        .frame(width: Theme.popoverWidth)
        .onAppear { if model.providers.isEmpty { model.refresh() } }
    }

    private var accent: Color { Theme.accent(model.selected?.accent ?? "") }

    // ── Header ───────────────────────────────────────────────────────────

    private var header: some View {
        HStack(spacing: 8) {
            providerIcon
            providerPicker
            Spacer(minLength: 4)
            if let provider = model.selected {
                StatusChipView(status: provider.status)
            }
            overflowMenu
        }
    }

    // Keep the artwork outside Menu's native button label. AppKit can reduce
    // a custom SwiftUI menu label to its title and omit the embedded image.
    @ViewBuilder
    private var providerIcon: some View {
        if let view = model.featureView {
            Circle().fill(Theme.accent(view.accentHex)).frame(width: 8, height: 8)
        } else {
            Image(nsImage: Artwork.providerImage(model.selected?.icon ?? "") ?? Artwork.fallbackSymbol)
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)
        }
    }

    private var providerPicker: some View {
        Menu {
            ForEach(model.featureTabs) { view in
                Button {
                    model.showFeature(view)
                } label: {
                    if model.featureView == view {
                        Label(view.title, systemImage: "checkmark")
                    } else {
                        Text(view.title)
                    }
                }
            }
            if !model.featureTabs.isEmpty {
                Divider()
            }
            ForEach(model.providers) { provider in
                Button {
                    model.showFeature(nil)
                    model.selectedID = provider.id
                } label: {
                    // A check mark is how a Mac menu says which item it is on.
                    if model.featureView == nil, provider.id == model.selectedID {
                        Label(provider.label, systemImage: "checkmark")
                    } else {
                        Text(provider.label)
                    }
                }
            }
        } label: {
            Text(model.featureView?.title ?? model.selected?.label ?? i18n("AI Usage"))
                .font(.system(size: 13, weight: .semibold))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(model.providers.count <= 1 && model.featureTabs.isEmpty)
        .accessibilityLabel(i18n("Choose a provider"))
    }

    private var overflowMenu: some View {
        Menu {
            Button(i18n("Refresh")) { model.refreshManually() }
                .keyboardShortcut("r")
            Button(i18n("Settings") + "…") { model.showingSettings = true }
                .keyboardShortcut(",")
            Divider()
            Button(i18n("Quit AI Usage")) { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(systemName: "ellipsis")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(i18n("More actions"))
    }

    // ── Body ─────────────────────────────────────────────────────────────

    @ViewBuilder
    private var content: some View {
        if !model.hasBackend {
            message(
                title: i18n("The usage backend is missing"),
                detail: i18n("This build has no copy of the Python backend to ask."))
        } else if !model.backendError.isEmpty {
            message(title: i18n("Could not read usage"), detail: model.backendError)
        } else if let view = model.featureView {
            featureBody(view)
        } else if let provider = model.selected {
            providerBody(provider)
        } else if model.isLoading {
            HStack {
                ProgressView().controlSize(.small)
                Text(i18n("Reading usage…")).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 8)
        } else {
            message(
                title: i18n("No providers are switched on"),
                detail: i18n("Open Settings to choose the services to follow."))
        }
    }

    /// The rows worth drawing: a quota window the provider had no reading for
    /// is not an empty meter, it is nothing to say.
    private func rows(_ provider: Provider) -> [QuotaWindow] {
        provider.visibleQuotaWindows
    }

    @ViewBuilder
    private func featureBody(_ view: FeatureView) -> some View {
        switch view {
        case .overview: OverviewView(model: model)
        case .spend: SpendView(model: model)
        case .sessions: SessionsView(model: model)
        }
    }

    @ViewBuilder
    private func providerBody(_ provider: Provider) -> some View {
        VStack(alignment: .leading, spacing: Theme.rowSpacing) {
            if !provider.error.isEmpty {
                message(title: provider.label, detail: provider.error)
            }

            if rows(provider).isEmpty, provider.error.isEmpty {
                message(
                    title: provider.summary.text.isEmpty ? provider.label : provider.summary.text,
                    detail: provider.summary.detail)
            }

            // One clock for the whole popover, so every countdown on screen
            // ticks at the same moment instead of each row drifting.
            TimelineView(.periodic(from: .now, by: 30)) { timeline in
                quotaRows(provider, nowMs: timeline.date.timeIntervalSince1970 * 1000)
            }

            if provider.hasChart, model.settings.showChart {
                disclosure(i18n("Usage history"), isOpen: model.showingChart) {
                    model.showingChart.toggle()
                } content: {
                    HistoryChartView(provider: provider, history: model.history, accent: accent)
                }
            }

            if provider.hasStats {
                disclosure(i18n("Activity Stats"), isOpen: model.showingStats) {
                    model.showingStats.toggle()
                } content: {
                    StatsView(stats: provider.stats, currency: provider.currency, accent: accent)
                }
            }
        }
    }

    private func quotaRows(_ provider: Provider, nowMs: Double) -> some View {
        VStack(alignment: .leading, spacing: Theme.rowSpacing) {
            ForEach(rows(provider)) { window in
                QuotaRowView(window: window, accent: accent, nowMs: nowMs)
            }
        }
    }

    /// A section the popover opens on demand. The thing the popover is opened
    /// for stays at the top; charts and statistics are one click below it.
    // Generic rather than `() -> some View`: an opaque type is not
    // expressible as a closure's return type in a parameter position.
    private func disclosure<Content: View>(
        _ title: String, isOpen: Bool, toggle: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { toggle() }
            } label: {
                HStack {
                    Text(title).font(.system(size: 12, weight: .medium))
                    Spacer()
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen { content() }
        }
    }

    private func message(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 12, weight: .medium))
            if !detail.isEmpty {
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // ── Footer ───────────────────────────────────────────────────────────

    private var footer: some View {
        HStack {
            Text(updatedText)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                model.refreshManually()
            } label: {
                if model.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .medium))
                }
            }
            .buttonStyle(.plain)
            .disabled(model.isLoading)
            .accessibilityLabel(i18n("Refresh"))
        }
    }

    private var updatedText: String {
        guard let updated = model.lastUpdated else { return i18n("Not read yet") }
        return i18n("Updated %1", Stamp.ago(updated.timeIntervalSince1970))
    }
}
