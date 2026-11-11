# ADR-0022: The puzzle pack is a release of its own; puzzles under review are kept

- Date: 2026-11-11
- Status: accepted

## Context
Every plugin release rebuilt the puzzle pack from the Lichess database the
CI cache held, and named it after the day that database was downloaded.
The cache key is the month and GitHub drops caches unused for a week, so a
release in a new month, or after a quiet week, published a "new" pack:
v0.6.1, a one-line fix, made every device download 9 MB of puzzles.

A new pack is not the old one plus some puzzles. The packs of 2026-10-19
and 2026-11-03 hold 60,657 and 60,776 puzzles, 53,793 in common: 6,864
(11%) dropped, because ratings, popularity and play counts move between
two dumps and the selection follows them (docs/reviews/2026-11-11).
The plugin deleted the review card of a missed puzzle that the new pack no
longer had, and a liked puzzle that was gone could only be opened on
Lichess. The user was not told.

Two questions: when does a device get a new pack, and what happens to the
user's puzzles when it does.

## Options
### A. Keep building the pack in the plugin release, version it by content
A hash of the pack as its version: the same database gives the same
version.
- Pros: the smallest change.
- Cons: a new month still changes the pack with any release; the loss of
  cards is untouched.

### B. A sticky selection in the pipeline
Build each pack from the previous pack's puzzles first, then fill up.
- Pros: few puzzles ever leave; nothing changes in the plugin.
- Cons: every pack depends on the one before (a build needs it at hand);
  puzzles whose quality dropped stay for ever; a puzzle Lichess removed is
  still lost; packs built by hand (`make packs`) are not covered.

### C. The pack as a release of its own, and the user's puzzles kept on the device
The pack is published by its own workflow, as Stockfish is, and a plugin
release only names the pack it offers. The plugin keeps a copy of each
puzzle under review or liked in the progress file.
- Pros: a pack changes on purpose, with one reviewed line; a plugin
  release downloads the plugin only; the user's reviews and likes survive
  any pack, hand-built ones too; the pipeline stays stateless.
- Cons: one more release to publish before a plugin release; a second
  place where a puzzle can live (the pack, then the kept copy).

## Decision
C. It answers both questions separately, each in the place that owns it:
releases decide when a pack changes, the progress file owns what the user
has touched.

- `puzzles.yml` builds the pack on a `puzzles-YYYY-MM-DD` tag and publishes
  `paperknight-puzzles-<date>.tar.gz` as a release that is not marked
  latest. `release.yml` names it (`PUZZLES_RELEASE`) and `install.sh`
  downloads it from there, with its checksum, as it does Stockfish.
- `progress.sqlite` gets a `puzzles_kept` table: the pack's row of a
  puzzle, saved with its review card (in the attempt's transaction) or its
  like, and removed once the puzzle is neither under review nor liked. The
  puzzle screen looks a puzzle up in the pack first (its rating is the
  current one), then in the kept copies. Opening the puzzle screen keeps
  the puzzles of cards and likes made before this decision, from the pack
  at hand.

## Consequences
- A plugin release never changes the pack; a new pack is a tag and a
  one-line change of `PUZZLES_RELEASE`, visible in the release notes.
- The first puzzles release, `puzzles-2026-11-03`, holds the archive v0.6.1
  published, under the same version: devices on v0.6.1 keep their pack.
- A card made before this decision whose puzzle an earlier pack already
  dropped cannot be saved: it is removed, as before.
- Kept puzzles do not cover the statistics: an attempt on a puzzle that
  left the pack no longer counts under its themes. Keeping themes with the
  attempts would fix it, if it shows.
- A local `make dist` still packs the stage's pack; with
  `PAPERKNIGHT_PUZZLES_ARCHIVE`, `_URL` and `_VERSION` it offers a released
  one.
- To revisit if packs grow much larger or if the selection should stop
  following Lichess's ratings: option B can be added on top.
