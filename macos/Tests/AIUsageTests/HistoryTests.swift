import XCTest

@testable import AIUsage

/// The usage history: reading the shared file's format, and drawing a quota
/// that emptied while nobody was looking.
final class HistoryTests: XCTestCase {
    private let hour: Double = 3_600_000

    private func series(_ pairs: [(Double, Double)]) -> [SeriesPoint] {
        pairs.map { SeriesPoint(t: $0.0, v: $0.1) }
    }

    // ── withResets ───────────────────────────────────────────────────────

    func testAResetInsideAGapDropsAtTheResetRatherThanAtWakeUp() {
        // Two samples four hours apart with a reset between them. Joined
        // straight, the curve would slope down across the whole gap and put
        // the drop at the second sample — hours of usage that never happened.
        let points = series([(0, 80), (4 * hour, 20)])
        let out = HistoryStore.withResets(
            points, resetAtMs: 2 * hour, periodMs: 5 * hour, minT: -hour, maxT: 4 * hour)

        XCTAssertEqual(out.count, 4)
        XCTAssertEqual(out[0].v, 80)
        XCTAssertEqual(out[1].t, 2 * hour - 1)
        XCTAssertEqual(out[1].v, 80, "the value is held right up to the instant")
        XCTAssertEqual(out[2].t, 2 * hour)
        XCTAssertEqual(out[2].v, 0, "and drops to nothing at it")
        XCTAssertEqual(out[3].v, 20)
    }

    func testSeveralResetsInOneLongGapAllDropFromZero() throws {
        // A machine asleep over a weekend: the held value after the first
        // replayed reset is zero, not the last real sample.
        let points = series([(0, 90), (12 * hour, 15)])
        let out = HistoryStore.withResets(
            points, resetAtMs: 10 * hour, periodMs: 5 * hour, minT: -hour, maxT: 12 * hour)

        XCTAssertEqual(out.first(where: { $0.t == 5 * hour })?.v, 0, "5 h falls inside the gap")
        XCTAssertEqual(out.first(where: { $0.t == 10 * hour })?.v, 0, "and so does 10 h")

        let beforeSecondDrop = try XCTUnwrap(out.first(where: { $0.t == 10 * hour - 1 }))
        XCTAssertEqual(
            beforeSecondDrop.v, 0,
            "the value held into the second reset is what the curve is at — zero after the first — not 90")
    }

    func testAResetNewerThanTheLastSampleStillEmptiesTheWindow() {
        let points = series([(0, 70), (hour, 75)])
        let out = HistoryStore.withResets(
            points, resetAtMs: 3 * hour, periodMs: 5 * hour, minT: -hour, maxT: 4 * hour)
        XCTAssertEqual(out.last?.v, 0, "the window emptied even though nothing was recorded")
        XCTAssertEqual(out.last?.t, 3 * hour)
    }

    func testNothingIsInventedWithoutAKnownPeriod() {
        let points = series([(0, 80), (4 * hour, 20)])
        XCTAssertEqual(
            HistoryStore.withResets(points, resetAtMs: 0, periodMs: 5 * hour, minT: 0, maxT: 4 * hour).count, 2)
        XCTAssertEqual(
            HistoryStore.withResets(points, resetAtMs: 2 * hour, periodMs: 0, minT: 0, maxT: 4 * hour).count, 2)
        XCTAssertTrue(
            HistoryStore.withResets([], resetAtMs: 2 * hour, periodMs: hour, minT: 0, maxT: hour).isEmpty)
    }

    func testAResetBeforeTheFirstSampleIsNotReplayed() {
        // It is already reflected in that first sample; drawing it would put a
        // cliff in front of data that never saw one.
        let points = series([(3 * hour, 30), (4 * hour, 40)])
        let out = HistoryStore.withResets(
            points, resetAtMs: 2 * hour, periodMs: 5 * hour, minT: 0, maxT: 4 * hour)
        XCTAssertEqual(out.count, 2)
    }

    // ── The shared file's format ─────────────────────────────────────────

    func testParsesWhatHistoryIoReturns() {
        let data = Data(#"{"ok":true,"data":[{"t":2000,"s":50,"w":60},{"t":1000,"s":10}]}"#.utf8)
        let points = HistoryStore.parse(data)
        XCTAssertEqual(points.map(\.t), [1000, 2000], "read back in time order whatever order they were written in")
        XCTAssertEqual(points[0].values["s"], 10)
        XCTAssertEqual(points[1].values["w"], 60)
    }

    func testLegacyWeeklyOnlyPointsAreMigrated() {
        // Points written before the series had names carried the value as `v`.
        let points = HistoryStore.parse(Data(#"{"ok":true,"data":[{"t":1000,"v":42}]}"#.utf8))
        XCTAssertEqual(points.first?.values["w"], 42)
        XCTAssertNil(points.first?.values["v"])
    }

    func testUnusablePointsAreDroppedRatherThanPoisoningTheRange() {
        // The file is written by whichever frontend ran last and can be edited
        // by hand. One point with no usable timestamp must not drag the whole
        // chart's range with it.
        let data = Data(
            #"{"ok":true,"data":[{"t":null,"s":1},{"s":2},{"t":"nonsense","s":3},{"t":"1500","s":4},{"t":2000,"s":5}]}"#
                .utf8)
        let points = HistoryStore.parse(data)
        XCTAssertEqual(points.map(\.t), [1500, 2000], "a plain decimal string is a timestamp; nothing else is")
    }

    func testNothingIsReadFromAFailedCall() {
        XCTAssertTrue(HistoryStore.parse(Data(#"{"ok":false,"error":"could not lock"}"#.utf8)).isEmpty)
        XCTAssertTrue(HistoryStore.parse(Data("not json".utf8)).isEmpty)
    }

    func testEncodesAnArrayOfPoints() throws {
        let payload = HistoryStore.encode([HistoryPoint(t: 1000, values: ["s": 50])])
        let rows = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [[String: Any]])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0]["t"] as? Double, 1000)
        XCTAssertEqual(rows[0]["s"] as? Double, 50)
    }
}
