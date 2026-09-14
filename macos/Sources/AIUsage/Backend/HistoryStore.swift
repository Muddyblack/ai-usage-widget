import Combine
import Foundation

/// One point of one series, ready to plot.
struct SeriesPoint: Identifiable, Equatable {
    /// Epoch milliseconds, and the identity: a series has one value per instant.
    let t: Double
    let v: Double
    var id: Double { t }
    var date: Date { Date(timeIntervalSince1970: t / 1000) }
}

/// One sample of every series, at one instant.
struct HistoryPoint: Equatable {
    /// Epoch milliseconds.
    var t: Double
    var values: [String: Double]

    func value(_ key: String, fallback: String? = nil) -> Double? {
        if let value = values[key] { return value }
        if let fallback { return values[fallback] }
        return nil
    }
}

/// The usage history every frontend of this widget shares.
///
/// The file itself is never touched from here. `history-io` in the backend owns
/// every access to it: it takes an flock, unions the new samples into whatever
/// is on disk and replaces the file by rename, so two frontends running at once
/// converge instead of clobbering each other. This asks it to do that and keeps
/// the merged series it hands back.
@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var points: [HistoryPoint] = []

    /// Samples taken but not yet merged in. A save whose lock could not be
    /// taken is not an error to shrug off — the merge is a read-modify-write,
    /// so going ahead without the lock would drop the other frontend's points.
    /// The batch is kept and offered again on the next poll.
    private var pending: [HistoryPoint] = []
    private var saving = false

    /// Read the stored series without leaving the caller's turn — for the
    /// diagnostic modes, which have no run loop to come back to.
    func loadSynchronously() {
        let loaded = Self.parse(Self.call("autoload"))
        if !loaded.isEmpty { points = loaded }
    }

    func load() {
        Task.detached(priority: .utility) {
            let loaded = Self.parse(Self.call("autoload"))
            await MainActor.run { if !loaded.isEmpty { self.points = loaded } }
        }
    }

    /// Take one sample of everything the providers reported this poll.
    func record(_ providers: [Provider], at date: Date = Date()) {
        var values: [String: Double] = [:]
        for provider in providers {
            for (key, value) in provider.historyValues { values[key] = value }
        }
        guard !values.isEmpty else { return }
        pending.append(HistoryPoint(t: date.timeIntervalSince1970 * 1000, values: values))
        flush()
    }

    private func flush() {
        guard !saving, !pending.isEmpty else { return }
        saving = true
        let batch = pending
        Task.detached(priority: .utility) {
            let payload = Self.encode(batch)
            let response = Self.call("autosave", payload: payload)
            let merged = Self.parse(response)
            let ok = Self.succeeded(response)
            await MainActor.run {
                self.saving = false
                if ok {
                    // Kept only on success: on failure the same batch is
                    // offered again with the next poll's sample.
                    self.pending.removeFirst(min(batch.count, self.pending.count))
                    if !merged.isEmpty { self.points = merged }
                }
            }
        }
    }

    // ── Chart series ─────────────────────────────────────────────────────

    /// One chart window's series, windowed, gap-aware and with known quota
    /// resets replayed.
    func series(for window: ChartWindow, fallbackKey: String? = nil, now: Date = Date()) -> [SeriesPoint] {
        let nowMs = now.timeIntervalSince1970 * 1000
        let minT = nowMs - window.size
        let windowed = points
            .filter { $0.t >= minT && $0.t <= nowMs }
            .compactMap { point -> SeriesPoint? in
                guard let value = point.value(window.key, fallback: fallbackKey) else { return nil }
                return SeriesPoint(t: point.t, v: value)
            }
        guard window.resets else { return windowed }
        return Self.withResets(
            windowed, resetAtMs: window.resetAt * 1000, periodMs: window.periodMs, minT: minT, maxT: nowMs)
    }

    /// A rolling quota empties at a known instant whether or not anything was
    /// recorded then. With the machine asleep — or simply between two polls —
    /// the samples on either side would be joined by one straight line, which
    /// reads as hours of gradual usage that never happened and puts the drop at
    /// wake-up time instead of at the reset.
    ///
    /// So replay the resets that can be derived: `resetAt` is the next one and
    /// `periodMs` how often it repeats, which pins every earlier one in the
    /// visible range. A port of `UsageHistory.withResets`, which the two QML
    /// frontends share; the same history must draw the same curve everywhere.
    nonisolated static func withResets(
        _ series: [SeriesPoint], resetAtMs: Double, periodMs: Double, minT: Double, maxT: Double
    ) -> [SeriesPoint] {
        guard resetAtMs > 0, periodMs > 0, let first = series.first else { return series }

        var instants: [Double] = []
        var instant = resetAtMs
        var guardCount = 0
        while instant > minT && guardCount < 1000 {
            if instant <= maxT && instant > first.t { instants.append(instant) }
            instant -= periodMs
            guardCount += 1
        }
        guard !instants.isEmpty else { return series }
        instants.reverse()

        var out: [SeriesPoint] = []
        var next = 0

        // The held value is whatever the curve is at right now, which after an
        // earlier replayed reset is zero rather than the last real sample — so
        // it is read back off the output. One long gap can span several resets.
        func dropAt(_ instant: Double) {
            guard let last = out.last else { return }
            out.append(SeriesPoint(t: instant - 1, v: last.v))
            out.append(SeriesPoint(t: instant, v: 0))
        }

        for (index, point) in series.enumerated() {
            while index > 0, next < instants.count,
                  instants[next] > series[index - 1].t, instants[next] < point.t {
                dropAt(instants[next])
                next += 1
            }
            out.append(point)
        }

        // A reset newer than the last sample: the window has already emptied
        // even though nothing has been recorded since.
        let lastT = series[series.count - 1].t
        while next < instants.count {
            if instants[next] > lastT { dropAt(instants[next]) }
            next += 1
        }
        return out
    }

    // ── Wire format ──────────────────────────────────────────────────────

    /// `history-io` answers with {"ok":…}; a lock it could not take is a
    /// failure the caller has to keep its batch for.
    nonisolated private static func succeeded(_ data: Data) -> Bool {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return root["ok"] as? Bool ?? false
    }

    nonisolated private static func call(_ command: String, payload: String = "") -> Data {
        (try? Backend.history(command, payload: payload)) ?? Data()
    }

    nonisolated static func encode(_ points: [HistoryPoint]) -> String {
        let array = points.map { point -> [String: Any] in
            var object: [String: Any] = ["t": point.t]
            for (key, value) in point.values { object[key] = value }
            return object
        }
        guard let data = try? JSONSerialization.data(withJSONObject: array) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    /// `{"ok":true,"data":[…]}` from `history-io`, or nothing.
    ///
    /// Read leniently on purpose: the file is written by whichever frontend ran
    /// last and can be edited by hand, so a point with no usable timestamp is
    /// dropped rather than allowed to drag the chart's range to NaN.
    nonisolated static func parse(_ data: Data) -> [HistoryPoint] {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let rows = root["data"] as? [[String: Any]]
        else { return [] }

        return rows.compactMap { row in
            guard let t = number(row["t"]), t.isFinite else { return nil }
            var values: [String: Double] = [:]
            for (key, raw) in row where key != "t" {
                if let value = number(raw), value.isFinite { values[key] = value }
            }
            // Legacy weekly-only points carried the value as `v`.
            if values["w"] == nil, let legacy = values["v"] { values["w"] = legacy }
            values.removeValue(forKey: "v")
            return HistoryPoint(t: t, values: values)
        }
        .sorted { $0.t < $1.t }
    }

    nonisolated private static func number(_ raw: Any?) -> Double? {
        if let value = raw as? Double { return value }
        if let value = raw as? Int { return Double(value) }
        // A timestamp written as a string is read back only when it is a plain
        // decimal — the same guard the JS carries, so that the two
        // implementations agree on every byte of the shared file.
        if let text = raw as? String {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            guard trimmed.range(of: #"^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$"#, options: .regularExpression) != nil
            else { return nil }
            return Double(trimmed)
        }
        return nil
    }
}
