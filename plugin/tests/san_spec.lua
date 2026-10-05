-- Fast SAN resolver (pksan.lua, ADR-0013), checked against chess.lua (the
-- engine used for play) and python-chess (fixture FENs).
local Chess = require("pkchess")
local PkPgn = require("pkpgn")
local PkSan = require("pksan")

local START = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
local RANDOM = (PK_REPO_ROOT or ".") .. "/plugin/tests/fixtures/random_games.pgn"

local function read(path)
    local f = assert(io.open(path, "rb"))
    local text = f:read("*a")
    f:close()
    return text
end

-- Both engines resolve `san` from `fen`; returns pksan's move and fen.
local function both(t, fen, san, where)
    local move, after = PkSan.play(fen, san)
    local game = Chess:new()
    game.load(fen)
    local ref = game.move(san)
    t.ok(move ~= nil, where .. ": pksan resolves " .. san .. " (" .. tostring(after) .. ")")
    t.ok(ref ~= nil, where .. ": chess.lua resolves " .. san)
    if move and ref then
        t.eq(move.from .. move.to .. (move.promotion or ""), ref.from .. ref.to .. (ref.promotion or ""), where .. " " .. san)
        t.eq(after, game.fen(), where .. " FEN after " .. san)
        t.eq(move.san, ref.san, where .. " standard SAN of " .. san)
    end
    return move, after
end

local function rejects(t, fen, san, why)
    local move, err = PkSan.play(fen, san)
    t.eq(move, nil, why .. ": " .. san .. " rejected")
    local game = Chess:new()
    game.load(fen)
    t.eq(game.move(san), nil, why .. ": chess.lua agrees")
    return err
end

