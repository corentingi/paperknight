# Master games — Guess the move

*Master games* (home screen) lists famous games, from Anderssen's Immortal
Game (1851) to Aronian – Anand (2013). Open one and play the master's side:

- The opening is played for you, up to the last named position.
- At each of your moves, play the move you think the master played. The
  master's move is then played whatever you chose, then the other side's
  reply.
- **✓ the master's move** (2 points); **a good move too** (1 point): one
  Stockfish rates about as well as the master's; otherwise the panel shows
  what was played, and Stockfish's view of both moves.
- **Key moments**: positions where one move stands out (the master found
  the only good move). The panel says so before you move.
- **Hint** circles the piece the master moved (the move then counts as a
  good move); **Show move** plays it (no point).
- At the end: the moves found, the key moments, a percentage. The best
  percentage of each game shows in the list. A game in progress comes back
  (*Continue* at the top of the list).
- **☰**: guess the other side's moves instead, start again, the move list,
  the list of games. **Analyse** (or a tap in the move list) opens the game
  on the analysis board.

You play the winner's side by default (White in a draw).

## The data

`plugin/paperknight.koplugin/data/games.tsv`, built on a PC (ADR-0021):

    make games STOCKFISH=/path/to/stockfish GAMES_THREADS=2

- The list is `pipeline/data/master-games.tsv`: one line a game, with the
  players' surnames as PGN Mentor writes them, the year, the result, and,
  when a player's file has several matching games, the round or a piece of
  the moves (`Qxf3`). Title and note are ours.
- The moves come from PGN Mentor's player files
  (`https://www.pgnmentor.com/players/<name>.zip`, cached in
  `build/downloads/pgnmentor/`). The site refuses Python's default
  User-Agent: the pipeline names itself, and waits between downloads.
- Stockfish (a binary for the PC, e.g. the official
  `stockfish-ubuntu-x86-64-avx2`) scores every position after the opening at
  depth 14: its three best moves, and the master's move if it is not one of
  them (`GAMES_THREADS` threads, 2 by default: about a minute or two a game
  on a laptop). Answers are cached in `build/downloads/games-analysis/`: a
  rebuild after adding a game only analyses that game.

The file format is described at the top of
`pipeline/paperknight_pipeline/games.py`.
