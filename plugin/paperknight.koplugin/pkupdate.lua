-- In-app updates (docs/releasing.md): the latest release's install.sh does
-- the work (downloads, checksums, the plugin swap, the install records in
-- koreader/paperknight/.parts); this module asks it what changed
-- (`--list`), shows that, and runs it for the parts chosen (`--yes
-- --parts=...`), in the background, then offers to restart KOReader.
-- The installer is fetched with curl, as on the command line.
local T = require("ffi/util").template
local _ = require("pkgettext")

local PkUpdate = {
    DEFAULT_URL = "https://github.com/corentingi/paperknight/releases/latest/download/install.sh",
    POLL_SECONDS = 0.5,
    -- the longest a job is waited for (seconds): the installer's downloads
    -- give up by themselves when the network stalls (install.sh), this is
    -- the last resort when nothing answers at all
    CHECK_TIMEOUT = 180,
    APPLY_TIMEOUT = 30 * 60,
    NOTES_MAX_LINES = 10, -- in the update dialog (it does not scroll)
    -- tests: where to look for updates and the koreader folder
    url_override = nil,
    koreader_dir_override = nil,
}

local function pluginDir()
    local source = debug.getinfo(1, "S").source:gsub("^@", "")
    return source:match("(.*)/pkupdate%.lua$") or "."
end
PkUpdate.pluginDir = pluginDir

