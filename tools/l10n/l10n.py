#!/usr/bin/env python3
"""The plugin's translations (docs/translations.md).

    python3 tools/l10n/l10n.py extract   # writes build/l10n/paperknight.pot (the template) from the code
    python3 tools/l10n/l10n.py check     # every catalogue: well formed, its placeholders kept

The strings are the `_("...")` calls of plugin/paperknight.koplugin/*.lua
(literals joined with `..` count as one).
A catalogue is l10n/<lang>.po (msgid/msgstr, no plurals). `check` fails on
a broken catalogue, a translation whose %1, %2… differ from its msgid, or an
entry the code no longer has; it lists the strings not translated yet
(they show in English) without failing.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
PLUGIN = REPO / "plugin" / "paperknight.koplugin"
L10N = PLUGIN / "l10n"
LITERAL = r'"(?:[^"\\\n]|\\.)*"'
# _("…"), or literals joined with .. (a long string over several lines)
CALL = re.compile(r'(?<![\w.:])_\(\s*(' + LITERAL + r'(?:\s*\.\.\s*' + LITERAL + r')*)\s*\)')
ESCAPES = {"n": "\n", "t": "\t", '"': '"', "\\": "\\", "'": "'"}


def unescape(s: str) -> str:
    return re.sub(r"\\(.)", lambda m: ESCAPES.get(m.group(1), "\\" + m.group(1)), s)


def po_quote(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\t", "\\t") + '"'


def extract() -> dict[str, list[str]]:
    """msgid -> the places it is used, in file order."""
    found: dict[str, list[str]] = {}
    for path in sorted(PLUGIN.glob("*.lua")):
        if path.name == "_meta.lua":
            continue  # read by KOReader before the plugin's modules can load
        text = path.read_text(encoding="utf-8")
        for m in CALL.finditer(text):
            line = text.count("\n", 0, m.start()) + 1
            msgid = "".join(unescape(lit[1:-1]) for lit in re.findall(LITERAL, m.group(1)))
            found.setdefault(msgid, []).append(f"{path.name}:{line}")
    return found


def read_po(path: Path) -> dict[str, str]:
    entries: dict[str, str] = {}
    msgid = msgstr = None
    field = None

    def flush():
        if msgid is not None and msgid != "":
            if msgid in entries:
                raise ValueError(f"{path.name}: duplicate msgid {msgid!r}")
            entries[msgid] = msgstr or ""

    for n, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        m = re.match(r'(msgid|msgstr)\s+"((?:[^"\\]|\\.)*)"$', line)
        if m:
            if m.group(1) == "msgid":
                flush()
                msgid, msgstr = unescape(m.group(2)), None
            else:
                if msgid is None:
                    raise ValueError(f"{path.name}:{n}: msgstr without msgid")
                msgstr = unescape(m.group(2))
            field = m.group(1)
            continue
        m = re.match(r'"((?:[^"\\]|\\.)*)"$', line)
        if m and field:
            if field == "msgid":
                msgid += unescape(m.group(1))
            else:
                msgstr += unescape(m.group(1))
            continue
        raise ValueError(f"{path.name}:{n}: cannot read {raw!r}")
    flush()
    return entries


def placeholders(s: str) -> list[str]:
    return sorted(re.findall(r"%\d", s))


def write_pot(found: dict[str, list[str]]) -> Path:
    out = ["# Paperknight's strings, from the code (tools/l10n/l10n.py extract).",
           'msgid ""', 'msgstr ""', '"Content-Type: text/plain; charset=UTF-8\\n"', ""]
    for msgid, places in found.items():
        out.append("#: " + " ".join(places[:4]))
        out.append("msgid " + po_quote(msgid))
        out.append('msgstr ""')
        out.append("")
    pot = REPO / "build" / "l10n" / "paperknight.pot"
    pot.parent.mkdir(parents=True, exist_ok=True)
    pot.write_text("\n".join(out), encoding="utf-8")
    return pot


def check() -> int:
    found = extract()
    errors = 0
    for po in sorted(L10N.glob("*.po")):
        try:
            entries = read_po(po)
        except ValueError as e:
            print(e)
            errors += 1
            continue
        for msgid, msgstr in entries.items():
            if msgid not in found:
                print(f"{po.name}: not in the code any more: {msgid!r}")
                errors += 1
            elif msgstr and placeholders(msgid) != placeholders(msgstr):
                print(f"{po.name}: placeholders differ: {msgid!r} -> {msgstr!r}")
                errors += 1
        missing = [m for m in found if not entries.get(m)]
        print(f"{po.name}: {len(found) - len(missing)} of {len(found)} strings translated")
        for m in missing:
            print(f"  not translated: {m!r} ({found[m][0]})")
    return 1 if errors else 0


if __name__ == "__main__":
    if sys.argv[1:] == ["extract"]:
        print(write_pot(extract()))
    elif sys.argv[1:] == ["check"]:
        sys.exit(check())
    else:
        print(__doc__)
        sys.exit(2)
