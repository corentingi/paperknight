# Contributing to Paperknight

Thanks for helping. Bug reports from real devices are the most useful
thing you can send: say which e-reader, its KOReader version and
Paperknight's (*Settings…* shows it), and what you did.

## Working on the code

The [development guide](docs/development.md) has the setup: a desktop
KOReader runs the plugin and its end-to-end scenarios headless, so no
Kindle is needed. `make help` lists the targets.

Four rules:

1. **`make check` passes before a commit**: the linters, the Lua specs, the
   pipeline's tests, the installer tests and the end-to-end scenarios. CI
   runs the same on every push and pull request.
2. **A new test must fail without its fix.** Revert the fix once, run the
   test, see it fail, put the fix back (a mutation check).
3. **Commit messages follow [Conventional Commits](https://www.conventionalcommits.org)**:
   `type(scope): summary` (`feat`, `fix`, `perf`, `refactor`, `docs`,
   `test`, `build`, `ci`, `chore`; the scope is the area: `puzzles`,
   `studies`, `openings`, `play`, `games`, `board`, `dist`…). The `feat`,
   `fix` and `perf` subjects are the release notes users read, in the app
   too: write them for users.
4. **Decisions that are costly to reverse get an ADR** in
   [`docs/adr/`](docs/adr/) (template `0000-template.md`), and behaviour
   changes update `docs/`.

Chess data in tests and fixtures is checked with python-chess first
(legality, castling rights, SAN). Don't commit Lichess study text: its
licence is unclear; write your own fixtures.

## Translations

Paperknight speaks English and French. A new language is one `.po` file:
see [docs/translations.md](docs/translations.md).

## Licence

Paperknight is GPL-3.0-or-later ([LICENSE](LICENSE)); contributions are
under the same licence. Credits for the code and data it builds on:
[docs/credits.md](docs/credits.md).
