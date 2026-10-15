-- Fast SAN resolver for PGN moves (ADR-0013). Pure Lua, standalone: reads a
-- FEN, resolves one SAN move ("Nf3", "exd5", "O-O", "e8=Q+") and writes the
-- FEN after it. Only the pieces that can reach the target square are looked
-- at, and only those are checked for legality: no move list, no SAN
-- generation (chess.lua, kept for interactive play, does both per move).
--   local move, fen = PkSan.play(fen, "Nf3")   -- nil, error if illegal
--   move = { from = "g1", to = "f3", promotion = nil|"q"…, piece = "n",
--            color = "w"|"b", captured = nil|"p"…, flags = "n"…, san = "Nf3" }
-- `san` is rewritten in standard form (minimal disambiguation, "x", "=Q",
-- "+"), like chess.lua's; "#" is kept when the PGN wrote it (detecting mate
-- would need the full move list).
-- Conventions follow chess.lua: the en passant square is set after every
-- double pawn push; `flags` uses chess.lua's letters (n c b e p k q, e.g.
-- "np" / "cp" for promotions).
-- Differences from chess.lua, on purpose: pksan is lenient with SAN written
-- by people and tools (over-disambiguation "Nbd2", a missing or extra "x",
-- "dc5", long form "e2e4" / "g1f3" / "e1g1", lowercase promotion "a8=q"): the target square
-- and the legality check decide. It is stricter where chess.lua is wrong
-- (castling needs the rook on its square) and allows kingless diagrams.
local PkSan = {}

-- Bump when the output changes (moves, FENs, SAN, legality): it
-- invalidates the resolved-moves caches (pkrescache.lua).
PkSan.VERSION = 2 -- 2: long-form piece moves ("g1f3", "e1g1")

local byte, char, sub, upper, lower = string.byte, string.char, string.sub, string.upper, string.lower

-- Squares are 0..63: index = rank0 * 8 + file0 (a1 = 0, h1 = 7, a8 = 56).
local function sq(name)
    return (byte(name, 2) - 49) * 8 + (byte(name, 1) - 97)
end
local function name(s)
    return char(97 + s % 8) .. char(49 + math.floor(s / 8))
end
PkSan.square, PkSan.squareName = sq, name

local KNIGHT = { { 1, 2 }, { 2, 1 }, { 2, -1 }, { 1, -2 }, { -1, -2 }, { -2, -1 }, { -2, 1 }, { -1, 2 } }
local KING = { { 1, 0 }, { 1, 1 }, { 0, 1 }, { -1, 1 }, { -1, 0 }, { -1, -1 }, { 0, -1 }, { 1, -1 } }
local ROOK_DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
local BISHOP_DIRS = { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }

local function colorOf(p) return p and ((p == upper(p)) and "w" or "b") or nil end
local function typeOf(p) return p and lower(p) or nil end
local function pieceChar(t, color) return color == "w" and upper(t) or t end

local function at(f, r) -- square at file/rank (0-based), or nil off the board
    if f < 0 or f > 7 or r < 0 or r > 7 then return nil end
    return r * 8 + f
end

--- Parses a FEN into a position { board = {[sq] = "P"|"n"…}, turn, castling
-- = { K, Q, k, q booleans }, ep = sq|nil, half, full }. nil if malformed.
local FEN_PIECES = {} -- byte -> piece letter
for c in ("pnbrqkPNBRQK"):gmatch(".") do FEN_PIECES[byte(c)] = c end

