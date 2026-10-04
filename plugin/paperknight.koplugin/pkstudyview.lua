-- Study viewer (ADR-0011, docs/studies.md): board + comment panel + navigation.
-- Tree logic lives in pkstudy.lua; this file only displays and dispatches.
local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geometry = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local Menu = require("ui/widget/menu")
local Screen = Device.screen
local ScrollTextWidget = require("ui/widget/scrolltextwidget")
local Size = require("ui/size")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template

local Chess = require("chess")
local ChessBoard = require("board")
local PkLesson = require("pklesson")
local PkPromotion = require("pkpromotion")
local PkStudy = require("pkstudy")

local REPLY_DELAY = 0.8 -- seconds before the opponent's reply in a lesson

local PkStudyView = InputContainer:extend{
    name = "paperknight_study",
    covers_fullscreen = true,
    study = nil,         -- PkStudy
    chapter_index = 1,
    reply_delay = REPLY_DELAY,
}

function PkStudyView:init()
    self.dimen = Geometry:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    if Device:hasKeys() then
        self.key_events = {
            Close = { { Device.input.group.Back } },
            Forward = { { Device.input.group.PgFwd } },
            Backward = { { Device.input.group.PgBack } },
        }
    end
    self.game = Chess:new()
    self.title_bar = TitleBar:new{
        fullscreen = true,
        title = "",
        subtitle = "",
        title_shrink_font_to_fit = true,
        with_bottom_line = true,
        left_icon = "appbar.menu",
        left_icon_tap_callback = function() self:showChapterMenu() end,
        close_callback = function() self:onClose() end,
    }
    self.browse_buttons = ButtonTable:new{
        width = self.dimen.w - 2 * Size.padding.default,
        buttons = {{
            { id = "start", icon = "chevron.first", callback = function() self:toStart() end },
            { id = "back", icon = "chevron.left", callback = function() self:back() end },
            { id = "lines", text = _("Lines"), callback = function() self:showLines() end },
            { id = "forward", icon = "chevron.right", callback = function() self:forward() end },
            { id = "end", icon = "chevron.last", callback = function() self:toEnd() end },
            { id = "train", text = _("Train"), callback = function() self:startLesson() end },
        }},
        zero_sep = true,
    }
    self.lesson_buttons = ButtonTable:new{
        width = self.dimen.w - 2 * Size.padding.default,
        buttons = {{
            { id = "hint", text = _("Hint"), callback = function() self:lessonHint() end },
            { id = "solution", text = _("Solution"), callback = function() self:lessonSolution() end },
            { id = "next", text = _("Next"), callback = function() self:lessonNext() end },
            { id = "restart", text = _("Restart"), callback = function() self:startLesson() end },
            { id = "browse", text = _("Browse"), callback = function() self:stopLesson() end },
        }},
        zero_sep = true,
    }
    self.buttons = self.browse_buttons
    local free_h = self.dimen.h - self.title_bar:getHeight() - self.buttons:getSize().h
    self.board_size = math.min(self.dimen.w, math.floor(free_h * 0.68))
    self.text_h = free_h - self.board_size - 3 * Size.padding.default
    self:loadChapter(self.chapter_index)
end

function PkStudyView:_build()
    local orientation_black = self.chapter.orientation == "black"
    if not self.board or self.board.flipped ~= orientation_black then
        if self.board then self.board:free() end
        self.board = ChessBoard:new{
            game = self.game,
            width = self.board_size,
            height = self.board_size,
            flipped = orientation_black,
            show_parent = self,
            moveCallback = function(move) self:onBoardMove(move) end,
            onPromotionNeeded = function(from, to, color)
                PkPromotion.show(color, function(letter)
                    local move = self.game.move({ from = from, to = to, promotion = letter })
                    if move then self.board:handleGameMove(move) end
                end)
            end,
        }
    end
    if self.text then self.text:free() end
    self.text = self:_textWidget("")
    self.vgroup = VerticalGroup:new{
        align = "center",
        self.title_bar,
        CenterContainer:new{
            dimen = Geometry:new{ w = self.dimen.w, h = self.board_size + Size.padding.default },
            self.board,
        },
        self.text,
        self.buttons,
    }
    self[1] = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        width = self.dimen.w,
        height = self.dimen.h,
        self.vgroup,
    }
end

function PkStudyView:_textWidget(text)
    return ScrollTextWidget:new{
        text = text,
        face = Font:getFace("cfont", 18),
        width = self.dimen.w - 2 * Size.padding.large,
        height = self.text_h,
        dialog = self,
    }
