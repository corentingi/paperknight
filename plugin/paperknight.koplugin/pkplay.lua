-- Play mode (ADR-0020): a game against Stockfish or between two players on
-- one Kindle (face to face: Black's pieces upside down). This file holds
-- the logic: the settings, whose turn is the user's, take-backs, the
-- result, the clock's time control, and the game in progress, saved so that
-- it comes back. pkplayview.lua shows it, pkplaysetup.lua sets it up.
local Chess = require("pkchess")
local _ = require("gettext")
local T = require("ffi/util").template

local PkPlay = {
    START_FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
    -- Stockfish's strength (UCI_Elo; 0: full strength), from easiest
    LEVELS = { 1350, 1500, 1800, 2100, 2400, 0 },
    -- time controls: minutes + seconds added per move
    CLOCKS = { "off", "5+0", "10+0", "15+10", "30+0" },
    DEFAULTS = { opponent = "engine", side = "w", level = 1500, face = true, clock = "off" },
}

---------------------------------------------------------------------------
-- Settings: { opponent = "engine"|"human", side = "w"|"b"|"random",
-- level = Elo or 0, face = boolean (two players), clock = "off"|"m+s" }

local function oneOf(value, list)
    for _, v in ipairs(list) do
        if v == value then return value end
    end
end

--- The settings from `read(key)` (progress settings, strings), with the
-- defaults for what is missing or unknown.
function PkPlay.loadSettings(read)
    local d = PkPlay.DEFAULTS
    local face = read("play.face")
    return {
        opponent = oneOf(read("play.opponent"), { "engine", "human" }) or d.opponent,
        side = oneOf(read("play.side"), { "w", "b", "random" }) or d.side,
        level = oneOf(tonumber(read("play.level")), PkPlay.LEVELS) or d.level,
        face = face == nil and d.face or face == "1",
        clock = oneOf(read("play.clock"), PkPlay.CLOCKS) or d.clock,
    }
end

function PkPlay.saveSettings(s, write)
    write("play.opponent", s.opponent)
    write("play.side", s.side)
    write("play.level", tostring(s.level))
    write("play.face", s.face and "1" or "0")
    write("play.clock", s.clock)
end

--- "5+0" -> 300, 0 (seconds); nil for "off".
function PkPlay.clockSpec(clock)
    local m, s = (clock or ""):match("^(%d+)%+(%d+)$")
    if not m then return nil end
    return tonumber(m) * 60, tonumber(s)
end

function PkPlay.levelName(level)
    return level == 0 and _("full strength") or tostring(level)
end

function PkPlay.clockName(clock)
    local base, inc = PkPlay.clockSpec(clock)
    if not base then return _("No clock") end
    return inc > 0 and T(_("%1 min + %2 s"), base / 60, inc) or T(_("%1 min"), base / 60)
end

---------------------------------------------------------------------------
-- A game

local Game = {}
Game.__index = Game

--- A new game with `settings`. `opts`: { engine = false when Stockfish is
-- not installed (then two players), random = function(n) for side
-- "random" (tests), fen, moves (UCI, a saved game) }.
function PkPlay.new(settings, opts)
    opts = opts or {}
    local s = {}
    for k, v in pairs(settings) do s[k] = v end
    if opts.engine == false then s.opponent = "human" end
    local self = setmetatable({ settings = s, chess = Chess:new() }, Game)
    self.start_fen = opts.fen or PkPlay.START_FEN
    self.chess.load(self.start_fen)
    if s.opponent == "engine" then
        local side = s.side
        if side == "random" then
            side = ((opts.random or math.random)(2) == 1) and "w" or "b"
        end
        self.user_side = side
        self.engine_side = side == "w" and "b" or "w"
        self.chess.set_human(self.engine_side, false)
    end
    for move in (opts.moves or ""):gmatch("%S+") do
        if not self:play({ from = move:sub(1, 2), to = move:sub(3, 4), promotion = move:sub(5, 5) ~= "" and move:sub(5, 5) or nil }, true) then
            break
        end
    end
    return self
end

function Game:vsEngine() return self.engine_side ~= nil end

function Game:turn() return self.chess.turn() end

function Game:isEngineTurn()
    return self.result == nil and self.engine_side ~= nil and self.chess.turn() == self.engine_side
end

--- Whether a player on this Kindle is to move (the board takes moves).
function Game:isUserTurn()
    return self.result == nil and not self:isEngineTurn()
end

--- Plays `move` ({ from, to, promotion }) for the side to move (`any`:
-- the engine's move too). Returns the move, or nil.
function Game:play(move, any)
    if self.result then return nil end
    if not any and self:isEngineTurn() then return nil end
    local played = self.chess.move(move)
    if played then self:_checkOver() end
    return played
end

--- The move the board already played in the chess game: the result checked.
function Game:played()
    self:_checkOver()
end

function Game:_checkOver()
    local over, result, reason = self.chess.game_over()
    if over then
        self.result = { score = result, reason = reason or "checkmate" }
    end
end

--- How many plies a take-back undoes: back to the user's last move (against
-- the engine, its reply too), one in a game between two players.
function Game:takeBackPlies()
    local n = #self.chess.history()
    if n == 0 then return 0 end
    if not self:vsEngine() then return 1 end
    -- the user's last move: the last ply of the user's side
    local plies = (self.chess.turn() == self.user_side) and 2 or 1
    if plies > n then
        -- the engine opened (the user plays Black): nothing of the user's yet
        return 0
    end
    return plies
end

function Game:canTakeBack()
    return self:takeBackPlies() > 0
end

--- Takes back (also after the end: the game goes on). Returns the plies undone.
function Game:takeBack()
    local plies = self:takeBackPlies()
    for _ = 1, plies do self.chess.undo() end
    self.chess.redo_stack = {}
    if plies > 0 then self.result = nil end
    return plies
end

function Game:resign(color)
    if self.result then return end
    self.result = { score = color == "w" and "0-1" or "1-0", reason = "resign" }
end

--- `color`'s clock ran out: the other side wins.
function Game:flag(color)
    if self.result then return end
    self.result = { score = color == "w" and "0-1" or "1-0", reason = "time" }
end

local REASONS = {
    checkmate = _("checkmate"),
    resign = _("resignation"),
    time = _("on time"),
    Stalemate = _("stalemate"),
    ["Insufficient material"] = _("insufficient material"),
    ["Threefold repetition"] = _("threefold repetition"),
    ["Fifty-move rule"] = _("fifty-move rule"),
}

--- "White wins by checkmate." / "Draw by stalemate." / "You win on time.",
-- nil while the game goes on.
function Game:resultText()
    local r = self.result
    if not r then return nil end
    local reason = REASONS[r.reason] or r.reason
    if r.score == "1/2-1/2" then return T(_("Draw: %1."), reason) end
    local winner = r.score == "1-0" and "w" or "b"
    local by = (r.reason == "time") and reason or T(_("by %1"), reason)
    if self:vsEngine() then
        return winner == self.user_side and T(_("You win %1."), by) or T(_("Stockfish wins %1."), by)
    end
    return winner == "w" and T(_("White wins %1."), by) or T(_("Black wins %1."), by)
end

--- The moves played, as UCI ("e2e4 e7e5").
function Game:uciMoves()
    local out = {}
    for _, m in ipairs(self.chess.history({ verbose = true })) do
        out[#out + 1] = m.from .. m.to .. (m.promotion or "")
    end
    return table.concat(out, " ")
end

--- Stockfish's thinking time (ms) for a move: longer at the higher levels,
-- never more than a thirtieth of what its clock has left.
function Game:movetime(clock_left_s)
    local level = self.settings.level
    local ms = (level == 0 and 5000) or (level >= 2100 and 2000) or 1000
    if clock_left_s then ms = math.min(ms, math.floor(clock_left_s * 1000 / 30)) end
    return math.max(200, ms)
end

--- The players' names: "You" / "Stockfish 1500", or "White" / "Black".
function Game:players()
    if not self:vsEngine() then return _("White"), _("Black") end
    local engine = T(_("Stockfish %1"), PkPlay.levelName(self.settings.level))
    if self.user_side == "w" then return _("You"), engine end
    return engine, _("You")
end

local function pgnTag(name, value)
    return ('[%s "%s"]'):format(name, (value:gsub("\\", "\\\\"):gsub('"', '\\"')))
end

--- The game as PGN, named `name` (Studies → Games).
function Game:pgn(name)
    local white, black = self:players()
    local result = self.result and self.result.score or "*"
    local tags = {
        pgnTag("Event", name),
        pgnTag("Site", "Paperknight"),
        pgnTag("Date", os.date("%Y.%m.%d")),
        pgnTag("White", white),
        pgnTag("Black", black),
        pgnTag("Result", result),
    }
    if self.start_fen ~= PkPlay.START_FEN then
        tags[#tags + 1] = pgnTag("SetUp", "1")
        tags[#tags + 1] = pgnTag("FEN", self.start_fen)
    end
    if self.user_side == "b" then tags[#tags + 1] = pgnTag("Orientation", "black") end
    local fields = {}
    for f in self.start_fen:gmatch("%S+") do fields[#fields + 1] = f end
    local number, white_moves = tonumber(fields[6]) or 1, fields[2] ~= "b"
    local moves = {}
    for i, san in ipairs(self.chess.history()) do
        if white_moves then
            moves[#moves + 1] = number .. ". " .. san
        else
            moves[#moves + 1] = (i == 1) and (number .. "... " .. san) or san
            number = number + 1
        end
        white_moves = not white_moves
    end
    moves[#moves + 1] = result
    return table.concat(tags, "\n") .. "\n\n" .. table.concat(moves, " ") .. "\n"
end

---------------------------------------------------------------------------
-- The game in progress, kept between sessions ("play.current"): the
-- settings it was started with, the side the user got, the moves, and the
-- clocks' time left (`times`: { w = s, b = s }, with a clock).

function Game:serialize(times)
    local s = self.settings
    return table.concat({
        "v1", s.opponent, self.user_side or "-", tostring(s.level), s.face and "1" or "0", s.clock,
        self.start_fen, self:uciMoves(),
        times and (math.floor(times.w) .. " " .. math.floor(times.b)) or "",
    }, "\n")
end

--- The game saved by serialize() and the clocks' times (or nil), or nil
-- (unreadable, or over).
function PkPlay.restore(text, opts)
    if type(text) ~= "string" then return nil end
    local f = {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do f[#f + 1] = line end
    if f[1] ~= "v1" or #f < 7 then return nil end
    local settings = {
        opponent = oneOf(f[2], { "engine", "human" }) or "human",
        side = oneOf(f[3], { "w", "b" }) or "w",
        level = oneOf(tonumber(f[4]), PkPlay.LEVELS) or PkPlay.DEFAULTS.level,
        face = f[5] == "1",
        clock = oneOf(f[6], PkPlay.CLOCKS) or "off",
    }
    local o = {}
    for k, v in pairs(opts or {}) do o[k] = v end
    o.fen, o.moves = f[7], f[8] or ""
    local probe = Chess:new()
    if not probe.load(o.fen) then return nil end
    local game = PkPlay.new(settings, o)
    if game.result then return nil end
    local w, b = (f[9] or ""):match("^(%d+) (%d+)$")
    return game, w and { w = tonumber(w), b = tonumber(b) } or nil
end

return PkPlay
