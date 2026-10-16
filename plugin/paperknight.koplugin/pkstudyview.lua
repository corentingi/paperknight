-- Study viewer (ADR-0011, docs/studies.md): board + comment panel + navigation.
-- Tree logic lives in pkstudy.lua; this file only displays and dispatches.
local ButtonDialog = require("ui/widget/buttondialog")
local ButtonTable = require("ui/widget/buttontable")
local Device = require("device")
local Geometry = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local Menu = require("ui/widget/menu")
local Notification = require("ui/widget/notification")
local Screen = Device.screen
local Size = require("ui/size")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local T = require("ffi/util").template

local Chess = require("pkchess")
local PkDone = require("pkdone")
local PkLesson = require("pklesson")
local PkOpeningNames = require("pkopeningnames")
local PkLinks = require("pklinks")
local PkProgress = require("pkprogress")
local PkButton = require("pkbutton")
local PkRefresh = require("pkrefresh")
local PkPgn = require("pkpgn")
local PkStudy = require("pkstudy")
local PkNav = require("pknav")
local PkSide = require("pkside")

local REPLY_DELAY = 0.8 -- seconds before the opponent's reply in a lesson

local PkStudyView = InputContainer:extend{
    name = "paperknight_study",
    covers_fullscreen = true,
    study = nil,         -- PkStudy
    chapter_index = 1,
    progress = nil,      -- PkProgress (flip settings); opened here if not given
    reply_delay = REPLY_DELAY,
}
-- board + text panel + buttons, the panel's text and refreshes (pkboardscreen.lua)
require("pkboardscreen").mixin(PkStudyView)

function PkStudyView:init()
    PkNav.tapTitle(self, function() return self.title_bar end, "studies") -- quick settings
    PkSide.followNight(self, function(v) if v.raw_text then v:_setText(PkSide.swap(v.raw_text)) end end)
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
        left_icon_tap_callback = function() self:showMenu() end,
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
    -- arrows: no tap highlight, which flashes on every step; the board
    -- changing is the feedback
    PkButton.noFeedback(self.browse_buttons, { "start", "back", "forward", "end" })
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
    if not self.progress then
        local ok, progress = pcall(PkProgress.open, PkProgress.defaultPath())
        if ok then
            self.progress, self._own_progress = progress, true
        else
            logger.warn("Paperknight: no progress database, flips are not remembered:", progress)
        end
    end
    -- the move list beside the board (☰ Hide/Show move list, remembered)
    self.list_shown = not (self.progress and self:_progressFlag(function(p)
        return p:getSetting("study.movelist") == "0"
    end))
    self:loadChapter(self.chapter_index)
end

-- Settings key of the current chapter's flip (studies opened from a file only).
function PkStudyView:_flipKey()
    local file = self.study.path and self.study.path:match("([^/]+)$")
    return file and ("study_flip:" .. file .. "#" .. self.chapter_index) or nil
end

function PkStudyView:isFlipped()
    -- a flip that could not be saved (no file path, no database) lives here
    if self._unsaved_flip ~= nil then return self._unsaved_flip end
    local key = self.progress and self:_flipKey()
    return key ~= nil and self.progress:getSetting(key) == "1"
end

--- Side shown at the bottom ("white"/"black"): the chapter's orientation,
-- reversed if the user flipped this chapter. It is also the side trained.
function PkStudyView:orientation()
    local o = self.chapter.orientation
    if self:isFlipped() then o = (o == "black") and "white" or "black" end
    return o
end

--- Flips the board of this chapter and remembers it. A running lesson
-- restarts from the new side.
function PkStudyView:toggleFlip()
    local key = self.progress and self:_flipKey()
    local saved = false
    if key then
        local ok, err = pcall(self.progress.setSetting, self.progress, key, (not self:isFlipped()) and "1" or nil)
        if ok then saved, self._unsaved_flip = true, nil else logger.warn("Paperknight: cannot save the flip:", err) end
    end
    if not saved then
        self._unsaved_flip = not self:isFlipped()
    end
    self:_build()
    if not self.cursor then -- chapter that cannot be opened: stays locked
        self:_showOpenError()
    elseif self.lesson then
        self:startLesson()
    else
        self:refresh(nil, true)
    end
    PkRefresh.page(self)
end

