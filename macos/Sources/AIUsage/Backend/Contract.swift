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
    var localSpend: LocalSpend

    enum CodingKeys: String, CodingKey {
        case schemaVersion, updatedAt, active, providers, localSpend
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = (try? c.decode(Int.self, forKey: .schemaVersion)) ?? 1
        updatedAt = (try? c.decode(Double.self, forKey: .updatedAt)) ?? 0
        active = (try? c.decode(String.self, forKey: .active)) ?? ""
        providers = (try? c.decode([Provider].self, forKey: .providers)) ?? []
        localSpend = (try? c.decode(LocalSpend.self, forKey: .localSpend)) ?? LocalSpend()
    }

    init(
        providers: [Provider] = [],
        active: String = "",
        updatedAt: Double = 0,
        localSpend: LocalSpend = LocalSpend()) {
        self.schemaVersion = 1
        self.updatedAt = updatedAt
        self.active = active
        self.providers = providers
        self.localSpend = localSpend
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
    let provider: Provider?
    let source: String?
    private let localIdentity: String?
    let label: String
    let accent: String
    let cost: Double
    let currency: String
    let note: String
    let provenance: String?
    let costStatus: String?
    let costBreakdown: CostBreakdown?
    let billing: String?
    /// Per-day history for the expandable chart. Cost comes from the session
    /// rows the total is summed from, tokens from the same rows, so the two
    /// always cover the same days.
    let dailyCost: [DailyCostPoint]
    let dailyTokens: [DailyPoint]

    var canExpand: Bool { dailyCost.count > 1 || dailyTokens.count > 1 }

    var id: String {
        if let provider { return provider.id }
        if billing == "subscription" {
            if let localIdentity { return "plan-\(localIdentity)" }
            if let source { return "plan-\(source)" }
            return "plan-subscription"
        }
        if let localIdentity { return "local-\(localIdentity)" }
        if let source { return "local-\(source)" }
        return "local-sessions"
    }

    init(provider: Provider, cost: Double, currency: String, note: String,
         dailyCost: [DailyCostPoint] = [], dailyTokens: [DailyPoint] = []) {
        self.dailyCost = dailyCost
        self.dailyTokens = dailyTokens
        self.provider = provider
        self.source = nil
        self.localIdentity = nil
        self.label = provider.label
        self.accent = provider.accent
        self.cost = cost
        self.currency = currency
        self.note = note
        self.provenance = nil
        self.costStatus = nil
        self.costBreakdown = nil
        self.billing = nil
    }

    init(localCost: Double) {
        self.init(localCost: localCost, label: i18n("Local sessions"), provenance: nil)
    }

    init(localCost: Double, label: String, provenance: String?, costStatus: String? = nil) {
        self.dailyCost = []
        self.dailyTokens = []
        self.provider = nil
        self.source = nil
        self.localIdentity = nil
        self.label = label
        self.accent = "#34d399"
        self.cost = localCost
        self.currency = "USD"
        self.note = costStatus.map {
            Self.localSpendNote(provenance ?? "legacy", costStatus: $0)
        } ?? i18n("local CLI logs")
        self.provenance = provenance
        self.costStatus = costStatus
        self.costBreakdown = nil
        self.billing = nil
    }

    init(localSource: String, actualUSD: Double, estimatedUSD: Double,
         provenance: String, costStatus: String, billingProvider: String? = nil,
         identity: String? = nil, viaSource: String? = nil, billing: String? = nil,
         dailyCost: [DailyCostPoint] = [], dailyTokens: [DailyPoint] = []) {
        self.dailyCost = dailyCost
        self.dailyTokens = dailyTokens
        let sourceKey = Self.localSourceKey(localSource)
        let viaSourceKey = Self.localSourceKey(viaSource ?? "")
        self.provider = nil
        self.source = sourceKey
        self.localIdentity = identity.map(Self.localSourceKey)
        self.label = Self.localSourceLabel(sourceKey, upstream: billingProvider)
        self.accent = "#34d399"
        self.cost = actualUSD + estimatedUSD
        self.currency = "USD"
        self.billing = billing
        if billing == "subscription" {
            self.note = Self.planSpendNote(costStatus, source: viaSourceKey)
        } else {
            self.note = Self.localSpendNote(provenance, costStatus: costStatus, source: viaSourceKey)
        }
        self.provenance = provenance
        self.costStatus = costStatus
        self.costBreakdown = CostBreakdown(actualUSD: actualUSD, estimatedUSD: estimatedUSD)
    }

    fileprivate func filtered(to timeframe: SpendTimeframe, referenceDate: Date) -> SpendRow {
        guard timeframe != .all else { return self }

        let calendar = SpendTimeframe.calendar
        let formatter = SpendTimeframe.dateFormatter
        let end = calendar.startOfDay(for: referenceDate)
        let start = calendar.date(byAdding: .day, value: -(timeframe.dayCount - 1), to: end) ?? end
        let startKey = formatter.string(from: start)
        let endKey = formatter.string(from: end)
        let cost = dailyCost.filter { $0.date >= startKey && $0.date <= endKey }
        let tokens = dailyTokens.filter { $0.date >= startKey && $0.date <= endKey }

        return SpendRow(copying: self, series: SpendSeries(
            cost: cost.reduce(0) { $0 + $1.usd }, dailyCost: cost, dailyTokens: tokens))
    }

    private struct SpendSeries {
        let cost: Double
        let dailyCost: [DailyCostPoint]
        let dailyTokens: [DailyPoint]
    }

    private init(copying row: SpendRow, series: SpendSeries) {
        provider = row.provider
        source = row.source
        localIdentity = row.localIdentity
        label = row.label
        accent = row.accent
        cost = series.cost
        currency = row.currency
        note = row.note
        provenance = row.provenance
        costStatus = row.costStatus
        costBreakdown = row.costBreakdown
        billing = row.billing
        dailyCost = series.dailyCost
        dailyTokens = series.dailyTokens
    }

    private static func localSourceKey(_ source: String) -> String {
        source.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
    }

    private static func localSourceLabel(_ source: String, upstream: String? = nil) -> String {
        if source == "opencode", let upstream {
            switch localSourceKey(upstream) {
            case "anthropic": return i18n("Anthropic")
            case "openai": return i18n("OpenAI")
            case "openrouter": return i18n("OpenRouter")
            case "ollama-cloud": return i18n("Ollama Cloud")
            case "ollama": return i18n("Ollama")
            case "github-copilot": return i18n("GitHub Copilot")
            case "google": return i18n("Google")
            case "zenmux": return i18n("ZenMux")
            case "opencode": return i18n("OpenCode Zen")
            default: break
            }
        }
        switch localSourceKey(source) {
        case "opencode": return i18n("OpenCode")
        case "claude", "claude-code", "claude_code": return i18n("Claude Code")
        case "openai", "codex": return i18n("Codex")
        case "cline": return i18n("Cline")
        case "grok", "grok-cli": return i18n("Grok CLI")
        case "muse": return i18n("Muse")
        case "antigravity": return i18n("Antigravity")
        default:
            let fallback = localSourceKey(source)
                .replacingOccurrences(of: "-", with: " ")
                .split(whereSeparator: { $0.isWhitespace })
                .joined(separator: " ")
            return fallback.isEmpty ? i18n("Local source") : fallback.capitalized
        }
    }

    private static func localSpendNote(_ provenance: String, costStatus: String, source: String = "") -> String {
        let prefix = source == "opencode" ? i18n("via OpenCode") : i18n("local CLI logs")
        switch "\(provenance):\(costStatus)" {
        case "legacy:exact": return "\(prefix) · exact"
        case "legacy:partial": return "\(prefix) · partial"
        case "actual:exact": return "\(prefix) · actual · exact"
        case "actual:partial": return "\(prefix) · actual · partial"
        case "estimated:exact": return "\(prefix) · estimated · exact"
        case "estimated:partial": return "\(prefix) · estimated · partial"
        case "mixed:exact": return "\(prefix) · mixed · exact"
        case "mixed:partial": return "\(prefix) · mixed · partial"
        default: return prefix
        }
    }

    private static func planSpendNote(_ costStatus: String, source: String = "") -> String {
        let prefix = source == "opencode" ? i18n("via OpenCode") : i18n("covered by plan")
        let wouldCost = i18n("would cost on API")
        let partial = i18n("partial")
        return "\(prefix) · \(wouldCost)" + (costStatus == "partial" ? " · \(partial)" : "")
    }
}

