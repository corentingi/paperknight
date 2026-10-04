# ADR-0010: Local Elo-style puzzle rating stored in progress.sqlite

- Date: 2026-10-04
- Status: accepted

## Context
Puzzles should match the user's level and the user should see progress.
Lichess uses Glicko-2 with server-side history; we are offline and single-user.
Progress must survive pack upgrades (ADR-0005).

## Options
### A. Elo update against the puzzle's rating, larger K for the first games
- Pros: a dozen lines; transparent; good enough for picking puzzle difficulty.
- Cons: no uncertainty tracking; slower to converge than Glicko.

### B. Glicko-2
- Pros: what Lichess uses; converges faster.
- Cons: more code and state for little benefit at one user's scale.

### C. No rating, user picks a difficulty band
- Pros: simplest.
- Cons: no sense of progress; manual tuning.

## Decision
A. Start at 1200. Expected score E = 1 / (1 + 10^((R_puzzle − R_user)/400)).
Score 1 if solved with no mistake and no hint/solution, else 0.
K = 60 for the first 20 attempts, 30 afterwards. Rating is clamped to 400–3000.
Stored in `<KOReader settings>/paperknight/progress.sqlite`:
`attempts(puzzle_id, ts, solved, mistakes, used_help, puzzle_rating, rating_before, rating_after)`
and `kv(key, value)` for the current rating. Next puzzle: within ±100 of the
user's rating, excluding puzzles attempted in the last 30 days when possible.

## Consequences
- Easy to replace by Glicko later: attempts keep enough data to recompute.
- A wrong first move counts as a fail even if the user then finds the line;
  the user can retry the puzzle without rating impact.
