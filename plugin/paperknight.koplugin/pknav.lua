-- Navigation between the modes, and screen settings (ADR-0015):
--  * the home screen: the modes, with a status line, and screen settings;
--  * quick settings: a pop-up with frontlight, night mode and the other
--    modes, from every screen's ☰ menu or a tap on its title;
--  * switching mode closes the Paperknight screens above the home screen.
-- Frontlight and night mode are KOReader's own (its frontlight dialog and
-- its ToggleNightMode event), so its settings stay the source of truth.
local ButtonDialog = require("ui/widget/buttondialog")
local DataStorage = require("datastorage")
local Device = require("device")
local Event = require("ui/event")
local GestureRange = require("ui/gesturerange")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template

local Screen = Device.screen

local PkNav = {
    app = nil, -- the plugin instance (main.lua): starts puzzles and games
}

local HOME = "paperknight_home"

local function isPkScreen(w)
    return type(w) == "table" and type(w.name) == "string" and w.name:find("^paperknight_") ~= nil
end

--- The Paperknight screens currently shown, top first.
function PkNav.screens()
    local out = {}
    local stack = UIManager._window_stack or {}
    for i = #stack, 1, -1 do
        local w = stack[i].widget
        if isPkScreen(w) then out[#out + 1] = w end
    end
    return out
end

function PkNav.homeShown()
    for _, w in ipairs(PkNav.screens()) do
        if w.name == HOME then return w end
    end
end

--- Closes every Paperknight screen above the home screen (all of them
-- when `with_home`). A screen can clean up in `pk_close` (the game).
function PkNav.closeScreens(with_home)
    for _, w in ipairs(PkNav.screens()) do
        if w.name ~= HOME or with_home then
            if w.pk_close then w:pk_close() else UIManager:close(w) end
        end
    end
end

-- The engine binary is looked for once per session (a file stat).
local engine_present
local function hasEngine()
    if engine_present == nil then
        engine_present = PkNav.app ~= nil and PkNav.app:hasEngine() or false
    end
    return engine_present
end

--- The modes: { id, text, start }.
function PkNav.modes()
    local modes = {
        { id = "puzzles", text = _("Puzzles"), start = function() return PkNav.app:startPuzzles() end },
        { id = "studies", text = _("Studies"), start = function() return require("pkstudies").show() end },
        { id = "openings", text = _("Openings"), start = function() return require("pkopenings").show() end },
        { id = "analysis", text = _("Analysis board"), start = function() return PkNav.app:startAnalysis() end },
        -- against Stockfish when installed, else two players on one board
        { id = "play", text = hasEngine() and _("Play") or _("Play (two players)"),
          start = function() return PkNav.app:startGame() end },
    }
    return modes
end

--- Opens mode `id` above the home screen (shown first if needed), closing
-- the other Paperknight screens.
function PkNav.open(id)
    PkNav.closeScreens(false)
    if not PkNav.homeShown() then PkNav.showHome() end
    for _, mode in ipairs(PkNav.modes()) do
        if mode.id == id then return mode.start() end
    end
end

--- Back to the home screen.
function PkNav.home()
    PkNav.closeScreens(false)
    if not PkNav.homeShown() then PkNav.showHome() end
end

---------------------------------------------------------------------------
-- Screen settings

function PkNav.hasFrontlight()
    return Device:hasFrontlight()
end

function PkNav.showFrontlight()
    UIManager:show(require("ui/widget/frontlightwidget"):new{})
end

function PkNav.toggleNightMode()
    -- KOReader's DeviceListener (in the file manager or reader underneath)
    -- toggles the screen, saves the setting and repaints everything
    UIManager:broadcastEvent(Event:new("ToggleNightMode"))
end

local function nightLabel()
    return Screen.night_mode and _("Night mode: on") or _("Night mode: off")
end

---------------------------------------------------------------------------
-- Quick settings

--- ButtonDialog rows: screen settings, then the other modes and Home.
-- `close`: closes the dialog; `current`: id of the mode shown (skipped).
function PkNav.quickRows(close, current)
    local rows = {}
    local screen_row = {}
    if PkNav.hasFrontlight() then
        screen_row[#screen_row + 1] = { text = _("Frontlight…"), callback = function() close(); PkNav.showFrontlight() end }
    end
    screen_row[#screen_row + 1] = { text = nightLabel(), callback = function() close(); PkNav.toggleNightMode() end }
    rows[#rows + 1] = screen_row
    local mode_row = {}
    for _, mode in ipairs(PkNav.modes()) do
        if mode.id ~= current then
            mode_row[#mode_row + 1] = { text = mode.text, callback = function() close(); PkNav.open(mode.id) end }
        end
    end
    rows[#rows + 1] = mode_row
    if current ~= "home" then
        rows[#rows + 1] = {{ text = _("Home"), callback = function() close(); PkNav.home() end }}
    end
    return rows
end

--- The quick settings pop-up (`current`: the mode shown).
function PkNav.showQuick(current)
    local dialog
    local function close() UIManager:close(dialog) end
    dialog = ButtonDialog:new{ title = _("Paperknight"), title_align = "center", buttons = PkNav.quickRows(close, current) }
    PkNav.quick_dialog = dialog -- tests
    UIManager:show(dialog)
    return dialog
end

--- A tap on the title of `widget` (its title bar given by `get_title_bar`,
-- outside the icons, which handle their own taps) opens the quick settings.
function PkNav.tapTitle(widget, get_title_bar, current)
    local events = {}
    for k, v in pairs(widget.ges_events or {}) do events[k] = v end
    events.PkTapTitle = { GestureRange:new{
        ges = "tap",
        range = function()
            local bar = get_title_bar()
            return bar and bar.dimen
        end,
    } }
    widget.ges_events = events
    widget.onPkTapTitle = function()
        PkNav.showQuick(current)
        return true
    end
end

---------------------------------------------------------------------------
-- Home screen

-- "Rating 1480 · 3 reviews due" (nil if the progress database can't be read).
-- Cached: the home screen paints often, and the status needs the progress
-- database. PkNav.statusChanged() (the puzzle screen closing) recomputes it.
local status_cache = { version = -1 }
PkNav.status_version = 0

--- The puzzle progress changed: the home screen's status is recomputed.
function PkNav.statusChanged()
    PkNav.status_version = PkNav.status_version + 1
end

local function computePuzzlesStatus()
    local progress
    local ok, text = pcall(function()
        local PkProgress = require("pkprogress")
        local PkSrs = require("pksrs")
        progress = PkProgress.open(DataStorage:getSettingsDir() .. "/paperknight/progress.sqlite")
        local rating, due = progress:rating(), progress:reviewDueCount(PkSrs.today())
        local s = T(_("Rating %1"), math.floor(rating + 0.5))
        if due > 0 then s = s .. " · " .. T(_("%1 to review"), due) end
        return s
    end)
    if progress then pcall(progress.close, progress) end -- also after an error
    if not ok then logger.warn("Paperknight: home status:", text) end
    return ok and text or nil
end

local function puzzlesStatus()
    if status_cache.version ~= PkNav.status_version then
        status_cache.text = computePuzzlesStatus()
        status_cache.version = PkNav.status_version
    end
    return status_cache.text
end

function PkNav.homeItems()
    local items = {}
    for _, mode in ipairs(PkNav.modes()) do
        items[#items + 1] = {
            text = mode.text,
            mandatory = mode.id == "puzzles" and puzzlesStatus() or nil,
            callback = function() mode.start() end,
        }
    end
    items[#items].separator = true
    if PkNav.hasFrontlight() then
        items[#items + 1] = { text = _("Frontlight…"), callback = PkNav.showFrontlight }
    end
    items[#items + 1] = { text = nightLabel(), callback = PkNav.toggleNightMode }
    return items
end

local function itemsKey(items)
    local parts = {}
    for _, it in ipairs(items) do parts[#parts + 1] = it.text .. "=" .. (it.mandatory or "") end
    return table.concat(parts, "|")
end

--- Shows the home screen. Its items follow the state (rating, reviews due,
-- night mode): a repaint (e.g. back from a mode) rebuilds them if changed.
function PkNav.showHome()
    local items = PkNav.homeItems()
    local menu = Menu:new{
        name = HOME,
        title = _("Paperknight"),
        item_table = items,
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        title_bar_left_icon = "appbar.menu",
    }
    menu.onLeftButtonTap = function() PkNav.showQuick("home") end
    PkNav.tapTitle(menu, function() return menu.title_bar end, "home")
    menu._pk_key = itemsKey(items)
    local paintTo = menu.paintTo
    menu.paintTo = function(m, bb, x, y)
        paintTo(m, bb, x, y)
        local now = PkNav.homeItems()
        local key = itemsKey(now)
        if key ~= m._pk_key then
            m._pk_key = key
            -- not while painting: rebuild on the next tick
            UIManager:nextTick(function() m:switchItemTable(nil, now) end)
        end
    end
    UIManager:show(menu)
    return menu
end

return PkNav
