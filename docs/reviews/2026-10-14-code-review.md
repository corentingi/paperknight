# Code review — 2026-10-14

Whole code base at commit `a040bd0`: plugin (Lua), pipeline (Python), build
and deploy tools, emulator harness, tests and docs. Five reviewers worked in
parallel, one per area. The findings marked **✓** were checked again in the
code before this report; the others come from the reviewers' own reading
(they verified each finding, several with scratch scripts on synthetic PGN).
Nothing was changed by the review.

Device context for the performance notes: Kindle PW2, single-core ARM
~1 GHz, 512 MB RAM, slow flash, e-ink where each refresh costs time. Desktop
timings quoted below are 10–20× faster than the PW2.

## Summary

- **4 high-severity bugs**: the en passant capture leaves the pawn drawn on
  the puzzle board; the installer deletes a hand-installed Stockfish; the
  engine process is never stopped; navigation cannot see the game screen.
- **Correctness worth fixing soon**: a mastered review comes back as a new,
  rated puzzle; a PGN variation at the root becomes the main line; the redo
  history of Play mode survives resets.
- **Performance hot spots**: marking a chapter done parses every chapter (and
  keeps the trees: ~60 MB for a 1.5 MB study); the home screen opens the
  progress database on every paint; the puzzle pick prepares a statement per
  candidate; the stats page queries the pack once per puzzle; the studies list
  rescans the folder tree after every chapter opened.
- **Tooling**: the installer is not atomic and can run half-downloaded; e2e
  time is mostly fixed sleeps; one Lua spec takes 28 of the 32 seconds.
- **Quality**: two large copies of KOReader code (`pkbutton`, `pkbuttontable`)
  that drift; the study and drill views duplicate most of their code; Kochess
  leftovers in `main.lua`; several docs out of date.

Suggested order: section 1 (bugs), then the performance items of section 2,
then tooling robustness (3), then the rest.

Paths are relative to `plugin/paperknight.koplugin/` unless they start with
another top-level folder.

## 1. Bugs, by priority

