-- Square names and ids of the board (pkboard.lua re-exports them as
-- Board.toId, Board.chessToId, Board.idToPosition): pure functions, with a
-- spec. An id is file * 8 + rank (0-based): the next rank is +1, the next
-- file +8.
local SIZE = 8

local PkSquares = {}

--- The id of the square at 0-based `file` (a = 0) and `rank` (1 = 0).
function PkSquares.toId(file, rank)
    return file * SIZE + rank
end

--- The id of square `position` ("e4"), nil if it is not a square.
function PkSquares.chessToId(position)
    if type(position) == "string" and #position == 2 then
        local file_char, rank_char = position:sub(1, 1), position:sub(2, 2)
        if "a" <= file_char and file_char <= "h" and "1" <= rank_char and rank_char <= "8" then
            return PkSquares.toId(file_char:byte() - ("a"):byte(), tonumber(rank_char) - 1)
        end
    end
    return nil
end

--- The name ("e4") of square `id`, nil if it is not an id.
function PkSquares.idToPosition(id)
    if type(id) == "number" and id >= 0 and id < SIZE * SIZE and id % 1 == 0 then
        return string.char(math.floor(id / SIZE) + ("a"):byte()) .. tostring(id % SIZE + 1)
    end
    return nil
end

--- Whether square `position` is a light one (h1 is light, a1 dark); nil
-- if it is not a square.
function PkSquares.isLight(position)
    local id = PkSquares.chessToId(position)
    if not id then return nil end
    return (math.floor(id / SIZE) + id % SIZE) % 2 == 1
end

return PkSquares
