-- Rules engine (vendored arizati/chess.lua) through the plugin's Chess wrapper.
local Chess = require("pkchess")

return {
    { "the history kept as moves are played and undone: as the engine replays it", function(t)
        local function same(game, what)
            local kept, replayed = game.history(), game._replayed_history()
            t.eq(table.concat(kept, " "), table.concat(replayed, " "), what .. ": SAN")
            local kv, rv = game.history({ verbose = true }), game._replayed_history({ verbose = true })
            t.eq(#kv, #rv, what .. ": length")
            for i = 1, #rv do
                for _, k in ipairs({ "from", "to", "san", "piece", "color", "flags", "promotion", "captured" }) do
                    t.eq(kv[i][k], rv[i][k], ("%s: ply %d %s"):format(what, i, k))
                end
            end
        end
        math.randomseed(20261112)
        for g = 1, 12 do
            local game = Chess:new()
            if g % 3 == 0 then t.ok(game.load("r3k2r/pppq1ppp/2n2n2/3pp3/1b1PP3/2N2N2/PPPQ1PPP/R3KB1R w KQkq - 2 8")) end
            for ply = 1, 90 do
                local r = math.random()
                if r < 0.12 then game.undo()
                elseif r < 0.18 then game.redo()
                else
                    local moves = game.moves({ verbose = true })
                    if #moves == 0 then break end
                    local m = moves[math.random(#moves)]
                    t.ok(game.move({ from = m.from, to = m.to, promotion = m.promotion }), "a legal move")
                end
                if ply % 15 == 0 then same(game, ("game %d, ply %d"):format(g, ply)) end
            end
            same(game, "game " .. g)
        end
        local game = Chess:new()
        game.move("e4"); game.move("e5")
        game.history({ verbose = true })[1].san = "changed"
        t.eq(game.history()[1], "e4", "the verbose moves are copies")
        t.ok(not game.load("not a fen"), "a bad FEN")
        t.eq(#game.history(), 2, "a FEN that does not load keeps the moves")
        game.reset()
        t.eq(#game.history(), 0, "reset")
        t.ok(game.load_pgn("1. d4 d5 2. c4 e6"), "a PGN")
        same(game, "load_pgn"); t.eq(#game.history(), 4)
        game.clear()
        t.eq(#game.history(), 0, "clear")
    end },
    { "perft(3) from the start position is 8902", function(t)
        local game = Chess:new()
        t.eq(game.perft(3), 8902, "perft(3)")
    end },
    { "SAN and history after 1.e4 e5 2.Nf3", function(t)
        local game = Chess:new()
        t.ok(game.move("e4")); t.ok(game.move("e5")); t.ok(game.move({ from = "g1", to = "f3" }))
        t.eq(table.concat(game.history(), " "), "e4 e5 Nf3", "history")
    end },
    { "loads a FEN and detects checkmate (back-rank mate)", function(t)
        local game = Chess:new()
        t.ok(game.load("6k1/5ppp/8/8/8/8/5PPP/3R2K1 w - - 0 1"), "load fen")
        t.ok(game.move("Rd8#"), "Rd8#")
        t.ok(game.in_checkmate(), "checkmate")
    end },
    { "rejects an illegal move", function(t)
        local game = Chess:new()
        t.eq(game.move({ from = "e2", to = "e5" }), nil, "illegal e2e5")
    end },
    { "undo/redo keeps a redo stack", function(t)
        local game = Chess:new()
        game.move("d4")
        t.ok(game.undo(), "undo")
        t.ok(game.redo(), "redo")
        t.eq(game.history()[1], "d4", "redone move")
    end },
    { "the redo history ends with a reset, a load or a new move", function(t)
        local game = Chess:new()
        game.move("d4"); game.move("d5")
        game.undo(); game.undo()
        t.eq(#game.redo_history(), 2, "two moves to redo")
        game.reset()
        t.eq(#game.redo_history(), 0, "reset clears it")
        t.eq(_G._reset, nil, "no global leaked")
        game.move("e4"); game.undo()
        game.load("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")
        t.eq(#game.redo_history(), 0, "load clears it")
        game.move("e4"); game.move("e5"); game.undo()
        t.eq(#game.redo_history(), 1, "one move to redo")
        game.move("c5")
        t.eq(#game.redo_history(), 0, "a new move clears it")
        t.eq(game.redo(), nil, "nothing to redo")
        game.move("Nf3"); game.undo(); game.redo()
        t.eq(game.history()[3], "Nf3", "redo still works")
    end },
}
