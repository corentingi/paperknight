# Stockfish on the Kindle

Paperknight looks for a UCI engine at
`koreader/plugins/paperknight.koplugin/bin/stockfish`. With it, *Play
against the engine* plays Stockfish and the analysis board shows its
evaluation and best line. Without it, Play is a two-player board and the
analysis board has no evaluation. Decision: ADR-0016.

In Play, Stockfish thinks 5 seconds per move by default (game settings ⚙ →
*Engine thinking time*: 1 to 60 s, saved), less when its clock runs low (at
most 1/30 of what it has left), not the clocks' budget of a real game. The tick button at the bottom right starts or pauses the clocks; a
game starts paused, and your first move (or the tick) starts it.

## Install (on the Kindle, kterm or SSH)

    curl -fkL <server>/stockfish.sh | sh

It downloads `stockfish.gz` (~80 MB), checks its sha256, unpacks it into
`bin/` and runs it once. `pka.sh` updates keep `bin/`. Restart KOReader.

## The binary

- Stockfish 19 (`sf_19`), its network embedded (nn-1a298aa575a0.nnue,
  109 MiB in memory).
- ARMv7 + NEON (Cortex-A9), static, against musl: no system library, runs on
  the PW2's kernel 3.0.
- ~100 MB on disk; it needs about 110 MB of RAM plus its hash table (16 MB
  by default).

## Build

    tools/dist/build-stockfish.sh            # or: tools/dist/build-stockfish.sh sf_19

Downloads Zig 0.17.0 and the Stockfish source, cross-compiles, and writes
`build/dist/stockfish`, `stockfish.gz`, `stockfish-sf_19-src.tar.gz` and
`stockfish.sh` (with the checksum). Check it under qemu-user
(`qemu-arm-static -cpu cortex-a9 build/dist/stockfish`, then `uci`,
`go depth 10`). Upload the four files.

## License

Stockfish is free software under the GNU GPL v3. Its source code is hosted
next to the binary: <server>/stockfish-sf_19-src.tar.gz
(upstream: https://github.com/official-stockfish/Stockfish, tag `sf_19`);
the build is the script above.
