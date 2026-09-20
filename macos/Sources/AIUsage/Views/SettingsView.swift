import AppKit
import SwiftUI

/// Settings, in a window of their own.
///
/// Not in the popover: a transient popover closes the moment focus moves, and
/// pasting an API key moves focus. It also means the settings survive a
/// menu-bar click, can be moved, and behave like every other Mac app's
/// settings window.
struct SettingsView: View {
    @ObservedObject var model: AppModel

    /// Which providers take a credential, and which settings key it is stored
    /// under. A provider absent from here needs none — it reads a local file or
    /// borrows another tool's login.
    /// The label and the help are msgids, translated where they are shown —
    /// a static table is built once and would otherwise freeze whatever
    /// language was loaded first.
    private static let keyFields: [String: (key: String, label: String, help: String)] = [
        "claude": ("claudeAdmin", i18nNoop("Admin API key"), i18nNoop("Optional. Adds organisation-wide usage next to your own.")),
        "openai": ("openai", i18nNoop("API key"), i18nNoop("Optional. Codex sign-in is read from ~/.codex.")),
        "mistral": ("mistral", i18nNoop("API key"), ""),
        "openrouter": ("openrouter", i18nNoop("API key"), ""),
        "ollama": ("ollama", i18nNoop("API key"), i18nNoop("Optional. OpenCode's Ollama Cloud login is used when this is empty.")),
        "grok": ("grok", i18nNoop("API key"), ""),
        "zai": ("zai", i18nNoop("Token"), ""),
        "copilot": ("github", i18nNoop("GitHub token"), i18nNoop("Optional. `gh auth token` is used when this is empty.")),
        "muse": ("muse", i18nNoop("META_API_KEY"), i18nNoop("Optional. The CLI's own login is used when this is empty.")),
        "deepseek": ("deepseek", i18nNoop("API key"), ""),
        "kimi": ("moonshot", i18nNoop("API key"), ""),
    ]

    var body: some View {
        TabView {
            providersTab
                .tabItem { Label(i18n("Providers"), systemImage: "square.grid.2x2") }
            viewsTab
                .tabItem { Label(i18n("Views"), systemImage: "rectangle.grid.2x2") }
            menuBarTab
                .tabItem { Label(i18n("Menu Bar"), systemImage: "menubar.rectangle") }
            generalTab
                .tabItem { Label(i18n("General"), systemImage: "gearshape") }
        }
        .frame(width: 460, height: 420)
    }

    // ── Providers ────────────────────────────────────────────────────────

