# Architecture Decision Records

One file per decision that is costly to reverse: `NNNN-kebab-title.md`.
Each records the context, the options honestly considered, the decision and its
consequences. Superseded ADRs stay in place with their status updated.

Template: [`0000-template.md`](0000-template.md).

| ADR | Decision | Status |
|---|---|---|
| [0001](0001-record-decisions-as-adrs.md) | Record decisions as ADRs in `docs/adr/` | accepted |
| [0002](0002-koreader-plugin.md) | Ship as a KOReader plugin | accepted |
| [0003](0003-fork-kochess-by-copy.md) | Fork Kochess (omer-faruq v1.0.1) by copying, GPL-3.0 | accepted |
| [0004](0004-monorepo-plugin-and-pipeline.md) | One repo, two spaces: `plugin/` and `pipeline/` | accepted |
| [0005](0005-sqlite-data-packs.md) | Ship data as offline SQLite packs | accepted |
| [0006](0006-python-pipeline.md) | Write the data pipeline in Python | accepted |
| [0007](0007-headless-koreader-emulator.md) | Test in a headless desktop KOReader | accepted |
| [0008](0008-puzzle-selection.md) | Select puzzles by quality + deterministic per-band quota | accepted |
| [0009](0009-puzzle-mode-architecture.md) | Puzzle mode as a separate screen with pure-Lua session logic | accepted |
| [0010](0010-puzzle-rating.md) | Local Elo-style puzzle rating in progress.sqlite | accepted |
| [0011](0011-studies-from-pgn.md) | Studies are PGN files read on the device, parsed lazily | accepted |
| [0012](0012-openings-trainer.md) | Openings trainer: repertoire PGNs, per-move cards, SM-2 | accepted |
| [0013](0013-fast-san-resolver.md) | Dedicated SAN resolver for PGN moves; chess.lua for play | accepted |
| [0014](0014-missed-puzzle-reviews.md) | Missed puzzles come back as reviews on a fixed ladder | accepted |
| [0015](0015-navigation-and-quick-settings.md) | Home screen and quick settings for navigation and screen settings | accepted |
