-- Night mode inverts the whole screen: the board switches to its night
-- palette (dark greys) and swaps the piece sets, so that once inverted white
-- pieces still show white. Pixels are read as the panel shows them.
return function(h)
    local Screen = require("device").screen
    local UIManager = require("ui/uimanager")
    local pk = h.ui.paperknight

    local view = pk:startPuzzles()
    h.check(view, "puzzle view did not open (pack missing?)")
    view:loadPuzzle(view.pack:get("0042j"))
    h.wait(1)
    local board = view.board

    local function shown(x, y)
        local bb = Screen.bb
        -- software night mode: paints are stored inverted and getPixel
        -- undoes it; hardware night mode: the panel inverts the stored value
        local c = bb:getPixel(x, y)
        if bb:getInverse() == 1 or Screen.night_mode then c = c:invert() end
        return c:getColor8().a
    end
    local function rect(sq)
        return board.table:getButtonById(board.chessToId(sq)).dimen
    end
    -- corner pixel: background, away from the piece drawn in the middle
    local function background(sq)
        local r = rect(sq)
        return shown(r.x + 2, r.y + 2)
    end
    local function plain(light)
        for _, sq in ipairs({ "a1", "b1", "c1", "d1", "e1", "f1", "g1", "h1", "a8", "b8", "c8", "d8" }) do
            local is_light = (sq:byte(1) - 97 + tonumber(sq:sub(2))) % 2 == 0
            if is_light == light and not board.highlighted[sq] then return sq end
        end
    end
    local light_sq, dark_sq = plain(true), plain(false)
    h.check(light_sq and dark_sq, "found plain squares")

    local circle_sq = dark_sq
    local function ring()
        local r = rect(circle_sq)
        local inset = math.floor(board.button_size / 12)
        return shown(r.x + inset + 1, r.y + math.floor(r.h / 2))
    end
    board:setShapes({ circles = { { square = circle_sq } }, arrows = {} })
    UIManager:setDirty("all", "full")
    h.wait(1)

    local day = { light = background(light_sq), dark = background(dark_sq), ring = ring() }
    h.check(day.light == 0xFF and day.dark == 0xDD, ("day colours %x %x"):format(day.light, day.dark))
    local last_move = next(board.highlighted) -- the setup move's squares
    h.check(last_move and background(last_move) == 0xAA, ("day last move %x"):format(background(last_move)))
    h.check(day.ring == 0x44, ("day shape %x"):format(day.ring))
    -- a white piece's middle pixel: white whatever the mode
    local function pieceMiddle(sq)
        local r = rect(sq)
        return shown(r.x + math.floor(r.w / 2), r.y + math.floor(r.h * 0.5)) -- the body, between its lines
    end
    local white_piece = board.game.get("d1") and "d1" -- rook in 0042j
    h.check(white_piece and board.game.get("d1").color == "w", "white piece on d1")
    local PkIcons = require("pkicons")
    local function iconOn(sq)
        return board.table:getButtonById(board.chessToId(sq)).icon
    end
    h.check(iconOn(white_piece) == PkIcons.pieces.r.w, "day: white rook icon")
    -- the side-to-move marker: a white disc, stored swapped in night mode
    local function status() return view.status.text end
    h.check(status():find("○ White to move", 1, true), "day marker: " .. status())

    Screen:toggleNightMode()
    UIManager:setDirty("all", "full")
    h.wait(1)
    h.shot("night-board")
    local ok, err = pcall(function()
        h.check(background(light_sq) == 0x66, ("night light square shown %x"):format(background(light_sq)))
        h.check(background(dark_sq) == 0x55, ("night dark square shown %x"):format(background(dark_sq)))
        h.check(background(last_move) == 0xAA, ("night last move shown %x"):format(background(last_move)))
        h.check(ring() == 0xCC, ("night shape shown %x"):format(ring()))
        h.check(iconOn(white_piece) == PkIcons.pieces.r.b, "night: black rook icon, shown inverted")
        h.check(pieceMiddle(white_piece) == 0xFF, ("white piece shown white: %x"):format(pieceMiddle(white_piece)))
        h.check(status():find("● White to move", 1, true), "night marker swapped on toggle: " .. status())
        view:loadPuzzle(view.pack:get("0042j"))
        h.check(status():find("● White to move", 1, true), "night marker on a new text: " .. status())
        -- a single-square repaint (Button:refresh paints the frame directly)
        board:markSelected(light_sq); board:unmarkSelected(light_sq)
        h.wait(0.5)
        h.check(background(light_sq) == 0x66, "night square after refresh")
    end)
    Screen:toggleNightMode() -- leave the emulator home in day mode
    UIManager:setDirty("all", "full")
    if not ok then error(err, 0) end
    h.wait(1)
    h.check(background(light_sq) == 0xFF and background(dark_sq) == 0xDD, "day palette back")
    h.check(iconOn(white_piece) == PkIcons.pieces.r.w, "day piece set back")
    h.check(status():find("○ White to move", 1, true), "day marker back: " .. status())
    h.log("night mode keeps the board's day colours")
end
