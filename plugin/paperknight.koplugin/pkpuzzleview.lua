-- Puzzle screen (ADR-0009): board + status + Hint / Solution / Retry / Next.
-- Judging lives in pkpuzzle.lua, storage in pkpuzzlepack.lua / pkprogress.lua.
local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geometry = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local Screen = require("device").screen
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template

local Chess = require("chess")
local ChessBoard = require("board")
local PkPromotion = require("pkpromotion")
local PkPuzzle = require("pkpuzzle")
local PkThemes = require("pkthemes")
local Menu = require("ui/widget/menu")

local REPLY_DELAY = 0.6 -- seconds before the opponent replies, so the user sees their move first
local RECENT_DAYS = 30  -- don't repeat puzzles attempted this recently (ADR-0010)

local PkPuzzleView = InputContainer:extend{
    name = "paperknight_puzzles",
    covers_fullscreen = true,
    pack = nil,      -- PkPuzzlePack (owned: closed with the view)
    progress = nil,  -- PkProgress (owned: closed with the view)
    random = nil,    -- optional function() -> [0,1), for tests
    reply_delay = REPLY_DELAY,
}

function PkPuzzleView:init()
    self.dimen = Geometry:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    if Device:hasKeys() then
        self.key_events = { Close = { { Device.input.group.Back } } }
    end
    self.game = Chess:new()
    self.title_bar = TitleBar:new{
        fullscreen = true,
        title = _("Puzzles"),
        subtitle = "",
        with_bottom_line = true,
        left_icon = "appbar.menu",
        left_icon_tap_callback = function() self:showThemeMenu() end,
        close_callback = function() self:onClose() end,
    }
    self.theme = self.progress:getSetting("theme") -- nil = all themes
    if self.theme and not self:_packHasTheme(self.theme) then
        -- saved with an older pack that had this theme: fall back to all themes
        self.theme = nil
        self.progress:setSetting("theme", nil)
    end
    self.status = TextBoxWidget:new{
        text = "",
        face = Font:getFace("cfont", 20),
        width = self.dimen.w - 2 * Size.padding.large,
        height = Screen:scaleBySize(80),
        alignment = "center",
    }
    self.buttons = ButtonTable:new{
        width = self.dimen.w - 2 * Size.padding.default,
        buttons = {{
            { id = "hint", text = _("Hint"), callback = function() self:onHint() end },
            { id = "solution", text = _("Solution"), callback = function() self:onSolution() end },
            { id = "retry", text = _("Retry"), callback = function() self:onRetry() end },
            { id = "next", text = _("Next"), callback = function() self:nextPuzzle() end },
        }},
        zero_sep = true,
    }
    local board_h = self.dimen.h - self.title_bar:getHeight() - self.status:getSize().h
        - self.buttons:getSize().h - 4 * Size.padding.default
    self.board_size = math.min(self.dimen.w, board_h)
    self:_prepareBoard(false) -- the frame exists even if no puzzle can be picked
    self:nextPuzzle()
end

-- (Re)builds the board only when the orientation changes; otherwise the
-- existing board is reused and simply redrawn.
function PkPuzzleView:_prepareBoard(flipped)
    if self.board and self.board.flipped == flipped then
        if self.board.selected then
            self.board:unmarkSelected(self.board.selected)
            self.board.selected = nil
        end
        self.board:setHighlights({})
        return
    end
    if self.board then self.board:free() end
    self.board = ChessBoard:new{
        game = self.game,
        width = self.board_size,
        height = self.board_size,
        flipped = flipped,
        show_parent = self, -- the board repaints through this window (selection overlay)
        moveCallback = function(move) self:onUserMove(move) end,
        onPromotionNeeded = function(from, to, color)
            PkPromotion.show(color, function(letter)
                local move = self.game.move({ from = from, to = to, promotion = letter })
                if move then self.board:handleGameMove(move) end
            end)
        end,
    }
    self[1] = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        width = self.dimen.w,   -- cover the whole screen, or the file manager
        height = self.dimen.h,  -- shows through below the buttons
        VerticalGroup:new{
            align = "center",
            self.title_bar,
            CenterContainer:new{
                dimen = Geometry:new{ w = self.dimen.w, h = self.board_size + 2 * Size.padding.default },
                self.board,
            },
            self.status,
            self.buttons,
        },
    }
