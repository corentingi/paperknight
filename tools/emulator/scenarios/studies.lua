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

    local function dialogButton(dialog, text)
        for _, row in ipairs(dialog.buttontable.buttons_layout) do
            for _, btn in ipairs(row) do
                if btn.text and btn.text:find(text, 1, true) then return btn end
            end
        end
    end

    -- flips are remembered in progress.sqlite: start from a clean state
    local DataStorage = require("datastorage")
    local PkProgress = require("pkprogress")
    local progress = PkProgress.open(DataStorage:getSettingsDir() .. "/paperknight/progress.sqlite")
    progress:setSetting("study_flip:study.pgn#3", nil)
    progress:close()

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

    -- e-ink: browsing (steps and jumps) only asks for "partial" refreshes
    -- of the view (no flicker; KOReader's full refresh rate applies)
    local modes = {}
    local setDirty = UIManager.setDirty
    UIManager.setDirty = function(um, widget, mode, ...)
        if widget == view and type(mode) == "string" then modes[#modes + 1] = mode end
        return setDirty(um, widget, mode, ...)
    end

    for _ = 1, 4 do tapButton("forward") end
    h.check(panel():find("^2%.%.%. Nc6"), "after 4 forwards: " .. panel())
    h.check(panel():find("3. Bc4!? (main)", 1, true) and panel():find("3. Bb5", 1, true), "alternatives listed: " .. panel())
    h.check(view.buttons:getButtonById("lines").enabled, "Lines enabled at a branch")
    tapButton("forward") -- 3. Bc4!?
    local badge = view.board.badge
    h.check(badge and badge.square == "c4" and badge.text == "!?", "move-mark badge on c4: " .. tostring(badge and badge.text))
    h.shot("study-badge")
    tapButton("back")
    h.check(view.board.badge == nil, "no badge on a move without a mark")

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
    h.check(panel():find("has counterplay", 1, true), "position mark in words: " .. panel())
    h.check(#view.board.shapes.arrows == 2 and #view.board.shapes.circles == 1, "final shapes")
    h.shot("study-shapes")
    tapButton("start")
    UIManager.setDirty = setDirty
    h.check(#modes >= 6, "refreshes recorded: " .. #modes)
    for _, m in ipairs(modes) do h.check(m == "partial", "browsing refresh: " .. m) end
    -- greyed when they can't act; at the end of a line › opens the next chapter
    view:toEnd()
    h.wait(0.5) -- painted, like a user sees it before tapping
    local function enabled(id) return view.browse_buttons:getButtonById(id).enabled end
    h.check(not enabled("end") and enabled("forward") and enabled("back"), "end of line: ›| greyed, › enabled")
    h.check(panel():find("› Next chapter: Mate in two", 1, true), "next chapter announced: " .. panel())
    local PkDone = require("pkdone")
    view.progress:setSetting("chapter_done:study.pgn#1", nil)
    tapButton("forward")
    h.check(view.chapter_index == 2, "› at the end of a line: next chapter (" .. view.chapter_index .. ")")
    h.check(PkDone.isChapterDone(view.progress, "study.pgn", 1), "the chapter left is marked done")
    view:loadChapter(4) -- a chapter without moves (intro): › is the way on
    h.wait(0.5)
    h.check(not (enabled("start") or enabled("back") or enabled("end")) and enabled("forward"), "empty chapter: only › enabled")
    h.check(panel():find("› Next chapter: Specials", 1, true), "empty chapter: " .. panel())
    tapButton("forward")
    h.check(view.chapter_index == 5, "empty chapter: › opens the next one")
    h.check(not PkDone.isChapterDone(view.progress, "study.pgn", 4), "an intro chapter is not marked")
    view.progress:setSetting("chapter_done:study.pgn#1", nil)
    view:toEnd()
    h.check(not enabled("forward") and not enabled("end"), "end of the last chapter: › ›| greyed")
    h.check(not panel():find("Next chapter", 1, true), "no next chapter after the last: " .. panel())
    view:loadChapter(1)
    h.wait(0.5)
    h.check(not enabled("start") and not enabled("back") and enabled("forward"), "chapter start: |‹ ‹ greyed")

    -- moves played on the board follow the study
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

    -- title-bar menu → chapters: black orientation chapter
    h.tapWidget(view.title_bar.left_button)
    h.wait(1)
    h.check(view.menu_dialog, "title-bar menu open")
    h.tapWidget(dialogButton(view.menu_dialog, "Chapters"))
    h.wait(1)
    h.tapWidget(menuItem(view.chapter_menu, "Alice"))
    h.wait(1)
    h.check(view.chapter_index == 3 and view.board.flipped, "chapter 3 shown from Black's side")
    h.check(not view.chapter_menu and top() == view, "chapter menu closed after the pick")
    tapButton("forward")
    h.check(panel():find("^60%.%.%. Ra6%+"), "black move numbering: " .. panel())
    h.shot("study-black")

    -- Flip board: remembered for this chapter, and the lesson trains the side shown
    h.tapWidget(view.title_bar.left_button)
    h.wait(1)
    h.tapWidget(dialogButton(view.menu_dialog, "Flip board"))
    h.wait(1)
    h.check(not view.board.flipped and view:orientation() == "white", "flipped to White's side")
    h.check(view.cursor.node.san == "Ra6+", "position kept after the flip")
    local study = view.study
    view:onClose()
    h.wait(0.5)
    h.check(top() == chapters, "closing the chapter returns to the chapter list")
    view = PkStudies.openChapter(study, 3)
    h.wait(1)
    h.check(not view.board.flipped, "flip remembered when the chapter is reopened")
    view:startLesson()
    h.check(view.lesson.student == "w", "lesson trains the side shown: " .. view.lesson.student)
    view:loadChapter(1)
    h.check(not view.board.flipped, "other chapters keep their orientation")
    view:loadChapter(3)
    view:toggleFlip()
    h.check(view.board.flipped, "flipped back to the chapter's orientation")
    view:onClose()
    h.wait(0.5)

    -- a chapter that cannot be opened (invalid FEN) shows an error and locks input
    local PkStudy = require("pkstudy")
    local broken = PkStudy.fromText('[Event "Broken"]\n[FEN "not a fen"]\n\n1. e4 *\n', "broken")
    local bview = PkStudies.openChapter(broken, 1)
    h.wait(1)
    h.check(bview.panel_text:find("Cannot open this chapter"), "error shown: " .. tostring(bview.panel_text))
    h.check(bview.board.locked and not bview.buttons:getButtonById("forward").enabled, "input locked")
    h.tapWidget(bview.buttons:getButtonById("forward")) -- must not crash
    bview:onForward()
    bview:toggleFlip() -- rebuilds the board: must stay locked
    h.check(bview.board.flipped and bview.board.locked, "flipped broken chapter stays locked")
    bview:onClose()
    h.wait(0.5)

    -- the studies list follows its folder (e.g. a PGN copied while it is open)
    local lfs = require("libs/libkoreader-lfs")
    local tmp = DataStorage:getSettingsDir() .. "/pk-e2e-studies"
    lfs.mkdir(tmp)
    for entry in lfs.dir(tmp) do
        if entry:match("%.pgn$") then os.remove(tmp .. "/" .. entry) end
    end
    local function write(name)
        local f = assert(io.open(tmp .. "/" .. name, "w"))
        f:write('[Event "x"]\n\n1. e4 *\n')
        f:close()
    end
    write("first.pgn")
    local tlist = PkStudies.show(tmp)
    h.wait(1)
    h.check(menuItem(tlist, "first") and not menuItem(tlist, "second"), "one study listed")
    local cover = PkStudies.openChapter(broken, 1) -- something on top of the list
    h.wait(0.5)
    write("second.pgn")
    cover:onClose()
    h.wait(1)
    h.check(menuItem(tlist, "second"), "new study listed after returning to the list")
    UIManager:close(tlist)
    h.wait(0.5)

    -- folders: listed first with "done/total"; a renames file carries the
    -- marks of a study renamed by a reorganised collection
    local lfs = require("libs/libkoreader-lfs")
    lfs.mkdir(tmp .. "/Openings")
    write("Openings/third.pgn")
    write("Openings/fourth.pgn")
    local rf = assert(io.open(tmp .. "/RENAMES.txt", "w"))
    rf:write("Opening - third.pgn\tthird.pgn\n")
    rf:close()
    progress = PkProgress.open(DataStorage:getSettingsDir() .. "/paperknight/progress.sqlite")
    progress:setSetting("study_done:third.pgn", nil)
    progress:setSetting("study_done:Opening - third.pgn", "1")
    progress:close()
    local flist = PkStudies.show(tmp)
    h.wait(1)
    local folder = menuItem(flist, "Openings/")
    h.check(folder and folder.mandatory == "1/2 ✓", "folder with its count: " .. tostring(folder and folder.mandatory))
    h.check(flist.item_table[1].text == "Openings/", "folders first")
    h.shot("study-folders")
    h.tapWidget(folder)
    h.wait(1)
    local sub = top()
    h.check(sub ~= flist and sub.title == "Openings", "folder opened: " .. tostring(sub.title))
    local third = menuItem(sub, "third")
    h.check(third and third.mandatory == "✓", "mark kept after the rename")
    h.check(not menuItem(sub, "Open a PGN file"), "no file chooser in sub-folders")
    UIManager:close(sub)
    h.wait(0.5)
    h.check(top() == flist, "back to the top level")
    UIManager:close(flist)
    h.wait(0.5)
    os.remove(tmp .. "/Openings/third.pgn"); os.remove(tmp .. "/Openings/fourth.pgn")
    os.remove(tmp .. "/Openings"); os.remove(tmp .. "/RENAMES.txt")
    progress = PkProgress.open(DataStorage:getSettingsDir() .. "/paperknight/progress.sqlite")
    progress:setSetting("study_done:third.pgn", nil)
    progress:close()

    -- done marks: long-press in the list, or the study's ≡ menu
    progress = PkProgress.open(DataStorage:getSettingsDir() .. "/paperknight/progress.sqlite")
    progress:setSetting("study_done:study.pgn", nil)
    progress:close()
    local dlist = PkStudies.show()
    h.wait(1)
    local item = menuItem(dlist, "study")
    h.check(item and item.mandatory == nil, "not done at first: " .. tostring(item and item.mandatory))
    dlist:onMenuHold(item.entry) -- long-press
    h.wait(1)
    item = menuItem(dlist, "study")
    h.check(item.mandatory == "✓" and item.text == "study", "✓ on the right: " .. item.text .. " / " .. tostring(item.mandatory))
    h.shot("study-done")
    h.tapWidget(item)
    h.wait(1)
    local dchapters = top()
    h.tapWidget(menuItem(dchapters, "1. Italian ideas"))
    h.wait(1)
    local dview = top()
    h.tapWidget(dview.title_bar.left_button)
    h.wait(0.5)
    local undone = dialogButton(dview.menu_dialog, "Mark study as not done")
    h.check(undone, "menu offers to unmark")
    h.tapWidget(undone)
    h.wait(0.5)
    dview:onClose()
    h.wait(0.5)
    UIManager:close(dchapters)
    h.wait(1)
    item = menuItem(dlist, "study")
    h.check(top() == dlist and item.mandatory == nil, "unmarked from the study menu: " .. tostring(item.mandatory))
    UIManager:close(dlist)
    h.wait(0.5)

    -- selection: tapping another own piece selects it; no border is left on
    -- the neighbours (the old frame border spilled over them and crashed)
    local Screen = require("device").screen
    local sel_study = PkStudy.fromText('[Event "sel"]\n[FEN "4k3/8/8/8/8/1P6/P7/4K3 w - - 0 1"]\n\n1. a4 *\n', "sel")
    local sview = PkStudies.openChapter(sel_study, 1)
    h.wait(1)
    local function tapSq(sq)
        local b = sview.board
        h.tapWidget(b.table:getButtonById(b.toId(sq:byte(1) - 97, tonumber(sq:sub(2, 2)) - 1)))
    end
    local function shown(x, y)
        local c = Screen.bb:getPixel(x, y)
        if Screen.bb:getInverse() == 1 or Screen.night_mode then c = c:invert() end
        return c:getColor8().a
    end
    local function rectOf(sq) return sview.board.table:getButtonById(sview.board.chessToId(sq)).dimen end
    tapSq("a2"); h.wait(0.3)
    h.check(sview.board.selected == "a2" and sview.board.selected_mark == "a2", "a2 selected")
    local a2 = rectOf("a2")
    h.check(shown(a2.x + 1, a2.y + math.floor(a2.h / 2)) == 0x00, "selection frame drawn inside a2")
    tapSq("b3"); h.wait(0.5)
    h.check(sview.board.selected == "b3", "tapping another own piece selects it: " .. tostring(sview.board.selected))
    local b2 = rectOf("b2")
    h.check(shown(b2.x + 3, b2.y + math.floor(b2.h / 2)) == 0xBB, "no border left on b2: "
        .. string.format("%x", shown(b2.x + 3, b2.y + math.floor(b2.h / 2))))
    h.check(shown(a2.x + 1, a2.y + math.floor(a2.h / 2)) ~= 0x00, "a2 frame removed")
    tapSq("b3"); h.wait(0.3)
    h.check(sview.board.selected == nil and sview.board.selected_mark == nil, "tap again: unselected")
    tapSq("a2"); tapSq("a4"); h.wait(0.5)
    h.check(sview.cursor.node.san == "a4", "then a move still plays: " .. tostring(sview.cursor.node.san))
    sview:onClose()
    h.wait(0.3)

    -- links: short in the panel; a tap on one shows its QR code; ≡ → Links…
    local lstudy = PkStudy.fromText('[Event "links"]\n\n{ Watch https://lichess.org/study/abcdefgh then see www.example.com/page. }\n1. e4 *\n', "links")
    local lview = PkStudies.openChapter(lstudy, 1)
    h.wait(1)
    h.check(lview.panel_text:find("lichess.org ↗ then see example.com ↗.", 1, true), "links shown short: " .. lview.panel_text)
    h.check(#lview.links == 2, "two links")
    local tw = lview.text.text_widget
    local x, y = tw:_getXYForCharPos(lview.links[1].first + 2)
    h.tap(tw.dimen.x + x + 2, tw.dimen.y + y + math.floor(tw.line_height_px / 2))
    h.wait(1)
    local qr = top()
    h.check(qr ~= lview and qr.text == "https://lichess.org/study/abcdefgh", "tap on the link shows its QR code: " .. tostring(qr.text))
    h.shot("study-link-qr")
    UIManager:close(qr)
    h.wait(0.5)
    h.tapWidget(lview.title_bar.left_button)
    h.wait(0.5)
    local links_btn = dialogButton(lview.menu_dialog, "Links (2)")
    h.check(links_btn, "≡ menu offers the links")
    h.tapWidget(links_btn)
    h.wait(0.5)
    local PkLinks = require("pklinks")
    h.tapWidget(dialogButton(PkLinks.dialog, "example.com"))
    h.wait(0.5)
    h.check(top().text == "https://www.example.com/page", "QR of a www address gets a scheme: " .. tostring(top().text))
    UIManager:close(top())
    h.wait(0.3)
    -- a tap elsewhere in the panel still scrolls (no QR)
    h.tap(tw.dimen.x + 2, tw.dimen.y + tw.dimen.h - 2)
    h.wait(0.5)
    h.check(top() == lview, "no QR for a tap outside links")
    lview:onClose()
    h.wait(0.3)
    -- a tap in the blank right of a soft-wrapped line must not open the link
    -- that starts the next line (getCharPosAtXY returns cursor positions)
    local TextBoxWidget = require("ui/widget/textboxwidget")
    local Font = require("ui/font")
    local Geom = require("ui/geometry")
    local PkText = require("pktext")
    local found
    for n = 1, 60 do
        local text, links = PkText.linkify(string.rep("word ", n) .. "https://lichess.org/practice")
        local box = TextBoxWidget:new{ text = text, face = Font:getFace("cfont", 18), width = 400 }
        box.dimen = Geom:new{ x = 0, y = 0, w = 400, h = box:getSize().h }
        local cx, cy = box:_getXYForCharPos(links[1].first)
        if cx <= 1 and cy > 0 then found = { box = box, links = links, row = math.floor(cy / box.line_height_px) }; break end
        box:free()
    end
    h.check(found, "a text where the link starts a wrapped line")
    local lh = found.box.line_height_px
    local blank = { pos = { x = 395, y = (found.row - 1) * lh + math.floor(lh / 2) } }
    h.check(PkLinks.linkAtTap(found.box, found.links, blank) == nil, "blank right of the previous line: no link")
    local on_link = { pos = { x = 5, y = found.row * lh + math.floor(lh / 2) } }
    h.check(PkLinks.linkAtTap(found.box, found.links, on_link) ~= nil, "tap on the link itself")
    -- a panel shorter than its text: the strip under the last visible line
    -- maps to the next, hidden line
    local text2, links2 = PkText.linkify("first line\nhttps://lichess.org/hidden")
    local short = TextBoxWidget:new{ text = text2, face = Font:getFace("cfont", 18), width = 400,
                                     height = math.floor(lh * 1.6) }
    short.dimen = Geom:new{ x = 0, y = 0, w = 400, h = math.floor(lh * 1.6) }
    h.check(short:getVisLineCount() == 1, "one visible line")
    local strip = { pos = { x = 5, y = math.floor(lh * 1.3) } }
    h.check(PkLinks.linkAtTap(short, links2, strip) == nil, "strip below the last visible line: hidden link not opened")
    short:free()
    found.box:free()
end
