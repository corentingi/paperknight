-- Interactive lessons on plugin/tests/fixtures/study.pgn (+ small inline
-- studies): gamebook chapter opens as a lesson, Lichess-style pacing (wait
-- for Next after a commented move), mistakes, hints, Train on an ordinary
-- chapter, error state, acting while a reply is pending.
return function(h)
    local PkStudy = require("pkstudy")
    local PkStudies = require("pkstudies")
    -- chapter marks are remembered in progress.sqlite: start clean
    local DataStorage = require("datastorage")
    local PkProgress = require("pkprogress")
    local PkDone = require("pkdone")
    local function withDb(fn)
        local p = PkProgress.open(DataStorage:getSettingsDir() .. "/paperknight/progress.sqlite")
        local r = fn(p)
        p:close()
        return r
    end
    withDb(function(p) p.conn:exec("DELETE FROM kv WHERE key LIKE 'setting.chapter_done:%' OR key LIKE 'setting.study_last:%'") end)
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
    h.check(panel():find("Your move %(○ White%)") and panel():find("mate in two"), "intro + prompt: " .. panel())
    h.check(not panel():find("Qxd8"), "solution not revealed")
    h.shot("lesson-start")

    tapSquare("a2"); tapSquare("a3")
    h.check(panel():find("Not the move"), "unknown move: " .. panel())
    -- e-ink: a lesson move on the board sends only "[partial]" refreshes
    -- (no tap highlight, no "ui" selection refresh; docs/eink-refresh.md)
    local stop = h.recordRefreshes()
    tapSquare("f4"); tapSquare("e5")
    for _, r in ipairs(stop()) do
        h.check(r.mode == "[partial]", ("lesson move refresh: %s %d,%d %dx%d"):format(r.mode, r.x, r.y, r.w, r.h))
    end
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
    h.check(view.progress and PkDone.isChapterDone(view.progress, "study.pgn", 2), "finished lesson marks the chapter done")
    h.check(panel():find("^Correct!"), "status first: " .. panel())
    h.check(view.buttons:getButtonById("next").enabled, "Next offers the next chapter")
    h.check(panel():find("Back%-rank mate"), "final comment shown")
    h.shot("lesson-end")

    tapButton("next")
    h.wait(1)
    h.check(view.chapter_index == 3, "Next went to chapter 3")

    -- 2. Train an ordinary chapter (as White, its orientation): e4 has a
    --    comment (Next), Nf3 doesn't (automatic reply); variations are sidelines
    view:loadChapter(1)
    h.wait(1)
    h.check(view.buttons == view.browse_buttons, "ordinary chapter opens in browse mode")
    tapButton("train"); h.wait(1)
    h.check(view.lesson and panel():find("Welcome!") and panel():find("^Your move %(○ White%)"), "training, status first: " .. panel())
    h.check(view.board.shapes == nil, "annotator shapes hidden while the student is to move")
    tapSquare("e2"); tapSquare("e4")
    h.check(view.waiting_next, "e4 has a comment: wait for Next")
    tapButton("next")
    h.check(view.cursor.node.san == "e5", "reply e5")
    view.reply_delay = 3 -- generous margin: the tap itself waits 0.5 s
    tapSquare("g1"); tapSquare("f3")
    h.check(view._reply_task and not view.waiting_next, "no comment: reply scheduled")
    h.wait(3.5)
    view.reply_delay = 0.8
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
    h.check(view.cursor.node.san == "e4" and panel():find("Your move %(● Black%)"), "then White's first move: " .. panel())
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

    -- chapter list: ✓ on the finished chapter, "Continue" opens the last one
    local chapters = PkStudies.openStudy(os.getenv("PAPERKNIGHT_STUDIES_DIR") .. "/study.pgn")
    h.wait(1)
    local function item(text)
        for _, w in ipairs(chapters.item_group) do
            if w.text and (w.text:sub(1, #text) == text or (text == "Continue:" and w.text:find(text, 1, true))) then return w end
        end
    end
    h.check(item("2. Mate in two") and item("2. Mate in two").mandatory == "lesson ✓", "✓ next to the finished lesson: "
        .. tostring(item("2. Mate in two") and item("2. Mate in two").mandatory))
    local cont = item("Continue:")
    h.check(cont, "Continue entry")
    h.shot("chapters-progress")
    h.tapWidget(cont)
    h.wait(1)
    local last_view = require("ui/uimanager")._window_stack[#require("ui/uimanager")._window_stack].widget
    h.check(last_view.name == "paperknight_study", "Continue opens a chapter: " .. tostring(last_view.name))
    -- manual toggle from the ≡ menu, and back in the list
    last_view:loadChapter(1)
    last_view:setChapterDone(true)
    h.check(PkDone.isChapterDone(last_view.progress, "study.pgn", 1), "chapter 1 marked by hand")
    last_view:onClose()
    h.wait(1)
    h.check(item("1. Italian ideas").mandatory == "✓", "list updated: " .. tostring(item("1. Italian ideas").mandatory))
    h.check(item("Continue:") and item("Continue:").text:find("Continue: 1.", 1, true), "Continue follows the last chapter opened")
    require("ui/uimanager"):close(chapters)
end
