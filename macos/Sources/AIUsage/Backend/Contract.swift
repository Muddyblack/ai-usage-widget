import Foundation

// The backend's JSON model, schema version 1 — docs/provider-contract.md.
//
// Only the provider-agnostic half is decoded here: `summary`, `quotaWindows`,
// `chartWindows`, `slots`, `historyValues` and the shared `details.status`.
// That is deliberate. Those fields describe any provider without naming one,
// so a provider added to the backend shows up in this app with no Swift
// change at all — which is the whole reason a second frontend is affordable.
// `details` beyond the shared sub-objects belongs to the Plasma widget's
// per-provider tabs and is skipped — except for the handful of spend figures
// the optional Usage & Spend view totals (see `SpendRow`), which are the same
// provider-agnostic cost numbers the Linux Spend tabs total in FeatureTabs.js.
// Local agent sessions (`LocalSession`) are their own envelope on purpose:
// redacted titles and recency only, never paths or transcripts.

struct Envelope: Decodable {
    var schemaVersion: Int
    var updatedAt: Double
    var active: String
    var providers: [Provider]

    enum CodingKeys: String, CodingKey {
        case schemaVersion, updatedAt, active, providers
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = (try? c.decode(Int.self, forKey: .schemaVersion)) ?? 1
        updatedAt = (try? c.decode(Double.self, forKey: .updatedAt)) ?? 0
        active = (try? c.decode(String.self, forKey: .active)) ?? ""
        providers = (try? c.decode([Provider].self, forKey: .providers)) ?? []
    }

    init(providers: [Provider] = [], active: String = "", updatedAt: Double = 0) {
        self.schemaVersion = 1
        self.updatedAt = updatedAt
        self.active = active
        self.providers = providers
    }

    func provider(id: String) -> Provider? {
        providers.first { $0.id == id }
    }

    /// The provider a frontend should show when its remembered one is gone:
    /// the backend's `active` (the first healthy one), else the first row.
    var fallbackID: String {
        if !active.isEmpty, provider(id: active) != nil { return active }
        return providers.first?.id ?? ""
    }
}

// ── Feature views ────────────────────────────────────────────────────────
// The same optional tabs the Linux frontends offer (Overview / Usage & Spend /
// Sessions), with the same defaults and the same shared settings keys, so a
// toggle in one frontend is a toggle in all of them. A feature view has no
// panel meter of its own — it sits ahead of the provider rows.

enum FeatureView: String, CaseIterable, Identifiable {
    case overview
    case spend
    case sessions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return i18n("Overview")
        case .spend: return i18n("Usage & Spend")
        case .sessions: return i18n("Sessions")
        }
    }

    var subtitle: String {
        switch self {
        case .overview: return i18n("All enabled providers at a glance")
        case .spend: return i18n("Combined cost figures across providers")
        case .sessions: return i18n("Recent local agent sessions (no transcripts)")
        }
    }

    var accentHex: String {
        switch self {
        case .overview: return "#38bdf8"
        case .spend: return "#34d399"
        case .sessions: return "#a78bfa"
        }
    }
}

// One row of the optional Usage & Spend view: the spend figure one provider
// already reported, with the range it covers. Ranges differ by source
// (30-day, all-time, lifetime) — the same caveat the Linux Spend tabs print.
struct SpendRow: Identifiable {
    let provider: Provider
    let cost: Double
    let currency: String
    let note: String

    var id: String { provider.id }
}

// The per-provider cost numbers the backend already exposed, in the same
// order and with the same sources as FeatureTabs.js `spendProviderRows`:
// Claude/OpenAI organisation usage, OpenRouter credit usage, Mistral vibe
// spend, Muse/Cline local stats, Cursor on-demand spend. Costs are read out
// of the generic details dictionary so no new per-provider contract is needed.
enum SpendRows {
    static func build(_ providers: [Provider]) -> [SpendRow] {
        var out: [SpendRow] = []
        for provider in providers {
            let details = provider.costDetails
            let cost: Double
            let note: String
            let currency: String
            switch provider.id {
            case "claude", "openai":
                cost = details.double(paths: [["organizationUsage", "totalCostUSD"], ["org", "totalCostUSD"], ["totalCostUSD"], ["stats", "totalCostUSD"]])
                note = "30d API"
                currency = "USD"
            case "openrouter":
                cost = details.double(paths: [["usageUSD"], ["usage"]])
                note = "all-time"
                currency = "USD"
            case "mistral":
                cost = details.double(paths: [["vibe", "totalCost"], ["vibeTotalCost"], ["totalCost"]])
                note = "vibe CLI"
                currency = "USD"
            case "muse":
                cost = details.double(paths: [["stats", "totalCostUSD"], ["totalCostUSD"]])
                note = "local est."
                currency = details.string(paths: [["stats", "currency"], ["currency"]], fallback: "USD")
            case "cline":
                cost = details.double(paths: [["stats", "totalCostUSD"], ["totalCostUSD"]])
                note = "local"
                currency = "USD"
            case "cursor":
                cost = details.double(paths: [["onDemandUsed"], ["onDemandSpendUSD"], ["onDemand"]])
                note = "on-demand"
                currency = "USD"
            default:
                continue
            }
            guard cost > 0 else { continue }
            out.append(SpendRow(provider: provider, cost: cost, currency: currency, note: note))
        }
        return out.sorted { $0.cost > $1.cost }
    }

