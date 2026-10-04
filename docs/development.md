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
| `make e2e` | Headless end-to-end scenarios; screenshots and logs in `build/e2e/` |
| `make emulator` | Visible KOReader window with the plugin loaded (needs a display) |
| `make packs` | Build data packs into `build/packs/` |
| `make check` | Everything CI runs |

## The emulator

KOReader's SDL frontend runs on a desktop. We run the official Linux release:

- `HOME=build/emulator-home` isolates settings from your own KOReader.
- The plugin is symlinked into KOReader's own `plugins/` folder
  (`build/koreader/lib/koreader/plugins/`), so KOReader loads it through the
  relative path `plugins/paperknight.koplugin`, exactly like on a Kindle.
  Edits are picked up on restart.
- `make e2e` sets `PAPERKNIGHT_PACKS_DIR` to the fixture packs
  (`build/packs/fixture/`) and `PAPERKNIGHT_STUDIES_DIR` to
  `plugin/tests/fixtures/`; without them the plugin reads `<plugin>/packs/`
  and `<KOReader data>/paperknight/studies/`.
- `EMULATE_READER_W=758 EMULATE_READER_H=1024` matches the Paperwhite 2 screen.
- `SDL_VIDEODRIVER=offscreen` runs without a display (used by `make e2e`).

See [ADR-0007](adr/0007-headless-koreader-emulator.md).

### Writing an e2e scenario

A scenario is a Lua file in `tools/emulator/scenarios/` returning
`function(h) … end`. Helpers: `h.ui` (the file manager, `h.ui.paperknight` is
the plugin), `h.wait(s)`, `h.tap(x, y)`, `h.tapWidget(w)`, `h.shot(name)`,
`h.check(cond, msg)`, `h.log(...)`. The run fails on a failed check, a Lua
error, any `ERROR` line in the log, a timeout, or a non-zero exit.

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