| # | Sev. | Where | Finding | Fix |
|---|---|---|---|---|
| 1 ✓ | high | `pkboard.lua:585-590` | **En passant**: ids are `file * 8 + rank`, but the captured pawn is looked up at `to_id ± 8`, one *file* away. After exd6 e.p. the board updates c6 and leaves the pawn drawn on d5. Visible in puzzles (moves are not followed by `updateBoard`); studies and drill hide it by redrawing everything. No spec covers pkboard. | `to_id ± 1`, or build the square from `to` file + `from` rank; add a check that fails without the fix. |
| 2 ✓ | high | `tools/dist/pka.sh:31-36` | **The installer deletes everything in the plugin folder except `packs`**, so the user's `bin/stockfish` (README step 4, `main.lua:64`) is removed on every update. `docs/development.md:49-52` (`rsync --delete`) does the same. | Keep `bin` too; add `--exclude bin/ --exclude packs/` to the documented rsync. |
| 3 ✓ | high | `pkuci.lua:233-239`, `113-134` | **Engine never stopped**: `stop()` tests `self.uciok`, but the flag is `self.state.uciok`, so `stop`/`quit` are never sent; fds are never closed and the child is never reaped. Each game leaves a Stockfish process (hash memory, 2 fds, then a zombie). | Test `self.state.uciok`; always send `quit`, close both fds, `waitpid(WNOHANG)` with a short retry; do it in the game screen's `onCloseWidget`. |
| 4 ✓ | high | `main.lua:103`, `pknav.lua:28-30` | **Navigation ignores the game screen**: the plugin instance is shown as the window, and KOReader's PluginLoader renames it `paperknight`, which does not match `^paperknight_`. `closeScreens`, `homeShown`, `screens()` skip it; ADR-0015's `pk_close` hook is never called. | Make the game screen its own widget (`pkgame.lua`, `name = "paperknight_game"`) instead of showing the plugin instance. |
| 5 ✓ | med-high | `pkpuzzleview.lua:308`, `399-419`; `pkpuzzlereview.lua:16-17` | **A mastered review comes back as a new, rated puzzle**: "fresh" only looks at `attempts` within 30 days, reviews never write there, and the ladder lasts ≥ 31 days. Once the card is removed, the puzzle is picked as unseen and changes the rating. | Record review solves in `attempts` with a flag (not rated, not in stats), or keep mastered cards and exclude them; add a test. |
| 6 ✓ | medium | `pkpgn.lua:289-296` | **Variation at the start**: `last = last.parent or root` — a variation before the first move (`(1. d4) 1. e4`) is added to the root and becomes the main line; `( (` nested at a line start misplaces the inner one. | On `(` at a line start, branch from the enclosing line's parent; at the root, keep the main-line move first. |
| 7 | high (Play) | `pkchess.lua:37-52` | `_reset = instance.reset` creates a global; the class-level `Chess:reset` override is dead (the engine table shadows it), so `reset()` never clears `redo_stack`; a new move after an undo does not clear it either, and `redo` returns the popped move even if `move()` failed. | Wrap `instance.reset` and `instance.move` on the instance; return `move()`'s result from `redo`; delete the class override. |
| 8 | medium | `pkpuzzlereview.lua:16-17`, `33-39` | Cards scheduled before the 2026-10-14 ladder change are one step off (old step k = new step k-1): an old step-2 card is mastered without its 21-day review; an old step-1 card skips 7 days. | One-time migration `step = step - 1 WHERE step > 0` behind a kv flag, or document it in the ADR amendment. |
| 9 | medium (Play) | `main.lua:863-871`, `885-886`, `1118-1128` | TitleBars without `show_parent`, and `setDirty(self.status_bar, "ui")` on a non-window: each clock tick (10 s) queues a **full-screen `ui`** (GC16_FAST) refresh with nothing repainted. | `show_parent = self`; refresh the status bar's `dimen` with `PkRefresh`. |
| 10 | medium (Play) | `pkutils.lua:82-117` | The engine reader treats each `read()` chunk as whole lines: a line split across reads (e.g. `bestmove`) is parsed as two broken lines and the game stalls. | Keep a `pending` buffer; emit only `\n`-terminated lines. |
| 11 | medium (Play) | `pktimer.lua:76-83`; `main.lua:553-595`, `618-631`, `1162` | `Timer:stop()` always adds the increment (pause, undo, redo, close give free time); undo/redo/PGN load restart the clock even when paused or before the first move. | Increment only on a real move; restart only if the game was running. |
| 12 | medium (Play) | `pksettingswidget.lua:372-375` | Only `UCI_Elo` is set; Stockfish ignores it without `UCI_LimitStrength=true`: the Elo setting does nothing. | Set `UCI_LimitStrength`. |
| 13 | medium (Play) | `main.lua:1096-1101` | The game's left icon is "home" but resets the game without confirmation; the game screen has no quick settings, unlike the others. | Another icon + confirmation; `PkNav.tapTitle`. |
| 14 | low | `pkstudyview.lua:148-154` | Flip on a chapter that failed to open rebuilds the panel empty: the error message disappears. | Keep the error text and set it again (one helper with `loadChapter:265-271`). |
| 15 | low | `pkpuzzleview.lua:295`, `322-331` | After a failed load with nothing else to pick, the board stays unlocked with no puzzle (moves silently ignored). | Lock the board when `session == nil`. |
| 16 | low | `pkprogress.lua:145-156`, `266-272` | `COMMIT` outside the pcall: if it fails, the transaction stays open for the session and later writes silently join it. | One `_tx(fn)` helper: COMMIT inside, ROLLBACK on any error (also `pkdone.lua:121`). |
| 17 | low | `pkpuzzlepack.lua:61-66` | The pick sees at most 200 rows per band (100 after the random key, 100 lowest): fresh puzzles between the windows are missed, the pick jumps bands or says "repeating" too early. `docs/pack-format.md` says `LIMIT 25`. | Page on from the last key, or filter freshness in SQL with the progress DB attached; fix the doc. |
| 18 | low | `pkpuzzleview.lua:299` vs `235` | On Next, the new puzzle is picked before the left one's attempt is recorded (old rating used), and the rating change / review note of that attempt is never shown. | Finish the attempt at the top of `nextPuzzle`. |
| 19 | low | `pkpgn.lua:23` | A tag value ending in `\\` is not recognised (`"(.-[^\\])"`): the game splits into two chapters. | Scan the value by hand. |
| 20 | low | `pksan.lua:15-19`, `255-266` | Long-form piece moves (`g1f3`, `e1g1`) are rejected as pawn captures, though the header says the long form is accepted. | Take the piece from the origin square, or document "pawn long form only". |
| 21 | low (Play) | `pkuci.lua:18-29`; `main.lua:896`, `622`, `809-812` | `uciok` triggered twice (banner + real line); `newgame` instead of `ucinewgame`; invalid PGN and illegal engine moves ignored silently; EOF never handled (`pkutils.lua:91-92`). | Trigger only on `uciok`; `ucinewgame` + `isready`; report errors; handle EOF. |
| 22 | low | `pksettingswidget.lua:40`, `241`, `192`; `main.lua:1130-1140` | Settings assert a non-nil engine (fails when spawn failed); `color.." Time Settings"` gives "w Time Settings"; `setDirty(self, "ui")` on a non-widget = full-screen refresh; settings never saved. | Allow a nil engine; `T(_("%1 time"), PkSide.name(color))`; `self.dialog`; save with `setSetting`. |
| 23 | low | `pkstatsview.lua:103` | The stats legend (black/white: clean) is computed once; wrong if night mode is toggled while the page is open. | Recompute on night toggle (`PkSide.followNight`). |

