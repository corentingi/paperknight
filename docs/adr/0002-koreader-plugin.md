# ADR-0002: Ship as a KOReader plugin

- Date: 2026-10-04
- Status: accepted

## Context
Target: a jailbroken Kindle Paperwhite 2 (firmware 5.12.x, ARMv7 soft-float,
758×1024 at 212 ppi). Three ways to put an app on it: a native Linux program
(KUAL/framebuffer), a web app for the built-in browser, or a KOReader plugin.

## Options
### A. KOReader plugin (Lua)
- Pros: KOReader already handles e-ink refresh, touch gestures, widgets,
  on-screen keyboard, sleep/wake and coexistence with the Amazon framework.
  No cross-compilation for Lua code. Runs on Kobo/PocketBook/reMarkable too.
  Bundles SQLite and LuaJIT. Existing chess plugins to fork (Kochess).
- Cons: users must install KOReader; tied to KOReader's widget toolkit and API.

### B. Native app (C/C++ with FBInk or GTK2)
- Pros: full control, no KOReader dependency.
- Cons: must rebuild UI toolkit, input handling, refresh logic; soft-float
  cross toolchain; per-firmware packaging. Weeks of work before any chess.

### C. Web app for the experimental browser
- Pros: no jailbreak needed; instant updates.
- Cons: old WebKit (ES5, no WebSockets), poor refresh control, needs network
  unless carefully cached; offline Stockfish impossible.

## Decision
A. The device-integration work is already done in KOReader, and offline
training with a local engine is the core of the product.

## Consequences
- Plugin code follows KOReader conventions (`_meta.lua`, `main.lua`,
  `WidgetContainer`, `UIManager`).
- We depend on KOReader's plugin API stability; pin a tested KOReader version
  in the emulator setup (ADR-0007).
- A web companion stays possible later, reusing the same data packs.