local function readFirstLine(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local line = f:read("*l")
    f:close()
    line = line and line:match("^%s*(.-)%s*$")
    return line ~= "" and line or nil
end
PkUpdate.readFirstLine = readFirstLine

--- The plugin's version (version.txt, written by the build), nil in a
-- development tree.
function PkUpdate.version()
    -- read once: the home screen shows it at every repaint
    if PkUpdate._version == nil then PkUpdate._version = readFirstLine(pluginDir() .. "/version.txt") or false end
    return PkUpdate._version or nil
end

--- The koreader folder: the plugin is <koreader>/plugins/paperknight.koplugin.
function PkUpdate.koreaderDir(plugin_dir)
    if PkUpdate.koreader_dir_override then return PkUpdate.koreader_dir_override end
    plugin_dir = plugin_dir or pluginDir()
    return plugin_dir:match("^(.*)/plugins/[^/]+$") or require("datastorage"):getDataDir()
end

--- Where the latest installer is (update-url.txt, written by the build).
function PkUpdate.url()
    return PkUpdate.url_override or readFirstLine(pluginDir() .. "/update-url.txt") or PkUpdate.DEFAULT_URL
end

--- The installed Stockfish version (its install record), "" if installed
-- otherwise (built by hand, an older installer), nil if not installed.
function PkUpdate.stockfishVersion()
    local v = readFirstLine(PkUpdate.koreaderDir() .. "/paperknight/.parts/stockfish")
    if v then return v end
    local lfs = require("libs/libkoreader-lfs")
    if lfs.attributes(pluginDir() .. "/bin/stockfish", "mode") == "file" then return "" end
end

PkUpdate.LABELS = {
    plugin = _("Paperknight"),
    puzzles = _("Puzzle pack"),
    fonts = _("Emoji font"),
    studies = _("Studies"),
    stockfish = _("Stockfish"),
}

function PkUpdate.human(bytes)
    bytes = tonumber(bytes) or 0
    if bytes >= 1048576 then return T(_("%1 MB"), math.floor(bytes / 1048576 + 0.5)) end
    return T(_("%1 KB"), math.floor((bytes + 1023) / 1024))
end

--- The installer's `--list` output: { part, have (nil: not installed),
-- version, size }, in its order.
function PkUpdate.parseList(text)
    local parts = {}
    for line in (text or ""):gmatch("[^\n]+") do
        local part, have, version, size = line:match("^([%w_-]+)|([^|]*)|([^|]*)|(%d+)$")
        if part then
            parts[#parts + 1] = { part = part, have = have ~= "" and have or nil, version = version, size = tonumber(size) }
        end
    end
    return parts
end

--- The release version written in an installer (VERSION='v0.2.0').
function PkUpdate.parseVersion(script)
    return (script or ""):match("\nVERSION='([^'\n]*)'")
end

--- The release notes written in an installer (NOTES='...', plain text
-- without '), at most `max_lines` lines (then "…"); nil if none.
function PkUpdate.parseNotes(script, max_lines)
    local notes = (script or ""):match("\nNOTES='([^']*)'")
    if not notes then return nil end
    local lines = {}
    for line in notes:gmatch("[^\n]+") do
        if line:find("%S") then lines[#lines + 1] = line end
    end
    if #lines == 0 then return nil end
    if max_lines and #lines > max_lines then
        lines[max_lines] = "…"
        for i = #lines, max_lines + 1, -1 do lines[i] = nil end
    end
    return table.concat(lines, "\n")
end

--- What to offer: `changes`, the installed parts with another version and
-- the missing ones (as install.sh does), and `stockfish`, a Stockfish not
-- installed (offered apart: a download not asked for otherwise).
function PkUpdate.plan(parts)
    local changes, stockfish = {}, nil
    for _, p in ipairs(parts) do
        if p.have ~= p.version then
            if p.part == "stockfish" and not p.have then
                stockfish = p
            else
                changes[#changes + 1] = p
            end
        end
    end
    return changes, stockfish
end

function PkUpdate.describe(p)
    local label = PkUpdate.LABELS[p.part] or p.part
    local what = p.have and T(_("%1 → %2"), p.have == "?" and _("unknown") or p.have, p.version)
        or T(_("install %1"), p.version)
    return T("%1: %2 (%3)", label, what, PkUpdate.human(p.size))
end

--- Whether installing `parts` replaces the plugin's own files (a puzzle
-- pack or Stockfish alone leaves the running code as it is).
function PkUpdate.changesPlugin(parts)
    for _, p in ipairs(parts) do
        if p.part == "plugin" then return true end
    end
    return false
end

local function names(parts)
    local out = {}
    for _, p in ipairs(parts) do out[#out + 1] = p.part end
    return table.concat(out, ",")
end
PkUpdate.names = names

---------------------------------------------------------------------------
-- Running shell commands in the background

local function q(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end
PkUpdate.quote = q

local function readFile(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

function PkUpdate.workDir()
    return PkUpdate.koreaderDir() .. "/paperknight/.update"
end

-- tests replace it (a scheduler they drive)
function PkUpdate._schedule(seconds, fn)
    require("ui/uimanager"):scheduleIn(seconds, fn)
end

-- Whether the job started last is still running: it wrote no status yet,
-- and its process is alive and still ours (its command line names the work
-- folder: a pid left from before a restart may belong to another process).
function PkUpdate.jobRunning()
    local work = PkUpdate.workDir()
    if readFile(work .. "/status") then return false end
    local pid = tonumber(readFirstLine(work .. "/pid") or "")
    if not pid then return false end
    local cmdline = readFile("/proc/" .. pid .. "/cmdline")
    if cmdline then return cmdline:find(work, 1, true) ~= nil end
    local code = os.execute("kill -0 " .. pid .. " 2>/dev/null") -- no /proc
    return code == 0 or code == true
end

--- Runs `cmd` (sh) in the background; `done(ok, output, timed_out)` when it
-- ends, or after `timeout` seconds without an end (the job is then left to
-- finish on its own: stopping the installer mid-way could leave the plugin
-- folder half swapped). A job still running from before is not started
-- twice: done(false, message).
function PkUpdate.run(cmd, done, timeout)
    if PkUpdate.jobRunning() then
        done(false, _("An update is still running. Try again in a minute."))
        return
    end
    local work = PkUpdate.workDir()
    os.execute("mkdir -p " .. q(work))
    local out, status, pidfile = work .. "/output", work .. "/status", work .. "/pid"
    os.remove(status)
    os.execute(T("( (%1) > %2 2>&1; echo $? > %3.part; mv %3.part %3 ) & echo $! > %4",
        cmd, q(out), q(status), q(pidfile)))
    local waited = 0
    local function poll()
        local code = readFile(status)
        if code then
            os.remove(status)
            os.remove(pidfile)
            done(tonumber(code) == 0, readFile(out) or "")
        elseif timeout and waited >= timeout then
            done(false, readFile(out) or "", true)
        else
            waited = waited + PkUpdate.POLL_SECONDS
            PkUpdate._schedule(PkUpdate.POLL_SECONDS, poll)
        end
    end
    PkUpdate._schedule(PkUpdate.POLL_SECONDS, poll)
end

-- The message of a job that failed: its last line, or that it timed out.
local function failure(output, timed_out)
    if timed_out then
        return _("No answer after several minutes (Wi-Fi lost?). Try again later.")
    end
    return PkUpdate.lastLine(output)
end

function PkUpdate.lastLine(text)
    local last
    for line in (text or ""):gmatch("[^\n]+") do last = line end
    return last or ""
end

---------------------------------------------------------------------------
-- The update, as the user sees it

local function installer() return PkUpdate.workDir() .. "/install.sh" end

local function installerCmd(args)
    return T("KOREADER_DIR=%1 sh %2 %3", q(PkUpdate.koreaderDir()), q(installer()), args)
end

local function show(widget)
    local UIManager = require("ui/uimanager")
    if PkUpdate.message then UIManager:close(PkUpdate.message) end
    PkUpdate.message = widget
    UIManager:show(widget)
    return widget
end

-- also the progress messages: dismissed, the work goes on and its result
-- shows when done
local function info(text)
    return show(require("ui/widget/infomessage"):new{ text = text })
end

-- An update job starts: the device stays awake until it ends (a Kindle
-- going to sleep mid-download cuts the connection).
local function busy()
    PkUpdate.busy = true
    if not PkUpdate._awake then
        PkUpdate._awake = true
        pcall(function() require("ui/uimanager"):preventStandby() end)
    end
end

local function idle()
    if PkUpdate.message then require("ui/uimanager"):close(PkUpdate.message) end
    PkUpdate.message = nil
    PkUpdate.busy = false
    if PkUpdate._awake then
        PkUpdate._awake = false
        pcall(function() require("ui/uimanager"):allowStandby() end)
    end
end

-- KOReader asks to restart now or later (where it can restart)
function PkUpdate._askForRestart(text)
    require("ui/uimanager"):askForRestart(text)
end

--- Loads every module of the plugin, and the data it reads on first use,
-- before the installer replaces the plugin's folder: the screens already
-- open keep running the old version until KOReader restarts, so nothing
-- they need later may come from the new one (ADR-0019). Returns how many
-- modules were loaded now.
function PkUpdate.preload()
    local lfs = require("libs/libkoreader-lfs")
    local loaded = 0
    for file in lfs.dir(pluginDir()) do
        local name = file:match("^(pk[%w_]+)%.lua$")
        if name and not package.loaded[name] then
            local ok, err = pcall(require, name)
            if ok then loaded = loaded + 1 else require("logger").warn("Paperknight: preload", name, err) end
        end
    end
    pcall(function() require("pkgames").list() end)
    pcall(function() require("pkopeningnames").of("") end)
    pcall(function() require("pkgettext")("") end)
    return loaded
end

--- After an update, until KOReader restarts: a mode asked for shows this
-- instead (the restart, or nothing).
function PkUpdate.askRestartFirst()
    PkUpdate._askForRestart(T(_("Paperknight was updated (%1).\nRestart KOReader to use it."),
        PkUpdate.installed or "?"))
end

--- Installs `parts` (from the list) with the downloaded installer.
function PkUpdate.apply(parts, release)
    local size = 0
    for _, p in ipairs(parts) do size = size + (p.size or 0) end
    busy()
    PkUpdate.preload()
    info(T(_("Updating Paperknight…\nDownloading %1."), PkUpdate.human(size)))
    PkUpdate.run(installerCmd("--yes --parts=" .. names(parts)), function(ok, output, timed_out)
        idle()
        if not ok then
            info(_("The update failed:") .. "\n" .. failure(output, timed_out))
            return
        end
        os.remove(installer())
        -- the plugin's files are the new version's from now on
        if PkUpdate.changesPlugin(parts) then PkUpdate.installed = release or "?" end
        PkUpdate._askForRestart(T(_("Paperknight is updated (%1).\nRestart KOReader to use it."), release or "?"))
    end, PkUpdate.APPLY_TIMEOUT)
end

--- The installer's answer: up to date, or what it would change (with the
-- release notes when the plugin changes).
function PkUpdate.offer(parts, release, notes)
    local ConfirmBox = require("ui/widget/confirmbox")
    local changes, stockfish = PkUpdate.plan(parts)
    if #changes == 0 and not stockfish then
        info(T(_("Paperknight is up to date (%1)."), release or "?"))
        return
    end
    local lines = {}
    for _, p in ipairs(changes) do lines[#lines + 1] = PkUpdate.describe(p) end
    local text, ok_text, other
    if #changes > 0 then
        text = T(_("Updates available (Paperknight %1):"), release or "?") .. "\n\n" .. table.concat(lines, "\n")
        if notes and changes[1].part == "plugin" then
            text = text .. "\n\n" .. T(_("What's new in %1:"), release or "?") .. "\n" .. notes
        end
        ok_text = _("Update")
        if stockfish then
            local with = { stockfish }
            for i, p in ipairs(changes) do with[i + 1] = p end
            other = {{{ text = T(_("Update and install Stockfish (%1)"), PkUpdate.human(stockfish.size)),
                        callback = function() PkUpdate.apply(with, release) end }}}
        end
    else
        text = T(_("Paperknight is up to date (%1).\n\nStockfish is not installed (%2): install it?"),
            release or "?", PkUpdate.human(stockfish.size))
        ok_text = _("Install")
        changes = { stockfish }
    end
    PkUpdate.confirm_box = show(ConfirmBox:new{
        text = text,
        ok_text = ok_text,
        ok_callback = function() PkUpdate.apply(changes, release) end,
        other_buttons = other,
        other_buttons_first = true,
    })
end

--- Downloads the latest installer and asks it what changed.
function PkUpdate.fetchAndCheck()
    busy()
    info(_("Checking for updates…"))
    local file = installer()
    local cmd = T("curl -fksSL --connect-timeout 30 --max-time 60 -o %1.part %2 && mv %1.part %1 && %3",
        q(file), q(PkUpdate.url()), installerCmd("--list"))
    PkUpdate.run(cmd, function(ok, output, timed_out)
        idle()
        if not ok then
            info(_("Could not check for updates.") .. "\n" .. failure(output, timed_out))
            return
        end
        local script = readFile(file)
        PkUpdate.offer(PkUpdate.parseList(output), PkUpdate.parseVersion(script),
            PkUpdate.parseNotes(script, PkUpdate.NOTES_MAX_LINES))
    end, PkUpdate.CHECK_TIMEOUT)
end

--- "Check for updates…": goes online (KOReader turns Wi-Fi on), then checks.
function PkUpdate.check()
    if PkUpdate.busy then return end
    require("ui/network/manager"):runWhenOnline(PkUpdate.fetchAndCheck)
end

return PkUpdate
