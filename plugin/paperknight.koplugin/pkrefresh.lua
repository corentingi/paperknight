-- E-ink refreshes for the board screens (study, drill, puzzles); see
-- docs/eink-refresh.md for how the Kindle and KOReader refresh the screen.
--  * A step (a move, a selection, the status line) is a "[partial]" refresh:
--    on the PW2 the same non-flashing waveform as KOReader's page turns
--    ("partial" is REAGL there, GL16_INV in night mode), but KOReader does
--    not count it towards its periodic flash, which would otherwise flash
--    the board region every few moves (a counted regional "partial" becomes
--    "flashui" every N, N being the user's full refresh rate).
--  * A page (a new puzzle, chapter or line) is a counted, whole-screen
--    "partial", like a book page: every N pages it becomes a full flash,
--    which clears the ghosting the steps leave.
-- Unchanged pixels are not touched, so a generous region costs nothing; the
-- puzzle screen still refreshes only the rectangle around the squares that
-- changed, in one refresh (Board.square_refresh), and the status strip.
local Geometry = require("ui/geometry")
local UIManager = require("ui/uimanager")

local PkRefresh = {}

PkRefresh.STEP = "[partial]"

--- Refreshes the part of `view` from widget `first` to widget `last`
-- (e.g. the board to the buttons) after a step: down to the bottom of the
-- view when `last` was just rebuilt (no position yet), the whole view when
-- `first` has no position either.
function PkRefresh.step(view, first, last)
    UIManager:setDirty(view, PkRefresh.STEP, PkRefresh.region(view, first, last))
end

--- Sets the subtitle of `view.title_bar` when it changed, refreshed as a
-- step (TitleBar's own refresh is "ui", GC16_FAST: it flickers the changed
-- text). `refresh(rect)`: optional, to join it to another refresh.
function PkRefresh.setSubTitle(view, text, refresh)
    local title_bar = view.title_bar
    if text == title_bar.subtitle_widget.text then return end
    title_bar:setSubTitle(text, true)
    if not title_bar.dimen then return end -- not shown yet: painted with the view
    if refresh then refresh(title_bar.dimen) else UIManager:setDirty(view, PkRefresh.STEP, title_bar.dimen) end
end

--- The region PkRefresh.step refreshes (nil: the whole view).
function PkRefresh.region(view, first, last)
    local a, b = first and first.dimen, last and last.dimen
    if not (a and a.y) then return nil end
    local bottom = (b and b.y) and (b.y + b.h) or (view.dimen.y or 0) + view.dimen.h
    return Geometry:new{ x = 0, y = a.y, w = view.dimen.w, h = bottom - a.y }
end

--- Refreshes the whole view (a new chapter, line or puzzle).
function PkRefresh.page(view)
    UIManager:setDirty(view, "partial")
end

return PkRefresh
