-- Study model (ADR-0011): chapters of a PGN file, and a cursor walking a
-- chapter's move tree. SAN is resolved with the rules engine only along the
-- path the user visits; each visited node caches its move and FEN.
local PkPgn = require("pkpgn")

local START_FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

local PkStudy = {}
PkStudy.__index = PkStudy

local function known(value)
    return value and value ~= "" and value ~= "?" and value
end

--- Display name of a chapter: ChapterName, else "White – Black", else Event
-- (without a "Study name: " prefix), else "Chapter n".
function PkStudy.chapterTitle(tags, index, study_name)
    if known(tags.ChapterName) then return tags.ChapterName end
    if known(tags.White) and known(tags.Black) then return tags.White .. " – " .. tags.Black end
    local event = known(tags.Event)
    if event then
        if study_name and event:sub(1, #study_name + 2) == study_name .. ": " then
            event = event:sub(#study_name + 3)
        end
        return event
    end
    return "Chapter " .. index
end

--- Parses a study from PGN text. `fallback_name` is used without a StudyName tag.
function PkStudy.fromText(text, fallback_name)
    local self = setmetatable({}, PkStudy)
    self.chapters = PkPgn.index(text)
    local first = self.chapters[1]
    self.name = (first and known(first.tags.StudyName)) or fallback_name or "Study"
    for i, ch in ipairs(self.chapters) do
        local tags = ch.tags
        ch.index = i
        ch.title = PkStudy.chapterTitle(tags, i, self.name)
        ch.gamebook = tags.ChapterMode == "gamebook"
        ch.start_fen = (known(tags.FEN)) or START_FEN
        -- some tools write 4-field FENs: add halfmove/fullmove counters
        local n_fields = select(2, ch.start_fen:gsub("%S+", ""))
        if n_fields == 4 then ch.start_fen = ch.start_fen .. " 0 1" end
        local turn = ch.start_fen:match("^%S+%s+([wb])") or "w"
        local orientation = tags.Orientation and tags.Orientation:lower()
        if orientation ~= "white" and orientation ~= "black" then
            -- gamebook without Orientation: the student plays the side to move
            orientation = (ch.gamebook and turn == "b") and "black" or "white"
        end
        ch.orientation = orientation
    end
    return self
end

--- Reads a study from a file. Returns the study, or nil and an error:
-- "empty" (no games), "not_pgn" (no tags and no moves), or an io message.
function PkStudy.open(path)
    local f, err = io.open(path, "rb")
    if not f then return nil, err end
    local text = f:read("*a")
    f:close()
    local base = path:match("([^/]+)%.[Pp][Gg][Nn]$") or path:match("([^/]+)$")
    local study = PkStudy.fromText(text, base)
    study.path = path
    if #study.chapters == 0 then return nil, "empty" end
    local first = study.chapters[1]
    if #study.chapters == 1 and next(first.tags) == nil
        and #study:tree(1).children == 0 then
        return nil, "not_pgn"
    end
    return study
end

--- Move tree of chapter `i` (parsed on first use).
function PkStudy:tree(i)
    local ch = self.chapters[i]
    if not ch.root then
        ch.root = PkPgn.parseMovetext(ch.movetext or "")
        ch.root.fen = ch.start_fen
        local fields = {}
        for field in ch.start_fen:gmatch("%S+") do fields[#fields + 1] = field end
        local fullmove = tonumber(fields[6]) or 1
        ch.root.ply = (fullmove - 1) * 2 + ((fields[2] == "b") and 1 or 0)
    end
    return ch.root
end

----------------------------------------------------------------------------
-- Cursor
----------------------------------------------------------------------------

local Cursor = {}
Cursor.__index = Cursor
PkStudy.Cursor = Cursor

--- `game` is a Chess instance; the cursor keeps it on the current node.
function PkStudy:cursor(i, game)
    local root = self:tree(i)
    local c = setmetatable({ root = root, game = game, chapter = self.chapters[i] }, Cursor)
    if not game.load(root.fen) then
        return nil, "invalid FEN: " .. tostring(root.fen)
    end
    c.node = root
    return c
end

--- Resolves a child's SAN against its parent's position (cached).
-- Returns true, or false if the SAN is illegal there.
function Cursor:resolve(child)
    if child.fen then return true end
    if child.error then return false end
    local parent = child.parent
    if not parent.fen and not self:resolve(parent) then return false end
    -- the game normally sits on self.node: only reload for other parents
    local at_parent = (parent == self.node)
    if not at_parent then self.game.load(parent.fen) end
    local move = self.game.move(child.san)
    if move then
        child.move = move
        child.fen = self.game.fen()
        child.ply = parent.ply + 1
    else
        child.error = "illegal move " .. tostring(child.san)
    end
    if at_parent and move then
        self.game.undo()
        -- the plugin's undo keeps a redo stack: drop this internal entry
        if self.game.redo_stack then table.remove(self.game.redo_stack) end
    elseif not at_parent then
        self.game.load(self.node.fen)
    end
    return move ~= nil
end

function Cursor:_goto(node)
    self.game.load(node.fen)
    self.node = node
    return node
end

--- Moves to child `i` (1 = main line). Returns the node, or nil and an error.
function Cursor:forward(i)
    local child = self.node.children[i or 1]
    if not child then return nil, "end of line" end
    if not self:resolve(child) then return nil, child.error end
    return self:_goto(child)
end

function Cursor:back()
    if not self.node.parent then return nil end
    return self:_goto(self.node.parent)
end

function Cursor:toStart()
    return self:_goto(self.root)
end

--- Follows the current line (first children) to its end or first bad move.
-- Resolves step by step and loads the board once at the end.
function Cursor:toEnd()
    local node = self.node
    while node.children[1] do
        local child = node.children[1]
        if not child.fen then
            self.game.load(node.fen)
            self.node = node -- resolve() works relative to the game's position
            if not self:resolve(child) then break end
        end
        node = child
    end
    return self:_goto(node)
end

--- Jumps to any node of the tree (resolving the path to it).
function Cursor:jump(node)
    local reversed = {}
    local n = node
    while n.parent do reversed[#reversed + 1] = n; n = n.parent end
    if n ~= self.root then return nil, "node is not in this chapter" end
    for i = #reversed, 1, -1 do
        local step = reversed[i]
        if not self:resolve(step) then return nil, step.error end
    end
    return self:_goto(node)
end

--- Child of the current node matching a played move (from/to/promotion), or nil.
function Cursor:childForMove(from, to, promotion)
    for i, child in ipairs(self.node.children) do
        if self:resolve(child) then
            local m = child.move
            if m.from == from and m.to == to and (m.promotion or nil) == (promotion or nil) then
                return child, i
            end
        end
    end
    return nil
end

--- True if the current node is on the chapter's main line.
function Cursor:onMainline(node)
    node = node or self.node
    while node.parent do
        if node.parent.children[1] ~= node then return false end
        node = node.parent
    end
    return true
end

--- "12. Nf3" / "12... Nf6" for a resolved node (SAN from the rules engine).
function PkStudy.moveLabel(node, with_glyphs)
    if not node.parent then return "" end
    local san = node.move and node.move.san or node.san
    local before = node.parent.ply
    if not before then return san end -- unresolved: no reliable move number
    local number = math.floor(before / 2) + 1
    local label = (before % 2 == 0) and (number .. ". " .. san) or (number .. "... " .. san)
    if with_glyphs ~= false and node.glyphs then
        -- move glyphs ($1-$6: !, ?, !!, ??, !?, ?!) stick to the move,
        -- position glyphs (+=, ±, ...) follow after a space
        local move_g, pos_g = {}, {}
        for _, nag in ipairs(node.glyphs) do
            table.insert(nag <= 6 and move_g or pos_g, nag)
        end
        label = label .. PkPgn.glyphText(move_g):gsub(" ", "")
        if #pos_g > 0 then label = label .. " " .. PkPgn.glyphText(pos_g) end
    end
    return label
end

return PkStudy
