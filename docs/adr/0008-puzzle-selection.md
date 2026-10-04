# ADR-0008: Select puzzles by quality, then a deterministic quota per rating band

- Date: 2026-10-04
- Status: accepted

## Context
The Lichess dump has 6.16M puzzles (~1 GB uncompressed). The PW2 has 2–4 GB of
storage and a slow CPU, and a training tool needs puzzles across all levels,
not a copy of the dump's skew towards 1200–2000. Rebuilding the pack from a newer
monthly dump should not reshuffle everything a user has already seen.

## Options
### A. Quality filter + per-band quota, chosen by a stable hash of the puzzle id
- Pros: every 100-point band gets up to N puzzles (default 2,500 → ~60k
  puzzles, ~15–25 MB); well-tested puzzles only (popularity ≥ 80, plays ≥ 300,
  rating deviation ≤ 90); deterministic and mostly stable across dumps; streams
  the dump with one bounded heap per band.
- Cons: rare themes are not guaranteed coverage; the hash ignores puzzle quality
  beyond the threshold.

### B. Random sample
- Pros: simplest.
- Cons: reproduces the dump's rating skew; not reproducible without a seed and
  unstable across dumps.

### C. Top-N most popular per band
- Pros: highest-rated puzzles.
- Cons: popularity correlates with "easy and flashy"; skews themes; changes as
  votes change between dumps.

## Decision
A, with all thresholds as CLI options so the pack can be tuned per device.

## Consequences
- Invalid lines (python-chess) are rejected before they take a slot.
- The plugin picks a puzzle near the user's rating with a fully indexed query
  on a `band = rating / 100` column (`band = ? AND rnd >= ? ORDER BY rnd`); a
  `rating BETWEEN` range cannot be ordered by `rnd` from an index.
- Revisit with per-theme minimums if theme training (e.g. "only forks") shows
  empty or tiny themes in practice.
