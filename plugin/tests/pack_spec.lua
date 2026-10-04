-- Puzzle pack reader and progress store, against the fixture pack built by
-- `make fixture-packs`. Needs KOReader's environment (lua-ljsqlite3).
if not PK_KOREADER_ENV then
    return { { "SKIPPED: run via `make test-lua` (needs KOReader env)", function(t) t.ok(false, "no KOReader env") end } }
end
local PkPuzzlePack = require("pkpuzzlepack")
local PkProgress = require("pkprogress")

local FIXTURE = PK_REPO_ROOT .. "/build/packs/fixture/puzzles.sqlite"

local function seq(...) -- deterministic "random" generator
    local values, i = { ... }, 0
    return function() i = i % #values + 1; return values[i] end
end

local function tmpdb()
    local path = os.tmpname()
    os.remove(path)
    return path .. ".sqlite"
end

return {
    { "opens the fixture pack and reads a puzzle by id", function(t)
        local pack = assert(PkPuzzlePack.open(FIXTURE))
        t.eq(pack:count(), 63, "count")
        local p = pack:get("004JD")
        t.eq(p.solver, "b", "solver"); t.eq(p.moves, "d2e3 a3c2", "moves")
        t.eq(type(p.rating), "number", "rating converted from int64"); t.eq(p.rating, 1291, "rating")
        pack:close()
    end },
    { "rejects missing files and non-pack databases", function(t)
        local pack, err = PkPuzzlePack.open("/nonexistent/puzzles.sqlite")
        t.eq(pack, nil, "missing"); t.ok(err:find("not found"), err)
        local progress_path = tmpdb()
        PkProgress.open(progress_path):close()
        pack, err = PkPuzzlePack.open(progress_path)
        t.eq(pack, nil, "wrong kind"); t.ok(err:find("not a puzzles pack"), err)
        os.remove(progress_path)
    end },
    { "pickNear prefers the home band and honours accept()", function(t)
        local pack = assert(PkPuzzlePack.open(FIXTURE))
        for _, r in ipairs({ 0.0, 0.3, 0.7, 0.999 }) do
            local p = pack:pickNear(1250, { random = seq(r) })
            t.ok(p and p.rating >= 1200 and p.rating < 1300, "home band, got " .. tostring(p and p.rating))
        end
        local p = pack:pickNear(1250, { random = seq(0.5), accept = function(c) return c.rating >= 1400 end })
        t.ok(p.rating >= 1400 and p.rating < 1500, "accept moves to a neighbouring band, got " .. p.rating)
        p = pack:pickNear(1250, { random = seq(0.5), accept = function(c) return c.rating >= 1600 end })
        t.ok(p.rating >= 1000 and p.rating < 1500, "a near rejected puzzle beats a far accepted one, got " .. p.rating)
        local any = pack:pickNear(1250, { random = seq(0.5), accept = function() return false end })
        t.ok(any ~= nil, "falls back to ignoring accept")
        pack:close()
    end },
    { "rating update follows ADR-0010", function(t)
        local up = PkProgress.updatedRating
        t.eq(up(1200, 1200, true, 0), 1230, "provisional win vs equal")
        t.eq(up(1200, 1200, false, 0), 1170, "provisional loss vs equal")
        t.eq(up(1200, 1200, true, 50), 1215, "established K=30")
        t.eq(up(410, 410, false, 0), 400, "clamped at 400")
        t.eq(up(2990, 2990, true, 0), 3000, "clamped at 3000")
    end },
    { "progress records attempts and persists the rating", function(t)
        local path = tmpdb()
        local prog = PkProgress.open(path)
        t.eq(prog:rating(), 1200, "start rating")
        local before, after = prog:record{ puzzle_id = "004JD", puzzle_rating = 1291, success = true,
                                           solved = true, mistakes = 0, used_help = false, ts = 1000 }
        t.eq(before, 1200, "before"); t.ok(after > 1200, "rating went up")
        t.ok(prog:wasAttemptedSince("004JD", 900), "recent attempt found")
        t.ok(not prog:wasAttemptedSince("004JD", 1001), "older attempt ignored")
        prog:close()
        local reopened = PkProgress.open(path)
        t.eq(reopened:rating(), after, "rating persisted")
        t.eq(reopened:attemptCount(), 1, "attempt persisted")
        reopened:close()
        os.remove(path)
    end },
}
