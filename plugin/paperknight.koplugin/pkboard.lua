-- pkboard.lua
local _ = require("gettext")
local logger = require("logger")
local Geom = require("ui/geometry")
local Blitbuffer = require("ffi/blitbuffer")
local PkButton = require("pkbutton")
local PkRefresh = require("pkrefresh")
local FrameContainer = require("ui/widget/container/framecontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Font = require("ui/font")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local Chess = require("pkchesslib/src/chess")
local Device = require("device")
local UIManager = require("ui/uimanager")
local Screen = Device.screen

local BOARD_SIZE = 8
local SELECTED_BORDER = 5
-- Paperknight: square colours, as the panel shows them (the board is
-- painted with their inverse in night mode, where the piece sets are also
-- swapped). Only the four DU4 grey levels (ADR-0018: 0x00,
-- 0x55, 0xAA, 0xFF), so that squares can be refreshed with DU4 (no flash,
-- pkrefresh.lua). The last move is not a tint any more but small triangles
-- in the four corners of its squares (`mark`), in black by day and white at
-- night, which read on both square colours.
local PALETTES = {
    day = {
        light = Blitbuffer.COLOR_WHITE,        -- 0xFF
        dark = Blitbuffer.Color8(0xAA),
        mark = Blitbuffer.COLOR_BLACK,         -- last-move corners
        -- study shapes ([%csl] circles, [%cal] arrows). Brush colours can't be
        -- told apart on e-ink, so all shapes share one style (docs/studies.md).
        shape = Blitbuffer.Color8(0x55),
    },
    night = {
        light = Blitbuffer.Color8(0x55),
        dark = Blitbuffer.COLOR_BLACK,
        mark = Blitbuffer.COLOR_WHITE,
        shape = Blitbuffer.Color8(0xAA),
    },
}
-- Thin frame around the squares, darker than the light squares, so the
-- white edge squares don't blend into the page.
local BOARD_BORDER_COLOR = Blitbuffer.Color8(0x55)
local BOARD_BORDER_SIZE = 2 -- scaled by screen DPI

local PkIcons = require("pkicons")
local icons = { empty = PkIcons.empty }
for piece, by_color in pairs(PkIcons.pieces) do icons[piece] = by_color end

-- The squares' grid (instead of a ButtonTable, which adds separators and
-- spacing the board doesn't want): getButtonById as on a ButtonTable.
local Grid = VerticalGroup:extend{ by_id = nil }
function Grid:getButtonById(id) return self.by_id[id] end

local Board = FrameContainer:extend{
    game = nil,
    width = 250,
    height = 250,
    moveCallback = nil,
    holdCallback = nil,
    onPromotionNeeded = nil, -- function(from, to, color): a pawn reaches the last rank (the view asks the piece)
    flipped = false, -- Paperknight: true shows the board from Black's side
    locked = false,  -- Paperknight: true ignores taps (e.g. puzzle finished, opponent thinking); set with setLocked
    show_turn = true, -- Paperknight: the corner disc shows the side to move while the board takes moves
    coordinates = true, -- Paperknight: draw a–h / 1–8 around the board
    padding = 0,
    bordersize = 0,  -- Paperknight: the grey frame is drawn around the squares only
    background = Blitbuffer.COLOR_WHITE,
    -- Paperknight: e-ink mode of the squares' refreshes (pkrefresh.lua)
    square_refresh = PkRefresh.STEP,
}

--- Board.palette(): colours for the current mode (night mode follows Screen),
-- as the panel shows them.
function Board.palette()
    return Screen.night_mode and PALETTES.night or PALETTES.day
end

--- Board.paintColor(color): value to paint so the panel shows `color`.
function Board.paintColor(color)
    return Screen.night_mode and color:invert() or color
end

function Board:getSize()
    return Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
end

function Board:init()
    if not self.game then
        logger.error("Chess: must be initialized with a Game object")
        return
    end

    local margins = self:allMarginSizes()
    self.button_size = math.min(
        math.floor(self.width / (BOARD_SIZE + 1)) - margins.w,
        math.floor(self.height / (BOARD_SIZE + 1)) - margins.h
    )

    self.selected = nil
    logger.dbg(string.format("Initializing board: %dx%d, button size: %d", self.width, self.height, self.button_size))

    self.highlighted = {}
    local grid = {}
    for row_idx = 0, BOARD_SIZE - 1 do
        -- Top row is rank 8 (index 7) normally, rank 1 (index 0) when flipped
        local rank = self.flipped and row_idx or (BOARD_SIZE - 1 - row_idx)
        local row = {}
        for col_idx = 0, BOARD_SIZE - 1 do
            local file = self.flipped and (BOARD_SIZE - 1 - col_idx) or col_idx
            table.insert(row, self:createSquareButton(file, rank))
        end
        table.insert(grid, row)
    end

    -- the 8x8 squares: rows of buttons, no separators; buttons found by id
    self.table = Grid:new{ align = "left", by_id = {} }
    for _, row in ipairs(grid) do
        local hgroup = HorizontalGroup:new{ align = "top" }
        for _, entry in ipairs(row) do
            local button = PkButton:new(entry)
            self.table.by_id[entry.id] = button
            hgroup[#hgroup + 1] = button
        end
        self.table[#self.table + 1] = hgroup
    end

    self:applySquareColors()
    for rank = 0, BOARD_SIZE - 1 do
        for file = 0, BOARD_SIZE - 1 do
            self:_showIcon(self.table:getButtonById(Board.toId(file, rank)))
        end
    end
    local framed = FrameContainer:new{
        bordersize = Screen:scaleBySize(BOARD_BORDER_SIZE),
        color = BOARD_BORDER_COLOR,
        padding = 0,
        margin = 0,
        self.table,
    }
    local content = self.coordinates and self:_withCoordinates(framed) or framed
    -- something on the right (the analysis move list): the board is as wide
    -- as what it draws, not the width it was given
    if self.centre_squares == false then self.width = content:getSize().w end
    self[1] = CenterContainer:new{
        dimen = self:getSize(),
        content,
    }

    logger.dbg("Chess board initialized")
end

--- Board:_withCoordinates(framed)
-- Paperknight: rank numbers on the left, file letters below, in the spare
-- margin (button_size leaves about one square of room). Follows `flipped`.
function Board:_withCoordinates(framed)
    local border = Screen:scaleBySize(BOARD_BORDER_SIZE)
    local face = Font:getFace("infont", 14) -- size is DPI-scaled by KOReader
    -- at least one text line high, so small boards don't overlap the labels
    local label_w = math.max(math.floor(self.button_size * 0.35), face.size + Screen:scaleBySize(2))
    self._label_w, self._border = label_w, border -- the corner cell (turn marker)
    local function label(text, w, h)
        return CenterContainer:new{
            dimen = Geom:new{ w = w, h = h },
            TextWidget:new{ text = text, face = face, fgcolor = Blitbuffer.COLOR_BLACK },
        }
    end
    local ranks = VerticalGroup:new{}
    table.insert(ranks, label("", label_w, border))
    for row_idx = 0, BOARD_SIZE - 1 do
        local rank = self.flipped and row_idx or (BOARD_SIZE - 1 - row_idx)
        table.insert(ranks, label(tostring(rank + 1), label_w, self.button_size))
    end
    local files = HorizontalGroup:new{}
    table.insert(files, label("", border, label_w))
    for col_idx = 0, BOARD_SIZE - 1 do
        local file = self.flipped and (BOARD_SIZE - 1 - col_idx) or col_idx
        table.insert(files, label(string.char(97 + file), self.button_size, label_w))
    end
    return HorizontalGroup:new{
        align = "top",
        ranks,
        VerticalGroup:new{ align = "left", framed, files },
        -- keeps the squares centred; not when something sits on the right
        -- (the analysis move list)
        self.centre_squares ~= false and label("", label_w, label_w) or nil,
    }
end

function Board:createSquareButton(file, rank)
    return {
        id = Board.toId(file, rank),
        icon = icons.empty,
        alpha = true,
        width = self.button_size,
        height = self.button_size,
        icon_width = self.button_size,
        icon_height = self.button_size,
        bordersize = 0,
        margin = 0,
        padding = 0,
        padding_h = 0,
        allow_hold_when_disabled = true,
        no_feedback = true, -- the selection border is the feedback (pkbutton.lua)
        callback = function() self:handleClick(file, rank) end,
        hold_callback = self.holdCallback,
    }
end

-- An empty square's icon is a transparent SVG: hidden, it is not
-- alpha-blended on every paint (about half the board).
function Board:_showIcon(button)
    if button.label_widget then button.label_widget.hide = (button.icon == icons.empty) end
end

function Board:applySquareColors()
    self._night = Screen.night_mode
    for rank = 0, BOARD_SIZE - 1 do
        for file = 0, BOARD_SIZE - 1 do
            local button = self.table:getButtonById(Board.toId(file, rank))
            button.frame.background = self:squareColor(string.char(97 + file) .. (rank + 1))
        end
    end
end

--- Board:handleClick(file, rank)
-- Handles a tap event on a chess board square.
-- Manages piece selection and initiates move attempts.
-- @param file Number, the 0-indexed file of the tapped square.
-- @param rank Number, the 0-indexed rank of the tapped square.
function Board:handleClick(file, rank)
    if self.locked then return end
    local id = Board.toId(file, rank)
    local square = Board.idToPosition(id) -- Chess algebraic notation (e.g., "e4")
    logger.dbg("Paperknight: square tapped", square)

    if self.selected then
        -- A piece is already selected, this click is a move attempt
        local target = self.game.get(square)
        if self.selected == square then
            -- Clicked the same square again, unselect it
            self:unmarkSelected(square)
            self.selected = nil
        elseif target and target.color == self.game.turn() then
            -- Paperknight: another piece of the side to move: select it instead
            -- (a move onto an own piece is never legal)
            local previous = self.selected
            self.selected = square
            self.selected_mark = square
            self:_repaintSquare(previous)
            self:_repaintSquare(square)
        else
            -- Attempt to move the selected piece to the new square
            self:handleMove(self.selected, square)
        end
    else
        -- No piece is selected, try to select one
        local piece = self.game.get(square)
        -- Only allow selection if there's a piece and it's the current player's turn
        if piece and piece.color == self.game.turn() then
            logger.dbg("Chess select piece " .. piece.type .. " at " .. square)
            self.selected = square
            self:markSelected(square)
        end
    end
end

--- Board:handleMove(from, to)
-- Attempts to make a move from 'from' square to 'to' square.
-- Includes logic for pawn promotion.
-- @param from String, algebraic notation of the starting square.
-- @param to String, algebraic notation of the destination square.
function Board:handleMove(from, to)
    self:unmarkSelected(from) -- Always unmark the selected piece after a move attempt
    self.selected = nil        -- Clear selection

    local piece = self.game.get(from) -- Get the piece that is moving

    -- Check for pawn promotion:
    -- 1. Is the piece a pawn?
    -- 2. Is the destination rank a promotion rank for its color?
    local is_pawn_promotion = false
    if piece and piece.type == Chess.PAWN then
        local to_rank_num = tonumber(to:sub(2, 2)) -- Extract rank number from 'to' square (e.g., '8' from "e8")
        if (piece.color == Chess.WHITE and to_rank_num == 8) or
           (piece.color == Chess.BLACK and to_rank_num == 1) then
            is_pawn_promotion = true
        end
    end

    if is_pawn_promotion then
        -- Paperknight: only offer the promotion dialog for a legal move
        local legal = false
        for _, m in ipairs(self.game.moves({ square = from, verbose = true })) do
            if m.to == to then legal = true; break end
        end
        is_pawn_promotion = legal
    end

    if is_pawn_promotion and self.onPromotionNeeded then
        -- a promotion: the view asks for the piece (onPromotionNeeded), then plays the move
        logger.dbg(string.format("Pawn promotion detected: %s pawn from %s to %s. Triggering promotion dialog.", piece.color, from, to))
        self.onPromotionNeeded(from, to, piece.color)
    else
        -- If not a promotion, or no promotion callback provided, proceed with a normal move.
        local move = self.game.move{ from = from, to = to }
        if move then
            self:handleGameMove(move)
        else
            -- Move was illegal (e.g., wrong piece, blocked, etc.)
            logger.dbg("Paperknight: illegal move", from, to)
            -- Re-render the board to revert any temporary visual changes for the illegal move
            self:updateBoard()
        end
    end
end

--- Board:handleGameMove(move)
-- Processes a successfully executed chess move (from game logic).
-- Updates the board visually and triggers the main move callback in Paperknight.
-- @param move Table, the move object returned by ChessGame.move().
function Board:handleGameMove(move)
    if not move then return end -- Should not happen if called with a valid move

    logger.dbg("Applying game move to board visuals: " .. move.san)
    self:showMove(move)

    if self.moveCallback then
        self.moveCallback(move) -- Notify Paperknight.lua that the move has completed
    end
    self:_syncTurnMarker() -- (the view may have locked the board, or taken the move back)
end

--- Board:showMove(move)
-- Paperknight: redraws the squares a move touched, without invoking moveCallback
-- (for moves played by the program: engine, puzzle replies, solutions).
function Board:showMove(move)
    self:updateSquare(move.from)
    self:updateSquare(move.to)
    -- Special moves (en passant, castling) affect other squares
    self:handleMoveFlags(move, move.to)
    self:_syncTurnMarker()
end

--- Board:setShapes(shapes)
-- Paperknight: { circles = { {square=}, ... }, arrows = { {from=, to=}, ... } }
-- drawn over the squares on the next paint (nil clears them).
-- The squares under the old and new shapes are
-- refreshed (an arrow: the rectangle between its ends), when they changed.
function Board:setShapes(shapes)
    local function key(s)
        if not s then return "" end
        local parts = {}
        for _, c in ipairs(s.circles or {}) do parts[#parts + 1] = "c" .. c.square end
        for _, a in ipairs(s.arrows or {}) do parts[#parts + 1] = "a" .. a.from .. a.to end
        return table.concat(parts, " ")
    end
    if key(shapes) == key(self.shapes) then
        self.shapes = shapes
        return
    end
    local old = self.shapes
    self.shapes = shapes
    for _, s in ipairs({ old or {}, shapes or {} }) do
        for _, c in ipairs(s.circles or {}) do self:_refreshSquare(c.square) end
        for _, a in ipairs(s.arrows or {}) do self:_refreshSquare(a.from); self:_refreshSquare(a.to) end
    end
end

-- Adds a square to the pending square refresh.
function Board:_refreshSquare(square)
    local id = Board.chessToId(square)
    if id then self:_refreshButton(self.table:getButtonById(id), self:_screenRect(square)) end
end

function Board:paintTo(bb, x, y)
    -- night mode toggled since the last paint: switch palettes and piece sets
    -- (no per-square refresh: the whole board is being painted)
    if self._night ~= Screen.night_mode then
        self:updateBoard(true)
        self:applySquareColors()
    end
    FrameContainer.paintTo(self, bb, x, y)
    self._shape_color = Board.paintColor(Board.palette().shape)
    if self.highlighted and next(self.highlighted) then self:_paintHighlights(bb) end
    if self.shapes then self:_paintShapes(bb) end
    if self.badge then self:_paintBadge(bb) end
    if self.selected_mark and not self.locked then self:_paintSelection(bb) end
    self:_cacheRects()
    if self.turn_marker then self:_paintTurnMarker(bb) end
end

--- Board:setLocked(locked): taps ignored or not; the turn marker follows.
function Board:setLocked(locked)
    self.locked = locked and true or false
    self:_syncTurnMarker()
end

-- The turn marker follows the board itself: the side to move while the
-- board takes moves (unlocked, game not over); hidden otherwise (the
-- opponent or the engine to move, a finished puzzle, a replay). Every mode
-- gets it this way: the views only lock and unlock the board.
function Board:_syncTurnMarker()
    local game = self.game
    local color = self.show_turn and not self.locked and game and not game.game_over() and game.turn() or nil
    self:setTurnMarker(color)
end

--- Board:setTurnMarker(color): a disc in the empty corner cell left of the
-- file letters ("w": hollow, "b": filled, swapped in night mode like the
-- side markers of pkside.lua), saying whose move it is; nil hides it.
-- Its cell joins the board's refresh.
function Board:setTurnMarker(color)
    if color == self.turn_marker then return end
    self.turn_marker = color
    -- in the update's single board refresh (a DU4 partial update drives
    -- only the pixels that changed: a larger rectangle costs nothing)
    local r = self:_markerRect()
    if r then self:_refreshButton(nil, r) end
end

-- The marker's square on screen (after a paint), or nil.
function Board:_markerRect()
    if not self._label_w then return nil end -- no coordinates: no corner cell
    local s = self:_screenRect(self.flipped and "h8" or "a1") -- the bottom-left square
    if not s then return nil end
    local lw = self._label_w
    local d = math.max(6, math.floor(lw * 0.8))
    local cx = s.x - self._border - math.floor(lw / 2)
    local cy = s.y + s.h + self._border + math.floor(lw / 2)
    return Geom:new{ x = cx - math.floor(d / 2), y = cy - math.floor(d / 2), w = d, h = d }
end

function Board:_paintTurnMarker(bb)
    local r = self:_markerRect()
    if not r then return end
    -- drawn in the framebuffer's own black (not Board.paintColor): night
    -- mode inverts it, so that the filled disc stays the light side's there
    local filled = (self.turn_marker == "b") ~= (Screen.night_mode == true)
    local radius = math.floor(r.w / 2)
    if filled then
        bb:paintRoundedRect(r.x, r.y, r.w, r.h, Blitbuffer.COLOR_BLACK, radius)
    else
        bb:paintRoundedRect(r.x, r.y, r.w, r.h, Blitbuffer.COLOR_WHITE, radius)
        bb:paintBorder(r.x, r.y, r.w, r.h, math.max(2, math.floor(r.w / 7)), Blitbuffer.COLOR_BLACK, radius)
    end
end

-- Screen rectangles of the squares, as just painted (see _refreshButton).
-- Square names by id, computed once (the cache runs on every paint).
local SQUARE_NAMES = {}

function Board:_cacheRects()
    self._rects = self._rects or {}
    local rects = self._rects
    for file = 0, BOARD_SIZE - 1 do
        for rank = 0, BOARD_SIZE - 1 do
            local id = Board.toId(file, rank)
            local name = SQUARE_NAMES[id]
            if not name then
                name = Board.idToPosition(id)
                SQUARE_NAMES[id] = name
            end
            local button = self.table:getButtonById(id)
            local d = button and button[1] and button[1].dimen -- the painted frame (as Button:refresh)
            if d and d.w then
                local r = rects[name]
                if r then -- updated in place: no new objects per paint
                    r.x, r.y, r.w, r.h = d.x, d.y, d.w, d.h
                else
                    rects[name] = Geom:new{ x = d.x, y = d.y, w = d.w, h = d.h }
                end
            end
        end
    end
end

-- Paperknight: move-mark badge ("!!", "?"…) on a square, like Lichess. Good
-- marks are a filled black disc with white text, bad ones a white disc with
-- a black ring: told apart without colours on e-ink. "✓" (puzzle solved) is
-- drawn as a tick, not as text (fonts may lack the glyph).
local TICK = "✓"
local GOOD_MARKS = { ["!"] = true, ["!!"] = true, ["!?"] = true, [TICK] = true }
Board.TICK = TICK

--- Board:setBadge(square, text): shows `text` in the top-right corner of
-- `square`; setBadge(nil) removes it. The caller repaints.
-- The old and new badge squares are refreshed.
function Board:setBadge(square, text)
    local old = self.badge and self.badge.square
    self.badge = (square and text) and { square = square, text = text } or nil
    for _, sq in pairs({ old = old, new = square }) do self:_refreshSquare(sq) end
end

function Board:_paintBadge(bb)
    local r = self:_squareRect(self.badge.square)
    if not r then return end
    local d = math.floor(self.button_size * 0.32)
    local bx, by = r.x + r.w - d, r.y
    local good = GOOD_MARKS[self.badge.text]
    local black, white = Board.paintColor(Blitbuffer.COLOR_BLACK), Board.paintColor(Blitbuffer.COLOR_WHITE)
    bb:paintRoundedRect(bx, by, d, d, good and black or white, math.floor(d / 2))
    if not good then
        bb:paintBorder(bx, by, d, d, math.max(2, math.floor(d / 10)), black, math.floor(d / 2))
    end
    if self.badge.text == TICK then
        local t = math.max(2, math.floor(d * 0.13))
        self:_paintSegment(bb, bx + d * 0.27, by + d * 0.52, bx + d * 0.43, by + d * 0.68, t, white)
        self:_paintSegment(bb, bx + d * 0.43, by + d * 0.68, bx + d * 0.73, by + d * 0.34, t, white)
        return
    end
    -- font sizes are scaled by screen DPI: convert the wanted pixel height
    -- the label is shaped once per badge (not on every board paint)
    local key = self.badge.text .. "|" .. d .. "|" .. tostring(Screen.night_mode)
    if self._badge_key ~= key then
        if self._badge_label then self._badge_label:free() end
        local px = d * 0.62
        local face = Font:getFace("infont", math.max(6, math.floor(px * 1000 / Screen:scaleBySize(1000))))
        self._badge_label = TextWidget:new{ text = self.badge.text, face = face, bold = true,
                                            fgcolor = good and white or black }
        self._badge_key = key
    end
    local label = self._badge_label
    local size = label:getSize()
    label:paintTo(bb, bx + math.floor((d - size.w) / 2), by + math.floor((d - size.h) / 2))
end

function Board:_squareRect(square)
    local id = Board.chessToId(square)
    local button = id and self.table:getButtonById(id)
    return button and button.dimen
end

function Board:_paintShapes(bb)
    local ring = math.max(2, math.floor(self.button_size / 14))
    for _, c in ipairs(self.shapes.circles or {}) do
        local r = self:_squareRect(c.square)
        if r then
            local inset = math.floor(self.button_size / 12)
            local w = r.w - 2 * inset
            bb:paintBorder(r.x + inset, r.y + inset, w, w, ring, self._shape_color, math.floor(w / 2))
        end
    end
    local thick = math.max(3, math.floor(self.button_size / 9))
    for _, a in ipairs(self.shapes.arrows or {}) do
        local r1, r2 = self:_squareRect(a.from), self:_squareRect(a.to)
        if r1 and r2 then
            self:_paintArrow(bb, r1.x + r1.w / 2, r1.y + r1.h / 2, r2.x + r2.w / 2, r2.y + r2.h / 2, thick)
        end
    end
end

-- Thick line ending in a filled head, drawn by stamping small squares
-- (Blitbuffer has no line primitive).
function Board:_paintArrow(bb, x1, y1, x2, y2, thick)
    local dx, dy = x2 - x1, y2 - y1
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 1 then return end
    local ux, uy = dx / len, dy / len
    local head = math.min(len * 0.45, self.button_size * 0.45)
    self:_paintSegment(bb, x1, y1, x1 + ux * (len - head), y1 + uy * (len - head), thick, self._shape_color)
    -- head: filled triangle, one horizontal span per scanline
    local px, py = -uy, ux
    local base_half = thick * 1.6
    local bx, by = x2 - ux * head, y2 - uy * head
    self:_fillTriangle(bb, x2, y2, bx + px * base_half, by + py * base_half,
        bx - px * base_half, by - py * base_half)
end

-- Thick line: overlapping squares every half thickness (cheap on slow CPUs).
function Board:_paintSegment(bb, x1, y1, x2, y2, thick, color)
    local dx, dy = x2 - x1, y2 - y1
    local len = math.sqrt(dx * dx + dy * dy)
    local ux, uy = 0, 0
    if len > 0 then ux, uy = dx / len, dy / len end
    local half = math.floor(thick / 2)
    local step = math.max(1, math.floor(half / 2))
    for i = 0, math.floor(len), step do
        bb:paintRect(math.floor(x1 + ux * i) - half, math.floor(y1 + uy * i) - half, thick, thick, color)
    end
    bb:paintRect(math.floor(x2) - half, math.floor(y2) - half, thick, thick, color)
end

function Board:_fillTriangle(bb, ax, ay, bx, by, cx, cy, color)
    color = color or self._shape_color
    local pts = { { ax, ay }, { bx, by }, { cx, cy } }
    local ymin = math.floor(math.min(ay, by, cy))
    local ymax = math.ceil(math.max(ay, by, cy))
    for y = ymin, ymax do
        local yc = y + 0.5
        local xs = {}
        for i = 1, 3 do
            local p1, p2 = pts[i], pts[i % 3 + 1]
            if (p1[2] <= yc and p2[2] > yc) or (p2[2] <= yc and p1[2] > yc) then
                xs[#xs + 1] = p1[1] + (yc - p1[2]) * (p2[1] - p1[1]) / (p2[2] - p1[2])
            end
        end
        if #xs == 2 then
            local x0, x1 = math.floor(math.min(xs[1], xs[2])), math.ceil(math.max(xs[1], xs[2]))
            bb:paintRect(x0, y, x1 - x0 + 1, 1, color)
        end
    end
end

--- Board:setHighlights(squares)
-- Paperknight: tint the given squares (e.g. the last move), replacing
-- previous highlights.
function Board:setHighlights(squares)
    local old = self.highlighted
    self.highlighted = {}
    for _, sq in ipairs(squares or {}) do self.highlighted[sq] = true end
    for sq in pairs(old) do
        if not self.highlighted[sq] then self:_applyBackground(sq) end
    end
    for sq in pairs(self.highlighted) do self:_applyBackground(sq) end
end

--- Board:squareColor(square): background to paint for a square, highlight included.
function Board:squareColor(square)
    -- (highlighted squares keep their colour: corner triangles, paintTo)
    return Board.paintColor(Board.positionToColor(square))
end

-- The last move's squares: a small triangle in each corner (no tint: the
-- squares keep their DU4 grey).
function Board:_paintHighlights(bb)
    local color = Board.paintColor(Board.palette().mark)
    local t = math.max(4, math.floor(self.button_size * 0.24)) -- the triangles' legs
    for sq in pairs(self.highlighted) do
        local r = self:_squareRect(sq)
        if r and r.w then
            local x0, y0, x1, y1 = r.x, r.y, r.x + r.w, r.y + r.h
            self:_fillTriangle(bb, x0, y0, x0 + t, y0, x0, y0 + t, color)
            self:_fillTriangle(bb, x1, y0, x1 - t, y0, x1, y0 + t, color)
            self:_fillTriangle(bb, x0, y1, x0 + t, y1, x0, y1 - t, color)
            self:_fillTriangle(bb, x1, y1, x1 - t, y1, x1, y1 - t, color)
        end
    end
end

function Board:_applyBackground(square)
    local id = Board.chessToId(square)
    if not id then return end
    local button = self.table:getButtonById(id)
    button.frame.background = self:squareColor(square)
    self:_refreshButton(button, self:_screenRect(square))
end

-- Screen rectangle of a square, from the last paint (nil before it).
-- Button:setIcon rebuilds the frame, which loses its position until the next
-- paint: hence the cache.
function Board:_screenRect(square)
    return self._rects and self._rects[square]
end

--- Paperknight: e-ink update of a square whose content changed, with the
-- `square_refresh` mode (PkRefresh.STEP: never promoted to a flash,
-- pkrefresh.lua). `rect`: the square on screen (nil before the first paint:
-- then the whole window, which is being shown anyway).
-- The squares changed by one update (a move, its highlights, a badge, the
-- shapes) are refreshed together: one refresh of the rectangle around them,
-- sent after painting, since separate refreshes run one after the other on
-- the e-ink controller. REAGL redraws every pixel of the region: the text
-- below the board is refreshed apart (docs/eink-refresh.md).
function Board:_refreshButton(button, rect)
    if not rect then return UIManager:setDirty(self.show_parent or self, self.square_refresh) end
    if self._batch then
        self._batch = self._batch:combine(rect)
        return
    end
    self._batch = rect:copy() -- the cached rect is updated in place at each paint
    UIManager:setDirty(self.show_parent or self, function()
        local region = self._batch
        self._batch = nil
        return PkRefresh.boardRegion(self.square_refresh, region)
    end)
end

--- Board:handleMoveFlags(move, to)
-- Handles visual updates for special move types (en passant, castling).
-- @param move Table, the move object.
-- @param to String, the destination square of the main piece.
function Board:handleMoveFlags(move, to)
    if not move.flags then return end

    if not Board.chessToId(to) then
        logger.info("Chess: invalid destination square for move flags:", tostring(to))
        return
    end

    if move.flags == Chess.FLAGS.EP_CAPTURE then
        -- En passant: the captured pawn is on the file of the 'to' square and
        -- the rank of the 'from' square (ids are file * 8 + rank: build the
        -- square from its name, not by id arithmetic)
        self:updateSquare(to:sub(1, 1) .. move.from:sub(2, 2))
    elseif move.flags == Chess.FLAGS.KSIDE_CASTLE then
        -- Kingside castling: King moves two squares, Rook moves to inner square
        -- Rook original square: h1 for White, h8 for Black
        -- Rook destination square: f1 for White, f8 for Black
        local rook_from_file_id = 7 -- 0-indexed 'h'
        local rook_to_file_id = 5 -- 0-indexed 'f'
        local rank_index = (move.color == Chess.WHITE and 0 or 7) -- 0-indexed rank 1 or 8
        self:updateSquare(Board.idToPosition(Board.toId(rook_from_file_id, rank_index)))
        self:updateSquare(Board.idToPosition(Board.toId(rook_to_file_id, rank_index)))
    elseif move.flags == Chess.FLAGS.QSIDE_CASTLE then
        -- Queenside castling: King moves two squares, Rook moves to inner square
        -- Rook original square: a1 for White, a8 for Black
        -- Rook destination square: d1 for White, d8 for Black
        local rook_from_file_id = 0 -- 0-indexed 'a'
        local rook_to_file_id = 3 -- 0-indexed 'd'
        local rank_index = (move.color == Chess.WHITE and 0 or 7) -- 0-indexed rank 1 or 8
        self:updateSquare(Board.idToPosition(Board.toId(rook_from_file_id, rank_index)))
        self:updateSquare(Board.idToPosition(Board.toId(rook_to_file_id, rank_index)))
    end
end

--- Board:markSelected(square) / unmarkSelected(square)
-- Paperknight: the selected square gets a frame drawn *inside* the square by
-- the board's overlay (paintTo). Changing the button's own border made its
-- frame larger than the square: it painted over the neighbours and left
-- pieces of border behind when removed.
function Board:markSelected(square)
    if not Board.chessToId(square) then
        logger.info("Chess: Invalid square to select: " .. tostring(square))
        return
    end
    self.selected_mark = square
    self:_repaintSquare(square)
end

function Board:unmarkSelected(square)
    if self.selected_mark == nil then return end
    self.selected_mark = nil
    self:_repaintSquare(square)
end

-- Repaints the board and refreshes only `square` on screen (the overlays are
-- drawn by paintTo, so the whole window is painted, but the e-ink refresh is
-- limited to the square).
function Board:_repaintSquare(square)
    -- in the update's single refresh (switching the selection to another
    -- piece is one refresh, not two in a row)
    if square then return self:_refreshSquare(square) end
    UIManager:setDirty(self.show_parent or self, self.square_refresh, self.dimen)
end

--- Removes the selection (e.g. before the board is locked).
function Board:clearSelection()
    local square = self.selected_mark
    self.selected, self.selected_mark = nil, nil
    if square then self:_repaintSquare(square) end
end

function Board:_paintSelection(bb)
    local r = self:_squareRect(self.selected_mark)
    if not (r and r.w) then return end
    -- stored black: shown black, or white once night mode inverts the screen
    bb:paintBorder(r.x, r.y, r.w, r.h, Screen:scaleBySize(SELECTED_BORDER), Blitbuffer.COLOR_BLACK)
end

--- Board:placePiece(square, piece, color)
-- Places or removes a piece icon on a specific board square.
-- @param square String, algebraic notation of the square.
-- @param piece String, the piece type (e.g., Chess.PAWN, Chess.QUEEN) or nil to clear.
-- @param color String, the piece color (Chess.WHITE or Chess.BLACK), only required if `piece` is not nil.
function Board:placePiece(square, piece, color, no_refresh)
    -- night mode inverts the screen: show the other set, inverted
    if Screen.night_mode and color then color = (color == "w") and "b" or "w" end
    local icon = (piece and icons[piece] and icons[piece][color]) or icons.empty
    local id_result = Board.chessToId(square)
    if not id_result then
        logger.warn("Paperknight: placePiece on an invalid square:", square, piece)
        return
    end
    local button = self.table:getButtonById(id_result)
    -- Paperknight: skip unchanged squares; each refresh is an e-ink update
    if button.icon == icon then return end
    local rect = self:_screenRect(square)
    button:swapIcon(icon) -- the icon only: the frame and its position stay
    self:_showIcon(button)
    button.frame.background = self:squareColor(square)
    if not no_refresh then self:_refreshButton(button, rect) end
end

--- Board:updateSquare(square)
-- Refreshes the display of a single square based on the current game state.
-- @param square String, algebraic notation of the square to update.
function Board:updateSquare(square)
    local piece = self.game.get(square)
    if piece then
        self:placePiece(square, piece.type, piece.color)
    else
        self:placePiece(square) -- Clear the square
    end
end

--- Board:updateBoard()
-- Refreshes the entire chess board display based on the current game state.
function Board:updateBoard(no_refresh)
    logger.dbg("Chess: Update entire board")
    local board_fen = self.game.board() -- Get the current board state from the game logic
    for file_idx = 0, BOARD_SIZE - 1 do
        for rank_idx = 0, BOARD_SIZE - 1 do
            -- Chess.js-like board structure: board[rank][file]
            -- Ranks are 1-8, files are a-h. Lua arrays are 1-indexed.
            -- So, board[BOARD_SIZE - rank_idx] corresponds to board ranks 8 down to 1.
            -- board[file_idx + 1] corresponds to files 'a' through 'h'.
            local element = board_fen[BOARD_SIZE - rank_idx][file_idx + 1]
            local square = Board.idToPosition(Board.toId(file_idx, rank_idx))
            if element then
                self:placePiece(square, element.type, element.color, no_refresh)
            else
                self:placePiece(square, nil, nil, no_refresh) -- Clear the square if no piece
            end
        end
    end
    if not no_refresh then self:_syncTurnMarker() end
end

-- Utility functions for square conversions
--- Board.toId(file, rank)
-- Converts 0-indexed file and rank to a unique linear ID.
-- @param file Number, 0-indexed file (0-7 for 'a'-'h').
-- @param rank Number, 0-indexed rank (0-7 for '1'-'8').
-- @return Number, unique ID.
function Board.toId(file, rank)
    return file * BOARD_SIZE + rank
end

--- Board.chessToId(position)
-- Converts chess algebraic notation (e.g., "e4") to a linear ID.
-- @param position String, algebraic notation.
-- @return id or nil
function Board.chessToId(position)
    if type(position) == "string" and #position == 2 then
        local file_char = position:sub(1, 1)
        local rank_char = position:sub(2, 2)
        if 'a' <= file_char and file_char <= 'h' and '1' <= rank_char and rank_char <= '8' then
            local file_idx = string.byte(file_char) - string.byte('a')
            local rank_idx = tonumber(rank_char) - 1
            return Board.toId(file_idx, rank_idx)
        end
    end
    return nil
end

--- Board.idToPosition(id)
-- Converts a linear ID back to chess algebraic notation.
-- @param id Number, the linear ID.
-- @return position or nil
function Board.idToPosition(id)
    if type(id) == "number" and id >= 0 and id < BOARD_SIZE * BOARD_SIZE then
        local file_idx = math.floor(id / BOARD_SIZE)
        local rank_idx = id % BOARD_SIZE
        local file_char = string.char(file_idx + string.byte('a'))
        local rank_char = tostring(rank_idx + 1) -- Convert 0-indexed rank to 1-indexed chess rank
        return file_char .. rank_char
    end
    return nil
end

--- Board.positionToColor(position)
-- Determines the background color of a square based on its algebraic position.
-- @param position String, algebraic notation (e.g., "e4").
-- @return the light or dark square colour of the current palette.
function Board.positionToColor(position)
    local id = Board.chessToId(position)
    if not id then return nil end
    local palette = Board.palette()
    return (math.floor(id / BOARD_SIZE) + id % BOARD_SIZE) % 2 == 1 and palette.light or palette.dark
end

function Board:allMarginSizes()
    self._padding_top = self.padding_top or self.padding
    self._padding_right = self.padding_right or self.padding
    self._padding_bottom = self.padding_bottom or self.padding
    self._padding_left = self.padding_left or self.padding
    return Geom:new{
        w = (self.margin + self.bordersize) * 2 + self._padding_right + self._padding_left,
        h = (self.margin + self.bordersize) * 2 + self._padding_top + self._padding_bottom,
    }
end

return Board
