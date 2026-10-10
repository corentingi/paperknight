-- User puzzle rating and attempt history (ADR-0010), in a writable SQLite file
-- kept apart from the read-only packs so packs can be replaced freely.
local SQ3 = require("lua-ljsqlite3/init")

local START_RATING = 1200
local MIN_RATING, MAX_RATING = 400, 3000
local PROVISIONAL_ATTEMPTS, K_PROVISIONAL, K_ESTABLISHED = 20, 60, 30

local PkProgress = {}
PkProgress.__index = PkProgress

local SCHEMA = [[
CREATE TABLE IF NOT EXISTS kv (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS attempts (
    puzzle_id     TEXT NOT NULL,
    ts            INTEGER NOT NULL,
    solved        INTEGER NOT NULL,
    mistakes      INTEGER NOT NULL,
    used_help     INTEGER NOT NULL,
    puzzle_rating INTEGER NOT NULL,
    rating_before INTEGER NOT NULL,
    rating_after  INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS attempts_puzzle_ts ON attempts (puzzle_id, ts);
CREATE TABLE IF NOT EXISTS rep_cards (
    rep        TEXT NOT NULL,     -- repertoire file name
    fen        TEXT NOT NULL,     -- normalized FEN (pkrepertoire)
    move       TEXT NOT NULL,     -- expected move (UCI)
    due        INTEGER NOT NULL,  -- day number (pksrs)
    interval   INTEGER NOT NULL,
    ease       REAL NOT NULL,
    reps       INTEGER NOT NULL,
    lapses     INTEGER NOT NULL,
    last       INTEGER NOT NULL,  -- timestamp
    introduced INTEGER NOT NULL,  -- day number
    PRIMARY KEY (rep, fen)
);
CREATE TABLE IF NOT EXISTS puzzle_reviews (
    puzzle_id TEXT PRIMARY KEY,
    due       INTEGER NOT NULL,  -- day number (pksrs)
    step      INTEGER NOT NULL,  -- clean solves in a row (pkpuzzlereview)
    lapses    INTEGER NOT NULL,
    missed    INTEGER NOT NULL   -- timestamp of the first miss
);
CREATE INDEX IF NOT EXISTS puzzle_reviews_due ON puzzle_reviews (due);
]]

--- Pure rating update. Returns the new rating (integer).
function PkProgress.updatedRating(rating, puzzle_rating, success, attempts_so_far)
    local expected = 1 / (1 + 10 ^ ((puzzle_rating - rating) / 400))
    local k = (attempts_so_far < PROVISIONAL_ATTEMPTS) and K_PROVISIONAL or K_ESTABLISHED
    local new = rating + k * ((success and 1 or 0) - expected)
    new = math.floor(new + 0.5)
    return math.max(MIN_RATING, math.min(MAX_RATING, new))
end

function PkProgress.open(path)
    local dir = path:match("(.*)/")
    if dir then
        local ok, lfs = pcall(require, "libs/libkoreader-lfs")
        if ok and lfs.attributes(dir, "mode") ~= "directory" then lfs.mkdir(dir) end
    end
    local conn = SQ3.open(path)
    conn:exec(SCHEMA)
    local self = setmetatable({ conn = conn, path = path }, PkProgress)
    self.insert_stmt = conn:prepare("INSERT INTO attempts VALUES (?, ?, ?, ?, ?, ?, ?, ?)")
    self.recent_stmt = conn:prepare("SELECT 1 FROM attempts WHERE puzzle_id = ? AND ts >= ? LIMIT 1")
    self.kv_stmt = conn:prepare("INSERT OR REPLACE INTO kv (key, value) VALUES ('rating', ?)")
    return self
end

function PkProgress:rating()
    local v = self.conn:rowexec("SELECT value FROM kv WHERE key = 'rating'")
    return tonumber(v) or START_RATING
end

--- Small settings stored next to the progress (e.g. the chosen puzzle theme).
function PkProgress:getSetting(key)
    local stmt = self.conn:prepare("SELECT value FROM kv WHERE key = ?")
    local row = stmt:reset():bind("setting." .. key):step()
    stmt:close()
    return row and row[1] or nil
end

--- Keys (without the "setting." prefix) of settings starting with `prefix`.
function PkProgress:settingKeys(prefix)
    local keys = {}
    -- instr, not substr with a byte length: SQLite counts characters, and
    -- file names in keys are often non-ASCII ("Étude.pgn", emojis)
    local stmt = self.conn:prepare("SELECT key FROM kv WHERE instr(key, ?) = 1")
    local full = "setting." .. prefix
    stmt:reset():bind(full)
    for row in stmt:rows() do keys[#keys + 1] = row[1]:sub(#"setting." + 1) end
    stmt:close()
    return keys
end

function PkProgress:setSetting(key, value)
    local stmt
    if value == nil then
        stmt = self.conn:prepare("DELETE FROM kv WHERE key = ?")
        stmt:reset():bind("setting." .. key):step()
    else
        stmt = self.conn:prepare("INSERT OR REPLACE INTO kv (key, value) VALUES (?, ?)")
        stmt:reset():bind("setting." .. key, tostring(value)):step()
    end
    stmt:close()
end

function PkProgress:attemptCount()
    return tonumber(self.conn:rowexec("SELECT count(*) FROM attempts"))
end

--- Every recorded attempt, oldest first: { {puzzle_id, clean, puzzle_rating} }
-- (clean: solved without a mistake or help, as counted by the rating).
function PkProgress:attempts()
    local out = {}
    local stmt = self.conn:prepare("SELECT puzzle_id, solved, mistakes, used_help, puzzle_rating"
        .. " FROM attempts ORDER BY ts")
    local row = stmt:step()
    while row do
        out[#out + 1] = {
            puzzle_id = row[1],
            clean = tonumber(row[2]) == 1 and tonumber(row[3]) == 0 and tonumber(row[4]) == 0,
            puzzle_rating = tonumber(row[5]),
        }
        row = stmt:step()
    end
    stmt:close()
    return out
end

function PkProgress:wasAttemptedSince(puzzle_id, since_ts)
    local row = self.recent_stmt:reset():bind(puzzle_id, since_ts):step()
    self.recent_stmt:reset() -- don't keep a read transaction open between calls
    return row ~= nil
end

--- Records a finished attempt and updates the rating.
-- @param result { puzzle_id, puzzle_rating, success, solved, mistakes, used_help, ts }
-- @return rating_before, rating_after
function PkProgress:record(result)
    local before = self:rating()
    local after = PkProgress.updatedRating(before, result.puzzle_rating, result.success, self:attemptCount())
    self.conn:exec("BEGIN")
    local ok, err = pcall(function()
        self.insert_stmt:reset():bind(result.puzzle_id, result.ts or os.time(),
            result.solved and 1 or 0, result.mistakes or 0, result.used_help and 1 or 0,
            result.puzzle_rating, before, after):step()
        self.kv_stmt:reset():bind(tostring(after)):step()
    end)
    if not ok then
        self.conn:exec("ROLLBACK")
        error(err)
    end
    self.conn:exec("COMMIT")
    return before, after
end

----------------------------------------------------------------------------
-- Repertoire cards (ADR-0012)
----------------------------------------------------------------------------

--- Stored cards of repertoire `rep`: fen -> { move, due, interval, ease, reps,
-- lapses, last, introduced } (never-seen cards are absent).
function PkProgress:loadCards(rep)
    local cards = {}
    local stmt = self.conn:prepare("SELECT fen, move, due, interval, ease, reps, lapses, last, introduced"
        .. " FROM rep_cards WHERE rep = ?")
    stmt:reset():bind(rep)
    for row in stmt:rows() do
        cards[row[1]] = {
            move = row[2], due = tonumber(row[3]), interval = tonumber(row[4]), ease = tonumber(row[5]),
            reps = tonumber(row[6]), lapses = tonumber(row[7]), last = tonumber(row[8]),
            introduced = tonumber(row[9]),
        }
    end
    stmt:close()
    return cards
end

--- Saves the state of one card (an introduced or reviewed card).
function PkProgress:saveCard(rep, fen, move, card)
    local stmt = self.conn:prepare("INSERT OR REPLACE INTO rep_cards VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)")
    stmt:reset():bind(rep, fen, move, card.due, card.interval, card.ease, card.reps, card.lapses,
        card.last, card.introduced or card.due):step()
    stmt:close()
end

--- Number of cards of `rep` introduced on day `day` (daily new-card cap).
function PkProgress:introducedOn(rep, day)
    local stmt = self.conn:prepare("SELECT count(*) FROM rep_cards WHERE rep = ? AND introduced = ?")
    local row = stmt:reset():bind(rep, day):step()
    stmt:close()
    return tonumber(row[1])
end

----------------------------------------------------------------------------
-- Missed-puzzle reviews (ADR-0014)
----------------------------------------------------------------------------

local function reviewRow(row)
    return { puzzle_id = row[1], due = tonumber(row[2]), step = tonumber(row[3]),
             lapses = tonumber(row[4]), missed = tonumber(row[5]) }
end

function PkProgress:getReview(puzzle_id)
    local stmt = self.conn:prepare("SELECT puzzle_id, due, step, lapses, missed FROM puzzle_reviews WHERE puzzle_id = ?")
    local row = stmt:reset():bind(puzzle_id):step()
    stmt:close()
    return row and reviewRow(row) or nil
end

function PkProgress:saveReview(puzzle_id, card)
    local stmt = self.conn:prepare("INSERT OR REPLACE INTO puzzle_reviews VALUES (?, ?, ?, ?, ?)")
    stmt:reset():bind(puzzle_id, card.due, card.step, card.lapses, card.missed):step()
    stmt:close()
end

function PkProgress:removeReview(puzzle_id)
    local stmt = self.conn:prepare("DELETE FROM puzzle_reviews WHERE puzzle_id = ?")
    stmt:reset():bind(puzzle_id):step()
    stmt:close()
end

--- Reviews due on day `today`, the longest overdue first.
function PkProgress:dueReviews(today)
    local out = {}
    local stmt = self.conn:prepare("SELECT puzzle_id, due, step, lapses, missed FROM puzzle_reviews"
        .. " WHERE due <= ? ORDER BY due, missed")
    stmt:reset():bind(today)
    for row in stmt:rows() do out[#out + 1] = reviewRow(row) end
    stmt:close()
    return out
end

function PkProgress:reviewDueCount(today)
    local stmt = self.conn:prepare("SELECT count(*) FROM puzzle_reviews WHERE due <= ?")
    local row = stmt:reset():bind(today):step()
    stmt:close()
    return tonumber(row[1])
end

--- Once: puzzles missed in the last `days` days (their latest attempt was
-- not a clean solve) become reviews, spread over a week. Returns how many.
function PkProgress:seedReviews(now, days)
    if self:getSetting("reviews_seeded") then return 0 end
    local PkPuzzleReview = require("pkpuzzlereview")
    local PkSrs = require("pksrs")
    local ids, at = {}, {}
    local stmt = self.conn:prepare([[
        SELECT a.puzzle_id, a.ts FROM attempts a
        WHERE a.ts >= ? AND (a.solved = 0 OR a.mistakes > 0 OR a.used_help = 1)
          AND a.ts = (SELECT max(ts) FROM attempts b WHERE b.puzzle_id = a.puzzle_id)
          AND a.puzzle_id NOT IN (SELECT puzzle_id FROM puzzle_reviews)
        ORDER BY a.ts DESC]])
    stmt:reset():bind(now - days * 86400)
    for row in stmt:rows() do
        if not at[row[1]] then
            ids[#ids + 1] = row[1]
            at[row[1]] = tonumber(row[2])
        end
    end
    stmt:close()
    local cards = PkPuzzleReview.seed(ids, at, PkSrs.today(now), 7)
    self.conn:exec("BEGIN")
    local ok, err = pcall(function()
        for _, id in ipairs(ids) do self:saveReview(id, cards[id]) end
        self:setSetting("reviews_seeded", "1")
    end)
    self.conn:exec(ok and "COMMIT" or "ROLLBACK")
    if not ok then error(err, 0) end
    return #ids
end

function PkProgress:close()
    if self.conn then
        self.insert_stmt:close()
        self.recent_stmt:close()
        self.kv_stmt:close()
        self.conn:close()
        self.conn = nil
    end
end

return PkProgress
