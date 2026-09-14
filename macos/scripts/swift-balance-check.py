"""A crude balance check for Swift sources: braces, parens and brackets outside
strings and comments. Not a parser — it only catches the class of mistake that
comes from editing a file with a script."""

import pathlib
import sys


def scan(path):
    text = path.read_text(encoding="utf-8")
    depth = {"{": 0, "(": 0, "[": 0}
    close = {"}": "{", ")": "(", "]": "["}
    i, n = 0, len(text)
    line = 1
    in_line_comment = in_block = in_str = triple = False
    hashes = 0
    problems = []
    while i < n:
        c = text[i]
        if c == "\n":
            line += 1
            in_line_comment = False
            i += 1
            continue
        if in_line_comment:
            i += 1
            continue
        if in_block:
            if text.startswith("*/", i):
                in_block = False
                i += 2
                continue
            i += 1
            continue
        if in_str:
            marker = "\\" + "#" * hashes
            if c == "\\" and (hashes == 0 or text[i : i + len(marker)] == marker):
                i += 2 if hashes == 0 else len(marker) + 1
                continue
            if c == '"':
                end = '"""' if triple else '"'
                if text.startswith(end, i) and text[i + len(end) : i + len(end) + hashes] == "#" * hashes:
                    in_str = triple = False
                    i += len(end) + hashes
                    continue
            i += 1
            continue
        if text.startswith("//", i):
            in_line_comment = True
            i += 2
            continue
        if text.startswith("/*", i):
            in_block = True
            i += 2
            continue
        if c == "#":
            j = i
            while j < n and text[j] == "#":
                j += 1
            if j < n and text[j] == '"':
                hashes, in_str = j - i, True
                triple = text.startswith('"""', j)
                # A raw string ends at the first `"` followed by its hashes, so
                # a JSON hex colour — `"color":"#fff"` — closes a #"…"# literal
                # in the middle of itself. The compiler's complaint about it is
                # several errors away from the cause, so say it plainly here.
                if not triple:
                    delimiter = '"' + "#" * hashes
                    end_of_line = text.find("\n", j)
                    rest = text[j : end_of_line if end_of_line != -1 else n]
                    if rest.count(delimiter) > 1:
                        problems.append(
                            f"{path}:{line}: this raw string's delimiter {delimiter} appears "
                            f"{rest.count(delimiter)} times on the line — it closes early. "
                            f"Use one more # on both sides."
                        )
                i = j + (3 if triple else 1)
                continue
        if c == '"':
            hashes, in_str = 0, True
            triple = text.startswith('"""', i)
            i += 3 if triple else 1
            continue
        if c in depth:
            depth[c] += 1
        elif c in close:
            depth[close[c]] -= 1
            if depth[close[c]] < 0:
                problems.append(f"{path}:{line}: unbalanced {c}")
                depth[close[c]] = 0
        i += 1
    if in_str:
        problems.append(f"{path}: unterminated string literal")
    if in_block:
        problems.append(f"{path}: unterminated block comment")
    for opener, count in depth.items():
        if count:
            problems.append(f"{path}: {count} unclosed {opener}")
    return problems


bad = []
files = sorted(pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "macos").rglob("*.swift"))
for f in files:
    bad += scan(f)
print(f"scanned {len(files)} Swift files")
for b in bad:
    print("  " + b)
sys.exit(1 if bad else 0)
