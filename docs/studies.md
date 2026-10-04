# Studies

Lichess-style studies on the e-reader: browse annotated chapters, follow
variations, read comments, see arrows/circles, and train interactive chapters.
Decision record: [ADR-0011](adr/0011-studies-from-pgn.md).

## Getting a study onto the device

- **From Lichess**: open the study → *Share & export* → *Study PGN* (or
  `make study ID=<8-char id>` / `python -m paperknight_pipeline study <id-or-url>`,
  which calls `https://lichess.org/api/study/<id>.pgn?orientation=true&clocks=false`).
  Private studies need a personal token with `study:read`.
- Copy the `.pgn` to `koreader/paperknight/studies/` on the Kindle.
- Any PGN works; each game is a chapter.

## What we read from the PGN

| PGN element | Use |
|---|---|
| `[StudyName]` | Study title (else the file name) |
| `[ChapterName]` | Chapter title (else `White – Black`, else `Event`, else "Chapter n") |
| `[Orientation "white"/"black"]` | Board orientation and the student's side in lessons (else White; for a gamebook chapter without the tag, the side to move at the start) |
| `[ChapterMode "gamebook"]` | Interactive chapter |
| `[FEN]` + `[SetUp "1"]` | Custom starting position |
| `{ text }`, `; text` | Comments (a comment before the first move is the chapter intro) |
| `[%anno "Name", id]` in comments | Comment author — stripped from the text |
| `[%csl Gd4,Re5]` | Circles: brush letter (G/R/Y/B) + square |
| `[%cal Ge2e4]` | Arrows: brush letter + from + to |
| `[%clk …]`, `[%eval …]`, `[%emt …]` | Ignored (stripped) |
| `!`, `?`, `!!`, `??`, `!?`, `?!`, `$1`–`$6` | Move glyphs, shown after the move |
| `$10`–`$19`, `$13`, `$14`–`$19`, `$32`…`$146` | Position glyphs (=, ⩲, ±, +−, ∞, …), shown with the move |
| `( … )` | Variations (nested to any depth) |

## Viewer

- Board (orientation from the chapter), last move tinted, circles drawn as a
  dark ring on the square, arrows drawn as thick dark lines with a head
  (brush colours are not distinguishable on e-ink; all shapes use one style).
- Text panel: the current move (`12... Nf6!?`), its glyphs and comment; the
  chapter intro at the start; a hint when the next move has alternatives.
- Navigation: ⏮ start · ◀ back · *Lines* · ▶ forward (follows the current
  line) · ⏭ end of line · *Train*. *Lines* chooses among the alternatives at
  the next move (main move first, then variations). Tapping on the board a
  move that exists as a child follows it; other moves are refused.
- Chapter list from the title bar; previous/next chapter.

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
a *sideline* ("find the main move"), not a mistake. **Browse** leaves the
lesson at the current position; **Restart** starts over. While a lesson runs,
the panel never shows upcoming moves.
