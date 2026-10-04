# ADR-0004: One repo, two spaces: `plugin/` and `pipeline/`

- Date: 2026-10-04
- Status: accepted

## Context
The product has two halves with different languages and run locations: the
KOReader plugin (Lua, runs on the Kindle) and the data pipeline (runs on a PC,
downloads public datasets, builds packs). They share one contract: the pack
format.

## Options
### A. One repository with `plugin/`, `pipeline/`, `tools/`, `docs/`
- Pros: the pack schema and both sides change in one commit; one CI; one place
  for docs and ADRs.
- Cons: two toolchains in one tree.

### B. Two repositories
- Pros: independent release cycles.
- Cons: schema changes need coordinated releases across repos; overkill for a
  one-person project.

## Decision
A. Layout:
- `plugin/paperknight.koplugin/` — exactly the folder copied to the device.
- `pipeline/` — Python package `paperknight_pipeline` + tests.
- `tools/emulator/` — desktop KOReader test harness.
- `docs/` — architecture, data sources, ADRs, pack format spec.
- `build/` — generated, git-ignored (packs, downloads, emulator home).

## Consequences
- The pack format is specified once in `docs/pack-format.md`; both sides test
  against it.
- A root `Makefile` is the single entry point (`make test`, `make packs`,
  `make emulator`).
