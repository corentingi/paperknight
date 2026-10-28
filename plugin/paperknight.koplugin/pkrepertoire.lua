-- Repertoire model (ADR-0012): a study PGN read as the user's opening
-- repertoire. Pure Lua over PkStudy, no UI:
--   local rep = PkRepertoire.fromStudy(study, game)
--   rep.lines   -- { { chapter = i, student = "w"|"b", nodes = {...}, cards = {key, ...} } }
--   rep.cards   -- key (normalized FEN) -> { key, fen, uci, san, chapter, node }
--   rep.order   -- card keys in tree order; rep.conflicts = number of cut lines
-- At the user's turn only the main child is followed (other children are
-- known mistakes); at the opponent's turn every child is a branch to learn.
-- A card is the user's move in one position; transpositions share a card.
-- If another line plays a different move in a position that already has a
-- card, the first move met wins and that line stops before the other move.
-- Lines end on a user move (trailing opponent moves are dropped).
local PkSan = require("pksan")
local PkStudy = require("pkstudy")

local PkRepertoire = {}
PkRepertoire.__index = PkRepertoire

-- Bump when cards, keys or lines change: it invalidates the cached list
-- summaries (pkopenings.lua).
PkRepertoire.VERSION = 2 -- 2: en passant kept only when legal (pinned pawns)

local function fields(fen)
    local f = {}
    for part in fen:gmatch("%S+") do f[#f + 1] = part end
    return f
end

-- Piece on `square` ("e5") of a FEN placement, or nil.
local function pieceAt(placement, square)
    local file = square:byte(1) - 96
    local rank = tonumber(square:sub(2, 2))
    local row = 0
    for rank_text in placement:gmatch("[^/]+") do
        row = row + 1
        if 9 - row == rank then
            local col = 0
            for ch in rank_text:gmatch(".") do
                local n = tonumber(ch)
                if n then
                    col = col + n
                else
                    col = col + 1
                    if col == file then return ch end
                end
                if col >= file then return nil end
            end
        end
    end
    return nil
end

--- FEN without move counters, and with the en passant square only when a
-- pawn can legally take there (so transpositions get the same key).
function PkRepertoire.normalizeFen(fen)
    local f = fields(fen)
    local placement, turn, castling, ep = f[1], f[2] or "w", f[3] or "-", f[4] or "-"
    if ep ~= "-" then
        local file = ep:byte(1)
        local pawn_rank = (turn == "w") and "5" or "4"
        local pawn = (turn == "w") and "P" or "p"
        local can_take = false
        for _, df in ipairs({ -1, 1 }) do
            local f2 = file + df
            if f2 >= 97 and f2 <= 104 and pieceAt(placement, string.char(f2) .. pawn_rank) == pawn then
                can_take = true
            end
        end
        -- next to it, the pawn may still be pinned: a legal capture there?
        if can_take then
            can_take = false
            local chess = require("pkchess"):new()
            if chess.load(table.concat({ placement, turn, castling, ep, "0", "1" }, " ")) then
                for _, m in ipairs(chess.moves({ verbose = true })) do
                    if m.flags:find("e", 1, true) then can_take = true; break end
                end
            end
        end
        if not can_take then ep = "-" end
    end
    return table.concat({ placement, turn, castling, ep }, " ")
end

local function uciOf(move)
    return move.from .. move.to .. (move.promotion or "")
end

local function turnOf(fen)
    return fen:match("^%S+%s+([wb])") or "w"
end

--- Builds a repertoire from a PkStudy. Moves are resolved with pksan
-- (ADR-0013); `game` (a Chess instance) only validates chapter start FENs. `orientation(i)` optionally overrides chapter i's side
-- ("white"/"black"), e.g. after a flip. Unresolvable moves end their line.
function PkRepertoire.fromStudy(study, game, orientation)
    local self = setmetatable({ study = study, lines = {}, cards = {}, order = {}, conflicts = 0 }, PkRepertoire)
    self.name = study.path and study.path:match("([^/]+)$") or study.name
    for i, ch in ipairs(study.chapters) do
        local root = study:tree(i)
        -- the drill shows positions with chess.lua: both must accept the FEN
        local pos = PkSan.parseFen(root.fen)
        if pos and (not game or game.load(root.fen)) then
            local side = (orientation and orientation(i)) or ch.orientation
            local student = (side == "black") and "b" or "w"
            self:_walk(i, student, root, pos, {})
        end
    end
    return self
end

-- `pos`: node's position parsed by pksan, or nil when not needed yet (its
-- children already resolved, e.g. from PkResCache): parsed only to resolve.
function PkRepertoire:_walk(chapter, student, node, pos, path)
    local followed = {}
    if node.children[1] then
        if turnOf(node.fen) == student then
            followed[1] = node.children[1] -- the repertoire move
        else
            followed = node.children       -- every opponent reply
        end
    end
    local any = false
    for _, child in ipairs(followed) do
        local ok, child_pos
        if child.fen then
            ok = true
        else
            pos = pos or PkSan.parseFen(node.fen)
            ok, child_pos = PkStudy.resolveNode(child, pos)
        end
        if ok then
            any = true
            path[#path + 1] = child
            self:_walk(chapter, student, child, child_pos, path)
            path[#path] = nil
        end
    end
    if not any and #path > 0 then
        self:_addLine(chapter, student, path)
    end
end

function PkRepertoire:_addLine(chapter, student, path)
    local line = { chapter = chapter, student = student, nodes = {}, cards = {}, card_nodes = {} }
    local last_user = 0
    for k, node in ipairs(path) do
        if turnOf(node.parent.fen) == student then
            local key = PkRepertoire.normalizeFen(node.parent.fen)
            local uci = uciOf(node.move)
            local card = self.cards[key]
            if card and card.uci ~= uci then
                self.conflicts = self.conflicts + 1
                break -- another move is already the answer here
            end
            if not card then
                self.cards[key] = { key = key, fen = key, uci = uci, san = node.move.san,
                                    chapter = chapter, node = node }
                self.order[#self.order + 1] = key
            end
            line.cards[#line.cards + 1] = key
            line.card_nodes[#line.card_nodes + 1] = k
            last_user = k
        end
        line.nodes[k] = node
    end
    for k = #line.nodes, last_user + 1, -1 do line.nodes[k] = nil end
    if #line.cards > 0 then -- nothing to drill in a line without user moves
        self.lines[#self.lines + 1] = line
    end
end

--- Index (in the line) of the node that answers card `key`, or nil.
function PkRepertoire.cardIndex(line, key)
    for j, k in ipairs(line.cards) do
        if k == key then return line.card_nodes[j] end
    end
    return nil
end

return PkRepertoire
