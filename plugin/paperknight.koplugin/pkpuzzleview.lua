-- Puzzle screen (ADR-0009): board + status + two button bars:
--  * solving: Retry / Hint / Solution / Next;
--  * finished (solved, or Solution tapped): Retry / ‹ / › / Next, to step
--    through the line (also by swiping, or with page-turn keys).
-- Judging lives in pkpuzzle.lua, storage in pkpuzzlepack.lua / pkprogress.lua.
local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local ButtonTable = require("ui/widget/buttontable")
local ButtonDialog = require("ui/widget/buttondialog")
local CenterContainer = require("ui/widget/container/centercontainer")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geometry = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local Screen = require("device").screen
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template

local Chess = require("pkchess")
local ChessBoard = require("pkboard")
local PkPromotion = require("pkpromotion")
local PkRefresh = require("pkrefresh")
local PkNav = require("pknav")
local PkSide = require("pkside")
local PkPuzzle = require("pkpuzzle")
local PkPuzzleReview = require("pkpuzzlereview")
local PkSrs = require("pksrs")
local PkThemes = require("pkthemes")
local PkPuzzleStats = require("pkpuzzlestats")
local PkStatsView = require("pkstatsview")
local Menu = require("ui/widget/menu")

local REPLY_DELAY = 0.6 -- seconds before the opponent replies, so the user sees their move first
local RECENT_DAYS = 30  -- don't repeat puzzles attempted this recently (ADR-0010)
local SEED_DAYS = 60    -- past misses turned into reviews, once (ADR-0014)

local PkPuzzleView = InputContainer:extend{
    name = "paperknight_puzzles",
    covers_fullscreen = true,
    pack = nil,      -- PkPuzzlePack (owned: closed with the view)
    progress = nil,  -- PkProgress (owned: closed with the view)
    random = nil,    -- optional function() -> [0,1), for tests
    reply_delay = REPLY_DELAY,
}

function PkPuzzleView:init()
    PkNav.tapTitle(self, function() return self.title_bar end, "puzzles") -- quick settings
    PkSide.followNight(self, function(v) v.status:setText(PkSide.swap(v.status.text)) end)
    self.dimen = Geometry:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    if Device:hasKeys() then
        self.key_events = {
            Close = { { Device.input.group.Back } },
            Forward = { { Device.input.group.PgFwd } },
            Backward = { { Device.input.group.PgBack } },
        }
    end
    self.ges_events.PkSwipe = { GestureRange:new{ ges = "swipe", range = function() return self.dimen end } }
    self.game = Chess:new()
    self.title_bar = TitleBar:new{
        fullscreen = true,
        title = _("Puzzles"),
        subtitle = "",
        with_bottom_line = true,
        left_icon = "appbar.menu",
        left_icon_tap_callback = function() self:showMenu() end,
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
        height = Screen:scaleBySize(105), -- 4 lines: result, themes, rating, review note
        alignment = "center",
    }
    self.solve_buttons = ButtonTable:new{
        width = self.dimen.w - 2 * Size.padding.default,
        buttons = {{
            { id = "retry", text = _("Retry"), callback = function() self:onRetry() end },
            { id = "hint", text = _("Hint"), callback = function() self:onHint() end },
            { id = "solution", text = _("Solution"), callback = function() self:onSolution() end },
            { id = "next", text = _("Next"), callback = function() self:nextPuzzle() end },
        }},
        zero_sep = true,
    }
    local function replayButtons(icon_size)
        return ButtonTable:new{
            width = self.dimen.w - 2 * Size.padding.default,
            buttons = {{
                { id = "retry", text = _("Retry"), callback = function() self:onRetry() end },
                { id = "back", icon = "chevron.left", icon_width = icon_size, icon_height = icon_size,
                  callback = function() self:step(-1) end },
                { id = "forward", icon = "chevron.right", icon_width = icon_size, icon_height = icon_size,
                  callback = function() self:step(1) end },
                { id = "next", text = _("Next"), callback = function() self:nextPuzzle() end },
            }},
            zero_sep = true,
        }
    end
    self.replay_buttons = replayButtons()
    -- icons are taller than text: shrink them so the board doesn't move
    local extra = self.replay_buttons:getSize().h - self.solve_buttons:getSize().h
    if extra > 0 then
        local size = self.replay_buttons:getButtonById("back").icon_width - extra
        self.replay_buttons:free()
        self.replay_buttons = replayButtons(size)
    end
    self.buttons = self.solve_buttons
    local board_h = self.dimen.h - self.title_bar:getHeight() - self.status:getSize().h
        - math.max(self.solve_buttons:getSize().h, self.replay_buttons:getSize().h) - 4 * Size.padding.default
    self.board_size = math.min(self.dimen.w, board_h)
    self:_prepareBoard(false) -- the frame exists even if no puzzle can be picked
    self._skipped = {} -- reviews already shown this session
    self._served = {}  -- puzzles already shown this session (no repeat until all were)
    local ok, err = pcall(self.progress.seedReviews, self.progress, os.time(), SEED_DAYS)
    if not ok then logger.warn("Paperknight: cannot seed puzzle reviews:", err) end
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
        square_refresh = "partial", -- a move refreshes its squares only (pkrefresh.lua)
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
    self.vgroup = self[1][1]
