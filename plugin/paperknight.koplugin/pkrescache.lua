-- Resolved-moves cache for study trees (ADR-0013). Resolving every SAN of
-- a repertoire takes seconds on an e-reader; the result is saved (by
-- pkopenings.lua, in <settings>/paperknight/cache), keyed by the PGN's file
-- stamp and pksan's version, and applied to a freshly parsed study instead
-- of resolving again.
--   local text, n = PkResCache.dump(study, stamp)   -- n = resolved + illegal nodes
--   local n = PkResCache.apply(study, text, stamp)  -- nil if stale/corrupt
-- Format (one node per line, chapters in order, nodes in pre-order):
--   pkres <format>.<pksan version> <stamp>
--   c <chapter> <nodes> <start FEN>
--   <pgn san>\t-                     not resolved yet
--   <pgn san>\t!                     illegal
--   <pgn san>\t<from>\t<to>\t<promotion>\t<piece>\t<color>\t<captured>\t<flags>\t<san>\t<fen>
-- Every line repeats the PGN's SAN: a file that does not match the tree
-- node for node is rejected as a whole (nothing is applied).
local PkResCache = {}

local PkSan = require("pksan")

local VERSION = "1." .. PkSan.VERSION

-- Pre-order walk of a tree, root excluded.
local function walk(node, fn)
    for _, child in ipairs(node.children) do
        fn(child)
        walk(child, fn)
    end
end

local function count(node)
    local n = 0
    walk(node, function() n = n + 1 end)
    return n
end

--- Text of the cache for `study` (chapters not parsed yet are parsed),
-- and the number of known (resolved or illegal) nodes in it.
function PkResCache.dump(study, stamp)
    local out = { "pkres " .. VERSION .. " " .. stamp }
    local resolved = 0
    for i = 1, #study.chapters do
        local root = study:tree(i)
        out[#out + 1] = "c " .. i .. " " .. count(root) .. " " .. root.fen
        walk(root, function(node)
            local m = node.move
            if node.fen and m then
                resolved = resolved + 1
                out[#out + 1] = table.concat({ node.san, m.from, m.to, m.promotion or "", m.piece or "",
                    m.color or "", m.captured or "", m.flags or "", m.san or node.san, node.fen }, "\t")
            elseif node.error then
                resolved = resolved + 1
                out[#out + 1] = node.san .. "\t!"
            else
                out[#out + 1] = node.san .. "\t-"
            end
        end)
    end
    out[#out + 1] = ""
    return table.concat(out, "\n"), resolved
end

local function opt(s) return s ~= "" and s or nil end

local function tabs(s)
    local n = 0
    for _ in s:gmatch("\t") do n = n + 1 end
    return n
end

--- Applies cache `text` to `study` (freshly parsed). Returns the number of
-- nodes known from it (resolved or illegal), or nil and a reason if the
-- text is for another stamp or version, or does not match the tree.
function PkResCache.apply(study, text, stamp)
    if type(text) ~= "string" then return nil, "no cache" end
    local header = "pkres " .. VERSION .. " " .. stamp .. "\n"
    if text:sub(1, #header) ~= header then return nil, "stale" end
    local lines = {}
    for line in text:gmatch("([^\n]*)\n") do lines[#lines + 1] = line end
    -- 1. check the whole file against the trees (fields split later)
    local plan = {} -- { node, rest } in application order
    local k = 2
    for i = 1, #study.chapters do
        local root = study:tree(i)
        if lines[k] ~= "c " .. i .. " " .. count(root) .. " " .. root.fen then return nil, "chapter mismatch" end
        k = k + 1
        local bad = false
        walk(root, function(node)
            if bad then return end
            local line = lines[k]
            k = k + 1
            local san, rest = (line or ""):match("^([^\t]*)\t(.*)$")
            if san ~= node.san or not (rest == "-" or rest == "!" or tabs(rest) == 8) then
                bad = true
                return
            end
            plan[#plan + 1] = { node, rest }
        end)
        if bad then return nil, "node mismatch" end
    end
    if k ~= #lines + 1 then return nil, "trailing data" end
    -- 2. apply; a resolved child needs a resolved parent
    local n = 0
    for _, step in ipairs(plan) do
        local node, rest = step[1], step[2]
        if rest == "!" then
            if not node.fen then
                node.error = "illegal move " .. tostring(node.san)
                n = n + 1
            end
        elseif rest ~= "-" and node.parent.fen and not node.fen then
            local f = {}
            for field in (rest .. "\t"):gmatch("([^\t]*)\t") do f[#f + 1] = field end
            node.move = { from = f[1], to = f[2], promotion = opt(f[3]), piece = opt(f[4]),
                          color = opt(f[5]), captured = opt(f[6]), flags = opt(f[7]), san = f[8] }
            node.fen, node.ply = f[9], node.parent.ply + 1
            n = n + 1
        end
    end
    return n
end

--- Reads a cache file; returns its text or nil.
function PkResCache.read(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local text = f:read("*a")
    f:close()
    return text
end

--- Writes a cache file atomically (temporary file + rename). Returns true
-- or nil and an error.
function PkResCache.write(path, text)
    local tmp = path .. ".tmp"
    local f, err = io.open(tmp, "wb")
    if not f then return nil, err end
    local ok, werr = f:write(text)
    local cok, cerr = f:close() -- buffered: a full disk may only fail here
    if not (ok and cok) then os.remove(tmp); return nil, werr or cerr end
    local rok, rerr = os.rename(tmp, path)
    if not rok then os.remove(tmp); return nil, rerr end
    return true
end

return PkResCache
