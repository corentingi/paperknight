-- Missed-puzzle reviews (pkpuzzlereview.lua) and their storage (pkprogress).
local PkProgress = require("pkprogress")
local PkPuzzleReview = require("pkpuzzlereview")
local PkSrs = require("pksrs")

local NOW = os.time{ year = 2026, month = 3, day = 10, hour = 12 }
local DAY = 86400

local function db()
    local path = os.tmpname()
    os.remove(path)
    local p = PkProgress.open(path)
    return p, function() p:close(); os.remove(path) end
end

local function puzzle(id)
    return { id = id, fen = "6k1/5ppp/8/8/8/8/5PPP/3R2K1 w - - 0 1", moves = "g8h8 d1d8", solver = "w",
             rating = 1234, themes = "mate backRankMate", opening = "", game_url = "https://lichess.org/x",
             rating_dev = 77 }
end

return {
    { "puzzles under review or liked are kept, whatever the pack (ADR-0022)", function(t)
        local p, done = db()
        local card = PkPuzzleReview.missed(nil, NOW)
        p:record({ puzzle_id = "aaaaa", puzzle_rating = 1234, success = false, solved = false, mistakes = 1,
                   ts = NOW, puzzle = puzzle("aaaaa") }, card)
        local kept = p:keptPuzzle("aaaaa")
        t.ok(kept, "kept with its review card")
        t.eq(kept.fen, puzzle("aaaaa").fen); t.eq(kept.moves, "g8h8 d1d8"); t.eq(kept.solver, "w")
        t.eq(kept.rating, 1234); t.eq(kept.rating_dev, 77); t.eq(kept.themes, "mate backRankMate")
        t.eq(p:keptPuzzle("zzzzz"), nil)
        -- a clean attempt (no card) keeps nothing
        p:record({ puzzle_id = "bbbbb", puzzle_rating = 1200, success = true, solved = true, mistakes = 0,
                   ts = NOW, puzzle = puzzle("bbbbb") })
        t.eq(p:keptPuzzle("bbbbb"), nil, "no card: not kept")
        -- liked: kept; liked and under review: kept until both are gone
        p:setLiked("bbbbb", true, NOW, puzzle("bbbbb"))
        t.ok(p:keptPuzzle("bbbbb"), "kept with the like")
        p:setLiked("aaaaa", true, NOW, puzzle("aaaaa"))
        p:recordReview("aaaaa", true, 1234, nil, NOW) -- mastered: the card removed
        t.ok(p:keptPuzzle("aaaaa"), "still liked: kept")
        p:setLiked("aaaaa", false)
        t.eq(p:keptPuzzle("aaaaa"), nil, "neither under review nor liked: forgotten")
        p:setLiked("bbbbb", false)
        t.eq(p:keptPuzzle("bbbbb"), nil)
        -- cards and likes made before: kept from the pack at hand
        p:saveReview("ccccc", card); p:saveReview("ddddd", card); p:setLiked("eeeee", true, NOW)
        local asked = {}
        local n = p:keepMissing(function(id)
            asked[#asked + 1] = id
            if id ~= "ddddd" then return puzzle(id) end -- ddddd: not in this pack
        end)
        table.sort(asked)
        t.eq(table.concat(asked, " "), "ccccc ddddd eeeee"); t.eq(n, 2)
        t.ok(p:keptPuzzle("ccccc") and p:keptPuzzle("eeeee")); t.eq(p:keptPuzzle("ddddd"), nil)
        t.eq(p:keepMissing(function(id) asked[#asked + 1] = id end), 0)
        t.eq(#asked, 4, "only the ones still missing are looked up again")
        done()
    end },
    { "a miss comes back in 3 days, then 7, 21, then mastered", function(t)
        local today = PkSrs.today(NOW)
        local c = PkPuzzleReview.missed(nil, NOW)
        t.eq(c.due, today + 3, "in 3 days"); t.eq(c.step, 0, "step"); t.eq(c.missed, NOW, "first miss kept")
        t.ok(not PkPuzzleReview.isDue(c, today + 2), "not before")
        t.ok(PkPuzzleReview.isDue(c, today + 3), "due in 3 days")
        local now, days = NOW + 3 * DAY, nil
        for _, expect in ipairs({ 7, 21 }) do
            c, days = PkPuzzleReview.solved(c, now)
            t.eq(days, expect, "interval"); t.eq(c.due, PkSrs.today(now) + expect, "due")
            now = now + expect * DAY
        end
        t.eq(PkPuzzleReview.solved(c, now), nil, "mastered after the 3rd clean review")
    end },
    { "a miss during reviews starts over and counts a lapse", function(t)
        local c = PkPuzzleReview.missed(nil, NOW)
        c = PkPuzzleReview.solved(c, NOW + DAY)
        c = PkPuzzleReview.missed(c, NOW + 4 * DAY)
        t.eq(c.step, 0, "back to the start"); t.eq(c.lapses, 1, "lapse")
        t.eq(c.due, PkSrs.today(NOW + 4 * DAY) + 3, "in 3 days again"); t.eq(c.missed, NOW, "first miss date kept")
    end },
    { "past misses are spread over a week", function(t)
        local ids, at = {}, {}
        for i = 1, 20 do ids[i] = "p" .. i; at[ids[i]] = NOW - i * DAY end
        local cards = PkPuzzleReview.seed(ids, at, 100, 7)
        t.eq(cards.p1.due, 100, "most recent today"); t.eq(cards.p3.due, 100, "3 a day")
        t.eq(cards.p4.due, 101, "next day"); t.eq(cards.p20.due, 106, "within the week")
        t.eq(cards.p5.missed, NOW - 5 * DAY, "miss date")
    end },
    { "storage: save, due list in order, count, remove", function(t)
        local p, close = db()
        p:saveReview("A", { step = 1, due = 105, lapses = 0, missed = 1 })
        p:saveReview("B", { step = 0, due = 101, lapses = 2, missed = 2 })
        p:saveReview("C", { step = 0, due = 110, lapses = 0, missed = 3 })
        t.eq(p:reviewDueCount(105), 2, "A and B due on day 105")
        local due = p:dueReviews(105)
        t.eq(#due, 2, "two due"); t.eq(due[1].puzzle_id, "B", "oldest due first"); t.eq(due[1].lapses, 2, "fields")
        local card = p:getReview("C")
        t.eq(card.due, 110, "get"); t.eq(p:getReview("Z"), nil, "missing")
        p:saveReview("B", { step = 1, due = 120, lapses = 2, missed = 2 })
        t.eq(p:reviewDueCount(105), 1, "B rescheduled")
        p:removeReview("A")
        t.eq(p:reviewDueCount(200), 2, "A removed")
        close()
    end },
    { "storage: past misses seeded once, from the attempts", function(t)
        local p, close = db()
        local function attempt(id, ts, solved, mistakes, help)
            p:record{ puzzle_id = id, puzzle_rating = 1500, success = solved and mistakes == 0 and not help,
                      solved = solved, mistakes = mistakes, used_help = help, ts = ts }
        end
        attempt("clean", NOW - DAY, true, 0, false)
        attempt("mistake", NOW - 2 * DAY, true, 1, false)
        attempt("help", NOW - 3 * DAY, true, 0, true)
        attempt("failed", NOW - 4 * DAY, false, 0, true)
        attempt("old", NOW - 90 * DAY, false, 2, false)
        attempt("later", NOW - 5 * DAY, false, 1, false)
        attempt("later", NOW - DAY / 2, true, 0, false) -- solved cleanly later: no review
        t.eq(p:seedReviews(NOW, 60), 3, "mistake, help, failed")
        t.ok(p:getReview("mistake") and p:getReview("help") and p:getReview("failed"), "seeded")
        t.eq(p:getReview("clean"), nil, "clean solve"); t.eq(p:getReview("old"), nil, "older than 60 days")
        t.eq(p:getReview("later"), nil, "solved cleanly since")
        t.eq(p:getReview("mistake").missed, NOW - 2 * DAY, "miss date")
        t.eq(p:seedReviews(NOW, 60), 0, "only once")
        close()
    end },
    { "liked puzzles: liked once, the latest first, unliked", function(t)
        local p, done = db()
        t.ok(not p:isLiked("004JD"), "not liked yet")
        p:setLiked("004JD", true, NOW)
        p:setLiked("0042j", true, NOW + 10)
        p:setLiked("004JD", true, NOW + 20) -- liked again: kept once, at its first time
        t.ok(p:isLiked("004JD"), "liked")
        t.eq(table.concat(p:likedIds(), " "), "0042j 004JD", "the latest liked first")
        p:setLiked("0042j", false)
        t.eq(table.concat(p:likedIds(), " "), "004JD", "unliked")
        done()
    end },
    { "a puzzle id from what the user typed", function(t)
        local parse = require("pkpuzzlepack").parseId
        t.eq(parse("004JD"), "004JD", "an id")
        t.eq(parse("  004JD \n"), "004JD", "spaces around")
        t.eq(parse("https://lichess.org/training/004JD"), "004JD", "an address")
        t.eq(parse("lichess.org/training/004JD/"), "004JD", "without the scheme")
        t.eq(parse("004J"), nil, "too short")
        t.eq(parse("004JD9"), nil, "too long")
        t.eq(parse("lichess.org/abcdefgh"), nil, "a game address")
        t.eq(parse(nil), nil, "nothing")
    end },
}
