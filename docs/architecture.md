# Architecture

```
            PC (developer)                               Kindle (KOReader)
 ┌────────────────────────────────────┐       ┌──────────────────────────────────┐
 │ pipeline/  (Python)                │       │ plugin/paperknight.koplugin (Lua)│
 │                                    │ copy  │                                  │
 │ download ─► filter ─► build pack ──┼──────►│ packs/*.sqlite   (read-only)     │
 │ (Lichess,    (rating,   (SQLite,   │       │        │                         │
 │  PGN Mentor,  themes,    schema in  │       │        ▼                         │
 │  TWIC…)       curation)  pack-format)       │ modes: Play · Puzzles · Openings │
 └────────────────────────────────────┘       │        · Master games            │
                                               │        │                         │
                                               │        ▼                         │
                                               │ settings/paperknight/progress.sqlite
                                               │ (user progress, writable)        │
                                               └──────────────────────────────────┘
```

## Plugin (`plugin/paperknight.koplugin/`)

Forked from Kochess (ADR-0003). Current modules, inherited:

| File | Role |
|---|---|
| `_meta.lua` | Plugin name/description for KOReader's plugin manager |
| `main.lua` | Entry point: menu registration, game screen, engine lifecycle |
| `board.lua` | Board widget: draws squares and pieces, handles taps |
| `chess.lua` + `chess/` | Rules engine (move generation, FEN, SAN, PGN), from arizati/chess.lua |
| `uci.lua` | Talks to a UCI engine (Stockfish) through a subprocess |
| `timer.lua` | Chess clocks |
| `settingswidget.lua` | Player types, engine strength, time controls |
| `button.lua`, `buttontable.lua` | Patched copies of KOReader button widgets |
| `utils.lua` | Helpers |

Paperknight modules (prefixed `pk` to avoid `package.loaded` clashes, ADR-0009):

| File | Role |
|---|---|
| `pkpuzzleview.lua` | Puzzle screen: board, status line, Hint / Solution / Retry / Next |
| `pkpuzzle.lua` | Puzzle session state machine (pure logic, unit-tested) |
| `pkpuzzlepack.lua` | Read-only access to `puzzles.sqlite` (indexed random picks) |
| `pkprogress.lua` | User rating + attempt history in `progress.sqlite` (ADR-0010) |
| `pkpromotion.lua` | Promotion piece chooser shared by both screens |
| `pkicons.lua` | Absolute paths of the piece icons inside the plugin folder |

The menu entry *Paperknight* opens a submenu: *Puzzles* and *Play against the
engine*. Planned additions are tracked in [`roadmap.md`](roadmap.md).

## Pipeline (`pipeline/`)

Python package `paperknight_pipeline` (ADR-0006). One sub-command per pack:
`python -m paperknight_pipeline puzzles …`. Inputs are cached in
`build/downloads/`, outputs written to `build/packs/`.

## Data contract

[`pack-format.md`](pack-format.md) specifies every pack table. Both sides are
tested against it; the plugin checks `meta.format_version` before use (ADR-0005).

## Testing

- Pipeline: `pytest` on small fixtures.
- Plugin logic: plain Lua tests run with the LuaJIT bundled in KOReader.
- End to end: headless desktop KOReader with a harness plugin that drives
  scenarios and takes screenshots (ADR-0007, [`development.md`](development.md)).
