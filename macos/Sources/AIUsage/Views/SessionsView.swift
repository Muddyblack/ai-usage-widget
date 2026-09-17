import SwiftUI

/// The optional Sessions view: recent local agent sessions as redacted
/// titles with recency only — never paths or transcripts. Tapping a row
/// opens that session's provider.
struct SessionsView: View {
    @ObservedObject var model: AppModel
    @State private var filterText = ""

    private var normalizedFilterText: String {
        filterText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(FeatureView.sessions.title).font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 8)
                if model.sessionsLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Text(i18np("%1 local session", "%1 local sessions", model.sessionsTotal))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Button { model.refreshSessions(query: filterText) } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .disabled(model.sessionsLoading)
                .accessibilityLabel(i18n("Refresh sessions"))
            }
            if !model.localSessions.isEmpty || !normalizedFilterText.isEmpty {
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
            if !model.sessionsLoading, model.localSessions.isEmpty, model.sessionsError.isEmpty, normalizedFilterText.isEmpty {
                FeatureViews.message(detail: i18n("No local agent sessions found. They appear after Claude Code, Codex, Muse, Cline or Grok CLI records activity."))
            }
            if !model.sessionsLoading, model.localSessions.isEmpty, model.sessionsError.isEmpty, !normalizedFilterText.isEmpty {
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
            .frame(maxHeight: min(360, CGFloat(model.localSessions.count) * 56))
            if model.sessionsHasMore {
                Button { model.loadMoreSessions() } label: {
                    Text(i18n("Load more"))
                        .font(.system(size: 11, weight: .medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(model.sessionsLoading)
            }
        }
        .onAppear { model.refreshSessions(query: filterText) }
        .onChange(of: filterText) { model.scheduleSessionsRefresh(query: $0) }
    }

    @ViewBuilder
    private var sessionRows: some View {
        ForEach(model.localSessions) { session in
            // Not a Button: the resume button below needs to be tappable on
            // its own, and SwiftUI does not route taps to a Button nested
            // inside another Button's label.
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(Theme.accent(model.envelope.provider(id: session.provider)?.accent ?? FeatureView.sessions.accentHex))
                    .frame(width: 8, height: 8)
                    .padding(.top, 4)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title.isEmpty ? session.provider : session.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    if !session.sessionName.isEmpty, session.sessionName != session.title {
                        Text(session.sessionName).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    if !session.detail.isEmpty {
                        Text(session.detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    }
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
