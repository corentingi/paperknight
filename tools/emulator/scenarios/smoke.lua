-- Opens Paperknight, checks piece icons resolve to real files, plays 1. e4 by
-- tapping the board, and screenshots it.
local NOT_FOUND = "resources/icons/icon-not-found.svg"

return function(h)
    local pk = h.ui.paperknight
    h.check(pk, "paperknight plugin is not loaded")
    local view = pk:startGame()
    h.settle()
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

    local stop = h.recordRefreshes()
    h.tapWidget(board.table:getButtonById(board.toId(4, 1))) -- e2
    h.tapWidget(board.table:getButtonById(board.toId(4, 3))) -- e4
    local sent = stop()
    -- a move: the board's squares and the text below, without a flash
    for _, r in ipairs(sent) do
        h.check(r.mode == "[partial]", ("game move refresh: %s %d,%d %dx%d"):format(r.mode, r.x, r.y, r.w, r.h))
    end
    h.settle()
    local hist = view.game.history()
    h.check(#hist == 1 and hist[1] == "e4", "expected history {e4}, got " .. table.concat(hist, " "))
    h.check(iconFile(4, 3):sub(-6) == "wP.svg", "e4 shows a white pawn")
    -- empty squares don't paint their transparent icon (pkboard _showIcon)
    local function hidden(file, rank) return board.table:getButtonById(board.toId(file, rank)).label_widget.hide end
    h.check(hidden(4, 1) and hidden(4, 4) and not hidden(4, 3) and not hidden(4, 0),
        "empty squares hidden (e2, e5), pieces shown (e4, e1)")
    h.shot("smoke-e4")
    -- the settings open without an engine (none installed here): clocks only
    h.check(view.engine == nil, "no engine binary: none spawned")
    local settings = require("pksettingswidget"):new{
        timer = view.timer, game = view.game, parent = view, onApply = function() end,
    }
    settings:show()
    h.settle()
    h.check(settings.dialog, "settings dialog shown without an engine")
    require("ui/uimanager"):close(settings.dialog)
    h.settle()
    -- an illegal engine move pauses the game with a message (no endless wait)
    local UIM = require("ui/uimanager")
    view.running = true
    view:uciMove("a1a8")
    h.settle()
    local message = UIM._window_stack[#UIM._window_stack].widget
    h.check(not view.running and message.text and message.text:find("illegal move", 1, true),
        "illegal engine move reported: " .. tostring(message.text))
    UIM:close(message)
    h.settle()
    -- the settings are saved and come back with the next game
    view.timer.base.w, view.timer.increment.w = 300, 5
    view:_saveSettings()
    local view2 = pk:startGame()
    h.settle()
    h.check(view2.timer.base.w == 300 and view2.timer.increment.w == 5, "saved clock settings applied to a new game")
    view2.timer.base.w, view2.timer.increment.w = 30 * 60, 0
    view2:_saveSettings()
    require("ui/uimanager"):close(view2)
    h.settle()
    view = pk.game_view or view
    -- switching mode closes it (and its cleanup runs: clock, engine)
    PkNav.closeScreens(false)
    h.settle()
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

    -- promotion chooser: no virtual keyboard behind it; a tap picks the piece;
    -- closing refreshes the dialog, not the whole screen
    local PkPromotion = require("pkpromotion")
    local chosen
    local dialog = PkPromotion.show("w", function(letter) chosen = letter end)
    h.settle()
    h.check(dialog._input_widget.keyboard == nil, "no keyboard built for the promotion chooser")
    local function find(w, id)
        if type(w) ~= "table" then return nil end
        if w.id == id then return w end
        for _, c in ipairs(w) do local r = find(c, id); if r then return r end end
    end
    local queen = find(dialog, "promote_q")
    h.check(queen and queen.dimen, "queen button shown")
    local stop = h.recordRefreshes()
    h.tapWidget(queen)
    local sent = stop()
    h.check(chosen == "q", "queen chosen: " .. tostring(chosen))
    local S = require("device").screen
    for _, r in ipairs(sent) do
        h.check(r.w * r.h < S:getWidth() * S:getHeight(), ("closing: not a whole-screen refresh (%s %dx%d)"):format(r.mode, r.w, r.h))
    end
end
