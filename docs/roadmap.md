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
- [ ] Theme filter (e.g. only forks, mates in 2) — pack already indexed for it
- [ ] Board coordinates (a–h / 1–8), square cells
- [ ] Test on a real Kindle Paperwhite 2

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
