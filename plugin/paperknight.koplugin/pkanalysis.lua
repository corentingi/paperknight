-- Analysis board: a free board where both sides move, the line played with
-- |‹ ‹ › ›| (or swipes / page keys) to step through it, a position from a FEN,
-- and, when Stockfish is installed (bin/stockfish), its evaluation and best
-- line for the position shown. Playing another move after stepping back
-- replaces the rest of the line.
local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geometry = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local ScrollTextWidget = require("ui/widget/scrolltextwidget")
local Size = require("ui/size")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local VerticalGroup = require("ui/widget/verticalgroup")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template
local Screen = Device.screen
local Chess = require("pkchess")
local ChessBoard = require("pkboard")
local PkButton = require("pkbutton")
local PkIcons = require("pkicons")
local PkMoveList = require("pkmovelist")
local PkNav = require("pknav")
local PkPromotion = require("pkpromotion")
local PkRefresh = require("pkrefresh")
local PkSide = require("pkside")

local START_FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
local PV_PLIES = 8           -- moves of the engine's line shown
local PANEL_MIN_INTERVAL = 2 -- seconds between engine updates of the panel (e-ink)

local PkAnalysis = InputContainer:extend{
    name = "paperknight_analysis",
    covers_fullscreen = true,
    fen = nil,          -- start position (nil: the initial position)
    flipped = false,
    engine_path = nil,  -- default: bin/stockfish (pkgame.lua)
    movetime = 4000,    -- milliseconds of analysis per position
    list_shown = true,  -- the move list beside the board (the two-column button toggles it)
    list_layout = "full", -- "full" (the whole height) or "beside" (as tall as the board)
}

--- Opens the analysis board. `opts`: { fen, flipped, engine_path }.
function PkAnalysis.show(opts)
    local view = PkAnalysis:new(opts or {})
    UIManager:show(view)
    return view
end

function PkAnalysis:init()
    self.dimen = Geometry:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    if Device:hasKeys() then
        self.key_events = {
            Close = { { Device.input.group.Back } },
            Forward = { { Device.input.group.PgFwd } },
            Backward = { { Device.input.group.PgBack } },
        }
    end
    self.ges_events.PkSwipe = { GestureRange:new{ ges = "swipe", range = function() return self.dimen end } }
    PkNav.tapTitle(self, function() return self.title_bar end, "analysis")
    self.title_bar = TitleBar:new{
        fullscreen = true,
        title = _("Analysis board"),
        with_bottom_line = true,
        left_icon = "appbar.menu",
        left_icon_tap_callback = function() self:showMenu() end,
        close_callback = function() self:onClose() end,
    }
    self.buttons = ButtonTable:new{
        width = self.dimen.w - 2 * Size.padding.default,
        buttons = {{
            -- the engine: a white knight when off, a black one when on
            { id = "engine", icon = "chevron.first", callback = function() self:toggleEngine() end },
            { id = "start", icon = "chevron.first", callback = function() self:toStart() end },
            { id = "back", icon = "chevron.left", callback = function() self:step(-1) end },
            { id = "forward", icon = "chevron.right", callback = function() self:step(1) end },
            { id = "end", icon = "chevron.last", callback = function() self:toEnd() end },
            { id = "list", icon = "column.two", callback = function() self:toggleList() end },
        }},
        zero_sep = true,
    }
    -- stepping: the board changing is the feedback (no flashing highlight)
    PkButton.noFeedback(self.buttons, { "engine", "start", "back", "forward", "end" })
    self.free_h = self.dimen.h - self.title_bar:getHeight() - self.buttons:getSize().h
    self.game = Chess:new()
    -- the engine is off at first; Stockfish starts when it is first turned on
    self.engine_on = false
    local lfs = require("libs/libkoreader-lfs")
    self.engine_missing = lfs.attributes(self:_enginePath(), "mode") ~= "file"
    self:_updateEngineButton()
    self:setPosition(self.fen or START_FEN)
end

