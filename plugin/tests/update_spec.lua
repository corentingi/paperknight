-- In-app updates (pkupdate.lua): reading the installer's answers. The
-- installer itself is tested by tools/dist/test-install.sh, the screens by
-- the settings e2e scenario.
local PkUpdate = require("pkupdate")

-- runs PkUpdate's scheduled polls (the real scheduler is KOReader's)
local function driven(fn)
    local queue = {}
    local schedule, dir = PkUpdate._schedule, PkUpdate.koreader_dir_override
    PkUpdate._schedule = function(_, poll) queue[#queue + 1] = poll end
    local tmp = os.tmpname()
    os.remove(tmp)
    os.execute("mkdir -p '" .. tmp .. "'")
    PkUpdate.koreader_dir_override = tmp
    local function step() -- one poll; true if one was waiting
        local poll = table.remove(queue, 1)
        if poll then poll() end
        return poll ~= nil
    end
    local ok, err = pcall(fn, step)
    PkUpdate._schedule, PkUpdate.koreader_dir_override = schedule, dir
    os.execute("rm -rf '" .. tmp .. "'")
    if not ok then error(err, 0) end
end

return {
    { "a background job: its output and status", function(t)
        driven(function(step)
            local result
            PkUpdate.run("echo first; echo last; exit 3", function(...) result = { ... } end, 60)
            for _ = 1, 100 do
                if result or not step() then break end
                os.execute("sleep 0.05")
            end
            t.ok(result, "done")
            t.eq(result[1], false, "exit 3: failed"); t.eq(result[2], "first\nlast\n"); t.eq(result[3], nil, "not timed out")
            t.ok(not PkUpdate.jobRunning(), "no job left")
        end)
    end },
    { "a job that never ends: given up after its time, not started twice", function(t)
        driven(function(step)
            local result
            PkUpdate.run("echo started; sleep 30", function(...) result = { ... } end, 2)
            local polls = 0
            while not result and step() do polls = polls + 1 end
            t.eq(polls, 5, "polled for 2 s (every 0.5 s)")
            t.eq(result[1], false); t.eq(result[3], true, "timed out")
            t.ok(PkUpdate.jobRunning(), "the job is left running (not killed mid-install)")
            local again
            PkUpdate.run("echo second", function(...) again = { ... } end, 60)
            t.ok(again and again[1] == false and again[2]:find("still running", 1, true), "not started twice")
            local pid = PkUpdate.readFirstLine(PkUpdate.workDir() .. "/pid")
            os.execute("kill " .. pid .. " 2>/dev/null; pkill -P " .. pid .. " 2>/dev/null; sleep 0.2")
            t.ok(not PkUpdate.jobRunning(), "ended: another job may start")
            -- a pid file left from before a restart, its pid now another process
            local f = io.open(PkUpdate.workDir() .. "/pid", "w"); f:write("1\n"); f:close()
            t.ok(not PkUpdate.jobRunning(), "a pid that is not our job")
        end)
    end },
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
    { "the release notes in an installer", function(t)
        local script = "VERSION='v2'\n# what changed\nNOTES='\nNew:\n• Puzzles: It’s new\n\nFixed:\n• A fix\n'\nDIST_URL='x'\n"
        t.eq(PkUpdate.parseNotes(script), "New:\n• Puzzles: It’s new\nFixed:\n• A fix")
        t.eq(PkUpdate.parseNotes(script, 3), "New:\n• Puzzles: It’s new\n…", "cut")
        t.eq(PkUpdate.parseNotes(script, 4), "New:\n• Puzzles: It’s new\nFixed:\n• A fix", "fits")
        t.eq(PkUpdate.parseNotes("VERSION='v1'\nNOTES='\n\n'\n"), nil, "a release without notes")
        t.eq(PkUpdate.parseNotes("VERSION='v1'\n"), nil, "an older installer")
    end },
    { "the koreader folder and shell quoting", function(t)
        t.eq(PkUpdate.koreaderDir("/mnt/us/koreader/plugins/paperknight.koplugin"), "/mnt/us/koreader")
        t.eq(PkUpdate.quote("it's here"), [['it'\''s here']])
        t.eq(PkUpdate.lastLine("a\nb\n\n"), "b"); t.eq(PkUpdate.lastLine(""), "")
    end },
}
