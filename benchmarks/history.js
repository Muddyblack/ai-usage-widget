"use strict";

const assert = require("node:assert/strict");
const { normalize, union } = require("../package/contents/code/UsageHistory.js");

const SIZES = [500, 5000, 10000];
const WARMUPS = 3;
const ITERATIONS = 7;
const START_TIME = 1700000000000;
const STEP_MS = 300000;

function makePoints(count) {
    return Array.from({ length: count }, (_, index) => ({
        t: START_TIME + index * STEP_MS,
        v: (index * 17) % 101,
        cp: (index * 31) % 101
    }));
}

function medianNanoseconds(samples) {
    const sorted = [...samples].sort((left, right) => (left < right ? -1 : left > right ? 1 : 0));
    return Number(sorted[Math.floor(sorted.length / 2)]);
}

function measure(operation) {
    for (let index = 0; index < WARMUPS; index += 1) {
        operation();
    }

    const samples = [];
    for (let index = 0; index < ITERATIONS; index += 1) {
        const started = process.hrtime.bigint();
        operation();
        samples.push(process.hrtime.bigint() - started);
    }
    return medianNanoseconds(samples);
}

function emit(operation, points, medianNs) {
    console.log(JSON.stringify({
        benchmark: "history",
        operation,
        points,
        median_ns: medianNs,
        warmups: WARMUPS,
        iterations: ITERATIONS
    }));
}

for (const size of SIZES) {
    const points = makePoints(size);
    const split = Math.floor(points.length / 2);
    const base = points.slice(0, split);
    const overlay = points.slice(split);
    const unionResult = union(base, overlay, size);
    const normalizeResult = normalize(points, size);
    const expectedNormalized = points.map((point) => ({
        t: point.t,
        w: point.v,
        cp: point.cp
    }));

    assert.deepStrictEqual(unionResult, points);
    assert.deepStrictEqual(normalizeResult, expectedNormalized);

    emit("union", size, measure(() => union(base, overlay, size)));
    emit("normalize", size, measure(() => normalize(points, size)));
}
