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
its `[FEN]`). The opponent's moves are
played automatically; you play yours on the board.

- **New move**: shown as an arrow ("New move: play Nf3"), with the PGN's
  comment. Play it to learn it; it is tested again later in the same session.
- **Review**: find the move. Right first time → it comes back in 1 day, then
  3, then longer and longer. Wrong move, *Hint* or *Solution* → it comes back
  in the same session and the interval starts over.
- A move you already know that isn't due is still played on the way; a wrong
  answer there counts as a failure too.
- *Next line* after a finished line; when nothing is due and today's new moves
  are learned, the session ends with a summary.

The panel and board work as in studies: move-mark badges, position
assessments in words, short links with a QR code (≡ → *Links…*).

Positions reached by different move orders share their review (one card per
position). If two lines of a file play different moves in the same position,
the first one wins and the other line stops there.

Reviews are stored in `koreader/settings/paperknight/progress.sqlite`, by file
name: renaming a repertoire file starts its history over.