## 2. Performance and memory

| # | Sev. | Where | Finding | Fix |
|---|---|---|---|---|
| P1 ✓ | medium | `pkstudyview.lua:489-493` | **Marking a chapter done parses every chapter** to count those with moves, and caches each tree (`pkstudy.lua:86-87`). Measured: 1.5 MB of PGN → 0.87 s (desktop) and **61 MB** of trees held while the study is open. Runs at the end of every line and lesson. | Compute "has moves" without trees (flag in `PkPgn.index`, or parse and discard), once per study. |
| P2 ✓ | medium | `pknav.lua:221-238` | The home screen's `paintTo` calls `homeItems()` on **every paint**: mkdir check, SQLite open + schema + 2 queries + close, and an engine `stat`. Also built twice at creation. | Cache the status; refresh it when a mode closes; keep `paintTo` a pure paint. |
| P3 ✓ | medium | `pkpuzzleview.lua:302-309`, `pkprogress.lua:207-212`, `pkpuzzlepack.lua:94-117` | **Puzzle pick**: `accept` calls `getReview`, which prepares and closes a statement for every candidate row; with a theme fully played, each Next evaluates every theme puzzle (thousands of FFI SQLite calls per tap on the PW2). | Load review ids and recent attempt ids into Lua sets once per `nextPuzzle`; at least keep a prepared statement. |
| P4 | medium | `pkpuzzleview.lua:540-549`, `pkprogress.lua:116-131` | **Stats page**: builds a table per attempt (whole history, `ORDER BY ts` without index), then one full-row pack query per puzzle just for `themes`; recomputed on every open. | Drop the sort; `ATTACH` the pack and aggregate in one join; cache until the next attempt. |
| P5 | medium | `pkdone.lua:388-392`, `pkstudies.lua:259-260`, `290-298` | Opening a chapter bumps a global version, so the studies list **rescans the folder tree** (recursive `lfs.dir` + stats + SQLite) on return; its `paintTo` also lists the folder on every repaint. | Separate counters for done marks and chapter state; check the folder's mtime first. |
| P6 | medium | `pkboard.lua:176-177`, `669`, `361` | Empty squares use a transparent SVG with `alpha = true`: every paint alpha-blends ~32 empty icons (and steps repaint the whole window). | Hide the label of empty squares (`label_widget.hide`). |
| P7 | med-low | `pkpuzzleview.lua:371-389`, `pkprogress.lua:63-64` | A missed puzzle = two commits; no PRAGMA anywhere: `journal_mode=DELETE`, `synchronous=FULL` (journal file + several fsyncs per write on slow flash). | One transaction for attempt + review; consider `journal_mode=TRUNCATE` (or WAL) and `synchronous=NORMAL`. |
| P8 | low-med | `pkopenings.lua:58-59`, `177` | The last repertoire opened (study, trees, cards) stays in a module variable for the whole KOReader session. | Clear it when the list and drill are closed. |
| P9 | low | `pkstudy.lua:84-95`; `pkpgn.lua:238-243` | Every visited chapter's tree is kept with its movetext; every node gets empty `glyphs`/`children` tables, every comment 3 shape tables (~310 B per node). | Keep only the current chapter's tree; create tables lazily. |
| P10 | low | `pkpgn.lua:263-266`, `pksan.lua:63-77`, `220`, `413`, `423` | Per-character loops (`text:sub(pos,pos)` + `match`, `gmatch(".")` in `parseFen`); `checkMark` applies the move again after `resolve`. | Dispatch on `string.byte`, skip whitespace with `find`; reuse the applied position. |
| P11 | low | `pkpuzzlepack.lua:53-55`; `pkprogress.lua:110-112`, `144` | `count(*)` over the whole pack each time Puzzles opens (only to test emptiness); `count(*)` over attempts on every attempt (only to compare with 20). | `EXISTS(...)` / `meta.puzzle_count`; `LIMIT 20` subquery or a kv counter. |
| P12 | low | `pkpuzzlepack.lua:101-114`; `pkpuzzleview.lua:266-279` | The pick tries bands up to home ± 30 that cannot exist (~1000 queries when a theme is exhausted); with a theme, every Next looks up every due review of other themes again. | Clamp bands to the pack's min/max; remember non-matching reviews per session. |
| P13 | low | `pkpromotion.lua:29-32`, `71-73` | The promotion chooser is an `InputDialog`: it builds a full virtual keyboard each time (never freed), refreshes the whole screen on show/close, and has no cancel. | A small dedicated dialog (or `readonly = true` at least), with a cancel. |
| P14 | low | `pkboard.lua:370-382`, `419-426`, `676-681` | Per paint: 64 new `Geom` + 64 strings for the rect cache, a new `TextWidget` for the badge; per changed square: a full `Button:init` via `setIcon`. | Update rects in place; cache the badge label; swap only the icon widget. |
| P15 | low | `pkboard.lua:224-228`, `626-645` + views | Selection refreshes bypass the board's batch: switching the selection sends two REAGL refreshes (the second waits). | `_repaintSquare` → `_refreshSquare` (join the batch). |
| P16 | low | `pkstudyview.lua:649-652`, `560-565`; `pkdrillview.lua:179`; `pkpuzzleview.lua:594-600` | A correct lesson move with a comment refreshes the panel twice; the drill recounts all cards on every step; Solution builds the themes line twice (font shaping). | Refresh once; maintain counts incrementally; compute the line once. |
| P17 | low | `pkutils.lua:36-46`, `pkuci.lua:175-182`, `213-220`, `98` | Engine output polled every 1 s, 4 KB per tick, with an uncancellable closure; `state.infos` grows for the whole game. | One engine-owned task unscheduled in `stop()`; drain until empty; keep the last info. |
| P18 | low | `pkstatsview.lua:170`, `192` | Each page turn builds the footer twice (once to measure) and does not free the previous tree. | Measure once; free the old tree. |

