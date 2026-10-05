# ADR-0013: A dedicated SAN resolver for PGN moves; chess.lua for play

- Date: 2026-10-05
- Status: accepted

## Context
PGN moves are SAN (`Nf3`, `exd5`, `O-O`): resolving one needs the position.
The rules library inherited from Kochess (chess.lua, a chess.js port)
resolves SAN by generating every legal move, writing each in SAN (with a
check test each) and comparing strings: ~130 µs per move on a desktop, and
a FEN reload around it. A 2.5k-card repertoire takes ~2 s on a desktop
(ADR-0012 walk), probably ~20 s on a Paperwhite 2. Studies and lessons
resolve moves the same way, lazily.

## Options
### A. Optimize chess.lua's `move_from_san`
- Pros: one engine.
- Cons: upstream code (fork by copy, ADR-0003) with globals and a redo
  stack; deep changes are risky for interactive play, which works.

### B. A small dedicated resolver (`pksan.lua`) for PGN moves
Parse the SAN (piece, target, disambiguation, promotion), look only at the
pieces of that type that can reach the target (knight jumps, slider rays
from the target, pawn pushes/captures), check legality of those candidates
only (own king not attacked after the move), apply the move and write the
FEN. Pure Lua over a compact board, no move list, no SAN generation.
- Pros: does only what PGN reading needs, far less work per move; no game
  object (resolving no longer moves the displayed position); easy to test
  against an oracle.
- Cons: a second rules implementation to keep correct (castling rights,
  en passant, pins, promotions).

### C. Precompute on the PC (pipeline)
- Pros: zero device work.
- Cons: a PC step for every PGN; kept as an option if B + cache are not enough.

## Decision
**B**, with **chess.lua kept for interactive play** (tap-to-move legal moves,
check/mate, puzzles, the engine game). `pksan` resolves PGN moves for
studies, lessons and repertoires. Correctness is guarded by oracle specs:
every ply of generated random games and a set of tricky positions are
resolved by both pksan and chess.lua (same from/to/promotion and FEN), and a
fixture of python-chess FENs.

pksan is deliberately lenient with hand-written SAN (over-disambiguation,
missing or extra `x`, `dc5`, `e2e4`, lowercase promotion) and stricter where
chess.lua is wrong (castling requires the rook on its square); it allows
kingless study diagrams. For every SAN chess.lua accepts in a legal
position, both give the same move and FEN.

Conventions follow chess.lua so both agree: the en passant square is set
after every double pawn push (repertoire keys normalize it, ADR-0012), the
move's `san` is the PGN's SAN (check marks as written), `flags` use
chess.lua's letters.

## Consequences
- PGN resolution no longer depends on the game object; cursors only load
  a FEN into the game when the displayed position changes.
- A rules bug could make pksan accept or reject a move differently from
  chess.lua: the oracle specs are the guard; any mismatch found on a real
  PGN becomes a fixture.
- An on-device cache of resolved repertoires (iteration after) removes even
  this cost on later sessions.
