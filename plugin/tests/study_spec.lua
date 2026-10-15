-- Study PGN parsing (pkpgn.lua) and tree cursor (pkstudy.lua) on a fixture
-- mimicking Lichess study exports (plugin/tests/fixtures/study.pgn).
local Chess = require("pkchess")
local PkPgn = require("pkpgn")
local PkStudy = require("pkstudy")

local FIXTURE = (PK_REPO_ROOT or ".") .. "/plugin/tests/fixtures/study.pgn"

local function study()
    return assert(PkStudy.open(FIXTURE))
end

local function sans(nodes)
    local out = {}
    for i, n in ipairs(nodes) do out[i] = n.san end
    return table.concat(out, " ")
end

local function mainline(root)
    local out, n = {}, root.children[1]
    while n do out[#out + 1] = n; n = n.children[1] end
    return out
end

return {
    { "index: chapters, titles, tags with escaped quotes", function(t)
        local s = study()
        t.eq(#s.chapters, 5, "chapters")
        t.eq(s.name, "Paperknight test study", "study name")
        t.eq(s.chapters[1].title, "Italian ideas", "ChapterName")
        t.eq(s.chapters[3].title, 'Alice "Ace" Smith – Bob', "White – Black with escaped quotes")
        t.eq(s.chapters[4].title, "Empty", "empty chapter")
        t.ok(s.chapters[2].gamebook and not s.chapters[1].gamebook, "gamebook flag")
        t.eq(s.chapters[3].orientation, "black", "orientation tag")
        t.eq(s.chapters[5].orientation, "white", "default orientation")
    end },
    { "index: '[' lines inside a multi-line comment are not tags", function(t)
        local chapters = PkPgn.index('[Event "A"]\n\n1. e4 { two\n[%cal Ge2e4]\nlines } e5 *\n\n[Event "B"]\n\n1. d4 *\n')
        t.eq(#chapters, 2, "two games")
        t.ok(chapters[1].movetext:find("%[%%cal"), "comment line kept in movetext")
    end },
    { "movetext: intro comment, anno stripped, shapes extracted", function(t)
        local root = study():tree(1)
        t.eq(root.comment, "Welcome! This chapter shows the\nItalian game.", "intro without [%anno]; a hand-written (unwrapped) file keeps its line break")
        t.eq(#root.shapes.circles, 2, "intro circles")
        local e4 = root.children[1]
        t.eq(e4.comment, "Controls the centre.", "[%clk] stripped")
        t.eq(e4.shapes.arrows[1].from .. e4.shapes.arrows[1].to, "e2e4", "arrow")
    end },
    { "movetext: main line, glyphs, nested variations, ';' comment", function(t)
        local root = study():tree(1)
        local main = mainline(root)
        t.eq(sans(main), "e4 e5 Nf3 Nc6 Bc4 Bc5 c3 Nf6 d4 exd4 cxd4 Bb4+ Bd2 Bxd2+ Nbxd2 d5", "main line")
        local bc4 = main[5]
        t.eq(bc4.glyphs[1], 5, "inline !? -> $5")
        t.eq(bc4.comment, "The Italian.", "comment")
        local nc6 = main[4]
        t.eq(#nc6.children, 2, "Bc4 and Bb5 after Nc6")
        local bb5 = nc6.children[2]
        t.eq(bb5.comment, "The Spanish.", "variation comment")
        local a6 = bb5.children[1]
        t.eq(a6.san, "a6", "variation continues")
        t.eq(sans(bb5.children), "a6 Nf6", "nested variation is an alternative to a6")
        t.eq(bb5.children[2].children[1].glyphs[1], 14, "$14 in nested variation")
        t.eq(a6.children[1].san, "Ba4", "after the nested variation the line resumes")
        t.eq(main[6].glyphs[1], 1, "$1")
        t.eq(main[6].comment, "a classical reply", "';' comment")
        local d5 = main[16]
        t.eq(d5.glyphs[1], 132, "$132")
        t.eq(d5.comment, nil, "comment of only commands is empty")
        t.eq(#d5.shapes.arrows, 2, "two arrows"); t.eq(d5.shapes.circles[1].brush, "R", "brush")
    end },
    { "movetext: comment before a variation's first move attaches to that move", function(t)
        local root = PkPgn.parseMovetext("1. e4 ( { Alternatively } 1. d4 ) 1... e5 *")
        t.eq(root.children[2].san, "d4", "variation")
        t.eq(root.children[2].comment, "Alternatively", "pre-move comment")
        t.eq(root.children[1].children[1].san, "e5", "main line resumes")
    end },
    { "movetext: a variation opened before any move of its line stays a sideline", function(t)
        local root = PkPgn.parseMovetext("(1. d4 d5) 1. e4 e5")
        t.eq(#root.children, 2, "two first moves")
        t.eq(root.children[1].san, "e4", "the main line stays first")
        t.eq(root.children[1].children[1].san, "e5", "main line continues")
        t.eq(root.children[2].san, "d4", "the variation is an alternative to 1. e4")
        local e4 = PkPgn.parseMovetext("1. e4 e5 ( ( 1... e6 ) 1... c5 ) 2. Nf3").children[1]
        local sans = {}
        for i, c in ipairs(e4.children) do sans[i] = c.san end
        t.eq(table.concat(sans, " "), "e5 c5 e6", "nested at a line start: alternatives to 1... c5")
        t.eq(e4.children[1].children[1].san, "Nf3", "main line resumes")
    end },
    { "hasMoves / countedChapters without parsing trees; releaseTrees", function(t)
        t.ok(PkPgn.hasMoves("1. e4 e5"), "moves")
        t.ok(not PkPgn.hasMoves("{ Welcome! 1. e4 is a move in a comment } *"), "comment only")
        t.ok(not PkPgn.hasMoves("; 1. e4 in a line comment\n*"), "line comment only")
        t.ok(PkPgn.hasMoves("{ intro } 12.Nf3!? *"), "glued number and glyph")
        local s = study()
        local counted = s:countedChapters()
        for i, ch in ipairs(s.chapters) do
            local expected = #s:tree(i).children > 0
            local listed = false
            for _, c in ipairs(counted) do if c == i then listed = true end end
            t.eq(listed, expected, "chapter " .. i .. " counted like its tree")
            ch.root = nil
        end
        s:tree(1); s:tree(2)
        s:releaseTrees(2)
        t.ok(s.chapters[1].root == nil and s.chapters[2].root ~= nil, "only the kept tree stays")
    end },
    { "index: a tag value ending in an escaped backslash", function(t)
        local games = PkPgn.index('[Event "x"]\n[Annotator "C:\\\\"]\n[Site "\\"q\\" \\\\"]\n\n1. e4 *\n')
        t.eq(#games, 1, "one game")
        t.eq(games[1].tags.Annotator, "C:\\", "backslash kept")
        t.eq(games[1].tags.Site, '"q" \\', "escaped quotes and backslash")
    end },
    { "movetext: robustness (unbalanced parens, 0-0, numbers glued to moves)", function(t)
        local root = PkPgn.parseMovetext("1.e4 e5 ) 2.Nf3 ( 2. Bc4 *")
        t.eq(sans(mainline(root)), "e4 e5 Nf3", "stray ')' ignored, glued numbers")
        t.eq(root.children[1].children[1].children[2].san, "Bc4", "unclosed variation kept")
        t.eq(PkPgn.parseMovetext("1. 0-0 0-0-0").children[1].san, "O-O", "zero castling normalised")
    end },
    { "cursor: walks main line and variations, resolves SAN lazily", function(t)
        local game = Chess:new()
        local s = study()
        local c = assert(s:cursor(1, game))
        t.eq(c.root.children[1].fen, nil, "nothing resolved before walking")
        for _ = 1, 4 do assert(c:forward()) end
        t.eq(PkStudy.moveLabel(c.node), "2... Nc6", "label")
        assert(c:forward(2)) -- 3. Bb5
        t.eq(PkStudy.moveLabel(c.node), "3. Bb5", "variation label")
        t.ok(not c:onMainline(), "off the main line")
        assert(c:forward(2)) -- 3... Nf6
        assert(c:forward()) -- 4. O-O
        t.eq(PkStudy.moveLabel(c.node), "4. O-O +=", "castling with position glyph")
        t.eq(game.get("g1").type, "k", "game follows the cursor")
        c:back(); c:back(); c:back()
        t.eq(PkStudy.moveLabel(c.node), "2... Nc6", "back to the branch point")
        c:toEnd()
        t.eq(PkStudy.moveLabel(c.node), "8... d5 (counterplay)", "end of main line")
        t.ok(c:onMainline(), "main line")
        c:toStart()
        t.eq(c.node, c.root, "start")
        t.eq(game.fen(), c.root.fen, "start position")
    end },
    { "cursor: custom FEN, black to move numbering, gamebook orientation", function(t)
        local game = Chess:new()
        local s = study()
        local c = assert(s:cursor(3, game))
        assert(c:forward())
        t.eq(PkStudy.moveLabel(c.node), "60... Ra6+", "black move number from FEN")
        assert(c:forward())
        t.eq(PkStudy.moveLabel(c.node), "61. Kd5", "white move after")
        c = assert(s:cursor(2, game))
        t.eq(s.chapters[2].orientation, "white", "gamebook orientation")
        local child = c:childForMove("f4", "e5")
        t.ok(child and child.glyphs[1] == 2, "childForMove finds the ? variation")
        t.eq(c:childForMove("a2", "a3"), nil, "move not in the tree")
    end },
    { "cursor: promotion and castling; illegal SAN reported at its node", function(t)
        local game = Chess:new()
        local s = study()
        local c = assert(s:cursor(5, game))
        c:toEnd()
        t.eq(PkStudy.moveLabel(c.node), "3... Rbxd8", "line played to the end")
        local bad = PkStudy.fromText('[Event "x"]\n\n1. e4 e5 2. Ke3 Nc6 *\n')
        local c2 = assert(bad:cursor(1, game))
        c2:toEnd()
        t.eq(c2.node.san, "e5", "stops before the illegal move")
        local ok, err = c2:forward()
        t.eq(ok, nil, "illegal move refused"); t.ok(err:find("Ke3"), err)
        t.eq(game.fen(), c2.node.fen, "game still on the current node")
    end },
    { "open: empty and non-PGN files are refused with a code", function(t)
        local function tmpfile(content)
            local path = os.tmpname()
            local f = io.open(path, "wb"); f:write(content); f:close()
            return path
        end
        local p1, p2 = tmpfile(""), tmpfile("Hello, this is a shopping list.\nMilk\n")
        local s, err = PkStudy.open(p1)
        t.eq(s, nil, "empty refused"); t.eq(err, "empty", "code")
        s, err = PkStudy.open(p2)
        t.eq(s, nil, "text refused"); t.eq(err, "not_pgn", "code")
        os.remove(p1); os.remove(p2)
        t.ok(PkStudy.fromText("1. e4 e5 *") ~= nil, "movetext without tags is still a study")
    end },
    { "empty chapter has a root and no moves", function(t)
        local s = study()
        local c = assert(s:cursor(4, Chess:new()))
        t.eq(#c.root.children, 0, "no moves")
        t.eq(c:forward(), nil, "cannot go forward")
    end },
    { "robustness: BOM, CRLF, '%' lines, several tags per line, empty values", function(t)
        local text = '\239\187\191[Event "A"][Site ""]\r\n[White "W"]\r\n\r\n% escape line\r\n1. e4 e5 *\r\n\r\n[Event "B"]\r\n\r\n1. d4 *\r\n'
        local chapters = PkPgn.index(text)
        t.eq(#chapters, 2, "two chapters")
        t.eq(chapters[1].tags.Event, "A", "BOM stripped"); t.eq(chapters[1].tags.Site, "", "empty value")
        t.eq(chapters[1].tags.White, "W", "CRLF")
        t.ok(not chapters[1].movetext:find("escape"), "'%' line dropped")
        t.eq(sans(mainline(PkPgn.parseMovetext(chapters[1].movetext))), "e4 e5", "moves")
    end },
    { "robustness: unterminated '{' does not swallow the next game", function(t)
        local chapters = PkPgn.index('[Event "A"]\n\n1. e4 { oops\n\n[Event "B"]\n\n1. d4 *\n')
        t.eq(#chapters, 2, "two chapters"); t.eq(chapters[2].tags.Event, "B", "second game")
    end },
    { "robustness: stray '}' and '{' inside a ';' comment", function(t)
        t.eq(sans(mainline(PkPgn.parseMovetext("1. e4 } e5"))), "e4 e5", "stray }")
        local root = PkPgn.parseMovetext("1. e4 ; x { y\n e5 } *")
        t.eq(sans(mainline(root)), "e4 e5", "brace in ';' comment")
        t.eq(root.children[1].comment, "x { y", "';' comment text")
    end },
    { "variation start: NAG dropped, ';' and '{}' comments go to the first move", function(t)
        local root = PkPgn.parseMovetext("1. e4 e5 2. Nf3 ( $5 2. Bc4 ) *")
        local e5 = root.children[1].children[1]
        t.eq(e5.glyphs, nil, "no NAG on e5 (no glyphs table)")
        root = PkPgn.parseMovetext("1. e4 e5 ( ; note\n 1... c5 ) *")
        t.eq(root.children[1].comment, nil, "nothing on e4")
        t.eq(root.children[1].children[2].comment, "note", "on c5")
        root = PkPgn.parseMovetext("1. e4 ( {c} ( 1. c4 ) 1. d4 ) *")
        local by_san = {}
        for _, ch in ipairs(root.children) do by_san[ch.san] = ch end
        t.eq(by_san.d4 and by_san.d4.comment, "c", "pending comment survives a nested variation")
        t.eq(by_san.c4 and by_san.c4.comment, nil, "not on c4")
    end },
    { "tokens: 'e.p.', separate '!' glyph, empty variation", function(t)
        local root = PkPgn.parseMovetext("1. e4 ! d5 2. e5 f5 3. exf6 e.p. () *")
        t.eq(sans(mainline(root)), "e4 d5 e5 f5 exf6", "e.p. skipped")
        t.eq(root.children[1].glyphs[1], 1, "separate ! attached")
    end },
    { "comments: wrapped lines joined, paragraphs kept", function(t)
        local text = PkPgn.cleanComment("a long comment wrapped by the tool that wrote this PGN file at\nabout eighty columns\n\nNew paragraph", nil, true)
        t.eq(text, "a long comment wrapped by the tool that wrote this PGN file at about eighty columns\n\nNew paragraph", "joined")
    end },
    { "cursor: 4-field FEN, jump across branches, foreign node, redo stack", function(t)
        local game = Chess:new()
        local s = PkStudy.fromText('[FEN "4k3/8/8/8/8/8/8/4K2R w K -"]\n\n1. O-O Kd7 ( 1... Kd8 ) *\n')
        t.eq(s.chapters[1].start_fen, "4k3/8/8/8/8/8/8/4K2R w K - 0 1", "padded")
        local c = assert(s:cursor(1, game))
        local kd8 = c.root.children[1].children[2]
        assert(c:jump(kd8))
        t.eq(PkStudy.moveLabel(c.node), "1... Kd8", "jumped into a variation")
        t.eq(game.get("d8").type, "k", "position")
        local other = assert(study():cursor(1, Chess:new()))
        local ok, err = c:jump(other.root.children[1])
        t.eq(ok, nil, "foreign node refused"); t.ok(err:find("not in this chapter"), err)
        c:toStart(); c:toEnd(); c:toStart(); c:toEnd()
        t.eq(#game.redo_stack, 0, "no redo entries leaked by internal undo")
        local unresolved = PkPgn.parseMovetext("1. e4 e5").children[1].children[1]
        t.eq(PkStudy.moveLabel(unresolved), "e5", "no fake move number when unresolved")
    end },
    { "orientation default: set-up position without the tag shows the side to move", function(t)
        local fen_b = "8/8/8/4k3/8/8/4K3/7R b - - 0 1"
        local fen_w = "8/8/8/4k3/8/8/4K3/7R w - - 0 1"
        local function orientation(tags)
            return PkStudy.fromText(tags .. "\n\n*\n").chapters[1].orientation
        end
        t.eq(orientation('[FEN "' .. fen_b .. '"]\n[SetUp "1"]'), "black", "black to move")
        t.eq(orientation('[FEN "8/8/8/4k3/8/8/4K3/7R b - -"]'), "black", "4-field FEN")
        t.eq(orientation('[FEN "' .. fen_w .. '"]'), "white", "white to move")
        t.eq(orientation('[Event "x"]'), "white", "standard start")
        t.eq(orientation('[FEN "' .. fen_b .. '"]\n[Orientation "white"]'), "white", "tag wins")
        t.eq(orientation('[Orientation "black"]'), "black", "tag without FEN")
    end },
}

