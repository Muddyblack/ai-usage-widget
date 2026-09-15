import Foundation

/// Translations, read from the same `translate/<lang>.po` every other frontend
/// of this widget reads.
///
/// Not a `.lproj` or a String Catalog, on purpose. Those would be a second set
/// of translation files for the same application, and a translator would have
/// to do the work twice — while `translate/fr.po` already carries "Paramètres",
/// "Actualiser" and "Réinitialisation dans %1". Using the same msgids as the
/// QML frontends means a string they have translated is translated here the
/// moment it is used, and a string this app adds goes into the same catalog
/// through `translate/Messages.sh`.
///
/// A port of `package/contents/code/I18n.js`, which is the Quickshell panel's
/// and the Windows tray app's copy of the same thing. ki18n's call shapes and
/// `%1` placeholders, so the three implementations agree on every msgid.
enum Catalog {
    /// The parsed catalog in use. Replaced by `load(language:)`; read on the
    /// main thread by the views.
    private(set) static var current = Parsed()

    struct Parsed {
        /// "context\u{4}msgid" → the translated forms.
        var messages: [String: [String]] = [:]
        /// The header's Plural-Forms, reduced to the handful of rules our own
        /// catalogs use. nil falls back to English's one-or-many.
        var plural: PluralRule?
        var language = ""

        var isEmpty: Bool { messages.isEmpty }
    }

    /// gettext separates a context from its msgid with EOT, and `parsePo` in
    /// I18n.js uses the empty string because QML's own lookups never carry a
    /// context. Kept explicit here so the two cannot drift silently.
    static let contextSeparator = ""

    // ── Loading ──────────────────────────────────────────────────────────

    /// Read the catalog for `language`, or for the system's own languages when
    /// it is empty. Leaves English in place when there is no catalog to read —
    /// which is also what "en" means, since English is the msgid itself.
    @discardableResult
    static func load(language: String = "") -> Bool {
        for tag in candidates(language: language) {
            guard let url = catalogURL(tag), let text = try? String(contentsOf: url, encoding: .utf8) else {
                continue
            }
            var parsed = parse(text)
            parsed.language = tag
            current = parsed
            return true
        }
        current = Parsed()
        return false
    }

    /// The language tags to try, best first: the explicit setting, else
    /// $LANGUAGE the way gettext reads it, else the system's own list.
    static func candidates(language: String) -> [String] {
        if !language.isEmpty { return normalise([language]) }
        let fromEnvironment = (ProcessInfo.processInfo.environment["LANGUAGE"] ?? "")
            .split(separator: ":").map(String.init)
        return normalise(fromEnvironment + Locale.preferredLanguages)
    }

    /// "fr-FR" / "fr_FR.UTF-8" → ["fr_FR", "fr"], in order, without repeats.
    static func normalise(_ languages: [String]) -> [String] {
        var out: [String] = []
        for raw in languages {
            // Strip the encoding and the modifier, then spell the separator
            // the way a .po file is named.
            var tag = raw
            if let dot = tag.firstIndex(of: ".") { tag = String(tag[tag.startIndex..<dot]) }
            if let at = tag.firstIndex(of: "@") { tag = String(tag[tag.startIndex..<at]) }
            tag = tag.replacingOccurrences(of: "-", with: "_")

            if tag.isEmpty || tag == "C" || tag == "POSIX" { continue }
            let base = String(tag.split(separator: "_").first ?? "")
            if !out.contains(tag) { out.append(tag) }
            if !base.isEmpty, !out.contains(base) { out.append(base) }
        }
        return out
    }

    /// Every language the checkout or the bundle has a catalog for, for the
    /// language picker.
    static func available() -> [String] {
        guard let directory = translateDirectory() else { return [] }
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return files.filter { $0.hasSuffix(".po") }.map { String($0.dropLast(3)) }.sorted()
    }

