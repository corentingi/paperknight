-- The board's settings (pksettings.lua, pkprefs.lua): legal moves shown on
-- the selected piece's squares (live, from the next selection), and the
-- coordinates off (larger squares, from the next board).
local UIManager = require("ui/uimanager")

return function(h)
    local PkNav = require("pknav")
    local function top() return UIManager._window_stack[#UIManager._window_stack].widget end
    local function menuItem(menu, text)
        for _, w in ipairs(menu.item_group) do
            if w.text and w.text:find(text, 1, true) then return w end
        end
    end
    local function count(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end

    -- 1. The defaults: coordinates, no legal moves
    local view = PkNav.open("analysis")
    h.settle()
    local board = view.board
    local function sq(square) return board.table:getButtonById(board.chessToId(square)) end
    h.check(board.coordinates and board._label_w, "coordinates by default")
    local size_with = board.button_size
    h.tapWidget(sq("e2"))
    h.check(board.selected_mark == "e2" and count(board.targets) == 0, "no legal moves shown by default")
    h.tapWidget(sq("e2"))
    view:onClose()
    h.settle()

    -- 2. The settings screen: both switched
    PkNav.showSettings()
    h.settle()
    local settings = top()
    local legal = menuItem(settings, "Show legal moves")
    h.check(legal and legal.mandatory == "off", "Show legal moves: off")
    h.tapWidget(legal)
    h.settle()
    settings = top()
    h.check(menuItem(settings, "Show legal moves").mandatory == "on", "Show legal moves: on")
    h.tapWidget(menuItem(settings, "Board coordinates"))
    h.settle()
    settings = top()
    h.check(menuItem(settings, "Board coordinates").mandatory == "off", "Board coordinates: off")
    h.check(require("pkprogress").readSetting("pref.legal_moves") == "1", "saved")
    settings:onClose()
    h.settle()

    -- 3. The next board: no coordinates (larger squares), dots on the moves
    view = PkNav.open("analysis")
    h.settle()
    board = view.board
    h.check(not board.coordinates and not board._label_w, "no coordinates")
    h.check(board.button_size > size_with, "larger squares: " .. board.button_size .. " > " .. size_with)
    h.tapWidget(sq("e2"))
    h.check(board.targets.e3 == "move" and board.targets.e4 == "move" and count(board.targets) == 2,
        "e2: e3 and e4 shown")
    h.tapWidget(sq("g1"))
    h.check(board.selected_mark == "g1" and board.targets.f3 and board.targets.h3 and not board.targets.e4,
        "another piece: its moves instead")
    h.shot("board-legal-moves")
    h.tapWidget(sq("f3"))
    h.check(board.selected_mark == nil and count(board.targets) == 0, "moved: the dots gone")
    -- a capture: a ring (1. Nf3 d5 2. e4: the d5 pawn takes e4 or goes to d4)
    h.tapWidget(sq("d7")); h.tapWidget(sq("d5"))
    h.tapWidget(sq("e2")); h.tapWidget(sq("e4"))
    h.tapWidget(sq("d5"))
    h.check(board.targets.e4 == "capture" and board.targets.d4 == "move", "d5: takes e4, or d4")
    h.tapWidget(sq("d5"))
    h.check(count(board.targets) == 0, "unselected: no dots")
    view:onClose()
    h.settle()
    PkNav.home()
    h.settle()
end