    static func totalUSD(_ rows: [SpendRow]) -> Double {
        rows.filter { $0.currency == "USD" }.reduce(0) { $0 + $1.cost }
    }
}

// ── Local sessions ───────────────────────────────────────────────────────
// `get-ai-usage --sessions`'s own envelope: a merged, newest-first, redacted
// list of local agent sessions. Decoding is lenient field-by-field, the same
// pattern as `Envelope` above, so an addition on the backend side never
// breaks this app.

struct LocalSessions: Decodable {
    var updatedAt: Double
    var sessions: [LocalSession]

    enum CodingKeys: String, CodingKey {
        case updatedAt, sessions
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        updatedAt = (try? c.decode(Double.self, forKey: .updatedAt)) ?? 0
        sessions = (try? c.decode([LocalSession].self, forKey: .sessions)) ?? []
    }
}

struct LocalSession: Decodable, Identifiable {
    var provider: String
    var title: String
    var sessionName: String
    var state: String
    var lastActivityAt: Double
    var detail: String
    /// Opaque, content-addressed handle for `--open-session`; empty when the
    /// provider (Muse) has no resume command, in which case no button shows.
    var openKey: String
    /// The untruncated title, present only when `title` was clipped (Claude
    /// Code's own opening prompt — see sessions.py). Empty otherwise; a row
    /// with an empty `fullTitle` offers no expand affordance.
    var fullTitle: String

    enum CodingKeys: String, CodingKey {
        case provider, title, sessionName, state, lastActivityAt, detail, openKey, fullTitle
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        provider = (try? c.decode(String.self, forKey: .provider)) ?? ""
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        sessionName = (try? c.decode(String.self, forKey: .sessionName)) ?? ""
        state = (try? c.decode(String.self, forKey: .state)) ?? ""
        lastActivityAt = (try? c.decode(Double.self, forKey: .lastActivityAt)) ?? 0
        detail = (try? c.decode(String.self, forKey: .detail)) ?? ""
        openKey = (try? c.decode(String.self, forKey: .openKey)) ?? ""
        fullTitle = (try? c.decode(String.self, forKey: .fullTitle)) ?? ""
    }

    var id: String { "\(provider)|\(title)|\(lastActivityAt)|\(openKey)" }

    var isActive: Bool { state == "active" || state == "running" }
}

// A small typeless walk over the provider's raw `details` dictionary — the
// only per-provider reads this app does, and only the spend figures the
// Usage & Spend view totals. Everything else stays in the typed contract.
struct CostDetails {
    let raw: [String: Any]

    func double(paths: [[String]]) -> Double {
        for path in paths {
            if let value = value(at: path), let number = number(value), number > 0 { return number }
        }
        return 0
    }

    func string(paths: [[String]], fallback: String) -> String {
        for path in paths {
            if let value = value(at: path) as? String, !value.isEmpty { return value }
        }
        return fallback
    }

    private func value(at path: [String]) -> Any? {
        var current: Any? = raw
        for key in path {
            guard let dict = current as? [String: Any] else { return nil }
            current = dict[key]
        }
        return current
    }

    private func number(_ value: Any?) -> Double? {
        if let number = value as? Double { return number }
        if let number = value as? Int { return Double(number) }
        if let number = value as? NSNumber { return number.doubleValue }
        if let text = value as? String, let parsed = Double(text) { return parsed }
        return nil
    }
}

