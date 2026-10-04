-- board.lua
local _ = require("gettext")
local logger = require("logger")
local Geom = require("ui/geometry")
local Blitbuffer = require("ffi/blitbuffer")
local ButtonTable = require("buttontable")
local FrameContainer = require("ui/widget/container/framecontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Font = require("ui/font")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local Chess = require("chess/src/chess")
local Device = require("device")
local UIManager = require("ui/uimanager")
local Screen = Device.screen

local BOARD_SIZE = 8
local SELECTED_BORDER = 5
-- Paperknight: square colours. E-ink shows 16 grey levels (steps of 0x11);
-- light squares are white and dark squares a light grey so pieces stay crisp.
-- The last-move tint sits two levels from both (a border would be partly
-- painted over by neighbouring squares in the ButtonTable).
local LIGHT_SQUARE = Blitbuffer.COLOR_WHITE      -- 0xFF
local DARK_SQUARE = Blitbuffer.COLOR_GRAY_B      -- 0xBB
local HIGHLIGHT_COLOR = Blitbuffer.COLOR_GRAY_D  -- 0xDD
-- Thin frame around the squares, a bit darker than the dark squares, so the
-- white edge squares don't blend into the page.
local BOARD_BORDER_COLOR = Blitbuffer.COLOR_DARK_GRAY -- 0x88
local BOARD_BORDER_SIZE = 2 -- scaled by screen DPI
-- Study shapes ([%csl] circles, [%cal] arrows). Brush colours can't be told
-- apart on e-ink, so all shapes share one dark style (docs/studies.md).
local SHAPE_COLOR = Blitbuffer.COLOR_GRAY_4

local PkIcons = require("pkicons")
local icons = { empty = PkIcons.empty }
for piece, by_color in pairs(PkIcons.pieces) do icons[piece] = by_color end

local Board = FrameContainer:extend{
    game = nil,
    width = 250,
    height = 250,
    moveCallback = nil,
    holdCallback = nil,
    onPromotionNeeded = nil, -- NEW: Callback for when a pawn promotion is detected
    flipped = false, -- Paperknight: true shows the board from Black's side
    locked = false,  -- Paperknight: true ignores taps (e.g. puzzle finished, opponent thinking)
    coordinates = true, -- Paperknight: draw a–h / 1–8 around the board
    padding = 0,
    bordersize = 0,  -- Paperknight: the grey frame is drawn around the squares only
    background = Blitbuffer.COLOR_WHITE,
}

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

    self.table = ButtonTable:new{
        buttons = grid,
        width = BOARD_SIZE * self.button_size, -- Paperknight: exactly 8 squares, no side margins
        shrink_unneeded_width = false,
        zero_sep = true,
        sep_width = 0,
        addVerticalSpan = function() end, -- No vertical spacing between rows
    }

    self:applySquareColors()
    local framed = FrameContainer:new{
        bordersize = Screen:scaleBySize(BOARD_BORDER_SIZE),
        color = BOARD_BORDER_COLOR,
        padding = 0,
        margin = 0,
        self.table,
    }
    self[1] = CenterContainer:new{
        dimen = self:getSize(),
        self.coordinates and self:_withCoordinates(framed) or framed,
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
        label("", label_w, label_w), -- keeps the squares centred
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
        callback = function() self:handleClick(file, rank) end,
        hold_callback = self.holdCallback,
    }
end

function Board:applySquareColors()
    for rank = 0, BOARD_SIZE - 1 do
        for file = 0, BOARD_SIZE - 1 do
            local button = self.table:getButtonById(Board.toId(file, rank))
            button.frame.background = ((file + rank) % 2 == 1)
                and LIGHT_SQUARE
                or DARK_SQUARE
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
    logger.dbg("Chess click on square: " .. square)

    if self.selected then
        -- A piece is already selected, this click is a move attempt
        if self.selected == square then
            -- Clicked the same square again, unselect it
            self:unmarkSelected(square)
            self.selected = nil
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

    if is_pawn_promotion and self.onPromotionNeeded then
        -- If it's a promotion and we have a callback, defer the move to Paperknight.lua.
        -- Paperknight.lua will then prompt for the promotion piece and call game.move().
        logger.dbg(string.format("Pawn promotion detected: %s pawn from %s to %s. Triggering promotion dialog.", piece.color, from, to))
        self.onPromotionNeeded(from, to, piece.color)
        -- IMPORTANT: Do NOT call self.game.move() here. Paperknight will handle it after selection.
    else
        -- If not a promotion, or no promotion callback provided, proceed with a normal move.
        local move = self.game.move{ from = from, to = to }
        if move then
            self:handleGameMove(move)
        else
            -- Move was illegal (e.g., wrong piece, blocked, etc.)
            logger.dbg(string.format("Illegal move attempted from %s to %s.", from, to), "ERROR")
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
end

--- Board:showMove(move)
-- Paperknight: redraws the squares a move touched, without invoking moveCallback
-- (for moves played by the program: engine, puzzle replies, solutions).
function Board:showMove(move)
    self:updateSquare(move.from)
    self:updateSquare(move.to)
    -- Special moves (en passant, castling) affect other squares
    self:handleMoveFlags(move, move.to)
end

--- Board:setShapes(shapes)
-- Paperknight: { circles = { {square=}, ... }, arrows = { {from=, to=}, ... } }
-- drawn over the squares on the next paint (nil clears them).
function Board:setShapes(shapes)
    self.shapes = shapes
end

-- A single-square refresh (selection border) paints only that button and
-- would erase shapes crossing it: repaint the whole board when shapes exist.
function Board:_repaintShapes()
    local shapes = self.shapes
    if shapes and ((shapes.circles and #shapes.circles > 0) or (shapes.arrows and #shapes.arrows > 0)) then
        UIManager:setDirty(self.show_parent or self, "ui", self.dimen)
    end
end

function Board:paintTo(bb, x, y)
    FrameContainer.paintTo(self, bb, x, y)
    if self.shapes then self:_paintShapes(bb) end
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
            bb:paintBorder(r.x + inset, r.y + inset, w, w, ring, SHAPE_COLOR, math.floor(w / 2))
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
    local half = math.floor(thick / 2)
    -- shaft: overlapping squares every half thickness (cheap on slow CPUs)
    local step = math.max(1, math.floor(half / 2))
    for i = 0, math.floor(len - head), step do
        bb:paintRect(math.floor(x1 + ux * i) - half, math.floor(y1 + uy * i) - half, thick, thick, SHAPE_COLOR)
    end
    -- head: filled triangle, one horizontal span per scanline
    local px, py = -uy, ux
    local base_half = thick * 1.6
    local bx, by = x2 - ux * head, y2 - uy * head
    self:_fillTriangle(bb, x2, y2, bx + px * base_half, by + py * base_half,
        bx - px * base_half, by - py * base_half)
end

function Board:_fillTriangle(bb, ax, ay, bx, by, cx, cy)
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
            bb:paintRect(x0, y, x1 - x0 + 1, 1, SHAPE_COLOR)
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

--- Board:squareColor(square): background for a square, highlight included.
function Board:squareColor(square)
    if self.highlighted and self.highlighted[square] then return HIGHLIGHT_COLOR end
    return Board.positionToColor(square)
end

function Board:_applyBackground(square)
    local id = Board.chessToId(square)
    if not id then return end
    local button = self.table:getButtonById(id)
    button.frame.background = self:squareColor(square)
    button:refresh()
end

--- Board:handleMoveFlags(move, to)
-- Handles visual updates for special move types (en passant, castling).
-- @param move Table, the move object.
-- @param to String, the destination square of the main piece.
function Board:handleMoveFlags(move, to)
    if not move.flags then return end

    local to_id_result = Board.chessToId(to)
    if not to_id_result then
        logger.info(_("Chess: Invalid destination square for move flags: " .. tostring(to)))
        return
    end
    local to_id = to_id_result

    if move.flags == Chess.FLAGS.EP_CAPTURE then
        -- En passant: the captured pawn is on the rank of the 'from' square, but the file of the 'to' square.
        -- We need to clear the square of the captured pawn.
        local captured_pawn_rank_offset = (move.color == Chess.BLACK and 1 or -1)
        local captured_pawn_id = to_id + captured_pawn_rank_offset * BOARD_SIZE -- Adjust ID by rank offset, maintaining file
        local captured_pawn_square_result = Board.idToPosition(captured_pawn_id)
        if captured_pawn_square_result then
            self:updateSquare(captured_pawn_square_result)
        end
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

--- Board:markSelected(square)
-- Visually marks a square as selected by adding a border.
-- @param square String, algebraic notation of the square to mark.
function Board:markSelected(square)
    local id_result = Board.chessToId(square)
    if not id_result then
        logger.info(_("Chess: Invalid square to select: " .. tostring(square)))
        return
    end
    local button = self.table:getButtonById(id_result)
    button.frame.bordersize = Screen:scaleBySize(SELECTED_BORDER)
    button:refresh()
    self:_repaintShapes()
end

--- Board:unmarkSelected(square)
-- Visually unmarks a square by removing its border.
-- @param square String, algebraic notation of the square to unmark.
function Board:unmarkSelected(square)
    local id_result = Board.chessToId(square)
    if not id_result then
        logger.info(_("Chess: Invalid square to unselect: " .. tostring(square)))
        return
    end
    local button = self.table:getButtonById(id_result)
    button.frame.bordersize = 0
    button:refresh()
    self:_repaintShapes()
end

--- Board:placePiece(square, piece, color)
-- Places or removes a piece icon on a specific board square.
-- @param square String, algebraic notation of the square.
-- @param piece String, the piece type (e.g., Chess.PAWN, Chess.QUEEN) or nil to clear.
-- @param color String, the piece color (Chess.WHITE or Chess.BLACK), only required if `piece` is not nil.
function Board:placePiece(square, piece, color)
    local icon = (piece and icons[piece] and icons[piece][color]) or icons.empty
    local id_result = Board.chessToId(square)
    if not id_result then
        logger.info(_("Error placing " .. tostring(piece) .. " on non-chess position: " .. square))
        return
    end
    local button = self.table:getButtonById(id_result)
    -- Paperknight: skip unchanged squares; each refresh is an e-ink update
    if button.icon == icon then return end
    button:setIcon(icon, self.button_size)
    button.frame.background = self:squareColor(square) -- Re-apply background color in case it was changed
    button:refresh()
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
function Board:updateBoard()
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
                self:placePiece(square, element.type, element.color)
            else
                self:placePiece(square) -- Clear the square if no piece
            end
        end
    end
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
-- @return LIGHT_SQUARE or DARK_SQUARE.
function Board.positionToColor(position)
    if type(position) == "string" and #position == 2 then
        local file_char = position:sub(1, 1)
        local rank_char = position:sub(2, 2)
        if 'a' <= file_char and file_char <= 'h' and '1' <= rank_char and rank_char <= '8' then
            local file_idx = string.byte(file_char) - string.byte('a')
            local rank_idx = tonumber(rank_char) - 1
            return (file_idx + rank_idx) % 2 == 1 and LIGHT_SQUARE or DARK_SQUARE
        end
    end
    return nil -- Or a default color, depending on desired behavior for invalid input
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
