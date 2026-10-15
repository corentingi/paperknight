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
        self.key_events = { Close = { { Device.input.group.Back } } }
    end
    self.game = self.drill.game
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
            { id = "next", text = _("Next line"), callback = function() self:nextLine() end },
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

--- Redraws board and panel from the drill state. `prefix`: feedback line.
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
    PkRefresh.setSubTitle(self, T(_("Due: %1 · New today: %2"), counts.due, counts.new_today))

    local parts = {}
    if prefix then parts[#parts + 1] = prefix end
    local state = drill.state
    board.locked = state ~= "play"
    if state == "done" then
        parts[#parts + 1] = _("All done for today.")
        parts[#parts + 1] = T(_("Reviewed: %1 · Mistakes: %2"), drill.reviewed, drill.failed)
        if counts.new > 0 then
            parts[#parts + 1] = T(_("%1 new moves are waiting for the next days."), counts.new)
        end
    elseif state == "end" then
        parts[#parts + 1] = _("Line complete. Tap Next line.")
    elseif state == "play" then
        local expected = drill:expected()
        local mode = drill:mode()
        if mode == "intro" then
            parts[#parts + 1] = T(_("New move: play %1."), expected.move.san)
            -- the move to learn, as an arrow
            board:setShapes({ circles = {}, arrows = { { from = expected.move.from, to = expected.move.to } } })
        else
            parts[#parts + 1] = T(_("Your move (%1)."), PkSide.name(drill.line.student))
        end
    end
    if node and node.parent then
        parts[#parts + 1] = PkStudy.moveLabel(node, "move")
        parts[#parts + 1] = PkPgn.positionWords(node.glyphs)
        if node.comment then parts[#parts + 1] = node.comment end
    end
    if state == "play" and drill:mode() == "intro" and drill:expected().comment then
        parts[#parts + 1] = drill:expected().comment -- why this move
    end
    self:_setText(table.concat(parts, "\n\n"))
    local playing = state == "play"
    self.buttons:getButtonById("hint"):enableDisable(playing and drill:mode() ~= "intro")
    self.buttons:getButtonById("solution"):enableDisable(playing)
    self.buttons:getButtonById("next"):enableDisable(state == "end")
    self:_redraw(full)
end

-- Opponent moves are played automatically after a short delay.
function PkDrillView:_paceOpponent()
    if self.drill.state ~= "reply" then return end
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
    if self.drill.state ~= "play" then return self:refresh() end
    self:_afterVerdict(self.drill:onUserMove(move.from, move.to, move.promotion))
end

function PkDrillView:_afterVerdict(verdict, node)
    if verdict == "good" then
        self:refresh(_("Correct!"))
        self:_paceOpponent()
    elseif verdict == "end" then
        self:refresh(_("Correct!"))
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
    local verdict, node = self.drill:solution()
    if verdict then self:_afterVerdict(verdict, node) end
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
    buttons[#buttons + 1] = PkLinks.menuRow(self.links, close)
    for _, row in ipairs(PkNav.quickRows(close, "openings")) do buttons[#buttons + 1] = row end
    dialog = ButtonDialog:new{ buttons = buttons }
    self.menu_dialog = dialog
    UIManager:show(dialog)
end

function PkDrillView:onClose()
    UIManager:close(self)
    return true
end

function PkDrillView:onCloseWidget()
    self:_cancelReply()
    if self.board then self.board:free() end
    if self.text then self.text:free() end
    if self.on_close then self.on_close() end
end

return PkDrillView
