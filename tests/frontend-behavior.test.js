const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const { execFile } = require("node:child_process");
const { promisify } = require("node:util");
const UsageHistory = require("../package/contents/code/UsageHistory.js");
const SessionSources = require("../package/contents/code/SessionSources.js");
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

function qmlFunctionBlock(file, name) {
    const source = fs.readFileSync(path.join(rootDir, file), "utf8");
    const start = source.indexOf("function " + name + "(");
    assert.notEqual(start, -1, `${file}: ${name}`);
    const opening = source.indexOf("{", start);
    assert.notEqual(opening, -1, `${file}: ${name} body`);
    let depth = 0;
    for (let index = opening; index < source.length; index++) {
        if (source[index] === "{") depth += 1;
        if (source[index] === "}") {
            depth -= 1;
            if (depth === 0) return source.slice(start, index + 1);
        }
    }
    assert.fail(`${file}: unterminated ${name}`);
}

function qmlSource(file) {
    return fs.readFileSync(path.join(rootDir, file), "utf8");
}

function countOccurrences(source, text) {
    return source.split(text).length - 1;
}

function replaySourcePopupSelection(file, owner) {
    const sources = [
        { id: "codex", label: "Codex" },
        { id: "claude", label: "Claude" },
        { id: "muse", label: "Muse" },
        { id: "cline", label: "Cline" }
    ];
    const state = {
        sessionSources: sources,
        selectedSourceIds: ["codex"],
        pendingSourceIds: ["codex"],
        sessions: ["existing row"],
        searchQuery: "",
        queryCount: 0,
        querySourceIds: [],
        loading: false,
        normalizedSourceIds: ids => SessionSources.normalizeIds(ids, sources),
        sourceSignature: ids => SessionSources.signature(ids),
        queryOnly: () => {
            state.queryCount += 1;
            state.querySourceIds.push(state.selectedSourceIds.slice(0));
            state.loading = true;
        }
    };
    const sandbox = { [owner]: state, SessionSources };
    if (owner === "page") {
        sandbox.shell = {
            setSessionsSourceIds: ids => {
                state.selectedSourceIds = SessionSources.normalizeIds(ids, sources);
            },
            querySessions: () => {
                state.queryCount += 1;
                state.querySourceIds.push(state.selectedSourceIds.slice(0));
                state.loading = true;
            }
        };
    }
    const functions = ["setSourceSelection", "stageSourceSelection", "commitSourceSelection", "stageToggleSource"]
        .map(name => qmlFunctionBlock(file, name))
        .join("\n");
    vm.runInNewContext(`${functions}
        ${owner}.setSourceSelection = setSourceSelection;
        ${owner}.stageSourceSelection = stageSourceSelection;
        ${owner}.commitSourceSelection = commitSourceSelection;
        ${owner}.stageToggleSource = stageToggleSource;`, sandbox);
    return state;
}

function assertSourcePopupWiring(file, owner) {
    const source = qmlSource(file);
    assert.match(source, new RegExp(`onOpened:\\s*(?:\\{\\s*)?${owner}\\.pendingSourceIds = ${owner}\\.selectedSourceIds\\.slice\\(0\\);?\\s*(?:\\})?`, "s"));
    assert.match(source, new RegExp(`onClosed:\\s*(?:\\{\\s*)?${owner}\\.commitSourceSelection\\(\\);?\\s*(?:\\})?`, "s"));
    assert.match(source, new RegExp(`checked: [^\\n]*${owner}\\.pendingSourceIds`));
    assert.doesNotMatch(qmlFunctionBlock(file, "stageToggleSource"), /queryOnly|querySessions/);
    assert.match(source, /ScrollView|Flickable/);
    assert.match(source, /availableHeight|maximumHeight|height: Math\.min/);
}

test("source popup stages multiple selections and commits once on close", () => {
    const frontends = [
        {
            file: "package/contents/ui/SessionsTab.qml",
            owner: "sessionsTab"
        },
        {
            file: "hyprland/SessionsPage.qml",
            owner: "page"
        }
    ];
    for (const frontend of frontends) {
        assertSourcePopupWiring(frontend.file, frontend.owner);
        const state = replaySourcePopupSelection(frontend.file, frontend.owner);

        state.stageToggleSource("claude", true);
        state.stageToggleSource("muse", true);
        assert.deepEqual(state.pendingSourceIds, ["codex", "claude", "muse"]);
        assert.deepEqual(state.selectedSourceIds, ["codex"]);
        assert.equal(state.queryCount, 0);
        assert.deepEqual(state.sessions, ["existing row"]);

        state.commitSourceSelection();
        assert.deepEqual(state.selectedSourceIds, ["codex", "claude", "muse"]);
        assert.equal(state.queryCount, 1);
        assert.deepEqual(state.querySourceIds, [["codex", "claude", "muse"]]);
        assert.deepEqual(state.sessions, ["existing row"]);

        state.commitSourceSelection();
        assert.equal(state.queryCount, 1);
    }
});

