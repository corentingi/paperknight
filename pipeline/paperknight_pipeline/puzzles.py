"""Lichess puzzle CSV -> puzzles.sqlite (pack format v1, docs/pack-format.md).

Selection (ADR-0008): keep well-tested puzzles (popularity, play count, rating
deviation), then take at most `per_band` puzzles per rating band. Within a band
the choice is deterministic: the puzzles with the smallest hash of their id win,
so rebuilding from a newer dump keeps most of the same puzzles.
"""
from __future__ import annotations

import csv
import hashlib
import heapq
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Iterator

import chess

from .pack import create_pack, finalize_pack

FORMAT_VERSION = 1

# Column order of the Lichess export, used when the file has no header row.
LICHESS_COLUMNS = [
    "PuzzleId", "FEN", "Moves", "Rating", "RatingDeviation", "Popularity",
    "NbPlays", "Themes", "GameUrl", "OpeningTags",
]


@dataclass(frozen=True)
class Puzzle:
    id: str
    fen: str
    moves: str
    rating: int
    rating_dev: int
    popularity: int
    plays: int
    themes: str
    game_url: str
    opening: str

    @property
    def stable_hash(self) -> int:
        return int.from_bytes(hashlib.sha1(self.id.encode()).digest()[:4], "big") & 0x7FFFFFFF


@dataclass(frozen=True)
class Selection:
    per_band: int = 2500
    band_width: int = 100
    min_popularity: int = 80
    min_plays: int = 300
    max_rating_dev: int = 90


def read_puzzles(lines: Iterable[str]) -> Iterator[Puzzle]:
    """Parse Lichess puzzle CSV rows (with or without header). Malformed rows are skipped."""
    columns = LICHESS_COLUMNS
    for row in csv.reader(lines):
        if not row:
            continue
        if row[0] == "PuzzleId":  # header row: trust its column order
            columns = row
            continue
        rec = dict(zip(columns, row))
        try:
            yield Puzzle(
                id=rec["PuzzleId"],
                fen=rec["FEN"],
                moves=rec["Moves"],
                rating=int(rec["Rating"]),
                rating_dev=int(rec["RatingDeviation"]),
                popularity=int(rec["Popularity"]),
                plays=int(rec["NbPlays"]),
                themes=rec.get("Themes", ""),
                game_url=rec.get("GameUrl", ""),
                opening=rec.get("OpeningTags", ""),
            )
        except (KeyError, ValueError):
            continue


def passes_quality(p: Puzzle, sel: Selection) -> bool:
    return (
        p.popularity >= sel.min_popularity
        and p.plays >= sel.min_plays
        and p.rating_dev <= sel.max_rating_dev
    )


@dataclass(frozen=True)
class Checked:
    """A puzzle whose line was validated: solver colour and normalised UCI moves."""
    puzzle: Puzzle
    solver: str
    moves: str


def check(p: Puzzle) -> Checked | None:
    """Validate the puzzle line with python-chess. Returns None if invalid.

    The FEN is the position before the opponent's setup move (first UCI move);
    the solver plays every second move after it, including the last one, so
    the line must have an even number of moves. Moves are re-emitted in
    standard UCI (castling as king-to-destination, e.g. e1g1).
    """
    try:
        board = chess.Board(p.fen)
        uci_moves = p.moves.split()
        if len(uci_moves) < 2 or len(uci_moves) % 2:
            return None
        normalised = []
        for uci in uci_moves:
            move = board.parse_uci(uci)  # raises ValueError if illegal; maps e1h1-style castling
            normalised.append(board.uci(move))
            board.push(move)
    except ValueError:
        return None
    solver = "b" if board_turn(p.fen) == "w" else "w"
    return Checked(p, solver, " ".join(normalised))


def board_turn(fen: str) -> str:
    return fen.split()[1]


def solver_color(p: Puzzle) -> str | None:
    checked = check(p)
    return checked.solver if checked else None


