import Combine
import Foundation

/// The settings file every frontend of this widget shares.
///
/// Same path, same keys, same file as the Hyprland shell and the Windows tray
/// app: `~/.config/ai-usage-widget/hyprland-settings.json`, or wherever
/// `AI_USAGE_CONFIG` points. A Mac app would normally keep this under
/// ~/Library/Application Support, and this one deliberately does not — the
/// `ai-usage-cli` terminal frontend and this app are meant to be two views of
/// one configuration, and splitting the file would mean pasting every API key
/// twice.
///
/// Keys this app does not know are read and written back untouched, so a
/// setting only the Linux frontends use survives a save from here.
final class SettingsStore: ObservableObject {
    /// Everything in the file, including keys this app never looks at.
    @Published private(set) var raw: [String: Any] = [:]

    private let url: URL
    /// Whether the file was missing when the app started. Captured here
    /// because the first save makes it exist, and the answer must not change
    /// underneath the one caller that asks.
    let isFirstRun: Bool

    init(url: URL? = nil) {
        let resolved = url ?? Self.defaultURL
        self.url = resolved
        self.isFirstRun = !FileManager.default.fileExists(atPath: resolved.path)
        reload()
    }

    static var defaultURL: URL {
        let env = ProcessInfo.processInfo.environment
        if let override = env["AI_USAGE_CONFIG"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        let base = env["XDG_CONFIG_HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config")
        return base
            .appendingPathComponent("ai-usage-widget", isDirectory: true)
            .appendingPathComponent("hyprland-settings.json")
    }

    var path: String { url.path }

    func reload() {
        guard
            let data = try? Data(contentsOf: url),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            raw = [:]
            return
        }
        raw = object
    }

    // ── Typed access ─────────────────────────────────────────────────────

    func bool(_ key: String, default fallback: Bool) -> Bool {
        raw[key] as? Bool ?? fallback
    }

    func int(_ key: String, default fallback: Int) -> Int {
        if let value = raw[key] as? Int { return value }
        if let value = raw[key] as? Double { return Int(value) }
        if let value = raw[key] as? String, let parsed = Int(value) { return parsed }
        return fallback
    }

    func string(_ key: String, default fallback: String = "") -> String {
        raw[key] as? String ?? fallback
    }

    func set(_ key: String, _ value: Any?) {
        var next = raw
        if let value { next[key] = value } else { next.removeValue(forKey: key) }
        write(next)
    }

    // ── Providers ────────────────────────────────────────────────────────

    /// Every provider id the backend knows, in the backend's own order.
    static let allProviders = [
        "claude", "antigravity", "openai", "kiro", "mistral", "openrouter", "ollama", "selfhosted",
        "grok", "zai", "copilot", "deepseek", "kimi", "muse", "cursor", "cline", "opencode",
    ]

    /// Providers that stay off until switched on — they need a token to paste,
    /// or a tool that may not be installed. Mirrors config.py:OPT_IN_PROVIDERS.
    static let optInProviders: Set<String> = ["zai", "copilot", "deepseek", "kimi", "muse", "cursor", "cline", "opencode", "ollama", "selfhosted"]

    func providerEnabled(_ id: String) -> Bool {
        let toggles = raw["providers"] as? [String: Any] ?? [:]
        return (toggles[id] as? Bool) == true
    }

    func setProvider(_ id: String, enabled: Bool) {
        var toggles = raw["providers"] as? [String: Any] ?? [:]
        toggles[id] = enabled
        var next = raw
        next["providers"] = toggles
        write(next)
    }

    func key(_ name: String) -> String {
        (raw["keys"] as? [String: Any])?[name] as? String ?? ""
    }

    func setKey(_ name: String, _ value: String) {
        var keys = raw["keys"] as? [String: Any] ?? [:]
        if value.isEmpty { keys.removeValue(forKey: name) } else { keys[name] = value }
        var next = raw
        next["keys"] = keys
        write(next)
    }

    // ── Named settings ───────────────────────────────────────────────────

    var pollSeconds: Int {
        get { max(30, int("pollSec", default: 300)) }
        set { set("pollSec", max(30, newValue)) }
    }

    var showChart: Bool {
        get { bool("showChart", default: true) }
        set { set("showChart", newValue) }
    }

    /// The catalog to use, "" meaning follow the system. The same key the
    /// Hyprland shell's language picker writes, so the two agree.
    var language: String {
        get { string("language") }
        set { set("language", newValue) }
    }