enum SpendTimeframe: CaseIterable, Hashable {
    case oneDay
    case sevenDays
    case thirtyDays
    case all

    var title: String {
        switch self {
        case .oneDay: return "1D"
        case .sevenDays: return "7D"
        case .thirtyDays: return "30D"
        case .all: return "ALL"
        }
    }

    var dayCount: Int {
        switch self {
        case .oneDay: return 1
        case .sevenDays: return 7
        case .thirtyDays: return 30
        case .all: return 0
        }
    }

    fileprivate static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }()

    fileprivate static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

/// One day of a provider's spend, from the session rows the totals are summed
/// from — so a provider's series always adds up to the figure beside it. A
/// plan-covered provider reports no real API cost, which is why this cannot
/// come from the provider's own usage stats.
struct DailyCostPoint: Decodable, Equatable, Identifiable {
    var date = ""
    var usd = 0.0
    var id: String { date }

    init(date: String = "", usd: Double = 0) {
        self.date = date
        self.usd = usd.isFinite && usd >= 0 ? usd : 0
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = (try? c.decode(String.self, forKey: .date)) ?? ""
        let decoded = (try? c.decode(Double.self, forKey: .usd)) ?? 0
        usd = decoded.isFinite && decoded >= 0 ? decoded : 0
    }

