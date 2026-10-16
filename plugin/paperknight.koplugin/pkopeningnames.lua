-- Opening names ("C50 Italian Game") by position, from data/openings.tsv
-- (Lichess chess-openings, CC0; built by `python -m paperknight_pipeline
-- openings`). Loaded on first use, kept for the session (~4000 names).
-- A position is keyed by the FEN's first three fields (pieces, side to
-- move, castling): no en passant square, which FEN writers set differently.
local PkOpeningNames = {}

local names -- key -> "ECO Name"; false if the file cannot be read

local function load()
    if names ~= nil then return names end
    local path = PkOpeningNames.path or (require("pkicons").plugin_dir .. "/data/openings.tsv")
    local f = io.open(path, "rb")
    if not f then
        require("logger").warn("Paperknight: no opening names:", path)
        names = false
        return names
    end
    names = {}
    for line in f:lines() do
        local key, eco, name = line:match("^([^\t#][^\t]*)\t([^\t]+)\t([^\t]+)$")
        if key then names[key] = eco .. " " .. name end
    end
    f:close()
    return names
end

--- The lookup key of a FEN.
function PkOpeningNames.key(fen)
    return fen and fen:match("^(%S+ %S+ %S+)")
end

--- The name of this exact position, or nil.
function PkOpeningNames.of(fen)
    local t = load()
    local key = t and PkOpeningNames.key(fen)
    return key and t[key] or nil
end

--- The name of the last named position among `fens` (from the start of a
-- line to the position shown), or nil: a line keeps its opening's name
-- once it leaves the book.
function PkOpeningNames.latest(fens)
    for i = #fens, 1, -1 do
        local name = PkOpeningNames.of(fens[i])
        if name then return name end
    end
    return nil
end

--- The same for a node of a study tree (pkpgn: node.fen once resolved,
-- node.parent), the result cached in the node.
function PkOpeningNames.forNode(node)
    local n = node
    while n do
        if n._opening == nil then n._opening = PkOpeningNames.of(n.fen) or false end
        if n._opening then return n._opening end
        n = n.parent
    end
    return nil
end

return PkOpeningNames
