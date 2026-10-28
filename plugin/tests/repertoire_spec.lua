-- Repertoire lines and cards (pkrepertoire.lua, ADR-0012) on the fixture.
local Chess = require("pkchess")
local PkRepertoire = require("pkrepertoire")
local PkStudy = require("pkstudy")

local FIXTURE = (PK_REPO_ROOT or ".") .. "/plugin/tests/fixtures/repertoires/repertoire.pgn"

local function rep()
    return PkRepertoire.fromStudy(assert(PkStudy.open(FIXTURE)), Chess:new())
end

local function sans(line)
    local out = {}
    for _, node in ipairs(line.nodes) do out[#out + 1] = node.move.san end
    return table.concat(out, " ")
end

return {
    { "lines follow the user's main move and every opponent reply", function(t)
        local r = rep()
        t.eq(r.name, "repertoire.pgn", "named after the file")
        local got = {}
        for _, line in ipairs(r.lines) do got[#got + 1] = line.chapter .. ": " .. sans(line) end
        t.eq(table.concat(got, "\n"), table.concat({
            "1: e4 e5 Nf3 Nc6 Bc4 Bc5 c3",
            "1: e4 e5 Nf3 d6 d4",
            "1: e4 c5 Nf3 d6 d4",
            "1: e4 c5 Nf3 Nc6 d4",
            "2: e4 c6 d4 d5 e5 Bf5",
            "2: e4 c6 d4 d5 Nc3 dxe4 Nxe4 Bf5",
            "3: e4 Nc6 Nf3 e5 Bc4",
        }, "\n"), "lines (Bb5?! is a known mistake, not drilled)")
        t.eq(r.lines[5].student, "b", "Caro-Kann chapter is played as Black")
    end },
    { "cards: one per user move and position; transpositions share", function(t)
        local r = rep()
        t.eq(#r.order, 14, "8 + 5 + 1 distinct cards")
        local first = r.cards[r.order[1]]
        t.eq(first.san, "e4", "tree order"); t.eq(first.uci, "e2e4", "uci")
        t.eq(first.fen, "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -", "normalized FEN")
        local italian = r.lines[1].cards[3]
        t.eq(r.cards[italian].san, "Bc4", "Bc4 card")
        t.eq(r.lines[7].cards[3], italian, "1. e4 Nc6 2. Nf3 e5 reaches the same Bc4 card")
        t.eq(#r.lines[5].cards, 3, "Black's moves only: c6 d5 Bf5")
        t.eq(PkRepertoire.cardIndex(r.lines[7], italian), 5, "card position in the line")
        t.eq(r.conflicts, 0, "no conflicting moves")
    end },
    { "conflicting moves: the first one met wins, the other line stops before it", function(t)
        local s = PkStudy.fromText('[Event "a"]\n\n1. e4 e5 2. Nf3 Nc6 3. Bc4 *\n\n'
            .. '[Event "b"]\n\n1. e4 e5 2. Bc4 Nf6 3. d3 *\n')
        local r = PkRepertoire.fromStudy(s, Chess:new())
        t.eq(r.conflicts, 1, "one conflict")
        t.eq(#r.lines, 2, "both lines kept")
        t.eq(sans(r.lines[2]), "e4", "second line cut before 2. Bc4, trailing 1... e5 dropped")
        t.eq(#r.order, 3, "cards: e4, Nf3, Bc4 (no card for 2. Bc4 or 3. d3)")
    end },
    { "normalizeFen drops counters and a useless en passant square", function(t)
        local n = PkRepertoire.normalizeFen
        t.eq(n("rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1"),
            "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq -", "no black pawn next to e4")
        t.eq(n("rnbqkbnr/ppp1pppp/8/8/3pP3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 3"),
            "rnbqkbnr/ppp1pppp/8/8/3pP3/8/PPPP1PPP/RNBQKBNR b KQkq e3", "d4 pawn can take en passant")
        t.eq(n("3k4/8/8/8/3pP3/8/8/3RK3 b - e3 0 1"), "3k4/8/8/8/3pP3/8/8/3RK3 b - -",
            "the d4 pawn is pinned: no en passant")
    end },
    { "orientation override and unplayable moves", function(t)
        local s = assert(PkStudy.open(FIXTURE))
        local r = PkRepertoire.fromStudy(s, Chess:new(), function(i) return i == 2 and "white" or nil end)
        t.eq(r.lines[5].student, "w", "chapter 2 drilled as White")
        t.eq(sans(r.lines[5]), "e4 c6 d4 d5 e5", "White follows main moves only, ends on its move")
        local bad = PkRepertoire.fromStudy(PkStudy.fromText('[Event "x"]\n\n1. e4 e5 2. Ke3 *\n'), Chess:new())
        t.eq(#bad.lines, 1, "line ends at the illegal move")
        t.eq(sans(bad.lines[1]), "e4", "up to the last user move (trailing replies dropped)")
    end },
    { "start FENs: counters repaired so both engines accept the chapter", function(t)
        local s = PkStudy.fromText('[Event "a"]\n[FEN "4k3/8/8/8/8/8/4P3/4K3 w - - 0 0"]\n\n1. e4 Kd7 *\n\n'
            .. '[Event "b"]\n[FEN "4k3/8/8/8/8/8/4P3/4K3 w - - 3"]\n\n1. e4 *\n')
        t.eq(s.chapters[1].start_fen, "4k3/8/8/8/8/8/4P3/4K3 w - - 0 1", "move number 0 → 1")
        t.eq(s.chapters[2].start_fen, "4k3/8/8/8/8/8/4P3/4K3 w - - 3 1", "5-field FEN completed")
        local r = PkRepertoire.fromStudy(s, Chess:new())
        t.eq(#r.lines, 2, "both chapters drillable")
        t.ok(s:cursor(1, Chess:new()), "chess.lua accepts the repaired FEN")
    end },
}
