# Architecture

```
            PC (developer)                               Kindle (KOReader)
 ┌────────────────────────────────────┐       ┌──────────────────────────────────┐
 │ pipeline/  (Python)                │       │ plugin/paperknight.koplugin (Lua)│
 │                                    │ pka   │                                  │
 │ download ─► filter ─► build pack ──┼──────►│ packs/puzzles.sqlite (read-only) │
 │ (Lichess    (rating,   (SQLite,    │       │ paperknight/studies, repertoires │
 │  puzzles,    themes,    schema in  │       │        │                         │
 │  studies)    quality)   pack-format)       │        ▼                         │
 │                                    │       │ Home · Puzzles · Studies ·       │
 │ tools/dist: pka.tar.gz + pka.sh,   │       │ Openings · Analysis board · Play │
 │ stockfish.gz + stockfish.sh        │       │        │                         │
 └────────────────────────────────────┘       │        ▼                         │
                                               │ settings/paperknight/progress.sqlite
                                               │ (user progress, writable)        │
                                               └──────────────────────────────────┘
```

## Plugin (`plugin/paperknight.koplugin/`)

Forked from Kochess (ADR-0003); every module has the `pk` prefix so it cannot
clash with Kochess or other plugins in `package.loaded` (ADR-0009).

### Entry point and navigation

| File | Role |
|---|---|
| `_meta.lua` | Plugin name and description for KOReader's plugin manager |
| `main.lua` | The plugin: menu entries, dispatcher action, starting each mode |
| `pknav.lua` | Home screen, quick settings (frontlight, night mode, modes), switching modes (ADR-0015) |
| `pkfonts.lua` | Emoji UI fallback font when Noto Emoji is installed (ADR-0017) |

### Board and screen widgets

| File | Role |
|---|---|
| `pkboard.lua` | Board widget: squares, pieces, last move, selection, badges, arrows and circles; refreshes only the squares an update changes |
| `pkboardscreen.lua` | Board + text panel + buttons shared by the study view and the openings drill (layout, optional move list beside the board, panel text with links, refreshes, reply timer) |
| `pkbutton.lua` | KOReader's Button for icon buttons given as absolute paths; `no_feedback` (no tap flash) |
| `pkrefresh.lua` | E-ink refresh policy: steps are `[partial]` (never promoted to a flash), pages a counted `partial`; see [eink-refresh.md](eink-refresh.md) |
| `pkmovelist.lua` | Move list beside the board (#, White, Black): tap a move to go there; KOReader's scrolling |
| `pkpromotion.lua` | Promotion piece chooser |
| `pkicons.lua` | Absolute paths of the piece icons inside the plugin folder |
| `pkside.lua` | Side names with a disc marker ("○ White", "● Black"), swapped in night mode |
| `pktext.lua` | Text helpers: UTF-8 length, web addresses shown short (linkify) |
| `pklinks.lua` | Tapping a link in a panel shows its QR code |

### Puzzles

| File | Role |
|---|---|
| `pkpuzzleview.lua` | Puzzle screen: Retry / Hint / Solution / Next while solving, Retry / ‹ / › / Next to step through the line once finished; themes once finished; ☰ Theme…, Stats…, Analyse position |
| `pkpuzzle.lua` | Puzzle session state machine (pure logic) |
| `pkpuzzlepack.lua` | Read-only access to `puzzles.sqlite` (paged random picks within ±50 of the rating first) |
| `pkglicko.lua` | Glicko-2 rating math (ADR-0010) |
| `pkpuzzlereview.lua` | Missed-puzzle review ladder: 3, 7, 21 days (ADR-0014) |
| `pkpuzzlestats.lua` | Per-theme stats: clean solves / attempts and a performance rating |
| `pkstatsview.lua` | Stats screen: a bar per theme; a tap trains the theme |
| `pkthemes.lua` | Theme labels and menu order; which tags are skills and worth showing |

### Studies and openings

| File | Role |
|---|---|
| `pkpgn.lua` | PGN reader: chapter index and movetext tree (ADR-0011) |
| `pksan.lua` | Fast SAN resolver for study and repertoire trees (ADR-0013) |
| `pkstudy.lua` | Study chapters and a lazy-resolving tree cursor |
| `pkstudies.lua` | Studies browser: folders, chapter list, done marks |
| `pkstudyview.lua` | Study viewer and lesson screen |
| `pklesson.lua` | Interactive lesson rules (Lichess gamebook) on a cursor |
| `pkdone.lua` | Done marks of studies and chapters, last chapter opened |
| `pkopenings.lua` | Openings list: repertoires, their counts, caches (ADR-0012) |
| `pkrepertoire.lua` | Repertoire cards from a study tree (positions to answer) |
| `pkdrill.lua` | Drill session over a repertoire, spaced repetition (pure logic) |
| `pkdrillview.lua` | Drill screen |
| `pksrs.lua` | SM-2 scheduling and the day boundary (4 am) |
| `pkopeningnames.lua` | Opening names by position (`data/openings.tsv`, Lichess chess-openings) |
| `pkrescache.lua` | On-device cache of resolved repertoire moves (ADR-0013) |

### Play and analysis

| File | Role |
|---|---|
| `pkanalysis.lua` | Analysis board: moves for both sides, line stepping, move list (full height, can be hidden), FEN, flip; Stockfish evaluation and best line, on/off with the knight button (remembered, like the move list; one search at a time, stopped on close) |
| `pkgame.lua` | Game screen (from Kochess): against Stockfish when installed, else two players; settings saved; clock and engine stopped on close |
| `pkuci.lua` | UCI engine in a subprocess: one polling task, stopped and reaped on close |
| `pktimer.lua` | Chess clocks |
| `pksettingswidget.lua` | Player types, engine strength, time controls |
| `pkchess.lua` + `pkchesslib/` | Rules engine (move generation, FEN, SAN, PGN) from arizati/chess.lua, with a redo history |
| `pkutils.lua` | Subprocess, pipe reader and writer |

### Storage

| File | Role |
|---|---|
| `pkprogress.lua` | `progress.sqlite`: rating (Glicko-2) and attempts (ADR-0010), puzzle reviews (ADR-0014), repertoire cards, settings; migrations |

The menu entry *Paperknight* opens a submenu: *Home*, *Puzzles*, *Studies*,
*Openings*, *Analysis board* and *Play*. Stockfish is installed apart
([stockfish.md](stockfish.md), ADR-0016). Planned additions are tracked in
[`roadmap.md`](roadmap.md).

## Pipeline (`pipeline/`)

Python package `paperknight_pipeline` (ADR-0006). One sub-command per pack:
`python -m paperknight_pipeline puzzles …` (and `study` to download a
Lichess study). Inputs are cached in `build/downloads/`, outputs written to
`build/packs/`.

## Data contract

[`pack-format.md`](pack-format.md) specifies every pack table. Both sides are
tested against it; the plugin checks `meta.format_version` before use (ADR-0005).

## Testing

- Pipeline: `pytest` on small fixtures and a local HTTP server.
- Plugin logic: plain Lua specs run with the LuaJIT bundled in KOReader.
- End to end: headless desktop KOReader with a harness plugin that drives
  scenarios and takes screenshots (ADR-0007, [`development.md`](development.md)).