struct Provider: Decodable, Identifiable {
    var id: String = ""
    var label: String = ""
    var accent: String = ""
    var icon: String = ""
    var ok: Bool = false
    var stale: Bool = false
    var error: String = ""
    var updatedAt: Double = 0
    var summary = Summary()
    var quotaWindows: [QuotaWindow] = []
    var chartWindows: [ChartWindow] = []
    var slots: [Slot] = []
    var historyValues: [String: Double] = [:]
    var status = ServiceStatus()
    var currency: String = "USD"
    var quotaError: String = ""
    var stats = ActivityStats()
    /// The provider's raw `details` beyond the typed sub-objects — kept only
    /// so the Usage & Spend view can total the cost figures it already
    /// carries. Decoded loosely (heterogeneous JSON) rather than grown into
    /// the typed contract.
    var rawDetails: [String: Any] = [:]

    /// The spend-figure lens over `rawDetails`.
    var costDetails: CostDetails { CostDetails(raw: rawDetails) }

    enum CodingKeys: String, CodingKey {
        case id, label, accent, icon, ok, stale, error, updatedAt
        case summary, quotaWindows, chartWindows, slots, historyValues, details
    }

    enum DetailKeys: String, CodingKey {
        case status, currency, quotaError, stats
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? ""
        label = (try? c.decode(String.self, forKey: .label)) ?? id
        accent = (try? c.decode(String.self, forKey: .accent)) ?? ""
        icon = (try? c.decode(String.self, forKey: .icon)) ?? ""
        ok = (try? c.decode(Bool.self, forKey: .ok)) ?? false
        stale = (try? c.decode(Bool.self, forKey: .stale)) ?? false
        error = (try? c.decode(String.self, forKey: .error)) ?? ""
        updatedAt = (try? c.decode(Double.self, forKey: .updatedAt)) ?? 0
        summary = (try? c.decode(Summary.self, forKey: .summary)) ?? Summary()
        quotaWindows = (try? c.decode([QuotaWindow].self, forKey: .quotaWindows)) ?? []
        chartWindows = (try? c.decode([ChartWindow].self, forKey: .chartWindows)) ?? []
        slots = (try? c.decode([Slot].self, forKey: .slots)) ?? []
        historyValues = (try? c.decode([String: Double].self, forKey: .historyValues)) ?? [:]

        if let details = try? c.nestedContainer(keyedBy: DetailKeys.self, forKey: .details) {
            status = (try? details.decode(ServiceStatus.self, forKey: .status)) ?? ServiceStatus()
            currency = (try? details.decode(String.self, forKey: .currency)) ?? "USD"
            quotaError = (try? details.decode(String.self, forKey: .quotaError)) ?? ""
            stats = (try? details.decode(ActivityStats.self, forKey: .stats)) ?? ActivityStats()
        }
        // The loose half of `details`: whatever JSON object it holds, kept as
        // plain values for the spend-figure walk. A provider the decoder never
        // heard of still totals here, which is the point of the spend view.
        if let detailsJSON = try? c.decode(AnyJSON.self, forKey: .details),
            let detailsObject = detailsJSON.value as? [String: Any] {
            rawDetails = detailsObject
        }
    }

    /// Rows worth a meter, in contract order.
    var meterRows: [QuotaWindow] { quotaWindows }

    var hasChart: Bool { summary.hasChart && !chartWindows.isEmpty }

    var hasStats: Bool { stats.available }

    var visibleQuotaWindows: [QuotaWindow] { quotaWindows.filter(\.available) }
}

struct Summary: Decodable, Equatable {
    var pct: Double = 0
    var text: String = ""
    var detail: String = ""
    var hasChart: Bool = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pct = (try? c.decode(Double.self, forKey: .pct)) ?? 0
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
        detail = (try? c.decode(String.self, forKey: .detail)) ?? ""
        hasChart = (try? c.decode(Bool.self, forKey: .hasChart)) ?? false
    }

    enum CodingKeys: String, CodingKey { case pct, text, detail, hasChart }
}

struct QuotaWindow: Decodable, Equatable, Identifiable {
    var key: String = ""
    var label: String = ""
    var pct: Double = 0
    var available: Bool = false
    var resetAt: Double = 0
    var resetText: String = ""
    var detail: String = ""
    var note: String = ""
    var showMeter: Bool = true