    enum CodingKeys: String, CodingKey { case date, usd }
}

struct LocalSpendProvider: Decodable, Equatable {
    var costUSD = 0.0
    var costStatus = "unavailable"
    var costProvenance: String?
    var source: String?
    /// Both halves of the expandable row chart, over the same days.
    var dailyUSD: [DailyCostPoint] = []
    var dailyTokens: [DailyPoint] = []

    init(costUSD: Double = 0, costStatus: String = "unavailable", costProvenance: String? = nil, source: String? = nil,
         dailyUSD: [DailyCostPoint] = [], dailyTokens: [DailyPoint] = []) {
        self.costUSD = costUSD
        self.costStatus = ["exact", "partial", "unavailable"].contains(costStatus)
            ? costStatus : "unavailable"
        self.costProvenance = Self.validProvenance(costProvenance)
        self.source = source
        self.dailyUSD = dailyUSD
        self.dailyTokens = dailyTokens
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let decodedCost = try? c.decode(Double.self, forKey: .costUSD)
        let decodedStatus = (try? c.decode(String.self, forKey: .costStatus)) ?? "unavailable"
        let decodedProvenance = try? c.decode(String.self, forKey: .costProvenance)
        let decodedSource = try? c.decode(String.self, forKey: .source)
        let validCost = decodedCost.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        let validStatus = ["exact", "partial", "unavailable"].contains(decodedStatus)
        let validOrigin = Self.validProvenance(decodedProvenance)
        costUSD = validCost ?? 0
        costStatus = validCost != nil && validStatus && (decodedProvenance == nil || validOrigin != nil)
            ? decodedStatus : "unavailable"
        costProvenance = costStatus == "unavailable" ? nil : validOrigin
        source = costStatus == "unavailable" ? nil : decodedSource
        dailyUSD = (try? c.decode([DailyCostPoint].self, forKey: .dailyUSD)) ?? []
        dailyTokens = (try? c.decode([DailyPoint].self, forKey: .dailyTokens)) ?? []
    }

    enum CodingKeys: String, CodingKey { case costUSD, costStatus, costProvenance, source, dailyUSD, dailyTokens }

    static func validProvenance(_ value: String?) -> String? {
        guard let value, ["actual", "estimated", "mixed"].contains(value) else { return nil }
        return value
    }
}

struct LocalSpendTotal: Decodable, Equatable {
    var totalUSD = 0.0
    var costStatus = "unavailable"
    var costProvenance: String?
    var providers: [String: LocalSpendProvider] = [:]

