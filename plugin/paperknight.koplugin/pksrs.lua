-- Spaced repetition for repertoire cards (ADR-0012): a simplified SM-2.
-- Pure Lua, no UI. A card is { reps, interval, ease, lapses, due, last }:
--   reps      successes in a row (0 = new or just failed)
--   interval  days until the next review
--   due       day number (PkSrs.today) from which the card is due; nil = new
--   last      timestamp of the last review; nil = never reviewed
--   introduced day number the card was first shown (daily cap on new cards)
local PkSrs = {}

PkSrs.START_EASE = 2.5
PkSrs.MIN_EASE = 1.3
PkSrs.MAX_EASE = 2.8
PkSrs.DAY = 86400
-- a "day" starts at 4 am local time, so a late-evening session counts for
-- the same day as the morning before it (like Anki)
PkSrs.DAY_START_HOUR = 4

function PkSrs.new()
    return { reps = 0, interval = 0, ease = PkSrs.START_EASE, lapses = 0, due = nil, last = nil }
end

-- Days since 1970-01-01 of a civil date (H. Hinnant's days_from_civil):
-- pure arithmetic, so time zones and DST cannot skip or repeat a day.
local function daysFromCivil(y, m, d)
    if m <= 2 then y = y - 1 end
    local era = math.floor(y / 400)
    local yoe = y - era * 400
    local mp = (m + 9) % 12
    local doy = math.floor((153 * mp + 2) / 5) + d - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    return era * 146097 + doe - 719468
end

--- Local day number of timestamp `now` (default: current time).
function PkSrs.today(now)
    local t = os.date("*t", (now or os.time()) - PkSrs.DAY_START_HOUR * 3600)
    return daysFromCivil(t.year, t.month, t.day)
end

function PkSrs.isNew(card)
    return card.last == nil
end

--- True if the card should be reviewed on day `today` (new cards are not
-- "due": they are introduced separately, under the daily cap).
function PkSrs.isDue(card, today)
    return card.due ~= nil and card.due <= today
end

--- A new card was shown to the user (the move is taught, not tested): it
-- becomes due today, so the same session tests it again.
function PkSrs.introduce(card, now)
    assert(PkSrs.isNew(card), "card already introduced")
    now = now or os.time()
    local today = PkSrs.today(now)
    return { reps = 0, interval = 0, ease = card.ease, lapses = card.lapses,
             last = now, due = today, introduced = today }
end

--- Returns a new card state after a review. `good`: right move first time,
-- without hint or solution. `now`: timestamp.
function PkSrs.grade(card, good, now)
    now = now or os.time()
    local c = {
        reps = card.reps, interval = card.interval, ease = card.ease,
        lapses = card.lapses, last = now, introduced = card.introduced,
    }
    if good then
        c.reps = c.reps + 1
        if c.reps == 1 then
            c.interval = 1
        elseif c.reps == 2 then
            c.interval = 3
        else
            c.interval = math.max(c.interval + 1, math.floor(c.interval * c.ease + 0.5))
        end
        c.ease = math.min(PkSrs.MAX_EASE, c.ease + 0.05)
    else
        if card.reps > 0 then c.lapses = c.lapses + 1 end -- forgot a learned move
        c.reps = 0
        c.interval = 0 -- relearn: due again today (the session repeats it)
        c.ease = math.max(PkSrs.MIN_EASE, c.ease - 0.20)
    end
    c.due = PkSrs.today(now) + c.interval
    return c
end

return PkSrs
