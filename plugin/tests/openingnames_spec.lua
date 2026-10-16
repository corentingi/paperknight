-- Opening names by position (pkopeningnames.lua), on the real table.
local PkOpeningNames = require("pkopeningnames")
PkOpeningNames.path = PK_REPO_ROOT .. "/plugin/paperknight.koplugin/data/openings.tsv"

local START = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
-- 1. e4 e5 (python-chess checked), with an en passant square as some FEN writers set it
local E4E5 = "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2"
-- 1. e4 e5 2. Qh5 Ke7 (python-chess checked): out of the book
local OUT = "rnbq1bnr/ppppkppp/8/4p2Q/4P3/8/PPPP1PPP/RNB1KBNR w KQ - 2 3"

return {
    { "a position's name; the en passant square does not matter", function(t)
        t.eq(PkOpeningNames.of(E4E5), "C20 King's Pawn Game", "1. e4 e5")
        t.eq(PkOpeningNames.of(START), nil, "the initial position has no name")
    end },
    { "a line keeps the last name once out of the book", function(t)
        t.eq(PkOpeningNames.latest({ START, E4E5, OUT }), "C20 King's Pawn Game", "latest")
        t.eq(PkOpeningNames.latest({ START }), nil, "nothing named")
    end },
    { "tree nodes: the name of the node or its nearest ancestor, cached", function(t)
        local root = { fen = START }
        local a = { fen = E4E5, parent = root }
        local b = { fen = OUT, parent = a }
        t.eq(PkOpeningNames.forNode(b), "C20 King's Pawn Game", "from the parent")
        t.eq(b._opening, false, "cached: no name of its own")
        t.eq(PkOpeningNames.forNode(root), nil, "root without a name")
    end },
}
