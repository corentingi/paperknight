-- PGN reader for studies (ADR-0011, docs/studies.md). Pure Lua, no rules engine:
--   PkPgn.index(text)          -> list of chapters { tags = {...}, movetext = "..." }
--                                 (tag sections only, movetext kept as a string)
--   PkPgn.parseMovetext(text)  -> root node of the move tree
-- A node is { san, glyphs = {...}, comment, shapes = { circles, arrows },
-- children = { mainline, variation, ... }, parent }. The root has no san;
-- its comment is the chapter introduction.
local PkPgn = {}

----------------------------------------------------------------------------
-- Chapter index
----------------------------------------------------------------------------

local function unescape(value)
    return (value:gsub('\\(["\\])', "%1"))
end

-- Returns a list of {name, value} if the whole line is made of tag pairs
-- (several tags on one line are allowed), else nil.
local function parseTagLine(line)
    local tags, pos = {}, 1
    while true do
        local _, open, name = line:find('^%s*%[%s*([%w_]+)%s+"', pos)
        if not open then break end
        -- the value ends at the first quote not escaped by a backslash
        -- (a pattern can't tell `\"` from `\\"`: a value ending in a backslash)
        local i, close = open + 1, nil
        while true do
            local q = line:find('["\\]', i)
            if not q then break end
            if line:sub(q, q) == "\\" then i = q + 2 else close = q; break end
        end
        if not close then break end
        local _, e = line:find('^%s*%]', close + 1)
        if not e then break end
        tags[#tags + 1] = { name, unescape(line:sub(open + 1, close - 1)) }
        pos = e + 1
    end
    if #tags > 0 and line:sub(pos):match("^%s*$") then return tags end
end

--- Splits a (multi-game) PGN into chapters. Lines starting with "[" inside a
-- brace comment are not mistaken for tags.
function PkPgn.index(text)
    text = text:gsub("^\239\187\191", "") -- UTF-8 byte order mark
    local chapters = {}
    local current
    local state = "between" -- between | tags | moves
    local in_comment = false
    local prev_blank = true
    local moves = {}

    local function finish()
        if current then
            current.movetext = table.concat(moves, "\n")
            chapters[#chapters + 1] = current
        end
        current, moves = nil, {}
    end

    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        line = line:gsub("\r$", "")
        local tags
        if line:sub(1, 1) == "[" and (not in_comment or prev_blank) then
            tags = parseTagLine(line)
            -- an unterminated "{" must not swallow the following games: a tag
            -- line after a blank line ends it
            if tags and in_comment then in_comment = false end
        end
        local blank = line:match("^%s*$") ~= nil
        if tags then
            if state ~= "tags" then
                finish()
                current = { tags = {} }
                state = "tags"
            end
            for _, tag in ipairs(tags) do current.tags[tag[1]] = tag[2] end
        elseif line:sub(1, 1) == "%" and not in_comment then -- PGN escape line
            -- ignored
        elseif blank and not in_comment then
            if state == "tags" then state = "moves" end
        else
            if not current then current = { tags = {} } end -- movetext without tags
            state = "moves"
            moves[#moves + 1] = line
            -- track brace comments across lines (braces don't nest in PGN);
            -- a ';' comment hides braces until the end of the line
            for ch_pos = 1, #line do
                local ch = line:sub(ch_pos, ch_pos)
                if in_comment then
                    if ch == "}" then in_comment = false end
                elseif ch == "{" then
                    in_comment = true
                elseif ch == ";" then
                    break
                end
            end
        end
        prev_blank = blank
    end
    finish()
    return chapters
end

----------------------------------------------------------------------------
-- Comments: shapes and commands
----------------------------------------------------------------------------

--- Extracts [%csl ...] / [%cal ...] shapes and drops other [%...] commands
-- (anno, clk, eval, emt, ...). Returns cleaned text (or nil) and shapes.
--- `wrapped`: the movetext was wrapped by a tool (PkPgn.isWrapped): single
-- newlines are then joined (except before list items); otherwise they are the
-- author's line breaks (Lichess does not wrap) and are kept.
function PkPgn.cleanComment(raw, shapes, wrapped)
    shapes = shapes or { circles = {}, arrows = {} }
    raw = raw:gsub("[ \t]+", " "):gsub(" *\n *", "\n")
    if wrapped then raw = PkPgn.joinWrappedLines(raw) end
    local text = raw:gsub("%[%%(%w+)%s*([^%]]*)%]", function(cmd, args)
        if cmd == "csl" then
            for brush, sq in args:gmatch("([GRYBgryb])([a-h][1-8])") do
                shapes.circles[#shapes.circles + 1] = { brush = brush:upper(), square = sq }
            end
        elseif cmd == "cal" then
            for brush, from, to in args:gmatch("([GRYBgryb])([a-h][1-8])([a-h][1-8])") do
                shapes.arrows[#shapes.arrows + 1] = { brush = brush:upper(), from = from, to = to }
            end
        end
        return ""
    end)
    -- tidy whitespace but keep paragraph breaks
    text = text:gsub("[ \t]+", " "):gsub(" *\n *", "\n"):gsub("\n\n\n+", "\n\n")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then text = nil end
    return text, shapes
end

-- PGN tools (ChessBase, pgn-extract, python-chess…) wrap movetext at 80
-- columns, so a comment's single newlines are not the author's; Lichess
-- writes each line in full (often hundreds of characters) and keeps the
-- author's line breaks. Decided per chapter from the movetext lines.
local WRAP_WIDTH = 80

local function ulen(s)
    local _, n = s:gsub("[^\128-\191]", "")
    return n
end

--- True if `movetext` looks wrapped by a tool: several lines, none longer
-- than 80 characters, and most of them filled close to that width (a tool
-- breaks a line only when the next word would not fit; a short Lichess
-- chapter has short lines).
function PkPgn.isWrapped(movetext)
    local lens = {}
    for line in (movetext .. "\n"):gmatch("([^\n]*)\n") do
        line = line:gsub("\r$", "")
        if line ~= "" then
            local n = ulen(line)
            if n > WRAP_WIDTH then return false end
            lens[#lens + 1] = n
        end
    end
    if #lens < 3 then return false end -- e.g. one line + the result
    local full = 0
    for i = 1, #lens - 1 do -- the last line of a text is naturally short
        if lens[i] >= WRAP_WIDTH - 20 then full = full + 1 end
    end
    return full >= 0.75 * (#lens - 1)
end

-- (not "12. Nf3": in wrapped movetext a numbered line is usually a move)
local function startsItem(line)
    return line:match("^[-*•–] ") ~= nil
end

--- Joins the single newlines of a wrapped comment (paragraphs and list
-- items keep their breaks).
function PkPgn.joinWrappedLines(text)
    local out = {}
    local prev
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        if prev == nil then
            out[#out + 1] = line
        elseif line == "" or prev == "" or startsItem(line) then
            out[#out + 1] = "\n" .. line
        else
            out[#out + 1] = " " .. line
        end
        prev = line
    end
    return table.concat(out)
end

----------------------------------------------------------------------------
-- Glyphs
----------------------------------------------------------------------------

-- ASCII/Latin-1 forms: e-reader fonts may lack the Unicode chess symbols.
PkPgn.NAG_SYMBOLS = {
    [1] = "!", [2] = "?", [3] = "!!", [4] = "??", [5] = "!?", [6] = "?!",
    [7] = "(only move)", [10] = "=", [13] = "unclear", [14] = "+=", [15] = "=+",
    [16] = "±", [17] = "-/+", [18] = "+-", [19] = "-+", [22] = "zugzwang", [23] = "zugzwang",
    [32] = "(development)", [33] = "(development)", [36] = "(initiative)", [37] = "(initiative)",
    [40] = "(attack)", [41] = "(attack)", [132] = "(counterplay)", [133] = "(counterplay)",
    [138] = "(time trouble)", [139] = "(time trouble)", [140] = "(with the idea)", [146] = "(novelty)",
}

-- Position assessments in words, for the text panel (NAG_SYMBOLS keeps the
-- compact form for move lists).
PkPgn.POSITION_WORDS = {
    [7] = "Only move", [10] = "Equal position", [13] = "Unclear position",
    [14] = "White is slightly better", [15] = "Black is slightly better",
    [16] = "White is better", [17] = "Black is better",
    [18] = "White is winning", [19] = "Black is winning",
    [22] = "Zugzwang (White)", [23] = "Zugzwang (Black)",
    [32] = "White has a development advantage", [33] = "Black has a development advantage",
    [36] = "White has the initiative", [37] = "Black has the initiative",
    [40] = "White has the attack", [41] = "Black has the attack",
    [132] = "White has counterplay", [133] = "Black has counterplay",
    [138] = "White is in time trouble", [139] = "Black is in time trouble",
    [140] = "With the idea", [146] = "Novelty",
}

--- Position glyphs of a node in words ("White is better"), or nil.
function PkPgn.positionWords(glyphs)
    local words = {}
    for _, nag in ipairs(glyphs or {}) do
        if nag > 6 and PkPgn.POSITION_WORDS[nag] then words[#words + 1] = PkPgn.POSITION_WORDS[nag] end
    end
    return #words > 0 and table.concat(words, ". ") or nil
end

local INLINE_TO_NAG = { ["!"] = 1, ["?"] = 2, ["!!"] = 3, ["??"] = 4, ["!?"] = 5, ["?!"] = 6 }

-- Shape of a SAN move (check marks and annotations already stripped or allowed).
local function looksLikeSan(san)
    return san:match("^[KQRBN]?[a-h]?[1-8]?x?[a-h][1-8]=?[QRBNqrbn]?[+#]?$") ~= nil
        or san:match("^O%-O%-O[+#]?$") ~= nil or san:match("^O%-O[+#]?$") ~= nil
        or san:match("^%-%-$") ~= nil -- null move (resolves to an error at that node)
end

----------------------------------------------------------------------------
-- Movetext
----------------------------------------------------------------------------

local function newNode(parent, san)
    return { san = san, glyphs = {}, children = {}, parent = parent }
end

local function addComment(node, raw, wrapped)
    node.shapes = node.shapes or { circles = {}, arrows = {} }
    local text = PkPgn.cleanComment(raw, node.shapes, wrapped)
    if text then
        node.comment = node.comment and (node.comment .. "\n" .. text) or text
    end
end

--- Parses movetext into a tree. Unknown tokens are skipped; unbalanced
-- parentheses are tolerated (a ')' without '(' is ignored, open variations
-- are closed at the end).
function PkPgn.parseMovetext(text)
    local wrapped = PkPgn.isWrapped(text)
    local root = newNode(nil, nil)
    -- `last`: node of the last move in the current line (root at start).
    -- `stack`: saved `last` of the enclosing lines when entering a variation.
    local last, stack = root, {}
    local pending_comment -- comment before the first move of a variation
    local at_line_start = true -- no move yet in the current line (game or variation)
    -- where the current line's first move goes among `last`'s children when a
    -- variation was opened before it (it stays first: the main line)
    local insert_at
    local pos, len = 1, #text

    while pos <= len do
        local ch = text:sub(pos, pos)
        if ch:match("%s") then
            pos = pos + 1
        elseif ch == "{" then
            local close = text:find("}", pos + 1, true) or (len + 1)
            local raw = text:sub(pos + 1, close - 1)
            if at_line_start and #stack == 0 then
                addComment(root, raw, wrapped) -- chapter introduction
            elseif at_line_start then
                pending_comment = (pending_comment and pending_comment .. "\n" or "") .. raw
            else
                addComment(last, raw, wrapped)
            end
            pos = close + 1
        elseif ch == ";" then
            local eol = text:find("\n", pos + 1, true) or (len + 1)
            local raw = text:sub(pos + 1, eol - 1)
            if at_line_start and #stack == 0 then
                addComment(root, raw, wrapped)
            elseif at_line_start then
                pending_comment = (pending_comment and pending_comment .. "\n" or "") .. raw
            else
                addComment(last, raw, wrapped)
            end
            pos = eol + 1
        elseif ch == "(" then
            -- a variation is an alternative to `last`: its moves branch from
            -- last.parent. Opened before any move of the current line (at the
            -- start of the game, or "( (" ), it is an alternative to the move
            -- that comes next: it branches from `last`, and that move will be
            -- inserted before it. The enclosing line's state is saved, restored
            -- at ")".
            local frame = { last = last, at_line_start = at_line_start, pending = pending_comment }
            if at_line_start then
                frame.insert_at = insert_at or (#last.children + 1)
            else
                last = last.parent or root
            end
            stack[#stack + 1] = frame
            pending_comment, insert_at = nil, nil
            at_line_start = true
            pos = pos + 1
        elseif ch == ")" then
            if #stack > 0 then
                local frame = table.remove(stack)
                last, at_line_start, pending_comment = frame.last, frame.at_line_start, frame.pending
                insert_at = frame.insert_at
            else
                pending_comment = nil
            end
            pos = pos + 1
        elseif ch == "$" then
            local digits = text:match("^%$(%d+)", pos)
            if digits and last ~= root and not at_line_start then
                table.insert(last.glyphs, tonumber(digits))
            end
            pos = pos + 1 + (digits and #digits or 0)
        else
            local token = text:match("^[^%s{}();$]+", pos)
            if not token then -- stray "}" or similar: skip it
                pos = pos + 1
            elseif token:match("^[!?]+$") then -- glyph separated from its move ("e4 !")
                pos = pos + #token
                if INLINE_TO_NAG[token] and last ~= root and not at_line_start then
                    table.insert(last.glyphs, INLINE_TO_NAG[token])
                end
            elseif token:match("^%d+%.+$") or token:match("^%.+$") then -- move number "12." / "12..."
                pos = pos + #token
                -- skip
            elseif token == "1-0" or token == "0-1" or token == "1/2-1/2" or token == "*" then
                pos = pos + #token -- result
            else
                pos = pos + #token
                local num_stripped = token:gsub("^%d+%.+", "") -- "12.e4" written without space
                local san, suffix = num_stripped:match("^(.-)([!?]*)$")
                san = san:gsub("^0%-0%-0", "O-O-O"):gsub("^0%-0", "O-O")
                if looksLikeSan(san) then -- skips "e.p.", stray symbols, etc.
                    local node = newNode(last, san)
                    if INLINE_TO_NAG[suffix] then node.glyphs[1] = INLINE_TO_NAG[suffix] end
                    if insert_at then
                        table.insert(last.children, insert_at, node)
                        insert_at = nil
                    else
                        table.insert(last.children, node)
                    end
                    if pending_comment then
                        addComment(node, pending_comment, wrapped)
                        pending_comment = nil
                    end
                    at_line_start = false
                    last = node
                end
            end
        end
    end
    return root
end

--- Glyph string for display, e.g. "!? +=". Move glyphs first.
function PkPgn.glyphText(glyphs)
    local parts = {}
    for _, nag in ipairs(glyphs or {}) do
        parts[#parts + 1] = PkPgn.NAG_SYMBOLS[nag] or ("$" .. nag)
    end
    return table.concat(parts, " ")
end

return PkPgn
