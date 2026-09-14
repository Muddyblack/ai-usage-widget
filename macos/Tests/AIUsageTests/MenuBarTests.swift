import AppKit
import XCTest

@testable import AIUsage

/// What the menu bar says, and what VoiceOver reads instead.
final class MenuBarTests: XCTestCase {
    /// One provider decoded from a fragment of a real envelope.
    private func makeProvider(_ json: String) throws -> Provider {
        let envelope = try JSONDecoder().decode(Envelope.self, from: Data("{\"providers\":[\(json)]}".utf8))
        return try XCTUnwrap(envelope.providers.first)
    }

    func testSeverityMatchesThePanelPill() {
        // hyprland/PanelSlot.qml and windows/app.py:_text_colour. A glance has
        // to mean the same thing on every platform.
        XCTAssertEqual(MenuBarTitle.colour(forPercent: 69, slotColour: nil, coloured: false), .labelColor)
        XCTAssertEqual(MenuBarTitle.colour(forPercent: 70, slotColour: nil, coloured: false), .systemOrange)
        XCTAssertEqual(MenuBarTitle.colour(forPercent: 89, slotColour: nil, coloured: false), .systemOrange)
        XCTAssertEqual(MenuBarTitle.colour(forPercent: 90, slotColour: nil, coloured: false), .systemRed)
    }

    func testAWarningOutranksTheColouredOption() {
        let blue = NSColor.systemBlue
        XCTAssertEqual(MenuBarTitle.colour(forPercent: 20, slotColour: blue, coloured: true), blue)
        XCTAssertEqual(
            MenuBarTitle.colour(forPercent: 95, slotColour: blue, coloured: true), .systemRed,
            "a decoration must not hide the one reading worth noticing")
    }

