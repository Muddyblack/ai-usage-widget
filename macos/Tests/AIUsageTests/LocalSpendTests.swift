import Foundation
import XCTest

@testable import AIUsage

final class LocalSpendContractTests: XCTestCase {
    private func decode(_ json: String) throws -> Envelope {
        try JSONDecoder().decode(Envelope.self, from: Data(json.utf8))
    }

    func testEnvelopeDecodesSeparateLocalSpendProvenanceTotals() throws {
        let envelope = try decode(
            #"{"localSpend":{"actual":{"totalUSD":12.34,"costStatus":"exact","costProvenance":"actual","providers":{"opencode":{"costUSD":0.42,"costStatus":"exact","costProvenance":"actual"}}},"estimated":{"totalUSD":3.5,"costStatus":"partial","costProvenance":"estimated"}}}"#)

        XCTAssertEqual(envelope.localSpend.actual.totalUSD, 12.34)
        XCTAssertEqual(envelope.localSpend.actual.costStatus, "exact")
        XCTAssertEqual(envelope.localSpend.actual.costProvenance, "actual")
        XCTAssertEqual(envelope.localSpend.actual.providers["opencode"]?.costUSD, 0.42)
        XCTAssertEqual(envelope.localSpend.estimated.totalUSD, 3.5)
        XCTAssertEqual(envelope.localSpend.estimated.costStatus, "partial")
        XCTAssertEqual(envelope.localSpend.estimated.costProvenance, "estimated")
    }

    func testLegacyLocalSpendShapeStillDecodes() throws {
        let legacy = try decode(
            #"{"localSpend":{"totalUSD":12.34,"costStatus":"exact","providers":{"opencode":{"costUSD":0.42,"costStatus":"exact"}}}}"#)

        XCTAssertEqual(legacy.localSpend.legacy?.totalUSD, 12.34)
        XCTAssertEqual(legacy.localSpend.legacy?.costStatus, "exact")
        XCTAssertEqual(legacy.localSpend.legacy?.providers["opencode"]?.costUSD, 0.42)

        let missing = try decode(#"{}"#)
        XCTAssertEqual(missing.localSpend.actual.costStatus, "unavailable")
        XCTAssertEqual(missing.localSpend.estimated.costStatus, "unavailable")
    }

    func testInvalidLocalSpendUsesUnavailableDefaults() throws {
        let envelope = try decode(#"{"localSpend":"not an object"}"#)
        let invalidTotal = try decode(#"{"localSpend":{"actual":{"totalUSD":"12.34","costStatus":"exact","costProvenance":"actual"}}}"#)

        XCTAssertEqual(envelope.localSpend.actual.costStatus, "unavailable")
        XCTAssertEqual(invalidTotal.localSpend.actual.totalUSD, 0)
        XCTAssertEqual(invalidTotal.localSpend.actual.costStatus, "unavailable")
        XCTAssertNil(invalidTotal.localSpend.actual.costProvenance)
    }

    func testMalformedOptionalProvenanceFailsClosedWithoutBreakingDecoding() throws {
        let envelope = try decode(
            #"{"localSpend":{"actual":{"totalUSD":4,"costStatus":"exact","costProvenance":"other"},"estimated":{"totalUSD":"bad","costStatus":"partial","costProvenance":true}}}"#)

        XCTAssertEqual(envelope.localSpend.actual.totalUSD, 0)
        XCTAssertEqual(envelope.localSpend.actual.costStatus, "unavailable")
        XCTAssertNil(envelope.localSpend.actual.costProvenance)
        XCTAssertEqual(envelope.localSpend.estimated.costStatus, "unavailable")
        XCTAssertNil(envelope.localSpend.estimated.costProvenance)
    }

    func testNegativeDecodedAggregateAndProviderCostsFailClosed() throws {
        let envelope = try decode(
            #"{"localSpend":{"actual":{"totalUSD":-1,"costStatus":"exact","providers":{"opencode":{"costUSD":-0.5,"costStatus":"exact"}}},"estimated":{"totalUSD":-2,"costStatus":"partial"}}}"#)

        XCTAssertEqual(envelope.localSpend.actual.totalUSD, 0)
        XCTAssertEqual(envelope.localSpend.actual.costStatus, "unavailable")
        XCTAssertEqual(envelope.localSpend.actual.providers["opencode"]?.costUSD, 0)
        XCTAssertEqual(envelope.localSpend.actual.providers["opencode"]?.costStatus, "unavailable")
        XCTAssertEqual(envelope.localSpend.estimated.totalUSD, 0)
        XCTAssertEqual(envelope.localSpend.estimated.costStatus, "unavailable")
    }

    func testSeparateTotalsWithoutProviderRollupsDoNotInventProviderRows() throws {
        let envelope = try decode(
            #"{"localSpend":{"actual":{"totalUSD":2,"costStatus":"exact"},"estimated":{"totalUSD":3,"costStatus":"partial"}}}"#)

        let rows = SpendRows.build([], localSpend: envelope.localSpend)
        XCTAssertTrue(rows.isEmpty)
        XCTAssertEqual(envelope.localSpend.actual.costProvenance, "actual")
        XCTAssertEqual(envelope.localSpend.estimated.costProvenance, "estimated")
    }
}

final class LocalSpendRowsTests: XCTestCase {
    private func provider(id: String, cost: Double) -> Provider {
        var provider = Provider()
        provider.id = id
        provider.label = id
        provider.rawDetails = ["totalCostUSD": cost]
        return provider
    }

    private func provider(id: String, rawCost: Any) -> Provider {
        var provider = Provider()
        provider.id = id
        provider.label = id
        provider.rawDetails = ["totalCostUSD": rawCost]
        return provider
    }

    private var providers: [Provider] {
        [provider(id: "openai", cost: 3), provider(id: "claude", cost: 2)]
    }

    func testLegacyPositiveTotalsRemainOneDistinctLocalRow() {
        for localSpend in [
            LocalSpend(totalUSD: 4, costStatus: "exact"),
            LocalSpend(totalUSD: 5, costStatus: "partial")
        ] {
            let rows = SpendRows.build(providers, localSpend: localSpend)
            let localRows = rows.filter { $0.provider == nil }

            XCTAssertEqual(localRows.count, 1)
            XCTAssertEqual(localRows.first?.label, "Local sessions")
            XCTAssertEqual(localRows.first?.note, "local CLI logs · \(localSpend.legacy?.costStatus ?? "")")
            XCTAssertEqual(localRows.first?.costStatus, localSpend.legacy?.costStatus)
            XCTAssertEqual(localRows.first?.currency, "USD")
            XCTAssertEqual(localRows.first?.id, "local-sessions")
            XCTAssertEqual(SpendRows.totalUSD(rows), 7)
        }
    }

    func testUnavailableZeroMissingAndNonFiniteTotalsDoNotChangeProviderRows() {
        let expected = SpendRows.build(providers)
        let cases = [
            LocalSpend(),
            LocalSpend(totalUSD: 0, costStatus: "exact"),
            LocalSpend(totalUSD: .infinity, costStatus: "exact"),
            LocalSpend(totalUSD: 4, costStatus: "unavailable")
        ]

        for localSpend in cases {
            let rows = SpendRows.build(providers, localSpend: localSpend)
            XCTAssertEqual(rows.map(\.id), expected.map(\.id))
            XCTAssertEqual(rows.map(\.cost), expected.map(\.cost))
            XCTAssertTrue(rows.allSatisfy { $0.provider != nil })
        }
    }

    func testProviderSpendRemainsSeparateFromLocalSpend() {
        let rows = SpendRows.build(
            [provider(id: "openai", cost: 3)],
            localSpend: LocalSpend(totalUSD: 10, costStatus: "exact"))

        XCTAssertEqual(rows.first(where: { $0.provider?.id == "openai" })?.cost, 3)
        XCTAssertEqual(rows.first(where: { $0.provider == nil })?.cost, 10)
        XCTAssertEqual(SpendRows.totalUSD(rows), 3)
    }

    func testActualAndEstimatedLocalTotalsMergeBySourceWithBreakdown() {
        let rows = SpendRows.build(
            providers,
            localSpend: LocalSpend(
                actual: LocalSpendTotal(
                    totalUSD: 4,
                    costStatus: "exact",
                    costProvenance: "actual",
                    providers: [" OpenCode ": LocalSpendProvider(costUSD: 4, costStatus: "exact")]),
                estimated: LocalSpendTotal(
                    totalUSD: 5,
                    costStatus: "partial",
                    costProvenance: "estimated",
                    providers: [
                        "opencode": LocalSpendProvider(costUSD: 2, costStatus: "partial"),
                        "cline": LocalSpendProvider(costUSD: 3, costStatus: "exact")
                    ])))

        let localRows = rows.filter { $0.provider == nil }
        XCTAssertEqual(Set(localRows.map(\.label)), ["OpenCode", "Cline"])
        XCTAssertEqual(localRows.first(where: { $0.source == "opencode" })?.cost, 6)
        XCTAssertEqual(localRows.first(where: { $0.source == "opencode" })?.provenance, "mixed")
        XCTAssertEqual(localRows.first(where: { $0.source == "opencode" })?.costStatus, "partial")
        XCTAssertEqual(localRows.first(where: { $0.source == "opencode" })?.costBreakdown?.actualUSD, 4)
        XCTAssertEqual(localRows.first(where: { $0.source == "opencode" })?.costBreakdown?.estimatedUSD, 2)
        XCTAssertEqual(localRows.first(where: { $0.source == "opencode" })?.note, "local CLI logs · mixed · partial")
        XCTAssertEqual(localRows.first(where: { $0.source == "cline" })?.cost, 3)
        XCTAssertEqual(SpendRows.totalUSD(rows), 5)
    }

    func testNativeAndOpenCodeSameProviderRemainDistinctAndTruthful() {
        let rows = SpendRows.build([], localSpend: LocalSpend(
            actual: LocalSpendTotal(
                totalUSD: 0.63,
                costStatus: "exact",
                costProvenance: "actual",
                providers: [
                    "anthropic": LocalSpendProvider(costUSD: 0.21, costStatus: "exact"),
                    "anthropic::opencode": LocalSpendProvider(
                        costUSD: 0.42,
                        costStatus: "exact",
                        source: "opencode")
                ])))

        let localRows = rows.filter { $0.provider == nil }
        XCTAssertEqual(localRows.count, 2)
        XCTAssertEqual(Set(localRows.map(\.id)), ["local-anthropic", "local-anthropic::opencode"])
        XCTAssertEqual(localRows.first(where: { $0.id == "local-anthropic" })?.source, "anthropic")
        XCTAssertEqual(localRows.first(where: { $0.id == "local-anthropic" })?.note, "local CLI logs · actual · exact")
        XCTAssertEqual(localRows.first(where: { $0.id == "local-anthropic::opencode" })?.source, "opencode")
        XCTAssertEqual(localRows.first(where: { $0.id == "local-anthropic::opencode" })?.label, "Anthropic")
        XCTAssertEqual(localRows.first(where: { $0.id == "local-anthropic::opencode" })?.note, "via OpenCode · actual · exact")
        XCTAssertEqual(SpendRows.totalUSD(rows), 0)
    }

    func testLocalSourceLabelsUseNormalizedKnownIDsAndSafeFallback() {
        let rows = SpendRows.build([], localSpend: LocalSpend(
            actual: LocalSpendTotal(
                totalUSD: 2,
                costStatus: "exact",
                providers: [" custom_source ": LocalSpendProvider(costUSD: 2, costStatus: "exact")]),
            estimated: LocalSpendTotal(
                totalUSD: 1,
                costStatus: "exact",
                providers: ["OPENAI": LocalSpendProvider(costUSD: 1, costStatus: "exact")])))

        XCTAssertEqual(rows.first(where: { $0.source == "custom-source" })?.label, "Custom Source")
        XCTAssertEqual(rows.first(where: { $0.source == "openai" })?.label, "Codex")
    }

    func testOpenCodeUpstreamLabelsCoverEveryRoutedProvider() {
        let expected: [String: String] = [
            "ollama-cloud::opencode": "Ollama Cloud",
            "ollama::opencode": "Ollama",
            "github-copilot::opencode": "GitHub Copilot",
            "google::opencode": "Google",
            "zenmux::opencode": "ZenMux",
            "opencode::opencode": "OpenCode Zen",
        ]
        let providers = Dictionary(uniqueKeysWithValues: expected.keys.map {
            ($0, LocalSpendProvider(costUSD: 1, costStatus: "exact", source: "opencode"))
        })
        let rows = SpendRows.build([], localSpend: LocalSpend(
            actual: LocalSpendTotal(
                totalUSD: 6,
                costStatus: "exact",
                costProvenance: "actual",
                providers: providers)))

        let localRows = rows.filter { $0.provider == nil }
        for (key, label) in expected {
            XCTAssertEqual(localRows.first(where: { $0.id == "local-\(key)" })?.label, label)
        }
    }

    func testProviderSpendAcceptsFiniteNumbersButRejectsStringsBooleansAndNonFiniteValues() {
        let cases: [(Any, Double?)] = [
            (Double(3.25), 3.25),
            (Int(2), 2),
            (NSNumber(value: 1.5), 1.5),
            ("3.5", nil),
            (true, nil),
            (NSNumber(value: true), nil),
            (Double.nan, nil),
            (Double.infinity, nil),
            (-Double.infinity, nil)
        ]

        for (rawCost, expectedCost) in cases {
            let rows = SpendRows.build([provider(id: "openai", rawCost: rawCost)])
            if let expectedCost {
                XCTAssertEqual(rows.count, 1)
                XCTAssertEqual(rows.first?.cost, expectedCost)
            } else {
                XCTAssertTrue(rows.isEmpty)
            }
        }
    }
}

@MainActor
final class LocalSpendAppModelTests: XCTestCase {
    func testAppModelSpendRowsUseEnvelopeLocalSpend() {
        let settingsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ai-usage-local-spend-\(UUID().uuidString).json")
        let model = AppModel(settings: SettingsStore(url: settingsURL))
        var provider = Provider()
        provider.id = "openai"
        provider.label = "OpenAI"
        provider.rawDetails = ["totalCostUSD": 2.0]

        model.applyForDiagnostics(Envelope(
            providers: [provider],
            localSpend: LocalSpend(
                actual: LocalSpendTotal(
                    totalUSD: 6,
                    costStatus: "partial",
                    costProvenance: "actual",
                    providers: ["opencode": LocalSpendProvider(costUSD: 6, costStatus: "partial")])))

        XCTAssertEqual(model.spendRows.first(where: { $0.provenance == "actual" })?.cost, 6)
        XCTAssertEqual(model.spendRows.first(where: { $0.provider?.id == "openai" })?.cost, 2)
    }
}
