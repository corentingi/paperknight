# ADR-0005: Ship data as offline SQLite packs

- Date: 2026-10-04
- Status: accepted

## Context
The plugin needs tens of thousands of puzzles, thousands of opening lines and
hundreds of games, queried by rating, theme and opening, on a device with
512 MB RAM and a slow CPU, offline. Training progress (spaced repetition) must
also be stored on the device.

## Options
### A. SQLite files built by the pipeline
- Pros: KOReader already bundles SQLite and the `lua-ljsqlite3` binding (its
  statistics plugin uses it); indexed queries without loading everything in
  RAM; one file per pack; inspectable with any SQLite tool.
- Cons: binary files; schema versioning needed.

### B. Lua tables / JSON files
- Pros: trivial to read.
- Cons: whole file parsed into RAM; 100k puzzles would be slow and heavy on a PW2.

### C. Fetch from Lichess at runtime
- Pros: always fresh, no packs.
- Cons: requires Wi-Fi; contradicts the offline goal; Lichess API rate limits
  and (since 2026) tokens for the explorer.

## Decision
A. Read-only content packs (`puzzles.sqlite`, later `openings.sqlite`,
`games.sqlite`), each with a `meta` table holding `format_version`, source and
build date. User progress lives in a separate writable `progress.sqlite` in
KOReader's settings directory, so packs can be replaced without losing it.

## Consequences
- `docs/pack-format.md` is the contract; bumping `format_version` is required
  for breaking schema changes, and the plugin refuses packs it doesn't know.
- Pack sizes must stay reasonable for a 2 GB device (target < 50 MB each).