    var id: String { key.isEmpty ? label : key }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = (try? c.decode(String.self, forKey: .key)) ?? ""
        label = (try? c.decode(String.self, forKey: .label)) ?? ""
        pct = (try? c.decode(Double.self, forKey: .pct)) ?? 0
        available = (try? c.decode(Bool.self, forKey: .available)) ?? false
        resetAt = (try? c.decode(Double.self, forKey: .resetAt)) ?? 0
        resetText = (try? c.decode(String.self, forKey: .resetText)) ?? ""
        detail = (try? c.decode(String.self, forKey: .detail)) ?? ""
        note = (try? c.decode(String.self, forKey: .note)) ?? ""
        showMeter = (try? c.decode(Bool.self, forKey: .showMeter)) ?? true
    }

    enum CodingKeys: String, CodingKey {
        case key, label, pct, available, resetAt, resetText, detail, note, showMeter
    }
}

struct ChartWindow: Decodable, Equatable, Identifiable {
    var id: String = ""
    var key: String = ""
    var label: String = ""
    var size: Double = 0
    var granularity: String = ""
    var raw: Bool = false
    var resets: Bool = false
    var periodMs: Double = 0
    var resetAt: Double = 0

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? ""
        key = (try? c.decode(String.self, forKey: .key)) ?? ""
        label = (try? c.decode(String.self, forKey: .label)) ?? ""
        size = (try? c.decode(Double.self, forKey: .size)) ?? 0
        granularity = (try? c.decode(String.self, forKey: .granularity)) ?? ""
        raw = (try? c.decode(Bool.self, forKey: .raw)) ?? false
        resets = (try? c.decode(Bool.self, forKey: .resets)) ?? false
        periodMs = (try? c.decode(Double.self, forKey: .periodMs)) ?? 0
        resetAt = (try? c.decode(Double.self, forKey: .resetAt)) ?? 0
    }

    enum CodingKeys: String, CodingKey {
        case id, key, label, size, granularity, raw, resets, periodMs, resetAt
    }
}

struct Slot: Decodable, Equatable {
    var pct: Double = 0
    var color: String = ""
    /// null in the contract means "draw the meter instead of a number".
    var text: String? = nil
    var tooltip: String = ""

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pct = (try? c.decode(Double.self, forKey: .pct)) ?? 0
        color = (try? c.decode(String.self, forKey: .color)) ?? ""
        text = try? c.decode(String.self, forKey: .text)
        tooltip = (try? c.decode(String.self, forKey: .tooltip)) ?? ""
    }

    enum CodingKeys: String, CodingKey { case pct, color, text, tooltip }
}

struct ServiceStatus: Decodable, Equatable {
    /// "" | none | minor | major | critical
    var indicator: String = ""
    var description: String = ""
    var latestUpdate: String = ""
    var url: String = ""

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        indicator = (try? c.decode(String.self, forKey: .indicator)) ?? ""
        description = (try? c.decode(String.self, forKey: .description)) ?? ""
        latestUpdate = (try? c.decode(String.self, forKey: .latestUpdate)) ?? ""
        url = (try? c.decode(String.self, forKey: .url)) ?? ""
    }

    enum CodingKeys: String, CodingKey { case indicator, description, latestUpdate, url }

    /// Worth showing a dot for: a live reading that is not "all clear".
    var isTrouble: Bool {
        ["minor", "major", "critical"].contains(indicator)
    }
}


/// `details.stats` — what the CLI wrote to disk, for the providers that keep a
/// local log: Claude Code, the Codex CLI, the Copilot CLI, Muse and Cursor.
///
/// The only part of `details` this app reads beyond the shared sub-objects, and
/// it is shared too: five providers fill in the same fields, with a handful of
/// extras each. Nothing here is per-provider logic — the fields a provider does
/// not report are zero, and a zero row is not drawn.
struct ActivityStats: Decodable, Equatable {
    var available = false

    var totalSessions: Double = 0
    var totalMessages: Double = 0
    var totalTokens: Double = 0
    var totalToolCalls: Double = 0
    var totalCostUSD: Double = 0
    var totalWebSearches: Double = 0
    var totalFiles: Double = 0
    var totalRepositories: Double = 0

    var activeDays: Double = 0
    var spanDays: Double = 0
    var currentStreak: Double = 0
    var longestStreak: Double = 0
    var longestSessionMs: Double = 0
    var longestSessionMessages: Double = 0
    /// Hour of day, 0–23. -1 when the provider reported none.
    var peakHour: Double = -1

    var favoriteModel = ""
    var firstDate = ""
    var computedDate = ""

