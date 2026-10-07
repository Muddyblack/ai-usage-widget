const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const I18n = require("../ui/js/I18n.js");

// The Quickshell panel and the Windows tray app translate with this parser
// instead of KDE's i18n; it has to read the catalog exactly as msgfmt would.

const PO = `msgid ""
msgstr ""
"Language: fr\\n"
"Plural-Forms: nplurals=2; plural=(n > 1);\\n"

#: ui/SettingsPage.qml
msgid "Refresh"
msgstr "Actualisation"

msgctxt "settings tab"
msgid "Data"
msgstr "Données"

msgid "%1 session"
msgid_plural "%1 sessions"
msgstr[0] "%1 session"
msgstr[1] "%1 sessions"

msgid ""
"Two\\n"
"lines"
msgstr ""
"Deux\\n"
"lignes"

#, fuzzy
msgid "Fuzzy"
msgstr "Flou"

msgid "Untranslated"
msgstr ""

msgid "Saved to %1"
msgstr "Enregistré dans %1"

#~ msgid "Gone"
#~ msgstr "Parti"
`;

test("looks up plain, context and multi-line entries", () => {
    const c = I18n.parsePo(PO);
    assert.equal(I18n.i18n(c, "Refresh"), "Actualisation");
    assert.equal(I18n.i18nc(c, "settings tab", "Data"), "Données");
    assert.equal(I18n.i18n(c, "Data"), "Data");
    assert.equal(I18n.i18n(c, "Two\nlines"), "Deux\nlignes");
});

test("falls back to English for fuzzy, untranslated, obsolete and unknown", () => {
    const c = I18n.parsePo(PO);
    assert.equal(I18n.i18n(c, "Fuzzy"), "Fuzzy");
    assert.equal(I18n.i18n(c, "Untranslated"), "Untranslated");
    assert.equal(I18n.i18n(c, "Gone"), "Gone");
    assert.equal(I18n.i18n(I18n.empty(), "Refresh"), "Refresh");
});

test("substitutes arguments and picks plural forms by the catalog's rule", () => {
    const c = I18n.parsePo(PO);
    assert.equal(I18n.i18n(c, "Saved to %1", "/tmp/x"), "Enregistré dans /tmp/x");
    assert.equal(I18n.i18np(c, "%1 session", "%1 sessions", 0), "0 session");
    assert.equal(I18n.i18np(c, "%1 session", "%1 sessions", 1), "1 session");
    assert.equal(I18n.i18np(c, "%1 session", "%1 sessions", 5), "5 sessions");
    assert.equal(I18n.i18np(I18n.empty(), "%1 session", "%1 sessions", 1), "1 session");
    assert.equal(I18n.i18np(I18n.empty(), "%1 session", "%1 sessions", 0), "0 sessions");
});

test("refuses a plural rule that is not arithmetic", () => {
    const c = I18n.parsePo(PO.replace("plural=(n > 1);", "plural=alert(1);"));
    assert.equal(c.plural, null);
    assert.equal(I18n.i18np(c, "%1 session", "%1 sessions", 5), "5 sessions");
});

test("turns locale names into .po candidates", () => {
    assert.deepEqual(I18n.languageCandidates(["fr-FR", "fr", "en-US"]), ["fr_FR", "fr", "en_US", "en"]);
    assert.deepEqual(I18n.languageCandidates(["de_DE.UTF-8", "C", ""]), ["de_DE", "de"]);
});

test("reads the shipped French catalog completely", () => {
    const po = path.join(__dirname, "..", "translate", "fr.po");
    const c = I18n.parsePo(fs.readFileSync(po, "utf8"));
    assert.ok(Object.keys(c.messages).length > 200);
    assert.equal(c.plural(1), 0);
    assert.equal(c.plural(2), 1);
    assert.equal(I18n.i18np(c, "%1 provider", "%1 providers", 3), "3 fournisseurs");
});

// The shared state's tr(): backend fields arrive with their template beside
// them (backend/aiusage/messages.py) and are translated with the same catalog.
function sharedTr(catalog) {
    const source = fs.readFileSync(path.join(__dirname, "..", "ui", "AppState.qml"), "utf8");
    const block = name => {
        const start = source.indexOf("    function " + name + "(");
        const end = source.indexOf("\n    }", start);
        return source.slice(start, end + 6);
    };
    const root = { catalog, i18n: (...args) => I18n.i18n(catalog, ...args) };
    vm.runInNewContext(`${block("tr")}\n${block("trMessage")}\nroot.tr = tr; root.trMessage = trMessage;`, { root, I18n });
    return root.tr;
}

test("backend fields translate through their message templates", () => {
    const c = I18n.parsePo(fs.readFileSync(path.join(__dirname, "..", "translate", "fr.po"), "utf8"));
    const tr = sharedTr(c);
    const row = {
        label: "5-hour session",
        labelI18n: { id: "5-hour session", args: [] },
        detail: "120 / 500 tokens",
        detailI18n: { id: "%1 / %2 tokens", args: ["120", "500"] },
        tooltip: "Cursor\nIncluded usage: 40%",
        tooltipI18n: { lines: [{ id: "Cursor", args: [], plain: true }, { id: "Included usage: %1%", args: ["40"] }] },
        error: "Claude not logged in",
        note: "",
    };
    assert.equal(tr(row, "label"), "Session de 5 heures");
    assert.equal(tr(row, "detail"), "120 / 500 jetons");
    assert.equal(tr(row, "tooltip").split("\n")[0], "Cursor");
    // No template: the English text itself is looked up.
    assert.equal(tr(row, "error"), "Claude n'est pas connecté");
    assert.equal(tr(row, "note"), "");
    assert.equal(tr(null, "label"), "");
    // Text the catalog does not know stays as it is.
    assert.equal(tr({ detail: "max" }, "detail"), "max");
});
