-- Puzzle mode end to end on the fixture pack (make fixture-packs):
-- wrong move, correct mate, rating update, multi-move line with reply,
-- hint, solution, next puzzle. Squares are tapped like a user would.
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
    h.shot("puzzle-2-solved")

    -- 3. Hint and solution on the same puzzle via Retry.
    tapButton("retry")
    h.wait(1)
    tapButton("hint")
    h.check(status():find("d2"), "hint names the square: " .. status())
    tapButton("solution")
    h.check(view.session.state == "failed" and view.game.in_checkmate(), "solution played to mate")
    h.check(view.progress:attemptCount() == 2, "a retry after a recorded attempt is not recorded again")

    -- 3b. Buttons pressed while the opponent's reply is still pending.
    view.reply_delay = 3
    tapButton("retry"); h.wait(1)
    tapSquare("d2"); tapSquare("d8")
    h.check(view.board.locked and view._reply_task, "reply pending")
    tapButton("solution")
    h.wait(3.5) -- past the original reply time
    h.check(view.session.state == "failed" and view.board.locked, "still finished and locked")
    h.check(status():find("Solution shown"), "status not overwritten by the reply: " .. status())
    h.check(iconAt("d8"):find("wR%.svg$"), "final position drawn (Rxd8#): " .. iconAt("d8"))
    tapButton("retry"); h.wait(1)
    tapSquare("d2"); tapSquare("d8")
    tapButton("hint") -- shows the pending reply at once, then the hint
    h.check(not view._reply_task and not view.board.locked, "reply flushed by hint")
    h.check(status():find("d1"), "hint names the next square: " .. status())
    view.reply_delay = 0.6

    -- 4. Theme filter: pick "Mate in 1" in the menu by tapping it.
    h.tapWidget(view.title_bar.left_button)
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
    view:onClose()
end
