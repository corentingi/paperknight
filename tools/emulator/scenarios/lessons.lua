-- Interactive lessons on plugin/tests/fixtures/study.pgn (+ small inline
-- studies): gamebook chapter opens as a lesson, Lichess-style pacing (wait
-- for Next after a commented move), mistakes, hints, Train on an ordinary
-- chapter, error state, acting while a reply is pending.
return function(h)
    local PkStudy = require("pkstudy")
    local PkStudies = require("pkstudies")
    local study = assert(PkStudy.open(os.getenv("PAPERKNIGHT_STUDIES_DIR") .. "/study.pgn"))
    local view
    local function panel() return view.panel_text end
    local function tapButton(id) h.tapWidget(view.buttons:getButtonById(id)) end
    local function tapSquare(sq)
        local b = view.board
        h.tapWidget(b.table:getButtonById(b.toId(sq:byte(1) - 97, tonumber(sq:sub(2, 2)) - 1)))
    end

    -- 1. gamebook chapter opens in lesson mode, upcoming moves hidden
    view = PkStudies.openChapter(study, 2)
    h.wait(1)
    h.check(view.lesson and view.buttons == view.lesson_buttons, "lesson mode")
    h.check(view.title_bar.subtitle_widget.text:find("Chapter 2/5", 1, true), "subtitle in lesson mode")
    h.check(panel():find("Your move %(White%)") and panel():find("mate in two"), "intro + prompt: " .. panel())
    h.check(not panel():find("Qxd8"), "solution not revealed")
    h.shot("lesson-start")

    tapSquare("a2"); tapSquare("a3")
    h.check(panel():find("Not the move"), "unknown move: " .. panel())
    tapSquare("f4"); tapSquare("e5")
    h.check(panel():find("That's a mistake") and panel():find("misses the mate"), "known mistake explained: " .. panel())
    h.check(view.game.get("f4").type == "p", "mistake not kept on the board")

    tapButton("hint")
    h.check(panel():find("d2"), "hint: " .. panel())
    h.check(view.board.shapes.circles[1].square == "d2", "hint drawn as a ring")
    -- correct move with a comment: wait for Next (Lichess pacing)
    tapSquare("d2"); tapSquare("d8")
    h.check(panel():find("Correct!") and panel():find("Forcing!") and panel():find("Tap Next"), "comment kept: " .. panel())
    h.wait(1.5)
    h.check(view.cursor.node.san == "Qxd8+" and view.board.locked, "no auto-reply while a comment is shown")
    tapButton("next")
    h.check(view.cursor.node.san == "Qxd8" and not view.board.locked, "Next played the reply")
    tapSquare("d1"); tapSquare("d8")
    h.check(panel():find("Lesson complete. Mistakes: 2 %(with hints or solutions%)"), "summary: " .. panel())
    h.check(panel():find("Back%-rank mate"), "final comment shown")
    h.shot("lesson-end")

    -- 2. Train an ordinary chapter (as White, its orientation): e4 has a
    --    comment (Next), Nf3 doesn't (automatic reply); variations are sidelines
    view:loadChapter(1)
    h.wait(1)
    h.check(view.buttons == view.browse_buttons, "ordinary chapter opens in browse mode")
    tapButton("train"); h.wait(1)
    h.check(view.lesson and panel():find("Welcome!") and panel():find("Your move %(White%)"), "training: " .. panel())
    tapSquare("e2"); tapSquare("e4")
    h.check(view.waiting_next, "e4 has a comment: wait for Next")
    tapButton("next")
    h.check(view.cursor.node.san == "e5", "reply e5")
    tapSquare("g1"); tapSquare("f3")
    h.check(view._reply_task and not view.waiting_next, "no comment: reply scheduled")
    h.wait(1.5)
    h.check(view.cursor.node.san == "Nc6", "automatic reply Nc6: " .. tostring(view.cursor.node.san))
    tapSquare("f1"); tapSquare("b5")
    h.check(panel():find("sideline") and view.lesson.mistakes == 0, "Bb5 is a sideline: " .. panel())
    tapButton("solution")
    h.check(view.cursor.node.san == "Bc4", "solution played Bc4")
    h.shot("lesson-train")

    -- 3. acting while a reply is pending: Browse, then Restart, then close
    view.reply_delay = 3
    tapButton("restart"); h.wait(1)
    tapSquare("e2"); tapSquare("e4"); tapButton("next") -- e5 (commented e4 waits)
    tapSquare("g1"); tapSquare("f3")
    h.check(view._reply_task, "reply pending")
    tapButton("browse")
    h.wait(3.5)
    h.check(not view.lesson and view.cursor.node.san == "Nf3", "Browse cancelled the reply")
    view:onClose()

    -- 4. opponent moves first and the chapter has an intro: read it first
    local first = PkStudy.fromText('[Orientation "black"]\n[ChapterMode "gamebook"]\n\n{ Black to defend. } 1. e4 e5 2. Nf3 Nc6 *\n', "first")
    view = PkStudies.openChapter(first, 1)
    h.wait(1.5)
    h.check(view.cursor.node == view.cursor.root and view.waiting_next, "intro shown, waiting for Next")
    h.check(panel():find("Black to defend"), "intro: " .. panel())
    tapButton("next")
    h.check(view.cursor.node.san == "e4" and panel():find("Your move %(Black%)"), "then White's first move: " .. panel())
    view.reply_delay = 3
    tapSquare("e7"); tapSquare("e5")
    h.check(view._reply_task, "reply pending")
    view:onClose() -- must cancel the timer (no crash after close)
    h.wait(3.5)

    -- 5. illegal move in the PGN: error state, not a loop
    local broken = PkStudy.fromText('[Event "x"]\n\n1. e4 Ke3 2. d4 *\n', "broken")
    view = PkStudies.openChapter(broken, 1)
    h.wait(1)
    tapButton("train"); h.wait(1)
    tapSquare("e2"); tapSquare("e4")
    h.check(view.lesson.state == "error" and panel():find("illegal move"), "error state: " .. panel())
    h.check(not view._reply_task and view.board.locked, "no timer loop, board locked")
    view:onClose()
end
