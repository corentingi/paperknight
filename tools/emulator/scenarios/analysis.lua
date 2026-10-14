-- Analysis board (pkanalysis.lua): free moves for both sides, stepping
-- through the line, a new move replacing the rest, a position from FEN,
-- flip, and the engine's evaluation (a fake UCI engine here), stopped on close.
return function(h)
    local UIManager = require("ui/uimanager")
    local PkNav = require("pknav")
    local PkAnalysis = require("pkanalysis")

    -- 1. From the home screen: listed with Play (two players: no engine here)
    PkNav.home()
    h.wait(1)
    local home = PkNav.homeShown()
    local labels = {}
    for _, item in ipairs(home.item_table) do labels[#labels + 1] = item.text end
    local joined = table.concat(labels, "|")
    h.check(joined:find("Analysis board", 1, true) and joined:find("Play (two players)", 1, true),
        "home lists the analysis board and Play: " .. joined)
    local view = PkNav.open("analysis")
    h.wait(1)
    h.check(view and view.name == "paperknight_analysis", "analysis board opened")
    h.check(view.engine == nil and view.panel_text:find("Install Stockfish", 1, true),
        "no engine installed: said in the panel: " .. view.panel_text)
    view:onClose()
    h.wait(0.5)

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
    tapSquare("e2"); tapSquare("e4")
    h.check(view.pos == 1 and view.panel_text:find("1. [e4]", 1, true), "move played: " .. view.panel_text)
    h.check(view.panel_text:find("Black to move", 1, true), "side to move shown")
    h.wait(1.5) -- the engine answers; the last line is shown when the search ends
    h.check(view.panel_text:find("Engine: #-3 (depth 6)", 1, true), "evaluation from White's side: " .. view.panel_text)
    h.check(view.panel_text:find("1… e5 2. Nf3 Nc6", 1, true), "engine line in SAN: " .. view.panel_text)

    -- 3. Both sides move; stepping back and forth
    tapSquare("e7"); tapSquare("e5")
    h.check(view.pos == 2 and view.panel_text:find("1. e4 [e5]", 1, true), "black move: " .. view.panel_text)
    h.tapWidget(view.buttons:getButtonById("back"))
    h.check(view.pos == 1 and iconAt("e5"):find("empty%.svg$"), "back: e5 empty again")
    h.check(view.panel_text:find("1. [e4] e5", 1, true), "the line stays: " .. view.panel_text)
    h.swipe(view.dimen.w / 2, view.dimen.h / 2, "west")
    h.check(view.pos == 2 and iconAt("e5"):find("bP%.svg$"), "swipe forward: e5 again")
    h.tapWidget(view.buttons:getButtonById("start"))
    h.check(view.pos == 0 and not view.buttons:getButtonById("back").enabled, "start: nothing to go back to")
    tapSquare("d2"); tapSquare("d4") -- another move: replaces the line
    h.check(#view.line == 1 and view.panel_text:find("1. [d4]", 1, true), "line replaced: " .. view.panel_text)
    h.wait(1.5)

    -- 4. Position from FEN, flip
    h.check(not view:setPosition("not a fen"), "invalid FEN refused")
    local fen = "6k1/5ppp/8/8/8/8/5PPP/3R2K1 w - - 0 1" -- back-rank mate in one (python-chess checked)
    h.check(view:setPosition(fen) and #view.line == 0 and view.game.fen() == fen, "position set from FEN")
    h.wait(0.5) -- the rebuilt board gets its positions when painted
    h.check(iconAt("g1"):find("wK%.svg$") and iconAt("d1"):find("wR%.svg$"), "the new position is drawn: "
        .. iconAt("g1"))
    tapSquare("d1"); tapSquare("d8")
    h.check(view.game.in_checkmate() and view.panel_text:find("Checkmate", 1, true), "mate shown: " .. view.panel_text)
    view:flip()
    h.wait(0.5)
    h.check(view.board.flipped and view.pos == 1, "flipped, line kept")
    h.check(iconAt("d8"):find("wR%.svg$") and iconAt("g8"):find("bK%.svg$"), "the flipped board shows the pieces")
    h.shot("analysis")

    -- 5. Closing stops the engine process
    local pid = view.engine.pid
    view:onClose()
    h.wait(1.5)
    local ffi = require("ffi")
    pcall(ffi.cdef, "int kill(int, int);")
    h.check(ffi.C.kill(pid, 0) ~= 0, "engine stopped and reaped on close")
    PkNav.closeScreens(true)
    h.wait(0.3)
    UIManager:nextTick(function() end)
end