    init(totalUSD: Double = 0, costStatus: String = "unavailable", costProvenance: String? = nil,
         providers: [String: LocalSpendProvider] = [:]) {
        self.totalUSD = totalUSD
        self.costStatus = ["exact", "partial", "unavailable"].contains(costStatus)
            ? costStatus : "unavailable"
        self.costProvenance = LocalSpendProvider.validProvenance(costProvenance)
        self.providers = providers
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let decodedTotal = try? c.decode(Double.self, forKey: .totalUSD)
        let decodedStatus = (try? c.decode(String.self, forKey: .costStatus)) ?? "unavailable"
        let decodedProvenance = try? c.decode(String.self, forKey: .costProvenance)
        let validTotal = decodedTotal.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        let validStatus = ["exact", "partial", "unavailable"].contains(decodedStatus)
        let validOrigin = LocalSpendProvider.validProvenance(decodedProvenance)
        let valid = validTotal != nil && validStatus && (decodedProvenance == nil || validOrigin != nil)
        totalUSD = valid ? (validTotal ?? 0) : 0
        costStatus = valid
            ? decodedStatus : "unavailable"
        costProvenance = valid && decodedStatus != "unavailable" ? validOrigin : nil
        providers = (try? c.decode([String: LocalSpendProvider].self, forKey: .providers)) ?? [:]
    }

    enum CodingKeys: String, CodingKey { case totalUSD, costStatus, costProvenance, providers }
}

struct LocalSpend: Decodable, Equatable {
    var actual = LocalSpendTotal()
    var estimated = LocalSpendTotal()
    var subscription = LocalSpendTotal()
    var subscriptionActual = LocalSpendTotal()
    var legacy: LocalSpendTotal?

    init(totalUSD: Double = 0, costStatus: String = "unavailable",
         providers: [String: LocalSpendProvider] = [:]) {
        legacy = LocalSpendTotal(totalUSD: totalUSD, costStatus: costStatus, providers: providers)
    }

    init(actual: LocalSpendTotal = LocalSpendTotal(),
         estimated: LocalSpendTotal = LocalSpendTotal(),
         subscription: LocalSpendTotal = LocalSpendTotal(),
         subscriptionActual: LocalSpendTotal = LocalSpendTotal()) {
        self.actual = Self.withDefaultProvenance(actual, value: "actual")
        self.estimated = Self.withDefaultProvenance(estimated, value: "estimated")
        self.subscription = Self.withDefaultProvenance(subscription, value: "estimated")
        self.subscriptionActual = Self.withDefaultProvenance(subscriptionActual, value: "actual")
        legacy = nil
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let hasSeparateTotals = c.contains(.actual) || c.contains(.estimated) || c.contains(.subscription) || c.contains(.subscriptionActual)
        if hasSeparateTotals {
            actual = Self.withDefaultProvenance(
                (try? c.decode(LocalSpendTotal.self, forKey: .actual)) ?? LocalSpendTotal(),
                value: "actual")
            estimated = Self.withDefaultProvenance(
                (try? c.decode(LocalSpendTotal.self, forKey: .estimated)) ?? LocalSpendTotal(),
                value: "estimated")
            subscription = Self.withDefaultProvenance(
                (try? c.decode(LocalSpendTotal.self, forKey: .subscription)) ?? LocalSpendTotal(),
                value: "estimated")
            subscriptionActual = Self.withDefaultProvenance(
                (try? c.decode(LocalSpendTotal.self, forKey: .subscriptionActual)) ?? LocalSpendTotal(),
                value: "actual")
            legacy = nil
        } else if c.contains(.totalUSD) || c.contains(.costStatus) || c.contains(.providers) {
            legacy = try? LocalSpendTotal(from: decoder)
        } else {
            legacy = nil
        }
    }

    enum CodingKeys: String, CodingKey { case actual, estimated, subscription, subscriptionActual, totalUSD, costStatus, providers }

    private static func withDefaultProvenance(_ total: LocalSpendTotal, value: String) -> LocalSpendTotal {
        guard total.costProvenance == nil,
              total.costStatus == "exact" || total.costStatus == "partial" else { return total }
        return LocalSpendTotal(
            totalUSD: total.totalUSD,
            costStatus: total.costStatus,
            costProvenance: value,
            providers: total.providers)
    }
}