    private var providersTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(SettingsStore.allProviders, id: \.self) { id in
                    providerRow(id)
                    Divider()
                }
            }
            .padding(16)
        }
    }

    private func providerRow(_ id: String) -> some View {
        let enabled = model.settings.providerEnabled(id)
        let field = Self.keyFields[id]
        return VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(
                get: { enabled },
                set: { value in model.changeSettings { $0.setProvider(id, enabled: value) } }
            )) {
                HStack(spacing: 6) {
                    if let image = Artwork.providerImage(iconName(id)) {
                        Image(nsImage: image).resizable().frame(width: 15, height: 15)
                    }
                    Text(label(id))
                }
            }
            .toggleStyle(.switch)

            if enabled, let field {
                VStack(alignment: .leading, spacing: 3) {
                    SecureField(i18n(field.label), text: Binding(
                        get: { model.settings.key(field.key) },
                        set: { value in model.changeSettings { $0.setKey(field.key, value) } }
                    ))
                    .textFieldStyle(.roundedBorder)
                    if !field.help.isEmpty {
                        Text(i18n(field.help)).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                .padding(.leading, 22)
            }
            if id == "selfhosted" {
                VStack(alignment: .leading, spacing: 4) {
                    TextField(i18n("Server URLs, comma separated (empty: auto detect)"), text: Binding(
                        get: { model.settings.string("selfhostedEndpoint") },
                        set: { value in model.changeSettings { $0.set("selfhostedEndpoint", value) } }
                    ))
                    TextField(i18n("Engine: auto, ollama, vllm, llama.cpp"), text: Binding(
                        get: { model.settings.string("selfhostedEngine", default: "auto") },
                        set: { value in model.changeSettings { $0.set("selfhostedEngine", value) } }
                    ))
                    SecureField(i18n("Optional bearer token"), text: Binding(
                        get: { model.settings.key("selfhosted") },
                        set: { value in model.changeSettings { $0.setKey("selfhosted", value) } }
                    ))
                }
                .textFieldStyle(.roundedBorder)
                .padding(.leading, 22)
            }
        }
    }

    /// The provider's own label and logo when the backend has reported it;
    /// the bare id before the first refresh, so the list is never empty.
    private func label(_ id: String) -> String {
        model.envelope.provider(id: id)?.label ?? id.capitalized
    }

    private func iconName(_ id: String) -> String {
        model.envelope.provider(id: id)?.icon ?? ""
    }

    // ── Views (Overview / Spend / Sessions) ────────────────────────────────
    // The same optional popup tabs the Linux frontends offer, with the same
    // defaults and the same shared settings keys — so a toggle here is a
    // toggle there. The popover reads them through AppModel.featureTabs.

    private var viewsTab: some View {
        Form {
            Text(i18n("Optional tabs that sit ahead of your providers in the popover."))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            // Literals, not `view.label`: xgettext only extracts literals, and
            // the settings key-field table next to this is the one allowed
            // indirection (see test_every_translation_call…).
            Toggle(isOn: Binding(
                get: { model.settings.featureEnabled("overview") },
                set: { value in model.changeSettings { $0.setFeature("overview", enabled: value) } }
            )) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(i18n("Overview"))
                    Text(i18n("All enabled providers at a glance"))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            Toggle(isOn: Binding(
                get: { model.settings.featureEnabled("spend") },
                set: { value in model.changeSettings { $0.setFeature("spend", enabled: value) } }
            )) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(i18n("Usage & Spend"))
                    Text(i18n("Combined cost figures across providers"))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            Toggle(isOn: Binding(
                get: { model.settings.featureEnabled("sessions") },
                set: { value in model.changeSettings { $0.setFeature("sessions", enabled: value) } }
            )) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(i18n("Sessions"))
                    Text(i18n("Recent local agent sessions (no transcripts)"))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    // ── Menu bar ─────────────────────────────────────────────────────────

    private var menuBarTab: some View {
        Form {
            Picker(i18n("Show"), selection: Binding(
                get: { model.settings.menuBarStyle },
                set: { value in model.changeSettings { $0.menuBarStyle = value } }
            )) {
                ForEach(MenuBarStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }

            Picker(i18n("Values"), selection: Binding(
                get: { model.settings.menuBarSlots },
                set: { value in model.changeSettings { $0.menuBarSlots = value } }
            )) {
                Text(i18n("One")).tag(1)
                Text(i18n("Two")).tag(2)
                Text(i18n("Three")).tag(3)
            }
            .disabled(model.settings.menuBarStyle == .iconOnly)

            Picker(i18n("Icon"), selection: Binding(
                get: { model.settings.menuBarIcon },
                set: { value in model.changeSettings { $0.menuBarIcon = value } }
            )) {
                ForEach(MenuBarIcon.allCases) { icon in
                    Text(icon.title).tag(icon)
                }
            }
            .disabled(model.settings.menuBarStyle == .percentOnly)
            Text(i18n("Monochrome is what macOS expects: it inverts with the menu bar and stays legible over any wallpaper. The other two show a logo beside every value, the way the Plasma panel does."))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            Toggle(i18n("Colour every percentage"), isOn: Binding(
                get: { model.settings.colouredPercentages },
                set: { value in model.changeSettings { $0.colouredPercentages = value } }
            ))
            Text(i18n("Off, a percentage stays in the menu bar's own colour until it is worth a look — amber from 70 %, red from 90 %."))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            Picker(i18n("Provider"), selection: Binding(
                get: { model.selectedID },
                set: { model.selectedID = $0 }
            )) {
                ForEach(model.providers) { provider in
                    Text(provider.label).tag(provider.id)
                }
            }
            .disabled(model.providers.isEmpty)
        }
        .formStyle(.grouped)
    }

    /// "fr" → "français", in that language rather than in the current one, so
    /// somebody who cannot read the current one can still find theirs.
    private func languageName(_ tag: String) -> String {
        let locale = Locale(identifier: tag)
        let name = locale.localizedString(forIdentifier: tag) ?? tag
        return name.isEmpty ? tag : name.prefix(1).uppercased() + name.dropFirst()
    }

    // ── General ──────────────────────────────────────────────────────────

    private var generalTab: some View {
        Form {
            Picker(i18n("Refresh every"), selection: Binding(
                get: { model.settings.pollSeconds },
                set: { value in model.changeSettings { $0.pollSeconds = value } }
            )) {
                Text(i18n("1 minute")).tag(60)
                Text(i18n("5 minutes")).tag(300)
                Text(i18n("15 minutes")).tag(900)
                Text(i18n("30 minutes")).tag(1800)
                Text(i18n("1 hour")).tag(3600)
            }

            Picker(i18n("Language"), selection: Binding(
                get: { model.settings.language },
                set: { value in model.changeSettings { $0.language = value } }
            )) {
                Text(i18n("Follow the system")).tag("")
                ForEach(Catalog.available(), id: \.self) { tag in
                    Text(languageName(tag)).tag(tag)
                }
            }
            Text(i18n("Translations come from the same catalogs the Linux frontends read."))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            Toggle(i18n("Show the usage history chart"), isOn: Binding(
                get: { model.settings.showChart },
                set: { value in model.changeSettings { $0.showChart = value } }
            ))

            Section {
                Toggle(i18n("Open at Login"), isOn: Binding(
                    get: { LoginItem.isEnabled },
                    set: { value in
                        LoginItem.set(value)
                        model.objectWillChange.send()
                    }
                ))
                .disabled(!LoginItem.isSupported)
                if LoginItem.needsApproval {
                    Text(i18n("macOS is waiting for you to allow this in System Settings › General › Login Items."))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                } else if !LoginItem.isSupported {
                    Text(i18n("Available once the app is running from AI Usage.app."))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Toggle(i18n("Muse live quota"), isOn: Binding(
                    get: { model.settings.museQuota },
                    set: { value in model.changeSettings { $0.museQuota = value } }
                ))
                Text(i18n("Meta publishes Muse's plan windows only on a billed model call, so reading them costs a few tokens per refresh. Everything else Muse shows is read from local files and costs nothing."))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent(i18n("Settings file")) {
                    Text(model.settings.path)
                        .font(.system(size: 10))
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
                Text(i18n("Shared with `ai-usage-cli` and with this widget's Linux frontends, so a key pasted here is pasted once."))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
