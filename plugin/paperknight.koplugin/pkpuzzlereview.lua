-- Missed-puzzle reviews (ADR-0014). Pure Lua, no UI, no storage.
-- A card is { step, due, lapses, missed }:
--   step    clean solves in a row since the last miss (0..#INTERVALS-1)
--   due     day number (PkSrs.today) from which the puzzle is due
--   lapses  misses after the first one
--   missed  timestamp of the first miss (shown to the user)
-- A missed puzzle comes back the next day; each clean solve sends it
-- further (INTERVALS days); after the last one it is mastered (no card).
-- A miss (mistake, hint or solution, as for the rating) starts it over.
local PkSrs = require("pksrs")

local PkPuzzleReview = {}

PkPuzzleReview.INTERVALS = { 3, 7, 21 } -- days after the 1st, 2nd, 3rd clean solve
PkPuzzleReview.AFTER_MISS = 1           -- days after a miss

--- Card for a puzzle missed at `now` (first attempt, or a review).
-- `card`: the existing card, if any.
function PkPuzzleReview.missed(card, now)
    now = now or os.time()
    return {
        step = 0,
        due = PkSrs.today(now) + PkPuzzleReview.AFTER_MISS,
        lapses = card and (card.lapses + 1) or 0,
        missed = card and card.missed or now,
    }
end

--- Card after a clean solve of a due review at `now`, or nil when the
-- puzzle is mastered. Second value: days until the next review (or nil).
function PkPuzzleReview.solved(card, now)
    now = now or os.time()
    local step = card.step + 1
    local days = PkPuzzleReview.INTERVALS[step]
    if not days then return nil, nil end
    return { step = step, due = PkSrs.today(now) + days, lapses = card.lapses, missed = card.missed }, days
end

function PkPuzzleReview.isDue(card, today)
    return card.due <= (today or PkSrs.today())
end

--- Cards for past misses (history from before reviews existed): `ids` most
-- recent first, spread over `days` days from `today` so they don't all
-- come at once. `missed_at[id]`: timestamp of the miss.
function PkPuzzleReview.seed(ids, missed_at, today, days)
    days = days or 7
    local cards = {}
    local per_day = math.max(1, math.ceil(#ids / days))
    for i, id in ipairs(ids) do
        cards[id] = { step = 0, due = today + math.floor((i - 1) / per_day), lapses = 0, missed = missed_at[id] }
    end
    return cards
end

return PkPuzzleReview
