-- Openings trainer end to end on plugin/tests/fixtures/repertoires
-- (PAPERKNIGHT_REPERTOIRES_DIR is set by `make e2e`): list with counts,
-- learn a line (new moves shown as arrows), a known mistake, then the same
-- moves tested the same day, a failure saved, counts after the session.
local UIManager = require("ui/uimanager")

return function(h)
    local function top() return UIManager._window_stack[#UIManager._window_stack].widget end
    local function menuItem(menu, text)
        for _, w in ipairs(menu.item_group) do
            if w.text and w.text:find(text, 1, true) then return w end
        end
    end

    -- start from a clean review history
    local DataStorage = require("datastorage")
    local PkProgress = require("pkprogress")
    local progress = PkProgress.open(DataStorage:getSettingsDir() .. "/paperknight/progress.sqlite")
    progress.conn:exec("DELETE FROM rep_cards")
    progress:close()

    local PkOpenings = require("pkopenings")
    local lfs = require("libs/libkoreader-lfs")
    local cache = PkOpenings.cacheDir()
    os.remove(cache .. "/repertoire.pgn.sum"); os.remove(cache .. "/repertoire.pgn.res")
    -- the cache of a repertoire deleted since: removed when the list opens
    for _, ext in ipairs({ ".sum", ".res" }) do
        local f = assert(io.open(cache .. "/deleted.pgn" .. ext, "w")); f:write("x"); f:close()
    end
    PkOpenings._clearMemory()
    local list = PkOpenings.show()
    h.settle()
    h.check(not lfs.attributes(cache .. "/deleted.pgn.sum") and not lfs.attributes(cache .. "/deleted.pgn.res"),
        "a deleted repertoire's cache removed")
    local item = menuItem(list, "repertoire")
    h.check(item, "repertoire listed")
    h.check(item.mandatory == "0 due · 10 new", "counts: " .. tostring(item.mandatory))
    -- the on-disk cache: after a restart the list is built without parsing
    h.check(lfs.attributes(cache .. "/repertoire.pgn.sum", "size"), "summary cached")
    h.check(lfs.attributes(cache .. "/repertoire.pgn.res", "size"), "resolved moves cached")
    PkOpenings._clearMemory()
    local dir = os.getenv("PAPERKNIGHT_REPERTOIRES_DIR")
    h.check(not PkOpenings.needsParse(dir .. "/repertoire.pgn"), "no parse after a restart")
    -- a damaged summary (its last card cut) is refused, then written again
    local sum = cache .. "/repertoire.pgn.sum"
    local f = assert(io.open(sum)); local good = f:read("*a"); f:close()
    f = assert(io.open(sum, "w")); f:write((good:gsub("[^\n]*\n$", ""))); f:close()
    PkOpenings._clearMemory()
    h.check(PkOpenings.needsParse(dir .. "/repertoire.pgn"), "a truncated summary is refused")
    PkOpenings.load(dir .. "/repertoire.pgn", nil, true)
    f = assert(io.open(sum)); local again = f:read("*a"); f:close()
    h.check(again == good, "and written again")
    PkOpenings._clearMemory()
    PkOpenings.refreshList()
    item = menuItem(list, "repertoire")
    h.check(item.mandatory == "0 due · 10 new", "same counts from the cache: " .. tostring(item.mandatory))
    PkOpenings._clearMemory() -- the drill below starts from the .res cache
    h.shot("openings-list")
    h.tapWidget(item)
    h.settle()

    local view = top()
    h.check(view.name == "paperknight_drill", "drill opened")
    view.reply_delay = 0.1
    local drill = view.drill
    local function panel() return view.panel_text end
    local function tapSquare(sq)
        local b = view.board
        h.tapWidget(b.table:getButtonById(b.toId(sq:byte(1) - 97, tonumber(sq:sub(2, 2)) - 1)))
    end
    local function play(uci) tapSquare(uci:sub(1, 2)); tapSquare(uci:sub(3, 4)) end
    local function waitReply() h.settle() end

    -- 1. learning the first line: e4, Nf3, Bc4, c3 are shown as arrows
    h.check(panel():find("New move: play e4", 1, true), "intro: " .. panel())
    local arrows = view.board.shapes and view.board.shapes.arrows
    h.check(arrows and arrows[1].from == "e2" and arrows[1].to == "e4", "arrow shows the new move")
    h.check(not view.board.flipped, "White's repertoire shown from White's side")
    h.shot("openings-intro")
    play("e2e4"); waitReply()
    h.check(drill.cursor.node.move.san == "e5", "opponent replied 1... e5")
    -- the move list: the moves played only (the answer is not shown)
    h.check(view.movelist and table.concat(view.movelist.moves, " ") == "e4 e5" and view.movelist.current == 2,
        "move list: the moves played: " .. table.concat(view.movelist and view.movelist.moves or {}, " "))
    local sub = view.title_bar.subtitle_widget.text
    h.check(sub:find("C20 King's Pawn Game", 1, true) and not panel():find("King's Pawn", 1, true),
        "opening named in the subtitle, not the panel: " .. sub)
    h.check(view.board.turn_marker == "w" and not panel():find("Your move", 1, true),
        "your turn: the corner marker, no line for it")
    play("g1f3"); waitReply()
    play("f1b5")
    h.check(panel():find("Not in your repertoire", 1, true) and panel():find("Not our line", 1, true),
        "known mistake explained: " .. panel())
    play("f1c4"); waitReply()
    play("c2c3")
    h.check(drill.state == "end" and panel():find("Line complete", 1, true), "line complete: " .. panel())
    h.check(view.buttons:getButtonById("next").enabled, "Next line enabled")

    -- 2. the next line keeps learning (new moves under today's cap)
    h.tapWidget(view.buttons:getButtonById("next"))
    h.settle()
    h.check(drill.state == "play", "next line started")

    -- 3. skip ahead: once the cap is reached, introduced moves are tested
    drill.introduced_today = drill.new_per_day
    view:nextLine()
    h.settle()
    h.check(drill:mode() == "test", "introduced moves are tested the same day: " .. tostring(drill:mode()))
    h.check(drill:expected().move.san == "e4", "first: e4")
    play("d2d4")
    h.check(panel():find("Not the move", 1, true), "wrong answer: " .. panel())
    play("e2e4"); waitReply()
    local key = drill.line.cards[1]
    h.check(drill.stored[key].reps == 0, "e4 failed: relearn today")
    h.shot("openings-test")
    -- ☰ → Hide move list (remembered), then shown again
    h.tapWidget(view.title_bar.left_button)
    h.settle()
    local function menuButton(text)
        for _, row in ipairs(view.menu_dialog.buttontable.buttons_layout) do
            for _, btn in ipairs(row) do if btn.text and btn.text:find(text, 1, true) then return btn end end
        end
    end
    h.tapWidget(menuButton("Hide move list"))
    h.settle()
    h.check(view.movelist == nil and require("pkprogress").readSetting("drill.movelist") == "0", "list hidden, remembered")
    h.tapWidget(view.title_bar.left_button)
    h.settle()
    h.tapWidget(menuButton("Show move list"))
    h.settle()
    h.check(view.movelist ~= nil, "shown again")

    view:onClose()
    h.settle()
    h.check(top() == list, "back to the list")
    -- 4 introduced (e4 Nf3 Bc4 c3; line 2 was skipped), all due again today; 6 new left today
    local after = menuItem(list, "repertoire")
    h.check(after and after.mandatory == "4 due · 6 new", "counts refreshed: " .. tostring(after and after.mandatory))

    progress = PkProgress.open(DataStorage:getSettingsDir() .. "/paperknight/progress.sqlite")
    local stored = progress:loadCards("repertoire.pgn")
    h.check(stored[key] and stored[key].reps == 0 and stored[key].move == "e2e4", "failure saved in progress.sqlite")
    progress:close()
    UIManager:close(list)
    h.settle()

    -- 4. a Black repertoire: flipped board, the opponent moves first; hint,
    -- relearning and the end-of-session summary; closing with a reply pending
    local tmp = DataStorage:getSettingsDir() .. "/pk-e2e-repertoires"
    lfs.mkdir(tmp)
    local f = assert(io.open(tmp .. "/black.pgn", "w"))
    f:write('[Event "ck"]\n[Orientation "black"]\n\n1. e4 c6 *\n')
    f:close()
    local blist = PkOpenings.show(tmp)
    h.settle()
    h.check(not menuItem(blist, "empty"), "no empty file yet")
    -- the list follows its folder: a file copied while it is open appears
    -- on the next repaint; a file that cannot be drilled is not parsed again
    -- Black's repertoire without a Black move: nothing to drill
    f = assert(io.open(tmp .. "/empty.pgn", "w"))
    f:write('[Event "e"]\n[Orientation "black"]\n\n1. e4 *\n')
    f:close()
    UIManager:setDirty(blist, "ui")
    h.settle()
    local empty = menuItem(blist, "empty")
    h.check(empty and empty.mandatory == "error", "new file listed, with its error: " .. tostring(empty and empty.mandatory))
    PkOpenings._clearMemory()
    h.check(not PkOpenings.needsParse(tmp .. "/empty.pgn"), "the error is cached: no parse after a restart")
    os.remove(tmp .. "/empty.pgn")
    UIManager:setDirty(blist, "ui")
    h.settle()
    h.check(not menuItem(blist, "empty"), "removed file leaves the list")
    h.tapWidget(menuItem(blist, "black"))
    h.wait(0.2)
    view = top()
    h.check(view.name == "paperknight_drill" and view.board.flipped, "Black's side shown")
    h.check(view.drill.state == "reply" and view.board.locked, "opponent to move first, board locked")
    view:onClose() -- with the opponent's move pending: must not fire later
    h.wait(1.5)
    h.check(top() == blist, "closed cleanly")

    h.tapWidget(menuItem(blist, "black"))
    view = top()
    view.reply_delay = 0.1
    drill = view.drill
    h.wait(1.5) -- default delay for the first reply
    h.check(drill.state == "play" and drill:mode() == "intro", "c6 introduced after 1. e4")
    play("c7c6")
    h.check(drill.state == "end", "line over")
    h.tapWidget(view.buttons:getButtonById("next"))
    h.settle()
    h.check(drill:mode() == "test", "c6 tested the same day")
    h.tapWidget(view.buttons:getButtonById("hint"))
    h.check(view.board.shapes.circles[1].square == "c7", "hint ring on c7")
    play("c7c6")
    h.tapWidget(view.buttons:getButtonById("next"))
    h.settle()
    h.check(drill:mode() == "test", "after a hint the move comes back")
    play("c7c6")
    h.tapWidget(view.buttons:getButtonById("next"))
    h.settle()
    h.check(drill.state == "done" and panel():find("All done for today", 1, true), "summary: " .. panel())
    h.check(panel():find("Reviewed: 2 · Mistakes: 1", 1, true), "session stats: " .. panel())
    h.check(#view.board.highlighted == 0 and next(view.board.highlighted) == nil, "no stale highlight")
    h.shot("openings-done")
    view:onClose()
    h.settle()
    h.check(menuItem(blist, "black").mandatory == "0 due · 0 new", "nothing left today")
    os.remove(tmp .. "/black.pgn")

    -- 5. a PGN without [Orientation] is drilled as White; the title-bar menu
    -- switches the chapter to Black (remembered), and back
    f = assert(io.open(tmp .. "/noside.pgn", "w"))
    f:write('[Event "x"]\n\n1. e4 c6 2. d4 d5 *\n')
    f:close()
    local function clearFlip()
        local p = PkProgress.open(DataStorage:getSettingsDir() .. "/paperknight/progress.sqlite")
        p:setSetting("rep_flip:noside.pgn#1", nil)
        p:close()
    end
    clearFlip()
    PkOpenings.refreshList()
    h.settle()
    h.tapWidget(menuItem(blist, "noside"))
    h.settle()
    view = top()
    h.check(not view.board.flipped and view.drill.line.student == "w", "default: White")
    h.tapWidget(view.title_bar.left_button)
    h.settle()
    local flip_btn
    for _, row in ipairs(view.menu_dialog.buttontable.buttons_layout) do
        for _, btn in ipairs(row) do if btn.text and btn.text:find("other side", 1, true) then flip_btn = btn end end
    end
    h.check(flip_btn, "flip action in the menu")
    h.tapWidget(flip_btn)
    h.settle()
    view = top()
    h.check(view.name == "paperknight_drill" and view.board.flipped, "reopened from Black's side")
    h.check(view.drill.line.student == "b", "Black's moves are drilled")
    view:onClose()
    h.settle()
    h.tapWidget(menuItem(blist, "noside"))
    h.settle()
    view = top()
    h.check(view.board.flipped, "the side is remembered")
    view:onClose()
    h.settle()
    clearFlip()
    local PkOpenings = require("pkopenings")
    h.check(PkOpenings.holdsRepertoire(), "the repertoire is kept while the list is open")
    UIManager:close(blist)
    h.settle()
    h.check(not PkOpenings.holdsRepertoire(), "released when the Openings list closes")
    os.remove(tmp .. "/noside.pgn")

    -- A quiet, paced drill (python-chess checked PGN): a right move gets a ✓
    -- and no text; a commented move waits for Continue; known moves that are
    -- not due are played for the user, and the line ends after the last
    -- move asked.
    local PkDrill = require("pkdrill")
    local PkDrillView = require("pkdrillview")
    local PkRepertoire = require("pkrepertoire")
    local PkSrs = require("pksrs")
    local PkStudy = require("pkstudy")
    local Chess = require("pkchess")
    local ChessBoard = require("pkboard")
    local text = '[Event "t"]\n[Orientation "white"]\n\n1. e4 { Best by test. } e5 2. Nf3 Nc6 3. Bc4 *\n'
    local today = PkSrs.today()
    local function drillWith(due) -- due: the line's cards due today (others known, not due)
        local game = Chess:new()
        local rep = PkRepertoire.fromStudy(PkStudy.fromText(text, "paced"), game)
        local cards = {}
        for i, key in ipairs(rep.lines[1].cards) do
            cards[key] = { move = rep.cards[key].uci, reps = 2, interval = 3, ease = 2.5, lapses = 0,
                           due = due[i] and today or today + 9, last = os.time() - 86400, introduced = today - 5 }
        end
        local d = PkDrill.new{ rep = rep, game = game, cards = cards }
        local v = PkDrillView:new{ drill = d, title = "Paced" }
        v.reply_delay = 0.1
        UIManager:show(v)
        h.settle()
        return v, d
    end
    local v, d = drillWith({ true, true, false })
    local function playOn(uci)
        local b = v.board
        for _, sq in ipairs({ uci:sub(1, 2), uci:sub(3, 4) }) do
            h.tapWidget(b.table:getButtonById(b.toId(sq:byte(1) - 97, tonumber(sq:sub(2, 2)) - 1)))
        end
    end
    h.check(d.state == "play" and d:mode() == "test" and v.board.turn_marker == "w", "e4 asked, your turn shown")
    playOn("e2e4")
    h.wait(0.5) -- longer than the reply delay
    h.check(v.waiting and d.cursor.node.san == "e4" and v.panel_text:find("Best by test", 1, true),
        "a commented move: the opponent waits, the comment stays: " .. v.panel_text)
    h.check(not v.panel_text:find("Correct", 1, true) and v.board.badge and v.board.badge.text == ChessBoard.TICK
        and v.board.badge.square == "e4", "a right move: ✓ on its piece, no text")
    local next_btn = v.buttons:getButtonById("next")
    h.check(next_btn.text == "Continue" and next_btn.enabled and v.board.turn_marker == nil, "Continue offered")
    h.shot("openings-continue")
    h.tapWidget(next_btn)
    h.settle()
    h.check(not v.waiting and d.cursor.node.san == "e5" and d:expected().move.san == "Nf3", "Continue: the reply")
    playOn("g1f3")
    h.check(d.state == "end", "Bc4 is known and not due: the line ends after Nf3")
    h.check(v.buttons:getButtonById("next").text == "Next line", "then Next line")
    v:onClose()
    h.settle()
    v, d = drillWith({ false, true, false })
    h.waitFor(function() return d.state == "play" end)
    h.check(d.cursor.node.san == "e5" and d:expected().move.san == "Nf3",
        "1. e4 known, not due: played for you, then asked Nf3")
    v:onClose()
    h.settle()
end
