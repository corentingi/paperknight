-- Studies browser: PGN files in the studies folder, then their chapters
-- (ADR-0011). Opening a chapter shows pkstudyview.
local DataStorage = require("datastorage")
local InfoMessage = require("ui/widget/infomessage")
local Menu = require("ui/widget/menu")
local PathChooser = require("ui/widget/pathchooser")
local Screen = require("device").screen
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local T = require("ffi/util").template

local PkStudy = require("pkstudy")
local PkStudyView = require("pkstudyview")

local PkStudies = {}

--- Studies folder: <KOReader data dir>/paperknight/studies (created if
-- missing); PAPERKNIGHT_STUDIES_DIR overrides it (tests).
function PkStudies.dir()
    local dir = os.getenv("PAPERKNIGHT_STUDIES_DIR")
    if dir then return dir end
    local base = DataStorage:getFullDataDir() .. "/paperknight"
    dir = base .. "/studies"
    for _, d in ipairs({ base, dir }) do
        if lfs.attributes(d, "mode") ~= "directory" then
            local ok, err = lfs.mkdir(d)
            if not ok then logger.warn("Paperknight: cannot create", d, err) end
        end
    end
    return dir
end

--- Sorted list of .pgn files in `dir`.
function PkStudies.listFiles(dir)
    local files = {}
    if lfs.attributes(dir, "mode") ~= "directory" then return files end
    local ok, iter, dir_obj = pcall(lfs.dir, dir) -- throws on unreadable folders
    if not ok then
        logger.warn("Paperknight: cannot list", dir, iter)
        return files
    end
    for entry in iter, dir_obj do
        if entry:lower():match("%.pgn$") and lfs.attributes(dir .. "/" .. entry, "mode") == "file" then
            files[#files + 1] = entry
        end
    end
    table.sort(files, function(a, b) return a:lower() < b:lower() end)
    return files
end

local function fullscreenMenu(title, items)
    local menu = Menu:new{
        title = title,
        item_table = items,
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
    }
    -- no close_callback: picking an item leaves the list open underneath,
    -- so closing a chapter or study returns to it
    return menu
end

--- Opens a study file and shows its chapter list. Returns the chapter menu.
function PkStudies.openStudy(path)
    local ok, study, err = pcall(PkStudy.open, path)
    if not ok then study, err = nil, study end
    if not study then
        logger.warn("Paperknight: cannot open study", path, err)
        UIManager:show(InfoMessage:new{ text = T(_("Cannot open study:\n%1"), tostring(err)) })
        return nil
    end
    local items = {}
    for i, ch in ipairs(study.chapters) do
        items[#items + 1] = {
            text = T("%1. %2", i, ch.title),
            mandatory = ch.gamebook and _("lesson") or nil,
            callback = function() PkStudies.openChapter(study, i) end,
        }
    end
    local menu = fullscreenMenu(study.name, items)
    UIManager:show(menu)
    return menu, study
end

function PkStudies.openChapter(study, index)
    local view = PkStudyView:new{ study = study, chapter_index = index }
    UIManager:show(view)
    return view
end

--- Top-level list: study files + "Open a PGN file…".
function PkStudies.show()
    local dir = PkStudies.dir()
    local items = {}
    for _i, file in ipairs(PkStudies.listFiles(dir)) do
        items[#items + 1] = {
            text = util.fixUtf8((file:gsub("%.[Pp][Gg][Nn]$", "")), "?"),
            callback = function() PkStudies.openStudy(dir .. "/" .. file) end,
        }
    end
    items[#items + 1] = {
        text = _("Open a PGN file…"),
        callback = function()
            UIManager:show(PathChooser:new{
                title = _("Choose a PGN file"),
                path = G_reader_settings:readSetting("home_dir") or dir,
                select_directory = false,
                file_filter = function(name) return name:lower():match("%.pgn$") ~= nil end,
                onConfirm = function(path) PkStudies.openStudy(path) end,
            })
        end,
    }
    if #items == 1 then
        items[1].text = items[1].text .. "  " .. T(_("(no studies in %1)"), dir)
    end
    local menu = fullscreenMenu(_("Studies"), items)
    UIManager:show(menu)
    return menu
end

return PkStudies
