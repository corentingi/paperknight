-- Read-only access to a puzzles pack (docs/pack-format.md, format_version 1).
local SQ3 = require("lua-ljsqlite3/init")

local SUPPORTED_FORMAT = 1

local PkPuzzlePack = {}
PkPuzzlePack.__index = PkPuzzlePack

local COLUMNS = "id, fen, moves, solver, rating, themes, opening, game_url"

local function rowToPuzzle(row)
    if not row then return nil end
    return {
        id = row[1], fen = row[2], moves = row[3], solver = row[4],
        rating = tonumber(row[5]), -- lua-ljsqlite3 returns INTEGER as int64 cdata
        themes = row[6], opening = row[7], game_url = row[8],
    }
end

--- Opens a pack. Returns the pack, or nil and an error message.
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
    local self = setmetatable({ conn = conn, path = path }, PkPuzzlePack)
    -- Candidates in random-key order from a random start, then wrapping around.
    local base = "SELECT " .. COLUMNS .. " FROM puzzles WHERE band = ? AND "
    self.after_stmt = conn:prepare(base .. "rnd >= ? ORDER BY rnd LIMIT ?")
    self.before_stmt = conn:prepare(base .. "rnd < ? ORDER BY rnd LIMIT ?")
    -- Same, restricted to a theme through the puzzle_themes index.
    local tbase = "SELECT " .. COLUMNS:gsub("([%w_]+)", "p.%1") .. " FROM puzzle_themes t"
        .. " JOIN puzzles p ON p.id = t.puzzle_id WHERE t.theme = ? AND t.band = ? AND "
    self.theme_after_stmt = conn:prepare(tbase .. "t.rnd >= ? ORDER BY t.rnd LIMIT ?")
    self.theme_before_stmt = conn:prepare(tbase .. "t.rnd < ? ORDER BY t.rnd LIMIT ?")
    self.get_stmt = conn:prepare("SELECT " .. COLUMNS .. " FROM puzzles WHERE id = ?")
    return self
end

function PkPuzzlePack:count()
    return tonumber(self.conn:rowexec("SELECT count(*) FROM puzzles"))
end

function PkPuzzlePack:get(id)
    return rowToPuzzle(self.get_stmt:reset():bind(id):step())
end

local BATCH = 100 -- candidates scanned per direction (enough to find fresh ones in a theme)

-- One random puzzle of rating band `band`: scans up to 2*BATCH candidates from
-- random key `rnd` (wrapping around), returning the first `accept`ed one.
function PkPuzzlePack:_pickInBand(band, rnd, accept, theme)
    local stmts = theme and { self.theme_after_stmt, self.theme_before_stmt }
        or { self.after_stmt, self.before_stmt }
    for _, stmt in ipairs(stmts) do
        if theme then
            stmt:reset():bind(theme, band, rnd, BATCH)
        else
            stmt:reset():bind(band, rnd, BATCH)
        end
        local row = stmt:step()
        while row do
            local p = rowToPuzzle(row)
            if not accept or accept(p) then return p end
            row = stmt:step()
        end
    end
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
            if band >= 0 then
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
        self.after_stmt:close()
        self.before_stmt:close()
        self.theme_after_stmt:close()
        self.theme_before_stmt:close()
        self.get_stmt:close()
        self.conn:close()
        self.conn = nil
    end
end

return PkPuzzlePack