    private static func catalogURL(_ tag: String) -> URL? {
        guard let directory = translateDirectory() else { return nil }
        // A catalog name has to look like one: this is a path built from a
        // settings file and an environment variable.
        guard tag.range(of: "^[A-Za-z]{2,3}(_[A-Za-z0-9]+)?$", options: .regularExpression) != nil else {
            return nil
        }
        let url = directory.appendingPathComponent("\(tag).po")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// `Contents/Resources/translate` in the bundle, or the checkout's own
    /// `translate/` when running from `swift run`.
    static func translateDirectory() -> URL? {
        var candidates = [
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/translate", isDirectory: true)
        ]
        var directory = Bundle.main.bundleURL.resolvingSymlinksInPath()
        for _ in 0..<6 {
            candidates.append(directory.appendingPathComponent("translate", isDirectory: true))
            directory = directory.deletingLastPathComponent()
        }
        return candidates.first { url in
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            return exists && isDirectory.boolValue
        }
    }
}

// ── Parsing ──────────────────────────────────────────────────────────────

extension Catalog {
    /// The plural rules our own catalogs use, chosen by the header rather than
    /// evaluated from it.
    ///
    /// I18n.js compiles the header's C expression with `new Function`, which
    /// Swift has no equivalent of and which would be a small interpreter to
    /// write. These are the forms gettext generates for the languages this
    /// project has catalogs for; anything else falls back to English's rule,
    /// which is what an untranslated string gets anyway.
    enum PluralRule {
        /// nplurals=2; plural=(n != 1) — English, German, most of Europe.
        case oneIsSingular
        /// nplurals=2; plural=(n > 1) — French, Portuguese.
        case zeroIsSingular
        /// nplurals=1 — Japanese, Chinese, Korean, Turkish.
        case single

        func form(_ n: Int) -> Int {
            switch self {
            case .oneIsSingular: return n != 1 ? 1 : 0
            case .zeroIsSingular: return n > 1 ? 1 : 0
            case .single: return 0
            }
        }

        static func parse(_ header: String) -> PluralRule? {
            guard let range = header.range(of: "Plural-Forms:") else { return nil }
            let line = header[range.upperBound...]
                .prefix { $0 != "\n" }
                .replacingOccurrences(of: " ", with: "")
            if line.contains("nplurals=1") { return .single }
            if line.contains("plural=(n>1)") || line.contains("plural=n>1") { return .zeroIsSingular }
            if line.contains("plural=(n!=1)") || line.contains("plural=n!=1") { return .oneIsSingular }
            return nil
        }
    }

    /// The text between the first and last quote of a .po line, with gettext's
    /// escapes undone.
    static func unquote(_ line: String) -> String {
        guard
            let start = line.firstIndex(of: "\""),
            let end = line.lastIndex(of: "\""),
            start < end
        else { return "" }

        var out = ""
        var escaped = false
        for character in line[line.index(after: start)..<end] {
            if escaped {
                switch character {
                case "n": out.append("\n")
                case "t": out.append("\t")
                case "r": out.append("\r")
                default: out.append(character)
                }
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else {
                out.append(character)
            }
        }
        return out
    }

    /// Fuzzy, obsolete and untranslated entries are left out, so they fall back
    /// to the English source text exactly as gettext does.
    static func parse(_ text: String) -> Parsed {
        var catalog = Parsed()

        var context = ""
        var msgid: String?
        var forms: [String] = []
        var fuzzy = false
        // Which field a bare continuation line ("…") belongs to.
        enum Field { case context, id, form(Int) }
        var field: Field?

        func flush() {
            defer {
                context = ""
                msgid = nil
                forms = []
                fuzzy = false
                field = nil
            }
            guard let id = msgid else { return }
            if id.isEmpty {
                catalog.plural = PluralRule.parse(forms.first ?? "")
                return
            }
            guard !fuzzy, !forms.isEmpty, !forms.contains("") else { return }
            catalog.messages[context + contextSeparator + id] = forms
        }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flush()
                continue
            }
            if line.hasPrefix("#~") { continue }
            if line.hasPrefix("#,") {
                if line.contains("fuzzy") { fuzzy = true }
                continue
            }
            if line.hasPrefix("#") { continue }

            if line.hasPrefix("msgctxt") {
                if msgid != nil { flush() }
                context = unquote(line)
                field = .context
            } else if line.hasPrefix("msgid_plural") {
                // The plural source is never looked up — the singular is the
                // key — so it is read and dropped.
                field = nil
            } else if line.hasPrefix("msgid") {
                if msgid != nil { flush() }
                msgid = unquote(line)
                field = .id
            } else if line.hasPrefix("msgstr[") {
                let digits = line.dropFirst("msgstr[".count).prefix { $0.isNumber }
                let index = Int(digits) ?? 0
                while forms.count <= index { forms.append("") }
                forms[index] = unquote(line)
                field = .form(index)
            } else if line.hasPrefix("msgstr") {
                if forms.isEmpty { forms.append("") }
                forms[0] = unquote(line)
                field = .form(0)
            } else if line.hasPrefix("\""), let current = field {
                let more = unquote(line)
                switch current {
                case .context: context += more
                case .id: msgid = (msgid ?? "") + more
                case .form(let index) where index < forms.count: forms[index] += more
                case .form: break
                }
            }
        }
        flush()
        return catalog
    }

