# Releasing

GitHub Actions builds and publishes everything (`.github/workflows/`):

| Workflow | When | What |
|---|---|---|
| `ci.yml` | every push to `main` and pull request | `make check` (Lua specs, pytest, installer tests under busybox, headless e2e) |
| `release.yml` | a tag `vX.Y.Z` | tests, builds the puzzle pack from the Lichess database, then the release files below, published as the release marked latest |
| `stockfish.yml` | a tag `stockfish-<sf tag>` (e.g. `stockfish-sf_18`) | Stockfish for each platform (`pw2` so far), checked under qemu, published as a release of its own (not latest) |
| `pages.yml` | a push to `main` touching `site/` or the screenshots | the web page (`site/` + `docs/screenshots/`) on GitHub Pages |

Run by hand (*Actions → workflow → Run workflow*), `release.yml` and
`stockfish.yml` build the same files as an artifact without publishing: a
dry run.

## What a plugin release holds

`tools/dist/build-dist.sh` (`make dist` locally) builds, in `build/dist/out`:

| File | Contents |
|---|---|
| `install.sh` | The installer, the only file with a fixed name: it lists the parts below with their versions and checksums |
| `paperknight-plugin-<version>.tar.gz` | The plugin code (`plugins/paperknight.koplugin`, without `packs/` and `bin/`) |
| `paperknight-puzzles-<date>.tar.gz` | The puzzle pack; `<date>`: the day its Lichess database was downloaded |
| `paperknight-emoji-font-<hash>.tar.gz` | Noto Emoji and its licence (`fonts/`) |
| `paperknight-studies-<hash>.tar.gz` | Studies and repertoires: local builds only, never in a release |
| `paperknight-<version>-usb.zip` | Everything as a `koreader/` folder to copy over USB, Stockfish included |
| `SHA256SUMS` | Checksums of the files |

Every archive holds paths relative to the `koreader` folder. A part's file
is named after its version, so an unchanged part keeps its name, and the
installer skips it.

## The installer

    curl -fkL https://github.com/corentingi/paperknight/releases/latest/download/install.sh | sh

(`latest/download` redirects to the latest release's asset; the installer
downloads the parts from its own release.) It shows what is installed and
what it would change, then:

- installs or updates the plugin, the font and studies without asking;
- installs the puzzle pack if missing, and asks before updating it (10 MB);
- offers Stockfish, from the Stockfish release named in `release.yml`
  (`STOCKFISH_RELEASE`), when there is a build for the device (`uname -m`;
  `SF_PLATFORM` overrides);
- asks *Go?*, downloads and checks every part first (sha256, gzip, tar),
  then installs them; the plugin folder is swapped with renames, keeping
  `packs/` and `bin/`.

What it installed is recorded in `koreader/paperknight/.parts/<part>` (the
version, then the files): an update removes the previous version's files
(studies you added yourself stay). An install made by the older `pka.sh`
(`paperknight/.pka-files`) is updated the same way.

Options: `--yes` (the default answers; also when there is no terminal, as
for a future in-app updater), `--dry-run` (the plan only):
`curl -fkL …/install.sh | sh -s -- --yes`. Questions are read from
`/dev/tty`, since the script itself is on stdin.

`tools/dist/test-install.sh` (`make test-dist`, in `make check`) tests it
under busybox against releases built from a fake stage, served as
`file://` URLs: a fresh install, updates, a study of your own kept, a
corrupted download, a dry run, an install made by `pka.sh`, the USB zip.

## A plugin release

Publish the Stockfish release first (the plugin release downloads its
binaries to describe them in `install.sh` and to put one in the USB zip),
then:

    git tag v0.1.0 && git push origin v0.1.0

The plugin gets `version.txt` with the tag. The release ships no study or
repertoire: Lichess study text has no clear licence
(`tools/dist/stage-release.sh` stages empty folders). A local `make dist`
bundles whatever you staged in `build/dist/all`.

## A Stockfish release

    git tag stockfish-sf_18 && git push origin stockfish-sf_18

Assets: `stockfish-<platform>.gz`, the Stockfish source tarball and our
patch (GPL), `SHA256SUMS`. A new platform is a `case` entry in
`tools/dist/build-stockfish.sh` (architecture, Zig target, CPU), a matrix
entry in `stockfish.yml` (its qemu command) and its `uname -m` in
`install.sh`'s `platform()`. For a new Stockfish version, update
`STOCKFISH_RELEASE` in `release.yml`: the next plugin release offers it.

## Your own server

`make dist` with `PAPERKNIGHT_DIST_URL` (environment or `local.mk`) builds
the same files from your stage (`build/dist/all`, your studies included)
and copies `build/dist/stockfish/stockfish-*.gz` (built by
`build-stockfish.sh`) and its source next to them. Upload the whole of
`build/dist/out`, then on the Kindle `curl -fkL <server>/install.sh | sh`.

## To check on the device

The installer runs `curl` on the Kindle against GitHub, which redirects
release assets to another host (`objects.githubusercontent.com`): the
Kindle's `curl` must follow it (`-L`) and speak its TLS (`-k` skips the
certificate check, not the protocol).
