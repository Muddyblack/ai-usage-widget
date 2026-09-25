const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const path = require("node:path");

function setup() {
    const context = vm.createContext({});
    const code = path.join(__dirname, "../package/contents/code/");
    vm.runInContext(fs.readFileSync(code + "ProjectInfoRequests.js", "utf8"), context);
    const project = vm.createContext({Funding: {links: []}});
    vm.runInContext(fs.readFileSync(code + "ProjectInfo.js", "utf8").replace(/^\.import.*$/m, ""), project);
    let time = 0, state;
    const requests = [];
    const client = context.create(project, () => {
        const request = {
            open(method, url) { this.url = url; },
            send() {},
            abort() { this.aborted = true; },
            getResponseHeader(name) { return this.headers?.[name] ?? null; },
            respond(status, body, headers) {
                this.status = status;
                this.responseText = JSON.stringify(body);
                this.headers = headers;
                this.readyState = 4;
                this.onreadystatechange?.();
            }
        };
        requests.push(request);
        return request;
    }, () => time, value => { state = value; });
    function success(request) {
        request.respond(200, request.url === project.latestReleaseUrl ? {tag_name: "v3.1.1"}
            : request.url === project.contributorsUrl ? [] : {value: "42"});
    }
    return {client, requests, success, get state() { return state; },
        advance(ms) { time += ms; client.tick(); }};
}

test("successful data and empty contributors do not poll; manual refresh has a cooldown", () => {
    const h = setup();
    h.client.tick();
    assert.equal(h.requests.length, 5);
    h.requests.forEach(h.success);
    assert.equal(h.state.counts.stars, "42");
    assert.equal(h.state.latestVersion, "3.1.1");
    h.client.refresh();
    assert.equal(h.requests.length, 5);
    h.advance(60000);
    assert.equal(h.requests.length, 5);
    assert.equal(h.state.canRefresh, true);
    h.client.refresh();
    h.client.refresh();
    assert.equal(h.requests.length, 10);
    h.requests.slice(5).forEach(r => r.respond(503, {}));
    assert.equal(h.state.counts.stars, "42");
    assert.equal(h.state.latestVersion, "3.1.1");
});

test("only failed endpoints retry, with two delayed retries and a hard stop", () => {
    const h = setup();
    h.client.tick();
    h.requests.slice(1).forEach(h.success);
    h.requests[0].respond(503, {});
    h.advance(14999);
    assert.equal(h.requests.length, 5);
    h.advance(1);
    assert.equal(h.requests.length, 6);
    h.requests[5].respond(200, {message: "invalid release"});
    h.advance(59999);
    assert.equal(h.requests.length, 6);
    h.advance(1);
    assert.equal(h.requests.length, 7);
    h.requests[6].respond(0, {});
    h.advance(3600000);
    assert.equal(h.requests.length, 7);
});

test("hanging requests time out and late callbacks cannot overwrite recovered data", () => {
    const h = setup();
    h.client.tick();
    const late = h.requests[1].onreadystatechange;
    h.advance(8000);
    assert.ok(h.requests.every(r => r.aborted));
    h.advance(15000);
    h.requests.slice(5).forEach(h.success);
    h.requests[1].status = 200;
    h.requests[1].responseText = '{"value":"999"}';
    h.requests[1].readyState = 4;
    late();
    assert.equal(h.state.counts.stars, "42");
    h.advance(3600000);
    assert.equal(h.requests.length, 10);
});

test("rate limits are not retried automatically and Retry-After also delays manual refresh", () => {
    const h = setup();
    h.client.tick();
    h.requests.forEach(r => r.respond(429, {}, {"Retry-After": "120"}));
    h.advance(60000);
    assert.equal(h.requests.length, 5);
    h.client.refresh();
    assert.equal(h.requests.length, 5);
    h.advance(60000);
    assert.equal(h.requests.length, 10);
    h.requests.slice(5).forEach(r => r.respond(403, {}));
    h.advance(3600000);
    assert.equal(h.requests.length, 10);
});

test("hiding cancels requests without resetting attempts; destruction prevents further requests", () => {
    const h = setup();
    for (let round = 0; round < 3; round++) {
        h.client.tick();
        h.client.pause();
        assert.ok(h.requests.every(r => r.aborted));
        // Reopening immediately must not issue another request.
        const count = h.requests.length;
        h.client.tick();
        assert.equal(h.requests.length, count);
        if (round < 2) h.advance(round === 0 ? 15000 : 60000);
    }
    h.advance(3600000);
    assert.equal(h.requests.length, 15);
    h.client.refresh();
    assert.equal(h.requests.length, 20);
    h.client.dispose();
    h.advance(3600000);
    h.client.refresh();
    assert.equal(h.requests.length, 20);
    assert.ok(h.requests.every(r => r.aborted));
});

test("error badges are failures, while a legitimate zero is retained", () => {
    const h = setup();
    h.client.tick();
    h.requests[0].respond(200, {tag_name: "v3.1.1"});
    h.requests[1].respond(200, {value: "0"});
    h.requests[2].respond(200, {value: "upstream error", isError: true});
    h.requests[3].respond(200, {value: "invalid"});
    h.requests[4].respond(200, {message: "invalid contributors"});
    h.advance(15000);
    assert.equal(h.state.counts.stars, "0");
    assert.equal(h.requests.length, 8);
});
