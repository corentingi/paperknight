-- Comment text: line breaks, position words (pkpgn.lua), links (pktext.lua).
local PkPgn = require("pkpgn")
local PkText = require("pktext")

local WRAPPED = "This comment was written in a tool that wraps its PGN output at\n"
    .. "eighty columns, so a sentence continues on the next line."

return {
    { "line breaks: lists and short lines kept, 80-column wrapping joined", function(t)
        local c = PkPgn.cleanComment
        t.eq(c("Plans:\n- attack the king\n- push the h-pawn"), "Plans:\n- attack the king\n- push the h-pawn", "list kept")
        t.eq(c("1. develop\n2. castle\n3. connect rooks"), "1. develop\n2. castle\n3. connect rooks", "numbered list")
        t.eq(c("White wins.\nBlack resigns."), "White wins.\nBlack resigns.", "short lines kept")
        t.eq(c("♟ pawns first\n♞ then knights"), "♟ pawns first\n♞ then knights", "emoji bullets")
        t.eq(c(WRAPPED, nil, true), WRAPPED:gsub("\n", " "), "wrapped sentence joined (tool-wrapped file)")
        t.eq(c(WRAPPED), WRAPPED, "kept in an unwrapped (Lichess) file")
        t.eq(c("Plans:\n- a\n- b", nil, true), "Plans:\n- a\n- b", "list items keep their breaks when wrapped")
        t.eq(c("Welcome! This chapter shows the\nItalian game.", nil, true), "Welcome! This chapter shows the Italian game.",
            "short first line of a wrapped comment joined")
        local lichess = "1. e4 { Some of black's moves are:\n- 5... Nbd7?? 6. Nb5 } 1... e5 2. Nf3 Nc6 3. Bc4 Bc5 4. c3 Nf6 5. d4 exd4 6. cxd4 Bb4+ 7. Bd2 *"
        t.ok(not PkPgn.isWrapped(lichess), "Lichess-style long line: not wrapped")
        t.eq(PkPgn.parseMovetext(lichess).children[1].comment, "Some of black's moves are:\n- 5... Nbd7?? 6. Nb5", "break kept")
        local tool = "1. e4 { This comment was written in a tool that wraps its PGN output at eighty\n"
            .. "columns. } 1... e5 2. Nf3 Nc6 3. Bc4 Bc5 4. c3 Nf6 5. d4 exd4 6. cxd4 Bb4+ 7.\n"
            .. "Bd2 Bxd2+ 8. Nbxd2 d5 *"
        t.ok(PkPgn.isWrapped(tool), "short lines: wrapped by a tool")
        t.eq(PkPgn.parseMovetext(tool).children[1].comment,
            "This comment was written in a tool that wraps its PGN output at eighty columns.", "joined")
        t.eq(c("Para one.\n\nPara two."), "Para one.\n\nPara two.", "paragraphs kept")
        t.eq(c("A long line that ends with a colon and introduces the list below:\n- item"),
            "A long line that ends with a colon and introduces the list below:\n- item", "colon keeps the break")
        t.eq(c("  spaced  \n  out  [%clk 0:01:00]  "), "spaced\nout", "whitespace tidied, commands dropped")
    end },
    { "position marks in words; move marks are not", function(t)
        t.eq(PkPgn.positionWords({ 14 }), "White is slightly better", "+=")
        t.eq(PkPgn.positionWords({ 3, 19 }), "Black is winning", "!! ignored, -+ in words")
        t.eq(PkPgn.positionWords({ 36, 18 }), "White has the initiative. White is winning", "several")
        t.eq(PkPgn.positionWords({ 1 }), nil, "move mark only")
        t.eq(PkPgn.positionWords(nil), nil, "no glyphs")
    end },
    { "links shortened, positions for taps", function(t)
        local text, links = PkText.linkify("Watch https://www.youtube.com/watch?v=abc123. Then read http://example.org/a_(b) ok")
        t.eq(text, "Watch youtube.com ↗. Then read example.org ↗ ok", "display")
        t.eq(#links, 2, "two links")
        t.eq(links[1].url, "https://www.youtube.com/watch?v=abc123", "trailing dot not in the address")
        t.eq(links[2].url, "http://example.org/a_(b)", "balanced parenthesis kept")
        t.eq(links[1].label, "youtube.com", "label")
        t.eq(PkText.linkAt(links, links[1].first).url, links[1].url, "tap on the label start")
        t.eq(PkText.linkAt(links, links[1].last).url, links[1].url, "tap on the arrow")
        t.eq(PkText.linkAt(links, 1), nil, "tap elsewhere")
        local t2, l2 = PkText.linkify("é ♟ https://lichess.org/study/abc")
        t.eq(l2[1].first, 5, "positions count characters, not bytes")
        t.eq(t2, "é ♟ lichess.org ↗", "after multibyte characters")
        local t4, l4 = PkText.linkify("(https://en.wikipedia.org/wiki/Foo_(bar)). See www.chessbase.com, or HTTPS://Lichess.org!")
        t.eq(l4[1].url, "https://en.wikipedia.org/wiki/Foo_(bar)", "outer parenthesis and dot are punctuation")
        t.eq(t4, "(en.wikipedia.org ↗). See chessbase.com ↗, or Lichess.org ↗!", "display keeps the punctuation")
        t.eq(l4[2].url, "www.chessbase.com", "bare www address")
        t.eq(l4[3].url, "HTTPS://Lichess.org", "upper-case scheme")
        local t5 = PkText.linkify("https://.")
        t.eq(t5, "link ↗.", "address without a host")
        local t3, l3 = PkText.linkify("no links here")
        t.eq(t3, "no links here", "unchanged"); t.eq(#l3, 0, "none")
    end },
}
