const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

// A raw executable DataSource remembers every command string it has ever run.
// Only CommandSource.qml (one disposable source per command) may name the engine.
const WRAPPER = "CommandSource.qml";
const root = path.join(__dirname, "..");

function qmlFiles(dir) {
    return fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
        const full = path.join(dir, entry.name);
        if (entry.isDirectory()) return qmlFiles(full);
        return entry.name.endsWith(".qml") ? [full] : [];
    });
}

test("executable commands run through the disposable CommandSource", () => {
    const offenders = ["package", "hyprland"]
        .flatMap((folder) => qmlFiles(path.join(root, folder)))
        .filter((file) => path.basename(file) !== WRAPPER)
        .filter((file) => /engine:\s*"executable"/.test(fs.readFileSync(file, "utf8")))
        .map((file) => path.relative(root, file));
    assert.deepEqual(offenders, [], "use CommandSource.qml instead of a raw executable DataSource");
});
