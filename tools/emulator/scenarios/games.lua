-- Master games (pkgamesview.lua, ADR-0021) on plugin/tests/fixtures/games.tsv
-- (the Opera Game with made-up scores: the master's move 100, the first
-- other legal move in UCI order 90, the last -200; a key moment at 16. Qb8+;
-- then a short draw): the list, guessing (the master's move, a good move,
-- a miss, a hint, Show move), a key moment, resuming, the end and the best
-- score, the next game, the other side, the analysis board.
local UIManager = require("ui/uimanager")

return function(h)
    local function top() return UIManager._window_stack[#UIManager._window_stack].widget end
    local function menuItem(menu, text)
        for _, w in ipairs(menu.item_group) do
            if w.text and w.text:find(text, 1, true) then return w end
        end
    end
    local function dialogButton(dialog, text)
        for _, row in ipairs(dialog.buttontable.buttons_layout) do
            for _, btn in ipairs(row) do
                if btn.text and btn.text:find(text, 1, true) then return btn end
            end
        end
    end

    local PkGames = require("pkgames")
    PkGames.path = os.getenv("PAPERKNIGHT_STUDIES_DIR") .. "/games.tsv"
    PkGames.reset()
    local PkProgress = require("pkprogress")
    PkProgress.writeSetting("games.current", nil)
    PkProgress.writeSetting("games.best.opera", nil)

    local view
    local function sq(square) return view.board.table:getButtonById(view.board.chessToId(square)) end
    local function move(from, to) h.tapWidget(sq(from)); h.tapWidget(sq(to)) end
    local function panel() return view.panel_text or "" end
    local function guessing() return view.session:guessing() end
    local function button(id) return view.buttons:getButtonById(id) end

    -- 1. The list, from the home screen's modes
    local PkNav = require("pknav")
    PkNav.open("games")
    h.settle()
    local list = top()
    h.check(list.name == "paperknight_master_games", "the list: " .. tostring(list.name))
    h.check(menuItem(list, "The Opera Game · Morphy – Duke Karl Count Isouard, Paris 1858"), "the Opera Game listed")
    h.shot("games-list")
    h.tapWidget(menuItem(list, "The Opera Game"))
    h.settle()
    view = top()
    h.check(view.name == "paperknight_master_game", "the game opened")
    view.reply_delay = 0.1
    h.check(not view.board.flipped and view.session.side == "w", "Morphy's side: White")
    h.check(view.session:ply() == 5, "the opening played: 1. e4 e5 2. Nf3 d6 3. d4")
    h.check(panel():find("Guess Morphy’s moves (○ White).", 1, true)
        and panel():find("A test note.", 1, true), "the intro: " .. panel())
    h.check(view.title_bar.subtitle_widget.text == "Morphy – Duke Karl Count Isouard · Paris 1858",
        "subtitle: " .. view.title_bar.subtitle_widget.text)
    local Screen = require("device").screen
    h.check(view.board_size >= 0.85 * Screen:getWidth(), "a large board: " .. view.board_size)

    -- 2. The master's move: ✓ on it
    h.check(h.waitFor(guessing, 5), "3... Bg4 played for Black")
    h.check(panel():find("What did Morphy play?", 1, true), "asked: " .. panel())
    h.check(not view.board.locked and button("hint").enabled, "the board takes a move")
    move("d4", "e5")
    h.check(panel():find("✓ 4. dxe5: Morphy’s move.", 1, true), "found: " .. panel())
    h.check(view.board.badge and view.board.badge.square == "e5", "a tick on the move")
    h.check(view.board.locked and not button("hint").enabled, "Black's reply next: no move, no hint")
    h.shot("games-found")

    -- 3. A good move too (a3, rated 90 against 100): Qxf3 is played
    h.check(h.waitFor(guessing, 5), "4... Bxf3 played")
    move("a2", "a3")
    h.check(panel():find("A good move too: 5. a3. Morphy played Qxf3.", 1, true), "good: " .. panel())
    h.check(view.game.fen():find("^rn1qkbnr/ppp2ppp/3p4/4P3/4P3/5Q2/PPP2PPP/RNB1KB1R b", 1), "Qxf3 on the board, not a3")

    -- 4. A miss (Nc3: not rated)
    h.check(h.waitFor(guessing, 5), "5... dxe5 played")
    move("b1", "c3")
    h.check(panel():find("Morphy played 6. Bc4. Yours: Nc3.", 1, true), "missed: " .. panel())

    -- 5. A hint, then the master's move: a good move's point
    h.check(h.waitFor(guessing, 5), "6... Nf6 played")
    h.tapWidget(button("hint"))
    h.check(panel():find("Hint: Morphy moved the piece on f3.", 1, true), "hint: " .. panel())
    h.check(view.board.shapes and view.board.shapes.circles[1].square == "f3", "the piece circled")
    move("f3", "b3")
    h.check(panel():find("✓ 7. Qb3, with a hint.", 1, true), "with a hint: " .. panel())

    -- 6. Show move
    h.check(h.waitFor(guessing, 5), "7... Qe7 played")
    h.tapWidget(button("show"))
    h.check(panel():find("Morphy played 8. Nc3.", 1, true), "shown: " .. panel())
    h.check(h.waitFor(guessing, 5), "8... c6 played")
    h.check(view.title_bar.subtitle_widget.text:find("Found 1 of 5 · 2 good", 1, true),
        "the score: " .. view.title_bar.subtitle_widget.text)

    -- 7. Closed and opened again: Continue
    view:onClose()
    h.settle()
    h.check(PkProgress.readSetting("games.current"), "the session saved")
    list = top()
    h.check(list.name == "paperknight_master_games", "back to the list")
    local continue = menuItem(list, "Continue: The Opera Game")
    h.check(continue and list.item_table[1].mandatory == "Found 1 of 5 · 2 good", "Continue first, with the score")
    h.tapWidget(continue)
    h.settle()
    view = top()
    view.reply_delay = 0.1
    h.check(view.session:ply() == 16 and guessing(), "resumed at 9. Bg5")

    -- 8. To the key moment (16. Qb8+)
    while view.session:ply() < 30 do
        if guessing() then h.tapWidget(button("show")) end
        h.check(h.waitFor(function() return guessing() or view.session:ply() >= 30 end, 5), "on to move 16")
    end
    h.check(panel():find("Key moment: one move stands out. What did Morphy play?", 1, true), "key moment: " .. panel())
    move("b3", "b8")
    h.check(panel():find("✓ 16. Qb8+: Morphy’s move. A key moment!", 1, true), "key moment found: " .. panel())

    -- 9. The end: the score, the best kept, Next game
    h.check(h.waitFor(guessing, 5), "16... Nxb8 played")
    move("d1", "d8")
    h.check(view.session:over(), "the game is over")
    h.check(panel():find("Game over: 1-0.", 1, true) and panel():find("Found 3 of 14 · 2 good · 29%", 1, true)
        and panel():find("Key moments: 1 of 1", 1, true), "the end: " .. panel())
    h.check(not panel():find("Your best", 1, true), "the first time: no best to compare with")
    h.check(PkProgress.readSetting("games.current") == nil, "no session kept once over")
    h.check(PkProgress.readSetting("games.best.opera"), "the best score kept")
    h.check(button("show").text == "Next game" and button("show").enabled, "Next game")
    h.check(view.board.locked, "no more moves")
    h.shot("games-over")

    -- 10. The analysis board: the whole game
    h.tapWidget(button("analyse"))
    h.settle()
    local av = top()
    h.check(av.name == "paperknight_analysis" and av.pos == 33, "the game on the analysis board")
    av:onClose()
    h.settle()

    -- 11. The next game (a draw: White's moves), then Black's
    h.tapWidget(button("show"))
    h.settle()
    h.check(view.session.game.id == "draw" and view.session.side == "w" and guessing(), "the next game")
    view:showMenu()
    h.settle()
    h.tapWidget(dialogButton(view.menu_dialog, "instead"))
    h.settle()
    h.check(view.session.side == "b" and view.board.flipped, "Black's moves, the board flipped")
    h.check(h.waitFor(guessing, 5), "2. Nf3 played for White")

    -- the list shows the best score
    view:onClose()
    h.settle()
    list = top()
    h.check(list.name == "paperknight_master_games", "the list again")
    local opera = menuItem(list, "The Opera Game")
    h.check(opera and opera.mandatory and opera.mandatory:find("^Best: %d+%%$"), "best score listed: "
        .. tostring(opera and opera.mandatory))
    PkNav.home()
    h.settle()
end
