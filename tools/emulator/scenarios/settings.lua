-- The settings screen (pksettings.lua) and the in-app update (pkupdate.lua),
-- against a fake release served as a file:// URL: its install.sh answers
-- --list and records the --parts it is run with (the real installer is
-- tested by tools/dist/test-install.sh).
local UIManager = require("ui/uimanager")

return function(h)
    local PkNav = require("pknav")
    local PkUpdate = require("pkupdate")
    local function top() return UIManager._window_stack[#UIManager._window_stack].widget end
    local function menuItem(menu, text)
        for _, w in ipairs(menu.item_group) do
            if w.text and w.text:find(text, 1, true) then return w end
        end
    end
    -- the button whose text is `text` (h.findButton: the first containing it)
    local function exactButton(widget, text)
        local seen = {}
        local function walk(w)
            if type(w) ~= "table" or seen[w] then return nil end
            seen[w] = true
            if w.text == text and w.callback and w.dimen then return w end
            for key, v in pairs(w) do
                if key ~= "show_parent" and key ~= "parent" then
                    local found = walk(v)
                    if found then return found end
                end
            end
        end
        return walk(widget)
    end
    local function read(path)
        local f = io.open(path, "r")
        if not f then return nil end
        local s = f:read("*a")
        f:close()
        return s
    end
    local function write(path, text)
        local f = assert(io.open(path, "w"))
        f:write(text)
        f:close()
    end

    -- the fake release and koreader folder
    local root = os.getenv("HOME") .. "/update"
    local k = root .. "/koreader"
    os.execute("mkdir -p '" .. k .. "'")
    write(root .. "/install.sh", [[#!/bin/sh
VERSION='v9.9.9'
NOTES='
New:
• Studies: Something new
'
case "$*" in
    *--list*)
        if [ -f "$KOREADER_DIR/uptodate" ]; then
            echo "plugin|v9.9.9|v9.9.9|2048"; echo "stockfish|sf_18|sf_18|1048576"
        else
            echo "plugin|v1|v9.9.9|2048"; echo "puzzles|2026-01-01|2026-01-01|10"; echo "stockfish||sf_18|1048576"
        fi ;;
    *--parts=*)
        echo "$*" > "$KOREADER_DIR/applied"
        if [ -f "$KOREADER_DIR/hang" ]; then echo "Downloading x"; sleep 5; fi
        if [ -f "$KOREADER_DIR/fail" ]; then echo "Download failed (x): nothing changed."; exit 1; fi ;;
esac
]])
    PkUpdate.url_override = "file://" .. root .. "/install.sh"
    PkUpdate.koreader_dir_override = k
    local restart
    PkUpdate._askForRestart = function(text) restart = text end

    -- 1. From the home screen.
    PkNav.home()
    h.settle()
    local home = top()
    local item = menuItem(home, "Settings…")
    h.check(item, "Settings… on the home screen")
    h.check(home.item_table[#home.item_table].mandatory == nil, "no version in a development tree")
    h.tapWidget(item)
    h.settle()
    local settings = top()
    h.check(settings.name == "paperknight_settings", "settings shown: " .. tostring(settings.name))
    h.check(menuItem(settings, "Night mode: off"), "screen settings")
    local check_item = menuItem(settings, "Check for updates…")
    h.check(check_item, "check for updates")
    h.check(menuItem(settings, "Stockfish: install…"), "Stockfish not installed")
    h.shot("settings")

    -- 2. An update: what changed, then the installer for those parts.
    h.tapWidget(check_item)
    h.check(h.waitFor(function() return PkUpdate.confirm_box and top() == PkUpdate.confirm_box end, 10),
        "the update is offered")
    local box = PkUpdate.confirm_box
    h.check(box.text:find("Updates available (Paperknight v9.9.9):", 1, true), "release named: " .. box.text)
    h.check(box.text:find("Paperknight: v1 → v9.9.9 (2 KB)", 1, true), "plugin change listed")
    h.check(not box.text:find("Puzzle pack", 1, true), "the pack up to date: not listed")
    h.check(box.text:find("What's new in v9.9.9:\nNew:\n• Studies: Something new", 1, true), "release notes")
    h.check(h.findButton(box, "Update and install Stockfish (1 MB)"), "Stockfish offered apart")
    -- no CA bundle in this koreader folder: downloaded without the check, said
    h.check(box.text:find("could not check the download's certificate", 1, true) and not PkUpdate.verified(),
        "an unchecked download is said")
    h.shot("settings-update")
    h.tapWidget(exactButton(box, "Update"))
    h.check(h.waitFor(function() return restart end, 10), "restart offered")
    h.check(restart:find("Paperknight is updated (v9.9.9)", 1, true), "restart message: " .. tostring(restart))
    h.check((read(k .. "/applied") or ""):find("--yes --parts=plugin\n", 1, true),
        "installer run for the plugin only: " .. tostring(read(k .. "/applied")))
    h.check(top() == settings, "back to the settings")
    -- restart later (T5): every module was loaded before the installer ran,
    -- and no mode opens until KOReader restarts (ADR-0019)
    local lfs = require("libs/libkoreader-lfs")
    local plugin_dir = require("pkicons").plugin_dir
    local not_loaded = {}
    for file in lfs.dir(plugin_dir) do
        local name = file:match("^(pk[%w_]+)%.lua$")
        if name and not package.loaded[name] then not_loaded[#not_loaded + 1] = name end
    end
    h.check(#not_loaded == 0, "every module loaded before the update: " .. table.concat(not_loaded, " "))
    h.check(PkUpdate.installed == "v9.9.9", "the update is remembered until a restart")
    restart = nil
    h.check(PkNav.open("games") == nil and restart and restart:find("Paperknight was updated (v9.9.9)", 1, true),
        "a mode asks for the restart instead: " .. tostring(restart))
    h.check(not (top().name or ""):find("games", 1, true), "Master games not opened")
    PkUpdate.installed = nil -- (the rest of the scenario: as before the update)
    PkNav.showSettings()
    h.settle()
    settings = top()
    check_item = menuItem(settings, "Check for updates…")

    -- 3. A failed update, with Stockfish this time.
    restart = nil
    write(k .. "/fail", "")
    h.tapWidget(check_item)
    h.check(h.waitFor(function() return PkUpdate.confirm_box ~= box and top() == PkUpdate.confirm_box end, 10),
        "offered again")
    h.tapWidget(h.findButton(PkUpdate.confirm_box, "Update and install Stockfish"))
    h.check(h.waitFor(function()
        return top().text and top().text:find("The update failed:\nDownload failed (x): nothing changed.", 1, true)
    end, 10), "failure shown: " .. tostring(top().text))
    h.check((read(k .. "/applied") or ""):find("--parts=stockfish,plugin", 1, true), "Stockfish and the plugin")
    h.check(not restart, "no restart after a failure")
    UIManager:close(top())
    h.settle()

    -- 3b. An update that never answers: given up after its time, the device
    -- allowed to sleep again, and not started twice while it still runs.
    os.remove(k .. "/fail")
    write(k .. "/hang", "")
    local standby = UIManager._prevent_standby_count or 0
    local apply_timeout = PkUpdate.APPLY_TIMEOUT
    PkUpdate.APPLY_TIMEOUT = 1
    h.tapWidget(check_item)
    h.check(h.waitFor(function() return PkUpdate.confirm_box and top() == PkUpdate.confirm_box end, 10),
        "offered once more")
    h.tapWidget(exactButton(PkUpdate.confirm_box, "Update"))
    h.check((UIManager._prevent_standby_count or 0) == standby + 1, "kept awake while updating")
    h.check(h.waitFor(function()
        return top().text and top().text:find("The update failed:\nNo answer after several minutes", 1, true)
    end, 10), "given up: " .. tostring(top().text))
    h.check((UIManager._prevent_standby_count or 0) == standby, "allowed to sleep again")
    h.check(not PkUpdate.busy and PkUpdate.jobRunning(), "not busy; the job left to finish")
    UIManager:close(top())
    h.settle()
    h.tapWidget(check_item)
    h.check(h.waitFor(function()
        return top().text and top().text:find("An update is still running", 1, true)
    end, 10), "not started twice: " .. tostring(top().text))
    UIManager:close(top())
    h.settle()
    PkUpdate.APPLY_TIMEOUT = apply_timeout
    os.remove(k .. "/hang")
    h.check(h.waitFor(function() return not PkUpdate.jobRunning() end, 10), "the job ended")

    -- 4. Up to date; KOReader's CA bundle there: the download checked.
    write(k .. "/uptodate", "")
    os.execute("mkdir -p '" .. k .. "/data' && cp data/ca-bundle.crt '" .. k .. "/data/'")
    h.tapWidget(check_item)
    h.check(h.waitFor(function()
        return top().text and top().text:find("Paperknight is up to date (v9.9.9).", 1, true)
    end, 10), "up to date: " .. tostring(top().text))
    h.check(PkUpdate.verified(), "the installer's certificate checked")
    h.check(not top().text:find("certificate", 1, true), "checked: nothing said")
    UIManager:close(top())
    h.settle()
    -- up to date but unchecked: said all the same (one check tells after an update)
    PkUpdate.offer(PkUpdate.parseList("plugin|v9.9.9|v9.9.9|2048\n"), "v9.9.9", nil, true)
    h.settle()
    h.check(top().text:find("Paperknight is up to date (v9.9.9).", 1, true)
        and top().text:find("could not check the download's certificate", 1, true), "unchecked, up to date: said")
    UIManager:close(top())
    h.settle()

    -- 4b. Checked once, then a check that fails (an attacker, or a broken
    -- network): no going back to an unchecked download.
    local fake = root .. "/fake-curl.sh"
    write(fake, '#!/bin/sh\ncase "$*" in *--cacert*) exit 60;; esac\nexec curl "$@"\n')
    os.execute("chmod +x '" .. fake .. "'")
    PkUpdate.CURL = fake
    h.tapWidget(check_item)
    h.check(h.waitFor(function()
        return top().text and top().text:find("Could not check for updates.", 1, true)
            and top().text:find("though it could before", 1, true)
    end, 10), "no fallback once verified: " .. tostring(top().text))
    UIManager:close(top())
    h.settle()
    PkUpdate.CURL = "curl"

    -- 5. No release there.
    PkUpdate.url_override = "file://" .. root .. "/missing/install.sh"
    h.tapWidget(check_item)
    h.check(h.waitFor(function()
        return top().text and top().text:find("Could not check for updates.", 1, true)
    end, 10), "check failed: " .. tostring(top().text))
    UIManager:close(top())
    h.settle()

    -- 6. Report a problem: the issue forms as a QR code, the versions to copy.
    h.tapWidget(menuItem(settings, "Report a problem…"))
    h.settle()
    h.check(top().text == "https://github.com/corentingi/paperknight/issues/new/choose", "report QR: " .. tostring(top().text))
    local caption = tostring(top().caption)
    h.check(caption:find("^Paperknight development · KOReader [%d.]+ · ") ~= nil, "the versions shown: " .. caption)
    UIManager:close(top())
    h.settle()

    -- 6b. The project page, and the settings from the quick settings.
    h.tapWidget(menuItem(settings, "Project page…"))
    h.settle()
    h.check(top().text == "https://github.com/corentingi/paperknight", "project QR code: " .. tostring(top().text))
    UIManager:close(top())
    h.settle()
    PkNav.home()
    h.settle()
    h.check(top().name == "paperknight_home", "home closes the settings")
    local quick = PkNav.showQuick("home")
    h.settle()
    h.tapWidget(h.findButton(quick, "Settings…"))
    h.settle()
    h.check(top().name == "paperknight_settings", "settings from the quick settings")
end
