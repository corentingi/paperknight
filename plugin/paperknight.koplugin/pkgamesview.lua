-- Master games (ADR-0021): the list of games and the Guess the move screen
-- (board + panel + buttons, pkboardscreen.lua) over a session of
-- pkgames.lua. The opening is played; the user then plays the move they
-- think the master played; the master's move is played whatever the guess,
-- then the other side's reply. The session in progress is saved after each
-- move and comes back; the best score of each game is kept.
local ButtonDialog = require("ui/widget/buttondialog")
local ButtonTable = require("ui/widget/buttontable")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local Geometry = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local Size = require("ui/size")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local T = require("ffi/util").template
local Screen = Device.screen

local ChessBoard = require("pkboard")
local PkGames = require("pkgames")
local PkNav = require("pknav")
local PkOpeningNames = require("pkopeningnames")
local PkProgress = require("pkprogress")
local PkRefresh = require("pkrefresh")
local PkSide = require("pkside")

local REPLY_DELAY = 1.2 -- seconds before the other side's move (the verdict is read first)
local LINE_PLIES = 12   -- the last moves in the panel, without the move list

local PkGamesView = InputContainer:extend{
    name = "paperknight_master_game", -- (PkNav: a Paperknight screen)
    covers_fullscreen = true,
    session = nil, -- PkGames session
    reply_delay = REPLY_DELAY,
}
require("pkboardscreen").mixin(PkGamesView)

PkGamesView._setting = PkProgress.readSetting
PkGamesView._saveSetting = PkProgress.writeSetting

---------------------------------------------------------------------------
-- The list

--- The best score of a game: "80%", or nil.
function PkGamesView.best(id)
    local s = PkGamesView._setting("games.best." .. id)
    local got, max = (s or ""):match("^(%d+)/(%d+)$")
    if not got or tonumber(max) == 0 then return nil end
    return math.floor(100 * tonumber(got) / tonumber(max) + 0.5)
end

local function listItems()
    local items = {}
    local current = PkGames.restore(PkGamesView._setting("games.current"))
    if current then
        items[#items + 1] = {
            text = T(_("Continue: %1"), current.game.title),
            mandatory = current:scoreText(),
            callback = function() PkGamesView.open(current) end,
            separator = true,
        }
    end
    for _i, game in ipairs(PkGames.list()) do
        local best = PkGamesView.best(game.id)
        items[#items + 1] = {
            text = T("%1 · %2, %3", game.title, PkGames.players(game), PkGames.place(game)),
            mandatory = best and T(_("Best: %1%"), best) or nil,
            callback = function() PkGamesView.open(PkGames.session(game)) end,
        }
    end
    if #items == 0 then
        items[1] = { text = _("No master games: reinstall Paperknight."), callback = function() end }
    end
    return items
end

--- The list of master games (and the game in progress first).
function PkGamesView.showList()
    -- up to two lines an item: the title, the players, place and year
    local menu = PkNav.liveMenu("paperknight_master_games", _("Master games"), listItems,
        { items_max_lines = 2, items_per_page = 8 })
    PkNav.tapTitle(menu, function() return menu.title_bar end, "games")
    UIManager:show(menu)
    return menu
end

--- Opens the screen on `session`.
function PkGamesView.open(session)
    local view = PkGamesView:new{ session = session }
    UIManager:show(view)
    return view
end

---------------------------------------------------------------------------
-- The screen

function PkGamesView:init()
    self.dimen = Geometry:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    if Device:hasKeys() then
        self.key_events = { Close = { { Device.input.group.Back } } }
    end
    PkNav.tapTitle(self, function() return self.title_bar end, "games")
    PkSide.followNight(self, function(v) if v.raw_text then v:_setText(PkSide.swap(v.raw_text)) end end)
    self.list_shown = PkGamesView._setting("games.movelist") == "1"
    self.title_bar = TitleBar:new{
        fullscreen = true,
        title = self.session.game.title,
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
            { id = "hint", text = _("Hint"), callback = function() self:hint() end },
            -- Show move, or Next game once the game is over
            { id = "show", text = _("Show move"), callback = function() self:showOrNext() end },
            { id = "analyse", text = _("Analyse"), callback = function() self:analyse() end },
        }},
        zero_sep = true,
    }
    -- the board as wide as the screen, as in puzzles; the panel below has
    -- room for the verdict, the last moves and the opening
    local free_h = self.dimen.h - self.title_bar:getHeight() - self.buttons:getSize().h
    self.board_size = math.min(self.dimen.w, free_h - Screen:scaleBySize(110) - 3 * Size.padding.default)
    self.text_h = free_h - self.board_size - 3 * Size.padding.default
    self:start(self.session)
