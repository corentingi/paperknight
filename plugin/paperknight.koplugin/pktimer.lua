-- Chess clocks: count down from a duration per player, with an increment
-- added when a player's turn ends. While running, `callback` is called
-- every TIMER_TIMEOUT seconds through one scheduled task (unscheduled on
-- stop, so stop/start never piles up loops).
local Chess = require("pkchesslib/src/chess")

local Timer = {
    now = os.time,   -- clock (tests replace it)
    scheduler = nil, -- UIManager unless set (tests)
}
local TIMER_TIMEOUT = 10
Timer.__index = Timer

local function copy(t)
    local c = {}
    for k, v in pairs(t) do c[k] = v end
    return c
end

--- Creates a new Timer.
-- @param duration { [Chess.WHITE] = seconds, [Chess.BLACK] = seconds }
-- @param increment same shape, seconds added after each move
-- @param callback called periodically while the timer runs, and when a flag falls
function Timer:new(duration, increment, callback)
    local obj = {
        base = copy(duration),
        increment = copy(increment),
        time = copy(duration), -- remaining time, as of the last stop
        currentPlayer = Chess.WHITE,
        running = false,
        startTime = 0,
        callback = callback,
    }
    setmetatable(obj, self)
    obj._tick = function() obj:_onTick() end
    return obj
end

function Timer:_scheduler()
    return self.scheduler or require("ui/uimanager")
end

function Timer:_onTick()
    if not self.running then return end
    if self:getRemainingTime(self.currentPlayer) <= 0 then
        self:stop() -- time is up
    else
        self:_scheduler():scheduleIn(TIMER_TIMEOUT, self._tick)
    end
    self.callback()
end

--- Starts the current player's clock.
function Timer:start()
    if self.running then return end
    self.startTime = self.now()
    self.running = true
    if self.callback then
        self:_scheduler():unschedule(self._tick)
        self:_scheduler():scheduleIn(0, self._tick)
    end
end

--- Stops the clock: the current player's time is updated, with the
-- increment when `with_increment` (a move was played: switchPlayer) and their
-- time did not run out. A pause, an undo or closing adds nothing.
function Timer:stop(with_increment)
    if not self.running then return end
    local player = self.currentPlayer
    local left = self:getRemainingTime(player)
    self.time[player] = left > 0 and left + (with_increment and self.increment[player] or 0) or 0
    self.running = false
    self:_scheduler():unschedule(self._tick)
end

--- Switches the turn to the other player and starts their clock.
function Timer:switchPlayer()
    self:stop(true)
    self.currentPlayer = (self.currentPlayer == Chess.WHITE) and Chess.BLACK or Chess.WHITE
    self:start()
end

--- Resets both clocks to the initial duration (stopped, White to move).
function Timer:reset()
    if self.running then self:_scheduler():unschedule(self._tick) end
    self.time = copy(self.base)
    self.currentPlayer = Chess.WHITE
    self.running = false
end

--- Remaining time of `player` in seconds, counting the running clock.
function Timer:getRemainingTime(player)
    local t = self.time[player]
    if self.running and player == self.currentPlayer then
        t = math.max(0, t - os.difftime(self.now(), self.startTime))
    end
    return t
end

--- Formats seconds as "HH:MM:SS".
function Timer:formatTime(seconds)
    local hours = math.floor(seconds / (60 * 60))
    local minutes = math.floor(seconds / 60) % 60
    local secs = seconds % 60
    return string.format("%02d:%02d:%02d", hours, minutes, secs)
end

return Timer
