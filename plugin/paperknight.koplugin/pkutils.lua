local UIManager = require("ui/uimanager")
local ffi = require("ffi")
local C = ffi.C
local Logger = require("logger")

ffi.cdef[[
    typedef long ssize_t;
    int pipe(int[2]);
    int fork(void);
    int execvp(const char *, char *const argv[]);
    void _exit(int);
    int waitpid(int, int *, int);
    int dup2(int, int);
    int close(int);
    int setpgid(int, int);
    int sched_setscheduler(int, int, void *);
    int setpriority(int, int, int);
    ssize_t read(int, void *, size_t);
    ssize_t write(int, const void *, size_t);
    int poll(struct pollfd *fds, unsigned long nfds, int timeout);
    char *strerror(int);
    ]]

    local SCHED_BATCH = 3
    local PRIO_PROCESS = 0
    local POLLIN = 0x001

local BUF_SZ = 4096
local WNOHANG, SIGTERM, SIGKILL = 1, 15, 9
pcall(ffi.cdef, "int kill(int, int);") -- may already be declared (ffi/posix_h)


local Utils = {}

function Utils.pollingLoop(timeout, action, condition, delayed)
    local loop
    loop = function()
        if condition and condition() then
            UIManager:scheduleIn(timeout, loop)
        end
        action()
    end

    UIManager:scheduleIn(delayed and timeout or 0, loop)
end

--- Closes a child process's file descriptors and reaps it: it is given about
-- a second to exit on its own (e.g. after "quit"), then SIGTERM, then SIGKILL.
-- Never blocks the UI: the checks are scheduled.
function Utils.closeProcess(pid, fds)
    for _, fd in ipairs(fds or {}) do
        if fd and fd >= 0 then C.close(fd) end
    end
    if not pid or pid <= 0 then return end
    local tries = 0
    local function reap()
        tries = tries + 1
        if C.waitpid(pid, nil, WNOHANG) ~= 0 then return end -- exited (pid), or gone (-1)
        if tries == 6 then C.kill(pid, SIGTERM) end
        if tries >= 11 then
            C.kill(pid, SIGKILL)
            C.waitpid(pid, nil, 0) -- immediate after SIGKILL
            return
        end
        UIManager:scheduleIn(0.2, reap)
    end
    reap()
end

function Utils.execInSubProcess(cmd, args, with_pipes, double_fork)
  local p2c_r, p2c_w, c2p_r, c2p_w

  if with_pipes then
    local p1 = ffi.new("int[2]")
    if C.pipe(p1) ~= 0 then
      local err = ffi.errno()
      return false, "pipe1: " .. ffi.string(C.strerror(err))
    end
    p2c_r, p2c_w = p1[0], p1[1]

    local p2 = ffi.new("int[2]")
    if C.pipe(p2) ~= 0 then
      C.close(p2c_r); C.close(p2c_w)
      local err = ffi.errno()
      return false, "pipe2: " .. ffi.string(C.strerror(err))
    end
    c2p_r, c2p_w = p2[0], p2[1]
  end

  local pid = C.fork()
  if pid < 0 then
    if with_pipes then C.close(p2c_r); C.close(p2c_w); C.close(c2p_r); C.close(c2p_w) end
    local err = ffi.errno()
    return false, "fork: " .. ffi.string(C.strerror(err))
  end

  if pid == 0 then
    if double_fork and C.fork() ~= 0 then C._exit(0) end
    C.setpgid(0, 0)
    if ffi.os == "Linux" then C.sched_setscheduler(0, SCHED_BATCH, nil) end
    C.setpriority(PRIO_PROCESS, 0, 5)

    if with_pipes then
      C.close(p2c_w)
      C.dup2(p2c_r, 0); C.close(p2c_r)
      C.close(c2p_r)
      C.dup2(c2p_w, 1); C.dup2(c2p_w, 2); C.close(c2p_w)
    end

    local argc = #args
    local argv = ffi.new("char *[?]", argc + 1)
    for i = 1, argc do argv[i - 1] = ffi.cast("char *", args[i]) end
    argv[argc] = nil
    C.execvp(cmd, argv)
    local err = ffi.errno()
    io.stderr:write("execvp(", cmd, ") failed: ", ffi.string(C.strerror(err)), "\n")
    io.stderr:write("kill", "\n")
    C._exit(127)
  end

  if double_fork then C.waitpid(pid, ffi.new("int[1]"), 0) end
  if with_pipes then C.close(p2c_r); C.close(c2p_w) end
  return pid, c2p_r, p2c_w
end

--- Returns a function that reads what is available on `fd` without blocking
-- and calls `action(line)` for each complete line. A line split across reads
-- is kept until its end arrives. `on_eof()`: called once when the other side
-- closed the pipe (the process exited).
function Utils.reader(fd, action, dbg, on_eof)
    local pending, ended = "", false
    local function log(line)
        Logger.dbg((dbg or "") .. "< " .. line)
        if dbg and dbg:find("Paperknight DBG UCI") then
            Logger.info((dbg or "") .. " < " .. line)
        end
    end
    local _reader = function()
        if ended then return end
        local pollfds = ffi.new("struct pollfd[1]")
        pollfds[0].fd = fd
        pollfds[0].events = POLLIN
        local ret = C.poll(pollfds, 1, 0) -- 0 ms timeout for non-blocking
        if ret <= 0 or pollfds[0].revents == 0 then
            return -- No data available
        end
        local buf = ffi.new("char[?]", BUF_SZ)
        local n = C.read(fd, buf, BUF_SZ - 1)
        if n == 0 then -- end of file: the process closed its output
            ended = true
            if #pending > 0 then log(pending); if action then action(pending) end end
            pending = ""
            if on_eof then on_eof() end
            return
        end
        if n < 0 then return end
        pending = pending .. ffi.string(buf, n)
        local last = 1
        for line, next_pos in pending:gmatch("([^\n]*)\n()") do
            log(line)
            if action then action(line) end
            last = next_pos
        end
        pending = pending:sub(last)
    end
    return _reader
end


function Utils.writer(fd, eol, dbg)
    local _writer = function (cmd)
        local line = cmd .. (eol and "\n" or "")
        Logger.dbg((dbg or "") .. " > " .. line)
        if dbg and dbg:find("Paperknight DBG UCI") then
            Logger.info((dbg or "") .. " > " .. line)
        end
        local n = C.write(fd, line, #line)
        if n ~= #line then
            local err = ffi.errno()
            Logger.info((dbg or "") .. " write error: n=" .. tostring(n)
                .. " errno=" .. tostring(err) .. " (" .. ffi.string(C.strerror(err)) .. ")")
            return
        end
    end
    return _writer
end


return Utils
