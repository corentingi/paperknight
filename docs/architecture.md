# Architecture

```
            PC (developer)                               Kindle (KOReader)
 ┌────────────────────────────────────┐       ┌──────────────────────────────────┐
 │ pipeline/  (Python)                │       │ plugin/paperknight.koplugin (Lua)│
 │                                    │install│                                  │
 │ download ─► filter ─► build pack ──┼──────►│ packs/puzzles.sqlite (read-only) │
 │ (Lichess    (rating,   (SQLite,    │       │ paperknight/studies, repertoires │
 │  puzzles,    themes,    schema in  │       │        │                         │
 │  studies)    quality)   pack-format)       │        ▼                         │
 │                                    │       │ Home · Puzzles · Studies ·       │
 │ tools/dist: install.sh + one       │       │ Openings · Analysis board · Play │
 │ archive per part, Stockfish        │       │        │                         │
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
| `pksettings.lua` | Settings screen: screen settings, board settings, version and updates, Stockfish, project page |
| `pkprefs.lua` | The user's on/off preferences (board coordinates, legal moves), saved in `progress.sqlite` |
| `pkupdate.lua` | In-app update: fetches the latest `install.sh`, shows what changed (`--list`), runs it for those parts (ADR-0019) |
| `pkfonts.lua` | Emoji UI fallback font when Noto Emoji is installed (ADR-0017) |

### Board and screen widgets

| File | Role |
|---|---|
| `pkboard.lua` | Board widget, shared by every mode: squares, pieces, last move (corner triangles), selection (with the legal moves: dots, rings on captures), badges, arrows and circles, coordinates (a setting) and the side to move in their corner (a disc, shown while the board takes moves); DU4 refreshes of the squares an update changes (ADR-0018) |
| `pkboardscreen.lua` | Board + text panel + buttons shared by the study view, the openings drill and Play (layout, optional move list beside the board, panel text with links, refreshes, reply timer) |
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
| `pkpuzzleview.lua` | Puzzle screen: Retry / Hint / Solution / Next (greyed until the puzzle is over) while solving, Retry / ‹ / › / Next to step through the line once finished; themes once finished; ☰ Theme…, Stats…, Analyse position (the analysis board with the puzzle's line), Like this puzzle, Liked puzzles…, Open a puzzle by its id… (chosen puzzles are not rated), the puzzle and its game on Lichess (QR codes) |
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
| `pkanalysis.lua` | Analysis board: moves for both sides, line stepping, move list (full height, can be hidden), position from a FEN or a line handed over (☰ Analyse position in puzzles and studies: the line that led to the position, and what follows), the position on Lichess (QR code, the FEN under it), flip, save the line as a study (Studies/Analyses); Stockfish evaluation and best line, on/off with the knight button (remembered, like the move list; one search at a time, stopped on close) |
| `pkplay.lua` | Play logic (ADR-0020): settings (opponent, side, Stockfish's level, face to face, clock), sides, take-back, results, PGN, the game in progress saved and restored |
| `pkplayview.lua` | Play screen (board, panel, move list, buttons: pkboardscreen.lua): Stockfish's moves (one search at a time, stale answers dropped), clocks, ☰ resign / flip / move list / save as a study (Studies/Games), Analyse (also a tap in the move list), resumed when opened |
| `pkplaysetup.lua` | New game dialog: radio buttons for the opponent, your side, Stockfish's strength, seats (face to face: Black's pieces upside down), clock |
| `pkgames.lua` | Master games (`data/games.tsv`, ADR-0021) and a Guess the move session: the opening played, guesses judged (the master's move, a good move by Stockfish's scores, a miss), hints, key moments, score, saved and resumed |
| `pkgamesview.lua` | Master games list (Continue, best scores) and the Guess the move screen (pkboardscreen.lua): verdicts, Hint / Show move / Analyse, ☰ the other side, start again, move list |
| `pkengine.lua` | Where Stockfish is installed (`bin/stockfish`) |
| `pkuci.lua` | UCI engine in a subprocess: one polling task, stopped and reaped on close |
| `pktimer.lua` | Chess clocks |
| `pkchess.lua` + `pkchesslib/` | Rules engine (move generation, FEN, SAN, PGN) from arizati/chess.lua, with a redo history |
| `pkutils.lua` | Subprocess, pipe reader and writer |

### Storage

| File | Role |
|---|---|
| `pkprogress.lua` | `progress.sqlite`: rating (Glicko-2) and attempts (ADR-0010), puzzle reviews (ADR-0014), liked puzzles, repertoire cards, settings; migrations |

The menu entry *Paperknight* opens a submenu: *Home*, *Puzzles*, *Studies*,
*Openings*, *Analysis board*, *Play* and *Master games*. Stockfish is installed apart
([stockfish.md](stockfish.md), ADR-0016). Planned additions are tracked in
[`roadmap.md`](roadmap.md).

## Pipeline (`pipeline/`)

Python package `paperknight_pipeline` (ADR-0006). One sub-command per pack:
`python -m paperknight_pipeline puzzles …` (and `study` to download a
Lichess study, `openings` for the opening names, `games` for the master
games with Stockfish's scores: [games.md](games.md)). Inputs are cached in `build/downloads/`, outputs written to
`build/packs/`.

## Data contract

[`pack-format.md`](pack-format.md) specifies every pack table. Both sides are
tested against it; the plugin checks `meta.format_version` before use (ADR-0005).

## Testing

- Pipeline: `pytest` on small fixtures and a local HTTP server.
- Plugin logic: plain Lua specs run with the LuaJIT bundled in KOReader.
- End to end: headless desktop KOReader with a harness plugin that drives
  scenarios and takes screenshots (ADR-0007, [`development.md`](development.md)).
