function normalizeDescriptors(raw) {
    var normalized = [];
    var seen = {};
    if (!Array.isArray(raw))
        return normalized;
    for (var i = 0; i < raw.length; i++) {
        var source = raw[i];
        if (!source || typeof source.id !== "string" || typeof source.label !== "string")
            continue;
        var id = source.id.trim();
        var label = source.label.trim();
        if (id === "" || label === "" || seen[id])
            continue;
        seen[id] = true;
        normalized.push({id: id, label: label});
    }
    return normalized;
}

function normalizeIds(ids, available) {
    var requested = {};
    if (Array.isArray(ids)) {
        for (var i = 0; i < ids.length; i++) {
            if (typeof ids[i] === "string") {
                var id = ids[i].trim();
                if (id !== "")
                    requested[id] = true;
            }
        }
    }
    var normalized = [];
    var sources = available || [];
    for (var j = 0; j < sources.length; j++) {
        if (requested[sources[j].id])
            normalized.push(sources[j].id);
    }
    return normalized.length === sources.length ? [] : normalized;
}

function signature(ids) {
    return (ids || []).join("\u001f");
}

function hasStaleIds(ids, available) {
    var known = {};
    var sources = available || [];
    for (var i = 0; i < sources.length; i++)
        known[sources[i].id] = true;
    for (var j = 0; j < (ids || []).length; j++)
        if (!known[ids[j]])
            return true;
    return false;
}

function toggled(ids, id, checked, available) {
    var sources = available || [];
    if (sources.length <= 1)
        return normalizeIds(ids, sources);
    var current = normalizeIds(ids, sources);
    if (!checked && current.length === 0) {
        var allExcept = [];
        for (var i = 0; i < sources.length; i++)
            if (sources[i].id !== id)
                allExcept.push(sources[i].id);
        return normalizeIds(allExcept, sources);
    }
    var next = current.slice(0);
    var index = next.indexOf(id);
    if (checked && index < 0)
        next.push(id);
    else if (!checked && index >= 0) {
        if (next.length === 1)
            // Unchecking the last explicitly-selected source would normalize
            // back to [], which is the same sentinel as "all sources" — keep
            // at least one source selected so that state stays representable.
            return current;
        next.splice(index, 1);
    }
    return normalizeIds(next, sources);
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        normalizeDescriptors: normalizeDescriptors,
        normalizeIds: normalizeIds,
        signature: signature,
        hasStaleIds: hasStaleIds,
        toggled: toggled
    };
}