function PkStudyView:_build()
    self:_buildScreen(self:orientation() == "black")
end

--- Shows or hides the move list beside the board (remembered).
function PkStudyView:toggleList()
    self.list_shown = not self.list_shown
    if self.progress then
        pcall(self.progress.setSetting, self.progress, "study.movelist", (not self.list_shown) and "0" or nil)
    end
    self:_build()
    if not self.cursor then
        self:_showOpenError()
    elseif self.lesson then
        self:_lessonRefresh()
        self:_updateList()
    else
        self:refresh(nil, true)
    end
    PkRefresh.page(self)
end

-- The move list: the moves from the chapter start to the current one,
-- then the line that follows (first moves) to its end; during a lesson,
-- only the moves played (the list must not give the answer away).
function PkStudyView:_updateList()
    if not (self.movelist and self.cursor) then return end
    local nodes = {}
    local n = self.cursor.node
    while n.parent do table.insert(nodes, 1, n); n = n.parent end
    local current = #nodes
    if not self.lesson then
        n = self.cursor.node
        while n.children[1] and self.cursor:resolve(n.children[1]) do
            n = n.children[1]
            nodes[#nodes + 1] = n
        end
    end
    local sans = {}
    for i, node in ipairs(nodes) do sans[i] = node.move and node.move.san or node.san end
    self.list_nodes = nodes
    local ply = self.cursor.root.ply or 0
    self:_setListMoves(sans, current, math.floor(ply / 2) + 1, ply % 2 == 1)
end

--- A move tapped in the list: its position (browsing only).
function PkStudyView:onListSelect(i)
    local node = self.list_nodes and self.list_nodes[i]
    if not node or not self:_canBrowse() or node == self.cursor.node then return end
    if self.cursor:jump(node) then self:refresh() end
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

-- A chapter that cannot be opened: empty locked board and the error (again
-- after a rebuild, e.g. Flip board).
function PkStudyView:_showOpenError()
    self.board:updateBoard()
    self.board:setHighlights({})
    self.board:setShapes(nil)
    self.board:setBadge(nil)
    self.board.locked = true
    self:_setText(T(_("Cannot open this chapter: %1"), self._open_error or "?"))
end

--- Opens chapter `index` at its start position.
function PkStudyView:loadChapter(index)
    self:_cancelReply()
    self.lesson = nil
    self._unsaved_flip = nil
    self.chapter_index = index
    -- remembered for "Continue" in the chapter list
    local file = PkDone.fileOf(self.study.path)
    if file and self.progress then pcall(PkDone.setLastChapter, self.progress, file, index) end
    self.chapter = self.study.chapters[index]
    self.study:releaseTrees(index) -- only the open chapter's tree stays in memory
    local cursor, err = self.study:cursor(index, self.game)
    if not cursor then
        logger.warn("Paperknight: cannot open chapter", index, err)
        self.cursor = nil
        self._open_error = tostring(err)
        self.game.reset()
        self:_build()
        self:_showOpenError()
        self:_setButtons(self.browse_buttons)
        for _, id in ipairs({ "start", "back", "lines", "forward", "end", "train" }) do
            self.buttons:getButtonById(id):enableDisable(false)
        end
        self.title_bar:setTitle(util.fixUtf8(self.chapter.title, "?"))
        PkRefresh.page(self)
        return
    end
    self._open_error = nil
    -- nothing to train in a chapter without moves
    self.browse_buttons:getButtonById("train"):enableDisable(#cursor.root.children > 0)
    self.cursor = cursor
    self:_build()
    self.title_bar:setTitle(util.fixUtf8(self.chapter.title, "?"))
    if self.chapter.gamebook then
        self:startLesson()
    else
        self:_setButtons(self.browse_buttons)
        self:refresh()
    end
    PkRefresh.page(self)
end

-- Text panel: current move (or intro), comment, then what comes next.
function PkStudyView:_panelText()
    local node = self.cursor.node
    local parts = {}
    if node == self.cursor.root then
        parts[#parts + 1] = self.chapter.gamebook and _("Interactive lesson") or _("Start of the chapter")
    else
        parts[#parts + 1] = PkStudy.moveLabel(node, "move")
        parts[#parts + 1] = PkPgn.positionWords(node.glyphs)
    end
    parts[#parts + 1] = PkOpeningNames.forNode(node) -- "C50 Italian Game", if known
    local children = node.children
    if #children == 0 then
        local text = (node == self.cursor.root) and _("(no moves)") or _("— End of line —")
        local next_chapter = self.study.chapters[self.chapter_index + 1]
        if next_chapter then
            text = text .. "\n" .. T(_("› Next chapter: %1"), next_chapter.title)
        end
        parts[#parts + 1] = text
    elseif #children > 1 then
        local alts = {}
        for i, child in ipairs(children) do
            local label = self.cursor:resolve(child) and PkStudy.moveLabel(child) or child.san
            alts[#alts + 1] = (i == 1) and (label .. " " .. _("(main)")) or label
        end
        parts[#parts + 1] = T(_("Next: %1"), table.concat(alts, " · "))
    end
    -- the comment last: long comments scroll without hiding the lines above
    if node.comment then parts[#parts + 1] = node.comment end
    return table.concat(parts, "\n\n")
end

--- Redraws board, highlights, shapes, panel and subtitle for the current node.
-- `prefix`: optional message shown above the panel text; `full`: force a
-- full e-ink refresh (jumps).
function PkStudyView:refresh(prefix, full)
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
    -- when training an ordinary chapter, annotators' arrows often point at the
    -- move to find: hide shapes while it's the student's turn
    local hide_shapes = self.lesson and not self.lesson.variations_are_mistakes and self.lesson.state == "play"
    self.board:setShapes(not hide_shapes and node.shapes or nil)
    self.board:setBadge(node.move and node.move.to, PkStudy.moveMark(node))
    self.board.locked = false
    PkRefresh.setSubTitle(self, T(_("%1 · Chapter %2/%3"), self.study.name, self.chapter_index, #self.study.chapters))
    if self.lesson then
        self:_lessonRefresh(prefix)
    else
        self:_setText(prefix and (prefix .. "\n\n" .. self:_panelText()) or self:_panelText())
        self:_updateBrowseButtons()
    end
    self:_updateList()
    self:_redraw(full)
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
--- One move forward; at the end of a line, the next chapter.
function PkStudyView:forward(i)
    if not self:_canBrowse() then return end
    if #self.cursor.node.children == 0 then return self:nextChapter() end
    self:_show(self.cursor:forward(i))
end

--- From the end of a line: marks this chapter done (if it has moves and
-- isn't yet), then opens the next one.
function PkStudyView:nextChapter()
    if self.chapter_index >= #self.study.chapters then return end
    local file = PkDone.fileOf(self.study.path)
    if file and self.progress and #self.cursor.root.children > 0 then
        local ok, done = pcall(PkDone.isChapterDone, self.progress, file, self.chapter_index)
        if ok and not done then self:setChapterDone(true) end
    end
    self:loadChapter(self.chapter_index + 1)
end

-- Greys out what can't act here: |‹ ‹ at the start, ›| at the end of the
-- line, › at the end of the last chapter, Lines without alternatives.
function PkStudyView:_updateBrowseButtons()
    local node = self.cursor.node
    local at_start, at_end = node == self.cursor.root, #node.children == 0
    local b = self.browse_buttons
    b:getButtonById("start"):enableDisable(not at_start)
    b:getButtonById("back"):enableDisable(not at_start)
    b:getButtonById("end"):enableDisable(not at_end)
    b:getButtonById("forward"):enableDisable(not at_end or self.chapter_index < #self.study.chapters)
    b:getButtonById("lines"):enableDisable(#node.children > 1)
end
function PkStudyView:back() if self:_canBrowse() and self.cursor:back() then self:refresh() end end
function PkStudyView:toStart() if self:_canBrowse() then self.cursor:toStart(); self:refresh(nil, true) end end
function PkStudyView:toEnd() if self:_canBrowse() then self.cursor:toEnd(); self:refresh(nil, true) end end
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
    self:_takeBackMove() -- the cursor decides what the position is
    if not self.cursor then return end
    if self.lesson then return self:onLessonMove(move.from, move.to, promotion) end
    local child, i = self.cursor:childForMove(move.from, move.to, promotion)
    if child then
        self:forward(i)
    else
        self:refresh(_("This move is not in the study."))
    end
end

--- Title-bar menu: chapters, flip board, done mark.
function PkStudyView:showMenu()
    local dialog
    local function close() UIManager:close(dialog); self.menu_dialog = nil end
    local buttons = {
        {{ text = _("Chapters…"), callback = function() close(); self:showChapterMenu() end }},
        {
            { text = _("Flip board"), callback = function() close(); self:toggleFlip() end },
            { text = self.list_shown and _("Hide move list") or _("Show move list"),
              callback = function() close(); self:toggleList() end },
        },
        {
            -- the position shown, on the analysis board (closing it comes back here)
            { text = _("Analyse position"), callback = function()
                close()
                require("pkanalysis").show{ fen = self.game.fen(), flipped = self.board and self.board.flipped }
            end },
        },
    }
    buttons[#buttons + 1] = PkLinks.menuRow(self.links, close)
    local file = PkDone.fileOf(self.study.path)
    if file and self.progress then
        local ch_done = self:_progressFlag(PkDone.isChapterDone, file, self.chapter_index)
        buttons[#buttons + 1] = {{
            text = ch_done and _("Mark chapter as not done") or _("Mark chapter as done ✓"),
            callback = function()
                close()
                self:setChapterDone(not ch_done)
            end,
        }}
        local done = self:_progressFlag(PkDone.isDone, file)
        buttons[#buttons + 1] = {{
            text = done and _("Mark study as not done") or _("Mark study as done ✓"),
            callback = function()
                close()
                local ok, err = pcall(PkDone.set, self.progress, file, not done)
                if not ok then
                    logger.warn("Paperknight: cannot save the done mark:", err)
                    return
                end
                UIManager:show(Notification:new{
                    text = (not done) and _("Study marked as done.") or _("Study marked as not done."),
                })
            end,
        }}
    end
    buttons[#buttons + 1] = PkNav.moreRow(close, "studies")
    dialog = ButtonDialog:new{ buttons = buttons }
    self.menu_dialog = dialog
    UIManager:show(dialog)
end

--- Marks the current chapter done (or not) and says so; marking the last
-- remaining chapter marks the whole study done too.
-- A done mark read from the progress file; false if it cannot be read (a
-- locked or damaged file must not break the menu or the panel).
function PkStudyView:_progressFlag(read, ...)
    local ok, value = pcall(read, self.progress, ...)
    if not ok then logger.warn("Paperknight: cannot read the done marks:", value) end
    return ok and value or false
end

function PkStudyView:setChapterDone(done)
    local file = PkDone.fileOf(self.study.path)
    if not (file and self.progress) then return end
    -- chapters without moves (intros) can't be finished: they don't count
    -- (found without parsing every chapter, PkStudy:countedChapters)
    local counted = self.study:countedChapters()
    local ok, study_done = pcall(PkDone.setChapterDone, self.progress, file, self.chapter_index, done, counted)
    if not ok then
        logger.warn("Paperknight: cannot save the chapter mark:", study_done)
        return
    end
    local text = done and _("Chapter marked as done.") or _("Chapter marked as not done.")
    if study_done then text = _("All chapters done: study marked as done ✓") end
    UIManager:show(Notification:new{ text = text })
end

function PkStudyView:showChapterMenu()
    local items = {}
    local done = {}
    pcall(function() done = PkDone.chapterDoneSet(self.progress, PkDone.fileOf(self.study.path)) end)
    for i, ch in ipairs(self.study.chapters) do
        local text = T("%1. %2", i, util.fixUtf8(ch.title, "?"))
        if i == self.chapter_index then text = "• " .. text end -- the chapter shown
        items[#items + 1] = {
            text = text,
            mandatory = PkDone.chapterInfo(ch.gamebook, done[i]),
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

--- Starts (or restarts) a lesson on the current chapter. Gamebook chapters
-- treat variations as known mistakes; ordinary chapters as sidelines.
function PkStudyView:startLesson()
    if not self.cursor then return end
    self:_cancelReply()
    local student = (self:orientation() == "black") and "b" or "w"
    self.lesson = PkLesson.new(self.cursor, student, { variations_are_mistakes = self.chapter.gamebook == true })
    self.lesson:start()
    self.waiting_next = false
    self:_setButtons(self.lesson_buttons)
    self:refresh(nil, true)
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
    if self.lesson and self.lesson.state == "end" and self.chapter_index < #self.study.chapters then
        return self:loadChapter(self.chapter_index + 1) -- lesson finished: next chapter
    end
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
    -- status first (a long comment scrolls below it)
    local status = {}
    if prefix then status[#status + 1] = prefix end
    local has_next_chapter = self.chapter_index < #self.study.chapters
    local parts = status
    if lesson.state == "end" then
        -- a finished lesson marks its chapter done (once per lesson; a
        -- chapter without moves is not "finished" by opening it)
        if not lesson._marked_done and self.cursor.node ~= self.cursor.root then
            lesson._marked_done = true
            local file = PkDone.fileOf(self.study.path)
            if file and self.progress and not self:_progressFlag(PkDone.isChapterDone, file, self.chapter_index) then
                self:setChapterDone(true)
            end
        end
        local summary
        if lesson.mistakes == 0 and not lesson.used_help then
            summary = _("Lesson complete — perfect!")
        else
            summary = T(_("Lesson complete. Mistakes: %1"), lesson.mistakes)
            if lesson.used_help then summary = summary .. " " .. _("(with hints or solutions)") end
        end
        parts[#parts + 1] = summary
        if has_next_chapter then parts[#parts + 1] = _("Tap Next for the next chapter.") end
        self.board.locked = true
    elseif lesson.state == "error" then
        parts[#parts + 1] = T(_("This study has an illegal move here (%1). Use Browse to read on."),
            tostring(lesson.error))
        self.board.locked = true
    elseif lesson.state == "play" then
        parts[#parts + 1] = T(_("Your move (%1)."), PkSide.name(lesson.student))
    else
        self.board.locked = true -- opponent to move
        if self.waiting_next then parts[#parts + 1] = _("Tap Next to continue.") end
    end
    if node ~= self.cursor.root then
        parts[#parts + 1] = PkStudy.moveLabel(node, "move")
        parts[#parts + 1] = PkPgn.positionWords(node.glyphs)
    end
    parts[#parts + 1] = PkOpeningNames.forNode(node) -- "C50 Italian Game", if known
    if node.comment then parts[#parts + 1] = node.comment end
    self:_setText(table.concat(parts, "\n\n"))
    local playing = lesson.state == "play"
    self.lesson_buttons:getButtonById("hint"):enableDisable(playing)
    self.lesson_buttons:getButtonById("solution"):enableDisable(playing)
    self.lesson_buttons:getButtonById("next"):enableDisable(self.waiting_next == true
        or (lesson.state == "end" and has_next_chapter))
end

function PkStudyView:onLessonMove(from, to, promotion)
    if self.lesson.state ~= "play" then return self:refresh() end
    local verdict, node = self.lesson:onStudentMove(from, to, promotion)
    self:_afterLessonVerdict(verdict, node)
end

function PkStudyView:_afterLessonVerdict(verdict, node)
    if verdict == "good" then
        -- a commented position waits for Next: decided first, so that the
        -- panel is built and refreshed once
        local wait = self.lesson.state == "reply" and self.cursor.node.comment ~= nil
        if wait then self.waiting_next = true end
        self:refresh(_("Correct!"))
        if not wait then self:_paceOpponent(_("Correct!")) end
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

function PkStudyView:lessonHint()
    if not self.lesson then return end
    local square = self.lesson:hint()
    if not square then return end
    self:refresh(T(_("Hint: move the piece on %1."), square))
    -- a ring, not the last-move tint, so it doesn't read as "the last move"
    local current = self.board.shapes or {}
    local shapes = { circles = { { square = square } }, arrows = current.arrows or {} }
    for _, c in ipairs(current.circles or {}) do table.insert(shapes.circles, c) end
    self.board:setShapes(shapes)
    UIManager:setDirty(self, "ui", self.board.dimen)
end

function PkStudyView:lessonSolution()
    if not self.lesson then return end
    local verdict, node = self.lesson:solution()
    if verdict then self:_afterLessonVerdict(verdict, node) end
end

function PkStudyView:onCloseWidget()
    self:_cancelReply()
    if self._own_progress and self.progress then
        self.progress:close()
        self.progress = nil
    end
    if self.board then self.board:free() end
    if self.text then self.text:free() end
end

return PkStudyView
