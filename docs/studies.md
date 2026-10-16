# Studies

Lichess-style studies on the e-reader: browse annotated chapters, follow
variations, read comments, see arrows/circles, and train interactive chapters.
Decision record: [ADR-0011](adr/0011-studies-from-pgn.md).

## Getting a study onto the device

- **From Lichess**: open the study → *Share & export* → *Study PGN* (or
  `make study ID=<8-char id>` / `python -m paperknight_pipeline study <id-or-url>`,
  which calls `https://lichess.org/api/study/<id>.pgn?orientation=true&clocks=false&comments=true&variations=true`).
  The pipeline export always includes `[Orientation]`; a PGN downloaded from the
  Lichess website may not: chapters then open from White's side, except set-up
  positions, which open from the side to move. *Flip board* fixes the rest.
  Private studies need a personal token with `study:read`.
- Copy the `.pgn` to `koreader/paperknight/studies/` on the Kindle. The
  Studies list follows the folder: a file added while it is open shows up
  when you come back to the list.
- **Folders**: sub-folders of `studies/` (e.g. `Openings/`, `Endgames/`)
  are listed first, as `Openings/` with the number of studies inside (and
  `done/total ✓` once some are done); tap one to open it, Back to return.
  Folders can be nested.
- Any PGN works; each game is a chapter.

## What we read from the PGN

| PGN element | Use |
|---|---|
| `[StudyName]` | Study title (else the file name) |
| `[ChapterName]` | Chapter title (else `White – Black`, else `Event`, else "Chapter n") |
| `[Orientation "white"/"black"]` | Board orientation and the student's side in lessons (else White; for a chapter with a set-up `[FEN]`, the side to move). *Flip board* reverses it per chapter |
| `[ChapterMode "gamebook"]` | Interactive chapter |
| `[FEN]` + `[SetUp "1"]` | Custom starting position |
| `{ text }`, `; text` | Comments (a comment before the first move is the chapter intro) |
| `[%anno "Name", id]` in comments | Comment author — stripped from the text |
| `[%csl Gd4,Re5]` | Circles: brush letter (G/R/Y/B) + square |
| `[%cal Ge2e4]` | Arrows: brush letter + from + to |
| `[%clk …]`, `[%eval …]`, `[%emt …]` | Ignored (stripped) |
| `!`, `?`, `!!`, `??`, `!?`, `?!`, `$1`–`$6` | Move glyphs, attached to the move (`Bc4!?`) |
| `$7`, `$10`, `$13`–`$19`, `$22`, `$32`…`$146` | Position glyphs: in words in the text panel ("White is slightly better"), compact ASCII/Latin-1 (`+=`, `±`, `+-`, …) in move lists; other codes show as `$n` |
| `( … )` | Variations (nested to any depth) |

## Viewer

- Board (orientation from the chapter), last move tinted, circles drawn as a
  dark ring on the square, arrows drawn as thick dark lines with a head
  (brush colours are not distinguishable on e-ink; all shapes use one style).
  The move's mark (`!`, `!!`, `!?` / `?`, `??`, `?!`) is a badge in the corner
  of its square: a black disc for good marks, a white ringed disc for bad ones.
- Text panel: the current move (`12... Nf6!?`), the position assessment in
  words, then the comment; the chapter intro at the start; a hint when the
  next move has alternatives.
- Comments keep their line breaks (lists, short lines) as written on Lichess;
  a PGN wrapped at 80 columns by a tool (every movetext line ≤ 80 characters
  and filled) has its lines joined back into paragraphs.
- Web addresses are shown short (`youtube.com ↗`). Tap one to see a QR code of
  the full address (scan it with a phone), or use ≡ → *Links…*.
- Navigation: ⏮ start · ◀ back · *Lines* · ▶ forward (follows the current
  line) · ⏭ end of line · *Train*. *Lines* chooses among the alternatives at
  the next move (main move first, then variations). Tapping on the board a
  move that exists as a child follows it; other moves are refused.
  Buttons that can't act are greyed (⏮ ◀ at the start, ⏭ at the end of the
  line, *Lines* without alternatives). At the end of a line (or in a chapter
  without moves), ▶ opens the next chapter, announced in the panel; leaving
  a chapter with moves this way marks it as done.
