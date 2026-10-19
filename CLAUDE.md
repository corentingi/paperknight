# Paperknight — notes for Claude

Machine-, deploy- and workflow-specific notes are in `CLAUDE.local.md` (not
committed; read it too when present).

## Commands (run from repo root)
- `make check` — everything (Lua unit + pytest + emulator e2e). Run before committing.
- `make test-lua` — Lua specs (`plugin/tests/*_spec.lua`), run with KOReader's luajit.
  A case using over 30 s of CPU fails with a traceback (endless loop); the
  whole run is killed after 600 s.
- `make test-py` — pipeline pytest (needs `make venv` once; venv at `pipeline/.venv`).
- `make e2e` — headless KOReader scenarios (`tools/emulator/scenarios/`).
  Output in `build/e2e/<scenario>.{log,result}`; on failure grep, don't cat:
  `grep -nE -A8 "ERROR|stack traceback" build/e2e/<name>.log`
  One scenario: `make e2e E2E_SCENARIOS=tools/emulator/scenarios/<name>.lua`
  (a path, not a bare name). Scenarios run 2 at a time (`PK_JOBS`), each in
  its own home, within `PK_TIMEOUT` s (default 120).
- `make koreader` once if `build/koreader` is missing.
- `make pka` — device archive `build/dist/pka.tar.gz` + installer
  `build/dist/pka.sh` (`tools/dist/`). Repacks the current plugin with the
  assets staged in `build/dist/all` (studies, repertoires, puzzle pack: not
  rebuilt). Needs `PAPERKNIGHT_DIST_URL`, the base URL the files are served
  from, baked into the installer (`local.mk`, not committed, or the
  environment). On the Kindle `curl -fkL <url>/pka.sh | sh` (it checks the
  archive's sha256, baked in by build-pka.sh: serve both files together).
- `make pkc` — code-only archive `build/dist/pkc.tar.gz` + `pkc.sh` (~140 KB,
  no puzzle pack/studies/fonts; the device keeps its assets). Use it when
  only the plugin code changed; `make pka` when assets changed.
- Stockfish for the Kindle: `tools/dist/build-stockfish.sh` (docs/stockfish.md,
  also needs `PAPERKNIGHT_DIST_URL`); serve `stockfish.gz`, `stockfish.sh`,
  the source tarball and the patch.

## Token hygiene
- Don't read `main.lua`, `pkboard.lua`, `pkstudyview.lua` in full: grep for the
  function, then Read with offset/limit. Never read the upstream engine
  `pkchesslib/src/chess.lua`; grep its API.
- Never cat `build/`, puzzle CSVs, `.sqlite` packs or emulator logs; use
  head/grep/sqlite3 queries.
- Only look at e2e screenshots when a visual change is being checked.

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
- e2e: `h.settle()` after a programmatic view change (`loadChapter`,
  `setPosition`…) before tapping: rebuilt widgets have no position yet
  (IconButton crash, or the tap lands at 0,0). Taps settle by themselves;
  `h.waitFor(pred)` for a condition, `h.wait(s)` only for timed tasks.
- In a ButtonTable, icon buttons are taller than text ones: size the icons
  to the text row, or the board moves when the bar is swapped.

## E-ink refreshes (pkrefresh.lua, docs/eink-refresh.md)
- PW2 is a REAGL Kindle: `partial`/`[partial]` = REAGL (no flash), `ui` =
  GC16_FAST (flickers changed pixels), `fast` = DU (black and white, crushes
  greys). Night: partial becomes GL16_INV.
- The board is drawn in the four DU4 greys only (0x00, 0x55, 0xAA, 0xFF)
  and its squares are refreshed with DU4 partial updates
  (`PkRefresh.boardRegion`, ADR-0018): confirmed on the PW2, keep it. No
  grey tints on the board: marks are black/white shapes (last move: corner
  triangles) or the 0x55/0xAA greys. A DU4 partial update drives only the
  changed pixels, so the board's single batched region may be large.
- Turn marker: the board shows the side to move in its corner cell by
  itself while it takes moves (`Board:_syncTurnMarker`); views lock and
  unlock it with `board:setLocked(...)`, never `board.locked =`.
- Steps (move, selection, status, replay/study step) use `PkRefresh.STEP`
  (`[partial]`): not counted by KOReader, never promoted to a flash. Pages
  (new puzzle/chapter/line) use a counted whole-screen `partial`
  (`PkRefresh.page`): the user's full refresh rate flashes there.
- No KOReader tap highlight where the board is the feedback: squares
  (`no_feedback`) and arrows (`PkButton.noFeedback`). Subtitles via
  `PkRefresh.setSubTitle` (TitleBar's own refresh is `ui`).
- REAGL is sent as a full update: it redraws every pixel of its region,
  visibly on grey squares. Keep regions tight: the board's changed squares
  in one rectangle (`Board.square_refresh`, each REAGL refresh waits for the
  previous one), the text below as its own refresh (`PkRefresh.below`/
  `step`); never one region over both (seen on the PW2).
- Closing a full-screen view: `PkRefresh.close` (UIManager:close without a
  mode repaints what is below but refreshes nothing; KOReader's menus
  refresh themselves, our board screens don't).
- Measure, don't guess: `h.recordRefreshes()` in an e2e scenario gives the
  refreshes sent to the screen (after merges and promotions).

## Chess test data
- Validate every FEN/PGN written into a test or fixture with python-chess
  first (`pipeline/.venv/bin/python -c ...`): legality, castling rights,
  SAN ambiguity.

## Rules
- Don't commit real Lichess study text (licence unclear); use own fixtures
  (`plugin/tests/fixtures/`).
- Record decisions as ADRs in `docs/adr/` (template `0000-template.md`);
  update `docs/` with behaviour changes.
- Routine for a change: implement, quick review of the diff, `make check`
  green, commit.
- Commit messages follow [Conventional Commits](https://www.conventionalcommits.org):
  `type(scope): summary`, lowercase type, summary without a final period.
  Types: `feat`, `fix`, `perf`, `refactor`, `docs`, `test`, `build`, `ci`,
  `chore`. Scope optional, the area touched: `puzzles`, `studies`,
  `openings`, `analysis`, `play`, `board`, `movelist`, `nav`, `eink`,
  `engine`, `pgn`, `pipeline`, `dist`, `stockfish`, `adr`, `claude`…
  A breaking change gets `!` after the type/scope (`feat(studies)!: …`) and
  a `BREAKING CHANGE:` footer.
- A new e2e check must fail without the fix: revert the fix once and run it
  (mutation check).