// The per-provider cost numbers the backend already exposed, in the same
// order and with the same sources as FeatureTabs.js `spendProviderRows`:
// Claude/OpenAI organisation usage, OpenRouter credit usage, Mistral vibe
// spend, Muse/Cline local stats, Cursor on-demand spend. Costs are read out
// of the generic details dictionary so no new per-provider contract is needed.
enum SpendRows {
    static func filtered(_ rows: [SpendRow], timeframe: SpendTimeframe, referenceDate: Date = Date()) -> [SpendRow] {
        rows.map { $0.filtered(to: timeframe, referenceDate: referenceDate) }
    }

    static func build(_ providers: [Provider], localSpend: LocalSpend = LocalSpend()) -> [SpendRow] {
        var out: [SpendRow] = []
        let dailyByProvider = dailyByProvider(localSpend)
        for provider in providers {
            let details = provider.costDetails
            let cost: Double
            let note: String
            let currency: String
            switch provider.id {
            case "claude", "openai":
                cost = details.double(paths: [["organizationUsage", "totalCostUSD"], ["org", "totalCostUSD"], ["totalCostUSD"], ["stats", "totalCostUSD"]])
                note = i18n("30d API")
                currency = "USD"
            case "openrouter":
                cost = details.double(paths: [["usageUSD"], ["usage"]])
                note = i18n("all-time")
                currency = "USD"
            case "mistral":
                cost = details.double(paths: [["vibe", "totalCost"], ["vibeTotalCost"], ["totalCost"]])
                note = i18n("vibe CLI")
                currency = "USD"
            case "muse":
                cost = details.double(paths: [["stats", "totalCostUSD"], ["totalCostUSD"]])
                note = i18n("local est.")
                currency = details.string(paths: [["stats", "currency"], ["currency"]], fallback: "USD")
            case "cline":
                cost = details.double(paths: [["stats", "totalCostUSD"], ["totalCostUSD"]])
                note = i18n("local")
                currency = "USD"
            case "cursor":
                cost = details.double(paths: [["onDemandUsed"], ["onDemandSpendUSD"], ["onDemand"]])
                note = i18n("on-demand")
                currency = "USD"
            case "opencode":
                cost = details.double(paths: [["stats", "totalCostUSD"], ["totalCostUSD"]])
                note = i18n("local sessions")
                currency = "USD"
            default:
                continue
            }
            guard cost > 0 else { continue }
            let history = dailyByProvider[provider.id]
            out.append(SpendRow(
                provider: provider,
                cost: cost,
                currency: currency,
                note: note,
                dailyCost: history?.cost ?? [],
                dailyTokens: history?.tokens ?? []))
        }
        if let legacy = localSpend.legacy {
            appendLocal(legacy, label: i18n("Local sessions"), provenance: nil, to: &out)
        } else {
            appendLocalProviders(actual: localSpend.actual, estimated: localSpend.estimated, suppressOpenCode: providers.contains(where: { $0.id == "opencode" }), to: &out)
            appendPlanProviders(subscription: localSpend.subscription, subscriptionActual: localSpend.subscriptionActual, to: &out)
        }
        return out.sorted { $0.cost > $1.cost }
    }

    /// Per-day cost and tokens for every provider that produced session rows,
    /// merged across the four billing groups. Provider-agnostic: a provider
    /// shows up here because it has sessions, not because it was named.
    private static func dailyByProvider(
        _ localSpend: LocalSpend
    ) -> [String: (cost: [DailyCostPoint], tokens: [DailyPoint])] {
        var cost: [String: [DailyCostPoint]] = [:]
        var tokens: [String: [DailyPoint]] = [:]
        for group in [localSpend.actual, localSpend.estimated, localSpend.subscription, localSpend.subscriptionActual] {
            for (key, entry) in group.providers {
                let providerKey = key.split(separator: "::", maxSplits: 1).map(String.init).first ?? key
                if !entry.dailyUSD.isEmpty {
                    cost[providerKey, default: []].append(contentsOf: entry.dailyUSD)
                }
                if !entry.dailyTokens.isEmpty {
                    tokens[providerKey, default: []].append(contentsOf: entry.dailyTokens)
                }
            }
        }
        var out: [String: (cost: [DailyCostPoint], tokens: [DailyPoint])] = [:]
        for key in Set(cost.keys).union(tokens.keys) {
            out[key] = (mergeDaily(cost[key] ?? []), mergeDailyTokens(tokens[key] ?? []))
        }
        return out
    }