    // ── Lookup ───────────────────────────────────────────────────────────

    /// `%1`, `%2`, … replaced positionally — ki18n's placeholders, which the
    /// QML frontends use too, so one msgid serves all of them.
    static func substitute(_ text: String, _ arguments: [String]) -> String {
        guard text.contains("%") else { return text }
        var out = ""
        let characters = Array(text)
        var index = 0
        while index < characters.count {
            if characters[index] == "%", index + 1 < characters.count,
               let position = characters[index + 1].wholeNumberValue, position >= 1,
               position <= arguments.count {
                out += arguments[position - 1]
                index += 2
            } else {
                out.append(characters[index])
                index += 1
            }
        }
        return out
    }

    static func forms(context: String, id: String) -> [String]? {
        current.messages[context + contextSeparator + id]
    }
}

// ── ki18n's call shapes ──────────────────────────────────────────────────
//
// Free functions, and named the way the QML calls them, so `translate/
// Messages.sh` extracts `i18n("…")` out of Swift into the very same catalog
// entry as `shell.i18n("…")` out of QML.

/// One translated string. `%1`, `%2`, … are filled from `arguments`.
func i18n(_ text: String, _ arguments: CustomStringConvertible...) -> String {
    let translated = Catalog.forms(context: "", id: text)?.first ?? text
    return Catalog.substitute(translated, arguments.map(\.description))
}

/// The same, disambiguated by context for a word that translates two ways.
func i18nc(_ context: String, _ text: String, _ arguments: CustomStringConvertible...) -> String {
    let translated = Catalog.forms(context: context, id: text)?.first ?? text
    return Catalog.substitute(translated, arguments.map(\.description))
}

/// Marks a string for extraction without translating it here.
///
/// gettext's `N_()`. A string held in a table — the settings page's per-provider
/// key labels — has to be translated where it is *shown*, because the table is
/// built once and would otherwise freeze whichever language was loaded first.
/// This is what puts it in the catalog anyway.
func i18nNoop(_ text: String) -> String { text }

/// Singular/plural by `n`, which is also `%1`.
func i18np(
    _ singular: String, _ plural: String, _ n: Int, _ arguments: CustomStringConvertible...
) -> String {
    let text: String
    if let forms = Catalog.forms(context: "", id: singular), let rule = Catalog.current.plural {
        let index = rule.form(n)
        text = index < forms.count ? forms[index] : (forms.last ?? singular)
    } else {
        text = n == 1 ? singular : plural
    }
    return Catalog.substitute(text, ["\(n)"] + arguments.map(\.description))
}
