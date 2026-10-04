-- Studies end to end on plugin/tests/fixtures/study.pgn
-- (PAPERKNIGHT_STUDIES_DIR is set by `make e2e`): browse, navigate the tree,
-- choose a variation, play moves on the board, shapes, flipped chapter.
local UIManager = require("ui/uimanager")

return function(h)
    local function top() return UIManager._window_stack[#UIManager._window_stack].widget end
    local function menuItem(menu, text)
        for _, w in ipairs(menu.item_group) do
            if w.text and w.text:find(text, 1, true) then return w end
        end
    end

    local PkStudies = require("pkstudies")
    local list = PkStudies.show()
    h.wait(1)
    local file_item = menuItem(list, "study")
    h.check(file_item, "study file listed")
    h.tapWidget(file_item)
    h.wait(1)
    local chapters = top()
    h.check(chapters.title == "Paperknight test study", "chapter list title: " .. tostring(chapters.title))
    h.shot("study-chapters")
    h.tapWidget(menuItem(chapters, "1. Italian ideas"))
    h.wait(1)

    local view = top()
    h.check(view.name == "paperknight_study", "study view opened")
    local function panel() return view.panel_text end
    local function tapButton(id) h.tapWidget(view.buttons:getButtonById(id)) end
    local function tapSquare(sq)
        local b = view.board
        h.tapWidget(b.table:getButtonById(b.toId(sq:byte(1) - 97, tonumber(sq:sub(2, 2)) - 1)))
    end

    h.check(panel():find("Welcome!"), "intro comment shown: " .. panel())
    h.check(view.board.shapes and #view.board.shapes.circles == 2, "intro circles set")
    h.shot("study-intro")

    for _ = 1, 4 do tapButton("forward") end
    h.check(panel():find("^2%.%.%. Nc6"), "after 4 forwards: " .. panel())
    h.check(panel():find("3. Bc4!? (main)", 1, true) and panel():find("3. Bb5", 1, true), "alternatives listed: " .. panel())
    h.check(view.buttons:getButtonById("lines").enabled, "Lines enabled at a branch")

    tapButton("lines")
    h.wait(1)
    h.check(view.lines_dialog, "lines dialog open")
    h.shot("study-lines")
    local bb5
    for _, row in ipairs(view.lines_dialog.buttontable.buttons_layout) do
        for _, btn in ipairs(row) do
            if btn.text and btn.text:find("Bb5", 1, true) then bb5 = btn end
        end
    end
    h.check(bb5, "Bb5 offered")
    h.tapWidget(bb5)
    h.wait(1)
    h.check(panel():find("^3%. Bb5"), "variation entered: " .. panel())
    h.check(panel():find("The Spanish."), "variation comment")
    h.check(not view.cursor:onMainline(), "off the main line")
    tapButton("back")
    h.check(panel():find("^2%.%.%. Nc6"), "back to the branch")

    tapButton("end")
    h.check(panel():find("^8%.%.%. d5"), "end of main line: " .. panel())
    h.check(#view.board.shapes.arrows == 2 and #view.board.shapes.circles == 1, "final shapes")
    h.shot("study-shapes")

    -- moves played on the board follow the study
    tapButton("start")
    tapSquare("e2"); tapSquare("e4")
    h.check(panel():find("^1%. e4"), "board move followed the study: " .. panel())
    h.check(#view.board.shapes.arrows == 1, "e4 arrow shown")
    tapSquare("d7"); tapSquare("d5")
    h.check(panel():find("not in the study"), "unknown move refused: " .. panel())
    h.check(view.game.get("d7") ~= nil and view.cursor.node.san == "e4", "position unchanged")
    local function iconAt(sq)
        local b = view.board
        return b.table:getButtonById(b.toId(sq:byte(1) - 97, tonumber(sq:sub(2, 2)) - 1)).icon
    end
    h.check(iconAt("d5"):find("empty%.svg$") and iconAt("d7"):find("bP%.svg$"), "board redrawn after refusal")
    h.check(#view.game.redo_stack == 0, "no redo entries left by board moves")

    -- chapter menu: black orientation chapter
    h.tapWidget(view.title_bar.left_button)
    h.wait(1)
    h.tapWidget(menuItem(view.chapter_menu, "Alice"))
    h.wait(1)
    h.check(view.chapter_index == 3 and view.board.flipped, "chapter 3 shown from Black's side")
    h.check(not view.chapter_menu and top() == view, "chapter menu closed after the pick")
    tapButton("forward")
    h.check(panel():find("^60%.%.%. Ra6%+"), "black move numbering: " .. panel())
    h.shot("study-black")
    view:onClose()
    h.wait(0.5)
    h.check(top() == chapters, "closing the chapter returns to the chapter list")

    -- a chapter that cannot be opened (invalid FEN) shows an error and locks input
    local PkStudy = require("pkstudy")
    local broken = PkStudy.fromText('[Event "Broken"]\n[FEN "not a fen"]\n\n1. e4 *\n', "broken")
    local bview = PkStudies.openChapter(broken, 1)
    h.wait(1)
    h.check(bview.panel_text:find("Cannot open this chapter"), "error shown: " .. tostring(bview.panel_text))
    h.check(bview.board.locked and not bview.buttons:getButtonById("forward").enabled, "input locked")
    h.tapWidget(bview.buttons:getButtonById("forward")) -- must not crash
    bview:onForward()
    bview:onClose()
end
