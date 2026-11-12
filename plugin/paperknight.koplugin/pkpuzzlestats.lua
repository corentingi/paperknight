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

--- The rating over time for a chart `width` columns wide: { first, last,
-- best, low, high, n, columns = { rating per column } } (each column the
-- rating after the attempts it stands for: the last of them), nil with
-- fewer than 2 ratings. `low` and `high` frame the curve with a margin, at
-- least 100 points apart (a flat start does not fill the chart).
function PkPuzzleStats.ratingSeries(ratings, width)
    local n = #ratings
    if n < 2 or width < 2 then return nil end
    local s = { first = ratings[1], last = ratings[n], best = ratings[1], n = n, columns = {} }
    local lo, hi = ratings[1], ratings[1]
    for _, r in ipairs(ratings) do
        if r > s.best then s.best = r end
        if r < lo then lo = r end
        if r > hi then hi = r end
    end
    local pad = math.max(10, math.floor((hi - lo) * 0.1))
    s.low, s.high = lo - pad, hi + pad
    if s.high - s.low < 100 then
        local mid = (s.high + s.low) / 2
        s.low, s.high = math.floor(mid - 50), math.ceil(mid + 50)
    end
    local cols = math.min(width, n)
    for c = 1, cols do
        -- column c stands for the attempts up to this one
        s.columns[c] = ratings[math.max(1, math.floor(c * n / cols + 0.5))]
    end
    return s
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
