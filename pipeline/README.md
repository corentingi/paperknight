# Pipeline space

Python scripts that turn public chess datasets into compact SQLite packs for
the plugin ([ADR-0005](../docs/adr/0005-sqlite-data-packs.md),
[ADR-0006](../docs/adr/0006-python-pipeline.md)).

- Package: `paperknight_pipeline/`, tests in `tests/`.
- Setup: `make venv` (creates `pipeline/.venv`).
- Downloads are cached in `build/downloads/`, packs written to `build/packs/`.
- Sources and licenses: [`docs/data-sources.md`](../docs/data-sources.md).
