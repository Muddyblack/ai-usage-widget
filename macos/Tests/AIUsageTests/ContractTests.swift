import XCTest

@testable import AIUsage

/// Decoding the backend's envelope.
///
/// Leniency is the point of most of these: every field the frontends read was
/// produced by a backend that may be older or newer than this app, so a
/// missing or oddly-typed field has to cost that field and nothing else.
final class ContractTests: XCTestCase {
    private func decode(_ json: String) throws -> Envelope {
        try JSONDecoder().decode(Envelope.self, from: Data(json.utf8))
    }

    func testDecodesAFullProvider() throws {
        let envelope = try decode(
            """
            {"schemaVersion":1,"updatedAt":1785000000,"active":"claude","providers":[
              {"id":"claude","label":"Claude","accent":"#cc785c","icon":"claude-color.svg",
               "ok":true,"stale":false,"error":"","updatedAt":1785000000,
               "summary":{"pct":23,"text":"23%","detail":"max","hasChart":true},
               "quotaWindows":[{"key":"session","label":"5-hour session","pct":23,"available":true,
                                "resetAt":1785010000,"resetText":"Jul 19, 15:00",
                                "detail":"120000 / 500000 tokens","showMeter":true}],
               "chartWindows":[{"id":"session","key":"s","label":"5H","size":18000000,
                                "granularity":"5h","raw":false,"resets":true,
                                "periodMs":18000000,"resetAt":1785010000}],
               "slots":[{"pct":23,"color":"#e05252","text":null,"tooltip":"Claude 5-hour: 23%"}],
               "historyValues":{"s":23,"w":61},
               "details":{"status":{"indicator":"none","description":"All Systems Operational",
                                    "latestUpdate":"","url":"https://status.claude.com"},
                          "currency":"USD"}}
            ]}
            """)

        XCTAssertEqual(envelope.active, "claude")
        let provider = try XCTUnwrap(envelope.provider(id: "claude"))
        XCTAssertEqual(provider.label, "Claude")
        XCTAssertEqual(provider.summary.pct, 23)
        XCTAssertEqual(provider.quotaWindows.first?.label, "5-hour session")
        XCTAssertEqual(provider.chartWindows.first?.label, "5H")
        XCTAssertEqual(provider.historyValues["w"], 61)
        XCTAssertEqual(provider.status.url, "https://status.claude.com")
        XCTAssertFalse(provider.status.isTrouble, "\"none\" is an all-clear, not a disruption")
        XCTAssertTrue(provider.hasChart)
    }

    func testASlotWithNoTextAsksForAMeter() throws {
        let envelope = try decode(
            """
            {"providers":[{"id":"a","slots":[{"pct":40,"color":"#fff","text":null,"tooltip":""},
                                             {"pct":50,"color":"#fff","text":"$12.50","tooltip":""}]}]}
            """)
        let slots = try XCTUnwrap(envelope.providers.first).slots
        XCTAssertNil(slots[0].text)
        XCTAssertEqual(slots[1].text, "$12.50")
    }

    func testAProviderMissingEverythingOptionalStillDecodes() throws {
        // What an older backend, or a provider that failed early, can produce.
        let envelope = try decode(#"{"providers":[{"id":"kiro"}]}"#)
        let provider = try XCTUnwrap(envelope.providers.first)
        XCTAssertEqual(provider.id, "kiro")
        XCTAssertEqual(provider.label, "kiro", "the label falls back to the id")
        XCTAssertTrue(provider.quotaWindows.isEmpty)
        XCTAssertFalse(provider.hasChart)
        XCTAssertEqual(provider.currency, "USD")
    }

    func testFieldsOfTheWrongTypeCostOnlyThatField() throws {
        let envelope = try decode(
            #"{"providers":[{"id":"a","ok":"yes","summary":{"pct":"lots","text":"—"},"quotaWindows":{}}]}"#)
        let provider = try XCTUnwrap(envelope.providers.first)
        XCTAssertEqual(provider.id, "a")
        XCTAssertFalse(provider.ok)
        XCTAssertEqual(provider.summary.pct, 0)
        XCTAssertEqual(provider.summary.text, "—", "the readable field survives the unreadable one")
    }

    func testTheFallbackProviderIsTheBackendsActiveOne() throws {
        var envelope = try decode(#"{"active":"openai","providers":[{"id":"claude"},{"id":"openai"}]}"#)
        XCTAssertEqual(envelope.fallbackID, "openai")

        // `active` naming a provider that is not in the list — switched off
        // between the two reads — falls back to the first row rather than to
        // nothing.
        envelope = try decode(#"{"active":"grok","providers":[{"id":"claude"}]}"#)
        XCTAssertEqual(envelope.fallbackID, "claude")
        envelope = try decode(#"{"active":"grok","providers":[]}"#)
        XCTAssertEqual(envelope.fallbackID, "")
    }

    func testStatusIndicatorSeverity() throws {
        for (indicator, trouble) in [("", false), ("none", false), ("minor", true), ("major", true), ("critical", true)] {
            let envelope = try decode(
                #"{"providers":[{"id":"a","details":{"status":{"indicator":"\#(indicator)"}}}]}"#)
            XCTAssertEqual(envelope.providers.first?.status.isTrouble, trouble, "indicator \(indicator)")
        }
    }
}
