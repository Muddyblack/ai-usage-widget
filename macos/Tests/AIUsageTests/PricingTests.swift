import Foundation
import XCTest

@testable import AIUsage

final class PricingContractTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ai-usage-pricing-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func script(json: String, exitCode: Int = 0) throws -> URL {
        let url = directory.appendingPathComponent("backend.sh")
        let body = """
        #!/bin/sh
        if [ "$1" != "--refresh-pricing" ]; then exit 9; fi
        printf '%s\\n' '\(json)'
        exit \(exitCode)
        """
        try Data(body.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    func testRefreshPricingForwardsTheExactArgumentAndDecodesSuccess() throws {
        let backend = try script(json: #"{"ok":true,"status":"refreshed","fetchedAt":1785000000,"error":""}"#)
        let result = try Backend.refreshPricing(using: backend)

        XCTAssertEqual(Backend.refreshPricingArguments, ["--refresh-pricing"])
        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.status, "refreshed")
        XCTAssertEqual(result.fetchedAt, 1785000000)
        XCTAssertEqual(result.error, "")
    }

    func testStaleGoodResultSurvivesARefreshFailureExit() throws {
        let backend = try script(
            json: #"{"ok":true,"status":"stale-good","fetchedAt":1784000000,"error":"HTTP 503"}"#,
            exitCode: 1)
        let result = try Backend.refreshPricing(using: backend)

        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.status, "stale-good")
        XCTAssertEqual(result.error, "HTTP 503")
    }

