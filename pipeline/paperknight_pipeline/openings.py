"""Opening names for the plugin, from Lichess's chess-openings (CC0).

Each line of a.tsv ... e.tsv is `eco<TAB>name<TAB>pgn`; the plugin looks
names up by position, so each line becomes the position its moves reach:
`key<TAB>eco<TAB>name`, where key is the FEN's first three fields (pieces,
side to move, castling rights; no en passant square, which FEN writers set
differently). The first name of a position wins (files in ECO order).
"""
from __future__ import annotations

import urllib.request
from pathlib import Path
from typing import Iterable

import chess

BASE_URL = "https://raw.githubusercontent.com/lichess-org/chess-openings/master/"
FILES = ("a.tsv", "b.tsv", "c.tsv", "d.tsv", "e.tsv")
HEADER = ("# Opening names by position (pieces, side to move, castling): "
          "key<TAB>ECO<TAB>name. From https://github.com/lichess-org/chess-openings "
          "(CC0 1.0), built by `python -m paperknight_pipeline openings`.\n")


def position_key(board: chess.Board) -> str:
    """The lookup key of a position (also computed by pkopeningnames.lua)."""
    return f"{board.board_fen()} {'w' if board.turn else 'b'} {board.castling_xfen()}"


def parse(lines: Iterable[str]) -> list[tuple[str, str, str]]:
    """Rows (key, eco, name) of the TSV lines (a header line is skipped)."""
    rows = []
    for line in lines:
        fields = line.rstrip("\n").split("\t")
        if len(fields) != 3 or fields[0] == "eco":
            continue
        eco, name, pgn = fields
        board = chess.Board()
        for token in pgn.split():
            if token[0].isdigit():  # move numbers ("1.")
                continue
            board.push_san(token)  # raises on an illegal move: the source is broken
        rows.append((position_key(board), eco, name))
    return rows


def build(texts: Iterable[str], output: Path) -> int:
    """Writes the plugin's table from the TSV texts; returns the positions written."""
    seen: dict[str, tuple[str, str]] = {}
    for text in texts:
        for key, eco, name in parse(text.splitlines()):
            seen.setdefault(key, (eco, name))
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", encoding="utf-8") as f:
        f.write(HEADER)
        for key in sorted(seen):
            eco, name = seen[key]
            f.write(f"{key}\t{eco}\t{name}\n")
    return len(seen)


def download() -> list[str]:
    texts = []
    for name in FILES:
        with urllib.request.urlopen(BASE_URL + name, timeout=60) as r:
            texts.append(r.read().decode("utf-8"))
    return texts
