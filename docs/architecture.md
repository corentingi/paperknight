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

Forked from Kochess (ADR-0003). Inherited modules (renamed with the `pk` prefix so they cannot clash with Kochess or other chess plugins in `package.loaded`):

| File | Role |
|---|---|
| `_meta.lua` | Plugin name/description for KOReader's plugin manager |
| `main.lua` | Entry point: menu registration, game screen, engine lifecycle |
| `pkboard.lua` | Board widget: draws squares and pieces, handles taps |
| `pkchess.lua` + `pkchesslib/` | Rules engine (move generation, FEN, SAN, PGN), from arizati/chess.lua |
| `pkuci.lua` | Talks to a UCI engine (Stockfish) through a subprocess |
| `pktimer.lua` | Chess clocks |
| `pksettingswidget.lua` | Player types, engine strength, time controls |
| `pkbutton.lua`, `pkbuttontable.lua` | Patched copies of KOReader button widgets |
| `pkutils.lua` | Helpers |

Paperknight modules (prefixed `pk` to avoid `package.loaded` clashes, ADR-0009):

| File | Role |
|---|---|
| `pkpuzzleview.lua` | Puzzle screen: board, status line, Hint / Solution / Retry / Next |
| `pkpuzzle.lua` | Puzzle session state machine (pure logic, unit-tested) |
| `pkpuzzlereview.lua` | Missed-puzzle review ladder (pure logic, ADR-0014) |
| `pkrefresh.lua` | E-ink refresh policy of the board screens ("partial", like page turns) |
| `pkrescache.lua` | On-device cache of resolved repertoire moves (ADR-0013) |
| `pkpuzzlepack.lua` | Read-only access to `puzzles.sqlite` (indexed random picks) |
| `pkprogress.lua` | `progress.sqlite`: rating + attempts (ADR-0010), puzzle reviews (ADR-0014), repertoire cards, settings |
| `pkpromotion.lua` | Promotion piece chooser shared by both screens |
| `pkicons.lua` | Absolute paths of the piece icons inside the plugin folder |
| `pkthemes.lua` | Puzzle theme labels and menu order |
| `pkpgn.lua` | PGN reader: chapter index + movetext tree (ADR-0011) |
| `pkstudy.lua` | Study chapters and a lazy-resolving tree cursor |
| `pklesson.lua` | Interactive lesson rules (Lichess gamebook) on a cursor |
| `pkstudies.lua` | Studies browser (folder listing, chapter list) |
| `pkstudyview.lua` | Study viewer and lesson screen |

The menu entry *Paperknight* opens a submenu: *Puzzles*, *Studies* and
*Play against the engine*. Planned additions are tracked in [`roadmap.md`](roadmap.md).

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
