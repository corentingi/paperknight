-- Rules engine (vendored arizati/chess.lua) through the plugin's Chess wrapper.
local Chess = require("pkchess")

return {
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