end

-- Swaps the button bar (solving <-> replay).
function PkPuzzleView:_setButtons(tbl)
    if self.buttons == tbl then return end
    for i, w in ipairs(self.vgroup) do
        if w == self.buttons then self.vgroup[i] = tbl end
    end
    self.buttons = tbl
    self.vgroup:resetLayout()
end

function PkPuzzleView:_updateTitle()
    local ok, rating = pcall(self.progress.rating, self.progress)
    if not ok then rating = "?" end
    local subtitle = T(_("Your rating: %1"), rating)
    local c_ok, due = pcall(self.progress.reviewDueCount, self.progress, PkSrs.today())
    if c_ok and due > 0 then subtitle = subtitle .. " · " .. T(_("Reviews: %1"), due) end
    if self.puzzle then
        subtitle = subtitle .. " · " .. T(_("Puzzle %1"), self.puzzle.rating)
    end
    if self.theme then -- last: a long theme name may be cut off
        subtitle = subtitle .. " · " .. PkThemes.label(self.theme)
    end
    self.title_bar:setSubTitle(subtitle)
end

-- The board refreshes the squares it changes; this refreshes the status and
-- the buttons only, so that a move never refreshes (or flashes) the whole
-- board. A new puzzle refreshes the page (loadPuzzle).
function PkPuzzleView:_setStatus(text)
    self.status:setText(text)
    PkRefresh.step(self, self.status, self.buttons)
end

function PkPuzzleView:_toMoveText()
    local text = T(_("%1 to move. Find the best move."), PkSide.name(self.session:solverColor()))
    if self.review then
        text = T(_("Review: you missed this puzzle on %1."), os.date("%d %b %Y", self.review.missed)) .. "\n" .. text
    elseif self.stale then
        text = (self.theme and _("You played every puzzle of this theme recently: repeating.")
            or _("You played every puzzle near your rating recently: repeating.")) .. "\n" .. text
    end
    return text
end

