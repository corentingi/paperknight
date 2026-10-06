-- Puzzle mode end to end on the fixture pack (make fixture-packs):
-- wrong move, correct mate, rating update, multi-move line with reply,
-- hint, solution and its replay (‹ › and swipes), next puzzle. Squares are tapped like a user would.
return function(h)
    local pk = h.ui.paperknight
    -- A theme saved with an older pack that the current pack lacks must not
    -- leave a blank screen: it falls back to all themes.
    local DataStorage = require("datastorage")
    local PkProgress = require("pkprogress")
    local seed = PkProgress.open(DataStorage:getSettingsDir() .. "/paperknight/progress.sqlite")
    seed:setSetting("theme", "noSuchTheme")
    seed:close()

    local view = pk:startPuzzles()
    h.check(view, "puzzle view did not open (pack missing?)")
    h.wait(1)
    h.check(view.theme == nil and view.puzzle, "stale theme dropped and a puzzle loaded")
    h.check(view.progress:getSetting("theme") == nil, "stale theme cleared from settings")

    -- Coordinate labels follow the orientation.
    local function labels(board)
        local group = board[1][1]              -- HorizontalGroup: ranks | (frame + files) | spacer
        local ranks, files = group[1], group[2][2]
        return ranks[2][1].text .. ranks[9][1].text, files[2][1].text .. files[9][1].text
    end

    local function tapSquare(sq)
        local board = view.board
        local file, rank = sq:byte(1) - 96, tonumber(sq:sub(2, 2))
        h.tapWidget(board.table:getButtonById(board.toId(file - 1, rank - 1)))
    end
    local function tapButton(id) h.tapWidget(view.buttons:getButtonById(id)) end
    local function status() return view.status.text end

    -- 1. Mate in one for Black (board flipped): wrong move first, then the mate.
    view:loadPuzzle(view.pack:get("004JD"))
    h.wait(1)
    h.check(view.board.flipped, "board shows Black's side")
    local r, f = labels(view.board)
    h.check(r == "18" and f == "ha", "flipped labels top-down 1..8, h..a: " .. r .. " " .. f)
    h.check(status():find("Black to move"), "prompt: " .. status())
    h.shot("puzzle-1-start")
    tapSquare("d8"); tapSquare("d1")
    h.check(status():find("Not the move"), "wrong move feedback: " .. status())
    h.check(view.session.mistakes == 1, "mistake counted")
    h.check(view.game.get("d8") ~= nil, "wrong move taken back")
    tapSquare("a3"); tapSquare("c2")
    h.check(view.session.state == "solved", "solved, state=" .. view.session.state)
    h.check(view.progress:attemptCount() == 1, "attempt recorded")
    h.check(view.progress:rating() < 1200, "failed attempt lowers rating: " .. view.progress:rating())
    h.check(status():find("Solved, after a mistake") and status():find("Rating 1200"), "status: " .. status())
    h.check(status():find("come back tomorrow", 1, true), "review announced: " .. status())
    local PkSrs = require("pksrs")
    local today = PkSrs.today()
    local card = view.progress:getReview("004JD")
    h.check(card and card.due == today + 1 and card.step == 0, "missed puzzle scheduled for tomorrow")
    h.shot("puzzle-1-solved")

    -- 2. Mate in two for White: correct move, opponent replies, finishing move.
    view:loadPuzzle(view.pack:get("0042j"))
    h.wait(1)
    -- selection frame on the puzzle board (the board repaints through the view)
    do
        local Screen = require("device").screen
        local function shown(x, y)
            local c = Screen.bb:getPixel(x, y)
            if Screen.bb:getInverse() == 1 or Screen.night_mode then c = c:invert() end
            return c:getColor8().a
        end
        local r = view.board.table:getButtonById(view.board.chessToId("a2")).dimen
        tapSquare("a2"); h.wait(0.5)
        h.check(shown(r.x + 1, r.y + math.floor(r.h / 2)) == 0x00, "selection frame shown on the puzzle board")
        tapSquare("b2"); h.wait(0.5) -- another own piece: selection moves
        h.check(view.board.selected == "b2", "selection switched to b2")
        h.check(shown(r.x + 1, r.y + math.floor(r.h / 2)) ~= 0x00, "a2 frame gone")
        tapSquare("b2"); h.wait(0.3)
    end
    h.check(not view.board.flipped, "board shows White's side")
    r, f = labels(view.board)
    h.check(r == "81" and f == "ah", "labels top-down 8..1, a..h: " .. r .. " " .. f)
    local rating_before = view.progress:rating()
    local function iconAt(sq)
        local file, rank = sq:byte(1) - 96, tonumber(sq:sub(2, 2))
        return view.board.table:getButtonById(view.board.toId(file - 1, rank - 1)).icon
    end
    tapSquare("d2"); tapSquare("d8")
    h.check(status():find("Correct"), "correct: " .. status())
    h.wait(1.5) -- opponent reply delay
    -- what the board shows, not just the game state (which changes immediately)
    h.check(not view.board.locked, "board unlocked after the reply")
    h.check(iconAt("d8"):find("bQ%.svg$"), "black queen shown on d8: " .. iconAt("d8"))
    h.check(iconAt("b6"):find("empty%.svg$"), "b6 emptied: " .. iconAt("b6"))
    h.shot("puzzle-2-reply")
    tapSquare("d1"); tapSquare("d8")
    h.check(view.session:isCleanSolve(), "clean solve")
    h.check(view.progress:rating() > rating_before, "clean solve raises rating")
    h.check(view.buttons == view.replay_buttons and view.session.pos == 4, "solved: replay bar, at the end")
    h.check(not view.buttons:getButtonById("forward").enabled, "› disabled at the end")
    h.shot("puzzle-2-solved")
    tapButton("back")
    h.check(view.session.pos == 3 and iconAt("d8"):find("bQ%.svg$"), "‹ shows the reply again")
    h.check(status():find("Solved!", 1, true) and status():find("Move 2/3: 25… Qxd8", 1, true), "replay status: " .. status())

    -- 3. Hint and solution on the same puzzle via Retry.
    tapButton("retry")
    h.wait(1)
    tapButton("hint")
    h.check(status():find("d2"), "hint names the square: " .. status())
    h.check(view.buttons == view.solve_buttons, "retry: solving bar again")
    tapButton("solution")
    h.check(view.session.state == "failed" and not view.game.in_checkmate(), "solution: only the first move")
    h.check(iconAt("d8"):find("wQ%.svg$"), "the revealed move is drawn: " .. iconAt("d8"))
    h.check(status():find("Solution: 25. Qxd8+ (move 1/3)", 1, true), "solution status: " .. status())
    h.check(view.progress:attemptCount() == 2, "a retry after a recorded attempt is not recorded again")
    h.check(view.buttons == view.replay_buttons, "replay bar")
    h.shot("puzzle-3-solution")
    tapButton("forward"); tapButton("forward")
    h.check(view.game.in_checkmate() and status():find("Move 3/3: 26. Rxd8#", 1, true), "› to the mate: " .. status())
    local mid = view.board.dimen
    h.swipe(mid.x + math.floor(mid.w / 2), mid.y + math.floor(mid.h / 2), "east") -- back
    h.check(view.session.pos == 3, "swipe east steps back")
    for _ = 1, 3 do tapButton("back") end
    h.check(view.session.pos == 0 and status():find("Before the puzzle", 1, true), "start: " .. status())
    h.check(view.game.fen() == view.puzzle.fen and not view.buttons:getButtonById("back").enabled, "puzzle FEN, ‹ disabled")
    h.swipe(mid.x + math.floor(mid.w / 2), mid.y + math.floor(mid.h / 2), "west")
    h.check(view.session.pos == 1 and status():find("Puzzle position, after 24… dxe5", 1, true), "swipe west: " .. status())

    -- 3b. Buttons pressed while the opponent's reply is still pending.
    view.reply_delay = 3
    tapButton("retry"); h.wait(1)
    tapSquare("d2"); tapSquare("d8")
    h.check(view.board.locked and view._reply_task, "reply pending")
    tapButton("solution")
    h.wait(3.5) -- past the original reply time
    h.check(view.session.state == "failed" and view.board.locked, "still finished and locked")
    h.check(status():find("Solution: 26. Rxd8#", 1, true), "status not overwritten by the reply: " .. status())
    h.check(iconAt("d8"):find("wR%.svg$"), "revealed move drawn (Rxd8#): " .. iconAt("d8"))
    tapButton("retry"); h.wait(1)
    tapSquare("d2"); tapSquare("d8")
    tapButton("hint") -- shows the pending reply at once, then the hint
    h.check(not view._reply_task and not view.board.locked, "reply flushed by hint")
    h.check(status():find("d1"), "hint names the next square: " .. status())
    view.reply_delay = 0.6

    -- 4. Theme filter: pick "Mate in 1" in the menu by tapping it.
    h.tapWidget(view.title_bar.left_button)
    h.wait(0.5)
    h.check(view.menu_dialog, "title-bar menu opened")
    for _, row in ipairs(view.menu_dialog.buttontable.buttons_layout) do
        for _, btn in ipairs(row) do
            if btn.text == "Theme…" then h.tapWidget(btn) end
        end
    end
    h.wait(1)
    h.check(view.theme_menu, "theme menu opened")
    h.shot("puzzle-themes")
    local target
    for _, w in ipairs(view.theme_menu.item_group) do
        if w.text == "Mate in 1" then target = w end
    end
    h.check(target, "'Mate in 1' is listed on the first menu page")
    h.tapWidget(target)
    h.wait(1)
    h.check(not view.theme_menu, "menu closed after choosing")
    h.check(view.theme == "mateIn1", "theme set")
    h.check(view.progress:getSetting("theme") == "mateIn1", "theme saved")
    local subtitle = view.title_bar.subtitle_widget.text
    h.check(subtitle:find("Mate in 1"), "subtitle shows the theme: " .. subtitle)
    for _ = 1, 3 do
        h.check((" " .. view.puzzle.themes .. " "):find(" mateIn1 "), "puzzle has the theme: " .. view.puzzle.themes)
        tapButton("next"); h.wait(1)
    end
    h.shot("puzzle-theme-mate1")
    -- choosing the current theme again keeps the current puzzle
    local current = view.puzzle.id
    view:setTheme("mateIn1")
    h.check(view.puzzle.id == current, "re-selecting the same theme is a no-op")

    -- 5. Next picks another puzzle near the rating.
    local last_id = view.puzzle.id
    tapButton("next")
    h.wait(1)
    h.check(view.puzzle and view.puzzle.id ~= last_id, "a new puzzle is loaded")
    h.shot("puzzle-next")

    -- 6. Bad pack data never crashes: an unplayable puzzle is skipped, a
    -- line with an impossible move stops cleanly, a failing save is logged.
    local good = view.pack:get("004JD")
    local function copy(t, extra)
        local c = {}
        for k, v in pairs(t) do c[k] = v end
        for k, v in pairs(extra) do c[k] = v end
        return c
    end
    local bad_fen = copy(good, { id = "BADFEN", fen = "not a fen" })
    local pickNear, picks = view.pack.pickNear, 0
    view.pack.pickNear = function(pack, rating, opts)
        picks = picks + 1
        if picks == 1 then return bad_fen end
        return pickNear(pack, rating, opts)
    end
    h.check(view:nextPuzzle(), "a good puzzle loaded after the bad one")
    h.check(view.puzzle.id ~= "BADFEN" and view._bad.BADFEN, "bad puzzle skipped and remembered")
    view.pack.pickNear = function() error("database is locked") end
    h.check(not view:nextPuzzle(), "a database error is reported")
    h.check(status():find("Cannot load a puzzle", 1, true), "status: " .. status())
    view.pack.pickNear = pickNear

    -- 0042j: setup d6e5, solver d2d8, then an impossible reply
    local line = view.pack:get("0042j")
    local solve = "d2d8"
    view:loadPuzzle(copy(line, { id = "BADLINE", moves = "d6e5 d2d8 a1a1 d1d8" }))
    h.wait(0.5)
    local record = view.progress.record
    view.progress.record = function() error("disk full") end
    tapSquare(solve:sub(1, 2)); tapSquare(solve:sub(3, 4))
    h.wait(0.5)
    h.check(view.session == nil and view.board.locked, "broken line stopped")
    h.check(status():find("invalid move", 1, true), "status: " .. status())
    view.progress.record = record
    h.check(view:nextPuzzle() and view.session, "Next works after a broken puzzle")

    -- 7. Reviews of missed puzzles (ADR-0014): served first when due, no
    -- rating change; clean solve -> 3 days; 4th clean solve -> mastered;
    -- a miss -> tomorrow again; an untouched review is not served twice.
    local function makeDue(step, lapses)
        -- as in a new session (a review is shown once per session)
        view._skipped, view.review = {}, nil
        local c = view.progress:getReview("004JD") or { missed = os.time() }
        view.progress:saveReview("004JD", { step = step, due = today, lapses = lapses or 0, missed = c.missed })
    end
    view:setTheme(nil)
    makeDue(0)
    h.check(view:nextPuzzle() and view.puzzle.id == "004JD" and view.review, "due review served first")
    h.check(status():find("Review: you missed this puzzle", 1, true), "review status: " .. status())
    h.check(view.title_bar.subtitle_widget.text:find("Reviews: 1", 1, true), "due count in the subtitle: "
        .. view.title_bar.subtitle_widget.text)
    h.shot("puzzle-review")
    local rating, attempts = view.progress:rating(), view.progress:attemptCount()
    tapSquare("a3"); tapSquare("c2")
    h.check(view.session.state == "solved", "review solved")
    h.check(status():find("Next review in 3 days", 1, true), "status: " .. status())
    h.check(view.progress:getReview("004JD").due == today + 3, "rescheduled in 3 days")
    h.check(view.progress:rating() == rating and view.progress:attemptCount() == attempts, "no rating change")
    h.check(not status():find("Rating", 1, true), "no rating line for a review")

    makeDue(3)
    view:nextPuzzle()
    h.wait(0.5) -- painted: the squares have their positions
    h.check(view.puzzle.id == "004JD" and view.review, "served again")
    tapSquare("a3"); tapSquare("c2")
    h.check(status():find("Mastered", 1, true) and not view.progress:getReview("004JD"), "mastered: " .. status())

    view.progress:saveReview("004JD", { step = 2, due = today, lapses = 0, missed = os.time() })
    view._skipped, view.review = {}, nil
    view:nextPuzzle()
    h.wait(0.5)
    tapButton("solution")
    h.check(status():find("come back tomorrow", 1, true), "missed review: " .. status())
    card = view.progress:getReview("004JD")
    h.check(card.step == 0 and card.lapses == 1 and card.due == today + 1, "starts over, one lapse")

    makeDue(0, 1)
    view:nextPuzzle()
    h.check(view.review, "review shown")
    view:nextPuzzle() -- skipped without a move
    h.check(view.puzzle.id ~= "004JD" and not view.review, "an untouched review is not served twice")
    h.check(view.progress:getReview("004JD").due == today, "and stays due")

    -- 8. A theme that runs out never serves the same puzzle twice in a row:
    -- unplayed ones first, then repeats (announced), alternating.
    view:setTheme("intermezzo") -- 2 puzzles in the fixture pack
    h.wait(0.5)
    local seen, prev = {}, view.puzzle.id
    seen[prev] = true
    h.check(not view.stale, "first one unplayed")
    for _ = 1, 5 do
        view.progress:record{ puzzle_id = view.puzzle.id, puzzle_rating = view.puzzle.rating, success = true,
                              solved = true, mistakes = 0, used_help = false, ts = os.time() }
        h.check(view:nextPuzzle(), "a puzzle is served")
        h.check(view.puzzle.id ~= prev, "not the same puzzle again: " .. view.puzzle.id)
        prev = view.puzzle.id
        seen[prev] = true
    end
    h.check(view.stale and status():find("repeating", 1, true), "repeats announced: " .. status())
    h.shot("puzzle-theme-repeat")
    local n = 0
    for _ in pairs(seen) do n = n + 1 end
    h.check(n == 2, "both puzzles of the theme served")
    view.progress:removeReview("004JD") -- else it waits as a review
    view:setTheme("cornerMate") -- a single puzzle: 004JD
    h.wait(0.5)
    h.check(view.theme == "cornerMate", "single-puzzle theme chosen")
    local only = view.puzzle.id
    h.check(not view:nextPuzzle(), "no other puzzle")
    h.check(view.puzzle.id == only and status():find("No other puzzle with this theme", 1, true),
        "the current one stays: " .. status())
    view:onClose()
end
