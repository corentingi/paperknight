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
    self.get_stmt = conn:prepare("SELECT " .. COLUMNS .. " FROM puzzles WHERE id = ?")
    return self
end

function PkPuzzlePack:count()
    return tonumber(self.conn:rowexec("SELECT count(*) FROM puzzles"))
end

function PkPuzzlePack:get(id)
    return rowToPuzzle(self.get_stmt:reset():bind(id):step())
end

local BATCH = 25

-- One random puzzle of rating band `band`: scans up to 2*BATCH candidates from
-- random key `rnd` (wrapping around), returning the first `accept`ed one.
function PkPuzzlePack:_pickInBand(band, rnd, accept)
    for _, stmt in ipairs({ self.after_stmt, self.before_stmt }) do
        stmt:reset():bind(band, rnd, BATCH)
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
--  1. an accepted puzzle within ±2 bands (home band first, then neighbours),
--  2. any puzzle within ±2 bands (e.g. all recent ones were rejected),
--  3. an accepted puzzle further away, 4. anything.
-- @param opts { random = function() -> [0,1), accept = function(p) -> bool }
function PkPuzzlePack:pickNear(rating, opts)
    opts = opts or {}
    local random = opts.random or math.random
    local home = math.floor(rating / 100)
    local near, far = { home }, {}
    for d = 1, 30 do
        local list = (d <= 2) and near or far
        list[#list + 1] = home + d
        list[#list + 1] = home - d
    end
    for _, pass in ipairs({ { near, opts.accept }, { near, nil }, { far, opts.accept }, { far, nil } }) do
        for _, band in ipairs(pass[1]) do
            if band >= 0 then
                local p = self:_pickInBand(band, math.floor(random() * 0x7FFFFFFF), pass[2])
                if p then return p end
            end
        end
    end
    return nil
end

function PkPuzzlePack:close()
    if self.conn then
        self.after_stmt:close()
        self.before_stmt:close()
        self.get_stmt:close()
        self.conn:close()
        self.conn = nil
    end
end

return PkPuzzlePack
