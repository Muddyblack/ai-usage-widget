const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const { execFile } = require("node:child_process");
const { promisify } = require("node:util");
const UsageHistory = require("../package/contents/code/UsageHistory.js");
const rootDir = path.resolve(__dirname, "..");

// Execute the production QML adapter functions, without starting the desktop
// shell or its network polling. No copies of their mapping logic live here.
function qmlFunction(file, name) {
    const source = fs.readFileSync(path.join(rootDir, file), "utf8");
    const start = source.indexOf("    function " + name + "(");
    assert.notEqual(start, -1, name);
    const end = source.indexOf("\n    }", start);
    assert.notEqual(end, -1, name);
    return source.slice(start, end + 6);
}
const plasma = qmlFunction("package/contents/ui/main.qml", "applyOpenAi");
const windows = ["providerById", "activeProvider", "pillProvider", "publishTray"]
    .map(name => qmlFunction("windows/qml/Main.qml", name)
        + "\nroot." + name + " = " + name + ";")
    .join("\n");

function publishWindowsTray(state) {
    let published;
    const root = { providers: [], settings: {}, providerIcon: () => "", ...state };
    const backend = { defaultTrayStyle: "numbers", publishTrayState: value => { published = JSON.parse(value); } };
    vm.runInNewContext(windows + "\nroot.publishTray();", { root, backend });
    return published;
}

test("shared frontend behavior", async t => {
    const { stdout } = await promisify(execFile)(process.env.PYTHON || "python3",
        [path.join(rootDir, "scripts/frontend-fixtures.py")]);
    const cases = JSON.parse(stdout);
    for (const scenario of cases) {
        await t.test(scenario.name + ": Plasma quota state and shared history", () => {
            const provider = scenario.envelope.providers[0];
            const root = { dateFromEpoch: x => x, ensureAvailableChartWindow() {} };
            vm.runInNewContext(plasma + "\napplyOpenAi(details);", { root, details: provider.details || {} });
            assert.equal(root.codexSessionAvailable, scenario.expected.rowKeys.includes("codex_session"));
            assert.equal(root.codexWeeklyAvailable, scenario.expected.rowKeys.includes("codex_weekly"));
            const values = [];
            if (root.codexSessionAvailable) values.push(root.codexSessionPct);
            if (root.codexWeeklyAvailable) values.push(root.codexWeeklyPct);
            assert.deepEqual(values.map(v => Math.round(v) + "%"), scenario.expected.panelText);
            const additional = root.codexAdditionalLimits.flatMap(entry =>
                [entry.session, entry.weekly].filter(window => window.available).map(window => window.pct));
            assert.deepEqual(values.concat(additional), scenario.expected.rowValues);
            assert.deepEqual(UsageHistory.collect([provider]), scenario.expected.history);
        });

        await t.test(scenario.name + ": Windows tray publication", () => {
            const provider = scenario.envelope.providers[0];
            const published = publishWindowsTray({
                activeId: provider.id, activeIsFeature: false, providers: [provider]
            });
            assert.deepEqual(published.slots.map(s => s.text || Math.round(s.pct) + "%"), scenario.expected.panelText);
        });
    }
});


test("Windows tray keeps provider usage while a feature tab is active", () => {
    const providers = [
        { id: "claude", label: "Claude", slots: [{ pct: 25 }] },
        { id: "openai", label: "OpenAI", slots: [{ pct: 70 }] }
    ];
    for (const activeId of ["overview", "spend", "sessions"]) {
        const state = { activeId, activeIsFeature: true, providers, lastProviderId: "openai" };
        assert.deepEqual(publishWindowsTray(state).slots.map(s => s.pct), [70]);
        assert.deepEqual(publishWindowsTray({ ...state, lastProviderId: "removed" }).slots.map(s => s.pct), [25]);
        assert.deepEqual(publishWindowsTray({ ...state, providers: [] }).slots, []);
    }
});