end

--- Shows `session` from its position (a new one: after the opening).
function PkGamesView:start(session)
    self:_cancelReply()
    self.session = session
    self.game = session.chess
    self.feedback = session:ply() <= session.start_ply and self:_intro() or nil
    self.title_bar:setTitle(session.game.title)
    self:_build(session.side == "b")
    self:refresh(true)
    self:_save()
    self:_paceReply()
end

function PkGamesView:_build(flipped)
    self:_buildScreen(flipped)
    self.board.game = self.game
    self.board:updateBoard(true)
end

-- The master on the side guessed: "Morphy"
function PkGamesView:_master()
    local g = self.session.game
    return self.session.side == "w" and g.white or g.black
end

function PkGamesView:_intro()
    local s, g = self.session, self.session.game
    local lines = { T(_("Guess %1’s moves (%2)."), self:_master(), PkSide.name(s.side)) }
    if s.start_ply > 0 then
        lines[#lines + 1] = T(_("The opening is played up to move %1."), math.floor((s.start_ply + 1) / 2))
    end
    if g.note ~= "" then lines[#lines + 1] = g.note end
    return table.concat(lines, "\n")
end

-- The other side's move, after a pause (the verdict is read first).
function PkGamesView:_paceReply()
    if not self.session:replyNext() or self._reply_task then return end
    self._reply_task = function()
        self._reply_task = nil
        local move = self.session:reply()
        if not move then return end
        self.board:showMove(move)
        self:refresh()
        self:_save()
    end
    UIManager:scheduleIn(self.reply_delay, self._reply_task)
end

-- The user's guess, played by the board: taken back, judged, then the
-- master's move is played.
function PkGamesView:onBoardMove(move)
    self:_takeBackMove()
    local s = self.session
    if not s:guessing() then return self:refresh() end
    local ply = s:ply() + 1
    local verdict, info = s:guess(move)
    self.feedback = self:_verdictText(verdict, info, ply)
    self.board:updateBoard()
    self:_afterStep()
    if verdict == "found" or verdict == "hinted" then
        self.board:setBadge(self.session:history()[ply].to, ChessBoard.TICK)
    end
end

local function moveNumber(ply)
    local n = math.floor((ply + 1) / 2)
    return ply % 2 == 1 and (n .. ".") or (n .. "…")
end

-- A score for the side to move, in pawns: "+1.2", "−0.4", "mate"
local function scoreText(cp)
    if cp >= 9000 then return _("mates") end
    if cp <= -9000 then return _("gets mated") end
    local s = string.format("%.1f", math.abs(cp) / 100)
    return (cp >= 0 and "+" or "−") .. s
end

function PkGamesView:_verdictText(verdict, info, ply)
    local master, number = self:_master(), moveNumber(ply)
    local lines = {}
    if verdict == "found" then
        lines[1] = T(_("✓ %1 %2: %3’s move."), number, info.master, master)
        if info.key then lines[1] = lines[1] .. " " .. _("A key moment!") end
    elseif verdict == "hinted" then
        lines[1] = T(_("✓ %1 %2, with a hint."), number, info.master)
    elseif verdict == "good" then
        lines[1] = T(_("A good move too: %1 %2. %3 played %4."), number, info.guess, master, info.master)
    else
        lines[1] = T(_("%1 played %2 %3. Yours: %4."), master, number, info.master, info.guess)
        if info.cp_guess and info.cp_master then
            lines[2] = T(_("Stockfish: %1 for %2, %3 for yours."), scoreText(info.cp_master), info.master,
                scoreText(info.cp_guess))
        end
    end
    if info.best and info.best ~= info.master and info.best ~= info.guess then
        lines[#lines + 1] = T(_("Stockfish’s choice: %1."), info.best)
    end
    return table.concat(lines, "\n")
end

-- After the user's move (guessed or shown): the end (the best score kept
-- before it is shown), the screen, the reply.
function PkGamesView:_afterStep()
    if self.session:over() then self:_finished() end
    self:refresh()
    self:_save()
    self:_paceReply()
end

function PkGamesView:hint()
    local square = self.session:hint()
    if not square then return end
    self.feedback = T(_("Hint: %1 moved the piece on %2."), self:_master(), square)
    self:refresh()
    self.board:setShapes({ circles = { { square = square } }, arrows = {} })
end

--- Show move (the master's move, counted as missed), or Next game.
function PkGamesView:showOrNext()
    local s = self.session
    if s:over() then return self:nextGame() end
    if not s:guessing() then return end
    local ply = s:ply() + 1
    local move = s:show()
    self.feedback = T(_("%1 played %2 %3."), self:_master(), moveNumber(ply), move.san)
    self.board:showMove(move)
    self:_afterStep()
end

-- The game is over: its best score kept.
function PkGamesView:_finished()
    local s = self.session
    local got, max = s:points()
    local best = PkGamesView._setting("games.best." .. s.game.id)
    local old_got, old_max = (best or ""):match("^(%d+)/(%d+)$")
    if max > 0 and (not old_got or got / max > tonumber(old_got) / math.max(1, tonumber(old_max))) then
        PkGamesView._saveSetting("games.best." .. s.game.id, got .. "/" .. max)
    end
end

--- The next game of the list (after this one), the winner's side.
function PkGamesView:nextGame()
    local list = PkGames.list()
    for i, g in ipairs(list) do
        if g.id == self.session.game.id then
            local nxt = list[i % #list + 1]
            return self:start(PkGames.session(nxt))
        end
    end
end

--- Opens the analysis board with the game so far (over: the whole game),
-- at `ply` (default: the position shown).
function PkGamesView:analyse(ply)
    local moves = self.session:history()
    return require("pkanalysis").show{
        moves = moves,
        pos = ply or #moves,
        flipped = self.board and self.board.flipped,
    }
end

function PkGamesView:onListSelect(ply)
    self:analyse(ply)
end

-- The session in progress kept (none once the game is over).
function PkGamesView:_save()
    local s = self.session
    PkGamesView._saveSetting("games.current", (not s:over()) and s:serialize() or nil)
end

---------------------------------------------------------------------------
-- Display

function PkGamesView:_lineText()
    local sans = self.game.history()
    if #sans == 0 then return nil end
    local first = math.max(1, #sans - LINE_PLIES + 1)
    local parts = first > 1 and { "…" } or {}
    for i = first, #sans do
        if i % 2 == 1 then
            parts[#parts + 1] = math.floor((i + 1) / 2) .. ". " .. sans[i]
        elseif i == first then
            parts[#parts + 1] = math.floor(i / 2) .. "… " .. sans[i]
        else
            parts[#parts + 1] = sans[i]
        end
    end
    return table.concat(parts, " ")
end

function PkGamesView:_status()
    local s = self.session
    if s:over() then
        local lines = { T(_("Game over: %1."), s.game.result) }
        local got, max = s:points()
        local pct = max > 0 and math.floor(100 * got / max + 0.5) or nil
        lines[#lines + 1] = s:scoreText() .. (pct and T(" · %1%", pct) or "")
        if s.keys > 0 then lines[#lines + 1] = T(_("Key moments: %1 of %2"), s.keys_found, s.keys) end
        -- a better score before: shown (the panel is short)
        local best = PkGamesView.best(s.game.id)
        if best and pct and best > pct then lines[#lines + 1] = T(_("Your best for this game: %1%"), best) end
        return table.concat(lines, "\n")
    end
    if s:guessing() then
        if s:keyMoment() then
            return T(_("Key moment: one move stands out. What did %1 play?"), self:_master())
        end
        return T(_("What did %1 play?"), self:_master())
    end
    return nil
end

--- Redraws board, panel, list and buttons from the session (`page`: the
-- whole screen).
function PkGamesView:refresh(page)
    local s, board = self.session, self.board
    if board.selected then
        board:unmarkSelected(board.selected)
        board.selected = nil
    end
    local history = s:history()
    local last = history[#history]
    board:setHighlights(last and { last.from, last.to } or {})
    board:setBadge(nil)
    board:setShapes(nil)
    board:setLocked(not s:guessing())
    local lines = {}
    if self.feedback then lines[#lines + 1] = self.feedback end
    local status = self:_status()
    if status then lines[#lines + 1] = status end
    if not self.movelist then
        local line = self:_lineText()
        if line then lines[#lines + 1] = line end
    end
    local fens = {}
    do
        local probe = require("pkchess"):new()
        probe.reset()
        fens[1] = probe.fen()
        for _, m in ipairs(history) do
            probe.move({ from = m.from, to = m.to, promotion = m.promotion })
            fens[#fens + 1] = probe.fen()
        end
    end
    local opening = PkOpeningNames.latest(fens)
    if opening then lines[#lines + 1] = opening end
    self:_setText(table.concat(lines, "\n"))
    local sans = {}
    for i, m in ipairs(history) do sans[i] = m.san end
    self:_setListMoves(sans, #sans, 1, false)
    PkRefresh.enable(self, self.buttons:getButtonById("hint"), s:guessing())
    local show = self.buttons:getButtonById("show")
    local text = s:over() and _("Next game") or _("Show move")
    if show.text ~= text then show:setText(text, show.width) end
    PkRefresh.enable(self, show, s:guessing() or s:over())
    PkRefresh.setSubTitle(self, self:_subtitle())
    self:_redraw(page)
end

-- "Morphy – Isouard · Paris 1858", then the score once guessing started
function PkGamesView:_subtitle()
    local s, g = self.session, self.session.game
    local head = T("%1 · %2", PkGames.players(g), PkGames.place(g))
    if s.asked == 0 then return head end
    return T("%1 · %2", PkGames.players(g), s:scoreText())
end

---------------------------------------------------------------------------
-- Menu, closing

function PkGamesView:showMenu()
    local s = self.session
    local other = s.side == "w" and "b" or "w"
    local dialog
    local function close() UIManager:close(dialog); self.menu_dialog = nil end
    local function restart(side)
        close()
        local function go() self:start(PkGames.session(s.game, side)) end
        if s.asked == 0 or s:over() then return go() end
        UIManager:show(ConfirmBox:new{
            text = _("Start this game again? The moves guessed so far are lost."),
            ok_text = _("Start again"),
            ok_callback = go,
        })
    end
    local buttons = {
        {{ text = T(_("Guess %1’s moves instead"), other == "w" and s.game.white or s.game.black),
           callback = function() restart(other) end }},
        {
            { text = _("Start again"), callback = function() restart(s.side) end },
            { text = self.list_shown and _("Hide move list") or _("Show move list"),
              callback = function() close(); self:toggleList() end },
        },
        {{ text = _("Master games…"), callback = function()
            close()
            self:onClose()
            PkGamesView.showList()
        end }},
    }
    buttons[#buttons + 1] = PkNav.moreRow(close, "games")
    dialog = ButtonDialog:new{ buttons = buttons }
    self.menu_dialog = dialog
    UIManager:show(dialog)
end

function PkGamesView:toggleList()
    self.list_shown = not self.list_shown
    PkGamesView._saveSetting("games.movelist", self.list_shown and "1" or "0")
    self:_build(self.board.flipped)
    self:refresh(true)
end

function PkGamesView:onClose()
    PkRefresh.close(self)
    return true
end

function PkGamesView:onCloseWidget()
    self:_cancelReply()
    if self.session then self:_save() end
    if self.board then self.board:free() end
    if self.text then self.text:free() end
end

return PkGamesView
