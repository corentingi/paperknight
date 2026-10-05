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

local PkDone = require("pkdone")
local PkProgress = require("pkprogress")
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

local MAX_STUDY_BYTES = 2 * 1024 * 1024 -- larger files are game databases, not studies

local ERRORS = {
    empty = _("This file contains no games."),
    not_pgn = _("This file is not a PGN file."),
}

--- Opens a study file and shows its chapter list. Returns the chapter menu.
function PkStudies.openStudy(path)
    local name = path:match("([^/]+)$") or path
    local size = lfs.attributes(path, "size")
    if size and size > MAX_STUDY_BYTES then
        UIManager:show(InfoMessage:new{ text = T(_("%1 is too large for a study (%2 MB, limit 2 MB)."),
            util.fixUtf8(name, "?"), string.format("%.1f", size / 1048576)) })
        return nil
    end
    local ok, study, err = pcall(PkStudy.open, path)
    if not ok then study, err = nil, study end
    if not study then
        logger.warn("Paperknight: cannot open study", path, err)
        UIManager:show(InfoMessage:new{ text = T(_("Cannot open %1:\n%2"), util.fixUtf8(name, "?"),
            ERRORS[err] or tostring(err)) })
        return nil
    end
    local items = {}
    for i, ch in ipairs(study.chapters) do
        items[#items + 1] = {
            text = T("%1. %2", i, util.fixUtf8(ch.title, "?")),
            mandatory = ch.gamebook and _("lesson") or nil,
            callback = function() PkStudies.openChapter(study, i) end,
        }
    end
    local menu = fullscreenMenu(util.fixUtf8(study.name, "?"), items)
    UIManager:show(menu)
    return menu, study
end

function PkStudies.openChapter(study, index)
    local view = PkStudyView:new{ study = study, chapter_index = index }
    UIManager:show(view)
    return view
end

-- Runs fn(progress) with the progress database (nil if it cannot be opened).
local function withProgress(fn)
    local ok, progress = pcall(PkProgress.open, DataStorage:getSettingsDir() .. "/paperknight/progress.sqlite")
    if not ok then
        logger.warn("Paperknight: cannot open progress database:", progress)
        progress = nil
    end
    local res_ok, res = pcall(fn, progress)
    if progress then progress:close() end
    if not res_ok then
        logger.warn("Paperknight:", res)
        return nil
    end
    return res
end

-- Items of the top-level list: study files (✓ when done) + "Open a PGN file…".
local function listItems(dir, files)
    local items = {}
    local done = withProgress(PkDone.doneSet) or {}
    for _i, file in ipairs(files) do
        items[#items + 1] = {
            text = (done[file] and PkDone.MARK or "") .. util.fixUtf8((file:gsub("%.[Pp][Gg][Nn]$", "")), "?"),
            _pk_file = file,
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
    return items
end

--- Toggles the done mark of a study file. Returns the new state, or nil.
function PkStudies.toggleDone(file)
    return withProgress(function(progress)
        if not progress then return nil end
        local done = not PkDone.isDone(progress, file)
        PkDone.set(progress, file, done)
        return done
    end)
end

--- Top-level list. `dir` defaults to PkStudies.dir() (tests pass their own).
-- The list follows the folder and the done marks: each repaint (e.g. back
-- from a study) rebuilds the items if the .pgn files or the marks changed.
-- Long-press on a study toggles its done mark.
function PkStudies.show(dir)
    dir = dir or PkStudies.dir()
    local files = PkStudies.listFiles(dir)
    local menu = fullscreenMenu(_("Studies"), listItems(dir, files))
    menu._pk_files = table.concat(files, "\n") .. "|" .. PkDone.version
    menu.onMenuHold = function(m, item)
        if item and item._pk_file and PkStudies.toggleDone(item._pk_file) ~= nil then
            -- rebuild now (one refresh), on the same page
            local now = PkStudies.listFiles(dir)
            m._pk_files = table.concat(now, "\n") .. "|" .. PkDone.version
            local first = ((m.page or 1) - 1) * (m.perpage or 1) + 1
            m:switchItemTable(nil, listItems(dir, now), first)
        end
        return true
    end
    local paintTo = menu.paintTo
    menu.paintTo = function(m, bb, x, y)
        paintTo(m, bb, x, y)
        local now = PkStudies.listFiles(dir)
        local key = table.concat(now, "\n") .. "|" .. PkDone.version
        if key ~= m._pk_files then
            m._pk_files = key
            -- not while painting: rebuild on the next tick
            UIManager:nextTick(function()
                -- stay on the current page
                local first = ((m.page or 1) - 1) * (m.perpage or 1) + 1
                m:switchItemTable(nil, listItems(dir, now), first)
            end)
        end
    end
    UIManager:show(menu)
    return menu
end

return PkStudies
