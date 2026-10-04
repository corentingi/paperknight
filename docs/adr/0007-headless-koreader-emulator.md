# ADR-0007: Test in a headless desktop KOReader

- Date: 2026-10-04
- Status: accepted

## Context
Developing only on a real Kindle means slow copy-restart cycles and no
automated checks. KOReader has an SDL desktop frontend, used by its own
developers as an "emulator".

## Options
### A. Official KOReader Linux x86_64 release, run headless with SDL's offscreen driver
- Pros: the exact Lua frontend and plugin API that runs on the Kindle; no
  compilation; verified working on this machine with
  `SDL_VIDEODRIVER=offscreen`, no X server needed; screen size set with
  `EMULATE_READER_W/H` (758×1024 = PW2). Loads user plugins from
  `$HOME/.config/koreader/plugins/`, so the plugin can be symlinked in.
- Cons: x86 not ARM: the Stockfish binary and performance differ from the
  device; needs glibc ≥ 2.35 on the host.

### B. Build KOReader's emulator from source (`kodev build`)
- Pros: debug builds, latest master.
- Cons: long, heavy toolchain build; unnecessary for plugin work.

### C. Docker image with Xvfb
- Pros: reproducible across hosts.
- Cons: more moving parts; offscreen SDL already removes the need for X.
  Can be added later for CI on hosts with old glibc.

## Decision
A. `tools/emulator/` downloads a pinned KOReader release (v2026.07.1) into
`build/koreader/`, uses an isolated `HOME` under `build/emulator-home/`, and
symlinks the plugin into it. A harness plugin drives scripted scenarios
(open Paperknight, tap squares, take screenshots with KOReader's own
screenshot function, quit) so `make e2e` runs without a display.
`make emulator` runs the same setup in a visible window for manual testing.

## Consequences
- Fast inner loop and automated end-to-end smoke tests.
- Device-only issues (ARM engine, real e-ink refresh, PW2 performance) still
  need a manual check on the Kindle before releases.
- Revisit (option C) if CI runs on a host with glibc < 2.35.