def select(puzzles: Iterable[Puzzle], sel: Selection, stats: Counter[str] | None = None) -> list[Checked]:
    """Quality filter + per-band quota, keeping the smallest stable hashes.

    Only candidates that would enter a band's heap are validated, so invalid
    puzzles never take a slot and the cost stays proportional to the quota.
    """
    if sel.per_band < 1 or sel.band_width < 1:
        raise ValueError("per_band and band_width must be >= 1")
    stats = stats if stats is not None else Counter()
    bands: dict[int, list[tuple[int, str]]] = {}
    kept: dict[str, Checked] = {}
    for p in puzzles:
        if not passes_quality(p, sel) or p.id in kept:
            continue
        heap = bands.setdefault(p.rating // sel.band_width, [])
        # max-heap on hash via negation: evict the largest hash when over quota
        item = (-p.stable_hash, p.id)
        if len(heap) >= sel.per_band and item <= heap[0]:
            continue
        checked = check(p)
        if checked is None:
            stats["invalid"] += 1
            continue
        kept[p.id] = checked
        if len(heap) < sel.per_band:
            heapq.heappush(heap, item)
        else:
            evicted = heapq.heapreplace(heap, item)
            del kept[evicted[1]]
    chosen = list(kept.values())
    chosen.sort(key=lambda c: (c.puzzle.rating, c.puzzle.id))
    return chosen


SCHEMA = """
CREATE TABLE puzzles (
    id          TEXT PRIMARY KEY,
    fen         TEXT NOT NULL,
    moves       TEXT NOT NULL,
    solver      TEXT NOT NULL CHECK (solver IN ('w', 'b')),
    rating      INTEGER NOT NULL,
    rating_dev  INTEGER NOT NULL,
    popularity  INTEGER NOT NULL,
    plays       INTEGER NOT NULL,
    themes      TEXT NOT NULL,
    opening     TEXT NOT NULL,
    game_url    TEXT NOT NULL,
    band        INTEGER NOT NULL,
    rnd         INTEGER NOT NULL
);
CREATE INDEX puzzles_band_rnd ON puzzles (band, rnd);
CREATE TABLE puzzle_themes (
    theme       TEXT NOT NULL,
    band        INTEGER NOT NULL,
    rnd         INTEGER NOT NULL,
    puzzle_id   TEXT NOT NULL REFERENCES puzzles (id),
    PRIMARY KEY (theme, band, rnd, puzzle_id)
) WITHOUT ROWID;
CREATE TABLE themes (
    theme       TEXT PRIMARY KEY,
    count       INTEGER NOT NULL
);
"""


PICK_BAND = 100  # `band` column = rating // 100, independent of the selection band width


def build_pack(lines: Iterable[str], output: Path, sel: Selection, source_label: str) -> dict[str, int]:
    """Select puzzles from `lines` and write the pack atomically. Returns build statistics."""
    stats: Counter[str] = Counter()
    chosen = select(read_puzzles(lines), sel, stats)
    tmp = output.with_name(output.name + ".tmp")
    conn = create_pack(tmp, kind="puzzles", format_version=FORMAT_VERSION,
                       source=source_label, license="CC0-1.0")
    try:
        conn.executescript(SCHEMA)
        theme_counts: Counter[str] = Counter()
        for c in chosen:
            p = c.puzzle
            band = p.rating // PICK_BAND
            conn.execute(
                "INSERT INTO puzzles VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)",
                (p.id, p.fen, c.moves, c.solver, p.rating, p.rating_dev, p.popularity,
                 p.plays, p.themes, p.opening, p.game_url, band, p.stable_hash),
            )
            themes = sorted(set(p.themes.split()))
            conn.executemany("INSERT INTO puzzle_themes VALUES (?, ?, ?, ?)",
                             [(t, band, p.stable_hash, p.id) for t in themes])
            theme_counts.update(themes)
        conn.executemany("INSERT INTO themes VALUES (?, ?)", sorted(theme_counts.items()))
        finalize_pack(conn, {
            "puzzle_count": str(len(chosen)),
            "selection": (f"per_band={sel.per_band} band_width={sel.band_width} "
                          f"min_popularity={sel.min_popularity} min_plays={sel.min_plays} "
                          f"max_rating_dev={sel.max_rating_dev}"),
        })
    except BaseException:
        conn.close()
        tmp.unlink(missing_ok=True)
        raise
    if not chosen:
        tmp.unlink()
        return {"written": 0, "invalid": stats["invalid"]}
    tmp.replace(output)
    return {"written": len(chosen), "invalid": stats["invalid"]}
