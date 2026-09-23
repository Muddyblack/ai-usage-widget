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

function spendDateDaysAgo(days) {
    const now = new Date();
    const date = new Date(Date.UTC(now.getFullYear(), now.getMonth(), now.getDate()));
    date.setUTCDate(date.getUTCDate() - days);
    return date.toISOString().slice(0, 10);
}

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
    // Either a QQC2.CheckBox `checked:` binding or a custom row's `isChecked:`
    // — both must read the staged selection, not the committed one.
    assert.match(source, new RegExp(`(?:checked|isChecked): [^\\n]*${owner}\\.pendingSourceIds`));
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
test("QML scrollbars explicitly create horizontal attached objects", () => {
    for (const file of ["SpendTab.qml", "MistralTab.qml", "SessionsTab.qml"]) {
        const source = fs.readFileSync(path.join(rootDir, "package/contents/ui", file), "utf8");
        assert.doesNotMatch(source, /ScrollBar\.horizontal\.policy/);
        assert.match(source, /ScrollBar\.horizontal:\s+QQC2\.ScrollBar\s*\{/);
    }
});
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
    // The grand total sits in each frontend's popup header, not in the Spend
    // view itself, so the figure stays visible while the view scrolls.
    for (const file of ["package/contents/ui/main.qml", "hyprland/PopupContent.qml"]) {
        assert.match(fs.readFileSync(path.join(rootDir, file), "utf8"), /Provider\/API total/);
    }
    for (const file of ["package/contents/ui/SpendTab.qml", "hyprland/SpendPage.qml"]) {
        const source = fs.readFileSync(path.join(rootDir, file), "utf8");
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

    assert.deepEqual(Array.from(rows, row => ({ ...row, dailyCost: [...row.dailyCost], dailyTokens: [...row.dailyTokens] })), [
        {
            id: "claude",
            label: "Claude",
            accent: "#cc785c",
            icon: "",
            cost: 4.5,
            currency: "USD",
            note: "30d API",
            dailyCost: [],
            dailyTokens: [],
        },
        {
            id: "openrouter",
            label: "OpenRouter",
            accent: "#9333ea",
            icon: "",
            cost: 3,
            currency: "USD",
            note: "all-time",
            dailyCost: [],
            dailyTokens: [],
        },
        {
            id: "openai",
            label: "OpenAI",
            accent: "#10a37f",
            icon: "",
            cost: 2,
            currency: "USD",
            note: "30d API",
            dailyCost: [],
            dailyTokens: [],
        },
    ]);
    assert.equal(FeatureTabs.spendTotal(rows, "USD"), 9.5);
});

test("provider spend rows take cost-by-day from sessions and tokens-by-day from stats", () => {
    // A provider blob only ever carries totals; per-day cost lives on the
    // session rollups, which is also the only place plan-covered work has a
    // non-zero figure.
    const rows = FeatureTabs.spendProviderRows(
        [
            {
                id: "claude",
                label: "Claude",
                details: {
                    organizationUsage: { totalCostUSD: 4.5 },
                    stats: { dailySeries: [{ date: "2026-01-01", total: 100 }] },
                },
            },
            {
                id: "openai",
                label: "OpenAI",
                details: { organizationUsage: { totalCostUSD: 2 } },
            },
        ],
        {
            subscription: {
                costStatus: "exact",
                providers: {
                    claude: {
                        costUSD: 4.5,
                        costStatus: "exact",
                        dailyUSD: [{ date: "2026-01-01", usd: 4.5 }],
                    },
                },
            },
        },
    );
    assert.deepEqual(Array.from(rows[0].dailyCost, x => ({ ...x })), [{ date: "2026-01-01", usd: 4.5 }]);
    assert.deepEqual(Array.from(rows[0].dailyTokens, x => ({ ...x })), [{ date: "2026-01-01", total: 100 }]);
    // No sessions for this provider, so no cost history — not a fake zero line.
    assert.deepEqual(Array.from(rows[1].dailyCost), []);
    assert.deepEqual(Array.from(rows[1].dailyTokens), []);
});

