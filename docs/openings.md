# Openings trainer

Drill your own opening repertoire with spaced repetition (ADR-0012).

## Getting a repertoire onto the Kindle

A repertoire is a PGN file in `koreader/paperknight/repertoires/`. The
easiest way is a Lichess study:

- one chapter per opening (or per opponent reply), with
  `Orientation` set to the side you play (Lichess sets it from the chapter's
  board orientation; `make study ID=…` keeps it). Without the tag a chapter is
  played as White (or, from a set-up `[FEN]`, as the side to move); the drill's
  ≡ menu → *Play the other side* switches a chapter, and is remembered;
- at **your** turn, the main move is your repertoire move. Other moves at your
  turn are treated as known mistakes: playing one shows its comment;
- at the **opponent's** turn, every variation is a reply to learn.

Copy the `.pgn` to the folder (USB, or `wget`/`curl` from kterm), then open
*Paperknight → Openings*.

In the drill, a move list beside the board shows the moves of the line so
far (never the move to find; ≡ → *Hide move list*, remembered), and the
panel names the opening ("C20 King's Pawn Game").

## The list

Each repertoire shows `N due · M new`: moves to review today and new moves
you can still learn today (10 per day and per repertoire).

Reading a repertoire takes seconds on an e-reader (every move is checked).
The first time, the list says *Loading repertoires…*; the result is cached
in `koreader/settings/paperknight/cache/` (per file: the list summary,
`.sum`, and the checked moves, `.res`). Later the list opens without
reading the files, and opening a repertoire skips the move checks. A file
that changes (date or size) is read again, and so is every file after an
update that changes how moves are checked; the cache folder can be deleted
at any time.

## A session

The trainer plays lines from the chapter's start (the initial position, or
its `[FEN]`). The opponent's moves are played automatically, and so are
your moves that you know and that are not due yet; it stops at each move
it asks (new or due), and the line ends after the last one. ≡ → *Play my
known moves too* (remembered) makes you play every move of the line again.

- **New move**: shown as an arrow ("New move: play Nf3"), with the PGN's
  comment. Play it to learn it; it is tested again later in the same session.
- **Review**: find the move. Right first time → it comes back in 1 day, then
  3, then longer and longer. Wrong move, *Hint* or *Solution* → it comes back
  in the same session and the interval starts over.
- A right move gets a ✓ on its piece. If it has a comment, the opponent
  waits: read it, then *Continue* (or the page-turn key).
- With *Play my known moves too*, a known move that isn't due is yours to
  play as well; a wrong answer there counts as a failure too.
- *Next line* after a finished line; when nothing is due and today's new moves
  are learned, the session ends with a summary.

The panel stays short: the instruction (a new move, a wrong one), then the
annotator's words. The opening's name and the counts are in the title bar,
the moves in the move list, and a disc in the board's bottom-left corner
(○ White, ● Black) shows when it is your move. Badges, assessments in words
and links (≡ → *Links…*) work as in studies.

Positions reached by different move orders share their review (one card per
position). If two lines of a file play different moves in the same position,
the first one wins and the other line stops there.

Reviews are stored in `koreader/settings/paperknight/progress.sqlite`, by file
name: renaming a repertoire file starts its history over.
