# ADR-0021: Master games — a curated list, PGN Mentor moves, Stockfish scores in the plugin

- Date: 2026-10-28
- Status: accepted

## Context
Milestone 4 asks for famous master games and a *Guess the move* mode: the
user plays one side of a game and is judged against the master's moves.
Three things are costly to change once shipped: where the games come from
(licences), how a guess that is not the master's move is judged, and where
the data lives (pack, plugin, part of the installer).

## Options
### Source of the games
**A. A curated list matched in PGN Mentor's player files** (free downloads;
moves are facts). Our own list (`pipeline/data/master-games.tsv`): players,
year, result, round or a piece of the moves when needed, our own title and
one-line note. The build stops if a line matches no game or several.
- Pros: reproducible; no text of anyone else's; a typo is caught.
- Cons: a game must be in a player's file; ~40 games to start with.

**B. Lichess's broadcasts or a big database (Lumbra, TWIC).**
- Pros: many more games.
- Cons: no curation (a famous game is the point), mixed provenance,
  gigabytes to download.

### Judging a guess
**A. The master's move only.** Simple, but a move as good is a "miss".
**B. Stockfish's scores, computed on the PC**: for each position, its three
best moves with their scores and the score of the master's move. A guess
Stockfish rates within 5 points of winning chances (Lichess's scale) of the
master's move is a good move too.
- Cons: a good move outside the three best is a miss (no engine on the
  device needed, which most users do not have).
**C. Stockfish on the device.** Exact, but needs Stockfish installed and
seconds per move on a Paperwhite 2.

### Where the data lives
**A. `data/games.tsv` in the plugin** (one game a line, UCI moves, the
scores), like `data/openings.tsv`. **B. An SQLite pack, a part of its own in
the installer.** A is ~300 kB and needs no installer change; B pays off at
thousands of games.

## Decision
- Source **A**, scores **B**, data **A**.
- Stockfish 18 at depth 14, one thread (the same result each run), on every
  ply after the opening (the plies through the last named position of
  `data/openings.tsv` are played, not guessed); answers cached in
  `build/downloads/games-analysis/`.
- **Key moments**: the master's move is within 3 points of the best and 15
  points of winning chances ahead of every other move, not an answer to a
  check nor a recapture. They are announced before the move ("one move
  stands out") and counted apart.
- **Scoring**: the master's move 2 points, a good move 1, a miss or *Show
  move* 0; the master's move after a hint counts as a good move. The best
  percentage of each game is kept; the session in progress comes back.
- The side guessed is the winner's (White in a draw); ☰ switches.

## Consequences
- `python -m paperknight_pipeline games --engine <stockfish>` rebuilds the
  file (an hour on a laptop, minutes from the cache); its output is
  committed. CI does not run it.
- Adding a game: a line in `master-games.tsv` and a rebuild.
- Revisit B for the data if the list grows past a few hundred games, and C
  for judging if most users have Stockfish.
