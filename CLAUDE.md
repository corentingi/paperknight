# Paperknight — notes for Claude

## Commands (run from repo root)
- `make check` — everything (Lua unit + pytest + emulator e2e). Run before committing.
- `make test-lua` — Lua specs (`plugin/tests/*_spec.lua`), run with KOReader's luajit.
- `make test-py` — pipeline pytest (needs `make venv` once; venv at `pipeline/.venv`).
- `make e2e` — headless KOReader scenarios (`tools/emulator/scenarios/`).
  Output in `build/e2e/<scenario>.{log,result}`; on failure grep, don't cat:
  `grep -nE -A8 "ERROR|stack traceback" build/e2e/<name>.log`
- `make koreader` once if `build/koreader` is missing.

## Token hygiene
- Don't read `main.lua`, `pkboard.lua`, `pkstudyview.lua` in full: grep for the
  function, then Read with offset/limit. Never read the upstream engine
  `pkchesslib/src/chess.lua`; grep its API.
- Never cat `build/`, puzzle CSVs, `.sqlite` packs or emulator logs; use
  head/grep/sqlite3 queries.
- Only look at e2e screenshots when a visual change is being checked.
- `.pm/JOURNAL.md` is append-only: read only the last iteration block.

## KOReader pitfalls (each cost an iteration)
- `ScrollTextWidget` has no `setText`: rebuild the widget.
- ButtonDialog's table field is `buttontable`; TitleBar subtitle text is
  `title_bar.subtitle_widget.text`.
- `lua-ljsqlite3` returns INTEGER as int64 cdata: always `tonumber()`.
- `_meta.lua` has no `name`; InfoMessage takes `text` (not `message`).
- Icons: absolute paths (`pkicons.lua`). Extend widgets with `:extend{}`;
  never patch globals.
- Always cancel `UIManager:scheduleIn` tasks on close/restart (crash risk).

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