-- The engine button: its icon says whether the engine is on; greyed
-- without Stockfish (a tap then says how to install it).
function PkAnalysis:_updateEngineButton()
    local button = self.buttons:getButtonById("engine")
    button.enabled = not self.engine_missing
    button.allow_tap_when_disabled = true
    local knight = PkIcons.pieces[Chess.KNIGHT]
    PkButton.setFileIcon(button, self.engine_on and knight[Chess.BLACK] or knight[Chess.WHITE])
    local d = button.dimen -- (none before the first paint, which draws it anyway)
    if d and d.x then UIManager:setDirty(self, PkRefresh.STEP, d) end
end

---------------------------------------------------------------------------
-- Position and line

--- Starts from `fen` (an empty line). Returns false if the FEN is invalid.
function PkAnalysis:setPosition(fen)
    local probe = Chess:new()
    if not probe.load(fen) then return false end
    self.start_fen = fen
    self.line, self.pos = {}, 0
    self.game.load(fen)
    self:_build()
    self:_update(true)
    return true
end

-- Sizes of the board, the list and the panel for the current layout.
function PkAnalysis:_sizes()
    local pad, free_h = Size.padding.default, self.free_h
    if not self.list_shown then
        self.board_size = math.min(self.dimen.w, math.floor(free_h * 0.7))
        self.text_w = self.dimen.w - 2 * Size.padding.large
    else
        -- the board on the left, the move list on its right
        self.board_size = math.min(math.floor(self.dimen.w * 0.78), math.floor(free_h * 0.7))
        self.list_w = self.dimen.w - self.board_size - 3 * pad
        self.list_h = self.list_layout == "full" and free_h - pad or self.board_size
        self.text_w = self.list_layout == "full" and self.board_size or self.dimen.w - 2 * Size.padding.large
    end
    self.text_h = free_h - self.board_size - 3 * pad
end

--- Shows or hides the move list.
function PkAnalysis:toggleList()
    self.list_shown = not self.list_shown
    self:_build()
    self:_update(true)
end

function PkAnalysis:_build()
    self:_sizes()
    if self.board then self.board:free() end
    self.board = ChessBoard:new{
        game = self.game,
        width = self.board_size,
        height = self.board_size,
        flipped = self.flipped,
        centre_squares = not self.list_shown, -- the list takes the room on the right
        show_parent = self,
        moveCallback = function(move) self:onBoardMove(move) end,
        onPromotionNeeded = function(from, to, color)
            PkPromotion.show(color, function(letter)
                local move = self.game.move({ from = from, to = to, promotion = letter })
                if move then
                    self.board:handleGameMove(move)
                    self:onBoardMove(move)
                end
            end)
        end,
    }
    self.board:updateBoard() -- a new board starts empty: draw the position
    self.text = self:_textWidget("")
    local pad = Size.padding.default
    if self.list_shown then
        -- the list gets everything the board does not use
        self.list_w = self.dimen.w - self.board:getSize().w - 2 * pad
        if self.list_layout == "full" then self.text_w = self.board:getSize().w end
    end
    self.movelist = self.list_shown and PkMoveList:new{
        width = self.list_w,
        height = self.list_h,
        show_parent = self,
        onSelect = function(ply) self:_goTo(ply) end,
    } or nil
    local board_row = CenterContainer:new{
        dimen = Geometry:new{ w = self.dimen.w, h = self.board_size + pad },
        self.movelist and HorizontalGroup:new{
            align = "top", self.board, HorizontalSpan:new{ width = pad }, self.movelist,
        } or self.board,
    }
    if self.movelist and self.list_layout == "full" then
        -- the list from the title to the buttons; the panel under the board
        self.vgroup = VerticalGroup:new{
            align = "center",
            self.title_bar,
            HorizontalGroup:new{
                align = "top",
                HorizontalSpan:new{ width = pad },
                VerticalGroup:new{
                    align = "left",
                    CenterContainer:new{
                        dimen = Geometry:new{ w = self.board:getSize().w, h = self.board_size + pad }, self.board },
                    self.text,
                },
                HorizontalSpan:new{ width = pad },
                self.movelist,
            },
            self.buttons,
        }
        self.text_parent = self.vgroup[2][2]
    else
        self.vgroup = VerticalGroup:new{
            align = "center",
            self.title_bar,
            board_row,
            self.text,
            self.buttons,
        }
        self.text_parent = self.vgroup
    end
    self[1] = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        width = self.dimen.w,
        height = self.dimen.h,
        self.vgroup,
    }
end

