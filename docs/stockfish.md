# Stockfish on the Kindle

Paperknight looks for a UCI engine at
`koreader/plugins/paperknight.koplugin/bin/stockfish`. With it, *Play
against the engine* plays Stockfish and the analysis board shows its
evaluation and best line once the knight button (bottom left) turns it on
(off by default; Stockfish is started on the first tap and kept until the
board closes). Without it, Play is a two-player board and the
analysis board has no evaluation. Decision: ADR-0016.

In Play, Stockfish thinks 5 seconds per move by default (game settings ⚙ →
*Engine thinking time*: 1 to 60 s, saved), less when its clock runs low (at
most 1/30 of what it has left), not the clocks' budget of a real game. The tick button at the bottom right starts or pauses the clocks; a
game starts paused, and your first move (or the tick) starts it.

## Install (on the Kindle, kterm or SSH)

    curl -fkL <server>/stockfish.sh | sh

It downloads `stockfish.gz` (~3 MB), checks its sha256, unpacks it into
`bin/` (replacing an older Stockfish) and runs it once. `pka.sh` updates
keep `bin/`. Restart KOReader.

## The binary

- Stockfish 18 (`sf_18`) with its **small network only**
  (nn-37f18f62d772.nnue, 3.5 MB, embedded), patched by
  `tools/dist/stockfish-sf_18-smallnet.patch`: Stockfish 18 normally loads a
  109 MB big network as well and uses the small one only for lopsided
  positions; the patch never loads the big one and evaluates every position
  with the small one. Stockfish 19 has no small network any more.
- ARMv7 + NEON (Cortex-A9), static, against musl: no system library, runs on
  the PW2's kernel 3.0.
- ~5 MB on disk; a few tens of MB of RAM with its 16 MB hash table, where
  Stockfish 19 needed about 130 MB (under qemu, which adds its own
  overhead: 80 MB searching against 265 MB just loaded). The PW2 has
  512 MB, of which about 100 MB are free with the Kindle framework running; the analysis board and Play log the free and
  available memory and the engine's resident size when it is ready
  (`crash.log`, "engine ready, memory:"), after a freeze was seen on the
  device with the engine on.

## Build

    tools/dist/build-stockfish.sh            # sf_18 small network; or: tools/dist/build-stockfish.sh sf_19

Downloads Zig 0.17.0 and the Stockfish source, cross-compiles, and writes
`build/dist/stockfish`, `stockfish.gz`, `stockfish-sf_18-src.tar.gz`, the
patch, and `stockfish.sh` (with the checksum). Check it under qemu-user
(`qemu-arm-static -cpu cortex-a9 build/dist/stockfish`, then `uci`,
`go depth 10`). Upload the five files.

## License

Stockfish is free software under the GNU GPL v3. Its source code is hosted
next to the binary: <server>/stockfish-sf_18-src.tar.gz
and the patch applied to it,
<server>/stockfish-sf_18-smallnet.patch (upstream:
https://github.com/official-stockfish/Stockfish, tag `sf_18`); the build is
the script above.
