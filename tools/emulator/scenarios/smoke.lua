-- Opens Paperknight, checks piece icons resolve to real files, plays 1. e4 by
-- tapping the board, and screenshots it.
local NOT_FOUND = "resources/icons/icon-not-found.svg"

return function(h)
    local pk = h.ui.paperknight
    h.check(pk, "paperknight plugin is not loaded")
    local view = pk:startGame()
    h.wait(1)
    h.shot("smoke-start")
    -- the game is its own screen, seen by the navigation (pknav.lua)
    local PkNav = require("pknav")
    h.check(view.name == "paperknight_game" and pk.game_view == view, "game screen widget")
    h.check(PkNav.screens()[1] == view, "PkNav sees the game screen")

    local board = view.board
    local function iconFile(file, rank)
        return board.table:getButtonById(board.toId(file, rank)).label_widget.file
    end
    for _, sq in ipairs({ { 4, 0, "wK.svg" }, { 3, 7, "bQ.svg" }, { 4, 4, "empty.svg" } }) do
        local f = iconFile(sq[1], sq[2])
        h.check(f and f ~= NOT_FOUND and f:sub(-#sq[3]) == sq[3], "icon file for " .. sq[3] .. ": " .. tostring(f))
        h.check(f:sub(1, 1) == "/" and io.open(f) ~= nil, "icon path must be absolute and exist: " .. f)
    end

    h.tapWidget(board.table:getButtonById(board.toId(4, 1))) -- e2
    h.tapWidget(board.table:getButtonById(board.toId(4, 3))) -- e4
    h.wait(1)
    local hist = view.game.history()
    h.check(#hist == 1 and hist[1] == "e4", "expected history {e4}, got " .. table.concat(hist, " "))
    h.check(iconFile(4, 3):sub(-6) == "wP.svg", "e4 shows a white pawn")
    h.shot("smoke-e4")
    -- the settings open without an engine (none installed here): clocks only
    h.check(view.engine == nil, "no engine binary: none spawned")
    local settings = require("pksettingswidget"):new{
        timer = view.timer, game = view.game, parent = view, onApply = function() end,
    }
    settings:show()
    h.wait(0.5)
    h.check(settings.dialog, "settings dialog shown without an engine")
    require("ui/uimanager"):close(settings.dialog)
    h.wait(0.3)
    -- switching mode closes it (and its cleanup runs: clock, engine)
    PkNav.closeScreens(false)
    h.wait(0.5)
    h.check(pk.game_view == nil and PkNav.screens()[1] ~= view, "closed by PkNav")

    -- the engine process is stopped for good: quit sent, pipes closed, child
    -- reaped (a fake UCI engine: answers uciok, exits on quit)
    local script = os.getenv("HOME") .. "/fake-uci.sh"
    local f = assert(io.open(script, "w"))
    f:write('#!/bin/sh\nwhile read l; do case "$l" in uci) echo uciok;; quit) exit 0;; esac; done\n')
    f:close()
    os.execute("chmod +x '" .. script .. "'")
    local Uci = require("pkuci")
    local engine = Uci.UCIEngine.spawn(script, { script })
    h.check(engine and engine.pid and engine.pid > 0, "fake engine spawned")
    engine:uci()
    h.wait(1.5)
    h.check(engine.state.uciok, "fake engine answered uciok")
    local ffi = require("ffi")
    pcall(ffi.cdef, "int kill(int, int);")
    engine:stop()
    h.wait(1.5)
    h.check(ffi.C.kill(engine.pid, 0) ~= 0, "engine process gone and reaped (no zombie)")
    engine:stop() -- twice is harmless
end
