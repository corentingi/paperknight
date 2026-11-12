-- The real Stockfish, when there is one for this computer
-- (PAPERKNIGHT_HOST_STOCKFISH, set by `make e2e` from STOCKFISH when the
-- binary is there; skipped otherwise, as in CI): the UCI handshake, a
-- limited strength, a legal best move, the analysis board's evaluation,
-- and no process left once stopped. The other scenarios use fake engines.
local UIManager = require("ui/uimanager")

return function(h)
    local path = os.getenv("PAPERKNIGHT_HOST_STOCKFISH")
    local lfs = require("libs/libkoreader-lfs")
    if not path or lfs.attributes(path, "mode") ~= "file" then
        h.log("no Stockfish for this computer: skipped")
        return
    end
    -- the process is there, running or a zombie (exited but never reaped:
    -- what the engine left before 2026-10-14)
    local function alive(pid)
        return lfs.attributes("/proc/" .. pid, "mode") == "directory"
    end

    -- 1. The engine itself: handshake, options, a search.
    local engine = require("pkuci").UCIEngine.spawn(path, { path })
    h.check(engine, "Stockfish started")
    local best, ready, uciok
    engine:on("uciok", function() uciok = true end)
    engine:on("readyok", function() ready = true end)
    engine:on("bestmove", function(move) best = move end)
    engine:uci()
    h.check(h.waitFor(function() return uciok end, 10), "uciok")
    h.check(engine.state.id_name and engine.state.id_name:find("Stockfish", 1, true), "named: " .. tostring(engine.state.id_name))
    local elo = engine.state.options.UCI_Elo
    h.check(elo and tonumber(elo.min) and tonumber(elo.max), "UCI_Elo advertised with its bounds")
    h.check(engine.state.options.UCI_LimitStrength, "UCI_LimitStrength advertised (Play's strength needs it)")
    engine:setOption("UCI_LimitStrength", "true")
    engine:setOption("UCI_Elo", tostring(math.max(1350, tonumber(elo.min))))
    engine:isready()
    h.check(h.waitFor(function() return ready end, 10), "readyok")
    engine:position{ fen = "startpos", moves = "e2e4 e7e5" }
    engine:go{ movetime = 300 }
    h.check(h.waitFor(function() return best end, 10), "a best move")
    local chess = require("pkchess"):new()
    chess.move({ from = "e2", to = "e4" }); chess.move({ from = "e7", to = "e5" })
    h.check(chess.move({ from = best:sub(1, 2), to = best:sub(3, 4), promotion = best:sub(5, 5) ~= "" and best:sub(5, 5) or nil }),
        "the best move is legal: " .. best)
    local pid = engine.pid
    engine:stop()
    h.check(h.waitFor(function() return not alive(pid) end, 5), "stopped: no process left")

    -- 2. The analysis board's evaluation, from the real engine.
    local PkAnalysis = require("pkanalysis")
    local view = PkAnalysis.show{ engine_path = path }
    view.movetime = 500
    h.settle()
    view:toggleEngine()
    h.check(h.waitFor(function() return view.engine_ready end, 10), "the board's engine is ready")
    local b = view.board
    h.tapWidget(b.table:getButtonById(b.chessToId("e2"))); h.tapWidget(b.table:getButtonById(b.chessToId("e4")))
    h.check(h.waitFor(function() return (view.panel_text or ""):find("Engine: .*%(depth %d+%)") end, 10),
        "an evaluation shown: " .. tostring(view.panel_text))
    h.check(view.panel_text:find("%(depth %d+%)") and view.panel_text:find("1… ", 1, true),
        "with its depth and its line in SAN, Black to move: " .. view.panel_text)
    pid = view.engine.pid
    view:onClose()
    h.settle()
    h.check(h.waitFor(function() return not alive(pid) end, 5), "closed: the engine stopped")
    while #UIManager._window_stack > 0 and UIManager._window_stack[#UIManager._window_stack].widget.name ~= "paperknight_home" do
        UIManager:close(UIManager._window_stack[#UIManager._window_stack].widget)
    end
end
