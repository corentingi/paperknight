-- Resolved-moves cache (pkrescache.lua): a repertoire built from a cached
-- study equals one built cold, and stale or damaged caches are refused.
local Chess = require("pkchess")
local PkRepertoire = require("pkrepertoire")
local PkResCache = require("pkrescache")
local PkStudy = require("pkstudy")

local FIXTURE = (PK_REPO_ROOT or ".") .. "/plugin/tests/fixtures/repertoires/repertoire.pgn"

-- Everything the drill reads from a repertoire, as text.
local function signature(rep)
    local out = {}
    for _, key in ipairs(rep.order) do
        local c = rep.cards[key]
        out[#out + 1] = table.concat({ key, c.uci, c.san, c.chapter, c.node.fen }, "|")
    end
    for _, line in ipairs(rep.lines) do
        local moves = {}
        for _, node in ipairs(line.nodes) do
            local m = node.move
            moves[#moves + 1] = table.concat({ m.from, m.to, m.promotion or "", m.piece, m.color,
                m.captured or "", m.flags, m.san, node.fen, node.ply }, ",")
        end
        out[#out + 1] = line.chapter .. line.student .. table.concat(line.cards, ";") .. table.concat(moves, " ")
    end
    out[#out + 1] = "conflicts " .. rep.conflicts
    return table.concat(out, "\n")
end

local function cold()
    local study = assert(PkStudy.open(FIXTURE))
    return study, PkRepertoire.fromStudy(study, Chess:new())
end

local function nodes(study)
    local n = 0
    local function walk(node) for _, c in ipairs(node.children) do n = n + 1; walk(c) end end
    for i = 1, #study.chapters do walk(study:tree(i)) end
    return n
end

-- Builds a repertoire from a fresh study with `text` applied, and checks
-- that no move was resolved by pksan.
local function warm(t, text, stamp)
    local study = assert(PkStudy.open(FIXTURE))
    local n = PkResCache.apply(study, text, stamp)
    local PkSan = require("pksan")
    local playPos, play = PkSan.playPos, PkSan.play
    local calls = 0
    PkSan.playPos = function(...) calls = calls + 1; return playPos(...) end
    PkSan.play = function(...) calls = calls + 1; return play(...) end
    local ok, rep = pcall(PkRepertoire.fromStudy, study, Chess:new())
    PkSan.playPos, PkSan.play = playPos, play
    t.ok(ok, tostring(rep))
    return rep, n, calls, study
end

return {
    { "a cached study builds the same repertoire, without resolving", function(t)
        local study, rep = cold()
        local text, resolved = PkResCache.dump(study, "f|1")
        t.ok(resolved > 0 and resolved < nodes(study), "only the walked nodes are resolved: " .. resolved)
        local rep2, applied, calls = warm(t, text, "f|1")
        t.eq(applied, resolved, "every resolved node applied")
        t.eq(calls, 0, "no SAN resolved")
        t.eq(signature(rep2), signature(rep), "same repertoire")
    end },
    { "a flip resolves the missing moves, and the dump grows", function(t)
        local study, rep = cold()
        local text, resolved = PkResCache.dump(study, "s")
        local study2 = assert(PkStudy.open(FIXTURE))
        PkResCache.apply(study2, text, "s")
        local flipped = function(i) return i == 1 and "black" or nil end
        local rep2 = PkRepertoire.fromStudy(study2, Chess:new(), flipped)
        local _, resolved2 = PkResCache.dump(study2, "s")
        t.ok(resolved2 > resolved, "more moves resolved: " .. resolved .. " -> " .. resolved2)
        local study3 = assert(PkStudy.open(FIXTURE))
        local rep3 = PkRepertoire.fromStudy(study3, Chess:new(), flipped)
        t.eq(signature(rep2), signature(rep3), "flipped repertoire from a partial cache = cold")
        t.ok(signature(rep2) ~= signature(rep), "the flip changed the repertoire")
    end },
    { "illegal moves are remembered", function(t)
        local study = PkStudy.fromText('[Event "x"]\n\n1. e4 e5 2. Ke3 Nc6 (2... Qh4) *\n', "x")
        study.path = "x.pgn"
        PkRepertoire.fromStudy(study, Chess:new())
        local text = PkResCache.dump(study, "s")
        t.ok(text:find("Ke3\t!", 1, true), "error line")
        local study2 = PkStudy.fromText('[Event "x"]\n\n1. e4 e5 2. Ke3 Nc6 (2... Qh4) *\n', "x")
        PkResCache.apply(study2, text, "s")
        local ke3 = study2:tree(1).children[1].children[1].children[1]
        t.eq(ke3.error, "illegal move Ke3", "error restored")
        t.ok(not ke3.children[1].fen, "nothing below it is resolved")
    end },
    { "stale, edited or damaged caches are refused, with nothing applied", function(t)
        local study = cold()
        local text = PkResCache.dump(study, "f|1")
        local function refused(bad, stamp, why)
            local s = assert(PkStudy.open(FIXTURE))
            local n, reason = PkResCache.apply(s, bad, stamp or "f|1")
            t.eq(n, nil, why)
            t.ok(reason, why .. ": a reason")
            t.ok(not s:tree(1).children[1].fen, why .. ": nothing applied")
        end
        refused(text, "f|2", "other stamp")
        refused(nil, nil, "no file")
        refused("", nil, "empty file")
        refused((text:gsub("pkres 1", "pkres 9")), nil, "other version")
        refused((text:gsub("\tNc6\t", "\tNc7\t", 1):gsub("\nNc6\t", "\nNd4\t", 1)), nil, "other SAN in the PGN")
        refused((text:sub(1, math.floor(#text / 2)):gsub("[^\n]*$", "")), nil, "truncated")
        refused((text:gsub("\n[^\n]*\n$", "\n")), nil, "last line missing")
        refused(text .. "junk\n", nil, "trailing data")
        refused((text:gsub("(\ne4\t)[^\n]*", "%1e2\te4", 1)), nil, "short line")
        refused((text:gsub("\nc 2 (%d+)", function(n) return "\nc 2 " .. (n + 1) end)), nil, "node count")
    end },
    { "a changed chapter start position is refused", function(t)
        local pgn = '[Event "x"]\n[SetUp "1"]\n[FEN "%s"]\n\n1. Nf3 Nf6 *\n'
        local a = PkStudy.fromText(pgn:format("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"), "x")
        PkRepertoire.fromStudy(a, Chess:new())
        local text = PkResCache.dump(a, "s")
        local b = PkStudy.fromText(pgn:format("rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 1"), "x")
        t.eq(PkResCache.apply(b, text, "s"), nil, "same moves, other start: refused")
        t.ok(not b:tree(1).children[1].fen, "nothing applied")
    end },
    { "a cache made with a flip serves the unflipped repertoire", function(t)
        local flipped = function(i) return i == 1 and "black" or nil end
        local study = assert(PkStudy.open(FIXTURE))
        PkRepertoire.fromStudy(study, Chess:new(), flipped)
        local text = PkResCache.dump(study, "s")
        local _, rep = cold()
        local rep2 = warm(t, text, "s")
        t.eq(signature(rep2), signature(rep), "same as cold")
    end },
}
