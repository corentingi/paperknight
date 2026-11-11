# Project review — 2026-11-11

The whole project at commit `4a4b07c` (v0.6.1), read the way an experienced
developer and a product manager would: the product, the code, performance,
tests and CI, the release pipeline, the docs. One reviewer, no code changed.
The previous review is `2026-10-14-code-review.md`; its findings are not
repeated here (the ones checked again are fixed).

How to read the findings:

- **measured**: a number from a script run for this review, on the desktop
  (x86-64, KOReader's LuaJIT). The Kindle PW2 is roughly 10–20× slower.
- **read**: seen in the code or in a published release file.
- **to confirm**: a risk that follows from the code but was not reproduced.

Paths are relative to `plugin/paperknight.koplugin/` unless they start with
another top-level folder.

## Summary

The project is in good shape for its age: six training modes, a tested
installer, releases built by CI, 147 Lua cases, 57 pytest cases and 12
end-to-end scenarios that run in about 80 seconds. The code is small
(12,700 lines of Lua, 1,100 of Python), has no TODO left in it, and only 12
of its 733 functions are longer than 60 lines.

What deserves attention, most important first:

1. **A new puzzle pack deletes review cards.** Two packs released two weeks
   apart share 89% of their puzzles; a missed puzzle that is not in the new
   pack loses its review silently. Every release can publish a new pack,
   even a one-line fix (P1, R1).
2. **Master games get slow in long games.** The move history is rebuilt
   about 16 times per guess, and each rebuild replays the whole game (F1).
3. **The update is not authenticated.** `install.sh` is downloaded with
   `curl -k` and run; the checksums inside it cannot protect it (S1). This
   is a known trade-off (ADR-0019), but two cheap mitigations exist.
4. **An update can hang with no way out**, and using the app after an
   update without restarting may mix two versions (U1, U2).
5. **No backup of the user's progress**, and no licence text in the release
   archives (P3, L1).
6. **Product**: the USB zip is downloaded about ten times more than the
   installer, the app only names one device, and it is English only (P4–P6).

## 1. Product

| # | Finding | Evidence | Suggestion |
|---|---|---|---|
| P1 | **A new puzzle pack removes part of the user's history.** Between the packs of v0.6.0 (2026-10-19) and v0.6.1 (2026-11-03): 60,657 and 60,776 puzzles, 53,793 in common, **6,864 dropped** (11%), 36,121 with another rating. A due review whose puzzle is gone is deleted (`pkpuzzleview.lua:314-316`, "the pack was replaced"); a liked puzzle that is gone is only offered as a QR code. The user is not told. | measured (both release assets compared), read | Keep the card when its puzzle is missing (skip it, don't delete it), or make the selection sticky: build the new pack from the previous pack's ids first, then fill up. Say in the update dialog that the puzzle pack changes. |
| P2 | **A release costs the user a 9 MB download that brings nothing they asked for.** v0.6.1 fixed one night-mode colour; devices also downloaded a new puzzle pack. See R1 for the cause. | read (`install.sh` of v0.6.1) | R1. |
| P3 | **Progress has no backup or export.** The rating, attempts, review cards, repertoire cards, likes, best scores and games in progress live in one file (`settings/paperknight/progress.sqlite`). Nothing in the app copies or exports it; a corrupted file means "Cannot open the progress database" (`main.lua:121-129`) and no way forward in the app. | read (no "backup" or "export" in the plugin) | A copy of the file once a day or before each update (`progress.sqlite.bak`), and an offer to start again from the copy when the file cannot be opened. |
| P4 | **Most people install from the USB zip.** Downloads of v0.6.1 after 8 days: USB zip 38, `install.sh` 4, plugin archive 1. Counts are small and include bots, but the order of magnitude is clear. The USB path gets less room: it is one paragraph in the README, after the terminal command, and its zip always carries the PW2 Stockfish. (The installer run after a USB copy is tested: `test-install.sh`, "USB zip, then the installer".) | read (GitHub release assets) | Treat USB as the main path: lead with it in the README and on the site, and add a "then update in the app" line. |
| P5 | **One device named, a much larger audience next door.** README, site and installer speak of the Kindle Paperwhite 2 only. The plugin itself is plain KOReader code; the installer defaults to `/mnt/us/koreader` and offers Stockfish only for `armv7*` as "pw2". Kobo is KOReader's largest user base. | read | Decide it on purpose. If other devices are wanted: say "should work on any KOReader device, tested on PW2", let the installer find KOReader on a Kobo (`/mnt/onboard/.adds/koreader`), and ask for device reports in an issue template. |
| P6 | **English only.** Every string goes through `_()`, but no translation ships and nothing loads one. | read | Low cost to offer French first (the strings are already marked); needs a small loader, since KOReader does not translate plugins' own strings. |
| P7 | **No way to hear from users.** No telemetry (a stated feature, keep it), no issue template, no "report a problem" entry in the app; 1 star, 0 issues. | read | An issue template (device, KOReader version, Paperknight version), and a *Settings…* entry showing the project's issues page as a QR code, like the links in comments. |
| P8 | **The roadmap has run out.** Every milestone is checked except "Test on a real Kindle Paperwhite 2" (which has been done, see the e-ink notes) and one item under *Later*. | read (`docs/roadmap.md`) | Tick the device test; write the next milestone. Candidates from this review: data safety (P1, P3), speed in long games (F1), other devices (P5), the rating over time on the stats page. |
| P9 | **Eight releases in 16 days** (v0.1.0 on 2026-10-19 to v0.6.1 on 2026-11-03), each asking for a KOReader restart. Fine while the project is young; with P2 it makes updating feel heavy. | read | Batch small fixes; keep patch releases plugin-only (R1). |

