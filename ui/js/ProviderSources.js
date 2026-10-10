.pragma library

// What the settings page needs to know about a provider's sources — the places
// its numbers can be read from — kept free of QML so it can be tested on its own.
//
// The backend (aiusage/sources.py) sends every provider that can be read more
// than one way a `sources` block:
//
//     { choice, selected, active, options: [{ id, kind, label, detail, state }] }
//
// `state` is working | failing | ready | missing. A provider with no such block
// is read one way only. Nothing here names a provider or a kind of source, so a
// new source (a browser session, say) shows up once the backend lists it.

var AUTO = "auto";

// How each state reads, best first. `tone` names a Theme colour.
var STATES = {
    working: { rank: 0, tone: "ok" },
    ready: { rank: 1, tone: "muted" },
    failing: { rank: 2, tone: "bad" },
    missing: { rank: 3, tone: "dim" }
};

function stateTone(state) {
    return (STATES[state] || STATES.missing).tone;
}

function block(snapshot) {
    var sources = snapshot && snapshot.sources;
    return sources && Array.isArray(sources.options) && sources.options.length > 0 ? sources : null;
}

// The choices a provider offers: "auto" first, then each source. A provider
// whose sources are not alternatives to each other has nothing to choose.
function choices(snapshot) {
    var sources = block(snapshot);
    return sources && sources.choice !== false ? [AUTO].concat(sources.options.map(function (o) {
        return o.id;
    })) : [];
}

// The option a snapshot reports as in use, or null.
function activeOption(snapshot) {
    var sources = block(snapshot);
    if (!sources || !sources.active)
        return null;
    for (var i = 0; i < sources.options.length; i++)
        if (sources.options[i].id === sources.active)
            return sources.options[i];
    return null;
}

// One line for a provider's row in the list. `code` picks the wording (the QML
// translates it); `label` is the source it names, `text` the provider's own
// error where that is what there is to say.
//   using    "Using <label>"          a source is answering
//   failing  "<label>: <error>"       the source in use is not
//   unset    "Not set up"             nothing on this machine suggests a source
//   ok       "Working"                a provider read one way only
//   error    "<error>"                a provider read one way only, not working
//   waiting  "Waiting for data"       no snapshot yet
function statusLine(snapshot) {
    if (!snapshot)
        return { code: "waiting", label: "", text: "" };
    var sources = block(snapshot);
    if (!sources)
        return snapshot.ok === true ? { code: "ok", label: "", text: "" } : { code: "error", label: "", text: String(snapshot.error || "") };
    var active = activeOption(snapshot);
    if (snapshot.ok === true && active)
        return { code: "using", label: active.label, text: "" };
    if (snapshot.ok === true)
        return { code: "ok", label: "", text: "" };
    if (active)
        return { code: "failing", label: active.label, text: String(snapshot.error || "") };
    return { code: "unset", label: "", text: String(snapshot.error || "") };
}

// Providers the picker offers: not already added, matching `query` on name or id
// (case-insensitive, every word must match), A to Z.
function pickable(providers, query, isEnabled) {
    var words = String(query || "").toLowerCase().split(/\s+/).filter(function (w) {
        return w !== "";
    });
    return (providers || []).filter(function (p) {
        if (isEnabled(p.id))
            return false;
        var hay = (String(p.label || "") + " " + p.id).toLowerCase();
        return words.every(function (w) {
            return hay.indexOf(w) !== -1;
        });
    }).sort(function (a, b) {
        return String(a.label || a.id).toLowerCase() < String(b.label || b.id).toLowerCase() ? -1 : 1;
    });
}

// The providers on the list, in the order the registry gives them.
function added(providers, isEnabled) {
    return (providers || []).filter(function (p) {
        return isEnabled(p.id);
    });
}