    /// What the per-day series counts — not every CLI records tokens; the
    /// Copilot CLI counts messages and Cursor counts requests.
    var dailyUnit = "tokens"
    var daily: [DailyPoint] = []

    /// Where the sessions went: repositories for the Copilot CLI, workspace
    /// folders for Muse. One list, and `topGroupsAreRepositories` says which
    /// word to put above it.
    var topGroups: [NamedCount] = []
    var topGroupsAreRepositories = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func number(_ key: CodingKeys, _ fallback: Double = 0) -> Double {
            (try? c.decode(Double.self, forKey: key)) ?? fallback
        }
        func text(_ key: CodingKeys) -> String {
            (try? c.decode(String.self, forKey: key)) ?? ""
        }

        available = (try? c.decode(Bool.self, forKey: .available)) ?? false
        totalSessions = number(.totalSessions)
        totalMessages = number(.totalMessages)
        totalTokens = number(.totalTokens)
        totalToolCalls = number(.totalToolCalls)
        totalCostUSD = number(.totalCostUSD)
        totalWebSearches = number(.totalWebSearches)
        totalFiles = number(.totalFiles)
        totalRepositories = number(.totalRepositories)

        activeDays = number(.activeDays)
        spanDays = number(.spanDays)
        currentStreak = number(.currentStreak)
        longestStreak = number(.longestStreak)
        longestSessionMs = number(.longestSessionMs)
        longestSessionMessages = number(.longestSessionMessages)
        peakHour = number(.peakHour, -1)

        favoriteModel = text(.favoriteModel)
        firstDate = text(.firstDate)
        computedDate = text(.computedDate)

        dailyUnit = (try? c.decode(String.self, forKey: .dailyUnit)) ?? "tokens"
        // dailySeries is the named one; dailyTokens is what a provider that
        // only ever counted tokens still sends.
        daily = (try? c.decode([DailyPoint].self, forKey: .dailySeries))
            ?? (try? c.decode([DailyPoint].self, forKey: .dailyTokens))
            ?? []

        if let repositories = try? c.decode([NamedCount].self, forKey: .topRepositories), !repositories.isEmpty {
            topGroups = repositories
            topGroupsAreRepositories = true
        } else {
            topGroups = (try? c.decode([NamedCount].self, forKey: .topWorkspaces)) ?? []
        }
    }

    enum CodingKeys: String, CodingKey {
        case available
        case totalSessions, totalMessages, totalTokens, totalToolCalls
        case totalCostUSD, totalWebSearches, totalFiles, totalRepositories
        case activeDays, spanDays, currentStreak, longestStreak
        case longestSessionMs, longestSessionMessages, peakHour
        case favoriteModel, firstDate, computedDate
        case dailyUnit, dailySeries, dailyTokens
        case topRepositories, topWorkspaces
    }
}

struct DailyPoint: Decodable, Equatable, Identifiable {
    var date = ""
    var total: Double = 0
    var id: String { date }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = (try? c.decode(String.self, forKey: .date)) ?? ""
        total = (try? c.decode(Double.self, forKey: .total)) ?? 0
    }

    enum CodingKeys: String, CodingKey { case date, total }
}

struct NamedCount: Decodable, Equatable, Identifiable {
    var name = ""
    var sessions: Double = 0
    var id: String { name }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        sessions = (try? c.decode(Double.self, forKey: .sessions)) ?? 0
    }

    enum CodingKeys: String, CodingKey { case name, sessions }
}

// A heterogeneous JSON value — the loose half of `details`, decoded without
// growing the typed contract for every provider-specific key.
enum AnyJSON: Decodable {
    case object([String: AnyJSON])
    case array([AnyJSON])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    var value: Any {
        switch self {
        case let .object(object): return object.mapValues { $0.value }
        case let .array(array): return array.map { $0.value }
        case let .string(text): return text
        case let .number(number): return number
        case let .bool(flag): return flag
        case .null: return NSNull()
        }
    }

    init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if single.decodeNil() { self = .null; return }
        if let flag = try? single.decode(Bool.self) { self = .bool(flag); return }
        if let number = try? single.decode(Double.self) { self = .number(number); return }
        if let text = try? single.decode(String.self) { self = .string(text); return }
        if let array = try? single.decode([AnyJSON].self) { self = .array(array); return }
        self = .object((try? single.decode([String: AnyJSON].self)) ?? [:])
    }
}
