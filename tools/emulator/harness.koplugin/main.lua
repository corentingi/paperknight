-- Paperknight end-to-end test harness (development only, see ADR-0007).
--
-- Does nothing unless PK_SCENARIO points at a scenario file. A scenario is a Lua
-- file returning `function(h) ... end`; it runs in a coroutine so `h.wait()` can
-- let KOReader's event loop process taps and repaints between steps.
-- The outcome is written to PK_RESULT ("PASS" or "FAIL: <reason>") and
-- KOReader quits.
local Event = require("ui/event")
local Geometry = require("ui/geometry")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Screen = require("device").screen
local logger = require("logger")
local time = require("ui/time")

local Harness = WidgetContainer:extend{
    name = "pkharness",
}

-- Module-level: a new plugin instance is created whenever KOReader switches
-- between the file manager and the reader; the scenario must only run once.
local started = false

local function writeResult(text)
    local path = os.getenv("PK_RESULT")
    if not path then return end
    local f = io.open(path, "w")
    if f then
        f:write(text, "\n")
        f:close()
    end
end

function Harness:init()
    local scenario_path = os.getenv("PK_SCENARIO")
    if not scenario_path or started then return end
    started = true
    UIManager:scheduleIn(tonumber(os.getenv("PK_START_DELAY")) or 1, function()
        self:run(scenario_path)
    end)
end

function Harness:helpers(co)
    local h = { ui = self.ui }
    local shots_dir = os.getenv("PK_SHOTS_DIR") or "."

    local function resume()
        local ok, err = coroutine.resume(co)
        if not ok then
            self:finish("FAIL: " .. tostring(err) .. "\n" .. debug.traceback(co))
        end
    end

    function h.wait(seconds)
        UIManager:scheduleIn(seconds or 0.5, resume)
        coroutine.yield()
    end

    -- Lets the UI catch up after an action, without a fixed delay: paints now
    -- (rebuilt widgets get their positions), lets the tasks queued for the
    -- next tick run, and paints again. Timed tasks (an opponent's reply
    -- after a delay) still need h.wait or h.waitFor.
    function h.settle()
        UIManager:forceRePaint()
        h.wait(0.05)
        UIManager:forceRePaint()
    end

    -- Waits until `pred()` is true (polled every 0.05 s), at most `timeout`
    -- seconds (default 3); returns whether it became true.
    function h.waitFor(pred, timeout)
        local deadline = time.now() + time.s(timeout or 3)
        while not pred() do
            if time.now() > deadline then return false end
            h.wait(0.05)
        end
        return true
    end

    function h.tap(x, y)
        logger.info("pkharness: tap", x, y)
        UIManager:sendEvent(Event:new("Gesture", {
            ges = "tap",
            pos = Geometry:new{ x = x, y = y, w = 0, h = 0 },
            time = time.now(),
        }))
        h.settle()
    end

    -- Swipe from (x, y); direction "west" (finger moves left), "east", ...
    function h.swipe(x, y, direction)
        logger.info("pkharness: swipe", x, y, direction)
        UIManager:sendEvent(Event:new("Gesture", {
            ges = "swipe",
            direction = direction,
            distance = 200,
            pos = Geometry:new{ x = x, y = y, w = 0, h = 0 },
            time = time.now(),
        }))
        h.settle()
    end

    -- Records the refreshes sent to the screen (after KOReader's merges and
    -- its periodic promotion to a flash) until the returned function is
    -- called; it returns { {mode=, x=, y=, w=, h=}, ... }. The mode -> Screen
    -- method table is a local of uimanager.lua: its entries are wrapped.
    function h.recordRefreshes()
        local methods
        for i = 1, 100 do
            local name, val = debug.getupvalue(UIManager._repaint, i)
            if not name then break end
            if name == "refresh_methods" then methods = val end
        end
        assert(methods, "recordRefreshes: refresh_methods not found in UIManager._repaint")
        local log, saved = {}, {}
        for mode, fn in pairs(methods) do
            saved[mode] = fn
            methods[mode] = function(screen, x, y, w, hh, d)
                log[#log + 1] = { mode = mode, x = x, y = y, w = w, h = hh }
                return fn(screen, x, y, w, hh, d)
            end
        end
        return function()
            for mode, fn in pairs(saved) do methods[mode] = fn end
            return log
        end
    end

    -- Tap the centre of a widget that has been painted at least once.
    function h.tapWidget(widget)
        assert(widget and widget.dimen, "tapWidget: widget has no dimen (not painted yet?)")
        local d = widget.dimen
        h.tap(d.x + math.floor(d.w / 2), d.y + math.floor(d.h / 2))
    end

    -- The first button under `widget` (a dialog...) whose text contains
    -- `text`: a widget with a text, a callback and a place on screen.
    function h.findButton(widget, text)
        local seen = {}
        local function walk(w)
            if type(w) ~= "table" or seen[w] then return nil end
            seen[w] = true
            if type(w.text) == "string" and w.callback and w.dimen and w.text:find(text, 1, true) then return w end
            for k, v in pairs(w) do
                if type(v) == "table" and k ~= "show_parent" and k ~= "parent" then
                    local found = walk(v)
                    if found then return found end
                end
            end
        end
        return walk(widget)
    end

    function h.shot(name)
        UIManager:forceRePaint()
        local path = shots_dir .. "/" .. name .. ".png"
        Screen:shot(path)
        logger.info("pkharness: screenshot", path)
        return path
    end

    function h.check(cond, message)
        if not cond then
            error("check failed: " .. tostring(message), 2)
        end
    end

    function h.log(...)
        logger.info("pkharness:", ...)
    end

    return h
end

-- First-run KOReader popups (InfoMessages) would swallow scripted taps.
-- Close every window above the file manager. Uses a private UIManager field:
-- acceptable for a development-only harness.
function Harness:dismissPopups()
    for i = #UIManager._window_stack, 1, -1 do
        local widget = UIManager._window_stack[i].widget
        if widget ~= self.ui then
            logger.info("pkharness: dismissing", widget.name or widget.id or tostring(widget))
            UIManager:close(widget)
        end
    end
end

function Harness:run(scenario_path)
    self:dismissPopups()
    logger.info("pkharness: running scenario", scenario_path)
    local chunk, load_err = loadfile(scenario_path)
    if not chunk then
        return self:finish("FAIL: cannot load scenario: " .. tostring(load_err))
    end
    local loaded, scenario = pcall(chunk)
    if not loaded or type(scenario) ~= "function" then
        return self:finish("FAIL: the scenario must return a function: " .. tostring(scenario))
    end
    local co
    co = coroutine.create(function()
        scenario(self:helpers(co))
        self:finish("PASS")
    end)
    local ok, err = coroutine.resume(co)
    if not ok then
        self:finish("FAIL: " .. tostring(err) .. "\n" .. debug.traceback(co))
    end
end

function Harness:finish(result)
    if self.finished then return end
    self.finished = true
    logger.info("pkharness: result", result)
    writeResult(result)
    UIManager:scheduleIn(0.2, function() UIManager:quit() end)
end

return Harness
