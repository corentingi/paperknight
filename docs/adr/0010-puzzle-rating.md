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
and `kv(key, value)` for the current rating.

An attempt is recorded once per puzzle load: when the puzzle ends (solved or
solution shown), or when the user leaves it (Next, Retry, close) after having
"touched" it — a mistake, a hint, or at least one correct move (part of the
line has been seen). Leaving an untouched puzzle records nothing. Retry after
a recorded attempt replays without rating impact.

Next puzzle (pack `band` = rating / 100, see pack format): an unseen puzzle
(not attempted in the last 30 days) within ±2 bands of the user's rating,
home band first; else an unseen one in further bands (nearest first); only
then a recently seen one, near bands first, and the status line says puzzles
are being repeated. Whatever the fallback, the next puzzle is never the
current one, nor one already shown in this session until all the eligible
ones have been (then a new round starts), nor one waiting as a review
(ADR-0014). (Amended: unseen far puzzles used to come after recently seen
near ones, which made a small theme repeat the same puzzle.)

## Consequences
- Easy to replace by Glicko later: attempts keep enough data to recompute.
- A wrong first move counts as a fail even if the user then finds the line;
  the user can retry the puzzle without rating impact.
