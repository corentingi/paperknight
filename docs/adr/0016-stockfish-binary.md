# ADR-0016: A Stockfish binary for the Kindle, built and hosted separately

- Date: 2026-10-14
- Status: accepted

## Context
Play against the engine and the analysis board's evaluation need a UCI
engine at `paperknight.koplugin/bin/stockfish`. None is shipped: the PW2 is
an ARMv7 Cortex-A9 (NEON) running kernel 3.0 with an old glibc, and a
recent Stockfish embeds a ~100 MB network. Stockfish is GPLv3.

## Options
### A. Official Stockfish release binaries (Android ARMv7)
- Pros: no build.
- Cons: built for Android (bionic); untested on the Kindle's kernel, and
  their dynamic or PIE linking may not run there.

### B. Our static build against musl, with Zig's cross compiler
- Pros: one self-contained file, no system library used, runs on the old
  kernel (musl has no "kernel too old" check, unlike a static glibc); the
  build is a script (`tools/dist/build-stockfish.sh`), checked under qemu.
- Cons: ~100 MB binary and about as much RAM; we build and host it.

### C. An older, small Stockfish (classical evaluation, ~1 MB)
- Pros: tiny, light on memory and CPU.
- Cons: much weaker evaluation; the request was a recent Stockfish.

## Decision
B, Stockfish 19 for `armv7-neon`. It is not part of `pka.tar.gz` (too large
for every update): `stockfish.sh` installs it once into `bin/`, which
`pka.sh` keeps. The source tarball is hosted next to the binary (GPLv3).

## Consequences
- Play and the analysis board work as soon as `bin/stockfish` exists;
  without it Play is two players and the analysis board has no evaluation.
- The engine needs ~110 MB of RAM next to KOReader; the analysis board
  runs one engine at a time and stops it when closed.
- Revisit if memory is short on the device (a smaller network or option C),
  or if the Kindle firmware changes the ABI (kindlehf).
