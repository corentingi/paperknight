# Pack format

Status: v1 — `puzzles` pack implemented (pipeline `paperknight_pipeline/puzzles.py`).

Every pack is a SQLite 3 file with a `meta` table:

| key | value |
|---|---|
| `format_version` | integer as text, e.g. `1` |
| `kind` | `puzzles` · `openings` · `games` |
| `built_at` | ISO 8601 UTC |
| `source` | human-readable provenance (URL + date) |
| `license` | e.g. `CC0-1.0` |

The plugin refuses a pack whose `format_version` it does not support.
Pack-specific tables are specified below. Packs are read-only on the device;
user progress lives in a separate `progress.sqlite` (ADR-0005).

## `puzzles` pack, format_version 1

File: `puzzles.sqlite`. Extra meta keys: `puzzle_count`, and `selection`:
the build thresholds as space-separated `key=value` pairs (informational,
ADR-0008).

### `puzzles`
| column | type | meaning |
|---|---|---|
| `id` | TEXT PK | Lichess puzzle id (`https://lichess.org/training/<id>`) |
| `fen` | TEXT | Position **before** the opponent's setup move |
| `moves` | TEXT | Space-separated UCI moves, even count. `moves[1]` (1-based) is the opponent's setup move, then solver and opponent alternate; the last move is the solver's. Castling is written king-to-destination (`e1g1`, `e8c8`); promotions carry a lowercase letter (`b7b8n`) |
| `solver` | TEXT | `w` or `b`: the side the user plays (opposite of the FEN side to move) |
| `rating` | INTEGER | Lichess puzzle rating (Glicko-2) |
| `rating_dev` | INTEGER | Rating deviation |
| `popularity` | INTEGER | −100…100, Lichess votes |
| `plays` | INTEGER | Times played on Lichess |
| `themes` | TEXT | Space-separated theme keys (e.g. `fork middlegame short`) |
| `opening` | TEXT | Space-separated opening tags (may be empty) |
| `game_url` | TEXT | Source game on Lichess |
| `band` | INTEGER | `rating / 100` (integer division), for indexed picks |
| `rnd` | INTEGER | Stable pseudo-random key in [0, 2³¹) (hash of `id`) for random picks |

Index `puzzles_band_rnd (band, rnd)`.

### `puzzle_themes`
`(theme TEXT, band INTEGER, rnd INTEGER, puzzle_id TEXT)`, primary key
`(theme, band, rnd, puzzle_id)`, WITHOUT ROWID: one row per theme of each
puzzle (`band`/`rnd` copied from `puzzles`) so theme picks are indexed too.

### `themes`
`(theme TEXT PK, count INTEGER)`: themes present in the pack and how many
puzzles carry each, for building menus.

### Picking a random puzzle (plugin side)
Choose a band `b` (the plugin first tries the bands overlapping a ±50
window around the user's rating, keeping rows rated inside it) and a random `r` in [0, 2³¹), then page through the band
in key order from `r`, wrapping around, until a row is acceptable (not seen
recently, not under review):

```sql
SELECT … , rnd FROM puzzles WHERE band = :b AND rnd >= :lo AND rnd < :hi ORDER BY rnd LIMIT 100;
-- first [r, 2^31), then [0, r); the next page starts after the last rnd read
-- by theme: same shape on puzzle_themes (theme = :t AND band = :b AND rnd …), joined by id
```

Both are answered from an index without sorting (tested in the pipeline).

### Solving rules (plugin side)
1. Load `fen`, play `moves[1]` (opponent), show the board from `solver`'s side.
2. For i = 2, 4, …: the user's move must equal `moves[i]` (UCI, promotion
   letter included). Exception: a move that delivers checkmate is accepted
   and the puzzle is **solved immediately** (no further moves are played).
3. After a correct move, play `moves[i+1]` automatically.
4. Solved when the user has played the last move.