function PkSan.parseFen(fen)
    local fields = {}
    for part in fen:gmatch("%S+") do fields[#fields + 1] = part end
    local placement, turn, castling, ep, half, full = fields[1], fields[2], fields[3] or "-",
        fields[4] or "-", fields[5] or "0", fields[6] or "1"
    if #fields > 6 or not placement or (turn ~= "w" and turn ~= "b") then return nil end
    if not castling:match("^%-$") and not castling:match("^K?Q?k?q?$") then return nil end
    if not tonumber(half) or not tonumber(full) then return nil end
    local board = {}
    local r, f = 7, 0
    for i = 1, #placement do -- bytes, not one pattern match per character
        local b = byte(placement, i)
        if b == 47 then -- "/"
            if f ~= 8 then return nil end -- each rank has 8 squares
            r, f = r - 1, 0
        elseif b >= 49 and b <= 56 then -- "1".."8"
            f = f + (b - 48)
            if f > 8 then return nil end
        else
            local c = FEN_PIECES[b]
            if not c or f > 7 or r < 0 then return nil end
            board[r * 8 + f] = c
            f = f + 1
        end
    end
    if r ~= 0 or f ~= 8 then return nil end
    local rights = {}
    for c in castling:gmatch("[KQkq]") do rights[c] = true end
    -- the en passant square must fit the side to move ("-" otherwise)
    local ep_sq
    if ep ~= "-" then
        local want = (turn == "w") and "6" or "3"
        if not ep:match("^[a-h]" .. want .. "$") then return nil end
        ep_sq = sq(ep)
    end
    return {
        board = board, turn = turn, castling = rights, ep = ep_sq,
        half = tonumber(half), full = tonumber(full),
    }
end

function PkSan.toFen(pos)
    local rows = {}
    for r = 7, 0, -1 do
        local row, empty = {}, 0
        for f = 0, 7 do
            local p = pos.board[r * 8 + f]
            if p then
                if empty > 0 then row[#row + 1] = tostring(empty); empty = 0 end
                row[#row + 1] = p
            else
                empty = empty + 1
            end
        end
        if empty > 0 then row[#row + 1] = tostring(empty) end
        rows[#rows + 1] = table.concat(row)
    end
    local c = pos.castling
    local cast = (c.K and "K" or "") .. (c.Q and "Q" or "") .. (c.k and "k" or "") .. (c.q and "q" or "")
    return table.concat(rows, "/") .. " " .. pos.turn .. " " .. (cast ~= "" and cast or "-") .. " "
        .. (pos.ep and name(pos.ep) or "-") .. " " .. pos.half .. " " .. pos.full
end

--- True if square `s` is attacked by a piece of color `by` on `board`.
local function attacked(board, s, by)
    local f, r = s % 8, math.floor(s / 8)
    for _, d in ipairs(KNIGHT) do
        local t = at(f + d[1], r + d[2])
        if t and board[t] == pieceChar("n", by) then return true end
    end
    for _, d in ipairs(KING) do
        local t = at(f + d[1], r + d[2])
        if t and board[t] == pieceChar("k", by) then return true end
    end
    local pr = (by == "w") and -1 or 1 -- attacking pawns sit one rank behind
    for _, df in ipairs({ -1, 1 }) do
        local t = at(f + df, r + pr)
        if t and board[t] == pieceChar("p", by) then return true end
    end
    local rook, bishop, queen = pieceChar("r", by), pieceChar("b", by), pieceChar("q", by)
    for _, d in ipairs(ROOK_DIRS) do
        local ff, rr = f + d[1], r + d[2]
        while true do
            local t = at(ff, rr)
            if not t then break end
            local p = board[t]
            if p then
                if p == rook or p == queen then return true end
                break
            end
            ff, rr = ff + d[1], rr + d[2]
        end
    end
    for _, d in ipairs(BISHOP_DIRS) do
        local ff, rr = f + d[1], r + d[2]
        while true do
            local t = at(ff, rr)
            if not t then break end
            local p = board[t]
            if p then
                if p == bishop or p == queen then return true end
                break
            end
            ff, rr = ff + d[1], rr + d[2]
        end
    end
    return false
end
PkSan.attacked = attacked

local function kingSquare(board, color)
    local k = pieceChar("k", color)
    for s = 0, 63 do
        if board[s] == k then return s end
    end
end

-- Board after a move (shallow: only what the legality test needs).
local function boardAfter(pos, from, to, ep_capture)
    local b = {}
    for s, p in pairs(pos.board) do b[s] = p end
    b[to] = b[from]
    b[from] = nil
    if ep_capture then b[ep_capture] = nil end
    return b
end

local function legal(pos, from, to, ep_capture)
    local b = boardAfter(pos, from, to, ep_capture)
    local k = kingSquare(b, pos.turn)
    if not k then return true end -- no king (study diagrams): anything goes
    return not attacked(b, k, pos.turn == "w" and "b" or "w")
end

-- Candidate origin squares for a non-pawn piece of type `t` moving to `to`.
local function pieceOrigins(pos, t, to)
    local out = {}
    local own = pieceChar(t, pos.turn)
    local f, r = to % 8, math.floor(to / 8)
    if t == "n" or t == "k" then
        for _, d in ipairs(t == "n" and KNIGHT or KING) do
            local s = at(f + d[1], r + d[2])
            if s and pos.board[s] == own then out[#out + 1] = s end
        end
        return out
    end
    local dirs = {}
    if t == "r" or t == "q" then for _, d in ipairs(ROOK_DIRS) do dirs[#dirs + 1] = d end end
    if t == "b" or t == "q" then for _, d in ipairs(BISHOP_DIRS) do dirs[#dirs + 1] = d end end
    for _, d in ipairs(dirs) do
        local ff, rr = f + d[1], r + d[2]
        while true do
            local s = at(ff, rr)
            if not s then break end
            local p = pos.board[s]
            if p then
                if p == own then out[#out + 1] = s end
                break
            end
            ff, rr = ff + d[1], rr + d[2]
        end
    end
    return out
end

-- "+" if the side that just moved gives check; "#" if the PGN said mate.
-- The check mark of `move`, and the position after it (computed for the
-- check test; returned so that callers don't apply the move again).
local function checkMark(pos, move, written)
    local after = PkSan.apply(pos, move)
    local k = kingSquare(after.board, after.turn)
    if not (k and attacked(after.board, k, pos.turn)) then return "", after end
    return written:find("#", 1, true) and "#" or "+", after
end

local function castle(pos, side, san)
    local color = pos.turn
    local r = (color == "w") and 0 or 7
    local right = (color == "w") and (side == "k" and "K" or "Q") or side
    if not pos.castling[right] then return nil, "no castling right" end
    local king_from = r * 8 + 4
    if pos.board[king_from] ~= pieceChar("k", color) then return nil, "king not on e-file" end
    local rook_from = r * 8 + (side == "k" and 7 or 0)
    if pos.board[rook_from] ~= pieceChar("r", color) then return nil, "no rook to castle with" end
    local between = side == "k" and { 5, 6 } or { 1, 2, 3 }
    for _, f in ipairs(between) do
        if pos.board[r * 8 + f] then return nil, "castling path blocked" end
    end
    local enemy = color == "w" and "b" or "w"
    local crossing = side == "k" and { 4, 5, 6 } or { 4, 3, 2 }
    for _, f in ipairs(crossing) do
        if attacked(pos.board, r * 8 + f, enemy) then return nil, "castling through check" end
    end
    local move = { from = name(king_from), to = name(r * 8 + (side == "k" and 6 or 2)), piece = "k",
                   color = color, flags = side }
    local mark, after = checkMark(pos, move, san)
    move.san = (side == "k" and "O-O" or "O-O-O") .. mark
    return move, nil, after
end

--- Resolves `san` in position `pos`. Returns a move (and, third, the
-- position after it), or nil and an error.
function PkSan.resolve(pos, san)
    local clean = san:gsub("[+#!?]+$", ""):gsub("^0%-0%-0$", "O-O-O"):gsub("^0%-0$", "O-O")
    if clean == "O-O" then return castle(pos, "k", san) end
    if clean == "O-O-O" then return castle(pos, "q", san) end
    local p, df, dr, x, target, promo = clean:match("^([KQRBN]?)([a-h]?)([1-8]?)(x?)([a-h][1-8])=?([QRBNqrbn]?)$")
    if not target then return nil, "not a SAN move: " .. san end
    local to = sq(target)
    local color = pos.turn
    local t = (p ~= "" and lower(p)) or "p"
    -- long form without a piece letter ("g1f3"): the piece on the origin square
    if p == "" and df ~= "" and dr ~= "" then
        local piece = pos.board[sq(df .. dr)]
        if piece and colorOf(piece) == color and lower(piece) ~= "p" then
            t = lower(piece)
            if t == "k" and df == "e" and dr == target:sub(2, 2) and (target:sub(1, 1) == "g" or target:sub(1, 1) == "c") then
                return castle(pos, target:sub(1, 1) == "g" and "k" or "q", san) -- "e1g1"
            end
        end
    end
    local occupant = pos.board[to]
    if occupant and colorOf(occupant) == color then return nil, "own piece on " .. target end
    local origins, ep_capture = {}, nil
    if t == "p" then
        local dir = (color == "w") and 1 or -1
        local f, r = to % 8, math.floor(to / 8)
        local capture = x == "x" or (df ~= "" and byte(df) - 97 ~= f)
        local own = pieceChar("p", color)
        if capture then
            for _, d in ipairs({ -1, 1 }) do
                local s = at(f + d, r - dir)
                if s and pos.board[s] == own then origins[#origins + 1] = s end
            end
            if not occupant then
                -- en passant: the enemy pawn that just moved stands behind
                if pos.ep == to and pos.board[to - 8 * dir] == pieceChar("p", color == "w" and "b" or "w") then
                    ep_capture = to - 8 * dir
                else
                    return nil, "nothing to capture on " .. target
                end
            end
        else
            if occupant then return nil, "square " .. target .. " is occupied" end
            local one = at(f, r - dir)
            if one and pos.board[one] == own then
                origins[1] = one
            elseif one and not pos.board[one] and r == ((color == "w") and 3 or 4) then
                local two = at(f, r - 2 * dir)
                if two and pos.board[two] == own then origins[1] = two end
            end
        end
        local last = (color == "w") and 7 or 0
        if r == last and promo == "" then return nil, "promotion piece missing" end
        if r ~= last and promo ~= "" then return nil, "promotion on " .. target end
    else
        if promo ~= "" then return nil, "only pawns promote" end
        origins = pieceOrigins(pos, t, to)
    end
    local found
    local others = {} -- other legal origins (for the disambiguation in SAN)
    for _, s in ipairs(origins) do
        local sf, sr = char(97 + s % 8), char(49 + math.floor(s / 8))
        local fits = (df == "" or df == sf) and (dr == "" or dr == sr)
        if (fits or #origins > 1) and legal(pos, s, to, ep_capture) then
            if fits then
                if found then return nil, "ambiguous move " .. san end
                found = s
            else
                others[#others + 1] = s
            end
        end
    end
    if not found then return nil, "illegal move " .. san end
    local flags
    if ep_capture then
        flags = "e"
    elseif t == "p" and math.abs(to - found) == 16 then
        flags = "b"
    else
        flags = (occupant and "c" or "n") .. (promo ~= "" and "p" or "")
    end
    local move = {
        from = name(found), to = target, piece = t, color = color,
        captured = occupant and typeOf(occupant) or (ep_capture and "p") or nil,
        promotion = promo ~= "" and lower(promo) or nil, flags = flags,
    }
    -- standard SAN
    local capture = move.captured ~= nil
    local prefix
    if t == "p" then
        prefix = capture and sub(move.from, 1, 1) or ""
    else
        prefix = upper(t)
        if #others > 0 then
            local same_file, same_rank = false, false
            for _, o in ipairs(others) do
                if o % 8 == found % 8 then same_file = true end
                if math.floor(o / 8) == math.floor(found / 8) then same_rank = true end
            end
            if not same_file then
                prefix = prefix .. sub(move.from, 1, 1)
            elseif not same_rank then
                prefix = prefix .. sub(move.from, 2, 2)
            else
                prefix = prefix .. move.from
            end
        end
    end
    local mark, after = checkMark(pos, move, san)
    move.san = prefix .. (capture and "x" or "") .. target
        .. (move.promotion and ("=" .. upper(move.promotion)) or "") .. mark
    return move, nil, after
end

local CORNER_RIGHT = { [0] = "Q", [7] = "K", [56] = "q", [63] = "k" }

--- Position after `move` (from PkSan.resolve). Does not modify `pos`.
function PkSan.apply(pos, move)
    local board = {}
    for s, p in pairs(pos.board) do board[s] = p end
    local from, to = sq(move.from), sq(move.to)
    local color = pos.turn
    local piece = board[from]
    board[from] = nil
    if move.flags == "e" then board[to + ((color == "w") and -8 or 8)] = nil end
    board[to] = move.promotion and pieceChar(move.promotion, color) or piece
    if move.flags == "k" or move.flags == "q" then
        local r = (color == "w") and 0 or 7
        local rf, rt = (move.flags == "k") and 7 or 0, (move.flags == "k") and 5 or 3
        board[r * 8 + rt] = board[r * 8 + rf]
        board[r * 8 + rf] = nil
    end
    local castling = {}
    for k, v in pairs(pos.castling) do castling[k] = v end
    if move.piece == "k" then
        if color == "w" then castling.K, castling.Q = nil, nil else castling.k, castling.q = nil, nil end
    end
    if CORNER_RIGHT[from] then castling[CORNER_RIGHT[from]] = nil end
    if CORNER_RIGHT[to] then castling[CORNER_RIGHT[to]] = nil end
    local reset = move.piece == "p" or move.captured ~= nil
    return {
        board = board,
        turn = (color == "w") and "b" or "w",
        castling = castling,
        ep = (move.flags == "b") and math.floor((from + to) / 2) or nil,
        half = reset and 0 or pos.half + 1,
        full = pos.full + ((color == "b") and 1 or 0),
    }
end

-- Parsed positions by FEN (positions are never modified: apply copies). A
-- tree walk resolves all children of a node in turn, and comes back to the
-- node after each subtree: a small cache avoids re-parsing it each time.
local CACHE_SIZE = 64
local cache, cache_keys, cache_next = {}, {}, 1

local function parsed(fen)
    local pos = cache[fen]
    if pos then return pos end
    pos = PkSan.parseFen(fen)
    if pos then
        local old = cache_keys[cache_next]
        if old then cache[old] = nil end
        cache_keys[cache_next], cache[fen] = fen, pos
        cache_next = cache_next % CACHE_SIZE + 1
    end
    return pos
end

--- Resolves `san` from a parsed position. Returns move, position after it,
-- FEN after it; or nil, error. (Tree walks pass positions down.)
function PkSan.playPos(pos, san)
    local move, err, after = PkSan.resolve(pos, san)
    if not move then return nil, err end
    after = after or PkSan.apply(pos, move)
    return move, after, PkSan.toFen(after)
end

--- Resolves `san` from `fen`. Returns move, fen after it; or nil, error.
function PkSan.play(fen, san)
    local pos = parsed(fen)
    if not pos then return nil, "invalid FEN" end
    local move, err, after = PkSan.resolve(pos, san)
    if not move then return nil, err end
    return move, PkSan.toFen(after or PkSan.apply(pos, move))
end

return PkSan