## 3. Tooling, deploy and tests

| # | Sev. | Where | Finding | Fix |
|---|---|---|---|---|
| T1 | medium | `tools/dist/pka.sh:11-50` | `curl … \| sh` runs lines as they arrive: a cut connection can run the delete block without the extraction. | Wrap the body in `main() { … }; main "$@"`. |
| T2 | medium | `tools/dist/pka.sh:30-48` | Not atomic: old files deleted before extraction; a full disk leaves no plugin. | Extract to a staging folder, swap on success. |
| T3 | medium | `pka.sh:21-27`, `build-pka.sh:15` | No integrity check (`curl -k`, only `tar tf`); gzip's status is ignored in the pipe. | Bake the archive's sha256 into the installer at build time and `sha256sum -c` it. |
| T4 | medium | `pipeline/…/sources.py:33,64-67`; `cli.py:72-81` | A partial download is resumed without `If-Range` onto the next month's dump (corrupt file); the cache is never refreshed (no `--force` in the CLI). | Store ETag, send `If-Range`; add `--refresh`. |
| T5 | medium | `harness.koplugin/main.lua:54-67`; scenarios | E2E time is mostly fixed sleeps (0.5 s per tap, `h.wait(1)` after views open): ~58 s in studies, ~22 s in lessons and puzzles; the pending-reply tests sleep 3.5 s each. | Synchronous tap settle (`forceRePaint`), `h.waitFor(pred)`, call reply tasks directly. |
| T6 | medium | `plugin/tests/san_spec.lua:43-59` | 27.9 s of the 32 s `make test-lua`: a new game + `load(fen)` for every ply of every game. | Reuse one game, or sample; full run behind a flag. |
| T7 | low | `tools/emulator/run.sh:48`, `51-55` | Scenarios share one home dir (serial only); a timeout is reported as "no result written". | One home per scenario (`xargs -P`); report exit 124 as a timeout. |
| T8 | low | `tools/dist/build-pka.sh:12` | The archive ships upstream dev files (`pkchesslib/spec`, `.travis.yml`, `perft.lua`, `example.lua`) and any untracked file. | Exclude them, or use `git ls-files`. |
| T9 | low | `pka.sh:39-41`; `Makefile:27` | The delete list accepts `..` paths; the KOReader download has no checksum. | Refuse `*..*`; pin a sha256. |
| T10 | low | `plugin/tests/run.lua:2,212`; `harness…/main.lua:156` | A spec's top-level error aborts the run without summary; no tracebacks; a scenario's top-level error escapes the harness. | `pcall(dofile)`, `xpcall(…, debug.traceback)`; `pcall(chunk)`. |
| T11 | low | `pipeline/…/cli.py:52`, `puzzles.py:140`, `studies.py:60-63` | Offline/DNS errors print tracebacks; `--per-band 0` raises; study validation recurses per ply (`RecursionError` past ~990 plies). | Catch `URLError`; argparse validation; iterative walk. |
| T12 | low | tests | Gaps: pkboard (en passant), pkuci, pkpromotion, unsupported pack format, pipeline failure keeping the old pack, mastered review not fresh, rollback, legacy review steps, pickNear edge cases, drill free-mode wrong answer and cap branch, pkpgn edge cases. | Add specs alongside the fixes above. |
| T13 | low | `pipeline/tests/*.py`; `scenarios/studies.lua:22-27,231-235,256` | Unclosed fixture files; `pytest.raises(Exception)`; duplicate `local lfs` and dead cleanup in the study scenario. | Small cleanups. |