    static func totalUSD(_ rows: [SpendRow]) -> Double {
        rows.filter { $0.provider != nil && $0.currency == "USD" }.reduce(0) { $0 + $1.cost }
    }

    static func meteredTotalUSD(_ rows: [SpendRow]) -> Double {
        rows.filter { $0.billing != "subscription" && $0.currency == "USD" && $0.cost > 0 && $0.cost.isFinite }.reduce(0) { $0 + $1.cost }
    }

    static func planTotalUSD(_ rows: [SpendRow]) -> Double {
        rows.filter { $0.billing == "subscription" && $0.currency == "USD" && $0.cost > 0 && $0.cost.isFinite }.reduce(0) { $0 + $1.cost }
    }

    static func allTotalUSD(_ rows: [SpendRow]) -> Double {
        rows.filter { $0.currency == "USD" && $0.cost > 0 && $0.cost.isFinite }.reduce(0) { $0 + $1.cost }
    }

    private static func appendLocal(
        _ total: LocalSpendTotal,
        label: String,
        provenance: String?,
        to rows: inout [SpendRow]) {
        guard total.costProvenance == provenance,
              total.costStatus == "exact" || total.costStatus == "partial",
              total.totalUSD > 0,
              total.totalUSD.isFinite else { return }
        rows.append(SpendRow(
            localCost: total.totalUSD,
            label: label,
            provenance: provenance,
            costStatus: total.costStatus))
    }

    private static func appendLocalProviders(
        actual: LocalSpendTotal,
        estimated: LocalSpendTotal,
        suppressOpenCode: Bool,
        to rows: inout [SpendRow]) {
        let sources = Set(actual.providers.keys.compactMap(localSourceKey))
            .union(estimated.providers.keys.compactMap(localSourceKey))
            .filter { !$0.isEmpty }
            .sorted()
        for source in sources {
            let actualEntry = validLocalProvider(localProvider(source, in: actual.providers))
            let estimatedEntry = validLocalProvider(localProvider(source, in: estimated.providers))
            guard actualEntry != nil || estimatedEntry != nil else { continue }

            let actualUSD = actualEntry?.cost ?? 0
            let estimatedUSD = estimatedEntry?.cost ?? 0
            let sourceMetadata = actualEntry?.source ?? estimatedEntry?.source ?? ""
            let identityParts = source.split(separator: "::", maxSplits: 1).map(String.init)
            let providerKey = identityParts.first ?? source
            let localSource = sourceMetadata.isEmpty ? providerKey : sourceMetadata
            if suppressOpenCode && localSource == "opencode" { continue }
            let provenance = actualUSD > 0 && estimatedUSD > 0
                ? "mixed" : actualUSD > 0 ? "actual" : "estimated"
            let costStatus = actualEntry?.status == "partial" || estimatedEntry?.status == "partial"
                ? "partial" : "exact"
            let viaSource = sourceMetadata.isEmpty ? nil : sourceMetadata
            rows.append(SpendRow(
                localSource: localSource,
                actualUSD: actualUSD,
                estimatedUSD: estimatedUSD,
                provenance: provenance,
                costStatus: costStatus,
                billingProvider: localSource == "opencode" && viaSource != nil ? providerKey : nil,
                identity: source,
                viaSource: viaSource,
                dailyCost: mergeDaily(actualEntry?.daily ?? [], estimatedEntry?.daily ?? []),
                dailyTokens: mergeDailyTokens(actualEntry?.dailyTokens ?? [], estimatedEntry?.dailyTokens ?? [])))
        }
    }

