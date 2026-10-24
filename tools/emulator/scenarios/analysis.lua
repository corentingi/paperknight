-- Analysis board (pkanalysis.lua): free moves for both sides, stepping
-- through the line, a new move replacing the rest, a position from FEN,
-- flip, and the engine's evaluation (a fake UCI engine here), stopped on close.
return function(h)
    local UIManager = require("ui/uimanager")
    local PkNav = require("pknav")
    local PkAnalysis = require("pkanalysis")

    -- 1. From the home screen: listed with Play
    PkNav.home()
    h.settle()
    local home = PkNav.homeShown()
    local labels = {}
    for _, item in ipairs(home.item_table) do labels[#labels + 1] = item.text end
    local joined = table.concat(labels, "|")
    h.check(joined:find("Analysis board", 1, true) and joined:find("|Play", 1, true),
        "home lists the analysis board and Play: " .. joined)
    local view = PkNav.open("analysis")
    h.settle()
    h.check(view and view.name == "paperknight_analysis", "analysis board opened")
    -- no Stockfish: the engine button is greyed; a tap says how to install it
    local engine_btn = view.buttons:getButtonById("engine")
    h.check(view.engine == nil and not engine_btn.enabled, "no engine installed: button greyed")
    h.tapWidget(engine_btn)
    h.settle()
    local msg = UIManager._window_stack[#UIManager._window_stack].widget
    h.check(msg.text and msg.text:find("Stockfish is not installed", 1, true), "tap: how to install it")
    UIManager:close(msg)
    h.settle()
    view:onClose()
    h.settle()

    -- 2. With an engine (fake: two info lines and a bestmove per search)
    local script = os.getenv("HOME") .. "/fake-analysis.sh"
    local f = assert(io.open(script, "w"))
    f:write([[#!/bin/sh
while read l; do case "$l" in
  uci) echo "id name FakeFish"; echo uciok;;
  isready) echo readyok;;
  go*) echo "info depth 5 score cp 35 pv e7e5 g1f3"; echo "info depth 6 score mate 3 pv e7e5 g1f3 b8c6"; echo "bestmove e7e5";;
  quit) exit 0;;
esac; done
]])
    f:close()
    os.execute("chmod +x '" .. script .. "'")
    view = PkAnalysis.show{ engine_path = script }
    h.settle()
    -- off at first: no process until the knight button turns it on
    local knight = view.buttons:getButtonById("engine")
    h.check(view.engine == nil and not view.engine_on and knight.icon:find("wN%.svg$"), "engine off by default")
    local stop = h.recordRefreshes()
    h.tapWidget(knight)
    local sent = stop()
    h.check(view.engine_on and knight.icon:find("bN%.svg$"), "knight button: engine on, black knight")
    for _, r in ipairs(sent) do
        h.check(r.mode == "[partial]", ("engine button refresh: %s %dx%d"):format(r.mode, r.w, r.h))
    end
    h.wait(1.5)
    h.check(view.engine and view.engine_ready, "engine started")
    local function tapSquare(sq)
        local b = view.board
        h.tapWidget(b.table:getButtonById(b.toId(sq:byte(1) - 97, tonumber(sq:sub(2, 2)) - 1)))
    end
    local function iconAt(sq)
        local b = view.board
        return b.table:getButtonById(b.toId(sq:byte(1) - 97, tonumber(sq:sub(2, 2)) - 1)).icon
    end
    -- the move list beside the board: its moves, @ the current one
    local function listed()
        return table.concat(view.movelist.moves, " ") .. "@" .. view.movelist.current
    end
    tapSquare("e2"); tapSquare("e4")
    h.check(view.pos == 1 and listed() == "e4@1", "move played: " .. listed())
    h.check(view.board.turn_marker == "b" and not view.panel_text:find("to move", 1, true), "side to move: the corner marker, not a line")
    h.wait(1.5) -- the engine answers; the last line is shown when the search ends
    h.check(view.panel_text:find("Engine: #-3 (depth 6)", 1, true), "evaluation from White's side: " .. view.panel_text)
    h.check(view.panel_text:find("1… e5 2. Nf3 Nc6", 1, true), "engine line in SAN: " .. view.panel_text)
    h.tapWidget(knight)
    h.check(not view.engine_on and knight.icon:find("wN%.svg$") and not view.panel_text:find("Engine", 1, true),
        "off again: no evaluation shown")
    local pid_kept = view.engine.pid
    h.tapWidget(knight)
    h.check(view.engine_on and view.engine.pid == pid_kept, "on again: the same process (kept while the board is open)")

    -- 3. Both sides move; stepping back and forth
    tapSquare("e7"); tapSquare("e5")
    h.check(view.pos == 2 and listed() == "e4 e5@2", "black move: " .. listed())
    h.check(view.panel_text:find("C20 King's Pawn Game", 1, true), "opening named: " .. view.panel_text)
    h.tapWidget(view.buttons:getButtonById("back"))
    h.check(view.pos == 1 and iconAt("e5"):find("empty%.svg$"), "back: e5 empty again")
    h.check(listed() == "e4 e5@1", "the line stays: " .. listed())
    h.swipe(view.dimen.w / 2, view.dimen.h / 2, "west")
    h.check(view.pos == 2 and iconAt("e5"):find("bP%.svg$"), "swipe forward: e5 again")
    h.tapWidget(view.buttons:getButtonById("start"))
    h.check(view.pos == 0 and not view.buttons:getButtonById("back").enabled, "start: nothing to go back to")
    tapSquare("d2"); tapSquare("d4") -- another move: replaces the line
    h.check(#view.line == 1 and listed() == "d4@1", "line replaced: " .. listed())
    h.wait(1.5)

    -- 4. Position from FEN, flip
    h.check(not view:setPosition("not a fen"), "invalid FEN refused")
    local fen = "6k1/5ppp/8/8/8/8/5PPP/3R2K1 w - - 0 1" -- back-rank mate in one (python-chess checked)
    h.check(view:setPosition(fen) and #view.line == 0 and view.game.fen() == fen, "position set from FEN")
    h.settle() -- the rebuilt board gets its positions when painted
    h.check(iconAt("g1"):find("wK%.svg$") and iconAt("d1"):find("wR%.svg$"), "the new position is drawn: "
        .. iconAt("g1"))
    tapSquare("d1"); tapSquare("d8")
    h.check(view.game.in_checkmate() and view.panel_text:find("Checkmate", 1, true), "mate shown: " .. view.panel_text)
    h.check(view.board.mate_square == "g8", "# on the mated king: " .. tostring(view.board.mate_square))
    view:step(-1)
    h.check(view.board.mate_square == nil, "stepping back takes the # away")
    view:step(1)
    h.check(view.board.mate_square == "g8", "and forward brings it back")
    -- the arrows' new state reaches the screen: under the full-height list,
    -- a step refreshes the panel, not the bar (they stayed grey on the e-ink)
    h.settle()
    h.check(view.movelist and view.list_layout == "full", "the list down the right side")
    local function refreshed(sent, d)
        for _, r in ipairs(sent) do
            if r.x <= d.x and r.y <= d.y and r.x + r.w >= d.x + d.w and r.y + r.h >= d.y + d.h then return true end
        end
        return false
    end
    for _, case in ipairs({ { -1, true }, { 1, false } }) do
        local d = view.buttons:getButtonById("forward")[1].dimen:copy()
        stop = h.recordRefreshes()
        view:step(case[1])
        h.settle()
        sent = stop()
        local forward = view.buttons:getButtonById("forward")
        h.check(forward.enabled == case[2], "forward enabled: " .. tostring(forward.enabled))
        h.check(refreshed(sent, d), "forward " .. (case[2] and "enabled" or "greyed") .. " on screen too")
    end
    view:flip()
    h.settle()
    h.check(view.board.flipped and view.pos == 1, "flipped, line kept")
    h.check(iconAt("d8"):find("wR%.svg$") and iconAt("g8"):find("bK%.svg$"), "the flipped board shows the pieces")
    h.shot("analysis")
    -- ☰ → the position on Lichess's analysis board: a QR code, from the side
    -- shown, the FEN written under it (FEN checked with python-chess)
    h.tapWidget(view.title_bar.left_button)
    h.settle()
    h.tapWidget(h.findButton(view.menu_dialog, "Position on Lichess…"))
    h.settle()
    local qr = UIManager._window_stack[#UIManager._window_stack].widget
    h.check(qr.text == "https://lichess.org/analysis/3R2k1/5ppp/8/8/8/8/5PPP/6K1_b_-_-_1_1?color=black",
        "QR code of the Lichess analysis: " .. tostring(qr.text))
    h.check(qr.caption == "3R2k1/5ppp/8/8/8/8/5PPP/6K1 b - - 1 1", "the FEN under it: " .. tostring(qr.caption))
    h.shot("analysis-lichess")
    UIManager:close(qr)
    h.settle()
    -- saved as a study (☰ → Save line as a study…): a PGN the studies read
    -- back, from the position set and from Black's side; a taken name gets " (2)"
    local tmp = os.getenv("HOME") .. "/analyses"
    local path = view:saveLine("Back rank: mate", tmp)
    h.check(path and path:find("/Back rank%- mate%.pgn$"), "saved: " .. tostring(path))
    local saved = require("pkstudy").open(path)
    local ch = saved and saved.chapters[1]
    h.check(ch and #saved.chapters == 1 and ch.title:find("Back rank: mate", 1, true), "read back as a study")
    local tree = saved:tree(1)
    h.check(tree.fen == fen and tree.children[1] and tree.children[1].san == "Rd8#", "from the FEN, the line kept")
    h.check(saved:cursor(1, require("pkchess"):new()) and ch.tags.Orientation == "black", "oriented as shown")
    local again = view:saveLine("Back rank: mate", tmp)
    h.check(again and again:find("%(2%)%.pgn$"), "a taken name: " .. tostring(again))
    view:showMenu()
    h.settle()
    local save_btn
    for _, row in ipairs(view.menu_dialog.buttontable.buttons_layout) do
        for _, btn in ipairs(row) do if btn.text == "Save line as a study…" then save_btn = btn end end
    end
    h.check(save_btn and save_btn.enabled, "menu: save the line")
    UIManager:close(view.menu_dialog)
    h.settle()

    -- 4b. Long moves are not cut in the list ("Nbxd2", not "Nbx…"): the
    -- Italian Game of the study fixture (python-chess checked)
    view:setPosition("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")
    h.settle()
    for _, san in ipairs({ "e4", "e5", "Nf3", "Nc6", "Bc4", "Bc5", "c3", "Nf6", "d4", "exd4",
                           "cxd4", "Bb4+", "Bd2", "Bxd2+", "Nbxd2", "d5" }) do
        local m = view.game.move(san)
        view.board:updateBoard()
        view:onBoardMove(m)
    end
    h.settle()
    local cut = {}
    local function walk(w)
        if type(w) ~= "table" then return end
        if w._is_truncated then cut[#cut + 1] = w.text end
        for _, c in ipairs(w) do walk(c) end
    end
    walk(view.movelist.scroll[1])
    h.check(#cut == 0, "no move cut in the list: " .. table.concat(cut, ", "))

    -- 5. The move list: a line longer than the list scrolls (KOReader's
    -- scrolling, kept on the current move); a tap on a move goes there; the
    -- list can be hidden (the line is then in the panel)
    view:setPosition("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")
    h.settle()
    local sans = { "e4", "e5", "Nf3", "Nc6" } -- then knights back and forth (python-chess checked)
    for _ = 1, 20 do
        for _, san in ipairs({ "Ng1", "Nb8", "Nf3", "Nc6" }) do sans[#sans + 1] = san end
    end
    for _, san in ipairs(sans) do
        local m = view.game.move(san)
        view.board:updateBoard()
        view:onBoardMove(m)
    end
    h.settle()
    local ml = view.movelist
    local offset = function() return ml.scroll:getScrolledOffset().y end
    h.check(ml.scroll._is_scrollable and offset() > 0, "a long line scrolls, shown at its end: " .. offset())
    h.check(ml.scroll.dimen.h % ml.row_h == 0, "whole rows only")
    local before = offset()
    h.swipe(ml.dimen.x + math.floor(ml.dimen.w / 2), ml.dimen.y + 100, "south")
    h.check(offset() < before and offset() % ml.row_h == 0, "swipe down: back a page, on a row: " .. offset())
    h.check(view.pos == #sans, "a vertical swipe on the list does not step")
    local stop = h.recordRefreshes()
    -- the first row shown, Black's move
    local row = math.floor(offset() / ml.row_h) + 1
    h.tap(ml.dimen.x + ml.num_w + ml.move_w + 10, ml.dimen.y + math.floor(ml.row_h / 2))
    local sent = stop()
    h.check(view.pos == 2 * row and view.game.history()[view.pos] == sans[view.pos],
        "tap on a move: its position (" .. view.pos .. ", row " .. row .. ")")
    for _, r in ipairs(sent) do
        h.check(r.mode == "[partial]", ("list tap refresh: %s %dx%d"):format(r.mode, r.w, r.h))
    end
    h.shot("analysis-list")
    h.tapWidget(view.buttons:getButtonById("list"))
    h.settle()
    h.check(view.movelist == nil and view.panel_text:find("[" .. sans[view.pos] .. "]", 1, true),
        "list hidden: the line in the panel")
    h.tapWidget(view.buttons:getButtonById("list"))
    h.settle()
    h.check(view.movelist and listed():find("@" .. view.pos .. "$"), "shown again on the current move")

    -- 6. Closing stops the engine process
    local pid = view.engine.pid
    view:onClose()
    h.wait(1.5)
    local ffi = require("ffi")
    pcall(ffi.cdef, "int kill(int, int);")
    h.check(ffi.C.kill(pid, 0) ~= 0, "engine stopped and reaped on close")

    -- 7. The engine and the move list come back as they were left
    view = PkAnalysis.show{ engine_path = script }
    h.settle()
    h.check(view.engine_on and view.engine and view.movelist, "reopened: engine on (left on), list shown")
    h.tapWidget(view.buttons:getButtonById("engine")) -- off
    h.tapWidget(view.buttons:getButtonById("list")) -- hidden
    h.settle()
    view:onClose()
    h.settle()
    view = PkAnalysis.show{ engine_path = script }
    h.settle()
    h.check(not view.engine_on and view.engine == nil and view.movelist == nil,
        "reopened: engine off and list hidden, as left (no engine process)")
    h.tapWidget(view.buttons:getButtonById("list")) -- shown again for the next runs
    h.settle()
    view:onClose()
    h.settle()
    PkNav.closeScreens(true)
    h.settle()
    UIManager:nextTick(function() end)
end
