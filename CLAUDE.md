# Paperknight — notes for Claude

## Commands (run from repo root)
- `make check` — everything (Lua unit + pytest + emulator e2e). Run before committing.
- `make test-lua` — Lua specs (`plugin/tests/*_spec.lua`), run with KOReader's luajit.
- `make test-py` — pipeline pytest (needs `make venv` once; venv at `pipeline/.venv`).
- `make e2e` — headless KOReader scenarios (`tools/emulator/scenarios/`).
  Output in `build/e2e/<scenario>.{log,result}`; on failure grep, don't cat:
  `grep -nE -A8 "ERROR|stack traceback" build/e2e/<name>.log`
  One scenario: `make e2e E2E_SCENARIOS=tools/emulator/scenarios/<name>.lua`
  (a path, not a bare name).
- `make koreader` once if `build/koreader` is missing.
- `make pka` — device archive `build/dist/pka.tar.gz` + installer
  `build/dist/pka.sh` (`tools/dist/`). Repacks the current plugin with the
  assets staged in `build/dist/all` (studies, repertoires, puzzle pack: not
  rebuilt). Deploy: upload both (remote-file skill); on the Kindle
  `curl -fkL <url>/pka.sh | sh`.

## Token hygiene
- Don't read `main.lua`, `pkboard.lua`, `pkstudyview.lua` in full: grep for the
  function, then Read with offset/limit. Never read the upstream engine
  `pkchesslib/src/chess.lua`; grep its API.
- Never cat `build/`, puzzle CSVs, `.sqlite` packs or emulator logs; use
  head/grep/sqlite3 queries.
- Only look at e2e screenshots when a visual change is being checked.
- `.pm/JOURNAL.md` is append-only: read only the last iteration block.
- `grep` on this machine is ugrep: long `.{0,N}` patterns fail ("exceeds
  complexity limits"); use `LC_ALL=C grep` or a simpler pattern.

## KOReader pitfalls (each cost an iteration)
- `ScrollTextWidget` has no `setText`: rebuild the widget.
- ButtonDialog's table field is `buttontable`; TitleBar subtitle text is
  `title_bar.subtitle_widget.text`.
- `lua-ljsqlite3` returns INTEGER as int64 cdata: always `tonumber()`.
- `_meta.lua` has no `name`; InfoMessage takes `text` (not `message`).
- Icons: absolute paths (`pkicons.lua`). Extend widgets with `:extend{}`;
  never patch globals.
- Always cancel `UIManager:scheduleIn` tasks on close/restart (crash risk).
- `Button:setIcon` / `enableDisable` rebuild the button: its frame has no
  `dimen` until the next paint (cache square rects at paint time, pkboard).
- e2e: `h.wait()` after a programmatic view change (`loadChapter`, `toEnd`…)
  before tapping: rebuilt widgets have no position yet (IconButton crash, or
  the tap lands at 0,0).
- In a ButtonTable, icon buttons are taller than text ones: size the icons
  to the text row, or the board moves when the bar is swapped.

## E-ink refreshes (pkrefresh.lua)
- Overlapping refreshes merge and the stronger mode wins (`partial` > `ui` >
  `fast`). KOReader promotes every Nth `partial` (user's full refresh rate)
  to a flash over its region, `full` screen when it has no region: keep
  board-screen refreshes regional and small. `fast` is black and white
  (degrades grey squares); `ui` flickers changed pixels.
- Separate refreshes run in sequence on the Kindle: batch one update into one
  region (Board.square_refresh collects the changed squares).
- Measure, don't guess: hook `UIManager._refresh` in an e2e scenario and log
  mode + region. Merges re-enter `_refresh`, so dedupe regions when counting.

## Chess test data
- Validate every FEN/PGN written into a test or fixture with python-chess
  first (`pipeline/.venv/bin/python -c ...`): legality, castling rights,
  SAN ambiguity.

## Rules
- Don't commit real Lichess study text (licence unclear); use own fixtures
  (`plugin/tests/fixtures/`).
- Record decisions as ADRs in `docs/adr/` (template `0000-template.md`);
  update `docs/` with behaviour changes.
- Commit/push only when asked.
- A new e2e check must fail without the fix: revert the fix once and run it
  (mutation check).
