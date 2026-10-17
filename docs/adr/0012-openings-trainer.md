# ADR-0012: Openings trainer — repertoire PGNs, per-move cards, SM-2 scheduling

- Date: 2026-10-05
- Status: accepted

## Context
Milestone 3 asks for a repertoire drill with spaced repetition. A repertoire is
the user's own choice of moves for one side, with the opponent's likely
replies as branches. Three things are costly to change once users have
months of review history: where repertoires come from, what a reviewed "card"
is, and how cards are scheduled and stored.

## Options

### Source of repertoires
**A. PGN files in `koreader/paperknight/repertoires/`** (same parser as
studies, ADR-0011). One file = one repertoire, chapters = sub-repertoires;
`[Orientation]` (or the ADR-0011 default) is the side the user plays.
- Pros: users already build repertoires as Lichess studies or in ChessBase;
  no pipeline step; reuses tested code.
- Cons: no moves out of the box unless we ship a sample.

**B. Generated from lichess chess-openings (CC0) on the PC.**
- Pros: thousands of named lines.
- Cons: the TSV lists named positions, not a repertoire: it has no "my move"
  choice, and picking replies needs the opening explorer (token-gated since 2026).

### Unit of review ("card")
**A. A whole line** (root → leaf). Simple, but one wrong move resets a long
line and transpositions are reviewed many times.
**B. One user move in one position** (normalized FEN without move counters →
expected move). Lines are only a way to reach due positions. Transpositions
share a card; a mistake reschedules only that move. (This is how Chessable /
Listudy style trainers work.)

### Scheduling
**A. Leitner boxes** — simple, coarse.
**B. SM-2 (Anki-style)** — ease factor per card, well understood, tiny state.
**C. FSRS** — better retention model but needs fitted weights and more code;
overkill on a Kindle with a few hundred cards.

## Decision
- **Source A**: repertoire PGNs in their own folder. A small sample
  repertoire written by us (moves are facts; own comments) can ship later.
- **Card B**: key `(repertoire file name, normalized FEN)`; the card stores
  the expected move. If two lines play different moves in one position, the
  first met (tree order) wins and the other line stops before its move. Lines
  end on a user move.
  At the user's turn the **main** child is the move to play; other children at
  the user's turn are treated as known mistakes (their comment is shown) and
  lines through them are not drilled. At the opponent's turn every child is a
  branch to learn.
- **Scheduling B, simplified SM-2** with grades *again* (wrong move, or hint /
  solution used) and *good* (right first time):
  - a new card is first *introduced* (the move is shown and played, not
    tested); it is then due the same day;
  - good → 1 day after introduction or a failure; second success → 3 days;
    then max(interval + 1, interval × ease);
  - again → due again the same day (the session repeats it), ease − 0.20
    (min 1.3); good → ease + 0.05 (max 2.8); start ease 2.5; a lapse is
    counted only when a learned card (≥ 1 success) is failed;
  - days are local calendar days starting at 4 am;
  - only due or new cards are rescheduled when met in a line; a non-due card
    answered wrongly is still graded *again*.
  - New cards per day are capped (default 10) so a big repertoire is learned
    gradually.
- **Drill session**: pick the line that reaches the most-overdue card (then
  new cards in tree order); play it from the start, opponent moves automatic,
  user moves graded; repeat until no card is due or the user stops.
- **Storage**: table `rep_cards` in `progress.sqlite` (ADR-0010):
  `(rep, fen, move, due, interval, ease, reps, lapses, last, introduced)`, PK
  `(rep, fen)`; `introduced` (day number) drives the daily new-card cap. Packs stay read-only (ADR-0005).
- **Logic in pure Lua modules** (`pksrs.lua` scheduler, `pkrepertoire.lua`
  lines/cards, `pkdrill.lua` session), unit-tested; the screen only displays.

## Consequences
- Easy: any Lichess study of a repertoire works by copying the PGN; review
  history survives edits of the PGN as long as positions/moves stay.
- Renaming a repertoire file orphans its cards (key = file name); editing a
  move creates a new card and the old one is never due again (harmless).
- A different main move for the same position in one file conflicts: the
  first one met wins and the other line is cut there (counted and logged).
- Opening names (Milestone 3 item) need the chess-openings TSV later; not
  required by the drill.
- Revisit with FSRS if users have thousands of cards.

## Amendment (2026-10-17): known moves played for the user, pauses on comments
Replaying every known move from the start made deep cards slow to reach,
and a comment on the user's move was replaced by the opponent's reply
0.8 s later. Now, by default, the user's known moves that are not due are
played automatically like the opponent's (no grade), the session stops at
each new or due move, and a line ends after its last move to ask
(`PkDrill.play_known` false; ≡ → *Play my known moves too* restores the
former behaviour, where a wrong answer on a non-due move still counts).
After a right move that has a comment (except a new move, whose comment
was shown before), the opponent waits for *Continue*. Cost: no extra
practice of known moves between reviews (Chessable's review works the
same way).
