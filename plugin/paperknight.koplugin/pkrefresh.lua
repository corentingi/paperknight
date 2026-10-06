-- E-ink refreshes for the board screens (study, drill, puzzles), like
-- KOReader's own page turns: "partial" refreshes (GL16 on Kindles: no
-- flicker for text and greys on white; "ui" is GC16 there, which flickers
-- every changed pixel). KOReader counts "partial" refreshes and flashes once
-- every N of them, N being the user's setting (Screen > E-ink > Full refresh
-- rate, "never" included), and downgrades them when "Avoid flashing" is on.
-- Unchanged pixels are not touched, so a generous region costs nothing,
-- except that the periodic flash covers the whole region: the puzzle screen
-- (one board update per move) refreshes only the rectangle around the
-- squares that changed, in one refresh (Board.square_refresh), and the
-- status strip.
local Geometry = require("ui/geometry")
local UIManager = require("ui/uimanager")

local PkRefresh = {}

--- Refreshes the part of `view` from widget `first` to widget `last`
-- (e.g. the board to the buttons) after a step; the whole view when their
-- positions are not known yet.
function PkRefresh.step(view, first, last)
    local region
    local a, b = first and first.dimen, last and last.dimen
    if a and b and a.y and b.y then
        region = Geometry:new{ x = 0, y = a.y, w = view.dimen.w, h = b.y + b.h - a.y }
    end
    UIManager:setDirty(view, "partial", region)
end

--- Refreshes the whole view (a new chapter, line or puzzle).
function PkRefresh.page(view)
    UIManager:setDirty(view, "partial")
end

return PkRefresh
