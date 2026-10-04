# ADR-0009: Puzzle mode as a separate screen with pure-Lua session logic

- Date: 2026-10-04
- Status: accepted

## Context
The inherited `main.lua` is a single 1,100-line widget for "play vs engine"
(clocks, PGN log, engine). Puzzle mode needs the same board and rules engine
but a different flow: load a position, auto-play the opponent's moves, judge
the user's moves, show hints/solution, record results. We want the judging
logic covered by fast unit tests, not only by e2e screenshots.

## Options
### A. New screen `pkpuzzleview.lua` + pure modules
- `pkpuzzle.lua`: puzzle session state machine (no UI), driven by the rules
  engine only → unit-testable with LuaJIT.
- `pkpuzzlepack.lua`: read-only access to `puzzles.sqlite` (lua-ljsqlite3).
- `pkprogress.lua`: user rating and attempt history (ADR-0010).
- Board widget gains `flipped` and a callback-free `showMove`.
- Pros: clear seams; logic tested without UI; play mode untouched.
- Cons: some layout code duplicated with `main.lua` until a later refactor.

### B. Add a "puzzle" flag to the existing `main.lua` widget
- Pros: reuses the toolbar/log layout.
- Cons: entangles clocks/engine/PGN with puzzle flow; hard to test; grows the
  monolith we may strip later.

## Decision
A. The plugin menu becomes a submenu: *Play against engine* (existing screen)
and *Puzzles*. New modules use a `pk` prefix (`pkpuzzle`, …) to avoid
`package.loaded` clashes with other chess plugins; renaming the inherited
generic modules (`board`, `chess`, …) is deferred.

## Consequences
- The session API (`start`, `tryMove`, `hint`, `solution`) is the contract the
  view and the tests share.
- The promotion dialog moves out of `main.lua` into a shared module so both
  screens use it.
- Packs are looked up in `<plugin>/packs/`, overridable with
  `PAPERKNIGHT_PACKS_DIR` (used by e2e with a fixture pack).
