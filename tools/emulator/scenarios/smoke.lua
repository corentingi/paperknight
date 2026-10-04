-- Opens Paperknight, checks piece icons resolve to real files, plays 1. e4 by
-- tapping the board, and screenshots it.
local NOT_FOUND = "resources/icons/icon-not-found.svg"

return function(h)
    local pk = h.ui.paperknight
    h.check(pk, "paperknight plugin is not loaded")
    pk:startGame()
    h.wait(1)
    h.shot("smoke-start")

    local board = pk.board
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
    local hist = pk.game.history()
    h.check(#hist == 1 and hist[1] == "e4", "expected history {e4}, got " .. table.concat(hist, " "))
    h.check(iconFile(4, 3):sub(-6) == "wP.svg", "e4 shows a white pawn")
    h.shot("smoke-e4")
end