end

function PkPuzzleView:_updateTitle()
    local rating = self.progress:rating()
    local subtitle = T(_("Your rating: %1"), rating)
    if self.puzzle then
        subtitle = subtitle .. " · " .. T(_("Puzzle %1"), self.puzzle.rating)
    end
    if self.theme then -- last: a long theme name may be cut off
        subtitle = subtitle .. " · " .. PkThemes.label(self.theme)
    end
    self.title_bar:setSubTitle(subtitle)
end

function PkPuzzleView:_setStatus(text)
    self.status:setText(text)
    UIManager:setDirty(self, "ui")
end

local function sideName(color)
    return color == Chess.WHITE and _("White") or _("Black")
end

function PkPuzzleView:_toMoveText()
    return T(_("%1 to move. Find the best move."), sideName(self.session:solverColor()))
end

--- Starts `puzzle` (a pack row), or a new pick near the user's rating if nil.
function PkPuzzleView:loadPuzzle(puzzle)
    self:_cancelReply()
    self:_finishAttempt("skipped")
    self.puzzle = puzzle
    self.session = PkPuzzle.new(puzzle, self.game)
    self.recorded = false
    self:_prepareBoard(puzzle.solver == Chess.BLACK)
    local setup = self.session:start()
    self.board:updateBoard()
    self.board:setHighlights({ setup.from, setup.to })
    self.board.locked = false
    self:_updateTitle()
    self:_setStatus(self:_toMoveText())
    logger.info("Paperknight: puzzle", puzzle.id, "rating", puzzle.rating)
    UIManager:setDirty(self, "full") -- new position: full refresh clears e-ink ghosting
end

function PkPuzzleView:_packHasTheme(theme)
    for _, t in ipairs(self.pack:themes()) do
        if t.theme == theme and t.count > 0 then return true end
    end
    return false
end

--- Picks and loads the next puzzle. Returns true on success.
function PkPuzzleView:nextPuzzle()
    local since = os.time() - RECENT_DAYS * 86400
    local puzzle = self.pack:pickNear(self.progress:rating(), {
        random = self.random,
        theme = self.theme,
        accept = function(p)
            return not (self.puzzle and p.id == self.puzzle.id)
                and not self.progress:wasAttemptedSince(p.id, since)
        end,
    })
    if not puzzle then
        self:_updateTitle()
        self:_setStatus(self.theme and _("No puzzles with this theme in the pack.")
            or _("No puzzles found in the pack."))
        return false
    end
    self:loadPuzzle(puzzle)
    return true
end

-- Records the attempt once (ADR-0010): when the puzzle ends, or when the user
-- leaves it after having made a mistake or asked for help.
function PkPuzzleView:_finishAttempt(reason)
    local s = self.session
    if not s or self.recorded then return end
    -- Touched: a mistake, help, or at least one correct move (part of the line seen).
    local touched = s.mistakes > 0 or s.used_help or s.index > 2
    if not s:isOver() and not touched then return end
    self.recorded = true
    local before, after = self.progress:record{
        puzzle_id = self.puzzle.id,
        puzzle_rating = self.puzzle.rating,
        success = s:isCleanSolve(),
        solved = s.state == "solved",
        mistakes = s.mistakes,
        used_help = s.used_help,
    }
    logger.info("Paperknight: attempt", self.puzzle.id, reason, before, "->", after)
    return before, after
end

function PkPuzzleView:onUserMove(move)
    local verdict, reply = self.session:onUserMove(move)
    if verdict == "wrong" then
        self.board:updateBoard() -- the move was taken back
        self:_setStatus(_("Not the move. Try again."))
        return
    end
    self.board:setHighlights({ move.from, move.to })
    if verdict == "solved" then
        self.board.locked = true
        local before, after = self:_finishAttempt("solved")
        local text = (self.session:isCleanSolve() and _("Solved!"))
            or (self.session.used_help and _("Solved, with help."))
            or _("Solved, after a mistake.")
        if before then
            text = text .. "\n" .. T(_("Rating %1 → %2"), before, after)
        end
        self:_updateTitle()
        self:_setStatus(text)
        return
    end
    -- correct, more to come: show the opponent's reply (already played in the
    -- game) after a short pause, unless the user moves on first.
    self.board.locked = true
    self:_setStatus(_("Correct! Keep going."))
    self._pending_reply = reply
    self._reply_task = function()
        self._reply_task = nil
        self:_showReply()
    end
    UIManager:scheduleIn(self.reply_delay, self._reply_task)
