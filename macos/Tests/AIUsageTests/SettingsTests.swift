import XCTest

@testable import AIUsage

/// The settings file, which this app shares with `ai-usage-cli` and with the
/// Linux frontends. Losing another frontend's setting on save is the one
/// failure here that would be invisible until someone else's widget broke.
final class SettingsTests: XCTestCase {
    private var url: URL!

    override func setUp() {
        super.setUp()
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ai-usage-settings-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: url)
        super.tearDown()
    }

    private func write(_ json: String) {
        try? Data(json.utf8).write(to: url)
    }

    private func read() throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    func testKeysThisAppDoesNotKnowSurviveASave() throws {
        // pillMode, position and monitor belong to the Hyprland shell. A Mac
        // save must not erase them from a shared dotfile directory.
        write(#"{"pillMode":"always","position":"top-right","monitor":"DP-1","pollSec":300}"#)
        let settings = SettingsStore(url: url)
        settings.pollSeconds = 900

        let saved = try read()
        XCTAssertEqual(saved["pollSec"] as? Int, 900)
        XCTAssertEqual(saved["pillMode"] as? String, "always")
        XCTAssertEqual(saved["position"] as? String, "top-right")
        XCTAssertEqual(saved["monitor"] as? String, "DP-1")
    }

    func testProviderTogglesDefaultTheWayTheBackendDoes() {
        let settings = SettingsStore(url: url)
        XCTAssertTrue(settings.providerEnabled("claude"), "a provider that needs no pasted token is on")
        XCTAssertFalse(settings.providerEnabled("kimi"), "one that needs a token stays off until asked for")

        settings.setProvider("kimi", enabled: true)
        XCTAssertTrue(settings.providerEnabled("kimi"))
        settings.setProvider("claude", enabled: false)
        XCTAssertFalse(settings.providerEnabled("claude"))
    }

    func testTogglingOneProviderLeavesTheOthersAlone() throws {
        write(#"{"providers":{"claude":false,"openai":true}}"#)
        let settings = SettingsStore(url: url)
        settings.setProvider("grok", enabled: true)

        let toggles = try XCTUnwrap(read()["providers"] as? [String: Any])
        XCTAssertEqual(toggles["claude"] as? Bool, false)
        XCTAssertEqual(toggles["openai"] as? Bool, true)
        XCTAssertEqual(toggles["grok"] as? Bool, true)
    }

    func testAnEmptyKeyIsRemovedRatherThanStoredBlank() throws {
        let settings = SettingsStore(url: url)
        settings.setKey("openai", "sk-test")
        XCTAssertEqual(settings.key("openai"), "sk-test")

        settings.setKey("openai", "")
        XCTAssertEqual(settings.key("openai"), "")
        let keys = try XCTUnwrap(read()["keys"] as? [String: Any])
        XCTAssertNil(keys["openai"], "an empty string would read as a key the backend then tries to use")
    }

    func testAnUnreadableFileIsNotTreatedAsSettings() {
        write("{ this is not json")
        let settings = SettingsStore(url: url)
        XCTAssertTrue(settings.raw.isEmpty)
        XCTAssertEqual(settings.pollSeconds, 300, "the defaults still apply")
    }

    func testThePollIntervalHasAFloor() {
        let settings = SettingsStore(url: url)
        settings.pollSeconds = 1
        XCTAssertEqual(settings.pollSeconds, 30, "a one-second poll would hammer every provider's API")
    }

    func testNumbersWrittenAsStringsAreStillNumbers() {
        // The Plasma widget's config round-trips some values as strings.
        write(#"{"pollSec":"600"}"#)
        XCTAssertEqual(SettingsStore(url: url).pollSeconds, 600)
    }

    func testTheMenuBarSettingsAreBounded() {
        let settings = SettingsStore(url: url)
        XCTAssertEqual(settings.menuBarStyle, .iconAndPercent)
        XCTAssertEqual(settings.menuBarSlots, 2)

        settings.menuBarSlots = 99
        XCTAssertEqual(settings.menuBarSlots, 3)
        settings.menuBarSlots = 0
        XCTAssertEqual(settings.menuBarSlots, 1)

        write(#"{"macMenuBarStyle":"somethingElse"}"#)
        let reloaded = SettingsStore(url: url)
        XCTAssertEqual(reloaded.menuBarStyle, .iconAndPercent, "an unknown style falls back")
    }

    func testFirstRunIsDecidedOnceAtLaunch() {
        let settings = SettingsStore(url: url)
        XCTAssertTrue(settings.isFirstRun)
        settings.pollSeconds = 600
        XCTAssertTrue(settings.isFirstRun, "still the first run — the app only asks once, after saving")
    }
}