    func testASlotWithNoTextIsPrintedAsAPercentage() throws {
        let provider = try makeProvider(
            ###"{"id":"a","slots":[{"pct":92.4,"color":"#fff","text":null,"tooltip":""}]}"###)
        XCTAssertEqual(MenuBarTitle.readings(for: provider, limit: 2).first?.text, "92%")
    }

    func testASlotThatIsNotAPercentageIsPrintedAsGiven() throws {
        let provider = try makeProvider(
            ###"{"id":"a","slots":[{"pct":0,"color":"#fff","text":"$12.50","tooltip":""}]}"###)
        XCTAssertEqual(MenuBarTitle.readings(for: provider, limit: 2).first?.text, "$12.50")
    }

    func testTheReadingLimitIsWhatTheUserAskedFor() throws {
        let provider = try makeProvider(
            """
            {"id":"a","slots":[{"pct":10,"color":"","text":"10%","tooltip":""},
                               {"pct":20,"color":"","text":"20%","tooltip":""},
                               {"pct":30,"color":"","text":"30%","tooltip":""}]}
            """)
        XCTAssertEqual(MenuBarTitle.readings(for: provider, limit: 1).map(\.text), ["10%"])
        XCTAssertEqual(MenuBarTitle.readings(for: provider, limit: 2).map(\.text), ["10%", "20%"])
        XCTAssertEqual(
            MenuBarTitle.readings(for: provider, limit: 9).map(\.text), ["10%", "20%", "30%"],
            "asking for more than there are is not an error")
    }

    func testTheTitleIsEmptyWhenThereIsNothingToSay() throws {
        let provider = try makeProvider(#"{"id":"a","slots":[{"pct":10,"color":"","text":"10%","tooltip":""}]}"#)
        XCTAssertEqual(
            MenuBarTitle.attributedTitle(for: provider, style: .iconOnly, slots: 2, coloured: false).string, "")
        XCTAssertEqual(
            MenuBarTitle.attributedTitle(for: nil, style: .iconAndPercent, slots: 2, coloured: false).string, "")

        let empty = try makeProvider(#"{"id":"a","slots":[]}"#)
        XCTAssertEqual(
            MenuBarTitle.attributedTitle(for: empty, style: .iconAndPercent, slots: 2, coloured: false).string, "")
    }

    func testTheTitleJoinsTheReadings() throws {
        let provider = try makeProvider(
            """
            {"id":"a","icon":"claude-color.svg",
             "slots":[{"pct":93,"color":"","text":"93%","tooltip":""},
                      {"pct":82,"color":"","text":"82%","tooltip":""}]}
            """)
        XCTAssertEqual(
            MenuBarTitle.attributedTitle(
                for: provider, style: .iconAndPercent, slots: 2, coloured: false, icon: .monochrome
            ).string,
            "93% 82%")
    }

    func testAValueAndItsLogoReadAsOneGroup() throws {
        // With a logo in front of each value the gap *between* groups has to be
        // wider than the gap inside one, or "93% 82%" becomes a single smear.
        // An attachment occupies one object-replacement character in the string.
        let provider = try makeProvider(
            """
            {"id":"a","icon":"claude-color.svg",
             "slots":[{"pct":93,"color":"","text":"93%","tooltip":""},
                      {"pct":82,"color":"","text":"82%","tooltip":""}]}
            """)
        let title = MenuBarTitle.attributedTitle(
            for: provider, style: .iconAndPercent, slots: 2, coloured: false, icon: .tinted)
        XCTAssertEqual(
            title.string.replacingOccurrences(of: "\u{FFFC}", with: "@"),
            "@ 93%  @ 82%")
    }

    func testTheTitleUsesMonospacedDigits() throws {
        // Without them the item re-measures on every poll and the whole
        // right-hand side of the menu bar twitches sideways.
        let provider = try makeProvider(#"{"id":"a","slots":[{"pct":9,"color":"","text":"9%","tooltip":""}]}"#)
        let title = MenuBarTitle.attributedTitle(for: provider, style: .percentOnly, slots: 1, coloured: false)
        let font = try XCTUnwrap(title.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        let narrow = NSAttributedString(string: "111", attributes: [.font: font]).size().width
        let wide = NSAttributedString(string: "888", attributes: [.font: font]).size().width
        XCTAssertEqual(narrow, wide, accuracy: 0.01, "every digit has to take the same width")
    }

    // ── Icons beside the values ──────────────────────────────────────────

    func testMonochromeKeepsTheTitleToText() throws {
        let provider = try makeProvider(
            #"{"id":"claude","icon":"claude-color.svg","slots":[{"pct":93,"color":"","text":"93%","tooltip":""}]}"#)
        let title = MenuBarTitle.attributedTitle(
            for: provider, style: .iconAndPercent, slots: 2, coloured: false, icon: .monochrome)
        XCTAssertEqual(title.string, "93%", "the one logo is the button's image, not part of the title")
    }

    func testAPerValueIconIsAttachedBesideEachReading() throws {
        let provider = try makeProvider(
            """
            {"id":"claude","icon":"claude-color.svg",
             "slots":[{"pct":93,"color":"#e05252","text":"93%","tooltip":""},
                      {"pct":61,"color":"#f5a623","text":"61%","tooltip":""}]}
            """)
        for icon in [MenuBarIcon.tinted, .brand] {
            let title = MenuBarTitle.attributedTitle(
                for: provider, style: .iconAndPercent, slots: 2, coloured: false, icon: icon)
            var attachments = 0
            title.enumerateAttribute(.attachment, in: NSRange(location: 0, length: title.length)) { value, _, _ in
                if value != nil { attachments += 1 }
            }
            XCTAssertEqual(attachments, 2, "\(icon.rawValue): one logo per value, as the panel pill draws it")
            XCTAssertTrue(title.string.contains("93%"))
            XCTAssertTrue(title.string.contains("61%"))
        }
    }

    func testAProviderWithNoArtworkGetsNoAttachment() throws {
        // The contract leaves `icon` empty for a provider that ships none;
        // the fallback symbol beside every value would be noise.
        let provider = try makeProvider(
            ##"{"id":"kiro","icon":"","slots":[{"pct":50,"color":"#fff","text":"50%","tooltip":""}]}"##)
        let title = MenuBarTitle.attributedTitle(
            for: provider, style: .iconAndPercent, slots: 1, coloured: false, icon: .tinted)
        var attachments = 0
        title.enumerateAttribute(.attachment, in: NSRange(location: 0, length: title.length)) { value, _, _ in
            if value != nil { attachments += 1 }
        }
        XCTAssertEqual(attachments, 0)
    }

    func testPercentOnlyKeepsEveryIconOut() throws {
        let provider = try makeProvider(
            ##"{"id":"claude","icon":"claude-color.svg","slots":[{"pct":93,"color":"#e05252","text":"93%","tooltip":""}]}"##)
        let title = MenuBarTitle.attributedTitle(
            for: provider, style: .percentOnly, slots: 2, coloured: false, icon: .tinted)
        title.enumerateAttribute(.attachment, in: NSRange(location: 0, length: title.length)) { value, _, _ in
            XCTAssertNil(value, "percentage only means no logo anywhere")
        }
    }

    func testTheIconStyleFallsBackWhenTheSettingIsNonsense() {
        XCTAssertNil(MenuBarIcon(rawValue: "rainbow"))
        XCTAssertTrue(MenuBarIcon.monochrome.isPerValue == false)
        XCTAssertTrue(MenuBarIcon.tinted.isPerValue)
        XCTAssertTrue(MenuBarIcon.brand.isPerValue)
    }

    func testVoiceOverGetsTheSentenceBehindTheNumbers() throws {
        let provider = try makeProvider(
            """
            {"id":"claude","label":"Claude",
             "quotaWindows":[{"key":"session","label":"5-hour session","pct":93,"available":true},
                             {"key":"weekly","label":"7-day window","pct":82,"available":true},
                             {"key":"scoped","label":"Hidden","pct":0,"available":false}]}
            """)
        XCTAssertEqual(
            MenuBarTitle.accessibilityLabel(for: provider),
            "Claude: 5-hour session 93% used, 7-day window 82% used")
    }

    func testAnErrorIsWhatTheLabelSays() throws {
        let provider = try makeProvider(#"{"id":"claude","label":"Claude","error":"token expired"}"#)
        XCTAssertEqual(MenuBarTitle.accessibilityLabel(for: provider), "Claude: token expired")
        XCTAssertEqual(MenuBarTitle.accessibilityLabel(for: nil), "AI Usage")
    }

    func testHexColoursAreReadAndBadOnesDoNotCrash() {
        let parsed = NSColor(hex: "#cc785c").usingColorSpace(.sRGB)
        XCTAssertEqual(parsed?.redComponent ?? 0, 204.0 / 255, accuracy: 0.01)
        XCTAssertEqual(parsed?.blueComponent ?? 0, 92.0 / 255, accuracy: 0.01)
        // Nothing here is information — a colour that cannot be read falls
        // back to a neutral grey rather than failing.
        XCTAssertNotNil(NSColor(hex: "nonsense"))
        XCTAssertNotNil(NSColor(hex: ""))
    }
}

final class CountdownTests: XCTestCase {
    private let minute: Double = 60_000

    func testFormatsTheWayEveryOtherFrontendDoes() {
        // package/contents/code/Format.js — the same quota must not read
        // "2h 14m" in one frontend and "2.2 hours" in another.
        XCTAssertEqual(Countdown.text(targetMs: 134 * minute, nowMs: 0), "2h 14m")
        XCTAssertEqual(Countdown.text(targetMs: 45 * minute, nowMs: 0), "45m")
        XCTAssertEqual(Countdown.text(targetMs: (2 * 1440 + 4 * 60 + 13) * minute, nowMs: 0), "2d 4h 13m")
        XCTAssertEqual(
            Countdown.text(targetMs: 1440 * minute, nowMs: 0), "1d 0h 0m",
            "an hours field appears as soon as there are days, even at zero")
    }

    func testNoTargetAndAPassedTarget() {
        XCTAssertEqual(Countdown.text(targetMs: 0, nowMs: 1000), "")
        XCTAssertEqual(Countdown.text(targetMs: -5, nowMs: 1000), "")
        XCTAssertFalse(Countdown.text(targetMs: 500, nowMs: 1000).isEmpty, "a passed deadline says so")
    }

    func testEpochSecondsAreConverted() {
        XCTAssertEqual(Countdown.fromEpoch(3600, nowMs: 0), "1h 0m")
        XCTAssertEqual(Countdown.fromEpoch(0, nowMs: 0), "", "0 means no reset is known")
    }
}