## 4. Code quality

- **Copies of KOReader code** (`pkbutton.lua:21-221`, `pkbuttontable.lua:14-154`):
  full copies of `Button:init` and `ButtonTable:init` that have drifted
  (missing background/border defaults, `no_refresh_checkmark`). The text
  branch of `pkbutton` is unused. Suggest calling `KOButton.init` and patching
  only the icon path and `day_colors`, and building the 8×8 grid directly
  (also removes 56 zero-width separators and the dead `addVerticalSpan`).
- **Study and drill views duplicate most of their code** (`_build`,
  `_textWidget`, `_setText`, `_redraw`, the undo/redo hack, reply timer, hint
  ring, verdict handling; `PkLesson` and `PkDrill` mirror each other). A shared
  base screen would remove several hundred lines.
- **One refresh policy**: the board still has `button:refresh()` (`fast`) and
  `"ui"` fallbacks for boards without `square_refresh` (only the Play board);
  give it `PkRefresh.STEP` and delete the fallbacks. Square rectangles come
  from three sources (`button.dimen`, `button[1].dimen`, `_rects`); use only
  `_screenRect`. The views repeat `unmarkSelected` + `selected = nil`
  instead of `Board:clearSelection()`.
- **Kochess leftovers in `main.lua`**: unused requires (`Event`,
  `VerticalSpan`), `registerHold`/`dbgTable`, `holdCallback = nil`, "NEW:"
  comments, an empty `onCancel`; cleanup only in `pk_close`, not in
  `onCloseWidget`; `nextTick` in the home menu not cancelled (`pknav.lua:235`).
- **Test hooks kept in production**: `PkNav.quick_dialog` (`pknav.lua:136`)
  and `PkLinks.dialog` (`pklinks.lua:114`) keep the last dialog alive for the
  session.
- **Global patching**: `main.lua:128-130` + `pkfonts.lua:36-38` insert into
  KOReader's `Font.fallbacks` on every FileManager/ReaderUI init, bypassing
  the user's fallback cap. CLAUDE.md forbids patching globals: decide in an
  ADR (once per process, respect the cap) or document the exception.
- **Error handling**: progress calls without pcall in `pkpuzzleview.lua:77`,
  `556`, `568` and `pkstudyview.lua:454`, `462`, `606`; `PkProgress.open`
  and `pknav.puzzlesStatus` leak the connection on error; pack statements left
  mid-step (`pkpuzzlepack.lua:57-58`, `77`).
