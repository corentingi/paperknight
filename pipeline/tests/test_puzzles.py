import sqlite3
from pathlib import Path

import pytest
import zstandard

from paperknight_pipeline import puzzles, sources
from paperknight_pipeline.cli import main

FIXTURE = Path(__file__).parent / "fixtures" / "lichess_puzzles_sample.csv"
LOOSE = puzzles.Selection(per_band=1000, min_popularity=-100, min_plays=0, max_rating_dev=500)


def make(id="x1", rating=1500, popularity=90, plays=1000, rating_dev=75,
         fen="6k1/5ppp/8/8/8/8/5PPP/3R2K1 b - - 0 1", moves="g8h8 d1d8"):
    return puzzles.Puzzle(id=id, fen=fen, moves=moves, rating=rating, rating_dev=rating_dev,
                          popularity=popularity, plays=plays, themes="mateIn1 short",
                          game_url="", opening="")


def test_reads_fixture_with_header():
    rows = list(puzzles.read_puzzles(FIXTURE.open()))
    assert len(rows) == 63
    assert all(p.id and p.fen and p.moves for p in rows)


def test_reads_headerless_rows_and_skips_malformed():
    lines = [
        "abc,6k1/5ppp/8/8/8/8/5PPP/3R2K1 b - - 0 1,g8h8 d1d8,1200,80,95,500,mateIn1,https://x,",
        "broken,row",
        "bad,fen,moves,not-a-number,1,1,1,t,u,",
    ]
    rows = list(puzzles.read_puzzles(lines))
    assert [p.id for p in rows] == ["abc"]


def test_quality_filter():
    sel = puzzles.Selection()
    assert puzzles.passes_quality(make(), sel)
    assert not puzzles.passes_quality(make(popularity=10), sel)
    assert not puzzles.passes_quality(make(plays=5), sel)
    assert not puzzles.passes_quality(make(rating_dev=300), sel)


def test_band_quota_keeps_smallest_hashes_deterministically():
    pool = [make(id=f"p{i}", rating=1500 + (i % 50)) for i in range(200)]
    sel = puzzles.Selection(per_band=10)
    chosen = puzzles.select(pool, sel)
    assert len(chosen) == 10
    expected = sorted(pool, key=lambda p: p.stable_hash)[:10]
    assert {c.puzzle.id for c in chosen} == {p.id for p in expected}
    assert {c.puzzle.id for c in puzzles.select(reversed(pool), sel)} == {c.puzzle.id for c in chosen}


def test_selection_skips_invalid_and_duplicates_without_losing_slots():
    bad = [make(id=f"bad{i}", moves="g8h8 d1e3") for i in range(5)]
    good = [make(id=f"ok{i}") for i in range(5)]
    stats = puzzles.Counter()
    chosen = puzzles.select(bad + good + good, puzzles.Selection(per_band=5), stats)
    assert sorted(c.puzzle.id for c in chosen) == sorted(p.id for p in good)
    assert stats["invalid"] == 5


def test_selection_rejects_zero_quota():
    with pytest.raises(ValueError):
        puzzles.select([make()], puzzles.Selection(per_band=0))


def test_castling_is_normalised_to_king_destination():
    p = make(fen="r3k2r/8/8/8/8/8/8/R3K2R b KQkq - 0 1", moves="e8h8 e1a1")
    assert puzzles.check(p).moves == "e8g8 e1c1"


def test_solver_color_and_validation():
    assert puzzles.solver_color(make()) == "w"  # black to move in FEN -> white solves
    assert puzzles.solver_color(make(moves="g8h8")) is None  # too short
    assert puzzles.solver_color(make(moves="g8h8 d1d8 h8h8 a1a1"[:14])) is None  # odd length
    assert puzzles.solver_color(make(moves="g8h8 d1d9")) is None  # malformed move
    assert puzzles.solver_color(make(moves="g8h8 d1e3")) is None  # illegal move
    assert puzzles.solver_color(make(fen="not a fen")) is None


