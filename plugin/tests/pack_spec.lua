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
    { "pickNear prefers the home band, fresh puzzles, and honours accept()", function(t)
        local pack = assert(PkPuzzlePack.open(FIXTURE))
        for _, r in ipairs({ 0.0, 0.3, 0.7, 0.999 }) do
            local p, fresh = pack:pickNear(1250, { random = seq(r) })
            t.ok(p and p.rating >= 1200 and p.rating < 1300, "home band, got " .. tostring(p and p.rating))
            t.eq(fresh, true, "no fresh filter: fresh")
        end
        -- within ±50 of the rating, across a band boundary (1250..1350)
        local seen = {}
        for _, r in ipairs({ 0.0, 0.2, 0.4, 0.6, 0.8, 0.999 }) do
            local w = pack:pickNear(1300, { random = seq(r) })
            t.ok(w.rating >= 1250 and w.rating <= 1350, "±50 window, got " .. w.rating)
            seen[math.floor(w.rating / 100)] = true
        end
        t.ok(seen[12] and seen[13], "from both bands of the window")
        local w = pack:pickNear(1300, { random = seq(0.5), fresh = function(c) return c.rating == 1354 end })
        t.eq(w.rating, 1354, "fresh within ±100 next")
        local p, fresh = pack:pickNear(1250, { random = seq(0.5), fresh = function(c) return c.rating >= 1400 end })
        t.ok(p.rating >= 1400 and p.rating < 1500, "a fresh neighbouring band first, got " .. p.rating)
        t.eq(fresh, true, "fresh")
        p, fresh = pack:pickNear(1250, { random = seq(0.5), fresh = function(c) return c.rating >= 1600 end })
        t.ok(p.rating >= 1600, "a far fresh puzzle beats a near stale one, got " .. p.rating)
        t.eq(fresh, true, "fresh")
        p, fresh = pack:pickNear(1250, { random = seq(0.5), fresh = function() return false end })
        t.ok(p and p.rating >= 1200 and p.rating < 1300, "all stale: the home band again")
        t.eq(fresh, false, "reported stale")
        p = pack:pickNear(1250, { random = seq(0.5), accept = function(c) return c.rating >= 1600 end,
                                  fresh = function() return false end })
        t.ok(p.rating >= 1600, "accept is never dropped, got " .. p.rating)
        t.eq(pack:pickNear(1250, { random = seq(0.5), accept = function() return false end }), nil,
             "nothing accepted: nil")
        pack:close()
    end },
    { "Glicko-2 matches Glickman's worked example", function(t)
        local PkGlicko = require("pkglicko")
        local p = PkGlicko.rate({ rating = 1500, rd = 200, vol = 0.06 }, {
            { rating = 1400, rd = 30, score = 1 },
            { rating = 1550, rd = 100, score = 0 },
            { rating = 1700, rd = 300, score = 0 },
        })
        t.ok(math.abs(p.rating - 1464.06) < 0.05, "rating " .. p.rating)
        t.ok(math.abs(p.rd - 151.52) < 0.05, "rd " .. p.rd)
        t.ok(math.abs(p.vol - 0.05999) < 0.00001, "vol " .. p.vol)
        t.ok(math.abs(PkGlicko.idleRd({ rd = 50, vol = 0.06 }, 30) - 76) < 1, "idle: the deviation grows")
    end },
    { "rating update (ADR-0010): settled ratings move less, breaks loosen them", function(t)
        local up = PkProgress.updatedState
        local new = { rating = 1200, rd = 350, vol = 0.06 }
        local settled = { rating = 1200, rd = 45, vol = 0.06, ts = 0 }
        local gain_new = up(new, 1200, 75, true, 0).rating - 1200
        local gain = up(settled, 1200, 75, true, 0).rating - 1200
        t.ok(gain_new > 100, "a new player moves fast: " .. gain_new)
        t.ok(gain > 3 and gain < 8, "a settled player moves a little: " .. gain)
        t.ok(up(settled, 1200, 75, false, 0).rating < 1200, "a miss lowers it")
        local after_break = up(settled, 1200, 75, true, 60 * 86400).rating - 1200
        t.ok(after_break > 2 * gain, "after two months it moves more: " .. after_break)
        t.ok(up(settled, 1600, 75, true, 0).rating - 1200 > gain, "a harder puzzle gives more")
        t.eq(up({ rating = 410, rd = 350, vol = 0.06 }, 410, 75, false, 0).rating, 400, "clamped at 400")
    end },
    { "progress: the Elo history is replayed into Glicko once", function(t)
        local path = tmpdb()
        local prog = PkProgress.open(path)
        for i = 1, 5 do
            prog:record{ puzzle_id = "P" .. i, puzzle_rating = 1500, success = true, solved = true,
                         mistakes = 0, used_help = false, ts = i * 1000 }
        end
        local rating = prog:rating()
        prog.conn:exec("DELETE FROM kv WHERE key LIKE 'rating%'")
        prog.conn:exec("INSERT INTO kv (key, value) VALUES ('rating', '1350')") -- the old Elo rating
        prog:close()
        prog = PkProgress.open(path)
        t.eq(prog:rating(), rating, "same rating as live updates")
        local state = prog:ratingState()
        t.ok(state.rd < 350 and state.ts == 5000, "deviation and last attempt restored")
        prog:close()
        os.remove(path)
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
    { "pickNear pages through a band: fresh puzzles are found wherever their key is", function(t)
        local pack = assert(PkPuzzlePack.open(FIXTURE))
        pack.batch = 1 -- every query returns one row: the scan must page on
        -- the fullest band, from a key before all of its puzzles: only the last
        -- one in key order is acceptable
        local band, n = pack.conn:rowexec("SELECT band, count(*) FROM puzzles GROUP BY band ORDER BY 2 DESC LIMIT 1")
        band, n = tonumber(band), tonumber(n)
        t.ok(n >= 3, "a band with several puzzles: " .. n)
        local last_id = pack.conn:rowexec("SELECT id FROM puzzles WHERE band = " .. band .. " ORDER BY rnd DESC LIMIT 1")
        local found = pack:_pickInBand(band, 0, function(p) return p.id == last_id end)
        t.eq(found and found.id, last_id, "found after paging")
        local wrapped = pack:_pickInBand(band, 0x7FFFFFFF, function(p) return p.id == last_id end)
        t.eq(wrapped and wrapped.id, last_id, "found after wrapping around")
        t.eq(pack:_pickInBand(band, 0, function() return false end), nil, "none acceptable: nil")
        t.ok(not pack:isEmpty(), "isEmpty")
        t.ok(pack:themesOf("004JD"):find("mateIn1"), "themesOf")
        t.eq(pack:themesOf("nope"), nil, "themesOf an unknown id")
        pack:close()
    end },
    { "progress: reviews are not rated, but mark the puzzle as seen for good", function(t)
        local path = tmpdb()
        local prog = PkProgress.open(path)
        prog:record({ puzzle_id = "A", puzzle_rating = 1200, success = false, solved = false, mistakes = 1,
                      used_help = false, ts = 1000 }, { step = 0, due = 5, lapses = 0, missed = 1000 })
        t.ok(prog:getReview("A"), "review card saved with the attempt")
        local rating = prog:rating()
        prog:recordReview("A", true, 1200, nil, 2000) -- mastered: card removed
        t.eq(prog:getReview("A"), nil, "card removed")
        t.eq(prog:rating(), rating, "a review does not change the rating")
        t.eq(prog:attemptCount(), 1, "nor counts as a rated attempt")
        t.eq(#prog:attempts(), 1, "nor appears in the stats")
        t.ok(prog:reviewedIds().A, "a mastered puzzle stays reviewed (never new again)")
        t.ok(prog:attemptedSince(1500).A and not prog:attemptedSince(2500).A, "attemptedSince: reviews included")
        prog:close()
        os.remove(path)
    end },
    { "progress: older files are migrated (review column, review ladder)", function(t)
        local path = tmpdb()
        local SQ3 = require("lua-ljsqlite3/init")
        local conn = SQ3.open(path)
        conn:exec([[
            CREATE TABLE attempts (puzzle_id TEXT NOT NULL, ts INTEGER NOT NULL, solved INTEGER NOT NULL,
                mistakes INTEGER NOT NULL, used_help INTEGER NOT NULL, puzzle_rating INTEGER NOT NULL,
                rating_before INTEGER NOT NULL, rating_after INTEGER NOT NULL);
            INSERT INTO attempts VALUES ('A', 1000, 1, 0, 0, 1200, 1200, 1215);
            CREATE TABLE puzzle_reviews (puzzle_id TEXT PRIMARY KEY, due INTEGER NOT NULL,
                step INTEGER NOT NULL, lapses INTEGER NOT NULL, missed INTEGER NOT NULL);
            INSERT INTO puzzle_reviews VALUES ('B', 10, 0, 0, 1), ('C', 10, 1, 0, 1), ('D', 10, 2, 0, 1);]])
        conn:close()
        local prog = PkProgress.open(path)
        t.eq(prog:attemptCount(), 1, "old attempts kept, rated")
        t.eq(prog:getReview("B").step, 0, "step 0 stays")
        t.eq(prog:getReview("C").step, 0, "old step 1 (waiting 3 days) -> new step 0")
        t.eq(prog:getReview("D").step, 1, "old step 2 (waiting 7 days) -> new step 1")
        prog:close()
        prog = PkProgress.open(path)
        t.eq(prog:getReview("D").step, 1, "the ladder migration runs once")
        prog:close()
        os.remove(path)
    end },
    { "progress: a failed transaction is rolled back and leaves the connection usable", function(t)
        local path = tmpdb()
        local prog = PkProgress.open(path)
        local ok = pcall(prog._tx, prog, function()
            prog:setSetting("x", "1")
            error("boom")
        end)
        t.ok(not ok, "error raised")
        t.eq(prog:getSetting("x"), nil, "rolled back")
        prog:record{ puzzle_id = "A", puzzle_rating = 1200, success = true, solved = true, mistakes = 0,
                     used_help = false, ts = 1000 }
        t.eq(prog:attemptCount(), 1, "later writes work (no transaction left open)")
        prog:close()
        os.remove(path)
    end },
    { "theme filter: every pick carries the theme, themes() lists counts", function(t)
        local pack = assert(PkPuzzlePack.open(FIXTURE))
        local counts = {}
        for _, th in ipairs(pack:themes()) do counts[th.theme] = th.count end
        t.eq(counts.mateIn1, 14, "mateIn1 count")
        for _, r in ipairs({ 0.1, 0.5, 0.9 }) do
            local p = pack:pickNear(1500, { random = seq(r), theme = "mateIn1" })
            t.ok(p and (" " .. p.themes .. " "):find(" mateIn1 "), "picked a mateIn1 puzzle: " .. tostring(p and p.themes))
            t.eq(p and type(p.rating), "number", "rating is a number")
        end
        t.eq(pack:pickNear(1500, { random = seq(0.5), theme = "noSuchTheme" }), nil, "unknown theme")
        pack:close()
    end },
    { "settings persist and can be cleared", function(t)
        local path = tmpdb()
        local prog = PkProgress.open(path)
        t.eq(prog:getSetting("theme"), nil, "unset")
        prog:setSetting("theme", "fork")
        prog:close()
        prog = PkProgress.open(path)
        t.eq(prog:getSetting("theme"), "fork", "persisted")
        prog:setSetting("theme", nil)
        t.eq(prog:getSetting("theme"), nil, "cleared")
        t.eq(prog:rating(), 1200, "settings don't touch the rating")
        prog:close()
        os.remove(path)
    end },
}