- **Misleading comments**:
  - `pkboard.lua:541-552`: says unchanged pixels are not touched; REAGL
    redraws the region.
  - `pkboard.lua:25-27`: the night last-move tint is described as "three
    levels above"; it is four above the light squares and five above the dark
    ones.
  - `pkrefresh.lua:39`: the guard `if not title_bar.dimen` never triggers;
    `setSubTitle` also crashes without a subtitle widget.
  - `main.lua:267`, `293`, `624`, `647-650`, `pkuci.lua:18-29`,
    `pklesson.lua:275`.
- **Dead or duplicated helpers**: `PkSan.square`/`squareName`/`attacked`,
  `PkStudy.Cursor`, `PkPuzzleReview.isDue` (tests only), `ulen` in pkpgn vs
  pktext, `MOVE_MARKS` vs `NAG_SYMBOLS`, `dir`/`withProgress`/`MAX_BYTES`
  duplicated between pkstudies and pkopenings, `positionToColor` vs
  `chessToId`; `_()` applied to concatenated strings in pkboard; `_bad`
  initialised lazily in two places.
- **Small UX inconsistency**: the "Reviews: N" subtitle counts reviews of
  other themes and those already skipped this session.

## 5. Docs out of date

- `docs/architecture.md`: 10 modules missing (pkdone, pkdrill, pkdrillview,
  pkfonts, pklinks, pkopenings, pkrepertoire, pksan, pksrs, pktext); the menu
  list predates Home and Openings.
- `docs/development.md`: lists `zstd` (unused) but not `rsync`; mentions a CI
  that does not exist; misses `PAPERKNIGHT_REPERTOIRES_DIR`, `h.swipe`,
  `h.recordRefreshes`, and the `make pka` flow; its rsync deploy deletes
  `bin/`.
- `docs/data-sources.md`: the dump has an 11th column, `DailyDate`.
- `docs/pack-format.md`: `selection` described twice; `LIMIT 25` (code: 100).
- `_meta.lua`: description mentions playing Stockfish (not shipped) and not
  Studies.

## 6. Checked and clean

- **Board night mode** (soft inversion, pre-inverted colours, piece set swap),
  board refresh batching, badge and shape refresh squares.
- **pkrescache** (atomic write, validation before apply), pkfonts
  idempotence, pkicons paths, pkside glyph swap.
- **SQLite**: every INTEGER read goes through `tonumber`; all statements
  prepared at open are closed; indexes cover every per-puzzle query; the
  pick queries are tested to use an index without a sort.
- **Scheduling**: `PkSrs.today` (4 am boundary), rating formula (ADR-0010),
  SM-2 in the drill (ADR-0012); reply timers cancelled on every exit path in
  the puzzle, study and drill views.
- **pksan rules**: castling (rights, path, attacked squares), en passant with
  a horizontal pin, promotion forms, minimal disambiguation ignoring pinned
  pieces; bounded FEN cache.
- **Studies data**: pkdone renames (transactional), pktext linkify, widget
  freeing on rebuild and close.
- **Pipeline**: the 300 MB dump is streamed (≈60 s for 5.6 M rows, bounded
  memory); python-chess validates only heap candidates; inserts in one
  transaction; download resume and retry tested against a local server.
- **Night mode toggle and frontlight** reuse KOReader's own listeners and
  widgets; `pktimer` never piles up tasks.

## Follow-up (2026-10-14)

Fixed, each with a test that fails without the fix:

- **Bugs**: 1–23 except 20 (long-form piece moves) and part of 21–22
  (an illegal engine move still stalls the game; Play settings are not
  saved). The game screen is now `pkgame.lua`.
- **Performance**: P1–P8, P11, P12, P13 (no keyboard, dialog-only
  refreshes; still no cancel, a piece must be chosen), P14 (rectangles
  updated in place, badge label cached; `setIcon` still rebuilds the
  button), P15, P16, P18, and the whitespace part of P10.

Not done yet: P9 (lazy node tables), the rest of P10 (`parseFen`,
`checkMark`), P17 (engine polling), bug 20, and sections 3–5 (tooling,
quality, docs), which were not part of this pass.