test("source changes keep normal rows and preserve stale-response recovery clears", () => {
    const kde = qmlSource("package/contents/ui/SessionsTab.qml");
    const hyprland = qmlSource("hyprland/AiUsageShell.qml");
    const windows = qmlSource("windows/qml/Main.qml");

    assert.doesNotMatch(qmlFunctionBlock("package/contents/ui/SessionsTab.qml", "setSourceSelection"), /sessionsTab\.sessions\s*=\s*\[\]/);
    assert.doesNotMatch(qmlFunctionBlock("hyprland/AiUsageShell.qml", "setSessionsSourceIds"), /root\.sessions\s*=\s*\[\]/);
    assert.doesNotMatch(qmlFunctionBlock("windows/qml/Main.qml", "setSessionsSourceIds"), /root\.sessions\s*=\s*\[\]/);

    assert.equal(countOccurrences(kde, "sessionsTab.sessions = [];"), 1);
    assert.equal(countOccurrences(hyprland, "root.sessions = [];"), 1);
    assert.equal(countOccurrences(windows, "root.sessions = [];"), 1);
});
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


test("KDE source popup stages selection and queries only on close", () => {
    const state = replaySourcePopupSelection("package/contents/ui/SessionsTab.qml", "sessionsTab");
    state.pendingSourceIds = state.selectedSourceIds.slice(0);
    state.stageSourceSelection(SessionSources.toggled(state.pendingSourceIds, "claude", true, state.sessionSources));
    assert.equal(state.queryCount, 0, "no query while the popup is open");
    assert.deepEqual(state.sessions, ["existing row"], "rows stay visible while the popup is open");
    state.commitSourceSelection();
    assert.equal(state.queryCount, 1, "one query after the popup closes");
    assert.deepEqual(state.selectedSourceIds, ["codex", "claude"]);
    assert.deepEqual(state.sessions, ["existing row"], "rows stay visible until the response replaces them");
});

test("KDE source popup close without changes does not query", () => {
    const state = replaySourcePopupSelection("package/contents/ui/SessionsTab.qml", "sessionsTab");
    state.pendingSourceIds = state.selectedSourceIds.slice(0);
    state.commitSourceSelection();
    assert.equal(state.queryCount, 0);
    assert.deepEqual(state.selectedSourceIds, ["codex"]);
});

test("KDE source popup coalesces multiple checkbox clicks into one query", () => {
    const state = replaySourcePopupSelection("package/contents/ui/SessionsTab.qml", "sessionsTab");
    state.pendingSourceIds = state.selectedSourceIds.slice(0);
    state.stageSourceSelection(SessionSources.toggled(state.pendingSourceIds, "claude", true, state.sessionSources));
    state.stageSourceSelection(SessionSources.toggled(state.pendingSourceIds, "muse", true, state.sessionSources));
    state.stageSourceSelection(SessionSources.toggled(state.pendingSourceIds, "claude", false, state.sessionSources));
    assert.equal(state.queryCount, 0);
    state.commitSourceSelection();
    assert.equal(state.queryCount, 1);
    assert.deepEqual(state.selectedSourceIds, ["codex", "muse"]);
});

test("shared Hyprland/Windows page stages source selection until popup close", () => {
    const state = replaySourcePopupSelection("hyprland/SessionsPage.qml", "page");
    state.pendingSourceIds = state.selectedSourceIds.slice(0);
    state.stageSourceSelection(SessionSources.toggled(state.pendingSourceIds, "claude", true, state.sessionSources));
    assert.equal(state.queryCount, 0, "no query while the popup is open");
    assert.deepEqual(state.sessions, ["existing row"], "rows stay visible while the popup is open");
    state.commitSourceSelection();
    assert.equal(state.queryCount, 1, "one query after the popup closes");
    assert.deepEqual(state.selectedSourceIds, ["codex", "claude"]);
});

test("shared Hyprland/Windows page close without changes does not query", () => {
    const state = replaySourcePopupSelection("hyprland/SessionsPage.qml", "page");
    state.pendingSourceIds = state.selectedSourceIds.slice(0);
    state.commitSourceSelection();
    assert.equal(state.queryCount, 0);
});
