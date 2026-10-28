-- The settings screen (from the home screen and the quick settings): screen
-- settings, the version and updates (pkupdate.lua), Stockfish, the project
-- page. The modes' own options stay in their ☰ menus.
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local PkNav = require("pknav")
local PkUpdate = require("pkupdate")

local PkSettings = {
    PROJECT_URL = "https://github.com/corentingi/paperknight",
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
    items[#items + 1] = {
        text = _("Project page…"),
        callback = function()
            require("pklinks").showQR({ url = PkSettings.PROJECT_URL })
        end,
    }
    return items
end

function PkSettings.show()
    menu = PkNav.liveMenu("paperknight_settings", _("Settings"), PkSettings.items)
    PkNav.tapTitle(menu, function() return menu.title_bar end, "settings")
    UIManager:show(menu)
    return menu
end

return PkSettings