    private static func appendPlanProviders(
        subscription: LocalSpendTotal,
        subscriptionActual: LocalSpendTotal,
        to rows: inout [SpendRow]) {
        let sources = Set(subscription.providers.keys.compactMap(localSourceKey))
            .union(subscriptionActual.providers.keys.compactMap(localSourceKey))
            .filter { !$0.isEmpty }
            .sorted()
        for source in sources {
            let estimatedEntry = validLocalProvider(localProvider(source, in: subscription.providers))
            let actualEntry = validLocalProvider(localProvider(source, in: subscriptionActual.providers))
            guard estimatedEntry != nil || actualEntry != nil else { continue }

            let estimatedUSD = estimatedEntry?.cost ?? 0
            let actualUSD = actualEntry?.cost ?? 0
            guard (estimatedUSD + actualUSD) > 0 else { continue }

            let sourceMetadata = estimatedEntry?.source ?? actualEntry?.source ?? ""
            let identityParts = source.split(separator: "::", maxSplits: 1).map(String.init)
            let providerKey = identityParts.first ?? source
            let localSource = sourceMetadata.isEmpty ? providerKey : sourceMetadata
            let costStatus = (estimatedEntry?.status == "partial" || actualEntry?.status == "partial")
                ? "partial" : "exact"
            let viaSource = sourceMetadata.isEmpty ? nil : sourceMetadata
            rows.append(SpendRow(
                localSource: localSource,
                actualUSD: actualUSD,
                estimatedUSD: estimatedUSD,
                provenance: "estimated",
                costStatus: costStatus,
                billingProvider: localSource == "opencode" && viaSource != nil ? providerKey : nil,
                identity: source,
                viaSource: viaSource,
                billing: "subscription",
                dailyCost: mergeDaily(actualEntry?.daily ?? [], estimatedEntry?.daily ?? []),
                dailyTokens: mergeDailyTokens(actualEntry?.dailyTokens ?? [], estimatedEntry?.dailyTokens ?? [])))
        }
    }

    private static func validLocalProvider(
        _ entry: LocalSpendProvider?
    ) -> (cost: Double, status: String, source: String?, daily: [DailyCostPoint], dailyTokens: [DailyPoint])? {
        guard let entry,
              entry.costStatus == "exact" || entry.costStatus == "partial",
              entry.costUSD > 0,
              entry.costUSD.isFinite else { return nil }
        return (entry.costUSD, entry.costStatus, entry.source, entry.dailyUSD, entry.dailyTokens)
    }

    /// Sum per-day series into one sorted series — a row can be fed by both
    /// the actual and estimated halves of the same provider.
    static func mergeDaily(_ series: [DailyCostPoint]...) -> [DailyCostPoint] {
        var totals: [String: Double] = [:]
        for one in series {
            for point in one where !point.date.isEmpty {
                totals[point.date, default: 0] += point.usd
            }
        }
        return totals.keys.sorted().map { DailyCostPoint(date: $0, usd: totals[$0] ?? 0) }
    }

    static func mergeDailyTokens(_ series: [DailyPoint]...) -> [DailyPoint] {
        var totals: [String: Double] = [:]
        for one in series {
            for point in one where !point.date.isEmpty {
                totals[point.date, default: 0] += point.total
            }
        }
        return totals.keys.sorted().map { DailyPoint(date: $0, total: totals[$0] ?? 0) }
    }

    private static func localProvider(
        _ source: String,
        in providers: [String: LocalSpendProvider]) -> LocalSpendProvider? {
        providers.first { localSourceKey($0.key) == source }?.value
    }

    private static func localSourceKey(_ source: String) -> String {
        source.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
    }
}

// ── Local sessions ───────────────────────────────────────────────────────
// `get-ai-usage --sessions`'s own envelope: a merged, newest-first, redacted
// list of local agent sessions. Decoding is lenient field-by-field, the same
// pattern as `Envelope` above, so an addition on the backend side never
// breaks this app.

struct SessionSource: Decodable, Identifiable, Equatable {
    var id = ""
    var label = ""

    init(id: String, label: String) {
        self.id = id
        self.label = label
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? ""
        let decodedLabel = (try? c.decode(String.self, forKey: .label)) ?? ""
        label = decodedLabel.isEmpty ? id : decodedLabel
    }

    enum CodingKeys: String, CodingKey { case id, label }
}

struct LocalSessions: Decodable {
    var updatedAt: Double
    var sessions: [LocalSession]
    var sources: [SessionSource]
    var total: Int
    var offset: Int
    var limit: Int?
    var hasMore: Bool
    var totalExact: Bool
    var cacheStatus: String
    var cacheAgeSeconds: Int?
    var refreshStatus: String
    var removedSourceCount: Int