    func testNoCacheResultRemainsDistinctFromStaleGood() throws {
        let backend = try script(
            json: #"{"ok":false,"status":"no-cache","fetchedAt":0,"error":"No usable pricing rates"}"#,
            exitCode: 1)
        let result = try Backend.refreshPricing(using: backend)

        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.status, "no-cache")
        XCTAssertEqual(result.fetchedAt, 0)
        XCTAssertEqual(result.error, "No usable pricing rates")
    }

    func testStructuredSessionCostsDecodeWithoutASingularModel() throws {
        let data = Data(
            #"""
            {"sessions":[
                {"provider":"openai","title":"multi","detail":"model-a + model-b","costUSD":0.1234,"costStatus":"exact"},
                {"provider":"claude","title":"partial","costUSD":1.25,"costStatus":"partial","costProvenance":"estimated"},
                {"provider":"muse","title":"unknown","costStatus":"unavailable"}
            ]}
            """#.utf8)
        let sessions = try JSONDecoder().decode(LocalSessions.self, from: data).sessions

        XCTAssertEqual(sessions.map(\.costStatus), ["exact", "partial", "unavailable"])
        XCTAssertEqual(sessions[0].costUSD, 0.1234)
        XCTAssertEqual(SessionCostPresentation.text(costUSD: sessions[0].costUSD, status: sessions[0].costStatus), "Cost: $0.1234 (exact)")
        XCTAssertEqual(SessionCostPresentation.text(costUSD: sessions[1].costUSD, status: sessions[1].costStatus), "Cost: $1.2500 (partial)")
        XCTAssertEqual(SessionCostPresentation.text(costUSD: sessions[2].costUSD, status: sessions[2].costStatus), "Cost unavailable")
    }

    func testSessionCostPresentationLabelsActualEstimatedAndMixedCosts() {
        XCTAssertEqual(
            SessionCostPresentation.text(
                costUSD: 0.42,
                status: "exact",
                provenance: "actual"),
            "Actual cost: $0.4200 (exact)")
        XCTAssertEqual(
            SessionCostPresentation.text(
                costUSD: 0.2,
                status: "partial",
                provenance: "estimated"),
            "Calculated estimate: $0.2000 (partial)")
        XCTAssertEqual(
            SessionCostPresentation.text(
                costUSD: 0.62,
                status: "exact",
                provenance: "mixed",
                breakdown: CostBreakdown(actualUSD: 0.42, estimatedUSD: 0.2)),
            "Actual $0.4200 + estimate $0.2000 (exact)")
        XCTAssertEqual(
            SessionCostPresentation.text(
                costUSD: 0.62,
                status: "exact",
                provenance: "mixed"),
            "Cost unavailable")
    }

    func testSessionCostPresentationLabelsSubscriptionCosts() {
        XCTAssertEqual(
            SessionCostPresentation.text(
                costUSD: 0.1234,
                status: "exact",
                billing: "subscription"),
            "Covered by plan · $0.1234 on API")
        XCTAssertEqual(
            SessionCostPresentation.text(
                costUSD: 1.25,
                status: "partial",
                billing: "subscription"),
            "Covered by plan · ~$1.2500 on API")
    }

    func testSessionCostDecodesCostBillingMode() throws {
        let data = Data(
            #"""
            {"sessions":[
                {"provider":"opencode","title":"test","costUSD":0.5,"costStatus":"exact","costBilling":"subscription"}
            ]}
            """#.utf8)
        let sessions = try JSONDecoder().decode(LocalSessions.self, from: data).sessions
        XCTAssertEqual(sessions[0].costBilling, "subscription")
    }

    func testSessionCostProvenanceAndBreakdownAreOptionalAndMalformedDataIsUnavailable() throws {
        let data = Data(
            #"""
            {"sessions":[
                {"provider":"legacy","title":"legacy","costUSD":0.5,"costStatus":"exact"},
                {"provider":"bad","title":"bad","costUSD":0.5,"costStatus":"exact","costProvenance":"other","costBreakdown":{"actualUSD":0.2,"estimatedUSD":0.3}},
                {"provider":"mixed","title":"mixed","costUSD":0.5,"costStatus":"partial","costProvenance":"mixed","costBreakdown":{"actualUSD":0.2,"estimatedUSD":"bad"}}
            ]}
            """#.utf8)
        let sessions = try JSONDecoder().decode(LocalSessions.self, from: data).sessions

        XCTAssertNil(sessions[0].costProvenance)
        XCTAssertNil(sessions[0].costBreakdown)
        XCTAssertNil(sessions[1].costProvenance)
        XCTAssertNil(sessions[1].costBreakdown)
        XCTAssertEqual(sessions[1].costStatus, "unavailable")
        XCTAssertEqual(sessions[2].costProvenance, "mixed")
        XCTAssertNil(sessions[2].costBreakdown)
        XCTAssertEqual(
            SessionCostPresentation.text(
                costUSD: sessions[2].costUSD,
                status: sessions[2].costStatus,
                provenance: sessions[2].costProvenance,
                breakdown: sessions[2].costBreakdown),
            "Cost unavailable")
    }

    func testNegativeSessionCostFailsClosed() throws {
        let data = Data(
            #"{"sessions":[{"provider":"bad","title":"negative","costUSD":-0.5,"costStatus":"exact","costProvenance":"actual"}]}"#.utf8)
        let session = try JSONDecoder().decode(LocalSessions.self, from: data).sessions[0]

        XCTAssertNil(session.costUSD)
        XCTAssertEqual(session.costStatus, "unavailable")
        XCTAssertNil(session.costProvenance)
    }

    func testMixedBreakdownPreservesFiniteZeroComponent() throws {
        let data = Data(
            #"{"sessions":[{"provider":"mixed","title":"zero","costUSD":0.2,"costStatus":"exact","costProvenance":"mixed","costBreakdown":{"actualUSD":0,"estimatedUSD":0.2}}]}"#.utf8)
        let session = try JSONDecoder().decode(LocalSessions.self, from: data).sessions[0]

        XCTAssertEqual(session.costUSD, 0.2)
        XCTAssertEqual(session.costStatus, "exact")
        XCTAssertEqual(session.costBreakdown?.actualUSD, 0)
        XCTAssertEqual(session.costBreakdown?.estimatedUSD, 0.2)
    }

    func testMismatchedMixedBreakdownFailsClosed() throws {
        let data = Data(
            #"{"sessions":[{"provider":"mixed","title":"mismatch","costUSD":0.5,"costStatus":"exact","costProvenance":"mixed","costBreakdown":{"actualUSD":0.2,"estimatedUSD":0.2}}]}"#.utf8)
        let session = try JSONDecoder().decode(LocalSessions.self, from: data).sessions[0]

        XCTAssertEqual(session.costUSD, 0.5)
        XCTAssertEqual(session.costStatus, "exact")
        XCTAssertEqual(session.costProvenance, "mixed")
        XCTAssertNil(session.costBreakdown)
    }
}

@MainActor
final class AppModelPricingTests: XCTestCase {
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0

        func increment() {
            lock.lock()
            count += 1
            lock.unlock()
        }

        var value: Int {
            lock.lock()
            defer { lock.unlock() }
            return count
        }
    }

    private func model(
        pricing: @escaping () throws -> PricingRefreshResult,
        snapshot: @escaping () throws -> Envelope = { Envelope() }
    ) -> AppModel {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ai-usage-model-\(UUID().uuidString).json")
        return AppModel(
            settings: SettingsStore(url: url),
            snapshotOperation: snapshot,
            pricingRefreshOperation: pricing)
    }

    func testSuccessStateUsesTheBackendResultAndKeepsFetchedAt() {
        let model = model {
            PricingRefreshResult(ok: true, status: "refreshed", fetchedAt: 1785000000)
        }

        model.applyPricingResult(PricingRefreshResult(
            ok: true, status: "refreshed", fetchedAt: 1785000000))

        XCTAssertFalse(model.pricingLoading)
        XCTAssertEqual(model.pricingStatus, "refreshed")
        XCTAssertEqual(model.pricingError, "")
        XCTAssertEqual(model.pricingFetchedAt, Date(timeIntervalSince1970: 1785000000))
    }

    func testStaleGoodStateKeepsUsableRatesAndErrorVisible() {
        let model = model { PricingRefreshResult() }
        model.applyPricingResult(PricingRefreshResult(
            ok: true, status: "stale-good", fetchedAt: 1784000000, error: "HTTP 503"))

        XCTAssertEqual(model.pricingStatus, "stale-good")
        XCTAssertEqual(model.pricingError, "HTTP 503")
        XCTAssertNotNil(model.pricingFetchedAt)
    }

    func testHardFailureUsesNoCacheState() {
        let model = model { PricingRefreshResult() }
        struct BackendError: LocalizedError {
            var errorDescription: String? { "backend unavailable" }
        }

        model.applyPricingFailure(BackendError())

        XCTAssertEqual(model.pricingStatus, "no-cache")
        XCTAssertEqual(model.pricingError, "backend unavailable")
        XCTAssertFalse(model.pricingLoading)
        XCTAssertNil(model.pricingFetchedAt)
    }

    func testRepeatedRefreshClicksLaunchOnlyOneBackendOperation() async throws {
        let counter = Counter()
        let model = model {
            counter.increment()
            return PricingRefreshResult(ok: false, status: "no-cache", error: "unavailable")
        }

        model.refreshPricing()
        model.refreshPricing()
        XCTAssertTrue(model.pricingLoading)

        let completed = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in !model.pricingLoading },
            object: nil)
        await fulfillment(of: [completed], timeout: 2)
        XCTAssertEqual(counter.value, 1)
        XCTAssertFalse(model.pricingLoading)
        XCTAssertEqual(model.pricingStatus, "no-cache")
    }
}
