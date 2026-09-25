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
    /// The batch is kept and offered again on the next window.
    private var pending: [HistoryPoint] = []
    private var saving = false

    /// The persistence debounce window, in milliseconds. Samples update the
    /// chart immediately but reach the disk at most once per window, so a poll
    /// that runs every few minutes does not pay for a save every time. Matches
    /// the 5-minute default poll and the other frontends' `historyDebounceMs`.
    private let debounceMs = 300_000

    /// The one save scheduled to close the current window, or nil when none is
    /// open. The guard that keeps the debounce leading-edge: a new sample arms
    /// it only when nothing is already scheduled, so a fast poll coalesces into
    /// one save per window instead of sliding it forever.
    private var debounceWork: DispatchWorkItem?

    /// The chart's ceiling, matching `UsageHistory.DEFAULT_LIMIT` — the shared
    /// file is capped to the same length, so the two frontends agree.
    static let limit = 10_000

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

    /// Take one sample of everything the providers reported this poll. The
    /// chart shows it now; only the write waits for the debounce window.
    func record(_ providers: [Provider], at date: Date = Date()) {
        var values: [String: Double] = [:]
        for provider in providers {
            for (key, value) in provider.historyValues { values[key] = value }
        }
        guard !values.isEmpty else { return }
        let point = HistoryPoint(t: date.timeIntervalSince1970 * 1000, values: values)
        pending.append(point)
        points.append(point)
        points.sort { $0.t < $1.t }
        if points.count > Self.limit { points.removeFirst(points.count - Self.limit) }
        armDebounce()
    }

    /// Schedule the one save that closes the current window. Leading-edge: a
    /// window is armed only when none is open, so samples keep arriving without
    /// pushing the save out forever.
    private func armDebounce() {
        guard debounceWork == nil, !saving, !pending.isEmpty else { return }
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.debounceWork = nil
                self?.flush()
            }
        }
        debounceWork = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + .milliseconds(debounceMs), execute: work)
    }

    private func flush() {
        debounceWork?.cancel()
        debounceWork = nil
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
                    // offered again with the next window's save.
                    self.removePending(batch)
                    if !merged.isEmpty { self.points = Self.union(self.points, merged) }
                }
                // Whether the save landed or not, the next window is armed so
                // a failed batch is offered again — and a successful one is
                // followed by whatever arrived while it was in flight.
                self.armDebounce()
            }
        }
    }

    /// Write everything still unsaved, synchronously, for the moment the app is
    /// going away and no run loop will come back to finish a deferred save.
    func flushSynchronously() {
        debounceWork?.cancel()
        debounceWork = nil
        guard !pending.isEmpty else { return }
        let batch = pending
        let response = Self.call("autosave", payload: Self.encode(batch))
        if Self.succeeded(response) {
            removePending(batch)
            let merged = Self.parse(response)
            if !merged.isEmpty { points = Self.union(points, merged) }
        }
    }

    private func removePending(_ batch: [HistoryPoint]) {
        guard pending.starts(with: batch) else { return }
        pending.removeFirst(batch.count)
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

    /// Combine two series that were recorded independently — the shared file
    /// on disk against whatever this frontend already holds. Points sharing a
    /// timestamp are combined key by key, with `overlay` winning, so a point
    /// holding only `w` and one holding only `cp` end up as one complete
    /// point. Points the other side never recorded are kept as they are.
    ///
    /// Returns a new array, ascending by `t` and trimmed to the cap. A port of
    /// `UsageHistory.union`, which the two QML frontends share; the same
    /// history must merge the same way everywhere.
    nonisolated static func union(_ base: [HistoryPoint], _ overlay: [HistoryPoint], limit: Int = 10_000) -> [HistoryPoint] {
        var byTime: [Double: HistoryPoint] = [:]

        // Both sides fold the same way: a repeated timestamp contributes its
        // keys to the point already there rather than replacing it, so two
        // half-filled points recorded a millisecond apart never cost each
        // other their series.
        func absorb(_ points: [HistoryPoint]) {
            for point in points {
                guard point.t.isFinite else { continue }
                var merged = byTime[point.t] ?? HistoryPoint(t: point.t, values: [:])
                for (key, value) in point.values { merged.values[key] = value }
                byTime[point.t] = merged
            }
        }

        absorb(base)
        absorb(overlay)

        var out = byTime.values.sorted { $0.t < $1.t }
        if out.count > limit { out.removeFirst(out.count - limit) }
        return out
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