end

function PkPuzzleView:_showReply()
    local reply = self._pending_reply
    if not reply then return end
    self._pending_reply = nil
    self.board:showMove(reply)
    self.board:setHighlights({ reply.from, reply.to })
    self.board.locked = false
    self:_setStatus(_("Correct! Keep going.") .. "\n" .. self:_toMoveText())
end

-- Drops a scheduled reply. Returns true if one was pending.
function PkPuzzleView:_cancelReply()
    if self._reply_task then
        UIManager:unschedule(self._reply_task)
        self._reply_task = nil
    end
    local pending = self._pending_reply ~= nil
    self._pending_reply = nil
    return pending
end

-- Shows a pending reply right away (before Hint, so the hint isn't wiped).
function PkPuzzleView:_flushReply()
    if self._reply_task then
        UIManager:unschedule(self._reply_task)
        self._reply_task = nil
    end
    self:_showReply()
end

--- Theme picker: "All themes" + the pack's themes with counts (pack format:
-- `themes` table). The current choice is marked with a check mark.
function PkPuzzleView:showThemeMenu()
    local function mark(text, selected) return selected and ("✓ " .. text) or text end
    local items = {{
        text = mark(_("All themes"), self.theme == nil),
        callback = function() self:setTheme(nil) end,
    }}
    for _, t in ipairs(PkThemes.sorted(self.pack:themes())) do
        items[#items + 1] = {
            text = mark(PkThemes.label(t.theme), self.theme == t.theme),
            mandatory = tostring(t.count),
            callback = function() self:setTheme(t.theme) end,
        }
    end
    self.theme_menu = Menu:new{
        title = T(_("Puzzle theme: %1"), self.theme and PkThemes.label(self.theme) or _("All themes")),
        item_table = items,
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
    }
    self.theme_menu.close_callback = function()
        UIManager:close(self.theme_menu)
        self.theme_menu = nil
    end
    UIManager:show(self.theme_menu)
end

function PkPuzzleView:setTheme(theme)
    if theme == self.theme then return end -- don't abandon the current puzzle
    local previous = self.theme
    self.theme = theme
    if self:nextPuzzle() then
        self.progress:setSetting("theme", theme)
    else
        self.theme = previous
        self:_updateTitle()
    end
end

function PkPuzzleView:onHint()
    if not self.session then return end
    self:_flushReply()
    local square = self.session:hint()
    if not square then return end
    self.board:clearSelection()
    self.board:setHighlights({ square })
    self:_setStatus(T(_("Hint: move the piece on %1."), square))
end

function PkPuzzleView:onSolution()
    if not self.session or self.session:isOver() then return end
    self:_cancelReply() -- the reply is already in the game; the redraw below shows it
    local played = self.session:revealSolution()
    self.board:clearSelection()
    self.board:updateBoard()
    local last = played[#played]
    if last then self.board:setHighlights({ last.from, last.to }) end
    self.board.locked = true
    local before, after = self:_finishAttempt("solution")
    local text = _("Solution shown.")
    if before then text = text .. "\n" .. T(_("Rating %1 → %2"), before, after) end
    self:_updateTitle()
    self:_setStatus(text)
end

--- Replays the current puzzle from the start. Rating is only affected by the
-- first attempt, which is recorded before restarting.
function PkPuzzleView:onRetry()
    if not self.puzzle then return end
    self:_cancelReply()
    self:_finishAttempt("retry")
    local recorded = self.recorded
    self:loadPuzzle(self.puzzle)
    self.recorded = recorded
end

function PkPuzzleView:onClose()
    UIManager:close(self)
    return true
end

-- Runs however the view is closed (X, Back key, or programmatically).
function PkPuzzleView:onCloseWidget()
    self:_cancelReply()
    self:_finishAttempt("closed")
    if self.pack then self.pack:close() end
    if self.progress then self.progress:close() end
end

return PkPuzzleView
