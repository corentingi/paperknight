# ADR-0011: Studies are PGN files read on the device, parsed lazily

- Date: 2026-10-04
- Status: accepted

## Context
Lichess studies are collections of chapters (≤ 64), each a game tree with
variations, comments, annotation glyphs, arrows/circles and a board
orientation; "interactive lesson" chapters (gamebook) let the student guess
moves. Lichess exports a study as one multi-game PGN
(`GET /api/study/{id}.pgn`): chapter metadata in tags (`StudyName`,
`ChapterName`, `ChapterURL`, `Orientation` with `?orientation=true`,
`[ChapterMode "gamebook"]` for interactive chapters, `FEN`/`SetUp` for custom
starting positions), shapes as `[%csl Gd4]` / `[%cal Ge2e4]` inside comments,
comment authors as `[%anno "Name", id]`. Gamebook-only texts (hints, deviation
messages) are **not** exported. Users also have PGNs from other sources.

Packs so far are SQLite built on a PC (ADR-0005). Should studies be too?

## Options
### A. Read PGN files directly on the device
- Pros: any PGN works (Lichess export, ChessBase, books); users add studies by
  copying a file — no pipeline needed; one format to support; small files
  (real 16- and 33-chapter studies: 98 kB and 59 kB).
- Cons: parsing in Lua on a slow CPU; SAN must be resolved with the rules engine.

### B. Convert to a SQLite "studies pack" in the pipeline
- Pros: pre-validated, fast to load.
- Cons: forces every study through a PC; loses the "drop a PGN" workflow;
  more schema to maintain for what is essentially a tree of text.

## Decision
A, with **lazy parsing** to stay fast on the PW2:
1. Opening a file only scans tag sections to build the chapter list (no move parsing).
2. Opening a chapter tokenises its movetext into a tree of SAN nodes
   (comments, glyphs, shapes attached) without the rules engine.
3. SAN is resolved to moves only along the path the user walks; positions are
   cached per visited node. An unresolvable SAN shows an error at that node
   instead of failing the whole file.

Studies live in `<KOReader data dir>/paperknight/studies/` (survives plugin
updates; on a Kindle `/mnt/us/koreader/paperknight/studies/`); any other PGN can
be opened with a file chooser. The pipeline gains a `study` command that
downloads a Lichess study export with the right flags and validates it with
python-chess, but it is optional.

## Consequences
- The PGN parser (`pkpgn.lua`) and the tree/cursor model (`pkstudy.lua`) are
  pure Lua and unit-tested on a fixture that mimics Lichess exports.
- Interactive chapters follow Lichess's gamebook rules (see docs/studies.md);
  our hints are generic (square of the piece) since Lichess hints aren't exported.
- Revisit B if very large PGN collections (thousands of games) become a use
  case; that is a "game database", not a study.
