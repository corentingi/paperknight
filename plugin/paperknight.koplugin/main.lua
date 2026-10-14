-- Paperknight plugin: menu entries, the dispatcher action and the modes'
-- entry points. Each screen is its own widget (pkgame.lua, pkpuzzleview.lua,
-- pkstudies.lua, pkopenings.lua; navigation in pknav.lua).
local DataStorage = require("datastorage")
local Dispatcher = require("dispatcher")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local infoMessage = require("ui/widget/infomessage")
local lfs = require("libs/libkoreader-lfs")
local PkGame = require("pkgame")
local PkNav = require("pknav")
local Logger = require("logger")
local _ = require("gettext")

local Paperknight = WidgetContainer:extend{
    name = "paperknight",
}

--- Paperknight:init()
-- Initializes the Paperknight application, registers it with the dispatcher
-- and adds it to the main menu.
function Paperknight:init()
    -- emojis in studies render if a Noto Emoji font is installed
    local ok, err = pcall(function() require("pkfonts").addEmojiFallback() end)
    if not ok then Logger.warn("Paperknight: emoji font:", err) end

    -- Register a dispatcher action to allow starting Paperknight from elsewhere
    Dispatcher:registerAction("paperknight", {
        category = "none",
        event = "PaperknightStart",
        title = _("Paperknight"),
        general = true,
    })

    -- Register this instance to the UIManager's main menu
    self.ui.menu:registerToMainMenu(self)
    PkNav.app = self
end

--- Whether the engine binary is installed ("Play against the engine").
function Paperknight:hasEngine()
    return PkGame.hasEngine()
end

--- Paperknight:onPaperknightStart()
-- Handler for the dispatcher action registered in init (gesture/hotkey launch).
function Paperknight:onPaperknightStart()
    PkNav.home()
    return true
end

--- Paperknight:addToMainMenu(menu_items)
-- Callback for the UIManager to add Paperknight as an option in the main menu.
-- @param menu_items Table of menu items to append to.
function Paperknight:addToMainMenu(menu_items)
    menu_items.paperknight = {
        text = _("Paperknight"),
        sorting_hint = "tools", -- Suggests where it should appear in the menu
        -- each mode opens above the home screen (closing it goes back there)
        sub_item_table = {
            {
                text = _("Home"),
                callback = function() PkNav.home() end,
                separator = true,
            },
            {
                text = _("Puzzles"),
                callback = function() PkNav.open("puzzles") end,
            },
            {
                text = _("Studies"),
                callback = function() PkNav.open("studies") end,
            },
            {
                text = _("Openings"),
                callback = function() PkNav.open("openings") end,
            },
            {
                text = _("Play against the engine"),
                -- Paperknight: no engine binary ships for the Kindle yet; the
                -- inherited game screen misbehaves without one
                enabled_func = function() return self:hasEngine() end,
                callback = function() PkNav.open("play") end,
            },
        },
    }
end

--- Paperknight:packsDir()
-- Data packs live in <plugin>/packs; PAPERKNIGHT_PACKS_DIR overrides it (tests).
function Paperknight:packsDir()
    return os.getenv("PAPERKNIGHT_PACKS_DIR") or (PkGame.PLUGIN_PATH .. "/packs")
end

--- Paperknight:startPuzzles()
-- Opens the puzzle screen (ADR-0009). Returns the view, or nil if no pack.
function Paperknight:startPuzzles()
    local PkProgress = require("pkprogress")
    local PkPuzzlePack = require("pkpuzzlepack")
    local PkPuzzleView = require("pkpuzzleview")
    local pack_path = self:packsDir() .. "/puzzles.sqlite"
    local pack, err = PkPuzzlePack.open(pack_path)
    if not pack then
        Logger.warn("Paperknight:", err)
        UIManager:show(infoMessage:new{
            text = _("No puzzle pack found.") .. "\n" .. _("Copy puzzles.sqlite to:") .. "\n" .. self:packsDir()
                .. "\n\n(" .. tostring(err) .. ")",
        })
        return nil
    end
    if pack:count() == 0 then
        pack:close()
        UIManager:show(infoMessage:new{ text = _("The puzzle pack is empty.") })
        return nil
    end
    local ok, progress = pcall(PkProgress.open, DataStorage:getSettingsDir() .. "/paperknight/progress.sqlite")
    if not ok then
        pack:close()
        Logger.warn("Paperknight: cannot open progress database:", progress)
        UIManager:show(infoMessage:new{
            text = _("Cannot open the progress database.") .. "\n" .. tostring(progress),
        })
        return nil
    end
    local view = PkPuzzleView:new{ pack = pack, progress = progress }
    UIManager:show(view)
    return view
end

--- Paperknight:startGame()
-- Entry point for starting a new chess game.
-- Initializes all game components (logic, engine, board) and builds the UI.
function Paperknight:startGame()
    Logger.info("Paperknight: new game")
    self.game_view = PkGame:new{}
    local view = self.game_view
    local on_close = view.onCloseWidget
    view.onCloseWidget = function(v)
        on_close(v)
        if self.game_view == v then self.game_view = nil end
    end
    UIManager:show(view)
    return view
end

return Paperknight
