import XCTest

@testable import AIUsage

/// The .po reader, against the same catalogs the QML frontends parse.
///
/// This is a port of `package/contents/code/I18n.js`, and the two have to agree
/// on every msgid or a string translated for the Hyprland panel would come out
/// English here. Most of these are the cases that make them disagree.
final class CatalogTests: XCTestCase {
    private func parse(_ text: String) -> Catalog.Parsed {
        Catalog.parse(text)
    }

    func testReadsASimpleEntry() {
        let catalog = parse(
            """
            msgid "Settings"
            msgstr "Paramètres"
            """)
        XCTAssertEqual(catalog.messages["Settings"], ["Paramètres"])
    }

    func testUntranslatedAndFuzzyEntriesFallBackToEnglish() {
        let catalog = parse(
            """
            msgid "Translated"
            msgstr "Traduit"

            msgid "Empty"
            msgstr ""

            #, fuzzy
            msgid "Unsure"
            msgstr "Incertain"

            #~ msgid "Gone"
            #~ msgstr "Parti"
            """)
        XCTAssertEqual(catalog.messages["Translated"], ["Traduit"])
        XCTAssertNil(catalog.messages["Empty"], "an untranslated entry is not a translation")
        XCTAssertNil(catalog.messages["Unsure"], "a fuzzy entry is a guess, not a translation")
        XCTAssertNil(catalog.messages["Gone"], "an obsolete entry is not in the catalog")
    }

    func testJoinsContinuationLines() {
        let catalog = parse(
            """
            msgid ""
            "A long "
            "source string"
            msgstr ""
            "Une longue "
            "chaîne source"
            """)
        XCTAssertEqual(catalog.messages["A long source string"], ["Une longue chaîne source"])
    }

    func testUndoesGettextEscapes() {
        let catalog = parse(
            #"""
            msgid "Quote \" and newline \n and backslash \\"
            msgstr "Guillemet \" et saut \n et barre \\"
            """#)
        XCTAssertEqual(
            catalog.messages["Quote \" and newline \n and backslash \\"],
            ["Guillemet \" et saut \n et barre \\"])
    }

    func testContextSeparatesTwoTranslationsOfOneWord() {
        let catalog = parse(
            """
            msgctxt "a noun"
            msgid "Usage"
            msgstr "Utilisation"

            msgid "Usage"
            msgstr "Emploi"
            """)
        // gettext itself separates context and id with EOT; I18n.js uses the
        // empty string, and the two implementations have to key the catalog
        // identically or a context'd string would miss in one of them.
        XCTAssertEqual(Catalog.contextSeparator, "")
        XCTAssertEqual(catalog.messages["a nounUsage"], ["Utilisation"])
        XCTAssertEqual(catalog.messages["Usage"], ["Emploi"])
    }

    func testPluralFormsAreReadFromTheHeader() {
        func rule(_ forms: String) -> Catalog.PluralRule? {
            parse(
                """
                msgid ""
                msgstr ""
                "Plural-Forms: \(forms)\\n"
                """
            ).plural
        }
        XCTAssertEqual(rule("nplurals=2; plural=(n != 1);")?.form(1), 0)
        XCTAssertEqual(rule("nplurals=2; plural=(n != 1);")?.form(2), 1)
        XCTAssertEqual(rule("nplurals=2; plural=(n != 1);")?.form(0), 1)
        // French counts zero as singular, which is the case an English-shaped
        // rule gets wrong.
        XCTAssertEqual(rule("nplurals=2; plural=(n > 1);")?.form(0), 0)
        XCTAssertEqual(rule("nplurals=2; plural=(n > 1);")?.form(1), 0)
        XCTAssertEqual(rule("nplurals=2; plural=(n > 1);")?.form(2), 1)
        XCTAssertEqual(rule("nplurals=1; plural=0;")?.form(7), 0)
    }

    // ── Placeholders ─────────────────────────────────────────────────────

    func testPositionalPlaceholders() {
        XCTAssertEqual(Catalog.substitute("Resets in %1", ["2h 14m"]), "Resets in 2h 14m")
        XCTAssertEqual(Catalog.substitute("%2 of %1", ["five", "three"]), "three of five")
        XCTAssertEqual(Catalog.substitute("%1% used", ["23"]), "23% used", "a literal % survives")
        XCTAssertEqual(Catalog.substitute("nothing here", ["unused"]), "nothing here")
    }

    func testAPlaceholderWithNoArgumentIsLeftAlone() {
        // A translator who writes %2 where the source has one argument should
        // see the mistake, not a crash and not a silent blank.
        XCTAssertEqual(Catalog.substitute("%1 and %2", ["one"]), "one and %2")
    }

    // ── Language tags ────────────────────────────────────────────────────

    func testLanguageCandidates() {
        XCTAssertEqual(Catalog.normalise(["fr_FR.UTF-8"]), ["fr_FR", "fr"])
        XCTAssertEqual(Catalog.normalise(["fr-FR"]), ["fr_FR", "fr"])
        XCTAssertEqual(Catalog.normalise(["de_AT@euro", "de"]), ["de_AT", "de"])
        XCTAssertEqual(Catalog.normalise(["C", "POSIX", ""]), [], "the C locale is not a language")
        XCTAssertEqual(Catalog.normalise(["fr", "fr_FR"]), ["fr", "fr_FR"], "no repeats, order kept")
    }

    func testAnExplicitSettingBeatsTheEnvironment() {
        XCTAssertEqual(Catalog.candidates(language: "fr").first, "fr")
    }

    // ── Against the catalog that is really in the repository ─────────────

    func testTheFrenchCatalogParses() throws {
        guard let directory = Catalog.translateDirectory() else {
            throw XCTSkip("no translate/ directory beside this build")
        }
        let url = directory.appendingPathComponent("fr.po")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("no French catalog")
        }
        let catalog = Catalog.parse(try String(contentsOf: url, encoding: .utf8))

        XCTAssertGreaterThan(catalog.messages.count, 100, "the French catalog has hundreds of entries")
        XCTAssertNotNil(catalog.plural, "its header declares Plural-Forms")
        // Strings this app uses that the QML frontends already had translated.
        // They are the reason this reads the shared catalog instead of its own.
        XCTAssertEqual(catalog.messages["Settings"]?.first, "Paramètres")
        XCTAssertEqual(catalog.messages["Resets in %1"]?.first, "Réinitialisation dans %1")
    }

    func testLoadingFrenchAndBack() throws {
        guard let directory = Catalog.translateDirectory(),
              FileManager.default.fileExists(atPath: directory.appendingPathComponent("fr.po").path)
        else { throw XCTSkip("no French catalog") }

        XCTAssertTrue(Catalog.load(language: "fr"))
        XCTAssertEqual(Catalog.current.language, "fr")
        XCTAssertEqual(i18n("Settings"), "Paramètres")
        XCTAssertEqual(i18n("Resets in %1", "2h 14m"), "Réinitialisation dans 2h 14m")
        XCTAssertEqual(i18n("A string nobody has translated"), "A string nobody has translated")

        // An unknown language leaves English, which is the msgid itself.
        XCTAssertFalse(Catalog.load(language: "xx"))
        XCTAssertEqual(i18n("Settings"), "Settings")
    }

    func testACatalogNameHasToLookLikeOne() {
        // The tag comes from a settings file and an environment variable, and
        // is used to build a path.
        for hostile in ["../../etc/passwd", "fr/../../x", "", "toolongtobealanguage"] {
            XCTAssertFalse(Catalog.load(language: hostile), "accepted \(hostile)")
        }
    }
}
