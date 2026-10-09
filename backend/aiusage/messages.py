"""Translatable text in the envelope.

The backend words its rows itself ("5-hour session", "120000 / 500000
tokens", "Claude not logged in"), and every frontend shows those words. To
translate them without the backend knowing any language, a string the user
reads is built with :func:`tr`:

    tr("%1 / %2 tokens", used, limit)

which returns a :class:`Msg` — an ordinary ``str`` holding the English text
("120000 / 500000 tokens"), so the terminal frontend, comparisons, f-strings
and tests see no difference — that also remembers its template and arguments.
:func:`aiusage.contract.finalize` then writes, beside every field holding one,

    "detail": "120000 / 500000 tokens",
    "detailI18n": {"id": "%1 / %2 tokens", "args": ["120000", "500000"]}

and the shared UI (``ui/AppState.qml``, ``tr()``) looks the template up in
translate/<lang>.po, the same catalog as every QML string, filling in the
arguments. ``translate/Messages.sh`` extracts the ``tr("…")`` literals from
this package into that catalog, so a translator sees backend and UI strings
side by side.

Placeholders are ki18n's ``%1``, ``%2`` …, as in the QML. A Msg that is
concatenated or reformatted becomes a plain string again and is shown in
English — wrap the whole sentence in one ``tr()`` instead.
"""

import re

_PLACEHOLDER = re.compile(r"%(\d)")


class Msg(str):
    """English text that knows the template and arguments it came from."""

    __slots__ = ("template", "args")

    def __new__(cls, template, args=()):
        values = [str(a) for a in args]

        def fill(match):
            index = int(match.group(1)) - 1
            return values[index] if 0 <= index < len(values) else match.group(0)

        obj = super().__new__(cls, _PLACEHOLDER.sub(fill, template))
        obj.template = template
        obj.args = values
        return obj

    def i18n(self):
        return {"id": self.template, "args": list(self.args)}

    def __reduce__(self):
        return (Msg, (self.template, tuple(self.args)))


def tr(template, *args):
    """A translatable message: ``template`` with ``%1``… filled from ``args``."""
    return Msg(template, args)


class Lines(Msg):
    """Several lines, each its own message (or plain text, shown as is), for
    multi-line text such as a tooltip; translated line by line."""

    __slots__ = ("parts",)

    def __new__(cls, parts):
        parts = [p for p in parts if p]
        obj = str.__new__(cls, "\n".join(parts))
        obj.template = str(obj)
        obj.args = []
        obj.parts = parts
        return obj

    def i18n(self):
        return {"lines": [p.i18n() if isinstance(p, Msg) else {"id": str(p), "args": [], "plain": True} for p in self.parts]}

    def __reduce__(self):
        return (Lines, (list(self.parts),))


def lines(*parts):
    """``parts`` (messages or plain strings; empty ones dropped) on separate lines."""
    return Lines(parts)
