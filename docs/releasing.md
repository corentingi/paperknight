# Releasing

GitHub Actions builds and publishes everything (`.github/workflows/`):

| Workflow | When | What |
|---|---|---|
| `ci.yml` | every push to `main` and pull request | `make check` (Lua specs, pytest, headless e2e) |
| `release.yml` | a tag `vX.Y.Z` | tests, builds the puzzle pack from the Lichess database, then `pka.tar.gz` (plugin, puzzle pack, Noto Emoji font), `pkc.tar.gz` (code only), their installers and `SHA256SUMS`, published as the release marked latest |
| `stockfish.yml` | a tag `stockfish-<sf tag>` (e.g. `stockfish-sf_18`) | Stockfish for each platform (`pw2` so far), checked under qemu, published as a release of its own (not latest) |
| `pages.yml` | a push to `main` touching `site/` or the screenshots | the web page (`site/` + `docs/screenshots/`) on GitHub Pages; skipped while the repository is private (GitHub Pages needs a public repository on a free plan) |

Run by hand (*Actions → workflow → Run workflow*), `release.yml` and
`stockfish.yml` build the same files as an artifact without publishing: a
dry run.

## A plugin release

    git tag v0.1.0 && git push origin v0.1.0

The installers download from the release they belong to
(`PAPERKNIGHT_DIST_URL` = `…/releases/download/<tag>`), and the plugin gets
`version.txt` with the tag. Users install or update with

    curl -fkL https://github.com/corentingi/paperknight/releases/latest/download/pka.sh | sh

(`latest/download` redirects to the latest release's asset; `pkc.sh` the
same way for a code-only update).

The release ships no study or repertoire: Lichess study text has no clear
licence (`tools/dist/stage-release.sh` stages empty folders). Your local
`make pka` still bundles whatever you staged in `build/dist/all`.

## A Stockfish release

    git tag stockfish-sf_18 && git push origin stockfish-sf_18

Assets: `stockfish-<platform>.gz` and its installer `stockfish-<platform>.sh`,
the Stockfish source tarball and our patch (GPL). A new platform is a
`case` entry in `tools/dist/build-stockfish.sh` (architecture, Zig target,
CPU) and a matrix entry in `stockfish.yml` (its qemu command).

Install on a Paperwhite 2:

    curl -fkL https://github.com/corentingi/paperknight/releases/download/stockfish-sf_18/stockfish-pw2.sh | sh

## To check on the device

The installers run `curl` on the Kindle against GitHub, which redirects
release assets to another host (`objects.githubusercontent.com`): the
Kindle's `curl` must follow it (`-L`) and speak its TLS (`-k` skips the
certificate check, not the protocol).
