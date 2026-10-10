const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

// ui/js/*.js are QML "pragma library" files: plain JavaScript once the pragma
// is dropped, loaded here the way the other shared-code tests do.
function load(name) {
    const source = fs.readFileSync(path.join(__dirname, "..", "ui", "js", name), "utf8").replace(/^\.pragma library/m, "");
    const sandbox = {};
    vm.runInNewContext(source, sandbox);
    return sandbox;
}

// Results come from another realm, so compare them as plain JSON.
const plain = (value) => JSON.parse(JSON.stringify(value));
const S = load("ProviderSources.js");
const option = (id, state) => ({ id, kind: "cli", label: `label ${id}`, detail: "", state });
const snapshot = (over) => ({ ok: true, error: "", sources: { choice: true, selected: "auto", active: "cli", options: [option("cli", "working"), option("ide", "ready")] }, ...over });

test("choices are Auto plus every source, and none when they are not alternatives", () => {
    assert.deepEqual(plain(S.choices(snapshot())), ["auto", "cli", "ide"]);
    assert.deepEqual(plain(S.choices(snapshot({ sources: { choice: false, options: [option("a", "working")] } }))), []);
    assert.deepEqual(plain(S.choices({ ok: true })), []);
    assert.deepEqual(plain(S.choices(null)), []);
});

test("the row says which source is answering", () => {
    assert.deepEqual(plain(S.statusLine(snapshot())), { code: "using", label: "label cli", text: "" });
});

test("a failing source is named with its error", () => {
    const line = S.statusLine(snapshot({ ok: false, error: "login expired" }));
    assert.equal(line.code, "failing");
    assert.equal(line.label, "label cli");
    assert.equal(line.text, "login expired");
});

test("nothing set up reads as not set up, with the provider's own error", () => {
    const line = S.statusLine(snapshot({ ok: false, error: "Cursor: no login", sources: { choice: true, active: "", options: [option("cli", "missing")] } }));
    assert.equal(line.code, "unset");
    assert.equal(line.text, "Cursor: no login");
});

test("a provider read one way is simply working, failing, or waiting", () => {
    assert.equal(S.statusLine({ ok: true }).code, "ok");
    assert.deepEqual(plain(S.statusLine({ ok: false, error: "no key" })), { code: "error", label: "", text: "no key" });
    assert.equal(S.statusLine(null).code, "waiting");
    assert.equal(S.statusLine(undefined).code, "waiting");
});

test("state tones are known, and an unknown state is dim", () => {
    assert.equal(S.stateTone("working"), "ok");
    assert.equal(S.stateTone("failing"), "bad");
    assert.equal(S.stateTone("ready"), "muted");
    assert.equal(S.stateTone("browser-future-state"), "dim");
});

test("the picker hides added providers, matches every word on name or id, and sorts A to Z", () => {
    const providers = [
        { id: "kimi", label: "Kimi" },
        { id: "zai", label: "Z.AI" },
        { id: "claude", label: "Claude" },
        { id: "cursor", label: "Cursor" },
    ];
    const on = (id) => id === "claude";
    assert.deepEqual(S.pickable(providers, "", on).map((p) => p.id), ["cursor", "kimi", "zai"]);
    assert.deepEqual(S.pickable(providers, "  CUR ", on).map((p) => p.id), ["cursor"]);
    assert.deepEqual(S.pickable(providers, "z.ai", on).map((p) => p.id), ["zai"]);
    assert.deepEqual(S.pickable(providers, "zai", on).map((p) => p.id), ["zai"]);
    assert.deepEqual(plain(S.pickable(providers, "nothing", on)), []);
    assert.deepEqual(plain(S.pickable(null, "x", on)), []);
});

test("the list keeps the registry order and only the added providers", () => {
    const providers = [{ id: "b" }, { id: "a" }, { id: "c" }];
    assert.deepEqual(S.added(providers, (id) => id !== "a").map((p) => p.id), ["b", "c"]);
});
