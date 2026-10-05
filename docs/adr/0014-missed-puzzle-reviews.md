# ADR-0014: Missed puzzles come back as reviews on a fixed ladder

- Date: 2026-10-05
- Status: accepted

## Context
A missed puzzle (mistake, hint or solution) is only recorded for the rating
(ADR-0010) and never seen again: the tactic that was missed is not
reinforced. The openings trainer already has spaced repetition (ADR-0012).
Reviews add stored state (progress.sqlite) that is costly to reshape later.

## Options
### A. Reuse SM-2 (pksrs.grade) as for repertoire cards
- Pros: one algorithm; ease adapts per puzzle.
- Cons: SM-2 relearns the same day after a miss (right for a move to
  memorise, wrong for a puzzle whose solution was just shown); ease never
  ends, so reviews pile up forever.

### B. Fixed ladder: next day after a miss, then 3, 7, 21 days, then mastered
- Pros: simple to explain and to see ("Next review in 7 days"); a review
  ends after four clean solves in a row, so the queue stays small; a miss
  starts over.
- Cons: no per-puzzle adaptation.

### C. A separate "missed puzzles" list to replay on demand
- Pros: no scheduling.
- Cons: the user must remember to use it; no spacing.

## Decision
B. Puzzles are not moves to memorise: the goal is to see the pattern again
a few times at growing intervals, then stop. Reviews are served first in
the normal puzzle flow (theme filter applies), once per session each, and
do not change the rating (only first attempts count, ADR-0010). They are
stored in `puzzle_reviews` (puzzle id, due day, step, lapses, first miss);
day numbers come from `PkSrs.today` (4 am boundary). Misses of the last 60
days are turned into reviews once, spread over a week.

## Consequences
- Pure logic in `pkpuzzlereview.lua` (unit-tested); the view only wires it.
- Replacing the pack drops reviews of puzzles it no longer has.
- A puzzle in reviews is not picked as a new puzzle.
- Revisit if users want reviews to affect the rating, or adaptive spacing.
