-- Chess clocks (pktimer.lua) with a fake clock and scheduler.
local Chess = require("pkchesslib/src/chess")
local Timer = require("pktimer")

local function setup()
    local clock = { t = 1000 }
    local sched = { tasks = {} }
    function sched:scheduleIn(_, fn) self.tasks[#self.tasks + 1] = fn end
    function sched:unschedule(fn)
        for i = #self.tasks, 1, -1 do if self.tasks[i] == fn then table.remove(self.tasks, i) end end
    end
    function sched:run() -- fires the pending tasks once
        local due = self.tasks
        self.tasks = {}
        for _, fn in ipairs(due) do fn() end
    end
    local ticks = 0
    local timer = Timer:new({ [Chess.WHITE] = 60, [Chess.BLACK] = 30 },
        { [Chess.WHITE] = 2, [Chess.BLACK] = 0 }, function() ticks = ticks + 1 end)
    timer.now = function() return clock.t end
    timer.scheduler = sched
    return timer, clock, sched, function() return ticks end
end

return {
    { "time runs for the current player, increment on the move", function(t)
        local timer, clock = setup()
        timer:start()
        clock.t = clock.t + 15
        t.eq(timer:getRemainingTime(Chess.WHITE), 45, "running clock counted")
        t.eq(timer:getRemainingTime(Chess.BLACK), 30, "other clock still")
        timer:switchPlayer()
        t.eq(timer:getRemainingTime(Chess.WHITE), 47, "increment added")
        clock.t = clock.t + 10
        t.eq(timer:getRemainingTime(Chess.BLACK), 20, "black runs")
    end },
    { "a pause, an undo or closing adds no increment; a move does", function(t)
        local timer, clock = setup()
        timer:start(); clock.t = clock.t + 10; timer:stop()
        t.eq(timer:getRemainingTime(Chess.WHITE), 50, "paused: no increment")
        timer:start(); clock.t = clock.t + 10; timer:switchPlayer()
        t.eq(timer:getRemainingTime(Chess.WHITE), 42, "move: increment added")
    end },
    { "reset restores the initial times", function(t)
        local timer, clock = setup()
        timer:start(); clock.t = clock.t + 20; timer:stop()
        timer:reset()
        t.eq(timer:getRemainingTime(Chess.WHITE), 60, "white restored")
        t.eq(timer.base[Chess.WHITE], 60, "base untouched")
        timer.base[Chess.WHITE] = 300 -- settings change, then reset
        timer:reset()
        t.eq(timer:getRemainingTime(Chess.WHITE), 300, "new base applied")
    end },
    { "stop/start never piles up polling tasks", function(t)
        local timer, _, sched, ticks = setup()
        for _ = 1, 5 do timer:start(); timer:stop(); timer:start() end
        t.eq(#sched.tasks, 1, "one task pending")
        sched:run()
        t.eq(ticks(), 1, "one tick")
        t.eq(#sched.tasks, 1, "rescheduled once")
        timer:stop()
        t.eq(#sched.tasks, 0, "stop unschedules")
    end },
    { "a fallen flag stops the clock without increment", function(t)
        local timer, clock, sched, ticks = setup()
        timer:start(); sched:run()
        clock.t = clock.t + 90
        sched:run()
        t.ok(not timer.running, "stopped")
        t.eq(timer:getRemainingTime(Chess.WHITE), 0, "no time, no increment")
        t.eq(ticks(), 2, "callback told")
        t.eq(#sched.tasks, 0, "no task left")
    end },
}
