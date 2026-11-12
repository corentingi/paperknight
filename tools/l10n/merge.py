#!/usr/bin/env python3
"""Adds translations to a catalogue and rewrites it in the code's order.

    python3 tools/l10n/merge.py fr new.tsv    # new.tsv: msgid<TAB>msgstr per line (\\n for a line break)

Entries the code no longer has are dropped; the header is kept.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import l10n  # noqa: E402


def main(lang: str, tsv: str) -> None:
    po = l10n.L10N / f"{lang}.po"
    entries = l10n.read_po(po)
    for line in Path(tsv).read_text(encoding="utf-8").splitlines():
        if line.strip():
            msgid, msgstr = line.split("\t")
            entries[msgid.replace("\\n", "\n")] = msgstr.replace("\\n", "\n")
    head = po.read_text(encoding="utf-8").split("\n\n")[0]
    out = [head, ""]
    for msgid, places in l10n.extract().items():
        out += ["#: " + " ".join(places[:4]), "msgid " + l10n.po_quote(msgid),
                "msgstr " + l10n.po_quote(entries.get(msgid, "")), ""]
    po.write_text("\n".join(out), encoding="utf-8")


if __name__ == "__main__":
    main(*sys.argv[1:])
