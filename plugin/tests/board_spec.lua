-- Square names and ids of the board (pksquares.lua, re-exported by
-- pkboard.lua): the en passant bug of 2026-10-14 mixed up files and ranks
-- there. The palettes are checked on screen (the nightmode scenario).
local PkSquares = require("pksquares")

return {
    { "square names and ids: one for one, file major", function(t)
        local seen = {}
        for file = 0, 7 do
            for rank = 0, 7 do
                local id = PkSquares.toId(file, rank)
                t.ok(not seen[id], "unique id " .. id); seen[id] = true
                local name = PkSquares.idToPosition(id)
                t.eq(name, string.char(97 + file) .. (rank + 1), "name of " .. id)
                t.eq(PkSquares.chessToId(name), id, "back to the id: " .. name)
            end
        end
        t.eq(PkSquares.chessToId("a1"), 0); t.eq(PkSquares.chessToId("a2"), 1, "the next rank: +1")
        t.eq(PkSquares.chessToId("b1"), 8, "the next file: +8 (en passant takes the pawn beside: ±8)")
        t.eq(PkSquares.chessToId("h8"), 63)
    end },
    { "what is not a square is refused", function(t)
        for _, bad in ipairs({ "i1", "a9", "a0", "A1", "e", "e44", "", 12 }) do
            t.eq(PkSquares.chessToId(bad), nil, "chessToId " .. tostring(bad))
        end
        for _, bad in ipairs({ -1, 64, "e4", 1.5 }) do
            t.eq(PkSquares.idToPosition(bad), nil, "idToPosition " .. tostring(bad))
        end
        t.eq(PkSquares.isLight("z9"), nil)
    end },
    { "light and dark squares", function(t)
        t.eq(PkSquares.isLight("a1"), false, "a1 dark"); t.eq(PkSquares.isLight("h1"), true, "h1 light")
        t.eq(PkSquares.isLight("a8"), true); t.eq(PkSquares.isLight("h8"), false)
        t.eq(PkSquares.isLight("e4"), true); t.eq(PkSquares.isLight("d4"), false)
        local light = 0
        for file = 0, 7 do
            for rank = 0, 7 do
                if PkSquares.isLight(PkSquares.idToPosition(PkSquares.toId(file, rank))) then light = light + 1 end
            end
        end
        t.eq(light, 32, "half the board")
    end },
}
