-- Per-theme puzzle stats (pkpuzzlestats.lua).
package.loaded["gettext"] = package.loaded["gettext"] or function(s) return s end
local PkPuzzleStats = require("pkpuzzlestats")

local TAGS = {
    a = "fork middlegame crushing",
    b = "fork pin",
    c = "pin endgame",
}
local function themesOf(id) return TAGS[id] end
local function attempt(id, clean, rating) return { puzzle_id = id, clean = clean, puzzle_rating = rating } end

local function byTheme(stats)
    local out = {}
    for _, g in ipairs(stats.themes) do out[g.theme] = g end
    return out
end

return {
    { "groups attempts by skill theme, total over all", function(t)
        local stats = PkPuzzleStats.compute({
            attempt("a", true, 1000), attempt("b", false, 1200), attempt("gone", true, 1400),
        }, themesOf)
        t.eq(stats.total.n, 3, "total counts puzzles missing from the pack")
        t.eq(stats.total.clean, 2, "total clean")
        local g = byTheme(stats)
        t.eq(g.fork.n, 2, "fork attempts"); t.eq(g.fork.clean, 1, "fork clean")
        t.eq(g.pin.n, 1, "pin"); t.eq(g.middlegame.n, 1, "middlegame")
        t.ok(g.crushing == nil, "evaluation tag left out")
        t.ok(g.fork.perf == nil, "no performance under MIN_ATTEMPTS")
        -- total: average 1200, 2 of 3 clean -> 1200 + 400 * 1/3
        t.eq(stats.total.perf, 1333, "total performance")
    end },
    { "performance: average rating +-400 by score; weakest first", function(t)
        local list = {}
        for _ = 1, 5 do list[#list + 1] = attempt("b", true, 1500) end  -- fork, pin: 5/5
        for _ = 1, 5 do list[#list + 1] = attempt("c", false, 1500) end -- pin, endgame: 0/5
        list[#list + 1] = attempt("a", false, 1500)                      -- fork 6, middlegame 1
        local stats = PkPuzzleStats.compute(list, themesOf)
        local g = byTheme(stats)
        t.eq(g.fork.perf, 1767, "fork: 5 of 6 clean -> 1500 + 400 * 4/6")
        t.eq(g.endgame.perf, 1100, "endgame: none clean -> -400")
        t.eq(g.pin.perf, 1500, "pin: half clean -> the average")
        local order = {}
        for i, th in ipairs(stats.themes) do order[i] = th.theme end
        t.eq(table.concat(order, " "), "endgame pin fork middlegame", "weakest first, then few attempts")
    end },
    { "no attempts", function(t)
        local stats = PkPuzzleStats.compute({}, themesOf)
        t.eq(stats.total.n, 0, "empty"); t.ok(stats.total.perf == nil, "no performance"); t.eq(#stats.themes, 0, "no themes")
    end },
}
