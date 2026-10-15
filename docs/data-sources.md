# Data sources

Researched 2026-10-04. Game moves are facts and generally not copyrightable;
written annotations are. We ship moves, tags we compute, and CC0/CC-BY-SA text
with attribution only.

## Puzzles

| Source | Content | License | Use |
|---|---|---|---|
| [Lichess puzzle DB](https://database.lichess.org/#puzzles) | 6.16M puzzles, CSV (`PuzzleId, FEN, Moves, Rating, RatingDeviation, Popularity, NbPlays, Themes, GameUrl, OpeningTags, DailyDate`; the pipeline ignores the last), ~300 MB `.zst`, monthly | CC0 | Main source. Filter by popularity/plays, stratify by rating × theme |
| [lichess-puzzler](https://github.com/ornicar/lichess-puzzler) | Generator (Stockfish) + theme tagger, Python | AGPL-3.0 (tool only; its output is ours) | Later: puzzles from master games |
| [Theme list](https://github.com/lichess-org/lila/blob/master/translation/source/puzzleTheme.xml) | Theme keys, names, descriptions | AGPL (lila) — reuse keys, write our own short labels | Theme menu |

CSV semantics: `FEN` is the position *before* the opponent's move; apply the
first UCI move of `Moves`, then the solver must find every other move (each is
an "only move").

## Openings

| Source | Content | License | Use |
|---|---|---|---|
| [lichess-org/chess-openings](https://github.com/lichess-org/chess-openings) | 3,864 named lines (`eco, name, pgn, uci, epd`) in `a–e.tsv` | CC0 | Names, ECO codes, position lookup |
| [Lichess opening explorer](https://github.com/lichess-org/lila-openingexplorer) (masters) | Move frequencies/scores from master games | API, personal token required since 2026 | Pipeline-side only, to pick repertoire replies |
| [Wikibooks Chess Opening Theory](https://en.wikibooks.org/wiki/Chess_Opening_Theory) | Prose on each line's ideas | CC BY-SA 4.0 (attribution + share-alike) | Optional explanations, kept in a separately licensed table |

## Master games

| Source | Content | License / terms | Use |
|---|---|---|---|
| [Wikipedia: List of chess games](https://en.wikipedia.org/wiki/List_of_chess_games) | ~80–90 notable games 1475–2023, nickname + significance | CC BY-SA (text) | Curation seed list; we write our own one-liners |
| [PGN Mentor](https://www.pgnmentor.com/files.html) | Per-player, per-opening, per-event PGNs | Free download | Classic players' games |
| [TWIC](https://theweekinchess.com) | Weekly top-level games since 1994 | Free download | Modern games |
| [Lumbra's Gigabase](https://lumbrasgigabase.com) | 13M+ games aggregated (TWIC, PGN Mentor, …) | Free download; mixed provenance | Offline lookup to find a game's moves |
| Lichess broadcasts export | OTB events relayed on Lichess | CC0 (to confirm) | Recent games |
| chessgames.com | Famous-game lists | ToS forbids scraping | Reading list only |

## Engine

Stockfish (GPL-3.0). The Kochess fork shipped a static ARMv7 soft-float build
(`arm-linux-musleabi`, no embedded NNUE, 55 MB unstripped). How we provide the
binary is an open decision (see roadmap).
