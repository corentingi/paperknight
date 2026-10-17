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
- [ ] Make the repository public (check licences: GPL code from Kochess and
      chess.lua, CC0 data, no Lichess study text committed; README for users)
- [ ] GitHub releases: a tag per version, built by CI, with `pka.tar.gz`,
      `pkc.tar.gz`, their installers and `stockfish.gz` as release assets,
      and a small version file (version, commit, date, sha256 of each asset)
- [ ] Version shown in the plugin (a version file written into the package
      by the build; on the home screen)
- [ ] **In-app updater**: *Update Paperknight* in the title-tap menu
  1. Turn Wi-Fi on if needed (KOReader's NetworkMgr), read the latest
     release's version file, compare with the installed version; say "up
     to date" or show what is new.
  2. Download `pkc.tar.gz` (or `pka.tar.gz` when assets changed) over
     HTTPS with KOReader's network library and its CA bundle (no `curl
     -k`), with a progress message.
  3. Check the sha256 from the version file.
  4. Unpack into a staging folder, then swap the plugin folder by renames,
     keeping `bin/` (Stockfish) and the packs, as `pka.sh` does; the
     updater loads everything it needs before swapping (the running code
     stays in memory).
  5. Offer to restart KOReader.
  - Later: Stockfish and the full package through the same path.
  - Tests: an e2e scenario against a local HTTP server (as the pipeline's
    download tests), including a bad checksum and a cut download.
  - Stopgap until then: KOReader's terminal emulator, or a `update.sh`
    run from the file browser, can run `pkc.sh`.

## Later / undecided
- Stockfish is installed by `stockfish.sh` from our server (ADR-0016);
  moves to the GitHub releases with Milestone 5
- Strip unused Kochess features (clocks, human-vs-human)
- Puzzles generated from master games (lichess-puzzler)
