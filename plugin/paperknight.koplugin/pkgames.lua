-- Master games and Guess the move (ADR-0021, docs/games.md): the games of
-- data/games.tsv (built by `python -m paperknight_pipeline games`), and a
-- session over one of them: the opening is played, then the user guesses
-- each move of one side; the master's move is then played, and the
-- other side's reply. A guess is the master's move, a move Stockfish rates
-- as well (a good move too), or a miss. Pure logic; pkgamesview.lua shows it.
local Chess = require("pkchess")
local _ = require("gettext")
local T = require("ffi/util").template

local PkGames = {
    path = nil, -- default: data/games.tsv in the plugin (tests set another)
    -- a move counts as good when its winning chances are within this of
    -- the master's move (Lichess's scale, as the pipeline's key moments)
    GOOD_MARGIN = 5,
}

local list -- the games, in the file's order; false if it cannot be read

local function split(s, sep)
    local out = {}
    for field in (s .. sep):gmatch("(.-)" .. sep) do out[#out + 1] = field end
    return out
end

local function load()
    if list ~= nil then return list end
    local path = PkGames.path or (require("pkicons").plugin_dir .. "/data/games.tsv")
    local f = io.open(path, "rb")
    if not f then
        require("logger").warn("Paperknight: no master games:", path)
        list = false
        return list
    end
    list = {}
    for line in f:lines() do
        if line ~= "" and line:sub(1, 1) ~= "#" then
            local c = split(line, "\t")
            if #c >= 13 then
                list[#list + 1] = {
                    id = c[1], title = c[2], white = c[3], black = c[4], event = c[5],
                    site = c[6], year = c[7], round = c[8], result = c[9], note = c[10],
                    book = tonumber(c[11]) or 0, moves_text = c[12], analysis_text = c[13],
                }
            end
        end
    end
    f:close()
    return list
end

--- Forgets the games read (tests change `path`).
function PkGames.reset() list = nil end

--- The games (empty if the file is missing).
function PkGames.list()
    return load() or {}
end

function PkGames.get(id)
    for _, g in ipairs(PkGames.list()) do
        if g.id == id then return g end
    end
end

--- "Morphy – Duke Karl Count Isouard" (the names are short in the file)
function PkGames.players(game)
    return T("%1 – %2", game.white, game.black)
end

function PkGames.place(game)
    local where = (game.site ~= "" and game.site) or game.event
    where = where:gsub("%s+%d%d%d%d$", "") -- "Hastings 1895": the year once
    return where ~= "" and (where .. " " .. game.year) or game.year
end

--- The winning side ("w"/"b"), nil for a draw.
function PkGames.winner(game)
    if game.result == "1-0" then return "w" elseif game.result == "0-1" then return "b" end
end

--- Winning chances (0–100) of a score in centipawns (Lichess's scale).
function PkGames.win(cp)
    return 50 + 50 * (2 / (1 + math.exp(-0.00368208 * cp)) - 1)
end

-- The moves (UCI) and the analysis of each ply: { scores = { {uci, cp}… }, key }
local function parse(game)
    if game.moves then return end
    game.moves = split(game.moves_text, " ")
    if game.moves_text == "" then game.moves = {} end
    game.analysis = {}
    for i, entry in ipairs(split(game.analysis_text, " ")) do
        local key = entry:sub(1, 1) == "!"
        if key then entry = entry:sub(2) end
        local scores = {}
        for uci, cp in entry:gmatch("([a-h][1-8][a-h][1-8][qrbn]?):(%-?%d+)") do
            scores[#scores + 1] = { uci, tonumber(cp) }
        end
        game.analysis[i] = { scores = scores, key = key }
    end
end

local function toMove(uci)
    return { from = uci:sub(1, 2), to = uci:sub(3, 4), promotion = #uci > 4 and uci:sub(5, 5) or nil }
end

local function uciOf(move)
    return move.from .. move.to .. (move.promotion or "")
end

---------------------------------------------------------------------------
-- A session: guessing `side`'s moves in a game

local Session = {}
Session.__index = Session

--- A session over `game` (from PkGames.list), guessing `side`'s moves
-- (default: the winner's, White in a draw). The opening (the book plies)
-- is played; `state` (from :serialize) resumes a session.
function PkGames.session(game, side, state)
    parse(game)
    side = side or PkGames.winner(game) or "w"
    local self = setmetatable({
        game = game, side = side, chess = Chess:new(),
        found = 0, good = 0, asked = 0, keys = 0, keys_found = 0,
        verdicts = {}, -- per ply guessed: "found", "good", "hinted", "miss", "shown"
    }, Session)
    self.chess.reset()
    local start = math.min(game.book, #game.moves)
    if state then
        start = math.min(state.ply, #game.moves)
        for k, v in pairs(state.counts or {}) do self[k] = v end
        for ply, v in pairs(state.verdicts or {}) do self.verdicts[ply] = v end
    end
    for i = 1, start do self:_playMaster(i) end
    self.start_ply = math.min(game.book, #game.moves)
    return self
end

function Session:ply() return #self.chess.history() end

function Session:over() return self:ply() >= #self.game.moves end

--- Whether the user is to guess the next move.
function Session:guessing()
    return not self:over() and self.chess.turn() == self.side
end

--- Whether the next move is the other side's (played for the user).
function Session:replyNext()
    return not self:over() and self.chess.turn() ~= self.side
end

--- The analysis of the next ply ({ scores, key }).
function Session:next()
    return self.game.analysis[self:ply() + 1]
end

--- Whether the move to guess is a key moment.
function Session:keyMoment()
    local a = self:guessing() and self:next()
    return a and a.key or false
end

function Session:_playMaster(i)
    local move = self.chess.move(toMove(self.game.moves[i]))
    assert(move, "illegal move in the master game " .. self.game.id .. " at ply " .. i)
    return move
end

-- The score of `uci` at the next ply, if Stockfish listed it.
function Session:_score(uci)
    local a = self:next()
    for _, s in ipairs(a and a.scores or {}) do
        if s[1] == uci then return s[2] end
    end
end

-- The SAN of `uci` in the current position (not played).
function Session:_san(uci)
    local move = self.chess.move(toMove(uci))
    if not move then return uci end
    self.chess.undo()
    return move.san
end

--- The user's guess `move` ({ from, to, promotion }) for the next move.
-- Returns the verdict ("found", "good", "miss"; "hinted": the master's
-- move after a hint, worth a good move) and a result table:
-- { master = SAN played, guess = SAN guessed, best = Stockfish's first
-- choice (SAN), cp_master, cp_guess (nil if Stockfish did not rate it),
-- key }. The master's move is then played.
function Session:guess(move)
    if not self:guessing() then return nil end
    local ply = self:ply() + 1
    local a = self:next()
    local master_uci = self.game.moves[ply]
    local uci = uciOf(move)
    local info = {
        guess = self:_san(uci), cp_guess = self:_score(uci), cp_master = self:_score(master_uci),
        key = a.key,
    }
    if a.scores[1] then info.best = self:_san(a.scores[1][1]) end
    local verdict
    if uci == master_uci then
        verdict = self.hinted == ply and "hinted" or "found"
    elseif info.cp_guess and info.cp_master
            and PkGames.win(info.cp_guess) >= PkGames.win(info.cp_master) - PkGames.GOOD_MARGIN then
        verdict = "good"
    else
        verdict = "miss"
    end
    self:_count(ply, verdict, a.key)
    self.hinted = nil
    info.master = self:_playMaster(ply).san
    return verdict, info
end

--- The master's move shown without a guess (counted as missed).
function Session:show()
    if not self:guessing() then return nil end
    local ply = self:ply() + 1
    local key = self:next().key
    self:_count(ply, "shown", key)
    self.hinted = nil
    return self:_playMaster(ply), key
end

function Session:_count(ply, verdict, key)
    self.asked = self.asked + 1
    if verdict == "found" then self.found = self.found + 1 end
    if verdict == "good" or verdict == "hinted" then self.good = self.good + 1 end
    if key then
        self.keys = self.keys + 1
        if verdict == "found" or verdict == "good" then self.keys_found = self.keys_found + 1 end
    end
    self.verdicts[ply] = verdict
end

--- Plays the other side's next move; returns it.
function Session:reply()
    if not self:replyNext() then return nil end
    return self:_playMaster(self:ply() + 1)
end

--- The square of the piece the master moved next (a hint: the master's
-- move then counts as a good move).
function Session:hint()
    if not self:guessing() then return nil end
    self.hinted = self:ply() + 1
    return self.game.moves[self.hinted]:sub(1, 2)
end

--- Points: a master's move 2, a good move 1 (of 2 per move asked).
function Session:points()
    return 2 * self.found + self.good, 2 * self.asked
end

--- "Found 5 of 8" (with the good moves: "Found 5 of 8 · 2 good")
function Session:scoreText()
    local s = T(_("Found %1 of %2"), self.found, self.asked)
    if self.good > 0 then s = s .. " · " .. T(_("%1 good"), self.good) end
    return s
end

--- The game's moves played so far, verbose (pkchess history).
function Session:history()
    return self.chess.history({ verbose = true })
end

-- Saved state: "v1|id|side|ply|found|good|asked|keys|keys_found|verdicts"
-- (verdicts: one letter a ply: f, g, h, m, s; - for a ply not asked).
local LETTER = { found = "f", good = "g", hinted = "h", miss = "m", shown = "s" }
local VERDICT = { f = "found", g = "good", h = "hinted", m = "miss", s = "shown" }

function Session:serialize()
    local letters = {}
    for ply = 1, self:ply() do letters[ply] = LETTER[self.verdicts[ply]] or "-" end
    return table.concat({ "v1", self.game.id, self.side, self:ply(), self.found, self.good, self.asked,
        self.keys, self.keys_found, table.concat(letters) }, "|")
end

--- The session saved by :serialize(), or nil (unreadable, the game gone).
function PkGames.restore(text)
    if type(text) ~= "string" then return nil end
    local f = split(text, "|")
    if f[1] ~= "v1" or #f < 10 then return nil end
    local game = PkGames.get(f[2])
    if not game or (f[3] ~= "w" and f[3] ~= "b") then return nil end
    local n = function(i) return tonumber(f[i]) or 0 end
    local verdicts = {}
    for ply = 1, #f[10] do verdicts[ply] = VERDICT[f[10]:sub(ply, ply)] end
    return PkGames.session(game, f[3], {
        ply = n(4),
        counts = { found = n(5), good = n(6), asked = n(7), keys = n(8), keys_found = n(9) },
        verdicts = verdicts,
    })
end

return PkGames
