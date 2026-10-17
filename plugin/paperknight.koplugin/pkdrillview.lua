-- Openings drill screen (ADR-0012, docs/openings.md): board + panel + buttons
-- over a PkDrill session. Logic lives in pkdrill.lua; this file displays.
local ButtonDialog = require("ui/widget/buttondialog")
local ButtonTable = require("ui/widget/buttontable")
local Device = require("device")
local Geometry = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local Screen = Device.screen
local Size = require("ui/size")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local util = require("util")
local _ = require("gettext")
local T = require("ffi/util").template

local PkLinks = require("pklinks")
local PkRefresh = require("pkrefresh")
local PkPgn = require("pkpgn")
local PkStudy = require("pkstudy")
local ChessBoard = require("pkboard")
local PkOpeningNames = require("pkopeningnames")
local PkProgress = require("pkprogress")
local PkNav = require("pknav")
local PkSide = require("pkside")

local REPLY_DELAY = 0.8 -- seconds before the opponent's move

local PkDrillView = InputContainer:extend{
    name = "paperknight_drill",
    covers_fullscreen = true,
    drill = nil,     -- PkDrill (its game is the board's game)
    title = nil,     -- repertoire name
    reply_delay = REPLY_DELAY,
    on_close = nil,  -- called after the screen closes (e.g. close the database)
    on_flip = nil,   -- function(chapter): play the other side in that chapter
}
-- board + text panel + buttons, the panel's text and refreshes (pkboardscreen.lua)
require("pkboardscreen").mixin(PkDrillView)

function PkDrillView:init()
    PkNav.tapTitle(self, function() return self.title_bar end, "openings") -- quick settings
    PkSide.followNight(self, function(v) if v.raw_text then v:_setText(PkSide.swap(v.raw_text)) end end)
    self.dimen = Geometry:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    if Device:hasKeys() then
        self.key_events = {
            Close = { { Device.input.group.Back } },
            Forward = { { Device.input.group.PgFwd } }, -- Continue / Next line
        }
    end
    self.game = self.drill.game
    -- the move list beside the board (☰ Hide/Show move list, remembered):
    -- the moves played only, which give nothing away
    self.list_shown = PkProgress.readSetting("drill.movelist") ~= "0"
    -- the user's known moves that are not due: played for them unless
    -- ☰ → Play my known moves (remembered)
    self.drill.play_known = PkProgress.readSetting("drill.play_known") == "1"
    self.title_bar = TitleBar:new{
        fullscreen = true,
        title = util.fixUtf8(self.title or _("Openings"), "?"),
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
            { id = "solution", text = _("Solution"), callback = function() self:solution() end },
            -- Continue (after a commented move) or Next line (line over)
            { id = "next", text = _("Next line"), callback = function() self:onForward() end },
        }},
        zero_sep = true,
    }
    local free_h = self.dimen.h - self.title_bar:getHeight() - self.buttons:getSize().h
    self.board_size = math.min(self.dimen.w, math.floor(free_h * 0.68))
    self.text_h = free_h - self.board_size - 3 * Size.padding.default
    self:nextLine()
end

function PkDrillView:_build(flipped)
    self:_buildScreen(flipped)
end

--- Starts the next line of the session, or shows the summary when done.
function PkDrillView:nextLine()
    self:_cancelReply()
    self.waiting = false
    self._last_line = self.drill.line or self._last_line
    local line = self.drill:nextLine()
    if not line then
        self.game.reset()
        self:_build(self.board and self.board.flipped or false)
        self:refresh(nil, true)
        return
    end
    self:_build(line.student == "b")
    self:refresh(nil, true)
    self:_paceOpponent()
end