    var museQuota: Bool {
        get { bool("museQuota", default: false) }
        set { set("museQuota", newValue) }
    }

    // ── Feature views (Overview / Spend / Sessions) ──────────────────────
    // Same defaults as FeatureTabs.js and the other frontends: Sessions is on
    // unless turned off, Overview and Spend stay off until turned on.
    // Top-level booleans (overviewEnabled …), shared with the Hyprland and
    // Windows settings files.
    func featureEnabled(_ id: String) -> Bool {
        if id == "sessions" { return bool("sessionsEnabled", default: true) }
        if id == "overview" { return bool("overviewEnabled", default: false) }
        if id == "spend" { return bool("spendEnabled", default: false) }
        return false
    }

    func setFeature(_ id: String, enabled: Bool) {
        if id == "overview" { set("overviewEnabled", enabled) }
        else if id == "spend" { set("spendEnabled", enabled) }
        else if id == "sessions" { set("sessionsEnabled", enabled) }
    }

    /// The provider the menu bar shows. Stable by choice: the numbers must not
    /// change meaning on their own while someone is glancing at them.
    var menuBarProvider: String {
        get { string("macProvider") }
        set { set("macProvider", newValue) }
    }

    var menuBarStyle: MenuBarStyle {
        get { MenuBarStyle(rawValue: string("macMenuBarStyle")) ?? .iconAndPercent }
        set { set("macMenuBarStyle", newValue.rawValue) }
    }

    /// How many of the provider's values the menu bar prints. Crowded menu
    /// bars are the norm on a laptop with a notch, so one is a real choice.
    var menuBarSlots: Int {
        get { min(3, max(1, int("macMenuBarSlots", default: 2))) }
        set { set("macMenuBarSlots", min(3, max(1, newValue))) }
    }

    /// Colour every percentage in the provider's accent, rather than keeping
    /// them in the menu bar's own colour until a value is worth a look.
    var colouredPercentages: Bool {
        get { bool("macColouredPercent", default: false) }
        set { set("macColouredPercent", newValue) }
    }

    /// How the provider's logo is drawn in the menu bar.
    var menuBarIcon: MenuBarIcon {
        get { MenuBarIcon(rawValue: string("macMenuBarIcon")) ?? .monochrome }
        set { set("macMenuBarIcon", newValue.rawValue) }
    }

    private func write(_ next: [String: Any]) {
        raw = next
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: next, options: [.sortedKeys, .prettyPrinted])
            // Replaced by rename: the Linux frontends read this file on a
            // timer, and a reader that catches a partial write treats it as
            // corrupt.
            guard FileManager.default.fileExists(atPath: url.path) else {
                try data.write(to: url, options: .atomic)
                return
            }
            let tmp = url.deletingLastPathComponent()
                .appendingPathComponent("\(url.lastPathComponent).tmp.\(ProcessInfo.processInfo.processIdentifier)")
            try data.write(to: tmp, options: .atomic)
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
        } catch {
            NSLog("AI Usage: could not save settings to \(url.path): \(error.localizedDescription)")
        }
    }
}

/// How the logo beside the percentages is drawn.
///
/// `monochrome` is the default because it is what macOS wants: a template
/// image inverts with the menu bar, dims with the app, and stays legible over
/// any wallpaper. The other two exist because the Plasma widget and the
/// Hyprland pill both show colour, and somebody moving between them may want
/// the same thing here.
enum MenuBarIcon: String, CaseIterable, Identifiable {
    /// One template logo, the menu bar's own colour.
    case monochrome
    /// One logo per value, filled with that value's colour — the panel pill.
    case tinted
    /// One logo per value, in the brand's own colours.
    case brand

    var id: String { rawValue }

    var title: String {
        switch self {
        case .monochrome: return i18n("Monochrome")
        case .tinted: return i18n("One per value, tinted")
        case .brand: return i18n("One per value, brand colours")
        }
    }

    /// Whether a logo is drawn beside each reading rather than once at the far
    /// left — which is what makes two values read as two things.
    var isPerValue: Bool { self != .monochrome }
}

enum MenuBarStyle: String, CaseIterable, Identifiable {
    case iconAndPercent
    case percentOnly
    case iconOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .iconAndPercent: return "Icon and percentage"
        case .percentOnly: return "Percentage only"
        case .iconOnly: return "Icon only"
        }
    }
}