- **Move list** beside the board (#, White, Black): the moves up to the one
  shown (framed), then the line that follows; in a variation, that
  variation's line. Tap a move to go to it; swipe up/down on the list (or
  drag it) to scroll a long one. During a lesson it lists only the moves
  played. ≡ → *Hide move list* gives the board the full width (remembered).
- Title-bar menu (≡): *Chapters…* (chapter list; • marks the chapter shown),
  *Flip board*, *Hide/Show move list*, *Links…* (when the panel has links), *Mark chapter as done*,
  *Mark study as done*. A flip is
  remembered per study file and chapter (in `progress.sqlite`) and also sets
  the side trained in lessons; a running lesson restarts from the new side.
  After a finished lesson, *Next* opens the next chapter.
- **Done marks**: long-press a study in the Studies list, or ≡ → *Mark study
  as done* (in a chapter or the chapter list), to put a ✓ at the right of its
  name (again to remove it). Marks are kept in `progress.sqlite`, by file
  name. ≡ → *Hide done studies* in the Studies list hides them (remembered).
- **Chapter progress**: a finished lesson puts a ✓ next to its chapter in the
  chapter list (≡ → *Mark chapter as done* does it by hand); when every
  chapter is done the study gets its ✓ too (it stays until you remove it).
  Chapters without moves (intros) don't count. Using *Solution* still
  counts as finishing. For studies with several chapters, the list starts
  with *▶ Continue* once you have opened one: it reopens the last chapter
  you read.
- Marks, flips and *Continue* are stored by **file name and chapter number**
  (not the folder: moving a study to another folder keeps them). Renaming
  a file loses them, unless the rename is listed in `studies/RENAMES.txt`
  (one `old name<TAB>new name` per line; the shipped collection uses it
  when it renames studies): the state moves to the new name when the
  Studies list opens, if the new name has none yet. Two studies with the
  same file name in different folders share their marks, and if a
  re-downloaded study gained chapters in the middle, the marks of the later
  chapters shift.
- **Emojis** (common in Lichess studies): KOReader has no emoji font. Copy the
  monochrome Noto Emoji font (OFL; e.g. `NotoEmoji-Regular.ttf`) to
  `koreader/fonts/`: Paperknight adds it to the UI fallback fonts at startup
  (the color Noto Color Emoji cannot be drawn and is ignored).
- E-ink: like page turns in KOReader, steps use non-flickering "partial"
  refreshes (the board-to-buttons area; the whole screen on a new chapter,
  ⏮/⏭ or a lesson start), and KOReader flashes the screen once every N of
  them, N being your *Screen → E-ink → Full refresh rate* setting ("Never"
  works too; *Avoid flashing* is honoured). The openings drill and the
  puzzles do the same.
- Text is shown with invalid UTF-8 replaced (older Latin-1 PGNs); files over
  2 MB are refused (game databases are not studies).

## Interactive chapters (Lichess gamebook rules)

The student plays the side the board is oriented to.
1. At the student's turn, the main-line move is correct: it is played, then the
   opponent's main-line reply after a short delay.
2. A move that exists as a variation at that point is a known mistake: its
   comment is shown ("bad"), then the student goes back and retries.
3. Any other move: "Not the move", retry.
4. The chapter ends when the main line ends; the final comment is shown.
5. Hint: the square of the piece to move (Lichess hints are not exported).
   Solution: plays the expected move.

Ordinary chapters can be trained with **Train** (same flow; the student plays
the chapter's orientation). There, a move found in a variation is reported as
a *sideline* ("find the main move"), not a mistake, and the annotator's
arrows/circles are hidden while it is the student's turn (they often point at
the answer).

Pacing follows Lichess: opponent moves play automatically after a short pause
unless the position just shown has a comment — then the lesson waits for
**Next** so it can be read. The status line ("Your move", "Correct!", the
summary) is always shown above the comment. If the PGN contains an illegal
move on the main line, the lesson stops with a message and **Browse** remains. **Browse** leaves the
lesson at the current position; **Restart** starts over. While a lesson runs,
the panel never shows upcoming moves.
