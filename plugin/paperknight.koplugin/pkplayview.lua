-- Play screen (ADR-0020): a game against Stockfish or between two players
-- (face to face: Black's pieces upside down), on the board + panel +
-- buttons screen of the studies and the drill (pkboardscreen.lua). The game
-- logic is pkplay.lua, the new game dialog pkplaysetup.lua. The game in
-- progress is saved after each move and comes back when Play is opened.
-- Clocks run from a move to the next: a take-back or reopening the game
-- pauses them until the next move.
local ButtonDialog = require("ui/widget/buttondialog")
local ButtonTable = require("ui/widget/buttontable")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local Geometry = require("ui/geometry")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local Size = require("ui/size")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template
local Screen = Device.screen

local PkEngine = require("pkengine")
local PkNav = require("pknav")
local PkOpeningNames = require("pkopeningnames")
local PkPlay = require("pkplay")
local PkPlaySetup = require("pkplaysetup")
local PkProgress = require("pkprogress")
local PkRefresh = require("pkrefresh")
local PkSide = require("pkside")
local Timer = require("pktimer")

local PkPlayView = InputContainer:extend{
    name = "paperknight_game", -- (PkNav: a Paperknight screen)
    covers_fullscreen = true,
    engine_path = nil, -- default: bin/stockfish (tests give a fake engine)
}
-- board + text panel + buttons, the panel's text and refreshes (pkboardscreen.lua)
require("pkboardscreen").mixin(PkPlayView)

-- Remembered choices and the game in progress (progress.sqlite)
PkPlayView._setting = PkProgress.readSetting
PkPlayView._saveSetting = PkProgress.writeSetting

--- Opens Play: the game in progress if there is one, else a new game with
-- the last settings and the new game dialog over it. `opts`: { engine_path }.
function PkPlayView.show(opts)
    local view = PkPlayView:new(opts or {})
    UIManager:show(view)
    if not view.resumed then view:showSetup() end
    return view
end

function PkPlayView:init()
    self.dimen = Geometry:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    if Device:hasKeys() then
        self.key_events = { Close = { { Device.input.group.Back } } }
    end
    PkNav.tapTitle(self, function() return self.title_bar end, "play") -- quick settings
    -- (the subtitle's discs follow at the next move or clock tick)
    PkSide.followNight(self, function(v) if v.raw_text then v:_setText(PkSide.swap(v.raw_text)) end end)
    self.has_engine = PkEngine.installed(self.engine_path)
    self.list_shown = PkPlayView._setting("play.movelist") ~= "0"
    self.title_bar = TitleBar:new{
        fullscreen = true,
        title = _("Play"),
        subtitle = "",
        title_shrink_font_to_fit = true,
        with_bottom_line = true,
        left_icon = "appbar.menu",
        left_icon_tap_callback = function() self:showMenu() end,
        close_callback = function() self:onClose() end,
    }
    self.buttons = ButtonTable:new{
        width = self.dimen.w - 2 * Size.padding.default,
        buttons = {{
            { id = "new", text = _("New game"), callback = function() self:showSetup() end },
            { id = "takeback", text = _("Take back"), callback = function() self:takeBack() end },
            { id = "analyse", text = _("Analyse"), callback = function() self:analyse() end },
        }},
        zero_sep = true,
    }
    local free_h = self.dimen.h - self.title_bar:getHeight() - self.buttons:getSize().h
    self.board_size = math.min(self.dimen.w, math.floor(free_h * 0.7))
    self.text_h = free_h - self.board_size - 3 * Size.padding.default
    local saved, times = PkPlay.restore(PkPlayView._setting("play.current"), { engine = self.has_engine })
    self.resumed = saved ~= nil
    self:startGame(saved or PkPlay.new(self:settings(), { engine = self.has_engine }), times)
end

--- The settings of the last new game (pkplay.lua).
function PkPlayView:settings()
    return PkPlay.loadSettings(PkPlayView._setting)
end

---------------------------------------------------------------------------
-- A game

--- Shows `play` (a PkPlay game); `times`: the clocks' time left (resumed).
function PkPlayView:startGame(play, times)
    self:_stopClock()
    if self.engine and self.search then self.engine.send("stop") end
    self.search = nil
    self.play = play
    self.game = play.chess -- the board's game
    local base, inc = PkPlay.clockSpec(play.settings.clock)
    self.timer = nil
    if base then
        self.timer = Timer:new({ w = base, b = base }, { w = inc, b = inc }, function() self:_onClockTick() end)
        if times then self.timer.time = { w = times.w, b = times.b } end
        self.timer.currentPlayer = play:turn()
    end
    self.rotate_black = not play:vsEngine() and play.settings.face
    local flipped = play:vsEngine() and play.user_side == "b"
    self:_build(flipped)
    if play:vsEngine() then self:_prepareEngine(true) end
    self:refresh(true)
    self:_save()
    self:_next()
end

-- The screen for the board's orientation; the board shows the game (a new
-- board starts empty, a kept one has the last game's; the page refresh
-- that follows shows it).
function PkPlayView:_build(flipped)
    self:_buildScreen(flipped)
    self.board.game = self.game
    self.board:updateBoard(true)
end

--- The new game dialog; Start begins the game (settings remembered).
function PkPlayView:showSetup()
    self.setup = PkPlaySetup.show{
        settings = self:settings(),
        has_engine = self.has_engine,
        on_start = function(settings)
            self.setup = nil
            PkPlay.saveSettings(settings, PkPlayView._saveSetting)
            if self.engine then self.engine.send("ucinewgame") end
            self:startGame(PkPlay.new(settings, { engine = self.has_engine }))
        end,
    }
    return self.setup
end

-- A move by the board (the user, or either player), already in the game:
-- taken back if it was not theirs to play (the board was not locked in time).
function PkPlayView:onBoardMove(move)
    local play = self.play
    if play.result or move.color == play.engine_side then
        self:_takeBackMove()
        return self:refresh()
    end
    self.play:played()
    self:_afterMove()
end

function PkPlayView:_afterMove()
    if self.timer then
        if self.play.result then
            self.timer:stop(true)
        elseif self.timer.running then
            self.timer:switchPlayer()
        else
            -- the first move since the start (or a pause): the next player's clock runs
            self.timer.currentPlayer = self.play:turn()
            self.timer:start()
        end
    end
    self:refresh()
    self:_save()
    self:_next()
end

-- Stockfish moves when it is its turn.
function PkPlayView:_next()
    if self.play:isEngineTurn() then self:_think() end
end

function PkPlayView:takeBack()
    if not self.play:canTakeBack() then return end
    if self.engine and self.search then self.engine.send("stop") end
    self.search = nil
    self:_stopClock()
    self.play:takeBack()
    if self.timer then self.timer.currentPlayer = self.play:turn() end
    self.board:updateBoard()
    self:refresh()
    self:_save()
end

function PkPlayView:resign()
    local play = self.play
    if play.result then return end
    play:resign(play:vsEngine() and play.user_side or play:turn())
    self:_gameOver()
end

function PkPlayView:_gameOver()
    if self.engine and self.search then self.engine.send("stop") end
    self.search = nil
    self:_stopClock()
    self:refresh()
    self:_save()
end

--- Opens the analysis board with the game, at move `ply` (default: the last).
function PkPlayView:analyse(ply)
    local moves = self.game.history({ verbose = true })
    return require("pkanalysis").show{
        fen = self.play.start_fen,
        moves = moves,
        pos = ply or #moves,
        flipped = self.board and self.board.flipped,
    }
end

-- A tap on a move of the list: that position on the analysis board.
function PkPlayView:onListSelect(ply)
    self:analyse(ply)
end

-- Saves the game in progress (none once over, or before a move: the new
-- game dialog comes next).
function PkPlayView:_save()
    local play = self.play
    if play.result or #self.game.history() == 0 then
        PkPlayView._saveSetting("play.current", nil)
        return
    end
    local times = self.timer and {
        w = self.timer:getRemainingTime("w"),
        b = self.timer:getRemainingTime("b"),
    } or nil
    PkPlayView._saveSetting("play.current", play:serialize(times))
end

---------------------------------------------------------------------------
-- Clocks

local function clockText(seconds)
    seconds = math.max(0, math.floor(seconds))
    local h, m, s = math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60
    if h > 0 then return string.format("%d:%02d:%02d", h, m, s) end
    return string.format("%d:%02d", m, s)
end
PkPlayView.clockText = clockText

function PkPlayView:_stopClock()
    if self.timer then self.timer:stop() end
end

function PkPlayView:_onClockTick()
    local timer, play = self.timer, self.play
    if not timer then return end
    local player = timer.currentPlayer
    if timer:getRemainingTime(player) <= 0 and not play.result then
        play:flag(player)
        self:_gameOver()
        return
    end
    self:_setSubtitle()
end

---------------------------------------------------------------------------
-- Display

-- "You (○ White) · Stockfish 1500", "Face to face"; with a clock, the times
-- ("You 4:58 · Stockfish 5:00", "○ 4:58 · ● 5:00").
function PkPlayView:_subtitle()
    local play, timer = self.play, self.timer
    if play:vsEngine() then
        local engine = T(_("Stockfish %1"), PkPlay.levelName(play.settings.level))
        if timer then
            local you, sf = play.user_side, play.engine_side
            return T(_("You %1 · %2 %3"), clockText(timer:getRemainingTime(you)), engine,
                clockText(timer:getRemainingTime(sf)))
        end
        return T(_("You (%1) · %2"), PkSide.name(play.user_side), engine)
    end
    if timer then
        return T("%1 %2 · %3 %4", PkSide.mark("w"), clockText(timer:getRemainingTime("w")),
            PkSide.mark("b"), clockText(timer:getRemainingTime("b")))
    end
    return play.settings.face and _("Two players, face to face") or _("Two players")
end

function PkPlayView:_setSubtitle()
    PkRefresh.setSubTitle(self, self:_subtitle())
end

-- "1. e4 e5 2. Nf3": the game in the panel when the move list is hidden.
function PkPlayView:_lineText()
    local sans = self.game.history()
    if #sans == 0 then return nil end
    local fields = {}
    for f in self.play.start_fen:gmatch("%S+") do fields[#fields + 1] = f end
    local number, white = tonumber(fields[6]) or 1, fields[2] ~= "b"
    local parts = {}
    for i, san in ipairs(sans) do
        if white then
            parts[#parts + 1] = number .. ". " .. san
        elseif i == 1 then
            parts[#parts + 1] = number .. "… " .. san
        else
            parts[#parts + 1] = san
        end
        if not white then number = number + 1 end
        white = not white
    end
    return table.concat(parts, " ")
end

--- Redraws board, panel, list and buttons from the game (`page`: the
-- whole screen, e.g. a new game).
function PkPlayView:refresh(page)
    local play, board = self.play, self.board
    local history = self.game.history({ verbose = true })
    local last = history[#history]
    board:setHighlights(last and { last.from, last.to } or {})
    board:setLocked(not play:isUserTurn())
    local lines = {}
    local result = play:resultText()
    if result then
        lines[#lines + 1] = result
    elseif play:isEngineTurn() then
        lines[#lines + 1] = _("Stockfish is thinking…")
    elseif play:vsEngine() then
        lines[#lines + 1] = self.game.in_check() and _("Check. Your move.") or _("Your move.")
    else
        lines[#lines + 1] = T(self.game.in_check() and _("Check. %1 to move.") or _("%1 to move."),
            PkSide.name(play:turn()))
    end
    if self.timer and not self.timer.running and not result then
        lines[#lines + 1] = _("The clock starts with the next move.")
    end
    local fens = { play.start_fen }
    do
        local probe = require("pkchess"):new()
        probe.load(play.start_fen)
        for _, m in ipairs(history) do
            probe.move({ from = m.from, to = m.to, promotion = m.promotion })
            fens[#fens + 1] = probe.fen()
        end
    end
    local opening = PkOpeningNames.latest(fens)
    if opening then lines[#lines + 1] = opening end
    if not self.movelist then
        local line = self:_lineText()
        if line then lines[#lines + 1] = "\n" .. line end
    end
    self:_setText(table.concat(lines, "\n"))
    local sans = {}
    for i, m in ipairs(history) do sans[i] = m.san end
    local fields = {}
    for f in play.start_fen:gmatch("%S+") do fields[#fields + 1] = f end
    self:_setListMoves(sans, #sans, tonumber(fields[6]) or 1, fields[2] == "b")
    self.buttons:getButtonById("takeback"):enableDisable(play:canTakeBack())
    self.buttons:getButtonById("analyse"):enableDisable(#history > 0)
    self:_setSubtitle()
    self:_redraw(page)
end

---------------------------------------------------------------------------
-- Stockfish

function PkPlayView:_enginePath()
    return self.engine_path or PkEngine.PATH
end

-- Starts Stockfish the first time; sets its strength (`new_game`: for the
-- game starting).
function PkPlayView:_prepareEngine(new_game)
    if not self.engine then
        local engine = require("pkuci").UCIEngine.spawn(self:_enginePath(), { self:_enginePath() })
        if not engine then
            logger.warn("Paperknight: cannot start the engine", self:_enginePath())
            return self:_engineGone()
        end
        self.engine = engine
        engine:on("uciok", function()
            logger.info("Paperknight: engine ready, memory:", require("pkutils").memoryLine(engine.pid, "engine"))
            self.engine_ready = true
            self:_setStrength()
            self:_next()
        end)
        engine:on("bestmove", function(move) self:_onBestmove(move) end)
        engine:on("eof", function()
            logger.warn("Paperknight: the engine exited")
            self:_engineGone()
        end)
        engine:uci()
    elseif new_game and self.engine_ready then
        self:_setStrength()
    end
end

function PkPlayView:_setStrength()
    local level = self.play.settings.level
    if level == 0 then
        self.engine:setOption("UCI_LimitStrength", "false")
    else
        self.engine:setOption("UCI_LimitStrength", "true")
        self.engine:setOption("UCI_Elo", tostring(level))
    end
end

function PkPlayView:_think()
    if not (self.engine and self.engine_ready) or self.search then return end
    local moves = self.play:uciMoves()
    self.search = { moves = moves }
    local left = self.timer and self.timer:getRemainingTime(self.play.engine_side) or nil
    self.engine:position{ fen = self.play.start_fen, moves = moves }
    self.engine:go{ movetime = self.play:movetime(left) }
end

function PkPlayView:_onBestmove(uci)
    local search = self.search
    self.search = nil
    local play = self.play
    -- a search for another position (a take-back, a new game): ignored
    if not search or search.moves ~= play:uciMoves() or not play:isEngineTurn() then
        return self:_next()
    end
    local move = play:play({ from = uci:sub(1, 2), to = uci:sub(3, 4),
                             promotion = #uci > 4 and uci:sub(5, 5) or nil }, true)
    if not move then
        logger.warn("Paperknight: illegal engine move", uci, "in", self.game.fen())
        UIManager:show(InfoMessage:new{
            text = T(_("Stockfish played an illegal move (%1). Take back, or start a new game."), tostring(uci)),
        })
        return
    end
    self.board:showMove(move)
    self:_afterMove()
end

-- Stockfish stopped or could not start: the game goes on between two players.
function PkPlayView:_engineGone()
    if self.engine then self.engine:stop() end
    self.engine, self.engine_ready, self.search = nil, false, nil
    local play = self.play
    if play:vsEngine() then
        play.engine_side, play.user_side, play.settings.opponent = nil, nil, "human"
        play.chess.set_human("w", true)
        play.chess.set_human("b", true)
        UIManager:show(InfoMessage:new{ text = _("Stockfish stopped: the game goes on between two players.") })
        self:refresh()
    end
end

---------------------------------------------------------------------------
-- Menu, saving, closing

function PkPlayView:showMenu()
    local play = self.play
    local dialog
    local function close() UIManager:close(dialog); self.menu_dialog = nil end
    local resign_text = play:vsEngine() and _("Resign")
        or T(_("Resign (%1)"), PkSide.name(play:turn()))
    local buttons = {
        {
            { text = resign_text, enabled = play.result == nil and #self.game.history() > 0, callback = function()
                close()
                UIManager:show(ConfirmBox:new{
                    text = _("Resign this game?"),
                    ok_text = _("Resign"),
                    ok_callback = function() self:resign() end,
                })
            end },
            { text = _("Flip board"), callback = function() close(); self:flip() end },
        },
        {
            { text = self.list_shown and _("Hide move list") or _("Show move list"),
              callback = function() close(); self:toggleList() end },
            { text = _("Save game as a study…"), enabled = #self.game.history() > 0,
              callback = function() close(); self:askSave() end },
        },
    }
    buttons[#buttons + 1] = PkNav.moreRow(close, "play")
    dialog = ButtonDialog:new{ buttons = buttons }
    self.menu_dialog = dialog
    UIManager:show(dialog)
end

function PkPlayView:flip()
    self:_build(not self.board.flipped)
    self:refresh(true)
end

function PkPlayView:toggleList()
    self.list_shown = not self.list_shown
    PkPlayView._saveSetting("play.movelist", self.list_shown and "1" or "0")
    self:_build(self.board.flipped)
    self:refresh(true)
end

--- Writes the game to <studies>/Games/<name>.pgn; returns the path, or nil
-- and an error.
function PkPlayView:saveGame(name, dir)
    return require("pkanalysis").writePgn(self.play:pgn(name), name,
        dir or (require("pkstudies").dir() .. "/Games"))
end

function PkPlayView:askSave()
    local dialog
    dialog = InputDialog:new{
        title = _("Save game as a study"),
        input = os.date("Game %Y-%m-%d %H.%M"),
        buttons = {{
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
            { text = _("Save"), is_enter_default = true, callback = function()
                local name = dialog:getInputText()
                UIManager:close(dialog)
                local path, err = self:saveGame(name)
                if path then
                    UIManager:show(InfoMessage:new{
                        text = T(_("Saved in Studies → Games:\n%1"), path:match("([^/]+)$")),
                        timeout = 3,
                    })
                else
                    logger.warn("Paperknight: cannot save the game:", err)
                    UIManager:show(InfoMessage:new{ text = T(_("Cannot save the game: %1"), tostring(err)) })
                end
            end },
        }},
    }
    self.save_dialog = dialog -- tests
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function PkPlayView:onClose()
    PkRefresh.close(self)
    return true
end

-- However the screen closes (X, Back, PkNav): the game saved with its
-- clocks, the clock and Stockfish stopped.
function PkPlayView:onCloseWidget()
    self:_stopClock()
    if self.play then self:_save() end
    if self.engine then
        self.engine:stop()
        self.engine = nil
    end
    if self.board then self.board:free() end
    if self.text then self.text:free() end
end

return PkPlayView