end

-- Swaps the button row (browse <-> lesson).
function PkStudyView:_setButtons(tbl)
    if self.buttons == tbl then return end
    for i, w in ipairs(self.vgroup) do
        if w == self.buttons then self.vgroup[i] = tbl end
    end
    self.buttons = tbl
    self.vgroup:resetLayout()
    UIManager:setDirty(self, "ui")
end

-- ScrollTextWidget has no setText: replace the panel widget.
function PkStudyView:_setText(text)
    self.panel_text = text
    local old = self.text
    self.text = self:_textWidget(text)
    for i, w in ipairs(self.vgroup) do
        if w == old then self.vgroup[i] = self.text end
    end
    old:free()
    self.vgroup:resetLayout()
    UIManager:setDirty(self, "ui")
end

--- Opens chapter `index` at its start position.
function PkStudyView:loadChapter(index)
    self:_cancelReply()
    self.lesson = nil
    self.chapter_index = index
    self.chapter = self.study.chapters[index]
    local cursor, err = self.study:cursor(index, self.game)
    if not cursor then
        logger.warn("Paperknight: cannot open chapter", index, err)
        self.cursor = nil
        self.game.reset()
        self:_build()
        self.board:updateBoard()
        self.board:setHighlights({})
        self.board:setShapes(nil)
        self.board.locked = true
        self:_setButtons(self.browse_buttons)
        for _, id in ipairs({ "start", "back", "lines", "forward", "end", "train" }) do
            self.buttons:getButtonById(id):enableDisable(false)
        end
        self.title_bar:setTitle(self.chapter.title)
        self:_setText(T(_("Cannot open this chapter: %1"), tostring(err)))
        UIManager:setDirty(self, "full")
        return
    end
    for _, id in ipairs({ "start", "back", "forward", "end" }) do
        self.browse_buttons:getButtonById(id):enableDisable(true)
    end
    -- nothing to train in a chapter without moves
    self.browse_buttons:getButtonById("train"):enableDisable(#cursor.root.children > 0)
    self.cursor = cursor
    self:_build()
    self.title_bar:setTitle(self.chapter.title)
    if self.chapter.gamebook then
        self:startLesson()
    else
        self:_setButtons(self.browse_buttons)
        self:refresh()
    end
    UIManager:setDirty(self, "full")
end

-- Text panel: current move (or intro), comment, then what comes next.
function PkStudyView:_panelText()
    local node = self.cursor.node
    local parts = {}
    if node == self.cursor.root then
        parts[#parts + 1] = self.chapter.gamebook and _("Interactive lesson") or _("Start of the chapter")
    else
        parts[#parts + 1] = PkStudy.moveLabel(node)
    end
    if node.comment then parts[#parts + 1] = node.comment end
    local children = node.children
    if #children == 0 then
        parts[#parts + 1] = (node == self.cursor.root) and _("(no moves)") or _("— End of line —")
    elseif #children > 1 then
        local alts = {}
        for i, child in ipairs(children) do
            local label = self.cursor:resolve(child) and PkStudy.moveLabel(child) or child.san
            alts[#alts + 1] = (i == 1) and (label .. " " .. _("(main)")) or label
        end
        parts[#parts + 1] = T(_("Next: %1"), table.concat(alts, " · "))
    end
    return table.concat(parts, "\n\n")
end

--- Redraws board, highlights, shapes, panel and subtitle for the current node.
-- `prefix`: optional message shown above the panel text.
function PkStudyView:refresh(prefix)
    local node = self.cursor.node
    if self.board.selected then -- a selection from before must not turn the next tap into a move
        self.board:unmarkSelected(self.board.selected)
        self.board.selected = nil
    end
    self.board:updateBoard()
    if node.move then
        self.board:setHighlights({ node.move.from, node.move.to })
    else
        self.board:setHighlights({})
    end
    self.board:setShapes(node.shapes)
    self.board.locked = false
    self.title_bar:setSubTitle(T(_("%1 · Chapter %2/%3"), self.study.name, self.chapter_index, #self.study.chapters))
    if self.lesson then return self:_lessonRefresh(prefix) end
    self:_setText(prefix and (prefix .. "\n\n" .. self:_panelText()) or self:_panelText())
    self.browse_buttons:getButtonById("lines"):enableDisable(#node.children > 1)
    UIManager:setDirty(self, "ui")
end

function PkStudyView:_show(node, err)
    if not node and err and err ~= "end of line" then
        self:_setText(T(_("Cannot play the next move: %1"), err))
        UIManager:setDirty(self, "ui")
        return
    end
    if node then self:refresh() end
end

-- Browse navigation (ignored during a lesson, e.g. from page-turn keys).
function PkStudyView:_canBrowse() return self.cursor ~= nil and self.lesson == nil end
function PkStudyView:forward(i) if self:_canBrowse() then self:_show(self.cursor:forward(i)) end end
function PkStudyView:back() if self:_canBrowse() and self.cursor:back() then self:refresh() end end
function PkStudyView:toStart() if self:_canBrowse() then self.cursor:toStart(); self:refresh() end end
function PkStudyView:toEnd() if self:_canBrowse() then self.cursor:toEnd(); self:refresh() end end
function PkStudyView:onForward() self:forward(); return true end
function PkStudyView:onBackward() self:back(); return true end

--- Alternatives at the next move: main move first, then variations.
function PkStudyView:showLines()
    if not self:_canBrowse() then return end
    local children = self.cursor.node.children
    if #children < 2 then return end
    local rows = {}
    for i, child in ipairs(children) do
        local label = self.cursor:resolve(child) and PkStudy.moveLabel(child) or child.san
        if i == 1 then label = label .. "  " .. _("(main line)") end
        rows[#rows + 1] = {{
            text = label,
            callback = function()
                UIManager:close(self.lines_dialog)
                self.lines_dialog = nil
                self:forward(i)
            end,
        }}
    end
    self.lines_dialog = ButtonDialog:new{ title = _("Choose a line"), buttons = rows }
    UIManager:show(self.lines_dialog)
end

--- A move played on the board follows the study if it exists at this point.
function PkStudyView:onBoardMove(move)
    local promotion = move.promotion
    self.game.undo() -- the cursor decides what the position is
    if self.game.redo_stack then table.remove(self.game.redo_stack) end
    if not self.cursor then return end
    if self.lesson then return self:onLessonMove(move.from, move.to, promotion) end
    local child, i = self.cursor:childForMove(move.from, move.to, promotion)
    if child then
        self:forward(i)
    else
        self:refresh(_("This move is not in the study."))
    end
end

function PkStudyView:showChapterMenu()
    local items = {}
    for i, ch in ipairs(self.study.chapters) do
        local text = ch.title
        if i == self.chapter_index then text = "✓ " .. text end
        items[#items + 1] = {
            text = text,
            mandatory = ch.gamebook and _("lesson") or nil,
            callback = function() self:loadChapter(i) end,
        }
    end
    self.chapter_menu = Menu:new{
        title = self.study.name,
        item_table = items,
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
    }
    self.chapter_menu.close_callback = function()
        UIManager:close(self.chapter_menu)
        self.chapter_menu = nil
    end
    -- open on the page of the current chapter
    self.chapter_menu:switchItemTable(nil, items, self.chapter_index)
    UIManager:show(self.chapter_menu)
end

function PkStudyView:onClose()
    UIManager:close(self)
    return true
end

----------------------------------------------------------------------------
-- Lessons (docs/studies.md "Interactive chapters"; logic in pklesson.lua)
----------------------------------------------------------------------------

local function sideName(color)
    return color == "w" and _("White") or _("Black")
end

--- Starts (or restarts) a lesson on the current chapter. Gamebook chapters
-- treat variations as known mistakes; ordinary chapters as sidelines.
function PkStudyView:startLesson()
    if not self.cursor then return end
    self:_cancelReply()
    local student = (self.chapter.orientation == "black") and "b" or "w"
    self.lesson = PkLesson.new(self.cursor, student, { variations_are_mistakes = self.chapter.gamebook == true })
    self.lesson:start()
    self.waiting_next = false
    self:_setButtons(self.lesson_buttons)
    self:refresh()
    self:_paceOpponent()
end

-- When it is the opponent's turn: like Lichess, continue automatically unless
-- the position just shown has a comment to read; then wait for "Next".
function PkStudyView:_paceOpponent(prefix)
    if not self.lesson or self.lesson.state ~= "reply" then return end
    if self.cursor.node.comment then
        self.waiting_next = true
        self:refresh(prefix)
    else
        self:_scheduleReply()
    end
end

function PkStudyView:lessonNext()
    if not (self.lesson and self.waiting_next) then return end
    self.waiting_next = false
    self:_cancelReply()
    self.lesson:opponentReply()
    self:refresh()
    self:_paceOpponent()
end

--- Leaves the lesson and browses from the current position.
function PkStudyView:stopLesson()
    self:_cancelReply()
    self.lesson = nil
    self.waiting_next = false
    self:_setButtons(self.browse_buttons)
    self:refresh()
end

-- Lesson panel: never shows upcoming moves. Status first, then the comment of
-- the last move (or the chapter intro at the start).
function PkStudyView:_lessonRefresh(prefix)
    local lesson, node = self.lesson, self.cursor.node
    local parts = {}
    if prefix then parts[#parts + 1] = prefix end
    if node ~= self.cursor.root then parts[#parts + 1] = PkStudy.moveLabel(node) end
    if node.comment then parts[#parts + 1] = node.comment end
    if lesson.state == "end" then
        local summary
        if lesson.mistakes == 0 and not lesson.used_help then
            summary = _("Lesson complete — perfect!")
        else
            summary = T(_("Lesson complete. Mistakes: %1"), lesson.mistakes)
            if lesson.used_help then summary = summary .. " " .. _("(with hints or solutions)") end
        end
        parts[#parts + 1] = summary
        self.board.locked = true
    elseif lesson.state == "error" then
        parts[#parts + 1] = T(_("This study has an illegal move here (%1). Use Browse to read on."),
            tostring(lesson.error))
        self.board.locked = true
    elseif lesson.state == "play" then
        parts[#parts + 1] = T(_("Your move (%1)."), sideName(lesson.student))
    else
        self.board.locked = true -- opponent to move
        if self.waiting_next then parts[#parts + 1] = _("Tap Next to continue.") end
    end
    self:_setText(table.concat(parts, "\n\n"))
    local playing = lesson.state == "play"
    self.lesson_buttons:getButtonById("hint"):enableDisable(playing)
    self.lesson_buttons:getButtonById("solution"):enableDisable(playing)
    self.lesson_buttons:getButtonById("next"):enableDisable(self.waiting_next == true)
end

function PkStudyView:onLessonMove(from, to, promotion)
    if self.lesson.state ~= "play" then return self:refresh() end
    local verdict, node = self.lesson:onStudentMove(from, to, promotion)
    self:_afterLessonVerdict(verdict, node)
end

function PkStudyView:_afterLessonVerdict(verdict, node)
    if verdict == "good" then
        self:refresh(_("Correct!"))
        self:_paceOpponent(_("Correct!"))
    elseif verdict == "end" then
        self:refresh(_("Correct!"))
    elseif verdict == "bad" then
        self:refresh(_("That's a mistake.") .. (node.comment and ("\n" .. node.comment) or "")
            .. "\n" .. _("Try again."))
    elseif verdict == "sideline" then
        self:refresh(_("That move is a sideline in this study. Find the main move."))
    else
        self:refresh(_("Not the move. Try again."))
    end
end

function PkStudyView:_scheduleReply()
    self._reply_task = function()
        self._reply_task = nil
        if not self.lesson then return end
        self.lesson:opponentReply()
        self:refresh()
        self:_paceOpponent()
    end
    UIManager:scheduleIn(self.reply_delay, self._reply_task)
end

function PkStudyView:_cancelReply()
    if self._reply_task then
        UIManager:unschedule(self._reply_task)
        self._reply_task = nil
    end
end

function PkStudyView:lessonHint()
    if not self.lesson then return end
    local square = self.lesson:hint()
    if not square then return end
    self:refresh(T(_("Hint: move the piece on %1."), square))
    -- a ring, not the last-move tint, so it doesn't read as "the last move"
    local shapes = { circles = { { square = square } }, arrows = {} }
    for _, c in ipairs((self.cursor.node.shapes or {}).circles or {}) do table.insert(shapes.circles, c) end
    shapes.arrows = (self.cursor.node.shapes or {}).arrows or {}
    self.board:setShapes(shapes)
    UIManager:setDirty(self, "ui")
end

function PkStudyView:lessonSolution()
    if not self.lesson then return end
    local verdict, node = self.lesson:solution()
    if verdict then self:_afterLessonVerdict(verdict, node) end
end

function PkStudyView:onCloseWidget()
    self:_cancelReply()
    if self.board then self.board:free() end
    if self.text then self.text:free() end
end

return PkStudyView
