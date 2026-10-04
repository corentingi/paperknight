# Pack format

Status: draft — finalised when the first pack is built (Milestone 2).

Every pack is a SQLite 3 file with a `meta` table:

| key | value |
|---|---|
| `format_version` | integer as text, e.g. `1` |
| `kind` | `puzzles` · `openings` · `games` |
| `built_at` | ISO 8601 UTC |
| `source` | human-readable provenance (URL + date) |
| `license` | e.g. `CC0-1.0` |

The plugin refuses a pack whose `format_version` it does not support.
Pack-specific tables are specified here as they are implemented.
