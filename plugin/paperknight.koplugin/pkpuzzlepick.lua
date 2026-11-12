-- Which puzzle comes next (ADR-0010, ADR-0014, ADR-0022): the due reviews
-- first, then a puzzle near the rating, not seen recently, not under
-- review, not shown this session. Holds the session's sets; the pack and
-- the progress file do the queries. pkpuzzleview.lua loads and shows the
-- puzzle; specs drive this with fakes (pick_spec.lua).
local PkSrs = require("pksrs")

local PkPuzzlePick = {
    RECENT_DAYS = 30, -- a puzzle attempted this recently is not fresh
}
PkPuzzlePick.__index = PkPuzzlePick

--- A pick over `pack` (pkpuzzlepack) and `progress` (pkprogress).
-- `random`: the pack's random source (tests: a fixed one).
function PkPuzzlePick.new(pack, progress, random)
    return setmetatable({
        pack = pack, progress = progress, random = random,
        skipped = {}, -- reviews already shown this session
        bad = {},     -- puzzles whose line is broken (never served again)
        served = {},  -- puzzles shown this session (no repeat until all were)
    }, PkPuzzlePick)
end

local function hasTheme(tags, theme)
    return (" " .. (tags or "") .. " "):find(" " .. theme .. " ", 1, true) ~= nil
end

--- Puzzle `id`: the pack's, else the copy kept with its review or like
-- (ADR-0022: a new pack drops puzzles); nil if neither has it.
function PkPuzzlePick:find(id)
    local ok, puzzle = pcall(self.pack.get, self.pack, id)
    if ok and puzzle then return puzzle end
    local k_ok, kept = pcall(self.progress.keptPuzzle, self.progress, id)
    return k_ok and kept or nil
end

--- Its theme tags ("fork pin"), nil if it is not known.
function PkPuzzlePick:themesOf(id)
    local themes = self.pack:themesOf(id)
    if themes then return themes end
    local ok, kept = pcall(self.progress.keptPuzzle, self.progress, id)
    return ok and kept and kept.themes or nil
end

--- How many due reviews this session can still serve: of `theme` (nil:
-- any), not skipped or broken (the title's "Reviews: N").
function PkPuzzlePick:servableReviewCount(theme, today)
    local n = 0
    for _, card in ipairs(self.progress:dueReviews(today or PkSrs.today())) do
        local id = card.puzzle_id
        if not self.skipped[id] and not self.bad[id] and (not theme or hasTheme(self:themesOf(id), theme)) then
            n = n + 1
        end
    end
    return n
end

--- The first due review not shown yet this session, of `theme`: its card
-- and its puzzle, or nil. A card whose puzzle is known nowhere (older than
-- ADR-0022, dropped by an earlier pack) is removed.
function PkPuzzlePick:nextReview(theme, today)
    for _, card in ipairs(self.progress:dueReviews(today or PkSrs.today())) do
        local id = card.puzzle_id
        if not self.skipped[id] and not self.bad[id] then
            local puzzle = self:find(id)
            if not puzzle then
                self.progress:removeReview(id)
            elseif not theme or hasTheme(puzzle.themes, theme) then
                return card, puzzle
            end
        end
    end
    return nil
end

-- Puzzles seen recently and puzzles under review (or mastered), as sets,
-- read once per session and kept up to date by markSeen: the pick tests
-- many candidates per Next.
function PkPuzzlePick:seenSets(now)
    if not self.recent then
        self.recent = self.progress:attemptedSince((now or os.time()) - PkPuzzlePick.RECENT_DAYS * 86400)
        self.reviewed = self.progress:reviewedIds()
    end
    return self.recent, self.reviewed
end

--- A puzzle was attempted (`reviewed`: missed or reviewed): the session's sets follow.
function PkPuzzlePick:markSeen(id, reviewed)
    if not self.recent then return end -- read later, from the database
    self.recent[id] = true
    if reviewed then self.reviewed[id] = true end
end

--- A new puzzle near the rating, of `theme`, other than `current_id`:
-- the puzzle (nil if none) and whether it is fresh (not seen recently).
-- Once every candidate was shown this session, a new round starts. Raises
-- on a database error.
function PkPuzzlePick:nextNew(theme, current_id)
    local function pick()
        local recent, reviewed = self:seenSets()
        return self.pack:pickNear(self.progress:rating(), {
            random = self.random,
            theme = theme,
            accept = function(p)
                return p.id ~= current_id and not self.served[p.id] and not self.bad[p.id]
                    -- under review: comes back as a review; mastered: never again
                    and not reviewed[p.id]
            end,
            fresh = function(p) return not recent[p.id] end,
        })
    end
    local puzzle, fresh = pick()
    if not puzzle and next(self.served) then
        self.served = {} -- a new round
        puzzle, fresh = pick()
    end
    if puzzle then self.served[puzzle.id] = true end
    return puzzle, fresh
end

return PkPuzzlePick
