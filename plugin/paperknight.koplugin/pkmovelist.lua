-- Move list: a lean table of the line (#, White, Black) beside the board,
-- the current move shaded. A tap on a move goes to the position after it
-- (onSelect(ply)). Scrolled by KOReader's ScrollableContainer when longer
-- than its space (swipe up/down by a page, drag, scroll bar), kept on the
-- current move. Taps are mapped to cells by position (no button per move).
local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geometry = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local RightContainer = require("ui/widget/container/rightcontainer")
local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local PkRefresh = require("pkrefresh")

-- KOReader's scrolling, with three changes: sideways swipes are left to the
-- view (they step through the line); no blank overflow past the first or
-- last row (KOReader's lists allow it); a scroll is refreshed as a step
-- (its own refresh is "ui", which flickers; the stronger mode wins).
local Scroll = ScrollableContainer:extend{}

function Scroll:onScrollableSwipe(arg, ges)
    if ges.direction ~= "north" and ges.direction ~= "south" then return false end
    return ScrollableContainer.onScrollableSwipe(self, arg, ges)
end

function Scroll:_scrollBy(dx, dy, ensure_scroll_steps)
    ScrollableContainer._scrollBy(self, dx, dy, ensure_scroll_steps)
    local y = math.max(0, math.min(self._scroll_offset_y, self._max_scroll_offset_y))
    if y ~= self._scroll_offset_y then
        self._scroll_offset_y = y
        self:_updateScrollBars()
    end
    if self.dimen.x then UIManager:setDirty(self.show_parent, PkRefresh.STEP, self.dimen) end
end

local PkMoveList = InputContainer:extend{
    width = nil,
    height = nil,
    moves = nil,         -- SAN of each ply
    first_number = 1,    -- move number of the first ply
    black_first = false, -- the first ply is Black's
    current = 0,         -- ply shown on the board (0: the start)
    onSelect = nil,      -- function(ply)
    font_size = 16,
    number_font_size = 12,
}

function PkMoveList:init()
    self.moves = self.moves or {}
    self.dimen = Geometry:new{ w = self.width, h = self.height }
    self.face = Font:getFace("cfont", self.font_size)
    self.number_face = Font:getFace("cfont", self.number_font_size)
    self.row_h = math.floor(self.face.size * 1.5)
    -- whole rows only: no row cut at the top or bottom
    self.rows_shown = math.max(1, math.floor(self.height / self.row_h))
    -- room for the scroll bar and its padding, so that it never scrolls sideways
    self.inner_w = self.width - ScrollableContainer:getScrollbarWidth()
    local probe = TextWidget:new{ text = "188.", face = self.number_face }
    self.num_w = probe:getSize().w + Size.padding.small
    probe:free()
    self.move_w = math.floor((self.inner_w - self.num_w) / 2)
    self.ges_events = {
        Tap = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
    }
    self.scroll = Scroll:new{
        dimen = Geometry:new{ w = self.width, h = self.rows_shown * self.row_h },
        show_parent = self.show_parent,
        step_scroll_grid_func = function() return self:_grid() end,
        self:_content(),
    }
    self[1] = FrameContainer:new{
        bordersize = 0, padding = 0, margin = 0,
        width = self.width, height = self.height,
        background = Blitbuffer.COLOR_WHITE,
        self.scroll,
    }
end

-- Ply i of the line is in row r, column 1 (White) or 2 (Black).
function PkMoveList:_cell(ply)
    local k = ply - 1 + (self.black_first and 1 or 0)
    return math.floor(k / 2) + 1, (k % 2) + 1
end

function PkMoveList:_rowCount()
    if #self.moves == 0 then return 0 end
    return (self:_cell(#self.moves))
end

function PkMoveList:_plyAt(row, col)
    local ply = (row - 1) * 2 + col - (self.black_first and 1 or 0)
    if ply >= 1 and ply <= #self.moves then return ply end
end

-- Rows for ScrollableContainer: a page scroll lands on a whole row.
function PkMoveList:_grid()
    local grid = {}
    for r = 1, self:_rowCount() do
        grid[r] = { top = (r - 1) * self.row_h, bottom = r * self.row_h - 1 }
    end
    return grid
end

-- A cell; the current move is framed by a thin black line (no grey: a
-- grey area redraws visibly under the e-ink's non-flashing refresh).
function PkMoveList:_cellWidget(text, w, face, current, right)
    local b = Size.border.thin
    local tw = TextWidget:new{ text = text, face = face, bold = current, max_width = w - 2 * Size.padding.small }
    return FrameContainer:new{
        bordersize = b, margin = 0, padding = 0,
        color = current and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE,
        padding_left = right and 0 or Size.padding.small - b,
        padding_right = right and Size.padding.small - b or 0,
        (right and RightContainer or LeftContainer):new{
            dimen = Geometry:new{ w = w - Size.padding.small - b, h = self.row_h - 2 * b }, tw },
    }
end

-- The table; rows that did not change are reused (a move or a step
-- changes one or two rows, even in a long line).
function PkMoveList:_content()
    local group = VerticalGroup:new{ align = "left" }
    local cache, kept = self._rows or {}, {}
    for row = 1, self:_rowCount() do
        local white, black = self:_plyAt(row, 1), self:_plyAt(row, 2)
        local number = tostring(self.first_number + row - 1)
        local w_text = white and self.moves[white] or "…"
        local b_text = black and self.moves[black] or ""
        local cur = (white and white == self.current and 1) or (black and black == self.current and 2) or 0
        local key = table.concat({ number, w_text, b_text, cur }, "\0")
        local widget = cache[key]
        if widget then
            cache[key] = nil
        else
            widget = HorizontalGroup:new{
                self:_cellWidget(number, self.num_w, self.number_face, false, true),
                self:_cellWidget(w_text, self.move_w, self.face, cur == 1),
                self:_cellWidget(b_text, self.move_w, self.face, cur == 2),
            }
        end
        kept[key] = widget
        group[#group + 1] = widget
    end
    for _, widget in pairs(cache) do widget:free() end -- rows gone or changed
    self._rows = kept
    if #group == 0 then
        group[1] = CenterContainer:new{ dimen = Geometry:new{ w = self.inner_w, h = self.row_h },
            TextWidget:new{ text = "", face = self.face } }
    end
    return group
end

--- Shows `moves` with `current` shaded, scrolled so that it is visible.
function PkMoveList:setMoves(moves, current)
    self.moves, self.current = moves, current or 0
    local offset = self.scroll:getScrolledOffset()
    self.scroll[1] = self:_content() -- (the old group's rows are reused or freed)
    self.scroll:reset() -- measured again at the next paint
    local top = math.floor(offset.y / self.row_h) + 1 -- first row shown
    if self.current > 0 then
        local row = self:_cell(self.current)
        if row < top then top = row
        elseif row >= top + self.rows_shown then top = row - self.rows_shown + 1 end
    end
    top = math.max(1, math.min(top, self:_rowCount() - self.rows_shown + 1))
    self.scroll:setScrolledOffset(Geometry:new{ x = 0, y = (top - 1) * self.row_h })
end

function PkMoveList:refresh()
    UIManager:setDirty(self.show_parent, PkRefresh.STEP, self.dimen.x and self.dimen or nil)
end

function PkMoveList:onTap(_, ges)
    if not self.dimen.x then return end
    local x = ges.pos.x - self.dimen.x
    local y = ges.pos.y - self.dimen.y + self.scroll:getScrolledOffset().y
    local row = math.floor(y / self.row_h) + 1
    local col = (x < self.num_w + self.move_w) and 1 or 2
    local ply = self:_plyAt(row, col)
    if ply and self.onSelect then self.onSelect(ply) end
    return true
end

return PkMoveList
