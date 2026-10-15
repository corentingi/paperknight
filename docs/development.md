# Development guide

## Requirements

- Linux x86_64 with glibc ≥ 2.35 (for the desktop KOReader build)
- Python ≥ 3.10, `make`, `curl`, `tar`, `rsync` (`make pka`), `sha256sum`

## Make targets

Run `make help` for the current list. Main ones:

| Target | Does |
|---|---|
| `make koreader` | Download the pinned desktop KOReader into `build/koreader/` |
| `make test` | Lua unit tests (with KOReader's LuaJIT) + pipeline `pytest` |
| `make e2e` | Headless end-to-end scenarios; screenshots and logs in `build/e2e/` |
| `make emulator` | Visible KOReader window with the plugin loaded (needs a display) |
| `make packs` | Build data packs into `build/packs/` (`--refresh` on the pipeline downloads the dump again) |
| `make pka` | Device archive and installer in `build/dist/` (see Deploying) |
| `make pkc` | Code-only device archive and installer (`pkc.tar.gz`, `pkc.sh`) |
| `make check` | Everything: run it before committing (there is no CI) |

## The emulator

KOReader's SDL frontend runs on a desktop. We run the official Linux release:

- `HOME=build/emulator-home` isolates settings from your own KOReader.
- The plugin is symlinked into KOReader's own `plugins/` folder
  (`build/koreader/lib/koreader/plugins/`), so KOReader loads it through the
  relative path `plugins/paperknight.koplugin`, exactly like on a Kindle.
  Edits are picked up on restart.
- `make e2e` sets `PAPERKNIGHT_PACKS_DIR` to the fixture packs
  (`build/packs/fixture/`), `PAPERKNIGHT_STUDIES_DIR` to
  `plugin/tests/fixtures/` and `PAPERKNIGHT_REPERTOIRES_DIR` to
  `plugin/tests/fixtures/repertoires/`; without them the plugin reads
  `<plugin>/packs/` and `<KOReader data>/paperknight/{studies,repertoires}/`.
- Each scenario runs in its own home (`build/emulator-home/<scenario>`), two
  at a time (`PK_JOBS`), each within `PK_TIMEOUT` seconds (default 120).
- `EMULATE_READER_W=758 EMULATE_READER_H=1024` matches the Paperwhite 2 screen.
- `SDL_VIDEODRIVER=offscreen` runs without a display (used by `make e2e`).

See [ADR-0007](adr/0007-headless-koreader-emulator.md).

### Writing an e2e scenario

A scenario is a Lua file in `tools/emulator/scenarios/` returning
`function(h) … end`. Helpers:

- `h.ui` (the file manager; `h.ui.paperknight` is the plugin);
- `h.tap(x, y)`, `h.tapWidget(w)`, `h.swipe(x, y, direction)`: each ends with
  `h.settle()` (a repaint, the next tick's tasks, a repaint) instead of a
  fixed delay;
- `h.settle()` after a programmatic change (rebuilt widgets get their
  positions when painted); `h.waitFor(pred, timeout)` for a condition;
  `h.wait(s)` only for timed tasks (an opponent's reply delay);
- `h.recordRefreshes()`: the e-ink refreshes sent to the screen until the
  returned function is called ([eink-refresh.md](eink-refresh.md));
- `h.shot(name)`, `h.check(cond, msg)`, `h.log(...)`.

The run fails on a failed check, a Lua error, any `ERROR` line in the log, a
timeout, or a non-zero exit.

## Deploying to a Kindle

Over Wi-Fi: `make pka` builds `build/dist/pka.tar.gz` (the plugin with the
assets staged in `build/dist/all`) and `pka.sh` (with the archive's
checksum); put both on a web server, then on the Kindle run
`curl -fkL <server>/pka.sh | sh`. It checks the archive, extracts it into a
staging folder, then swaps the plugin folder (keeping `bin/` and a pack it
doesn't bring). Stockfish: [stockfish.md](stockfish.md).

When only the code changed, `make pkc` builds a code-only archive
(`pkc.tar.gz`, about 140 KB) and `pkc.sh`, used the same way
(`curl -fkL <server>/pkc.sh | sh`): it replaces the plugin's code and keeps
the puzzle pack, studies, repertoires and fonts already installed.

Over USB:

```sh
# Kindle mounted over USB at /media/$USER/Kindle
rsync -a --delete --exclude bin/ --exclude packs/ plugin/paperknight.koplugin/ /media/$USER/Kindle/koreader/plugins/paperknight.koplugin/
cp build/packs/*.sqlite /media/$USER/Kindle/koreader/plugins/paperknight.koplugin/packs/
```

## Conventions

- Lua: follow KOReader style (4-space indent, `local X = require("x")` at top,
  widgets extend `WidgetContainer`/`InputContainer`).
- Python: standard library first; type hints; `pytest` fixtures in
  `pipeline/tests/fixtures/`.
- Any costly-to-reverse choice gets an ADR (`docs/adr/`).
