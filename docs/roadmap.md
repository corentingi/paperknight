# Roadmap

## Milestone 1 — Foundation
- [x] Repository, docs, ADRs
- [x] Plugin forked from Kochess, renamed, loads in KOReader
- [x] Headless emulator harness + `make e2e`
- [x] Unit tests for the rules engine with KOReader's LuaJIT

## Milestone 2 — Offline puzzles (first training feature)
- [x] Pack format v1 (`docs/pack-format.md`)
- [x] Pipeline: Lichess puzzle CSV → `puzzles.sqlite` (filtered, stratified)
- [x] Plugin: puzzle mode (load puzzle, play opponent's first move, check
      solver moves, reply, success/fail)
- [x] Puzzle rating + progress stored in `progress.sqlite`
- [x] Theme filter (e.g. only forks, mates in 2)
- [x] Square cells, thin grey board frame
- [x] Board coordinates (a–h / 1–8)
- [ ] Test on a real Kindle Paperwhite 2

## Milestone 2b — Studies (Lichess-style)
- [x] Design (ADR-0011, docs/studies.md)
- [x] PGN parser with variations, comments, glyphs, shapes
- [x] Viewer: chapters, move tree, comments, arrows/circles
- [x] Interactive chapters (gamebook rules) + Train for ordinary chapters
- [x] Pipeline `study` download command

## Milestone 3 — Openings
- [x] Pipeline: lichess chess-openings → `data/openings.tsv` (a 425 KB table
      shipped with the plugin, not a pack)
- [x] Opening name shown in studies, the drill and the analysis board
- [x] Repertoire drill with spaced repetition (repertoire PGNs, ADR-0012)

## Milestone 4 — Master games
- [ ] Curated list (Wikipedia seed) → `games.sqlite` with Stockfish key moments
- [ ] Guess-the-move mode

## Milestone 5 — Public project and updates (after making the repo public)
Order matters: the updater reads what the releases publish.
- [x] Make the repository public (check licences: GPL code from Kochess and
      chess.lua, CC0 data, no Lichess study text committed; README for users)
- [x] GitHub releases: a tag per version, built by CI (docs/releasing.md):
      `install.sh` (the parts with their versions and sha256), one archive
      per part (plugin, puzzle pack, emoji font), a USB zip; Stockfish in a
      release of its own, offered by the installer
- [x] Version shown in the plugin (home screen, *Settings…*)
- [x] Settings screen: screen settings, version, Stockfish, project page
- [x] **In-app updater**: *Settings… → Check for updates…* runs the latest
      release's `install.sh` (`--list`, then `--yes --parts=`), Stockfish
      installed on request, then offers to restart KOReader (ADR-0019)

## Later / undecided
- Strip unused Kochess features (clocks, human-vs-human)
- Puzzles generated from master games (lichess-puzzler)
