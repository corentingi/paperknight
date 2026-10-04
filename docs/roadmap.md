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
- [ ] Design (ADR-0011, docs/studies.md)
- [ ] PGN parser with variations, comments, glyphs, shapes
- [ ] Viewer: chapters, move tree, comments, arrows/circles
- [ ] Interactive chapters (gamebook rules)
- [ ] Pipeline `study` download command

## Milestone 3 — Openings
- [ ] Pipeline: lichess chess-openings → `openings.sqlite`
- [ ] Opening name shown during play
- [ ] Repertoire drill with spaced repetition

## Milestone 4 — Master games
- [ ] Curated list (Wikipedia seed) → `games.sqlite` with Stockfish key moments
- [ ] Guess-the-move mode

## Later / undecided
- How to ship Stockfish for the PW2 (download script vs. build vs. release asset)
- Strip unused Kochess features (clocks, human-vs-human)
- Puzzles generated from master games (lichess-puzzler)
