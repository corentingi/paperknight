# Stockfish on the Kindle

Paperknight looks for a UCI engine at
`koreader/plugins/paperknight.koplugin/bin/stockfish`. With it, *Play
against the engine* plays Stockfish and the analysis board shows its
evaluation and best line once the knight button (bottom left) turns it on
(off the first time, then as you left it; Stockfish is started when the
engine is on and kept until the board closes). Without it, Play is a two-player board and the
analysis board has no evaluation. Decision: ADR-0016.

In Play, Stockfish thinks 5 seconds per move by default (game settings ⚙ →
*Engine thinking time*: 1 to 60 s, saved), less when its clock runs low (at
most 1/30 of what it has left), not the clocks' budget of a real game. The tick button at the bottom right starts or pauses the clocks; a
game starts paused, and your first move (or the tick) starts it.

## Install

The Paperknight installer offers it (on the Kindle, kterm or SSH):

    curl -fkL https://github.com/corentingi/paperknight/releases/latest/download/install.sh | sh

It downloads `stockfish-pw2.gz` (~3 MB) from the Stockfish release
(`stockfish-sf_18`), checks its sha256, unpacks it into `bin/` (replacing
an older Stockfish) and runs it once; plugin updates keep `bin/`. The USB
zip of a release has it already. Restart KOReader.
([releasing.md](releasing.md))

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

Downloads Zig 0.17.0 (checksum pinned) and the Stockfish source,
cross-compiles, and writes into `build/dist/stockfish/`
`stockfish-pw2` (`SF_PLATFORM`, default `pw2`), `stockfish-pw2.gz`,
`stockfish-sf_18-src.tar.gz` and the patch; `make dist` picks them up.
Check it under qemu-user
(`qemu-arm-static -cpu cortex-a9 build/dist/stockfish/stockfish-pw2`, then `uci`,
`go depth 10`). Releases are built by GitHub Actions
([releasing.md](releasing.md)).

## License

Stockfish is free software under the GNU GPL v3. Its source code is hosted
with the binary, as assets of its release
(`stockfish-sf_18-src.tar.gz`, and the patch applied to it,
`stockfish-sf_18-smallnet.patch`; upstream:
https://github.com/official-stockfish/Stockfish, tag `sf_18`); the build is
the script above.
