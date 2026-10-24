# ADR-0020: Play rewritten on the app's board screen

- Date: 2026-10-24
- Status: accepted

## Context
Play was Kochess's game screen (`pkgame.lua`, `pksettingswidget.lua`): its
own layout (a toolbar beside a PGN log, a status bar with clocks and a
play/pause tick), PGN files loaded and saved through file choosers,
settings in a dialog of spinners, and "two players" only when Stockfish
was missing. The other modes share one screen (board, panel, move list,
button bar, ☰ menu, the e-ink refresh rules: `pkboardscreen.lua`). Two
players sharing a Kindle sit face to face, so one of them reads the pieces
upside down.

## Options
### A. Restyle pkgame.lua
- Pros: less new code.
- Cons: its structure (game state, engine, clocks and UI in one widget;
  undo/redo as navigation) stays apart from the rest of the app and from
  its tests.

### B. A new Play mode, logic apart from the screen
`pkplay.lua` (settings, sides, take-back, results, the saved game; unit
tested), `pkplayview.lua` on `pkboardscreen.lua`, `pkplaysetup.lua` (the new
game dialog, radio buttons).
- Pros: Play works like the other modes (menu, move list, Analyse, save as
  a study); the rules are tested without a screen.
- Cons: a rewrite; the PGN loading of the old screen goes (studies open
  PGN files).

## Decision
B. Choices made with it:
- The new game dialog: opponent (Stockfish, two players), your side (White,
  Black, random), Stockfish's strength (1350, 1500, 1800, 2100, 2400 Elo with
  `UCI_LimitStrength`, or full strength; 1 to 5 s per move by level), seats
  for two players (face to face: Black's pieces drawn upside down, by the
  board's `rotate_black`), clock (none, 5, 10, 15+10, 30 min). Remembered.
- Take back: to the user's last move against Stockfish (its reply too), one
  move between two players; also after the end (the game goes on).
- Clocks run from a move to the next; a take-back or reopening pauses them
  until the next move (no play/pause button).
- The game in progress is saved after each move (`play.current`: settings,
  the side drawn, moves, clocks) and comes back when Play opens; a finished
  game is not kept.
- Games are saved as studies in Studies → Games; Analyse (or a tap in the
  move list) hands the game to the analysis board.

## Consequences
- `pkgame.lua` and `pksettingswidget.lua` are gone (the old `play.*`
  settings are ignored); `pkengine.lua` says where Stockfish is.
- Text stays readable from White's side only (the panel, the clocks in the
  subtitle): for the player across, the board is what matters.
- Revisit for a game from a position (from the analysis board), or the
  clocks shown upside down for the player across.
