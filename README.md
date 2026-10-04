# Paperknight

Offline chess training for e-ink readers, built as a [KOReader](https://koreader.rocks)
plugin. Primary target: a jailbroken **Kindle Paperwhite 2**.

Paperknight is a fork of [Kochess](https://github.com/bateast/kochess) (play against
Stockfish, PGN load/save) that grows into a training tool:

- **Puzzles** — rated, themed tactics from the Lichess puzzle database, fully offline.
- **Openings** — named repertoire lines to drill with spaced repetition.
- **Master games** — curated notable games, replayed in "guess the move" mode.

> Status: early development. See [`docs/roadmap.md`](docs/roadmap.md).

## Repository layout

| Path | What lives there |
|---|---|
| [`plugin/paperknight.koplugin/`](plugin/) | The KOReader plugin (Lua). This folder is what you copy to the device. |
| [`pipeline/`](pipeline/) | Python scripts that download public datasets and build compact data packs for the plugin. |
| [`tools/emulator/`](tools/emulator/) | Runs KOReader on a desktop (in Docker) to test the plugin without a Kindle. |
| [`docs/`](docs/) | Architecture, data sources, development guide, and [decision records](docs/adr/). |

## Quick start (development)

```sh
make help          # list targets
make test          # unit tests (plugin + pipeline)
make packs         # build data packs into build/packs/
make emulator      # run the plugin in a desktop KOReader (see docs/development.md)
```

## Installing on a Kindle

1. Install KOReader on the jailbroken Kindle (for a Paperwhite 2, use the
   `koreader-kindlepw2-*.zip` release).
2. Copy `plugin/paperknight.koplugin/` to `/mnt/us/koreader/plugins/`.
3. Copy the data packs from `build/packs/` to `/mnt/us/koreader/plugins/paperknight.koplugin/packs/`.
4. Restart KOReader; Paperknight appears in the **Tools** menu.

## License

GPL-3.0-or-later, inherited from Kochess. See [`LICENSE`](LICENSE) and
[`docs/credits.md`](docs/credits.md) for upstream authors and data licenses.
