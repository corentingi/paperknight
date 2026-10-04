# ADR-0003: Fork Kochess (omer-faruq v1.0.1) by copying, GPL-3.0

- Date: 2026-10-04
- Status: accepted

## Context
Kochess provides a working board, touch move input, UCI engine wrapper, clocks,
PGN load/save. Three lineages exist:
- [bateast/kochess](https://github.com/bateast/kochess) — original, 7 commits,
  `chess.lua` as a git submodule, engine path in KOReader's `resources/bin`.
- [omer-faruq/chess.koplugin](https://github.com/omer-faruq/chess.koplugin)
  v1.0.1 (commit `2916acf`, 2025-11-30) — bateast + vendored `chess.lua`,
  plugin-local engine path, game-over detection, icon auto-install.
- coffman/kochess.koplugin and MJCopper/casualkochess — larger forks
  (evaluation, openings, other games) with more code to own.

We also need to choose how to import: preserve upstream git history or copy.

## Options
### A. Copy omer-faruq v1.0.1 into `plugin/`, record the upstream commit
- Pros: smallest codebase with the fixes we want; no submodule; no 55 MB
  Stockfish binary in our history.
- Cons: upstream history not in our `git log` (credited in docs instead).

### B. `git subtree` import with history
- Pros: full blame history.
- Cons: drags the 55 MB debug Stockfish binary into history forever.

### C. Fork a larger lineage (casualkochess)
- Pros: more features (eval line, ECO names, save/restore).
- Cons: 3× the code, three unrelated games to strip. We can port the few
  features we want later.

## Decision
A. Copy the omer-faruq tree at `2916acf`, excluding `bin/stockfish` and the
`Games/` sample PGNs, into `plugin/paperknight.koplugin/`. License stays
GPL-3.0-or-later; authors are credited in `docs/credits.md`.

## Consequences
- Unused Kochess features (human-vs-human, clocks) stay for now; stripping
  them later is a separate decision.
- The engine binary is provided separately (see a later ADR).
- Upstream fixes must be ported by hand; `docs/credits.md` records the base commit.
