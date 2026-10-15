-- Read-only access to a puzzles pack (docs/pack-format.md, format_version 1).
local SQ3 = require("lua-ljsqlite3/init")

local SUPPORTED_FORMAT = 1

local PkPuzzlePack = {}
PkPuzzlePack.__index = PkPuzzlePack

local COLUMNS = "id, fen, moves, solver, rating, themes, opening, game_url, rating_dev"
local RND = 10 -- the key column, selected after COLUMNS by the range queries

local function rowToPuzzle(row)
    if not row then return nil end
    return {
        id = row[1], fen = row[2], moves = row[3], solver = row[4],
        rating = tonumber(row[5]), -- lua-ljsqlite3 returns INTEGER as int64 cdata
        themes = row[6], opening = row[7], game_url = row[8],
        rating_dev = tonumber(row[9]),
    }
end

--- Opens a pack. Returns the pack, or nil and an error message.
local BATCH = 100 -- candidates read per query (paged: the whole band can be scanned)
local KEY_END = 0x80000000 -- keys (rnd) are 31-bit

function PkPuzzlePack.open(path)
    local f = io.open(path, "rb")
    if not f then return nil, "pack not found: " .. path end
    f:close()
    local ok, conn = pcall(SQ3.open, path, "ro")
    if not ok then return nil, "cannot open pack: " .. tostring(conn) end
    local ok_meta, kind, version = pcall(function()
        return conn:rowexec("SELECT value FROM meta WHERE key = 'kind'"),
               conn:rowexec("SELECT value FROM meta WHERE key = 'format_version'")
    end)
    if not ok_meta or kind ~= "puzzles" then
        conn:close()
        return nil, "not a puzzles pack: " .. path
    end
    if tonumber(version) ~= SUPPORTED_FORMAT then
        conn:close()
        return nil, ("unsupported puzzles pack format %s (expected %d)"):format(tostring(version), SUPPORTED_FORMAT)
    end
    local self = setmetatable({ conn = conn, path = path, batch = BATCH }, PkPuzzlePack)
    -- Candidates of a band in random-key order, between two keys (paged).
    self.range_stmt = conn:prepare("SELECT " .. COLUMNS .. ", rnd FROM puzzles"
        .. " WHERE band = ? AND rnd >= ? AND rnd < ? ORDER BY rnd LIMIT ?")
    -- Same, restricted to a theme through the puzzle_themes index.
    self.theme_range_stmt = conn:prepare("SELECT " .. COLUMNS:gsub("([%w_]+)", "p.%1") .. ", t.rnd"
        .. " FROM puzzle_themes t JOIN puzzles p ON p.id = t.puzzle_id"
        .. " WHERE t.theme = ? AND t.band = ? AND t.rnd >= ? AND t.rnd < ? ORDER BY t.rnd LIMIT ?")
    self.get_stmt = conn:prepare("SELECT " .. COLUMNS .. " FROM puzzles WHERE id = ?")
    self.themes_stmt = conn:prepare("SELECT themes FROM puzzles WHERE id = ?")
    -- the bands the pack has: the pick never queries the others
    local lo, hi = conn:rowexec("SELECT min(band), max(band) FROM puzzles")
    self.min_band, self.max_band = tonumber(lo) or 0, tonumber(hi) or -1
    return self
end

function PkPuzzlePack:count()
    return tonumber(self.conn:rowexec("SELECT count(*) FROM puzzles"))
end

--- True if the pack has no puzzle (without counting them all).
function PkPuzzlePack:isEmpty()
    return tonumber(self.conn:rowexec("SELECT EXISTS (SELECT 1 FROM puzzles)")) == 0
end

function PkPuzzlePack:get(id)
    local p = rowToPuzzle(self.get_stmt:reset():bind(id):step())
    self.get_stmt:reset() -- don't keep a read transaction open between calls
    return p
end

--- The theme tags of puzzle `id` ("fork pin ..."), nil if not in the pack.
function PkPuzzlePack:themesOf(id)
    local row = self.themes_stmt:reset():bind(id):step()
    local themes = row and row[1] or nil
    self.themes_stmt:reset()
    return themes
end


-- One random puzzle of rating band `band`: candidates in key order from the
-- random key `rnd` to the end, then from the start up to `rnd` (wrapping
-- around), returning the first `accept`ed one. Paged by BATCH, so that a
-- band's fresh puzzles are found wherever their keys are.
function PkPuzzlePack:_pickInBand(band, rnd, accept, theme)
    local stmt = theme and self.theme_range_stmt or self.range_stmt
    for _, window in ipairs({ { rnd, KEY_END }, { 0, rnd } }) do
        local lo, hi = window[1], window[2]
        while lo < hi do
            local batch = self.batch
            if theme then stmt:reset():bind(theme, band, lo, hi, batch) else stmt:reset():bind(band, lo, hi, batch) end
            local n, last = 0, nil
            local row = stmt:step()
            while row do
                n = n + 1
                last = tonumber(row[RND])
                local p = rowToPuzzle(row)
                if not accept or accept(p) then
                    stmt:reset()
                    return p
                end
                row = stmt:step()
            end
            if n < batch then break end
            lo = last + 1
        end
    end
    stmt:reset()
    return nil
end

--- Picks a random puzzle near `rating`. Preference order (ADR-0010):
--  1. a fresh puzzle within ±2 bands (home band first, then neighbours),
--  2. a fresh puzzle further away (nearest bands first),
--  3. a stale one within ±2 bands, 4. a stale one further away.
-- `accept` is a hard filter, `fresh` a soft one (dropped in steps 3-4, e.g.
-- once every puzzle of a theme was played recently).
-- @param opts { random = function() -> [0,1), accept = function(p) -> bool,
--                fresh = function(p) -> bool,
--                theme = key or nil (only puzzles carrying this theme) }
-- @return the puzzle (or nil), and whether it is fresh
function PkPuzzlePack:pickNear(rating, opts)
    opts = opts or {}
    local random = opts.random or math.random
    local accept, fresh = opts.accept, opts.fresh
    local function both(p)
        return (not accept or accept(p)) and (not fresh or fresh(p))
    end
    local home = math.floor(rating / 100)
    local near, far = { home }, {}
    for d = 1, 30 do
        local list = (d <= 2) and near or far
        list[#list + 1] = home + d
        list[#list + 1] = home - d
    end
    for _, pass in ipairs({ { near, both, true }, { far, both, true }, { near, accept, false }, { far, accept, false } }) do
        for _, band in ipairs(pass[1]) do
            if band >= self.min_band and band <= self.max_band then
                local p = self:_pickInBand(band, math.floor(random() * 0x7FFFFFFF), pass[2], opts.theme)
                if p then return p, pass[3] or not fresh or fresh(p) end
            end
        end
    end
    return nil
end

--- Themes present in the pack: { {theme=key, count=n}, ... } (unordered).
function PkPuzzlePack:themes()
    local out = {}
    local stmt = self.conn:prepare("SELECT theme, count FROM themes")
    local row = stmt:step()
    while row do
        out[#out + 1] = { theme = row[1], count = tonumber(row[2]) }
        row = stmt:step()
    end
    stmt:close()
    return out
end

function PkPuzzlePack:close()
    if self.conn then
        self.range_stmt:close()
        self.theme_range_stmt:close()
        self.get_stmt:close()
        self.themes_stmt:close()
        self.conn:close()
        self.conn = nil
    end
end

return PkPuzzlePack
