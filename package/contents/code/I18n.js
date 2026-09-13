// Translations for the frontends that have no KDE i18n: the Quickshell panel
// and the Windows tray app. They read the same translate/<lang>.po the Plasma
// widget compiles to a .mo, parse it here, and look strings up with ki18n's
// call shapes — so xgettext extracts `shell.i18n("…")` into that same catalog.
//
// Every lookup takes the parsed catalog first; the hosts wrap these as
// shell.i18n(text, …) and friends, which keeps QML bindings reactive to the
// catalog being loaded.

var CONTEXT_SEPARATOR = "";

function empty() {
    return { plural: null, messages: {} };
}

function unquote(line) {
    var start = line.indexOf('"');
    var end = line.lastIndexOf('"');
    if (start < 0 || end <= start)
        return "";
    return line.slice(start + 1, end).replace(/\\(.)/g, function (_all, c) {
        return c === "n" ? "\n" : c === "t" ? "\t" : c === "r" ? "\r" : c;
    });
}

// The header's Plural-Forms expression is C syntax that JavaScript shares.
// It comes from our own catalog, and anything beyond numbers, `n` and
// operators is refused rather than evaluated.
function pluralRule(header) {
    var m = /plural\s*=\s*([^;]+)/.exec(header || "");
    if (!m || !/^[\sn0-9()?:<>=!&|%+\-*\/]+$/.test(m[1]))
        return null;
    try {
        var rule = new Function("n", "return Number(" + m[1] + ");");
        rule(1);
        return rule;
    } catch (e) {
        return null;
    }
}

// { plural: fn(n) → form index | null, messages: { "ctxmsgid": [forms] } }
// Fuzzy, obsolete and untranslated entries are left out, so they fall back to
// the English source text exactly as gettext does.
function parsePo(text) {
    var catalog = empty();
    if (!text)
        return catalog;

    var entry = null;
    var field = null;

    function start() {
        entry = { ctx: "", id: null, strs: [], fuzzy: false };
        field = null;
    }
    function flush() {
        if (entry && entry.id !== null) {
            if (entry.id === "")
                catalog.plural = pluralRule(entry.strs[0]);
            else if (!entry.fuzzy && entry.strs.length > 0 && entry.strs.every(function (s) { return s !== ""; }))
                catalog.messages[entry.ctx + CONTEXT_SEPARATOR + entry.id] = entry.strs;
        }
        entry = null;
        field = null;
    }

    var lines = String(text).split(/\r?\n/);
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim();
        if (line === "") {
            flush();
            continue;
        }
        if (line.indexOf("#~") === 0)
            continue;
        if (!entry)
            start();
        if (line.indexOf("#,") === 0) {
            if (/\bfuzzy\b/.test(line))
                entry.fuzzy = true;
            continue;
        }
        if (line.charAt(0) === "#")
            continue;

        var m;
        if (line.indexOf("msgctxt") === 0) {
            if (entry.id !== null) {
                flush();
                start();
            }
            entry.ctx = unquote(line);
            field = { name: "ctx" };
        } else if (line.indexOf("msgid_plural") === 0) {
            field = { name: "plural" };
        } else if (line.indexOf("msgid") === 0) {
            if (entry.id !== null) {
                flush();
                start();
            }
            entry.id = unquote(line);
            field = { name: "id" };
        } else if ((m = /^msgstr\[(\d+)\]/.exec(line))) {
            entry.strs[Number(m[1])] = unquote(line);
            field = { name: "str", index: Number(m[1]) };
        } else if (line.indexOf("msgstr") === 0) {
            entry.strs[0] = unquote(line);
            field = { name: "str", index: 0 };
        } else if (line.charAt(0) === '"' && field) {
            var more = unquote(line);
            if (field.name === "ctx")
                entry.ctx += more;
            else if (field.name === "id")
                entry.id += more;
            else if (field.name === "str")
                entry.strs[field.index] += more;
        }
    }
    flush();
    return catalog;
}

// "fr-FR" / "fr_FR.UTF-8" → ["fr_FR", "fr"], in order, for picking a .po file.
function languageCandidates(languages) {
    var out = [];
    var list = languages || [];
    for (var i = 0; i < list.length; i++) {
        var tag = String(list[i] || "").split(".")[0].split("@")[0].replace("-", "_");
        if (tag === "" || tag === "C" || tag === "POSIX")
            continue;
        var base = tag.split("_")[0];
        if (out.indexOf(tag) < 0)
            out.push(tag);
        if (out.indexOf(base) < 0)
            out.push(base);
    }
    return out;
}

function substitute(text, args) {
    return String(text).replace(/%(\d)/g, function (all, d) {
        var value = args[Number(d) - 1];
        return value === undefined ? all : String(value);
    });
}

function lookup(catalog, ctx, id) {
    var messages = catalog && catalog.messages;
    return messages ? messages[ctx + CONTEXT_SEPARATOR + id] || null : null;
}

function translate(catalog, ctx, id, args) {
    var forms = lookup(catalog, ctx, id);
    return substitute(forms ? forms[0] : id, args);
}

function translatePlural(catalog, ctx, singular, plural, n, args) {
    var forms = lookup(catalog, ctx, singular);
    var text;
    if (forms && catalog.plural) {
        var index = catalog.plural(n);
        text = forms[index] !== undefined ? forms[index] : forms[forms.length - 1];
    } else {
        text = n === 1 ? singular : plural;
    }
    return substitute(text, [n].concat(args));
}

function rest(args, from) {
    return Array.prototype.slice.call(args, from);
}

// ki18n's shapes, catalog first: i18n(catalog, text, %1…), i18nc(catalog, ctx,
// text, %1…), i18np(catalog, singular, plural, n, %2…), i18ncp(catalog, ctx,
// singular, plural, n, %2…). In the plural forms %1 is n.
function i18n(catalog, text) {
    return translate(catalog, "", text, rest(arguments, 2));
}

function i18nc(catalog, ctx, text) {
    return translate(catalog, ctx, text, rest(arguments, 3));
}

function i18np(catalog, singular, plural, n) {
    return translatePlural(catalog, "", singular, plural, n, rest(arguments, 4));
}

function i18ncp(catalog, ctx, singular, plural, n) {
    return translatePlural(catalog, ctx, singular, plural, n, rest(arguments, 5));
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        empty: empty,
        parsePo: parsePo,
        languageCandidates: languageCandidates,
        i18n: i18n,
        i18nc: i18nc,
        i18np: i18np,
        i18ncp: i18ncp
    };
}
