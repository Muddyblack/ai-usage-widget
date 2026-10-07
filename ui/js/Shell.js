// Command-line building shared by the Plasma frontend.
//
// The widget talks to the backend by running a /bin/sh command line, and API
// keys ride along as environment assignments in that line. Every such value is
// base64-encoded here and decoded back inside the shell, so no metacharacter in
// a key can break out of the command.
//
// The encoder is spelled out by hand rather than delegating to Qt.btoa():
// btoa() takes a *string*, and handing it a byte array does not make it a byte
// encoder — QML stringifies the array first ("119,105,100,...") and faithfully
// encodes that instead of the key. A correctly pasted key then reached the
// provider as that digit soup and came back as an auth error (issue #16).

var _ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
var _REPLACEMENT = [0xEF, 0xBF, 0xBD];

// UTF-8 bytes of `text`. Unpaired surrogates become U+FFFD rather than the
// invalid three-byte sequence a naive encoder emits, so the output always
// survives the `base64 -d` on the other side.
function utf8Bytes(text) {
    var s = String(text);
    var bytes = [];
    for (var i = 0; i < s.length; ++i) {
        var c = s.charCodeAt(i);
        if (c < 0x80) {
            bytes.push(c);
        } else if (c < 0x800) {
            bytes.push(0xC0 | (c >> 6), 0x80 | (c & 0x3F));
        } else if (c >= 0xD800 && c <= 0xDBFF) {
            var low = i + 1 < s.length ? s.charCodeAt(i + 1) : 0;
            if (low >= 0xDC00 && low <= 0xDFFF) {
                ++i;
                var cp = 0x10000 + ((c & 0x3FF) << 10) + (low & 0x3FF);
                bytes.push(0xF0 | (cp >> 18), 0x80 | ((cp >> 12) & 0x3F), 0x80 | ((cp >> 6) & 0x3F), 0x80 | (cp & 0x3F));
            } else {
                bytes.push(_REPLACEMENT[0], _REPLACEMENT[1], _REPLACEMENT[2]);
            }
        } else if (c >= 0xDC00 && c <= 0xDFFF) {
            bytes.push(_REPLACEMENT[0], _REPLACEMENT[1], _REPLACEMENT[2]);
        } else {
            bytes.push(0xE0 | (c >> 12), 0x80 | ((c >> 6) & 0x3F), 0x80 | (c & 0x3F));
        }
    }
    return bytes;
}

// Standard (padded, +/ alphabet) base64 of the UTF-8 bytes of `text` — what
// `base64 -d` expects to read back.
function base64(text) {
    var bytes = utf8Bytes(text);
    var out = "";
    for (var i = 0; i < bytes.length; i += 3) {
        var b0 = bytes[i];
        var has1 = i + 1 < bytes.length;
        var has2 = i + 2 < bytes.length;
        var b1 = has1 ? bytes[i + 1] : 0;
        var b2 = has2 ? bytes[i + 2] : 0;
        out += _ALPHABET.charAt(b0 >> 2);
        out += _ALPHABET.charAt(((b0 & 0x03) << 4) | (b1 >> 4));
        out += has1 ? _ALPHABET.charAt(((b1 & 0x0F) << 2) | (b2 >> 6)) : "=";
        out += has2 ? _ALPHABET.charAt(b2 & 0x3F) : "=";
    }
    return out;
}

// Single-quote `s` for /bin/sh.
function quote(s) {
    return "'" + String(s).replace(/'/g, "'\\''") + "'";
}

// `NAME="<value>" ` prefix for a command line, empty for an empty value. The
// base64 alphabet holds no shell metacharacter, so the literal below is safe to
// interpolate whatever the value contains.
function envAssign(name, value) {
    if (!value)
        return "";

    return name + "=\"$(printf %s '" + base64(value) + "' | base64 -d)\" ";
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        utf8Bytes: utf8Bytes,
        base64: base64,
        quote: quote,
        envAssign: envAssign
    };
}