return {
    { "random games: every ply agrees with chess.lua, final FEN with python-chess", function(t)
        local games = PkPgn.index(read(RANDOM))
        t.ok(#games >= 100, "fixture loaded: " .. #games)
        local plies = 0
        for gi, g in ipairs(games) do
            local fen = START
            local node = PkPgn.parseMovetext(g.movetext).children[1]
            while node do
                local _, after = both(t, fen, node.san, "game " .. gi .. " ply " .. plies)
                if not after then break end
                fen, plies = after, plies + 1
                node = node.children[1]
            end
            t.eq(fen, g.tags.FinalFEN, "game " .. gi .. " final FEN")
        end
        t.ok(plies > 10000, "plies checked: " .. plies)
    end },
    { "every legal move at sampled positions agrees with chess.lua", function(t)
        local games = PkPgn.index(read(RANDOM))
        local checked = 0
        for gi = 1, #games, 12 do
            local fen, ply = START, 0
            local node = PkPgn.parseMovetext(games[gi].movetext).children[1]
            while node do
                if ply % 25 == 12 then
                    local game = Chess:new()
                    game.load(fen)
                    for _, m in ipairs(game.moves({ verbose = true })) do
                        local move, after = PkSan.play(fen, m.san)
                        t.ok(move and move.from == m.from and move.to == m.to
                            and move.promotion == m.promotion, "game " .. gi .. " " .. m.san .. " in " .. fen)
                        t.eq(move and move.flags, m.flags, "flags of " .. m.san)
                        t.eq(move and move.san, m.san, "SAN of " .. m.san)
                        game.move(m.san)
                        t.eq(after, game.fen(), "FEN after " .. m.san)
                        game.undo()
                        checked = checked + 1
                    end
                end
                fen = select(2, PkSan.play(fen, node.san))
                ply = ply + 1
                node = node.children[1]
            end
        end
        t.ok(checked > 500, "moves checked: " .. checked)
    end },
    { "castling: rights, path, through check", function(t)
        local fen = "r3kr2/8/8/8/8/8/8/R3K2R w KQ - 0 1"
        rejects(t, fen, "O-O", "f1 attacked by the f8 rook")
        local m, after = both(t, fen, "O-O-O", "queenside")
        t.eq(m.flags, "q", "castling flag")
        t.eq(after, "r3kr2/8/8/8/8/8/8/2KR3R b - - 1 1", "king and rook moved, rights gone")
        rejects(t, "r3k2r/8/8/8/8/8/8/R3K2R w Qkq - 0 1", "O-O", "no kingside right")
        rejects(t, "r3k2r/8/8/8/8/8/8/R2QK2R w KQkq - 0 1", "O-O-O", "path blocked")
        rejects(t, "4k3/8/8/8/8/8/4r3/R3K2R w KQ - 0 1", "O-O", "king in check")
        local _, a2 = both(t, "r3k2r/8/8/8/8/8/1B6/R3K2R w KQkq - 0 1", "Bxh8", "rook captured")
        t.eq(a2:match("^%S+ %S+ (%S+)"), "KQq", "capturing the h8 rook removes Black's kingside right")
    end },
    { "en passant: legal, pinned, square convention", function(t)
        local m, after = both(t, "8/8/8/1Pp5/8/8/8/K6k w - c6 0 2", "bxc6", "en passant")
        t.eq(m.flags, "e", "ep flag"); t.eq(m.captured, "p", "pawn captured")
        t.eq(after, "8/8/2P5/8/8/8/8/K6k b - - 0 2", "c5 pawn removed")
        rejects(t, "8/8/8/KPp4r/8/8/8/7k w - c6 0 2", "bxc6", "en passant exposing the king on the 5th rank")
        local _, a2 = both(t, START, "e4", "double push")
        t.eq(a2, "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1", "ep square set after every double push")
    end },
    { "disambiguation, pins, promotions, errors", function(t)
        local pinned = "k7/8/2b5/8/8/5N2/8/1N5K w - - 0 1" -- the f3 knight is pinned to h1
        local m = both(t, pinned, "Nd2", "pinned knight ignored")
        t.eq(m.from, "b1", "the free knight moves")
        local over = PkSan.play(pinned, "Nbd2")
        t.eq(over and over.from, "b1", "over-disambiguated SAN accepted (lenient)")
        t.eq(over and over.san, "Nd2", "and written in standard form")
        local long = PkSan.play(START, "Ng1f3")
        t.eq(long and long.san, "Nf3", "long form normalised")
        local nocheck = PkSan.play("4k3/8/8/8/8/8/8/R3K3 w - - 0 1", "Ra8")
        t.eq(nocheck and nocheck.san, "Ra8+", "missing check mark added")
        local rooks = "4k3/8/8/8/8/8/4K3/R6R w - - 0 1"
        t.ok(rejects(t, rooks, "Rd1", "two rooks"):find("ambiguous"), "ambiguity reported")
        t.eq(both(t, rooks, "Rad1", "file disambiguation").from, "a1", "a-rook")
        local promo = "1r5k/P7/8/8/8/8/8/K7 w - - 0 1"
        local p = both(t, promo, "axb8=N", "capture-promotion to a knight")
        t.eq(p.promotion, "n", "underpromotion"); t.eq(p.flags, "cp", "capture + promotion flags")
        both(t, "7k/P7/8/8/8/8/8/K7 w - - 0 1", "a8=Q+", "promotion with check mark")
        t.eq(PkSan.play("7k/P7/8/8/8/8/8/K7 w - - 0 1", "a8=q") ~= nil, true, "lowercase promotion piece")
        t.eq(PkSan.play("7k/P7/8/8/8/8/8/K7 w - - 0 1", "a8"), nil, "promotion piece required")
        rejects(t, "4k3/8/8/8/8/8/4r3/4K3 w - - 0 1", "Kf2", "king into check")
        rejects(t, "4k3/4r3/8/8/8/8/4B3/4K3 w - - 0 1", "Bd3", "pinned bishop")
        t.eq(PkSan.play(START, "Nf6"), nil, "no piece can get there")
        t.eq(PkSan.play(START, "e5"), nil, "pawn cannot jump")
        t.eq(PkSan.play("not a fen", "e4"), nil, "invalid FEN")
        -- stricter than chess.lua: castling needs the rook
        t.eq(PkSan.play("4k3/8/8/8/8/8/8/R3K3 w K - 0 1", "O-O"), nil, "no rook on h1")
        -- inconsistent en passant field: rejected, never deletes a piece
        t.eq(PkSan.play("4k3/8/8/8/8/8/3PQ3/4K3 w - e3 0 1", "dxe3"), nil, "ep square of the wrong side")
        t.eq(PkSan.play("4k3/8/4p3/3P4/8/8/8/4K3 w - e6 0 1", "dxe6") and true, true, "plain capture on the ep square")
        t.eq(PkSan.play("4k3/8/8/3P4/8/8/8/4K3 w - e6 0 1", "dxe6"), nil, "no pawn behind the ep square")
        -- malformed FENs
        for _, bad in ipairs({ "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBN w KQkq - 0 1",
                               "rnbqkbnr/pppppppp/9/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
                               "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq 0 1 x",
                               "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq 0 1" }) do
            t.eq(PkSan.parseFen(bad), nil, "malformed FEN rejected: " .. bad)
        end
        t.ok(PkSan.parseFen("8/8/8/8/8/8/8/4K2k w -"), "missing counters default to 0 1")
        -- study diagrams without kings are allowed (chess.lua refuses them)
        local m2, a3 = PkSan.play("8/8/8/8/8/8/4P3/8 w - - 0 1", "e4")
        t.ok(m2 and a3:find("^8/8/8/8/4P3/"), "kingless position")
    end },
}
