// Request generations and snapshot-write deduplication for the Plasma widget.
//
// The executable DataSource cannot cancel a command already running, so a
// refresh that resolves after a newer one must not overwrite newer state. Each
// refresh carries a monotonically increasing generation; a response is applied
// only when its generation is the newest seen. The same module decides whether
// a successful snapshot is worth persisting: writing an identical document to
// Plasmoid.configuration on every poll is a pointless config write.

function nextGeneration(current) {
    var value = Number(current);
    if (!isFinite(value) || value < 0)
        value = 0;
    return value + 1;
}

function isCurrent(responseGeneration, currentGeneration) {
    return Number(responseGeneration) === Number(currentGeneration);
}

// A snapshot is worth persisting only when it differs from what is already
// stored. The comparison is a cheap string equality on the exact text that
// would be written, so whitespace-only differences still count as a change.
function shouldPersist(text, storedText) {
    return String(text || "") !== String(storedText || "");
}

// The generation may be carried in the command when the backend ignores an
// unknown trailing token, or tracked out of band. This extracts a generation
// tagged into a command string as `#gen=<n>`; absent, the response is treated
// as current (legacy callers keep working).
function generationOf(command) {
    var match = /#gen=(\d+)/.exec(String(command || ""));
    return match ? Number(match[1]) : 0;
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        nextGeneration: nextGeneration,
        isCurrent: isCurrent,
        shouldPersist: shouldPersist,
        generationOf: generationOf
    };
}
