import Foundation

// The backend's JSON model, schema version 1 — docs/provider-contract.md.
//
// Only the provider-agnostic half is decoded here: `summary`, `quotaWindows`,
// `chartWindows`, `slots`, `historyValues` and the shared `details.status`.
// That is deliberate. Those fields describe any provider without naming one,
// so a provider added to the backend shows up in this app with no Swift
// change at all — which is the whole reason a second frontend is affordable.
// `details` beyond the shared sub-objects belongs to the Plasma widget's
// per-provider tabs and is skipped.

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

struct Provider: Decodable, Identifiable, Equatable {
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
    }

    /// Rows worth a meter, in contract order.
    var meterRows: [QuotaWindow] { quotaWindows }

    var hasChart: Bool { summary.hasChart && !chartWindows.isEmpty }

    var hasStats: Bool { stats.available }
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
