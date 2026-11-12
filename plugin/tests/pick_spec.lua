-- Which puzzle comes next (pkpuzzlepick.lua), over a fake pack and a fake
-- progress file: due reviews first (of the theme, not skipped or broken,
-- from the kept copy when the pack lost the puzzle), then a new puzzle
-- (not under review, not shown this session, a new round once all were).
local PkPuzzlePick = require("pkpuzzlepick")

local PUZZLES = {
    A = { id = "A", themes = "fork middlegame" }, B = { id = "B", themes = "pin" },
    C = { id = "C", themes = "fork" }, D = { id = "D", themes = "mateIn1" },
}

local function fakes(o)
    o = o or {}
    local pack = {
        get = function(_, id) return PUZZLES[id] end,
        themesOf = function(_, id) return PUZZLES[id] and PUZZLES[id].themes end,
        -- every candidate the accept filter lets through, in id order
        pickNear = function(_, rating, opts)
            o.rating = rating
            for _, id in ipairs({ "A", "B", "C", "D" }) do
                local p = PUZZLES[id]
                if (not opts.theme or p.themes:find(opts.theme, 1, true)) and opts.accept(p) then
                    return p, opts.fresh(p)
                end
            end
        end,
    }
    local removed = {}
    local progress = {
        due = o.due or {},
        kept = o.kept or {},
        dueReviews = function(self) return self.due end,
        keptPuzzle = function(self, id) return self.kept[id] end,
        removeReview = function(_, id) removed[#removed + 1] = id end,
        attemptedSince = function() return o.recent or {} end,
        reviewedIds = function() return o.reviewed or {} end,
        rating = function() return 1500 end,
    }
    return PkPuzzlePick.new(pack, progress), removed
end

local function card(id) return { puzzle_id = id } end

return {
    { "reviews: of the theme, not skipped or broken, the lost ones dropped", function(t)
        local pick, removed = fakes{
            due = { card("GONE"), card("B"), card("A"), card("OLD") },
            kept = { OLD = { id = "OLD", themes = "fork" } },
        }
        local c, p = pick:nextReview(nil)
        t.eq(c.puzzle_id, "B", "the first due one the pack has"); t.eq(p.id, "B")
        t.eq(table.concat(removed, " "), "GONE", "a card whose puzzle is known nowhere is removed")
        c = pick:nextReview("fork")
        t.eq(c.puzzle_id, "A", "of the theme")
        pick.skipped.A = true
        c, p = pick:nextReview("fork")
        t.eq(c.puzzle_id, "OLD", "skipped this session: the next one, from the kept copy")
        t.eq(p.themes, "fork")
        t.eq(pick:servableReviewCount("fork"), 1, "fork: OLD left (A skipped, GONE unknown)")
        pick.bad.OLD = true
        t.eq(pick:nextReview("fork"), nil, "a broken one is not served")
        t.eq(pick:servableReviewCount(nil), 2, "any theme: GONE and B (A skipped, OLD broken)")
    end },
    { "new puzzles: not the current one, not under review, one round at a time", function(t)
        local pick = fakes{ reviewed = { A = true }, recent = { C = true } }
        local p, fresh = pick:nextNew(nil, nil)
        t.eq(p.id, "B", "A under review: skipped"); t.ok(fresh, "B not seen recently")
        p, fresh = pick:nextNew(nil, "B")
        t.eq(p.id, "C", "B shown this session"); t.ok(not fresh, "C attempted recently: stale")
        p = pick:nextNew(nil, "C")
        t.eq(p.id, "D")
        p = pick:nextNew(nil, "D")
        t.eq(p.id, "B", "all shown: a new round (not the current one)")
        p = pick:nextNew("fork", nil)
        t.eq(p.id, "C", "a theme")
        pick.bad.C = true
        pick.served = {}
        t.eq(pick:nextNew("fork", nil), nil, "fork: A under review, C broken")
    end },
    { "the session's sets follow the attempts", function(t)
        local pick = fakes{}
        pick:markSeen("B") -- before the sets are read: nothing to update
        local recent, reviewed = pick:seenSets()
        t.eq(recent.B, nil)
        pick:markSeen("B", true)
        t.ok(recent.B and reviewed.B, "seen and under review")
        local p = pick:nextNew(nil, nil)
        t.eq(p.id, "A", "B now under review, A not")
    end },
}