## 2. Security and update safety

| # | Sev. | Where | Finding | Suggestion |
|---|---|---|---|---|
| S1 | medium | `pkupdate.lua:286`, `tools/dist/install.sh:182`, README | **read.** The installer is fetched with `curl -k` (no certificate check) and run by `sh`, as root on a Kindle. The sha256 of each archive is written in that same installer, so it protects against a broken download, not against a replaced installer. ADR-0019 accepts this. | Two mitigations that keep the single installer: (1) try without `-k` first and fall back to `-k` only when the device's certificates fail, telling the user; (2) pin the installer: the app knows the release tag it is updating to, so publish `install.sh.sha256` in the release and check it against a second, independent fetch — or sign `install.sh` and ship the public key in the plugin. Record the choice in ADR-0019. |
| S2 | low | `tools/dist/install.sh:183-186` | **read.** When `sha256sum` is missing, the checksum is skipped without a word. Only `gzip -t` then guards the download. | Print "checksums not verified (no sha256sum)", or fail unless `--no-verify` is given. |
| U1 | medium | `pkupdate.lua:165-182`, `225-240` | **read.** `PkUpdate.run` polls for a status file forever. The check has `--max-time 60`; the download step (`install.sh`'s `curl`) has no time limit. If Wi-Fi drops or the Kindle sleeps mid-download, `PkUpdate.busy` stays true: *Check for updates…* then does nothing until KOReader restarts, with no message. | A deadline in `run` (kill the job, report "timed out"), `--max-time`/`--speed-time` on the installer's `curl`, and keep the device awake while downloading. |
| U2 | medium | `tools/dist/install.sh:205-229`, lazy `require` in most modules | **to confirm.** The plugin folder is swapped while the old version runs. Modules are loaded on first use (`require("pkanalysis")` inside functions), so after "restart later" a screen opened for the first time loads the **new** file into the **old** session. A release that changes an internal interface can then crash. | Either load every module before the swap, or after a successful update only offer "Restart now" plus "Close Paperknight". An e2e check: update, don't restart, open every mode. |
| U3 | low | `tools/dist/install.sh` (`install_files`) | **read.** No free-space check: a full disk is found during extraction. The old pack is still in place then, so nothing is lost, but the message comes late. | Compare `df` with twice the download size before starting. |

## 3. Performance

Device context: single-core ARM around 1 GHz, slow flash, every refresh
costs time. Desktop figures below.

| # | Sev. | Where | Finding | Suggestion |
|---|---|---|---|---|
| F1 | high | `pkgames.lua:141` (`Session:ply`), `pkgamesview.lua:195, 289, 311, 357`, `pkchesslib` `history()` | **measured.** `chess.history()` undoes every move and replays it, generating the legal moves at each ply: 8 ms at ply 60, 11 ms at ply 120, 22 ms at ply 271. `Session:ply()` is `#self.chess.history()` and is called from 11 places; a scripted run of Carlsen – Nepomniachtchi (133 guesses) made **2,129 `history()` calls, 16 per guess, 22.7 s of CPU** in the session logic alone. Near the end of that game one guess costs about 0.35 s on the desktop, so several seconds on the PW2, before any painting. The view adds its own calls (move list, line text). | Keep the ply as a counter in the session (set on start, +1 on each move played), and keep the SAN list and the verbose list in the session, appended on each move. No call to `history()` should remain on the per-move path. Add a spec that counts the calls. |
| F2 | medium | `pkplay.lua:140, 204, 252`, `pkplayview.lua:214, 232, 302, 329` | **read.** The same pattern in Play: several `history()` calls per move (save, move list, status). Games are shorter than the longest master games, so it shows later, but it grows with the game the same way. | The same fix, shared: one small "game record" kept next to the engine (ply, SANs, verbose moves). |
| F3 | low | `pkprogress.lua:176-204`, `pkplayview.lua:229-240`, `pkgamesview.lua:302-305` | **measured.** A setting is saved by opening the database, running the schema and the three migration checks, preparing three statements, writing, closing: 2.1 ms on the desktop against 1.4 ms on an open handle. Play and Master games do it on every move, with SQLite's full sync. On slow flash the sync is the cost, the reopening adds to it. | One shared handle for the session (`PkProgress.shared()`), closed when KOReader exits; the views that already hold a handle pass it on. |
| F4 | low | `pkgames.lua:93-109` | **measured.** Parsing one game's analysis costs 3 ms on average (all 75: 226 ms, 6.7 MB kept). Done on opening a game, kept for the session: fine as it is, but the parsed tables are never released. | Drop `game.moves`/`game.analysis` when the session closes, if memory ever matters. |
| F5 | info | `pkopeningnames.lua`, `pkgames.lua` | **measured.** `openings.tsv` loads in 5 ms (1.6 MB kept), the games list in 8.5 ms (0.5 MB). No action. | — |

## 4. Release pipeline

| # | Sev. | Where | Finding | Suggestion |
|---|---|---|---|---|
| R1 | high | `.github/workflows/release.yml:51-58`, `tools/dist/build-dist.sh:69-76` | **read.** The puzzle pack is rebuilt on every tag from whatever Lichess database the CI cache holds, and its version is **the day the database was downloaded**. The cache key is the month, and GitHub drops caches unused for seven days: a release in a new month, or after a quiet week, downloads again and publishes a "new" pack. That is how v0.6.1 changed the pack (P1, P2). | Make the pack a release of its own, like Stockfish (`puzzles-YYYY-MM`), published on purpose; the plugin release then points at it (`PUZZLES_RELEASE`, as `STOCKFISH_RELEASE`). At least: version the pack by a hash of its content, so the same database gives the same version. |
| R2 | low | `.github/workflows/*.yml` | **read.** Actions are pinned by major tag (`actions/checkout@v7`…), and the release job has `contents: write`. | Pin by commit SHA in `release.yml` and `stockfish.yml`, the two workflows that publish. |
| R3 | low | `.github/workflows/release.yml` | **read.** A tag runs `make check` again although CI already ran it on the same commit; harmless (80 s), and it protects a tag pushed on an untested commit. | Keep. |
| L1 | medium | plugin archive of v0.6.1 (78 files) | **read.** The plugin archive holds no `LICENSE` and no credits file, though it ships GPL-3.0 code (Kochess), the piece icons (GPLv2+) and `chess.lua`. The GPL asks for a copy of the licence with every copy of the program. The repository has both (`LICENSE`, `docs/credits.md`). | Copy `LICENSE` and `docs/credits.md` into the plugin folder in `build-dist.sh`; a line in `test-install.sh` that they are there. Check the USB zip the same way. |
| R4 | low | `_meta.lua:5` | **read.** `version = "0.1.0"` while the release is v0.6.1 (the app shows `version.txt`, so users don't see it). | Remove the field or write it from the tag in `build-dist.sh`. |

## 5. Tests and CI

What exists: 23 spec files (147 cases, 15 s), 57 pytest cases (6 s), the
installer tests under busybox (2 s), 12 e2e scenarios with 610 checks
(56 s, two at a time). A mutation check is required for each new e2e check.
This is a strong base for a project of this size.

| # | Sev. | Finding | Suggestion |
|---|---|---|---|
| T1 | medium | **No static analysis.** Neither `luacheck` for the Lua (global leaks and shadowed `_` have cost iterations before: see the `for _,` rule) nor `ruff` for the Python. | `luacheck` with KOReader's globals declared, `ruff check` on the pipeline, both in `make check`. Expect a first batch of warnings to sort. |
| T2 | medium | **`pkuci.lua` has no spec** (257 lines): the UCI line parser is a local function, reached only through the fake engine of two e2e scenarios. `bestmove … ponder`, option lines with spaces and the banner case are not tested one by one. | Export the parser (`M._parseLine`) and give it a spec. |
| T3 | medium | **The real Stockfish never runs in `make check`.** Play and the analysis board are tested against a shell script that answers like an engine. The real binary is only checked under qemu in `stockfish.yml`, for "does it start". | One optional scenario that runs when `STOCKFISH` points at a host binary (the one `make games` uses): start, `go movetime`, a legal `bestmove`, stop, no process left. |
| T4 | low | **No performance guard.** F1 would have been caught by a spec that counts `history()` calls, or by a time budget on a long game. | With the fix of F1. |
| T5 | low | **The update path stops at the installer.** `update_spec.lua` covers parsing and planning; `test-install.sh` covers the installer. Nothing covers U1 (a job that never ends) or U2 (use after update without restart). | With U1 and U2. |
| T6 | low | **`pkboard.lua` (992 lines) is tested only through e2e.** Its geometry helpers (ids, rectangles, the marker cell) are pure and would be cheap to unit-test. | A small `board_spec.lua` for the pure helpers. |
| T7 | info | Views without a spec (`pkpuzzleview`, `pkstudyview`, `pkanalysis`…) are covered by their scenarios; that is the right level for them. | — |

## 6. Code quality

| # | Sev. | Finding | Suggestion |
|---|---|---|---|
| Q1 | medium | **Schema changes are found by probing.** `pkprogress.lua:_migrate` looks for a column and two `kv` flags on every open. Three migrations today; each new one adds a query to every open, and the order between them is implicit. | A `schema_version` in `kv` (or `PRAGMA user_version`) and a numbered list of steps. |
| Q2 | medium | **Five ways to reach the settings.** `PkProgress.readSetting`/`writeSetting`, the views' `_setting`/`_saveSetting` aliases, `PkPrefs`, an open handle's `getSetting`, and KOReader's own settings in `pkfonts`. | With F3: one settings object over the shared handle; `PkPrefs` on top of it. |
| Q3 | low | **Three views are close to 1,000 lines** (`pkboard` 992, `pkpuzzleview` 974, `pkanalysis` 773, `pkstudyview` 768). They read well, but `pkpuzzleview` mixes the pick, the reviews, likes, the stats entry and the display. | Move the pick and the review queue out of the view (`pkpuzzlepick.lua`), where they can have a spec. |
| Q4 | low | **`pkuci.lua` keeps Kochess's style** (two-space indent, "New setOption method" comments, an option parser that stores values nobody reads). | Trim when T2 is done. |
| Q5 | low | **The upstream `chess.lua` is wrapped, not changed** (`pkchess.lua`), and its `history()` is the root of F1 and F2. | The game record of F2 lives in the wrapper and keeps the upstream file untouched. |
| Q6 | info | No TODO or FIXME in the code; 12 functions over 60 lines of 733, the longest being the PGN and SAN parsers, which have specs. | — |

## 7. Docs

| # | Finding | Suggestion |
|---|---|---|
| D1 | `docs/roadmap.md`: "Test on a real Kindle Paperwhite 2" unchecked (P8). | Tick it. |
| D2 | The README's screenshots show six screens; Play and Master games, the two newest modes, have none. | Add both (they exist as e2e shots). |
| D3 | No `CONTRIBUTING.md`; the rules a contributor needs (Conventional Commits, `make check`, the mutation check, ADRs) are in `CLAUDE.md`, which a human contributor will not open first. | A short `CONTRIBUTING.md` pointing at `docs/development.md`, with those four rules. |
| D4 | ADR-0019 states the `curl -k` trade-off; nothing user-facing does. | One sentence in the README's Install section (S1). |
| D5 | `docs/releasing.md` does not say that a tag may publish a new puzzle pack (R1). | With R1. |

## 8. Checked and sound

- **The engine process** (`pkuci.lua`, `pkutils.lua`): lines split across
  reads are kept, end of file is reported and handled by both views, `stop`
  closes the pipes and reaps the child with SIGTERM then SIGKILL, and never
  blocks the UI. The polling task is unscheduled.
- **The installer**: everything is downloaded and checked before anything
  changes, the plugin folder is swapped with a rename and restored on
  failure, the user's studies are kept, and the USB zip writes the same
  install records as the installer.
- **Transactions** in `pkprogress.lua` commit inside the protected call and
  roll back on any error.
- **The puzzle pack is deterministic** for a given database (a stable hash
  orders each band).
- **Scheduled tasks** in the views (reply delays, the clock) and the
  engine's poll are cancelled on close; the updater's poll is the
  exception (U1).
- **The release archive is clean**: 78 files, no test, fixture or upstream
  leftovers.

## Suggested order

1. **R1 + P1**: the pack as its own release, and review cards kept when a
   puzzle is missing. Stops the data loss and the 9 MB patch releases.
2. **F1 + F2**: the game record (ply, SANs, moves) kept as moves are
   played. The largest speed gain on the device, with a spec to hold it.
3. **U1, S2, L1**: an update that can time out, a visible "not verified",
   the licence in the archives. Small, independent changes.
4. **P3**: the daily copy of `progress.sqlite`.
5. **S1 + U2**: decide them in ADR-0019 (pin or sign the installer; force
   the restart).
6. **T1–T3**: linters, the UCI parser's spec, a real-engine scenario.
7. **Product**: P4 (USB first), P5 (other devices), P8 (the next
   milestone), then P6 and P7.

## Follow-up (2026-11-11)

Done the same day, each with its tests (`make check` green):

| Finding | Commit | What changed |
|---|---|---|
| F1 | `48e743f` | Master games keep the game so far (moves, SANs, positions) as it is played. The scripted run of Carlsen – Nepomniachtchi: 22.7 s of CPU → 0.15 s, no `history()` call left per guess; a spec counts them. |
| P1 | `5493586` | A puzzle under review or liked is copied into `progress.sqlite` (`puzzles_kept`); the puzzle screen looks in the pack, then in the copies. Cards made before get their copy when the Puzzles screen opens. |
| R1, P2 | `d9eeabf` | The puzzle pack is a release of its own (`puzzles.yml`, `PUZZLES_RELEASE` in `release.yml`, ADR-0022). `puzzles-2026-11-03` holds the archive v0.6.1 published, so devices keep their pack. |
| F3, Q1, Q2 | `be018bf` | One shared handle on the progress file (`PkProgress.shared`), the settings through it (a save: 2.1 ms → 1.3 ms on the desktop), schema changes as numbered steps (`PRAGMA user_version`). |

Still open from this review: F2 (the same game record for Play), S1, S2,
U1–U3, P3–P9, L1, R2, R4, T1–T6, Q3–Q5, D1–D5. Not covered by P1: a card
whose puzzle an earlier pack had already dropped, and the stats by theme
for attempts on puzzles that left the pack.
