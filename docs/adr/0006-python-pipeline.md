# ADR-0006: Write the data pipeline in Python

- Date: 2026-10-04
- Status: accepted

## Context
The pipeline downloads multi-GB public datasets (Lichess CSV/PGN, zstd
compressed), filters them, and writes SQLite packs. It runs on a developer PC.

## Options
### A. Python 3.10+ with a small set of dependencies
- Pros: `sqlite3` and `csv` in the standard library; `python-chess` is the
  reference library for PGN/FEN/SAN; `zstandard` streams `.zst`; lichess's own
  puzzle generator is Python, so it can be reused later.
- Cons: a second language next to Lua.

### B. Lua (LuaJIT from KOReader)
- Pros: one language, could share move logic with the plugin.
- Cons: no mature PGN/zstd/HTTP libraries; much more code.

### C. Shell + sqlite3 CLI
- Pros: no dependencies.
- Cons: PGN/SAN processing impossible to do correctly.

## Decision
A. Python package `paperknight_pipeline` under `pipeline/`, installed in a
local venv (`pipeline/.venv`) by `make`. Dependencies are pinned in
`pipeline/pyproject.toml`. Tests use `pytest` with small fixture files, never
the real multi-GB downloads.

## Consequences
- Downloads are cached in `build/downloads/` and never committed.
- Anything the plugin needs at runtime must be in the pack; the plugin never
  depends on Python.