    enum CodingKeys: String, CodingKey {
        case updatedAt, sessions, sources, total, offset, limit, hasMore, totalExact
        case cacheStatus, cacheAgeSeconds, refreshStatus, removedSourceCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        updatedAt = (try? c.decode(Double.self, forKey: .updatedAt)) ?? 0
        sessions = (try? c.decode([LocalSession].self, forKey: .sessions)) ?? []
        sources = ((try? c.decode([SessionSource].self, forKey: .sources)) ?? [])
            .filter { !$0.id.isEmpty }
        total = (try? c.decode(Int.self, forKey: .total)) ?? sessions.count
        offset = (try? c.decode(Int.self, forKey: .offset)) ?? 0
        limit = try? c.decode(Int.self, forKey: .limit)
        hasMore = (try? c.decode(Bool.self, forKey: .hasMore)) ?? false
        totalExact = (try? c.decode(Bool.self, forKey: .totalExact)) ?? false
        cacheStatus = (try? c.decode(String.self, forKey: .cacheStatus)) ?? "unknown"
        cacheAgeSeconds = try? c.decode(Int.self, forKey: .cacheAgeSeconds)
        refreshStatus = (try? c.decode(String.self, forKey: .refreshStatus)) ?? "not-run"
        removedSourceCount = (try? c.decode(Int.self, forKey: .removedSourceCount)) ?? 0
    }
}

struct CostBreakdown: Decodable, Equatable {
    let actualUSD: Double
    let estimatedUSD: Double

    init(actualUSD: Double, estimatedUSD: Double) {
        self.actualUSD = actualUSD
        self.estimatedUSD = estimatedUSD
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let actual = try c.decode(Double.self, forKey: .actualUSD)
        let estimated = try c.decode(Double.self, forKey: .estimatedUSD)
        guard actual.isFinite, actual >= 0, estimated.isFinite, estimated >= 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .actualUSD,
                in: c,
                debugDescription: "cost breakdown values must be finite and non-negative")
        }
        actualUSD = actual
        estimatedUSD = estimated
    }

    /// JSON decimal values can differ by binary floating-point roundoff. The
    /// tolerance is relative at 1e-9 with a 1e-12 USD absolute floor.
    func sums(to total: Double) -> Bool {
        let sum = actualUSD + estimatedUSD
        let scale = max(abs(sum), abs(total))
        return abs(sum - total) <= max(1e-12, scale * 1e-9)
    }

    enum CodingKeys: String, CodingKey { case actualUSD, estimatedUSD }
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
    var costUSD: Double?
    var costStatus: String
    var costProvenance: String?
    var costBreakdown: CostBreakdown?
    var costBilling: String?

    enum CodingKeys: String, CodingKey {
        case provider, title, sessionName, state, lastActivityAt, detail, openKey, fullTitle, costUSD, costStatus, costProvenance, costBreakdown, costBilling
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
        let decodedCost = try? c.decode(Double.self, forKey: .costUSD)
        let decodedStatus = (try? c.decode(String.self, forKey: .costStatus)) ?? "unavailable"
        let decodedProvenance = try? c.decode(String.self, forKey: .costProvenance)
        let validCost = decodedCost.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        let validStatus = ["exact", "partial", "unavailable"].contains(decodedStatus)
        let validOrigin = LocalSpendProvider.validProvenance(decodedProvenance)
        let valid = validCost != nil && validStatus && (decodedProvenance == nil || validOrigin != nil)
        costUSD = valid && decodedStatus != "unavailable" ? validCost : nil
        costStatus = valid ? decodedStatus : "unavailable"
        costProvenance = valid && decodedStatus != "unavailable" ? validOrigin : nil
        costBilling = try? c.decode(String.self, forKey: .costBilling)
        if costProvenance == "mixed",
           let cost = costUSD,
           let breakdown = try? c.decode(CostBreakdown.self, forKey: .costBreakdown),
           breakdown.sums(to: cost) {
            costBreakdown = breakdown
        } else {
            costBreakdown = nil
        }
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
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
            let converted = number.doubleValue
            return converted.isFinite && converted >= 0 ? converted : nil
        }
        if let number = value as? Double { return number.isFinite && number >= 0 ? number : nil }
        if let number = value as? Int { return number >= 0 ? Double(number) : nil }
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

    init(date: String = "", total: Double = 0) {
        self.date = date
        self.total = total.isFinite && total >= 0 ? total : 0
    }

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
