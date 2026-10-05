-- Spaced repetition scheduler (pksrs.lua, ADR-0012).
local PkSrs = require("pksrs")

-- a fixed local noon, away from the 4 am day boundary
local NOON = os.time{ year = 2026, month = 3, day = 10, hour = 12 }
local DAY = PkSrs.DAY

return {
    { "day numbers: 4 am boundary", function(t)
        local today = PkSrs.today(NOON)
        t.eq(PkSrs.today(NOON + 11 * 3600), today, "11 pm is the same day")
        t.eq(PkSrs.today(NOON + 15 * 3600), today, "3 am next morning still the same day")
        t.eq(PkSrs.today(NOON + 17 * 3600), today + 1, "5 am next morning is the next day")
        t.eq(PkSrs.today(NOON + 30 * DAY), today + 30, "30 days later")
        t.eq(PkSrs.today(os.time{ year = 1970, month = 1, day = 2, hour = 12 }), 1, "epoch-based day numbers")
        t.eq(PkSrs.today(os.time{ year = 2024, month = 3, day = 1, hour = 12 })
            - PkSrs.today(os.time{ year = 2024, month = 2, day = 28, hour = 12 }), 2, "leap day")
    end },
    { "new card: introduce, then intervals 1, 3, then x ease", function(t)
        local today = PkSrs.today(NOON)
        local c = PkSrs.new()
        t.ok(PkSrs.isNew(c) and not PkSrs.isDue(c, today), "new cards are not due")
        c = PkSrs.introduce(c, NOON)
        t.ok(not PkSrs.isNew(c) and PkSrs.isDue(c, today), "introduced: due today")
        t.eq(c.introduced, today, "introduction day kept (daily cap)")
        t.ok(not pcall(PkSrs.introduce, c, NOON), "a card is introduced once")
        c = PkSrs.grade(c, true, NOON)
        t.eq(c.interval, 1, "first success: 1 day"); t.eq(c.due, today + 1, "due tomorrow")
        t.ok(not PkSrs.isDue(c, today), "not due again today")
        c = PkSrs.grade(c, true, NOON + DAY)
        t.eq(c.interval, 3, "second success: 3 days")
        local ease = c.ease
        c = PkSrs.grade(c, true, NOON + 4 * DAY)
        t.eq(c.interval, math.floor(3 * ease + 0.5), "then interval x ease")
        t.eq(c.reps, 3, "three successes"); t.eq(c.lapses, 0, "no lapse")
        t.eq(c.introduced, today, "introduction day survives reviews")
    end },
    { "failure resets the interval, lowers ease, counts a lapse once learned", function(t)
        local today = PkSrs.today(NOON)
        local c = PkSrs.introduce(PkSrs.new(), NOON)
        c = PkSrs.grade(c, false, NOON)
        t.eq(c.lapses, 0, "failing while learning is not a lapse")
        t.eq(c.ease, PkSrs.START_EASE - 0.20, "ease lowered")
        c = PkSrs.grade(c, true, NOON); c = PkSrs.grade(c, true, NOON + DAY)
        c = PkSrs.grade(c, false, NOON + 4 * DAY)
        t.eq(c.lapses, 1, "forgetting a learned move is a lapse")
        t.eq(c.reps, 0, "successes reset")
        t.eq(c.due, today + 4, "due again the same day (relearn in the session)")
        c = PkSrs.grade(c, true, NOON + 4 * DAY)
        t.eq(c.interval, 1, "relearned: back to 1 day")
        for _ = 1, 20 do c = PkSrs.grade(c, false, NOON) end
        t.eq(c.ease, PkSrs.MIN_EASE, "ease floor")
        for _ = 1, 40 do c = PkSrs.grade(c, true, NOON) end
        t.eq(c.ease, PkSrs.MAX_EASE, "ease ceiling")
    end },
    { "grade returns a new table", function(t)
        local c = PkSrs.introduce(PkSrs.new(), NOON)
        local c2 = PkSrs.grade(c, true, NOON)
        t.eq(c.reps, 0, "input unchanged"); t.eq(c2.reps, 1, "output updated")
    end },
}