--- Redraws board and panel from the drill state. `prefix`: an instruction
-- or feedback line. The panel stays quiet: one short line, then the
-- annotator's words; the opening name is in the subtitle, whose move it is
-- in the board's corner, the current move in the move list.
function PkDrillView:refresh(prefix, full)
    local drill, board = self.drill, self.board
    if board.selected then
        board:unmarkSelected(board.selected)
        board.selected = nil
    end
    board:updateBoard()
    local node = drill.state ~= "done" and drill.cursor and drill.cursor.node or nil
    board:setHighlights(node and node.move and { node.move.from, node.move.to } or {})
    board:setShapes(nil)
    board:setBadge(node and node.move and node.move.to, PkStudy.moveMark(node))
    local counts = drill:counts()
    local opening = node and PkOpeningNames.forNode(node)
    local due = T(_("%1 due · %2 new"), counts.due, counts.new_today)
    PkRefresh.setSubTitle(self, opening and (opening .. " · " .. due) or due)

    local lines = {}
    if prefix then lines[#lines + 1] = prefix end
    local state = drill.state
    local playing = state == "play" and not self.waiting
    board:setLocked(not playing)
    if state == "done" then
        lines[#lines + 1] = _("All done for today.")
        lines[#lines + 1] = T(_("Reviewed: %1 · Mistakes: %2"), drill.reviewed, drill.failed)
        if counts.new > 0 then
            lines[#lines + 1] = T(_("%1 new moves are waiting for the next days."), counts.new)
        end
    elseif state == "end" then
        lines[#lines + 1] = _("Line complete.")
    elseif playing and drill:mode() == "intro" then
        local expected = drill:expected()
        lines[#lines + 1] = T(_("New move: play %1."), expected.move.san)
        -- the move to learn, as an arrow
        board:setShapes({ circles = {}, arrows = { { from = expected.move.from, to = expected.move.to } } })
    end
    if node and node.parent then
        -- the move shown is framed in the move list; written out without it
        if not self.movelist then lines[#lines + 1] = PkStudy.moveLabel(node, "move") end
        lines[#lines + 1] = PkPgn.positionWords(node.glyphs)
        if node.comment then lines[#lines + 1] = node.comment end
    end
    if playing and drill:mode() == "intro" and drill:expected().comment then
        lines[#lines + 1] = drill:expected().comment -- why this move
    end
    self:_setText(table.concat(lines, "\n"))
    self:_updateList(node)
    self.buttons:getButtonById("hint"):enableDisable(playing and drill:mode() ~= "intro")
    self.buttons:getButtonById("solution"):enableDisable(playing)
    self:_setNextButton(self.waiting and _("Continue") or _("Next line"), self.waiting or state == "end")
    self:_redraw(full)
end

-- The third button: Continue (after a commented move) or Next line.
function PkDrillView:_setNextButton(text, enabled)
    local button = self.buttons:getButtonById("next")
    if button.text ~= text then button:setText(text, button.width) end
    button:enableDisable(enabled)
end

--- Continue after a commented move, or the next line once one is over
-- (the third button, or the page-turn key).
function PkDrillView:onForward()
    if self.waiting then
        self.waiting = false
        self:_cancelReply()
        self.drill:opponentReply()
        self:refresh()
        self:_paceOpponent()
    elseif self.drill.state == "end" or self.drill.state == "done" then
        self:nextLine()
    end
    return true
end

-- Opponent moves are played automatically after a short delay.
function PkDrillView:_paceOpponent()
    if self.drill.state ~= "reply" or self.waiting then return end
    self._reply_task = function()
        self._reply_task = nil
        if self.drill.state ~= "reply" then return end
        self.drill:opponentReply()
        self:refresh()
        self:_paceOpponent()
    end
    UIManager:scheduleIn(self.reply_delay, self._reply_task)
end

function PkDrillView:onBoardMove(move)
    self:_takeBackMove() -- the drill decides what the position is
    if self.drill.state ~= "play" or self.waiting then return self:refresh() end
    local mode = self.drill:mode()
    self:_afterVerdict(mode, self.drill:onUserMove(move.from, move.to, move.promotion))
end

-- After a move at the user's turn (`mode`: of the move asked). A right move
-- gets a ✓ on its piece (no text); if it has a comment, the opponent waits
-- for Continue, so that it can be read (except a new move, whose comment
-- was shown before it).
function PkDrillView:_afterVerdict(mode, verdict, node)
    if verdict == "good" or verdict == "end" then
        self.waiting = verdict == "good" and node.comment ~= nil and mode ~= "intro"
            and self.drill.state == "reply"
        self:refresh()
        self.board:setBadge(node.move.to, ChessBoard.TICK)
        if verdict == "good" and not self.waiting then self:_paceOpponent() end
    elseif verdict == "bad" then
        self:refresh(_("Not in your repertoire.") .. (node.comment and ("\n" .. node.comment) or "")
            .. "\n" .. _("Try again."))
    else
        self:refresh(_("Not the move. Try again."))
    end
end

function PkDrillView:hint()
    local square = self.drill:hint()
    if not square then return end
    self:refresh(T(_("Hint: move the piece on %1."), square))
    self.board:setShapes({ circles = { { square = square } }, arrows = {} })
    UIManager:setDirty(self, "ui", self.board.dimen)
end

function PkDrillView:solution()
    local mode = self.drill:mode()
    local verdict, node = self.drill:solution()
    if verdict then self:_afterVerdict(mode, verdict, node) end
end

-- The move list: the moves of the line up to the position shown.
function PkDrillView:_updateList(node)
    if not self.movelist then return end
    local nodes = {}
    local n = node
    while n and n.parent do table.insert(nodes, 1, n); n = n.parent end
    local sans = {}
    for i, nd in ipairs(nodes) do sans[i] = nd.move and nd.move.san or nd.san end
    local ply = (n and n.ply) or 0 -- the root's
    self:_setListMoves(sans, #nodes, math.floor(ply / 2) + 1, ply % 2 == 1)
end

--- Shows or hides the move list (remembered).
function PkDrillView:toggleList()
    self.list_shown = not self.list_shown
    PkProgress.writeSetting("drill.movelist", self.list_shown and "1" or "0")
    self:_build(self.board and self.board.flipped or false)
    self:refresh(nil, true)
end

--- Title-bar menu: switch the side played in the current line's chapter
-- (e.g. a PGN saved from the Lichess website without [Orientation]).
function PkDrillView:showMenu()
    local line = self.drill.line or self._last_line
    local chapter = line and line.chapter
    local dialog
    local function close() UIManager:close(dialog); self.menu_dialog = nil end
    local buttons = {
        {{ text = chapter and T(_("Play the other side (chapter %1)"), chapter) or _("Play the other side"),
           enabled = chapter ~= nil and self.on_flip ~= nil,
           callback = function()
               close()
               local on_flip = self.on_flip
               self:onClose()
               on_flip(chapter)
           end }},
    }
    buttons[#buttons + 1] = {{ text = self.list_shown and _("Hide move list") or _("Show move list"),
        callback = function() close(); self:toggleList() end }}
    -- the user's known moves that are not due: played for them, or by them
    buttons[#buttons + 1] = {{ text = _("Play my known moves too"), checked_func = function() return self.drill.play_known end,
        callback = function()
            close()
            self.drill.play_known = not self.drill.play_known
            PkProgress.writeSetting("drill.play_known", self.drill.play_known and "1" or nil)
        end }}
    buttons[#buttons + 1] = PkLinks.menuRow(self.links, close)
    buttons[#buttons + 1] = PkNav.moreRow(close, "openings")
    dialog = ButtonDialog:new{ buttons = buttons }
    self.menu_dialog = dialog
    UIManager:show(dialog)
end

function PkDrillView:onClose()
    PkRefresh.close(self)
    return true
end

function PkDrillView:onCloseWidget()
    self:_cancelReply()
    if self.board then self.board:free() end
    if self.text then self.text:free() end
    if self.on_close then self.on_close() end
end

return PkDrillView
