-- In-app updates (pkupdate.lua): reading the installer's answers. The
-- installer itself is tested by tools/dist/test-install.sh, the screens by
-- the settings e2e scenario.
local PkUpdate = require("pkupdate")

return {
    { "the installer's --list output", function(t)
        local parts = PkUpdate.parseList("plugin|v0.1.0|v0.2.0|120000\npuzzles|2026-01-01|2026-01-01|9000000\n"
            .. "fonts||abcd1234|500000\nnoise line\nstockfish||sf_18|1500000\n")
        t.eq(#parts, 4, "parts")
        t.eq(parts[1].part, "plugin"); t.eq(parts[1].have, "v0.1.0"); t.eq(parts[1].version, "v0.2.0")
        t.eq(parts[1].size, 120000, "size as a number")
        t.eq(parts[3].have, nil, "not installed")
        local changes, stockfish = PkUpdate.plan(parts)
        t.eq(PkUpdate.names(changes), "plugin,fonts", "changed and missing parts, the pack up to date")
        t.eq(stockfish and stockfish.version, "sf_18", "Stockfish not installed: offered apart")
    end },
    { "an installed Stockfish is updated with the rest", function(t)
        local changes, stockfish = PkUpdate.plan(PkUpdate.parseList("plugin|v1|v1|1\nstockfish|sf_17|sf_18|2\n"))
        t.eq(PkUpdate.names(changes), "stockfish"); t.eq(stockfish, nil)
        changes, stockfish = PkUpdate.plan(PkUpdate.parseList("plugin|v1|v1|1\nstockfish|sf_18|sf_18|2\n"))
        t.eq(#changes, 0, "up to date"); t.eq(stockfish, nil)
    end },
    { "descriptions and sizes", function(t)
        t.eq(PkUpdate.describe({ part = "plugin", have = "v1", version = "v2", size = 2048 }), "Paperknight: v1 → v2 (2 KB)")
        t.eq(PkUpdate.describe({ part = "puzzles", have = "?", version = "2026-01-01", size = 9 * 1048576 }),
            "Puzzle pack: unknown → 2026-01-01 (9 MB)")
        t.eq(PkUpdate.describe({ part = "fonts", version = "ab", size = 1 }), "Emoji font: install ab (1 KB)")
    end },
    { "the release version in an installer", function(t)
        t.eq(PkUpdate.parseVersion("#!/bin/sh\nPARTS='\nplugin|v2|f|s|1\n'\nVERSION='v0.2.0'\nDIST_URL='x'\n"), "v0.2.0")
        t.eq(PkUpdate.parseVersion("<html>Not found</html>"), nil)
    end },
    { "the koreader folder and shell quoting", function(t)
        t.eq(PkUpdate.koreaderDir("/mnt/us/koreader/plugins/paperknight.koplugin"), "/mnt/us/koreader")
        t.eq(PkUpdate.quote("it's here"), [['it'\''s here']])
        t.eq(PkUpdate.lastLine("a\nb\n\n"), "b"); t.eq(PkUpdate.lastLine(""), "")
    end },
}
