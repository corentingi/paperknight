-- Puzzle performance per theme, from the attempt history (progress.sqlite)
-- and the pack's theme tags. Pure: the view passes the data in.
local PkThemes = require("pkthemes")

local PkPuzzleStats = {
    MIN_ATTEMPTS = 5, -- fewer attempts: shown, but without a performance
}

-- Performance rating ("algorithm of 400"): the average puzzle rating, plus
-- 400 per clean solve above half, per attempt. All clean: +400; none: -400.
local function performance(group)
    return math.floor(group.rating_sum / group.n + 400 * (2 * group.clean - group.n) / group.n + 0.5)
end

local function newGroup(theme) return { theme = theme, n = 0, clean = 0, rating_sum = 0 } end

local function add(group, attempt)
    group.n = group.n + 1
    if attempt.clean then group.clean = group.clean + 1 end
    group.rating_sum = group.rating_sum + attempt.puzzle_rating
end

--- Groups `attempts` ({ {puzzle_id, clean, puzzle_rating} }, PkProgress:attempts)
-- by theme. `themesOf(puzzle_id)` returns the puzzle's tags ("fork pin ..."),
-- nil when the pack no longer has it (counted in the total only).
-- @return { total = group, themes = { group, ... } }, a group being
--   { theme, n, clean, perf } (perf nil under MIN_ATTEMPTS). Themes with a
--   performance come first, weakest first; then the others, most played first.
function PkPuzzleStats.compute(attempts, themesOf)
    local total, by_theme, list = newGroup(nil), {}, {}
    for _, a in ipairs(attempts) do
        add(total, a)
        for key in (themesOf(a.puzzle_id) or ""):gmatch("%S+") do
            if PkThemes.isSkill(key) then
                local g = by_theme[key]
                if not g then
                    g = newGroup(key)
                    by_theme[key] = g
                    list[#list + 1] = g
                end
                add(g, a)
            end
        end
    end
    if total.n > 0 then total.perf = performance(total) end
    for _, g in ipairs(list) do
        if g.n >= PkPuzzleStats.MIN_ATTEMPTS then g.perf = performance(g) end
    end
    table.sort(list, function(a, b)
        if (a.perf ~= nil) ~= (b.perf ~= nil) then return a.perf ~= nil end
        if a.perf and a.perf ~= b.perf then return a.perf < b.perf end
        if a.n ~= b.n then return a.n > b.n end
        return a.theme < b.theme
    end)
    return { total = total, themes = list }
end

return PkPuzzleStats