test("dailyCostByProvider merges every billing group and needs no per-provider code", () => {
    const daily = FeatureTabs.dailyCostByProvider({
        estimated: {
            providers: {
                grok: { dailyUSD: [{ date: "2026-01-01", usd: 1 }, { date: "2026-01-02", usd: 2 }] },
                "anthropic::opencode": { dailyUSD: [{ date: "2026-01-01", usd: 0.5 }] },
            },
        },
        subscription: {
            providers: { grok: { dailyUSD: [{ date: "2026-01-01", usd: 0.25 }] } },
        },
    });
    // Same provider in two groups sums per day; the "::source" rollup key
    // collapses onto the provider it belongs to.
    assert.deepEqual(Array.from(daily.grok, x => ({ ...x })), [
        { date: "2026-01-01", usd: 1.25 },
        { date: "2026-01-02", usd: 2 },
    ]);
    assert.deepEqual(Array.from(daily.anthropic, x => ({ ...x })), [{ date: "2026-01-01", usd: 0.5 }]);
});

test("spendTimeline zips cost and token series and can trim to a trailing window", () => {
    const cost = [
        { date: spendDateDaysAgo(2), usd: 1 },
        { date: spendDateDaysAgo(1), usd: 2 },
        { date: spendDateDaysAgo(0), usd: 3 },
    ];
    const tokens = [
        { date: spendDateDaysAgo(1), total: 20 },
        { date: spendDateDaysAgo(0), total: 30 },
    ];
    assert.deepEqual(Array.from(FeatureTabs.spendTimeline(cost, tokens, 0), x => ({ ...x })), [
        { date: spendDateDaysAgo(2), usd: 1, total: 0 },
        { date: spendDateDaysAgo(1), usd: 2, total: 20 },
        { date: spendDateDaysAgo(0), usd: 3, total: 30 },
    ]);
    assert.deepEqual(Array.from(FeatureTabs.spendTimeline(cost, tokens, 2), x => ({ ...x })), [
        { date: spendDateDaysAgo(1), usd: 2, total: 20 },
        { date: spendDateDaysAgo(0), usd: 3, total: 30 },
    ]);
    assert.deepEqual(Array.from(FeatureTabs.spendTimeline([], [], 30)), []);
});

test("spendTimeline clips tokens to the cost window so two histories never share one axis", () => {
    // Cost comes from session rows (recent), tokens from the provider's own
    // aggregate (older). Plotting the union drew a token line that stopped
    // exactly where the cost line started.
    const cost = [
        { date: "2026-08-22", usd: 5 },
        { date: "2026-08-23", usd: 7 },
    ];
    const tokens = [
        { date: "2026-04-07", total: 900 },
        { date: "2026-07-06", total: 800 },
        { date: "2026-08-23", total: 100 },
    ];
    const points = FeatureTabs.spendTimeline(cost, tokens, 0);

    assert.deepEqual(Array.from(points, x => ({ ...x })), [
        { date: "2026-08-22", usd: 5, total: 0 },
        { date: "2026-08-23", usd: 7, total: 100 },
    ]);
});