--- Starts `puzzle` (a pack row); `review`: its review card when it is a
-- review of a missed puzzle (ADR-0014); `stale`: played recently (repeat).
function PkPuzzleView:loadPuzzle(puzzle, review, stale)
    self:_cancelReply()
    self:_finishAttempt("skipped")
    self.puzzle = puzzle
    self.review = review
    self.stale = stale
    self.session = PkPuzzle.new(puzzle, self.game)
    self.recorded = false
    self.replaying = false
    self:_prepareBoard(puzzle.solver == Chess.BLACK)
    self:_setButtons(self.solve_buttons)
    local setup = self.session:start()
    self.board:updateBoard()
    self.board:setHighlights({ setup.from, setup.to })
    self.board:setBadge(nil)
    self.board.locked = false
    self:_updateTitle()
    self:_setStatus(self:_toMoveText())
    logger.info("Paperknight: puzzle", puzzle.id, "rating", puzzle.rating)
    PkRefresh.page(self) -- new position (KOReader's full refresh rate applies)
end

function PkPuzzleView:_packHasTheme(theme)
    for _, t in ipairs(self.pack:themes()) do
        if t.theme == theme and t.count > 0 then return true end
    end
    return false
end

local MAX_LOAD_TRIES = 5

-- First due review not shown yet this session (and of the chosen theme),
-- with its pack row. Reviews of puzzles gone from the pack are dropped.
function PkPuzzleView:_nextReview()
    for _, card in ipairs(self.progress:dueReviews(PkSrs.today())) do
        local id = card.puzzle_id
        if not self._skipped[id] and not self._bad[id] then
            local puzzle = self.pack:get(id)
            if not puzzle then
                self.progress:removeReview(id) -- the pack was replaced
            elseif not self.theme or (" " .. (puzzle.themes or "") .. " "):find(" " .. self.theme .. " ", 1, true) then
                return card, puzzle
            end
        end
    end
    return nil
end

--- Picks and loads the next puzzle. Returns true on success. A puzzle that
-- cannot be set up (bad pack data) is skipped for the session.
function PkPuzzleView:nextPuzzle()
    local since = os.time() - RECENT_DAYS * 86400
    self._bad = self._bad or {}
    if self.review and self.puzzle then self._skipped[self.puzzle.id] = true end
    local r_ok, review, r_puzzle = pcall(self._nextReview, self)
    if not r_ok then
        logger.warn("Paperknight: cannot read puzzle reviews:", review)
    elseif review then
        local l_ok, l_err = pcall(self.loadPuzzle, self, r_puzzle, review)
        if l_ok then return true end
        logger.warn("Paperknight: skipping review", review.puzzle_id, l_err)
        self._bad[review.puzzle_id] = true
        self.session, self.puzzle, self.review = nil, nil, nil
    end
    local err
    local function pick()
        return self.pack:pickNear(self.progress:rating(), {
            random = self.random,
            theme = self.theme,
            accept = function(p)
                return not (self.puzzle and p.id == self.puzzle.id)
                    and not self._served[p.id]
                    and not self._bad[p.id]
                    and not self.progress:getReview(p.id) -- comes back as a review
            end,
            fresh = function(p) return not self.progress:wasAttemptedSince(p.id, since) end,
        })
    end
    for _try = 1, MAX_LOAD_TRIES do
        local ok, puzzle, fresh = pcall(pick)
        if ok and not puzzle and next(self._served) then
            -- every puzzle was shown this session: start a new round
            self._served = {}
            ok, puzzle, fresh = pcall(pick)
        end
        if not ok then
            err = puzzle
            break -- the database itself: retrying will not help
        end
        if not puzzle then
            self:_updateTitle()
            if self.puzzle then
                self:_setStatus(self.theme and _("No other puzzle with this theme in the pack.")
                    or _("No other puzzle in the pack."))
            else
                self:_setStatus(self.theme and _("No puzzles with this theme in the pack.")
                    or _("No puzzles found in the pack."))
            end
            return false
        end
        self._served[puzzle.id] = true
        local l_ok, l_err = pcall(self.loadPuzzle, self, puzzle, nil, not fresh)
        if l_ok then return true end
        err = l_err
        logger.warn("Paperknight: skipping puzzle", puzzle.id, l_err)
        self._bad[puzzle.id] = true
        self.session, self.puzzle = nil, nil
    end
    logger.warn("Paperknight: cannot load a puzzle:", err)
    if self.board then self.board.locked = true end
    self:_updateTitle()
    self:_setStatus(_("Cannot load a puzzle from the pack.") .. "\n" .. tostring(err))
    return false
end

-- A puzzle whose line contains an impossible move: stop it cleanly.
function PkPuzzleView:_broken(err)
    logger.warn("Paperknight: broken puzzle", self.puzzle and self.puzzle.id, err)
    if self.puzzle then self._bad = self._bad or {}; self._bad[self.puzzle.id] = true end
    self.session = nil
    self.replaying = false
    self:_setButtons(self.solve_buttons)
    self.board:setBadge(nil)
    self.board.locked = true
    self.board:updateBoard()
    self:_setStatus(_("This puzzle contains an invalid move. Tap Next."))
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
    if self.review then return nil, nil, self:_gradeReview(s:isCleanSolve()) end
    local ok, before, after = pcall(self.progress.record, self.progress, {
        puzzle_id = self.puzzle.id,
        puzzle_rating = self.puzzle.rating,
        success = s:isCleanSolve(),
        solved = s.state == "solved",
        mistakes = s.mistakes,
        used_help = s.used_help,
    })
    if not ok then
        logger.warn("Paperknight: cannot save the attempt:", before)
        return nil
    end
    logger.info("Paperknight: attempt", self.puzzle.id, reason, before, "->", after)
    local note
    if not s:isCleanSolve() then -- missed: it will come back (ADR-0014)
        local r_ok, err = pcall(function()
            if not self.progress:getReview(self.puzzle.id) then
                self.progress:saveReview(self.puzzle.id, PkPuzzleReview.missed(nil))
            end
        end)
        if r_ok then note = _("It will come back tomorrow for a review.")
        else logger.warn("Paperknight: cannot save the review:", err) end
    end
    return before, after, note
end

-- Grades the review shown (no rating change: ADR-0010, ADR-0014). Returns
-- a line for the status.
function PkPuzzleView:_gradeReview(clean)
    local id, note = self.puzzle.id, nil
    local ok, err = pcall(function()
        if clean then
            local card, days = PkPuzzleReview.solved(self.review)
            if card then
                self.progress:saveReview(id, card)
                note = T(_("Next review in %1 days."), days)
            else
                self.progress:removeReview(id)
                note = _("Mastered: this puzzle will not come back.")
            end
        else
            self.progress:saveReview(id, PkPuzzleReview.missed(self.review))
            note = _("It will come back tomorrow.")
        end
    end)
    if not ok then logger.warn("Paperknight: cannot save the review:", err) end
    logger.info("Paperknight: review", id, clean and "clean" or "missed")
    return note
end

function PkPuzzleView:onUserMove(move)
    if not self.session then return end
    local ok, verdict, reply = pcall(self.session.onUserMove, self.session, move)
    if not ok then return self:_broken(verdict) end
    if verdict == "wrong" then
        self.board:updateBoard() -- the move was taken back
        self:_setStatus(_("Not the move. Try again."))
        return
    end
    self.board:setHighlights({ move.from, move.to })
    if verdict == "solved" then
        self.board.locked = true
        local before, after, note = self:_finishAttempt("solved")
        local result = (self.session:isCleanSolve() and _("Solved!"))
            or (self.session.used_help and _("Solved, with help."))
            or _("Solved, after a mistake.")
        result = self:_withThemes(result)
        local text = result
        if before then
            text = text .. "\n" .. T(_("Rating %1 → %2"), before, after)
        end
        if note then text = text .. "\n" .. note end
        self:_updateTitle()
        self:_startReplay(result)
        self:_updateBadge(move)
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
--- ☰ menu: the theme, then the quick settings (pknav.lua).
function PkPuzzleView:showMenu()
    local dialog
    local function close() UIManager:close(dialog); self.menu_dialog = nil end
    local buttons = {
        {
            { text = _("Theme…"), callback = function() close(); self:showThemeMenu() end },
            { text = _("Stats…"), callback = function() close(); self:showStats() end },
        },
    }
    for _, row in ipairs(PkNav.quickRows(close, "puzzles")) do buttons[#buttons + 1] = row end
    dialog = ButtonDialog:new{ buttons = buttons }
    self.menu_dialog = dialog
    UIManager:show(dialog)
end

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

--- Stats page (pkstatsview.lua): per theme, clean solves vs missed attempts
-- and the performance, weakest first. Tapping a theme trains it.
function PkPuzzleView:showStats()
    local cache = {}
    local function themesOf(id)
        if cache[id] == nil then
            local p = self.pack:get(id)
            cache[id] = p and p.themes or false
        end
        return cache[id] or nil
    end
    local ok, stats = pcall(function() return PkPuzzleStats.compute(self.progress:attempts(), themesOf) end)
    if not ok then
        logger.warn("Paperknight: cannot compute the stats:", stats)
        stats = { total = { n = 0 }, themes = {} }
    end
    self.stats_view = PkStatsView:new{
        stats = stats,
        rating = self.progress:rating(),
        on_pick = function(theme) self:setTheme(theme) end,
    }
    self.stats_view.onCloseWidget = function() self.stats_view = nil end
    UIManager:show(self.stats_view)
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

--- Plays the first move not found, then switches to the replay: › shows
-- the rest of the line, ‹ goes back to the start.
function PkPuzzleView:onSolution()
    if not self.session or self.session:isOver() then return end
    self:_cancelReply() -- the reply is already in the game; the redraw below shows it
    local ok, err = pcall(self.session.revealSolution, self.session)
    if not ok then return self:_broken(err) end
    self.board:clearSelection()
    local before, after, note = self:_finishAttempt("solution")
    if not self:_startReplay(self:_withThemes(_("Solution shown."))) then return end
    local s = self.session
    local r_ok, move, label = pcall(s.replayTo, s, s.pos)
    if not r_ok then return self:_broken(move) end
    self.board:updateBoard()
    self.board:setHighlights({ move.from, move.to })
    local text = self:_withThemes(T(_("Solution: %1 (move %2/%3)."), label, s.pos - 1, #s.line - 1))
    if before then text = text .. "\n" .. T(_("Rating %1 → %2"), before, after) end
    if note then text = text .. "\n" .. note end
    self:_updateTitle()
    self:_setStatus(text)
end

-- A finished puzzle's themes, on the line after `text`, when playing all
-- themes (a chosen theme is in the subtitle already).
function PkPuzzleView:_withThemes(text)
    if self.theme or not self.puzzle then return text end
    local labels = PkThemes.shown(self.puzzle.themes)
    -- one line, so that the lines below stay in the status box: drop the last
    -- themes until it fits
    local line
    for n = #labels, 1, -1 do
        line = T(_("Themes: %1"), table.concat(labels, ", ", 1, n) .. (n < #labels and ", …" or ""))
        local w = TextWidget:new{ text = line, face = self.status.face }
        local fits = w:getSize().w <= self.status.width
        w:free()
        if fits then break end
    end
    return line and (text .. "\n" .. line) or text
end

---------------------------------------------------------------------------
-- Replay of the finished puzzle

-- Switches to the replay bar at the current position; `result`: first line
-- of the status while stepping. Returns false if the puzzle is broken.
function PkPuzzleView:_startReplay(result)
    self.board.locked = true
    local ok, err = pcall(self.session.startReplay, self.session)
    if not ok then self:_broken(err); return false end
    self.replaying = true
    self.result_text = result
    self:_setButtons(self.replay_buttons)
    self:_updateReplayButtons()
    return true
end

function PkPuzzleView:_updateReplayButtons()
    local s = self.session
    self.replay_buttons:getButtonById("back"):enableDisable(s.pos > 0)
    self.replay_buttons:getButtonById("forward"):enableDisable(s.pos < #s.line)
end

-- "Move 2/3: 25. Qd8+" (the setup move is the puzzle position, not counted).
function PkPuzzleView:_replayText(label)
    local s = self.session
    if s.pos == 0 then
        local opponent = s:solverColor() == Chess.WHITE and Chess.BLACK or Chess.WHITE
        return T(_("Before the puzzle: %1 to move."), PkSide.name(opponent))
    elseif s.pos == 1 then
        return T(_("Puzzle position, after %1."), label)
    end
    return T(_("Move %1/%2: %3"), s.pos - 1, #s.line - 1, label)
end

-- Solved puzzle at its final position: a tick badge on the last moved piece
-- (`move`, the move shown); removed anywhere else.
function PkPuzzleView:_updateBadge(move)
    local s = self.session
    local done = move and s.state == "solved" and s.pos == #s.line
    self.board:setBadge(done and move.to or nil, ChessBoard.TICK)
end

--- Steps the replay by `delta` moves (‹ ›, swipes, page-turn keys).
function PkPuzzleView:step(delta)
    if not self.replaying or not self.session then return end
    local s = self.session
    local pos = s.pos + delta
    if pos < 0 or pos > #s.line then return end
    local ok, move, label = pcall(s.replayTo, s, pos)
    if not ok then return self:_broken(move) end
    self.board:updateBoard()
    self.board:setHighlights(move and { move.from, move.to } or {})
    self:_updateBadge(move)
    self:_updateReplayButtons()
    self:_setStatus(self.result_text .. "\n" .. self:_replayText(label))
end

function PkPuzzleView:onPkSwipe(_, ges)
    if not self.replaying then return false end
    if ges.direction == "west" then self:step(1) elseif ges.direction == "east" then self:step(-1) else return false end
    return true
end

function PkPuzzleView:onForward() self:step(1); return true end
function PkPuzzleView:onBackward() self:step(-1); return true end

--- Replays the current puzzle from the start. Rating is only affected by the
-- first attempt, which is recorded before restarting.
function PkPuzzleView:onRetry()
    if not self.puzzle then return end
    self:_cancelReply()
    self:_finishAttempt("retry")
    local recorded = self.recorded
    local ok, err = pcall(self.loadPuzzle, self, self.puzzle, self.review, self.stale)
    if not ok then return self:_broken(err) end
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
