# Plugin space

`paperknight.koplugin/` is the KOReader plugin, the exact folder that goes to
`/mnt/us/koreader/plugins/` on a Kindle.

- Language: Lua (LuaJIT 2.1), KOReader plugin API.
- Origin: fork of Kochess, see [ADR-0003](../docs/adr/0003-fork-kochess-by-copy.md).
- Tests: `plugin/tests/` (plain Lua, run with KOReader's LuaJIT via `make test-lua`).
- Data: reads packs from `paperknight.koplugin/packs/` (format: [`docs/pack-format.md`](../docs/pack-format.md)).