def test_build_pack_schema_and_meta(tmp_path):
    out = tmp_path / "puzzles.sqlite"
    stats = puzzles.build_pack(FIXTURE.open(), out, LOOSE, "fixture")
    assert stats == {"written": 63, "invalid": 0}
    assert not (tmp_path / "puzzles.sqlite.tmp").exists()
    db = sqlite3.connect(out)
    meta = dict(db.execute("SELECT key, value FROM meta"))
    assert meta["format_version"] == "1" and meta["kind"] == "puzzles"
    assert meta["license"] == "CC0-1.0" and meta["puzzle_count"] == "63"
    assert db.execute("SELECT count(*) FROM puzzles").fetchone()[0] == 63
    solver, moves = db.execute("SELECT solver, moves FROM puzzles WHERE id = '004JD'").fetchone()
    assert solver == "b" and moves == "d2e3 a3c2"
    n_mate1 = db.execute("SELECT count FROM themes WHERE theme = 'mateIn1'").fetchone()[0]
    assert n_mate1 == db.execute(
        "SELECT count(*) FROM puzzle_themes WHERE theme = 'mateIn1'").fetchone()[0] > 0
    assert db.execute("SELECT count(*) FROM puzzles WHERE band != rating / 100").fetchone()[0] == 0


@pytest.mark.parametrize("query", [
    "SELECT id FROM puzzles WHERE band = 12 AND rnd >= 5 ORDER BY rnd LIMIT 25",
    "SELECT id FROM puzzles WHERE band = 12 AND rnd < 5 ORDER BY rnd LIMIT 25",
    "SELECT puzzle_id FROM puzzle_themes WHERE theme = 'fork' AND band = 12 AND rnd >= 5 ORDER BY rnd LIMIT 25",
])
def test_plugin_queries_are_fully_indexed(tmp_path, query):
    """The plugin's pick queries (docs/pack-format.md) must not sort on the device."""
    out = tmp_path / "puzzles.sqlite"
    puzzles.build_pack(FIXTURE.open(), out, LOOSE, "fixture")
    plan = " | ".join(r[3] for r in sqlite3.connect(out).execute("EXPLAIN QUERY PLAN " + query))
    assert "TEMP B-TREE" not in plan and ("INDEX" in plan or "PRIMARY KEY" in plan), plan


def test_zst_input_and_headerless_rows(tmp_path):
    rows = FIXTURE.read_text().splitlines()[1:]  # drop the header
    rows.append("illegal,6k1/5ppp/8/8/8/8/5PPP/3R2K1 b - - 0 1,g8h8 d1e3,1500,80,95,900,short,https://x,")
    src = tmp_path / "p.csv.zst"
    src.write_bytes(zstandard.ZstdCompressor().compress(("\n".join(rows) + "\n").encode()))
    out = tmp_path / "p.sqlite"
    with sources.open_text(src) as lines:
        stats = puzzles.build_pack(lines, out, LOOSE, "zst")
    assert stats == {"written": 63, "invalid": 1}


def test_no_pack_written_when_nothing_selected(tmp_path):
    out = tmp_path / "p.sqlite"
    strict = puzzles.Selection(min_plays=10**9)
    assert puzzles.build_pack(FIXTURE.open(), out, strict, "x")["written"] == 0
    assert not out.exists() and not (tmp_path / "p.sqlite.tmp").exists()


def test_cli_builds_from_local_file(tmp_path, capsys):
    out = tmp_path / "p.sqlite"
    code = main(["puzzles", "--input", str(FIXTURE), "--output", str(out),
                 "--min-popularity", "-100", "--min-plays", "0", "--max-rating-dev", "500"])
    assert code == 0 and out.exists()
    assert "63 puzzles" in capsys.readouterr().out


@pytest.mark.parametrize("per_band", [1, 3])
def test_cli_per_band(tmp_path, per_band):
    out = tmp_path / "p.sqlite"
    main(["puzzles", "--input", str(FIXTURE), "--output", str(out), "--per-band", str(per_band),
          "--min-popularity", "-100", "--min-plays", "0", "--max-rating-dev", "500"])
    db = sqlite3.connect(out)
    worst = db.execute("SELECT max(c) FROM (SELECT count(*) c FROM puzzles GROUP BY rating / 100)").fetchone()[0]
    assert worst == per_band
