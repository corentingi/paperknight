-- The settings screen (from the home screen and the quick settings): screen
-- settings, the version and updates (pkupdate.lua), Stockfish, the project
-- page. The modes' own options stay in their ☰ menus.
local UIManager = require("ui/uimanager")
local _ = require("pkgettext")
local PkNav = require("pknav")
local PkUpdate = require("pkupdate")

local PkSettings = {
    PROJECT_URL = "https://github.com/corentingi/paperknight",
    REPORT_URL = "https://github.com/corentingi/paperknight/issues/new/choose",
}

local function stockfishItem()
    local v = PkUpdate.stockfishVersion()
    if v then
        return { text = _("Stockfish"), mandatory = v ~= "" and v or _("installed"), select_enabled = false }
    end
    -- the update check offers to install it
    return { text = _("Stockfish: install…"), mandatory = _("not installed"), callback = PkUpdate.check }
end

local function onOff(value) return value and _("on") or _("off") end

-- The board's switches (pkprefs.lua); `refresh` shows the new value
local function boardItems(items, refresh)
    local PkPrefs = require("pkprefs")
    items[#items + 1] = {
        text = _("Board coordinates"),
        mandatory = onOff(PkPrefs.get("coordinates")),
        callback = function() PkPrefs.toggle("coordinates"); refresh() end,
    }
    items[#items + 1] = {
        text = _("Show legal moves"),
        mandatory = onOff(PkPrefs.get("legal_moves")),
        callback = function() PkPrefs.toggle("legal_moves"); refresh() end,
    }
    return items
end

local menu

--- Offers to put back the daily copy of the progress file (pkprogress.lua):
-- `problem`, why (nil: asked from the settings); `after()` once restored.
-- Says so when there is no copy.
function PkSettings.offerRestore(problem, after)
    local T = require("ffi/util").template
    local PkProgress = require("pkprogress")
    local made = PkProgress.backupTime()
    local intro = problem and (_("Your progress file cannot be opened.") .. "\n" .. problem .. "\n\n") or ""
    if not made then
        UIManager:show(require("ui/widget/infomessage"):new{
            text = intro .. _("There is no copy of it yet: a copy is made once a day."),
        })
        return
    end
    UIManager:show(require("ui/widget/confirmbox"):new{
        text = intro .. T(_("Put back the copy of your progress made on %1?\nWhat you did since then is lost."),
            os.date("%Y-%m-%d %H:%M", made)),
        ok_text = _("Restore"),
        ok_callback = function()
            local ok, err = pcall(PkProgress.restoreBackup)
            UIManager:show(require("ui/widget/infomessage"):new{
                text = ok and _("Your progress is restored.") or (_("The copy cannot be restored:") .. "\n" .. tostring(err)),
            })
            if ok and after then after() end
        end,
    })
end

function PkSettings.items()
    local items = PkNav.screenItems({})
    items[#items].separator = true
    boardItems(items, function()
        if menu then menu:switchItemTable(nil, PkSettings.items()) end
    end)
    items[#items].separator = true
    items[#items + 1] = {
        text = _("Check for updates…"),
        mandatory = PkUpdate.version() or _("development"),
        callback = PkUpdate.check,
    }
    items[#items + 1] = stockfishItem()
    local made = require("pkprogress").backupTime()
    items[#items + 1] = {
        text = _("Restore progress from its copy…"),
        mandatory = made and os.date("%Y-%m-%d", made) or _("none yet"),
        callback = function()
            PkSettings.offerRestore(nil, function()
                if menu then menu:switchItemTable(nil, PkSettings.items()) end
            end)
        end,
    }
    items[#items + 1] = {
        text = _("Report a problem…"),
        callback = function()
            local T = require("ffi/util").template
            require("pklinks").showQR({
                url = PkSettings.REPORT_URL,
                -- what the report asks for, to copy from the screen
                caption = T(_("Paperknight %1 · KOReader %2 · %3"), PkUpdate.version() or _("development"),
                    PkSettings.koreaderVersion(), PkSettings.deviceName()),
            })
        end,
    }
    items[#items + 1] = {
        text = _("Project page…"),
        callback = function()
            require("pklinks").showQR({ url = PkSettings.PROJECT_URL })
        end,
    }
    return items
end

--- KOReader's version ("2026.07"), "?" if unknown.
function PkSettings.koreaderVersion()
    local ok, Version = pcall(require, "version")
    local v = ok and Version.getCurrentRevision and Version:getCurrentRevision()
    return v and (v:match("^v?([%d.]+)") or v) or "?"
end

--- The device's model as KOReader names it ("KindlePaperWhite2").
function PkSettings.deviceName()
    local ok, Device = pcall(require, "device")
    return ok and Device.model or "?"
end

function PkSettings.show()
    menu = PkNav.liveMenu("paperknight_settings", _("Settings"), PkSettings.items)
    PkNav.tapTitle(menu, function() return menu.title_bar end, "settings")
    UIManager:show(menu)
    return menu
end

return PkSettings
