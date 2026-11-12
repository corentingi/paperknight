local UIManager = require("ui/uimanager")
local Utils = require("pkutils")

-- One polling task per engine, from its first command to stop(): it drains
-- everything the engine wrote, every POLL seconds.
local POLL = 0.2

local M = {}

local UCIEngine = {}
UCIEngine.__index = UCIEngine

-- An option line: "option name Skill Level type spin default 20 min 0 max
-- 20" -> "Skill Level", { type, default, min, max, value } (value: the
-- default until setOption). The name may have spaces; it ends at "type".
local function parseOption(line)
    local name, rest = line:match("^option%s+name%s+(.-)%s+type%s+(.*)$")
    if not name then return nil end
    local words = {}
    for word in rest:gmatch("%S+") do words[#words + 1] = word end
    local opt = { type = words[1] }
    for i = 2, #words - 1 do
        local key = words[i]
        if (key == "default" or key == "min" or key == "max") and opt[key] == nil then opt[key] = words[i + 1] end
    end
    opt.value = opt.default
    return name, opt
end

-- One line from the engine: its state updated, the events triggered
-- ("uciok", "readyok", "bestmove", "info"; "line" is triggered for every
-- line by the reader).
local function parse_uci_line(line, state)
    line = line:match("^%s*(.-)%s*$")
    local eng = state._engine
    if line == "kill" then -- written by the child when exec failed (pkutils)
        state.to_uciok = -1
    elseif line == "uciok" then
        state.uciok = true
        eng:_trigger("uciok")
    elseif line:match("^Stockfish") and not state.id_name then
        -- a banner some builds print before the handshake: a name until "id name"
        state.id_name = line
    elseif line:find("^id name%s") then
        state.id_name = line:match("^id name%s+(.+)$")
    elseif line:find("^id author%s") then
        state.id_author = line:match("^id author%s+(.+)$")
    elseif line:find("^option%s") then
        local name, opt = parseOption(line)
        if name then state.options[name] = opt end
    elseif line == "readyok" then
        state.readyok = true
        eng:_trigger("readyok")
    elseif line:find("^info%s") then
        eng:_trigger("info", line) -- (not kept: a search prints thousands)
    elseif line:find("^bestmove%s") then
        local move, ponder = line:match("^bestmove%s+(%S+)%s+ponder%s+(%S+)$")
        state.bestmove = move or line:match("^bestmove%s+(%S+)")
        state.ponder = ponder
        eng:_trigger("bestmove", state.bestmove, state.ponder)
    end
end

--- Starts the engine `cmd` (argv `args`): the engine, or nil and an error.
function UCIEngine.spawn(cmd, args)
    local pid, rfd, wfd_or_err = Utils.execInSubProcess(cmd, args, true, false)
    if not pid then return nil, rfd end
    local self = setmetatable({ pid = pid, fd_read = rfd, fd_write = wfd_or_err, callbacks = {} }, UCIEngine)
    -- what the engine said: uciok, readyok, id_name, id_author, options
    -- (name -> { type, default, min, max, value }), bestmove, ponder
    self.state = { uciok = false, readyok = false, options = {}, _engine = self }
    local read = Utils.reader(self.fd_read, function(line)
        parse_uci_line(line, self.state)
        self:_trigger("line", line)
    end, "Paperknight DBG UCI", function() -- the engine exited
        self.state.to_uciok = -1
        self:_trigger("eof")
    end)
    -- the polling loops may run once more after stop(): never read a closed
    -- descriptor (its number can be reused by another file)
    self._reader = function() if not self.stopped then return read() end return 0 end
    local write = Utils.writer(self.fd_write, true, "Paperknight DBG UCI")
    self.send = function(line) if not self.stopped then write(line) end end
    return self
end

function UCIEngine:on(event, fn)
    assert(type(event) == "string", "event must be a string")
    assert(type(fn) == "function", "callback must be a function")
    self.callbacks[event] = self.callbacks[event] or {}
    table.insert(self.callbacks[event], fn)
end

function UCIEngine:_trigger(event, ...)
    local list = self.callbacks[event]
    if not list then return end
    for _, fn in ipairs(list) do
        pcall(fn, ...)
    end
end

--- Starts a UCI session ("uci"): the state starts over.
function UCIEngine:uci()
    self.state = { uciok = false, readyok = false, options = {}, to_uciok = 10, _engine = self }
    self.send("uci")
    self:_startPolling()
end

function UCIEngine:_startPolling()
    if self._poll or self.stopped then return end
    self._poll = function()
        if self.stopped then return end
        for _ = 1, 64 do -- all that is available, in 4 KB reads
            if self._reader() <= 0 then break end
        end
        if not self.stopped then UIManager:scheduleIn(POLL, self._poll) end
    end
    UIManager:scheduleIn(0, self._poll)
end

function UCIEngine:isready()
    self.state.readyok = false
    self.send("isready")
end

--- Sets an engine option (`value` nil: a button).
function UCIEngine:setOption(name, value)
    assert(type(name) == "string", "setOption: 'name' must be a string")
    self.send("setoption name " .. name .. (value ~= nil and (" value " .. tostring(value)) or ""))
    local opt = self.state.options[name] or {}
    opt.value = value
    self.state.options[name] = opt
end

--- "position": `spec` { fen = FEN or "startpos" (default), moves = "e2e4 e7e5" }.
function UCIEngine:position(spec)
    assert(type(spec) == "table", "position: expected a table")
    local fen = spec.fen or "startpos"
    assert(type(fen) == "string", "position: 'fen' must be a string")
    local cmd = "position " .. (fen == "startpos" and "startpos" or ("fen " .. fen))
    local moves = spec.moves and spec.moves:match("^%s*(.-)%s*$") or ""
    if #moves > 0 then cmd = cmd .. " moves " .. moves end
    self.send(cmd)
end

--- "go" with `opts` ({ movetime = 1000 }…); the bestmove comes as an event.
function UCIEngine:go(opts)
    local cmd = "go"
    for k, v in pairs(opts or {}) do cmd = cmd .. " " .. k .. " " .. tostring(v) end
    self.state.bestmove = nil
    self.send(cmd)
    self:_startPolling()
end

--- Stops the engine for good: ends the polling loops, asks it to quit (even
-- mid-search or before "uciok"), closes the pipes and reaps the process.
function UCIEngine:stop()
    if self.stopped then return end
    self.state.to_uciok = -1
    pcall(self.send, "stop")
    pcall(self.send, "quit")
    self.stopped = true
    if self._poll then UIManager:unschedule(self._poll) end
    Utils.closeProcess(self.pid, { self.fd_read, self.fd_write })
end

M.UCIEngine = UCIEngine
M._parseLine = parse_uci_line -- (specs)
return M
