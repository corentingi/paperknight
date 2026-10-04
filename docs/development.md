# Development guide

## Requirements

- Linux x86_64 with glibc ≥ 2.35 (for the desktop KOReader build)
- Python ≥ 3.10, `make`, `curl`, `tar`, `zstd`

## Make targets

Run `make help` for the current list. Main ones:

| Target | Does |
|---|---|
| `make koreader` | Download the pinned desktop KOReader into `build/koreader/` |
| `make test` | Lua unit tests (with KOReader's LuaJIT) + pipeline `pytest` |
| `make e2e` | Headless end-to-end scenarios; screenshots in `build/screenshots/` |
| `make emulator` | Visible KOReader window with the plugin loaded (needs a display) |
| `make packs` | Build data packs into `build/packs/` |
| `make check` | Everything CI runs |

## The emulator

KOReader's SDL frontend runs on a desktop. We run the official Linux release:

- `HOME=build/emulator-home` isolates settings from your own KOReader.
- The plugin is symlinked into `build/emulator-home/.config/koreader/plugins/`,
  so edits are picked up on restart.
- `EMULATE_READER_W=758 EMULATE_READER_H=1024` matches the Paperwhite 2 screen.
- `SDL_VIDEODRIVER=offscreen` runs without a display (used by `make e2e`).

See [ADR-0007](adr/0007-headless-koreader-emulator.md).

## Deploying to a Kindle

```sh
# Kindle mounted over USB at /media/$USER/Kindle
rsync -a --delete plugin/paperknight.koplugin/ /media/$USER/Kindle/koreader/plugins/paperknight.koplugin/
cp build/packs/*.sqlite /media/$USER/Kindle/koreader/plugins/paperknight.koplugin/packs/
```

## Conventions

- Lua: follow KOReader style (4-space indent, `local X = require("x")` at top,
  widgets extend `WidgetContainer`/`InputContainer`).
- Python: standard library first; type hints; `pytest` fixtures in
  `pipeline/tests/fixtures/`.
- Any costly-to-reverse choice gets an ADR (`docs/adr/`).
