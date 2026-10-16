-- User puzzle rating (Glicko-2) and attempt history (ADR-0010), in a writable SQLite file
-- kept apart from the read-only packs so packs can be replaced freely.
local SQ3 = require("lua-ljsqlite3/init")
local PkGlicko = require("pkglicko")

local MIN_RATING, MAX_RATING = 400, 3000
local DAY = 86400

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

--- Pure rating update (Glicko-2, ADR-0010): the player state { rating, rd,
-- vol, ts } after an attempt at `ts` on a puzzle rated `puzzle_rating` ±
-- `puzzle_rd`; the deviation grew with the days since the last attempt.
function PkProgress.updatedState(state, puzzle_rating, puzzle_rd, success, ts)
    local days = state.ts and math.max(0, (ts - state.ts) / DAY) or 0
    local new = PkGlicko.rate(state, { { rating = puzzle_rating, rd = puzzle_rd or PkGlicko.PUZZLE_RD,
                                         score = success and 1 or 0 } }, days)
    new.rating = math.max(MIN_RATING, math.min(MAX_RATING, new.rating))
    new.ts = ts
    return new
end

local function round(x) return math.floor(x + 0.5) end

--- The progress file (in KOReader's settings folder).
function PkProgress.defaultPath()
    return require("datastorage"):getSettingsDir() .. "/paperknight/progress.sqlite"
end

function PkProgress.open(path)
    local dir = path:match("(.*)/")
    if dir then
        local ok, lfs = pcall(require, "libs/libkoreader-lfs")
        if ok and lfs.attributes(dir, "mode") ~= "directory" then lfs.mkdir(dir) end
    end
    local conn = SQ3.open(path)
    local self = setmetatable({ conn = conn, path = path }, PkProgress)
    local ok, err = pcall(function()
        -- the rollback journal is truncated, not created and deleted on every
        -- write (slow flash); syncing stays the default (FULL): no corruption
        -- on a power cut
        conn:exec("PRAGMA journal_mode=TRUNCATE")
        conn:exec(SCHEMA)
        self:_migrate()
        self.insert_stmt = conn:prepare("INSERT INTO attempts (puzzle_id, ts, solved, mistakes, used_help,"
            .. " puzzle_rating, rating_before, rating_after, review) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)")
        self.recent_stmt = conn:prepare("SELECT 1 FROM attempts WHERE puzzle_id = ? AND ts >= ? LIMIT 1")
        self.review_stmt = conn:prepare("SELECT puzzle_id, due, step, lapses, missed FROM puzzle_reviews"
            .. " WHERE puzzle_id = ?")
    end)
    if not ok then
        self:close()
        error(err, 0)
    end
    return self
end

-- Schema changes of existing files.
--  * attempts.review: 1 for a review of a missed puzzle (recordReview): not
--    rated, not in the stats, but it marks the puzzle as seen.
--  * The review ladder changed on 2026-10-14 (3, 7, 21 days instead of 1, 3,
--    7, 21, ADR-0014): a card's step k waited for the old k-th interval, the
--    new step k-1 (one-time shift).
function PkProgress:_migrate()
    local has_review = false
    local info = self.conn:prepare("PRAGMA table_info(attempts)")
    for row in info:rows() do
        if row[2] == "review" then has_review = true end
    end
    info:close()
    if not has_review then
        self.conn:exec("ALTER TABLE attempts ADD COLUMN review INTEGER NOT NULL DEFAULT 0")
    end
    if not self.conn:rowexec("SELECT value FROM kv WHERE key = 'migration.review_ladder_3_7_21'") then
        self:_tx(function()
            self.conn:exec("UPDATE puzzle_reviews SET step = step - 1 WHERE step > 0")
            self.conn:exec("INSERT OR REPLACE INTO kv (key, value) VALUES ('migration.review_ladder_3_7_21', '1')")
        end)
    end
    if not self.conn:rowexec("SELECT value FROM kv WHERE key = 'rating.rd'") then
        self:_tx(function() self:_saveState(self:_replayedState()) end)
    end
end

-- The Glicko-2 state from the rated attempts, oldest first (the rating was
-- Elo until 2026-10-15; the history keeps what Glicko needs).
function PkProgress:_replayedState()
    local state = { rating = PkGlicko.START.rating, rd = PkGlicko.START.rd, vol = PkGlicko.START.vol }
    local stmt = self.conn:prepare("SELECT ts, solved, mistakes, used_help, puzzle_rating FROM attempts"
        .. " WHERE review = 0 ORDER BY ts, rowid")
    for row in stmt:rows() do
        local clean = tonumber(row[2]) == 1 and tonumber(row[3]) == 0 and tonumber(row[4]) == 0
        state = PkProgress.updatedState(state, tonumber(row[5]), nil, clean, tonumber(row[1]))
    end
    stmt:close()
    return state
end

function PkProgress:_saveState(state)
    local stmt = self.conn:prepare("INSERT OR REPLACE INTO kv (key, value) VALUES (?, ?)")
    for _, k in ipairs({ "rating", "rd", "vol", "ts" }) do
        if state[k] then
            stmt:reset():bind(k == "rating" and "rating" or "rating." .. k, tostring(state[k])):step()
        end
    end
    stmt:close()
end

--- The full rating state: { rating, rd, vol, ts } (ts: last rated attempt).
function PkProgress:ratingState()
    local state = { rating = PkGlicko.START.rating, rd = PkGlicko.START.rd, vol = PkGlicko.START.vol }
    local stmt = self.conn:prepare("SELECT key, value FROM kv WHERE key = 'rating' OR key LIKE 'rating.%'")
    for row in stmt:rows() do
        local k = row[1] == "rating" and "rating" or row[1]:sub(#"rating." + 1)
        state[k] = tonumber(row[2])
    end
    stmt:close()
    return state
end

--- Runs `fn` in a transaction: committed if it succeeds, rolled back (and
-- the error raised again) otherwise, a failed COMMIT included, so that no
-- transaction stays open for the rest of the session.
function PkProgress:_tx(fn)
    self.conn:exec("BEGIN")
    local ok, err = pcall(function()
        fn()
        self.conn:exec("COMMIT")
    end)
    if not ok then
        pcall(self.conn.exec, self.conn, "ROLLBACK")
        error(err, 0)
    end
end

--- The rating, rounded.
function PkProgress:rating()
    local v = self.conn:rowexec("SELECT value FROM kv WHERE key = 'rating'")
    return round(tonumber(v) or PkGlicko.START.rating)
end

--- A setting read from the default progress file, opened and closed for
-- it (screens that keep no progress handle); nil if unset or unreadable.
function PkProgress.readSetting(key)
    local ok, value = pcall(function()
        local progress = PkProgress.open(PkProgress.defaultPath())
        local v = progress:getSetting(key)
        progress:close()
        return v
    end)
    if not ok then require("logger").warn("Paperknight: cannot read", key, value) end
    return ok and value or nil
end

--- Saves a setting the same way (nil removes it); errors are logged.
function PkProgress.writeSetting(key, value)
    local ok, err = pcall(function()
        local progress = PkProgress.open(PkProgress.defaultPath())
        progress:setSetting(key, value)
        progress:close()
    end)
    if not ok then require("logger").warn("Paperknight: cannot save", key, err) end
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

--- Rated attempts (first attempts; reviews are not rated).
function PkProgress:attemptCount()
    return tonumber(self.conn:rowexec("SELECT count(*) FROM attempts WHERE review = 0"))
end

--- Every rated attempt: { {puzzle_id, clean, puzzle_rating} } (clean: solved
-- without a mistake or help, as counted by the rating). Unordered.
function PkProgress:attempts()
    local out = {}
    local stmt = self.conn:prepare("SELECT puzzle_id, solved, mistakes, used_help, puzzle_rating"
        .. " FROM attempts WHERE review = 0")
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

--- Ids of the puzzles attempted (reviews included) since `since_ts`: a set.
function PkProgress:attemptedSince(since_ts)
    local set = {}
    local stmt = self.conn:prepare("SELECT DISTINCT puzzle_id FROM attempts WHERE ts >= ?")
    stmt:reset():bind(since_ts)
    for row in stmt:rows() do set[row[1]] = true end
    stmt:close()
    return set
end

--- Ids of the puzzles that are or were under review (missed once): a set.
-- They never come back as new puzzles, mastered ones included.
function PkProgress:reviewedIds()
    local set = {}
    local stmt = self.conn:prepare("SELECT puzzle_id FROM puzzle_reviews"
        .. " UNION SELECT puzzle_id FROM attempts WHERE review = 1")
    for row in stmt:rows() do set[row[1]] = true end
    stmt:close()
    return set
end

function PkProgress:wasAttemptedSince(puzzle_id, since_ts)
    local row = self.recent_stmt:reset():bind(puzzle_id, since_ts):step()
    self.recent_stmt:reset() -- don't keep a read transaction open between calls
    return row ~= nil
end

--- Records a finished attempt and updates the rating; `review_card`, when
-- given, is saved in the same transaction (a missed puzzle's review).
-- @param result { puzzle_id, puzzle_rating, puzzle_rd, success, solved, mistakes, used_help, ts }
-- @return rating_before, rating_after (rounded)
function PkProgress:record(result, review_card)
    local ts = result.ts or os.time()
    local state = self:ratingState()
    local new = PkProgress.updatedState(state, result.puzzle_rating, result.puzzle_rd, result.success, ts)
    local before, after = round(state.rating), round(new.rating)
    self:_tx(function()
        self.insert_stmt:reset():bind(result.puzzle_id, ts,
            result.solved and 1 or 0, result.mistakes or 0, result.used_help and 1 or 0,
            result.puzzle_rating, before, after, 0):step()
        self:_saveState(new)
        if review_card then self:saveReview(result.puzzle_id, review_card) end
    end)
    return before, after
end

--- Records a review of a missed puzzle (not rated): it marks the puzzle as
-- seen (attemptedSince, reviewedIds). `card`: the review card to save (nil:
-- mastered, the card is removed), in the same transaction.
function PkProgress:recordReview(puzzle_id, clean, puzzle_rating, card, ts)
    local rating = self:rating()
    self:_tx(function()
        self.insert_stmt:reset():bind(puzzle_id, ts or os.time(), clean and 1 or 0, clean and 0 or 1, 0,
            puzzle_rating or 0, rating, rating, 1):step()
        if card then self:saveReview(puzzle_id, card) else self:removeReview(puzzle_id) end
    end)
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
    local row = self.review_stmt:reset():bind(puzzle_id):step()
    local card = row and reviewRow(row) or nil
    self.review_stmt:reset() -- don't keep a read transaction open between calls
    return card
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
        WHERE a.ts >= ? AND a.review = 0 AND (a.solved = 0 OR a.mistakes > 0 OR a.used_help = 1)
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
    self:_tx(function()
        for _, id in ipairs(ids) do self:saveReview(id, cards[id]) end
        self:setSetting("reviews_seeded", "1")
    end)
    return #ids
end

function PkProgress:close()
    if self.conn then
        for _, k in ipairs({ "insert_stmt", "recent_stmt", "review_stmt" }) do
            if self[k] then self[k]:close() end
        end
        self.conn:close()
        self.conn = nil
    end
end

return PkProgress