function PkAnalysis:_textWidget(text)
    return ScrollTextWidget:new{
        text = text,
        face = Font:getFace("cfont", 18),
        width = self.text_w,
        height = self.text_h,
        dialog = self,
    }
end

-- A move played on the board (already in the game): it replaces the rest
-- of the line.
function PkAnalysis:onBoardMove(move)
    for i = #self.line, self.pos + 1, -1 do self.line[i] = nil end
    self.line[#self.line + 1] = { from = move.from, to = move.to, promotion = move.promotion, san = move.san }
    self.pos = #self.line
    self:_update()
end

--- Steps `delta` moves through the line (‹ ›, swipes, page keys).
function PkAnalysis:step(delta)
    if delta > 0 and self.pos < #self.line then
        local m = self.line[self.pos + 1]
        if not self.game.move({ from = m.from, to = m.to, promotion = m.promotion }) then return end
        self.pos = self.pos + 1
    elseif delta < 0 and self.pos > 0 then
        self.game.undo()
        self.pos = self.pos - 1
    else
        return
    end
    self.board:updateBoard()
    self:_update()
end

function PkAnalysis:toStart() self:_goTo(0) end
function PkAnalysis:toEnd() self:_goTo(#self.line) end

function PkAnalysis:_goTo(pos)
    if pos == self.pos then return end
    self.game.load(self.start_fen)
    for i = 1, pos do
        local m = self.line[i]
        self.game.move({ from = m.from, to = m.to, promotion = m.promotion })
    end
    self.pos = pos
    self.board:updateBoard()
    self:_update()
end

-- After any change of the position: highlights, buttons, panel, engine.
function PkAnalysis:_update(page)
    local last = self.line[self.pos]
    self.board:setHighlights(last and { last.from, last.to } or {})
    self.buttons:getButtonById("start"):enableDisable(self.pos > 0)
    self.buttons:getButtonById("back"):enableDisable(self.pos > 0)
    self.buttons:getButtonById("forward"):enableDisable(self.pos < #self.line)
    self.buttons:getButtonById("end"):enableDisable(self.pos < #self.line)
    self.info = nil
    self:_updateList()
    self:_setText()
    if page then PkRefresh.page(self) end
    self:_analyse()
end

---------------------------------------------------------------------------
-- Panel

-- The move list beside the board: the line, the current move shaded.
function PkAnalysis:_updateList()
    if not self.movelist then return end
    local fields = {}
    for f in self.start_fen:gmatch("%S+") do fields[#fields + 1] = f end
    local sans = {}
    for i, m in ipairs(self.line) do sans[i] = m.san end
    self.movelist.first_number = tonumber(fields[6]) or 1
    self.movelist.black_first = fields[2] == "b"
    self.movelist:setMoves(sans, self.pos)
    self.movelist:refresh()
end

-- "1. e4 e5 2. Nf3 [Nc6] 3. Bb5": the line, the current move in brackets.
function PkAnalysis:_lineText()
    if #self.line == 0 then return nil end
    local fields = {}
    for f in self.start_fen:gmatch("%S+") do fields[#fields + 1] = f end
    local number = tonumber(fields[6]) or 1
    local white = fields[2] ~= "b"
    local parts = {}
    for i, m in ipairs(self.line) do
        local san = (i == self.pos) and ("[" .. m.san .. "]") or m.san
        if white then
            parts[#parts + 1] = number .. ". " .. san
        else
            if i == 1 then parts[#parts + 1] = number .. "… " .. san else parts[#parts + 1] = san end
            number = number + 1
        end
        white = not white
    end
    return table.concat(parts, " ")
end

function PkAnalysis:_engineText()
    if not (self.engine and self.engine_on) then return nil end
    if self.game.game_over() then return nil end
    local info = self.info
    if not info then return _("Engine: thinking…") end
    return T(_("Engine: %1 (depth %2)"), info.score, info.depth) .. (info.pv and ("\n" .. info.pv) or "")
end

function PkAnalysis:_statusText()
    if self.game.in_checkmate() then return _("Checkmate.") end
    if self.game.in_stalemate() then return _("Stalemate.") end
    if self.game.in_draw() then return _("Draw.") end
    local side = self.game.turn() == Chess.WHITE and "w" or "b"
    return T(_("%1 to move."), PkSide.name(side))
end

function PkAnalysis:_setText()
    local parts = { self:_statusText() }
    local engine = self:_engineText()
    if engine then parts[#parts + 1] = engine end
    local line = not self.movelist and self:_lineText() -- the list shows it otherwise
    if line then parts[#parts + 1] = "\n" .. line end
    local text = table.concat(parts, "\n")
    self.panel_text = text
    local old = self.text
    local old_dimen = old.dimen and old.dimen.x and old.dimen:copy()
    self.text = self:_textWidget(text)
    for i, w in ipairs(self.text_parent) do
        if w == old then self.text_parent[i] = self.text end
    end
    old:free()
    self.text_parent:resetLayout()
    self.vgroup:resetLayout()
    -- the board refreshes its own squares; the panel and buttons apart (only
    -- the panel when the list runs beside it)
    if self.movelist and self.list_layout == "full" then
        UIManager:setDirty(self, PkRefresh.STEP, old_dimen)
    else
        PkRefresh.below(self, self.board, self.buttons)
    end
end

---------------------------------------------------------------------------
-- Engine

function PkAnalysis:_enginePath()
    return self.engine_path or require("pkgame").ENGINE_PATH
end

function PkAnalysis:_startEngine()
    local path = self:_enginePath()
    local lfs = require("libs/libkoreader-lfs")
    if lfs.attributes(path, "mode") ~= "file" then
        self.engine_missing, self.engine_on = true, false
        self:_updateEngineButton()
        self:_setText()
        return
    end
    local Uci = require("pkuci")
    local engine = Uci.UCIEngine.spawn(path, { path })
    if not engine then
        logger.warn("Paperknight: cannot start the engine", path)
        self.engine_missing, self.engine_on = true, false
        self:_updateEngineButton()
        return
    end
    self.engine = engine
    engine:on("uciok", function()
        self.engine_ready = true
        self:_analyse()
    end)
    engine:on("line", function(line) self:_onEngineLine(line) end)
    engine:on("bestmove", function() self:_onBestmove() end)
    engine:on("eof", function()
        logger.warn("Paperknight: the engine exited")
        if self.engine then self.engine:stop() end
        self.engine = nil
        self.engine_missing, self.engine_on = true, false
        self:_updateEngineButton()
        self:_setText()
    end)
    engine:uci()
end

-- Analyses the position shown: a search runs at a time; a new position
-- stops it, and the next search starts once its bestmove arrives (so that
-- late lines of the old search are not shown for the new position).
function PkAnalysis:_analyse()
    local engine = self.engine
    if not (engine and self.engine_ready and self.engine_on) then return end
    if self.game.game_over() then
        if self.searching then engine.send("stop") end
        return
    end
    self.wanted_fen = self.game.fen()
    if self.searching then
        if self.search_fen ~= self.wanted_fen then engine.send("stop") end
        return
    end
    self.searching, self.search_fen = true, self.wanted_fen
    self.last_panel = nil
    engine:position{ fen = self.search_fen }
    engine:go{ movetime = self.movetime }
end

function PkAnalysis:_onBestmove()
    self.searching = false
    if self.wanted_fen ~= self.search_fen then
        self:_analyse() -- the position changed during the search
    elseif self.pending_info then
        self.info, self.pending_info = self.pending_info, nil
        self:_setText()
    end
end

-- Score from White's side: "+0.35", "-1.20", "#3" (White mates), "#-2".
local function scoreText(kind, value, white_to_move)
    if not white_to_move then value = -value end
    if kind == "mate" then return value > 0 and ("#" .. value) or ("#-" .. -value) end
    return string.format("%+.2f", value / 100)
end

-- "1... Nc6 2. Bb5 a6": the engine's line in SAN from position `fen`.
local function pvText(fen, uci_moves)
    local g = Chess:new()
    if not g.load(fen) then return nil end
    local fields = {}
    for f in fen:gmatch("%S+") do fields[#fields + 1] = f end
    local number, white = tonumber(fields[6]) or 1, fields[2] ~= "b"
    local parts = {}
    for i, u in ipairs(uci_moves) do
        if i > PV_PLIES then break end
        local promo = u:sub(5, 5)
        local m = g.move({ from = u:sub(1, 2), to = u:sub(3, 4), promotion = promo ~= "" and promo or nil })
        if not m then break end
        if white then
            parts[#parts + 1] = number .. ". " .. m.san
        else
            parts[#parts + 1] = (i == 1) and (number .. "… " .. m.san) or m.san
            number = number + 1
        end
        white = not white
    end
    return #parts > 0 and table.concat(parts, " ") or nil
end

function PkAnalysis:_onEngineLine(line)
    if not self.searching or self.wanted_fen ~= self.search_fen then return end -- stale search
    if not line:find("^info") or not line:find(" pv ") then return end
    local multipv = tonumber(line:match(" multipv (%d+)"))
    if multipv and multipv > 1 then return end
    local depth = tonumber(line:match(" depth (%d+)"))
    local kind, value = line:match(" score (%a+) (%-?%d+)")
    if not (depth and kind) then return end
    local moves = {}
    for u in (line:match(" pv (.+)$") or ""):gmatch("%S+") do moves[#moves + 1] = u end
    local white = self.search_fen:match("^%S+ (%a)") ~= "b"
    local info = {
        depth = depth,
        score = scoreText(kind, tonumber(value), white),
        pv = pvText(self.search_fen, moves),
    }
    -- the panel is refreshed at most every PANEL_MIN_INTERVAL seconds (e-ink);
    -- the last line is shown when the search ends
    local now = os.time()
    if not self.last_panel or now - self.last_panel >= PANEL_MIN_INTERVAL then
        self.last_panel = now
        self.info, self.pending_info = info, nil
        self:_setText()
    else
        self.pending_info = info
    end
end

---------------------------------------------------------------------------
-- Menu, gestures, closing

function PkAnalysis:showMenu()
    local dialog
    local function close() UIManager:close(dialog); self.menu_dialog = nil end
    local buttons = {
        {
            { text = _("Flip board"), callback = function() close(); self:flip() end },
            { text = _("Start position"), callback = function() close(); self:setPosition(START_FEN) end },
        },
        {
            { text = _("Position from FEN…"), callback = function() close(); self:askFen() end },
            { text = _("Show FEN"), callback = function()
                close()
                UIManager:show(InfoMessage:new{ text = self.game.fen() })
            end },
        },
    }
    buttons[#buttons + 1] = PkNav.moreRow(close, "analysis")
    dialog = ButtonDialog:new{ buttons = buttons }
    self.menu_dialog = dialog
    UIManager:show(dialog)
end

function PkAnalysis:flip()
    self.flipped = not self.flipped
    self:_build()
    self:_update(true)
end

function PkAnalysis:toggleEngine()
    if self.engine_missing then
        UIManager:show(InfoMessage:new{
            text = _("Stockfish is not installed (bin/stockfish in the plugin folder). See the Paperknight docs: stockfish.md."),
        })
        return
    end
    self.engine_on = not self.engine_on
    -- started the first time; afterwards kept (idle) until the board closes,
    -- so that turning it on again is immediate
    if self.engine_on and not self.engine then self:_startEngine() end
    if not self.engine_on and self.searching and self.engine then self.engine.send("stop") end
    self:_updateEngineButton()
    self.info = nil
    self:_updateList()
    self:_setText()
    self:_analyse()
end

function PkAnalysis:askFen()
    local dialog
    dialog = InputDialog:new{
        title = _("Position from FEN"),
        input = self.game.fen(),
        buttons = {{
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
            { text = _("Set"), is_enter_default = true, callback = function()
                local fen = dialog:getInputText():match("^%s*(.-)%s*$")
                UIManager:close(dialog)
                if not self:setPosition(fen) then
                    UIManager:show(InfoMessage:new{ text = _("Not a valid FEN.") })
                end
            end },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function PkAnalysis:onPkSwipe(_, ges)
    if ges.direction == "west" then self:step(1) elseif ges.direction == "east" then self:step(-1) else return false end
    return true
end

function PkAnalysis:onForward() self:step(1); return true end
function PkAnalysis:onBackward() self:step(-1); return true end

function PkAnalysis:onClose()
    UIManager:close(self)
    return true
end

-- However the screen closes: the engine process is stopped.
function PkAnalysis:onCloseWidget()
    if self.engine then
        self.engine:stop()
        self.engine = nil
    end
end

return PkAnalysis
