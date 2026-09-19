import SwiftUI
import Foundation

/// The optional Sessions view: recent local agent sessions as redacted
/// titles with recency only — never paths or transcripts. Tapping a row
/// opens that session's provider.
struct SessionsView: View {
    @ObservedObject var model: AppModel
    @State private var filterText = ""
    /// Rows currently showing their full (untruncated) title, by session id.
    @State private var expandedIDs: Set<String> = []

    /// Client-side only: filters the already-fetched list by title, session
    /// name, detail or provider id. No backend round-trip.
    private var filteredSessions: [LocalSession] {
        let q = filterText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return model.localSessions }
        return model.localSessions.filter { session in
            [session.title, session.sessionName, session.detail, session.provider]
                .joined(separator: " ")
                .lowercased()
                .contains(q)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(FeatureView.sessions.title).font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 8)
                if model.sessionsLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Text(i18np("%1 local session", "%1 local sessions", model.localSessions.count))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Button { model.refreshSessions() } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .disabled(model.sessionsLoading)
                .accessibilityLabel(i18n("Refresh sessions"))
            }
            if !model.localSessions.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundStyle(.secondary)
                    TextField(i18n("Search sessions…"), text: $filterText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.5)))
            }
            if !model.sessionsError.isEmpty {
                Text(model.sessionsError).font(.system(size: 11)).foregroundStyle(.red)
            }
            if !model.sessionsNotice.isEmpty {
                Text(model.sessionsNotice).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if !model.sessionsLoading, model.localSessions.isEmpty, model.sessionsError.isEmpty {
                FeatureViews.message(detail: i18n("No local agent sessions found. They appear after Claude Code, Codex, Muse, Cline or Grok CLI records activity."))
            }
            if !model.localSessions.isEmpty, filteredSessions.isEmpty {
                FeatureViews.message(detail: i18n("No sessions match your search."))
            }
            // Bounded and independently scrollable: the header above (title,
            // count, search) stays put instead of scrolling away with a long
            // list — the popover as a whole only grows to fit this box, not
            // every row in it.
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    sessionRows
                }
            }
            .frame(maxHeight: min(360, CGFloat(filteredSessions.count) * 56))
        }
        .onAppear { model.refreshSessions() }
    }

    @ViewBuilder
    private var sessionRows: some View {
        ForEach(filteredSessions) { session in
            // Not a Button: the resume button below needs to be tappable on
            // its own, and SwiftUI does not route taps to a Button nested
            // inside another Button's label.
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(Theme.accent(model.envelope.provider(id: session.provider)?.accent ?? FeatureView.sessions.accentHex))
                    .frame(width: 8, height: 8)
                    .padding(.top, 4)
                VStack(alignment: .leading, spacing: 2) {
                    let expanded = expandedIDs.contains(session.id)
                    Text(expanded && !session.fullTitle.isEmpty ? session.fullTitle : (session.title.isEmpty ? session.provider : session.title))
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(expanded ? nil : 1)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard !session.fullTitle.isEmpty else { return }
                            if expanded { expandedIDs.remove(session.id) } else { expandedIDs.insert(session.id) }
                        }
                    if !session.sessionName.isEmpty, session.sessionName != session.title {
                        Text(session.sessionName).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    if !session.detail.isEmpty {
                        Text(session.detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Text(SessionCostPresentation.text(
                        costUSD: session.costUSD,
                        status: session.costStatus,
                        provenance: session.costProvenance,
                        breakdown: session.costBreakdown))
                        .font(.system(size: 9))
                        .foregroundStyle(SessionCostPresentation.color(
                            costUSD: session.costUSD,
                            status: session.costStatus,
                            provenance: session.costProvenance,
                            accent: Theme.accent(model.envelope.provider(id: session.provider)?.accent ?? FeatureView.sessions.accentHex)))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(session.isActive ? i18n("Active") : i18n("Idle"))
                        .font(.system(size: 11, weight: .semibold))
                    Text(Stamp.ago(session.lastActivityAt))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                if !session.openKey.isEmpty {
                    Button { model.openSession(session.openKey) } label: {
                        Image(systemName: "terminal")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(i18n("Resume session"))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard !session.provider.isEmpty else { return }
                model.showFeature(nil); model.selectedID = session.provider
            }
        }
    }
}

enum SessionCostPresentation {
    static func text(
        costUSD: Double?,
        status: String,
        provenance: String? = nil,
        breakdown: CostBreakdown? = nil) -> String {
        guard let costUSD, costUSD.isFinite, (status == "exact" || status == "partial") else {
            return i18n("Cost unavailable")
        }
        if provenance == "mixed" {
            guard let breakdown else { return i18n("Cost unavailable") }
            let actual = formatted(breakdown.actualUSD)
            let estimate = formatted(breakdown.estimatedUSD)
            return i18n("Actual %1 + estimate %2 (%3)", actual, estimate, status)
        }
        let formatted = formatted(costUSD)
        if provenance == "actual" {
            return i18n("Actual cost: %1 (%2)", formatted, status)
        }
        if provenance == "estimated" {
            return i18n("Calculated estimate: %1 (%2)", formatted, status)
        }
        return i18n("Cost: %1 (%2)", formatted, status)
    }

    static func color(costUSD: Double?, status: String, provenance: String? = nil, accent: Color) -> Color {
        guard let costUSD, costUSD.isFinite, status == "exact" || status == "partial" else { return .secondary }
        if provenance == "actual" || provenance == nil, status == "exact" { return accent }
        if provenance == "estimated" || provenance == "mixed" || status == "partial" { return .orange }
        return .secondary
    }

    private static func formatted(_ costUSD: Double) -> String {
        String(format: "$%.4f", locale: Locale(identifier: "en_US_POSIX"), arguments: [costUSD])
    }
}

/// The two one-line helpers the feature views share.
enum FeatureViews {
    static func header(title: String, count: Int) -> some View {
        HStack {
            Text(title).font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 8)
            Text(i18np("%1 provider", "%1 providers", count))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    static func message(detail: String) -> some View {
        Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
    }
}
