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
const FeatureTabs = {};
vm.runInNewContext(
    fs.readFileSync(path.join(rootDir, "package/contents/code/FeatureTabs.js"), "utf8")
        .replace(/^\.pragma library\s*/, ""),
    FeatureTabs,
);

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
const plasmaCost = qmlFunction("package/contents/ui/SessionsTab.qml", "sessionCostText");
const hyprlandCost = qmlFunction("hyprland/SessionsPage.qml", "sessionCostText");
const spendTabSource = fs.readFileSync(path.join(rootDir, "package/contents/ui/SpendTab.qml"), "utf8");
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

function renderSessionCost(source, entry, usesShell) {
    const replace = (text, ...values) => text.replace(/%(\d)/g, (all, index) => values[Number(index) - 1] ?? all);
    const context = usesShell
        ? { root: {}, shell: { i18n: replace }, FeatureTabs }
        : { root: {}, i18n: replace, FeatureTabs };
    vm.runInNewContext(source + "\nroot.sessionCostText = sessionCostText;", context);
    return context.root.sessionCostText(entry);
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

test("local spend rows merge actual and estimated costs by source", () => {
    const rows = FeatureTabs.localSpendRows({
        actual: {
            totalUSD: 12.34,
            costStatus: "exact",
            providers: {
                OpenCode: { costUSD: 12.34, costStatus: "exact" },
            },
        },
        estimated: {
            totalUSD: 2.5,
            costStatus: "partial",
            providers: {
                " opencode ": { costUSD: 1.5, costStatus: "partial" },
                cline: { costUSD: 1, costStatus: "exact" },
            },
        },
    });

    assert.deepEqual(JSON.parse(JSON.stringify(rows.map(row => ({
        id: row.id,
        label: row.label,
        cost: row.cost,
        local: row.local,
        provenance: row.provenance,
        costStatus: row.costStatus,
        costBreakdown: row.costBreakdown,
        note: row.note,
    })))), [
        {
            id: "local-opencode",
            label: "OpenCode",
            cost: 13.84,
            local: true,
            provenance: "mixed",
            costStatus: "partial",
            costBreakdown: { actualUSD: 12.34, estimatedUSD: 1.5 },
            note: "local CLI logs · mixed · partial",
        },
        {
            id: "local-cline",
            label: "Cline",
            cost: 1,
            local: true,
            provenance: "estimated",
            costStatus: "exact",
            costBreakdown: { actualUSD: 0, estimatedUSD: 1 },
            note: "local CLI logs · estimated · exact",
        },
    ]);

    assert.equal(FeatureTabs.spendTotal([
        { id: "openai", cost: 4, currency: "USD" },
        ...rows,
    ], "USD"), 4);
});

test("OpenCode local rows retain separate upstream billing providers", () => {
    const rows = FeatureTabs.localSpendRows({
        actual: {
            totalUSD: 0.13,
            costStatus: "exact",
            providers: {
                "openai::opencode": { costUSD: 0.13, costStatus: "exact", source: "opencode" },
            },
        },
        estimated: {
            totalUSD: 0.42,
            costStatus: "exact",
            providers: {
                "anthropic::opencode": { costUSD: 0.42, costStatus: "exact", source: "opencode" },
            },
        },
    });

    assert.deepEqual(JSON.parse(JSON.stringify(rows.map(row => ({
        id: row.id,
        label: row.label,
        cost: row.cost,
        source: row.source,
        note: row.note,
    })))), [
        { id: "local-opencode-openai", label: "OpenAI", cost: 0.13, source: "opencode", note: "via OpenCode · actual · exact" },
        { id: "local-opencode-anthropic", label: "Anthropic", cost: 0.42, source: "opencode", note: "via OpenCode · estimated · exact" },
    ]);
});

test("local spend rows keep legacy flat totals and reject unavailable groups", () => {
    assert.equal(FeatureTabs.localSpendRows({
        actual: { totalUSD: 1, costStatus: "unavailable" },
        estimated: { totalUSD: Infinity, costStatus: "exact" },
    }).length, 0);

    assert.equal(FeatureTabs.localSpendRows({
        actual: { totalUSD: 1, costStatus: "exact" },
        estimated: { totalUSD: 2, costStatus: "partial" },
    }).length, 0);

    const legacy = FeatureTabs.localSpendRows({ totalUSD: 3.5, costStatus: "partial" });
    assert.deepEqual({ ...legacy[0] }, {
        id: "local",
        label: "Local sessions",
        cost: 3.5,
        currency: "USD",
        note: "local CLI logs · partial",
        local: true,
        legacy: true,
        costStatus: "partial",
    });

    for (const localSpend of [
        { actual: { totalUSD: 0, costStatus: "exact" } },
        { actual: { totalUSD: -1, costStatus: "partial" } },
        { actual: { totalUSD: "3.5", costStatus: "exact" } },
        { totalUSD: NaN, costStatus: "exact" },
        null,
    ]) {
        assert.equal(FeatureTabs.localSpendRows(localSpend).length, 0);
    }
});

test("local source labels normalize known IDs and safe fallbacks", () => {
    assert.equal(FeatureTabs.localSourceLabel(" OPENAI "), "Codex");
    assert.equal(FeatureTabs.localSourceLabel("claude_code"), "Claude Code");
    assert.equal(FeatureTabs.localSourceLabel("custom_source"), "Custom Source");
    assert.equal(FeatureTabs.localSourceLabel("  "), "Local source");
});

test("upstream provider labels cover every OpenCode-routed provider", () => {
    assert.equal(FeatureTabs.upstreamProviderLabel("ollama-cloud"), "Ollama Cloud");
    assert.equal(FeatureTabs.upstreamProviderLabel("ollama"), "Ollama");
    assert.equal(FeatureTabs.upstreamProviderLabel("github-copilot"), "GitHub Copilot");
    assert.equal(FeatureTabs.upstreamProviderLabel("google"), "Google");
    assert.equal(FeatureTabs.upstreamProviderLabel("zenmux"), "ZenMux");
    assert.equal(FeatureTabs.upstreamProviderLabel("opencode"), "OpenCode Zen");
    assert.equal(FeatureTabs.upstreamProviderLabel("anthropic"), "Anthropic");
});

test("spend views identify provider totals and constrain local metadata", () => {
    for (const file of ["package/contents/ui/SpendTab.qml", "hyprland/SpendPage.qml"]) {
        const source = fs.readFileSync(path.join(rootDir, file), "utf8");
        assert.match(source, /Provider\/API total/);
        assert.match(source, /maximumLineCount: 1/);
        assert.match(source, /elide: Text\.ElideRight/);
        assert.match(source, /wrapMode: Text\.NoWrap/);
    }
});

test("provider spend rows and totals remain provider-only", () => {
    const rows = FeatureTabs.spendProviderRows([
        {
            id: "claude",
            label: "Claude",
            details: { organizationUsage: { totalCostUSD: 4.5 } },
            accent: "#cc785c",
        },
        {
            id: "openai",
            label: "OpenAI",
            details: { organizationUsage: { totalCostUSD: 2 } },
            accent: "#10a37f",
        },
        {
            id: "openrouter",
            label: "OpenRouter",
            details: { usageUSD: 3 },
            accent: "#9333ea",
        },
        {
            id: "muse",
            label: "Muse",
            details: { stats: { totalCostUSD: 0 } },
            accent: "#0064e0",
        },
    ]);

    assert.deepEqual(Array.from(rows, row => ({ ...row })), [
        {
            id: "claude",
            label: "Claude",
            accent: "#cc785c",
            icon: "",
            cost: 4.5,
            currency: "USD",
            note: "30d API",
        },
        {
            id: "openrouter",
            label: "OpenRouter",
            accent: "#9333ea",
            icon: "",
            cost: 3,
            currency: "USD",
            note: "all-time",
        },
        {
            id: "openai",
            label: "OpenAI",
            accent: "#10a37f",
            icon: "",
            cost: 2,
            currency: "USD",
            note: "30d API",
        },
    ]);
    assert.equal(FeatureTabs.spendTotal(rows, "USD"), 9.5);
});

test("provider spend rows reject non-finite and non-numeric reported values", () => {
    const malformed = [
        { id: "claude", details: { organizationUsage: { totalCostUSD: Infinity } } },
        { id: "openai", details: { organizationUsage: { totalCostUSD: NaN } } },
        { id: "openrouter", details: { usageUSD: "3.25" } },
        { id: "mistral", details: { vibe: { totalCost: true } } },
    ];
    assert.equal(FeatureTabs.spendProviderRows(malformed).length, 0);

    const validAndMalformed = [
        { id: "openai", label: "OpenAI", details: { totalCostUSD: 2 } },
        { id: "claude", label: "Claude", details: { totalCostUSD: 4.5 } },
        { id: "openrouter", details: { usageUSD: Infinity } },
        { id: "mistral", details: { totalCost: "8" } },
        { id: "muse", details: { stats: { totalCostUSD: false } } },
    ];
    const rows = FeatureTabs.spendProviderRows(validAndMalformed);
    assert.deepEqual(Array.from(rows, row => [row.id, row.cost]), [
        ["claude", 4.5],
        ["openai", 2],
    ]);
    assert.equal(FeatureTabs.spendTotal(rows, "USD"), 6.5);
});

test("spend totals ignore non-numeric and non-finite row costs", () => {
    const rows = [
        { currency: "USD", cost: 4 },
        { currency: "USD", cost: 2 },
        { currency: "USD", cost: Infinity },
        { currency: "USD", cost: NaN },
        { currency: "USD", cost: "8" },
        { currency: "USD", cost: true },
        { currency: "EUR", cost: 99 },
    ];
    assert.equal(FeatureTabs.spendTotal(rows, "USD"), 6);
    assert.equal(FeatureTabs.spendTotal(rows, "EUR"), 99);
});

test("spend rows keep long text from moving the amount and center it vertically", () => {
    const rowStart = spendTabSource.indexOf("        Rectangle {\n            required property var modelData");
    assert.notEqual(rowStart, -1);
    const row = spendTabSource.slice(rowStart);
    const bodyStart = row.indexOf("            RowLayout {");
    const bodyEnd = row.indexOf("            MouseArea {", bodyStart);
    assert.notEqual(bodyStart, -1);
    assert.notEqual(bodyEnd, -1);
    const body = row.slice(bodyStart, bodyEnd);
    assert.match(body, /ColumnLayout \{[\s\S]*Layout\.fillWidth: true\s+Layout\.minimumWidth: 0/);
    assert.match(body, /PlasmaComponents\.Label \{[\s\S]*?text: rootItem\.formatMoney[\s\S]*font\.family: "monospace"/);
});

test("spend prices align their decimal points with fixed-width digits", () => {
    // Two-decimal amounts plus fixed-width digits put "." in one column.
    for (const file of ["package/contents/ui/SpendTab.qml", "hyprland/SpendPage.qml"]) {
        const source = fs.readFileSync(path.join(rootDir, file), "utf8");
        assert.match(source, /font\.family: "monospace"/);
        assert.doesNotMatch(source, /Layout\.preferredWidth: 60/);
        assert.doesNotMatch(source, /Layout\.maximumWidth: 60/);
        assert.doesNotMatch(source, /horizontalAlignment: Text\.AlignLeft/);
    }
});

test("session rows render provenance, coverage, unavailable, and legacy costs", () => {
    const cases = [
        [{ costStatus: "exact", costProvenance: "actual", costUSD: 0.123456 }, "Actual provider cost: $0.1235 (exact)"],
        [{ costStatus: "partial", costProvenance: "actual", costUSD: 0.123456 }, "Actual provider cost: $0.1235 (partial)"],
        [{ costStatus: "exact", costProvenance: "estimated", costUSD: 0.123456 }, "Calculated estimate: $0.1235 (exact)"],
        [{ costStatus: "partial", costProvenance: "estimated", costUSD: 0.123456 }, "Calculated estimate: $0.1235 (partial)"],
        [{ costStatus: "exact", costProvenance: "mixed", costUSD: 0.123456, costBreakdown: { actualUSD: 0.1, estimatedUSD: 0.023456 } }, "Mixed cost: $0.1235 (exact)"],
        [{ costStatus: "partial", costProvenance: "mixed", costUSD: 0.123456, costBreakdown: { actualUSD: 0.1, estimatedUSD: 0.023456 } }, "Mixed cost: $0.1235 (partial)"],
        [{ costStatus: "exact", costUSD: 0.123456 }, "Cost: $0.1235 (exact)"],
        [{ costStatus: "unavailable" }, "Cost unavailable"],
        [{ costStatus: "exact", costProvenance: "unknown", costUSD: 0.123456 }, "Cost unavailable"],
        [{ costStatus: "exact", costProvenance: "actual", costUSD: "0.123456" }, "Cost unavailable"],
    ];
    for (const [entry, expected] of cases) {
        assert.equal(renderSessionCost(plasmaCost, entry, false), expected);
        assert.equal(renderSessionCost(hyprlandCost, entry, true), expected);
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