test("spendTimeline keeps the token range when a row has no cost history at all", () => {
    const points = FeatureTabs.spendTimeline([], [{ date: "2026-09-10", total: 5 }, { date: "2026-09-14", total: 9 }], 0);

    assert.deepEqual(Array.from(points, x => ({ ...x })), [
        { date: "2026-09-10", usd: 0, total: 5 },
        { date: "2026-09-14", usd: 0, total: 9 },
    ]);
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

test("spend timeframe filtering recomputes bounded rows and preserves ALL", () => {
    const rows = [{
        id: "claude",
        cost: 6,
        currency: "USD",
        dailyCost: [
            { date: spendDateDaysAgo(2), usd: 1 },
            { date: spendDateDaysAgo(1), usd: 2 },
            { date: spendDateDaysAgo(0), usd: 3 },
        ],
        dailyTokens: [
            { date: spendDateDaysAgo(2), total: 10 },
            { date: spendDateDaysAgo(1), total: 20 },
            { date: spendDateDaysAgo(0), total: 30 },
        ],
    }];

    const oneDay = FeatureTabs.spendRowsForWindow(rows, 1);
    const all = FeatureTabs.spendRowsForWindow(rows, 0);

    assert.equal(oneDay[0].cost, 3);
    assert.equal(JSON.stringify(oneDay[0].dailyCost), JSON.stringify([{ date: spendDateDaysAgo(0), usd: 3 }]));
    assert.equal(JSON.stringify(oneDay[0].dailyTokens), JSON.stringify([{ date: spendDateDaysAgo(0), total: 30 }]));
    assert.strictEqual(all, rows);
});

test("spend timeframe filtering zeroes out rows without bounded history instead of dropping them", () => {
    const rows = [{ id: "legacy", cost: 4, currency: "USD", dailyCost: [], dailyTokens: [] }];

    const sevenDays = FeatureTabs.spendRowsForWindow(rows, 7);
    assert.equal(sevenDays.length, 1);
    assert.equal(sevenDays[0].cost, 0);
    assert.equal(FeatureTabs.spendRowsForWindow(rows, 0)[0].cost, 4);
});

test("spend timeframe windows end today rather than at the last recorded day", () => {
    const today = new Date();
    const lastRecorded = new Date(Date.UTC(today.getFullYear(), today.getMonth(), today.getDate()));
    lastRecorded.setUTCDate(lastRecorded.getUTCDate() - 45);
    const staleDate = lastRecorded.toISOString().slice(0, 10);
    const rows = [{
        id: "stale",
        cost: 4,
        currency: "USD",
        dailyCost: [{ date: staleDate, usd: 4 }],
        dailyTokens: [{ date: staleDate, total: 40 }],
    }];

    const thirtyDays = FeatureTabs.spendRowsForWindow(rows, 30);
    assert.equal(thirtyDays.length, 1);
    assert.equal(thirtyDays[0].cost, 0);
    assert.equal(FeatureTabs.spendRowsForWindow(rows, 0)[0].cost, 4);
});

test("Plasma spend timeframe controls are global and fixed", () => {
    assert.match(spendTabSource, /property int spendWindowDays: 0/);
    assert.match(spendTabSource, /spendRowsForWindow/);
    assert.doesNotMatch(spendTabSource, /rootItem\.refresh\(\)/);

    for (const label of ["1D", "7D", "30D", "ALL"])
        assert.match(spendTabSource, new RegExp('text: "' + label + '"'));

    const chartSource = fs.readFileSync(path.join(rootDir, "package/contents/ui/SpendTimelineChart.qml"), "utf8");
    assert.doesNotMatch(chartSource, /i18n\("90d"\)/);
    assert.doesNotMatch(chartSource, /windowDaysSelected/);
});

test("spend rows keep long text from moving the amount and center it vertically", () => {
    const rowStart = spendTabSource.indexOf("        Rectangle {\n            id: rowCard\n            required property var modelData");
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


test("plan-covered spend is its own row and never joins the metered total", () => {
    const rows = FeatureTabs.localSpendRows({
        estimated: {
            costStatus: "exact",
            totalUSD: 2,
            providers: { cline: { costUSD: 2, costStatus: "exact", costProvenance: "estimated" } },
        },
        subscription: {
            costStatus: "exact",
            totalUSD: 100,
            providers: { claude: { costUSD: 100, costStatus: "exact", costProvenance: "estimated" } },
        },
    });

    const plan = rows.find((row) => row.billing === "subscription");
    const metered = rows.find((row) => row.billing !== "subscription");
    assert.ok(plan, "expected a plan-covered row");
    assert.equal(plan.cost, 100);
    assert.match(plan.note, /would cost on API/);
    assert.equal(metered.cost, 2);
    // Local rows never count toward the provider/API total either way.
    assert.equal(FeatureTabs.spendTotal(rows, "USD"), 0);
});

test("spend summary computes metered, plan-covered and all-inclusive totals", () => {
    const rows = [
        { id: "cursor", cost: 2.10, currency: "USD" },
        { id: "local-grok", cost: 2.37, currency: "USD", local: true },
        { id: "plan-claude", cost: 3966.35, currency: "USD", local: true, billing: "subscription" },
        { id: "plan-codex", cost: 1457.64, currency: "USD", local: true, billing: "subscription" },
    ];

    assert.equal(Math.round(FeatureTabs.spendMeteredTotal(rows, "USD") * 100) / 100, 4.47);
    assert.equal(Math.round(FeatureTabs.spendPlanTotal(rows, "USD") * 100) / 100, 5423.99);
    assert.equal(Math.round(FeatureTabs.spendAllTotal(rows, "USD") * 100) / 100, 5428.46);
    assert.equal(FeatureTabs.spendSummaryText(rows, "USD"), "Metered: $4.47 · Incl. plan: $5428.46");

    // Only plan-covered
    assert.equal(FeatureTabs.spendSummaryText([rows[2]], "USD"), "Incl. plan: $3966.35");

    // Only metered
    assert.equal(FeatureTabs.spendSummaryText([rows[0], rows[1]], "USD"), "Metered: $4.47");

    // Empty
    assert.equal(FeatureTabs.spendSummaryText([], "USD"), "");

    // Tooltip breakdown
    const tooltip = FeatureTabs.spendSummaryTooltip(rows, "USD");
    assert.match(tooltip, /Metered \(out-of-pocket\): \$4\.47/);
    assert.match(tooltip, /Covered by plan \(subscription\): \$5423\.99/);
    assert.match(tooltip, /Total including plan: \$5428\.46/);
});

test("a plan-covered row's daily cost adds up to the total shown on it", () => {
    // The whole point of sourcing cost from sessions: a Pro/Max plan reports
    // $0 of real API cost, so a chart built from provider stats sat flat at
    // zero under a four-figure total.
    const rawProviders = [
        { id: "claude", details: { stats: { dailySeries: [{ date: "2026-01-01", total: 500 }] } } },
    ];
    const rows = FeatureTabs.localSpendRows(
        {
            subscription: {
                costStatus: "exact",
                totalUSD: 100,
                providers: {
                    claude: {
                        costUSD: 100,
                        costStatus: "exact",
                        costProvenance: "estimated",
                        dailyUSD: [{ date: "2026-01-01", usd: 60 }, { date: "2026-01-02", usd: 40 }],
                    },
                },
            },
        },
        [],
        rawProviders,
    );
    const plan = rows.find((row) => row.billing === "subscription");
    assert.ok(plan, "expected a plan-covered row");
    assert.deepEqual(Array.from(plan.dailyCost, x => ({ ...x })), [
        { date: "2026-01-01", usd: 60 },
        { date: "2026-01-02", usd: 40 },
    ]);
    assert.equal(plan.dailyCost.reduce((sum, point) => sum + point.usd, 0), plan.cost);
    assert.deepEqual(Array.from(plan.dailyTokens, x => ({ ...x })), [{ date: "2026-01-01", total: 500 }]);
});

test("local rows fall back to empty dailyCost/dailyTokens when rawProviders is omitted", () => {
    const rows = FeatureTabs.localSpendRows({
        estimated: {
            costStatus: "exact",
            totalUSD: 2,
            providers: { cline: { costUSD: 2, costStatus: "exact", costProvenance: "estimated" } },
        },
    });
    assert.deepEqual(Array.from(rows[0].dailyCost), []);
    assert.deepEqual(Array.from(rows[0].dailyTokens), []);
});

test("session cost info reports the billing mode it was priced under", () => {
    const plan = FeatureTabs.sessionCostInfo({
        costUSD: 1.5,
        costStatus: "exact",
        costProvenance: "estimated",
        costBilling: "subscription",
    });
    const metered = FeatureTabs.sessionCostInfo({
        costUSD: 1.5,
        costStatus: "exact",
        costProvenance: "estimated",
    });

    assert.equal(plan.billing, "subscription");
    assert.equal(metered.billing, "api");
    assert.equal(FeatureTabs.sessionCostInfo({ costStatus: "unavailable" }).billing, "api");
});

// ── Model rate table helpers (shared by the Plasma and Quickshell Spend views) ──

test("rateText formats rates, free tiers and missing values distinctly", () => {
    assert.equal(FeatureTabs.rateText(0), "free");
    assert.equal(FeatureTabs.rateText(0.25), "$0.250");
    assert.equal(FeatureTabs.rateText(15), "$15.00");
    assert.equal(FeatureTabs.rateText(undefined), "—");
    assert.equal(FeatureTabs.rateText(NaN), "—");
    assert.equal(FeatureTabs.rateText(Infinity), "—");
});

test("rateAge buckets the catalog age and stays empty when unknown", () => {
    const now = 1_700_000_000_000;
    const at = (secondsAgo) => FeatureTabs.rateAge(now / 1000 - secondsAgo, null, now);
    assert.equal(at(30), "updated just now");
    assert.equal(at(7200), "updated 2h ago");
    assert.equal(at(3 * 86400), "updated 3d ago");
    assert.equal(at(3 * 604800), "updated 3w ago");
    // A missing or unusable timestamp renders nothing rather than "1970".
    assert.equal(FeatureTabs.rateAge(0, null, now), "");
    assert.equal(FeatureTabs.rateAge(undefined, null, now), "");
    // A clock skewed behind the cache must not produce a negative age.
    assert.equal(FeatureTabs.rateAge(now / 1000 + 600, null, now), "updated just now");
});

test("rateAge routes through the frontend's i18n function", () => {
    const seen = [];
    const i18n = (text, arg) => {
        seen.push([text, arg]);
        return "T:" + text.replace("%1", arg);
    };
    const now = 1_700_000_000_000;
    assert.equal(FeatureTabs.rateAge(now / 1000 - 7200, i18n, now), "T:updated 2h ago");
    assert.deepEqual(seen, [["updated %1h ago", 2]]);
});

test("rate paging arithmetic is stable at the edges", () => {
    assert.equal(FeatureTabs.ratePageCount(0, 40), 1);
    assert.equal(FeatureTabs.ratePageCount(676, 40), 17);
    assert.equal(FeatureTabs.ratePageCount(80, 40), 2);
    assert.equal(FeatureTabs.ratePageNumber(0, 40, 676), 1);
    assert.equal(FeatureTabs.ratePageNumber(640, 40, 676), 17);
    // Never divide by zero, and never report a page past the last one.
    assert.equal(FeatureTabs.ratePageCount(100, 0), 100);
    assert.equal(FeatureTabs.ratePageNumber(9999, 40, 676), 17);
});

test("parseRateTable normalizes payloads and rejects unusable output", () => {
    const parsed = FeatureTabs.parseRateTable(
        '{"rows":[{"provider":"anthropic","model":"claude-opus-5","input":15,"output":75}],' +
        '"total":676,"unit":"USD per 1M tokens","fetchedAt":1789976769,"error":""}\n');
    assert.equal(parsed.total, 676);
    assert.equal(parsed.unit, "USD per 1M tokens");
    assert.equal(parsed.fetchedAt, 1789976769);
    assert.equal(parsed.rows[0].model, "claude-opus-5");
    // Unusable output is null so each frontend can pick its own error string.
    assert.equal(FeatureTabs.parseRateTable(""), null);
    assert.equal(FeatureTabs.parseRateTable("   "), null);
    assert.equal(FeatureTabs.parseRateTable("not json"), null);
    assert.equal(FeatureTabs.parseRateTable("[1,2]").rows.length, 0);
    // A payload missing fields degrades to empty rather than throwing.
    const bare = FeatureTabs.parseRateTable("{}");
    assert.equal(bare.rows.length, 0);
    assert.equal(bare.total, 0);
    assert.equal(bare.error, "");
});
