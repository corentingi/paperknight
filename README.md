# Paperknight

Offline chess training for e-ink readers, built as a [KOReader](https://koreader.rocks)
plugin. Primary target: a jailbroken **Kindle Paperwhite 2**.

Paperknight is a fork of [Kochess](https://github.com/bateast/kochess) (play against
Stockfish, PGN load/save) that grows into a training tool:

- **Puzzles** — rated, themed tactics from the Lichess puzzle database, fully offline;
  missed puzzles come back as spaced reviews (after 3, 7, then 21 days; then they stop).
  *Solution* shows the first move you missed; then step through the whole line with ‹ › (or swipes).
  A solved puzzle gets a ✓ badge on the last piece moved; the last move is the darkest square.
  Once a puzzle is over, its themes are shown; *Stats…* (☰) charts your results per theme (clean
  solves vs misses), weakest first, and a tap on a theme trains it.
- **Studies** — Lichess studies (or any PGN): chapters, variations, comments,
  arrows, and interactive lessons. See [`docs/studies.md`](docs/studies.md).
- **Openings** — drill your own repertoire (a PGN / Lichess study) with spaced
  repetition. See [`docs/openings.md`](docs/openings.md).
- **Analysis board** — move freely for both sides, step through the line, set a
  position from FEN; with Stockfish installed, its evaluation and best line
  (the knight button turns it on and off, remembered; the move list too).
  Studies, the openings drill and the analysis board name the opening
  ("C50 Italian Game", from Lichess's CC0 list).
  Also opens the current puzzle or study position (☰ → *Analyse position*).
- **Play** — against Stockfish, or two players on one board without it.
- **Master games** — curated notable games, replayed in "guess the move" mode.

> Status: early development — puzzles, studies and the openings trainer work
> in the desktop emulator; puzzles and studies are tested on a Paperwhite 2. See [`docs/roadmap.md`](docs/roadmap.md).

## Repository layout

| Path | What lives there |
|---|---|
| [`plugin/paperknight.koplugin/`](plugin/) | The KOReader plugin (Lua). This folder is what you copy to the device. |
| [`pipeline/`](pipeline/) | Python scripts that download public datasets and build compact data packs for the plugin. |
| [`tools/emulator/`](tools/emulator/) | Runs the desktop KOReader (headless or windowed) to test the plugin without a Kindle. |
| [`tools/dist/`](tools/dist/) | Builds the device archive and its installer script (`make pka`). |
| [`docs/`](docs/) | Architecture, data sources, development guide, and [decision records](docs/adr/). |

## Quick start (development)

```sh
make help          # list targets
make test          # unit tests (plugin + pipeline)
make packs         # download Lichess puzzles (~300 MB, once; an interrupted download resumes) and build build/packs/puzzles.sqlite
make study ID=<lichess study id or URL>   # download a study into build/studies/
make check         # unit tests + headless end-to-end scenarios (screenshots in build/e2e/)
make emulator      # run the plugin in a desktop KOReader window (see docs/development.md)
make pka           # device archive + installer in build/dist/ (pka.tar.gz, pka.sh)
make pkc           # code-only archive + installer (pkc.tar.gz, pkc.sh): keeps the assets on the device
```

## Installing on a Kindle

1. Install KOReader on the jailbroken Kindle (for a Paperwhite 2, use the
   `koreader-kindlepw2-*.zip` release).
2. Copy `plugin/paperknight.koplugin/` to `/mnt/us/koreader/plugins/`.
3. Copy the data packs from `build/packs/` to `/mnt/us/koreader/plugins/paperknight.koplugin/packs/`,
   study PGNs to `/mnt/us/koreader/paperknight/studies/`, and repertoire PGNs
   to `/mnt/us/koreader/paperknight/repertoires/`.
   Or, with everything staged in `build/dist/all`, `make pka` builds one
   archive (`build/dist/pka.tar.gz`) and its installer (`build/dist/pka.sh`,
   see [`tools/dist/pka.sh`](tools/dist/pka.sh)). Once both are on a web
   server, install or update from kterm with
   `curl -fkL <server>/pka.sh | sh`: it downloads the archive, removes the
   files the previous one installed (your own studies are kept) and extracts it.
4. Restart KOReader; **Paperknight** appears in the **Tools** menu, with
   *Home*, *Puzzles*, *Studies*, *Openings*, *Analysis board* and *Play*. For Stockfish
   (play against it, evaluation on the analysis board), run
   `curl -fkL <server>/stockfish.sh | sh` on the Kindle
   (see [`docs/stockfish.md`](docs/stockfish.md)).
   The home screen lists the modes and the screen settings; in any screen, a
   tap on the title opens the quick settings (frontlight, night mode, switch
   mode, home). ☰ has the actions of the screen shown, and *Settings &
   modes…* leads to the quick settings too. Tip: assign the *Paperknight* gesture action in
   KOReader to open the home screen in one tap.

## License

GPL-3.0-or-later, inherited from Kochess. See [`LICENSE`](LICENSE) and
[`docs/credits.md`](docs/credits.md) for upstream authors and data licenses.
