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

local function byName(a, b) return a:lower() < b:lower() end

--- Sorted .pgn files and sub-folders (hidden ones skipped) of `dir`.
function PkStudies.listEntries(dir)
    local files, folders = {}, {}
    if lfs.attributes(dir, "mode") ~= "directory" then return files, folders end
    local ok, iter, dir_obj = pcall(lfs.dir, dir) -- throws on unreadable folders
    if not ok then
        logger.warn("Paperknight: cannot list", dir, iter)
        return files, folders
    end
    for entry in iter, dir_obj do
        local mode = entry:sub(1, 1) ~= "." and lfs.attributes(dir .. "/" .. entry, "mode")
        if mode == "file" and entry:lower():match("%.pgn$") then
            files[#files + 1] = entry
        elseif mode == "directory" then
            folders[#folders + 1] = entry
        end
    end
    table.sort(files, byName)
    table.sort(folders, byName)
    return files, folders
end

--- Sorted list of .pgn files in `dir`.
function PkStudies.listFiles(dir)
    return (PkStudies.listEntries(dir))
end

-- Study files under `dir` (sub-folders included, a few levels deep).
local function studiesUnder(dir, depth, out)
    out = out or {}
    local files, folders = PkStudies.listEntries(dir)
    for _i, f in ipairs(files) do out[#out + 1] = f end
    if depth > 0 then
        for _i, d in ipairs(folders) do studiesUnder(dir .. "/" .. d, depth - 1, out) end
    end
    return out
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
    local menu = fullscreenMenu(util.fixUtf8(study.name, "?"), PkStudies.chapterItems(study))
    -- the marks and "Continue" change while a chapter is open: rebuild the
    -- list when coming back to it
    menu._pk_version = PkDone.version
    local paintTo = menu.paintTo
    menu.paintTo = function(m, bb, x, y)
        paintTo(m, bb, x, y)
        if m._pk_version ~= PkDone.version then
            m._pk_version = PkDone.version
            UIManager:nextTick(function()
                local first = ((m.page or 1) - 1) * (m.perpage or 1) + 1
                m:switchItemTable(nil, PkStudies.chapterItems(study), first)
            end)
        end
    end
    UIManager:show(menu)
    return menu, study
end

--- Chapter list items: "▶ Continue" (last chapter opened), then each
-- chapter with "lesson" / "✓" on the right.
function PkStudies.chapterItems(study)
    local file = PkDone.fileOf(study.path)
    local done, last = {}, nil
    withProgress(function(progress)
        done = PkDone.chapterDoneSet(progress, file)
        last = PkDone.lastChapter(progress, file)
    end)
    local items = {}
    if last and study.chapters[last] and #study.chapters > 1 then
        items[1] = {
            text = T(_("▶ Continue: %1. %2"), last, util.fixUtf8(study.chapters[last].title, "?")),
            callback = function() PkStudies.openChapter(study, last) end,
        }
    end
    for i, ch in ipairs(study.chapters) do
        items[#items + 1] = {
            text = T("%1. %2", i, util.fixUtf8(ch.title, "?")),
            mandatory = PkDone.chapterInfo(ch.gamebook, done[i]),
            callback = function() PkStudies.openChapter(study, i) end,
        }
    end
    return items
end

function PkStudies.openChapter(study, index)
    local view = PkStudyView:new{ study = study, chapter_index = index }
    UIManager:show(view)
    return view
end

-- Items of a studies list: sub-folders (with "done/total" on the right),
-- study files (✓ when done), and at the top level "Open a PGN file…".
local function listItems(dir, files, folders, is_root)
    local items = {}
    local done = withProgress(PkDone.doneSet) or {}
    for _i, folder in ipairs(folders) do
        local all = studiesUnder(dir .. "/" .. folder, 3)
        local n_done = 0
        for _j, f in ipairs(all) do if done[f] then n_done = n_done + 1 end end
        items[#items + 1] = {
            text = util.fixUtf8(folder, "?") .. "/",
            mandatory = n_done > 0 and T("%1/%2 %3", n_done, #all, PkDone.MARK) or tostring(#all),
            callback = function() PkStudies.show(dir .. "/" .. folder, folder) end,
        }
    end
    for _i, file in ipairs(files) do
        items[#items + 1] = {
            text = util.fixUtf8((file:gsub("%.[Pp][Gg][Nn]$", "")), "?"),
            mandatory = done[file] and PkDone.MARK or nil, -- ✓ on the far right
            _pk_file = file,
            callback = function() PkStudies.openStudy(dir .. "/" .. file) end,
        }
    end
    if not is_root then
        if #items == 0 then items[1] = { text = _("(empty folder)"), callback = function() end } end
        return items
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
    if #items == 1 and #folders == 0 then
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

-- Renames shipped with a collection (old -> new file names, see
-- PkDone.applyRenames): applied when the top-level list opens.
local RENAMES_FILE = "RENAMES.txt"

local function applyRenames(dir)
    local f = io.open(dir .. "/" .. RENAMES_FILE, "rb")
    if not f then return end
    local text = f:read("*a")
    f:close()
    local n = withProgress(function(progress)
        return progress and PkDone.applyRenames(progress, text) or 0
    end)
    if n and n > 0 then logger.info("Paperknight: kept the marks of", n, "renamed studies") end
end

local function entriesKey(files, folders)
    return table.concat(files, "\n") .. "|" .. table.concat(folders, "\n") .. "|" .. PkDone.version
end

--- Studies list of `dir` (default PkStudies.dir(), the top level; tests
-- pass their own); `title`: a sub-folder's name. Sub-folders open their
-- own list. The list follows the folder and the done marks: each repaint
-- (e.g. back from a study) rebuilds the items if the files, folders or
-- marks changed. Long-press on a study toggles its done mark.
function PkStudies.show(dir, title)
    local is_root = title == nil
    dir = dir or PkStudies.dir()
    if is_root then applyRenames(dir) end
    local files, folders = PkStudies.listEntries(dir)
    local menu = fullscreenMenu(title and util.fixUtf8(title, "?") or _("Studies"),
        listItems(dir, files, folders, is_root))
    menu._pk_files = entriesKey(files, folders)
    local function rebuild(m, now_files, now_folders)
        local first = ((m.page or 1) - 1) * (m.perpage or 1) + 1 -- stay on the current page
        m:switchItemTable(nil, listItems(dir, now_files, now_folders, is_root), first)
    end
    menu.onMenuHold = function(m, item)
        if item and item._pk_file and PkStudies.toggleDone(item._pk_file) ~= nil then
            -- rebuild now (one refresh), on the same page
            local now_files, now_folders = PkStudies.listEntries(dir)
            m._pk_files = entriesKey(now_files, now_folders)
            rebuild(m, now_files, now_folders)
        end
        return true
    end
    local paintTo = menu.paintTo
    menu.paintTo = function(m, bb, x, y)
        paintTo(m, bb, x, y)
        local now_files, now_folders = PkStudies.listEntries(dir)
        local key = entriesKey(now_files, now_folders)
        if key ~= m._pk_files then
            m._pk_files = key
            -- not while painting: rebuild on the next tick
            UIManager:nextTick(function() rebuild(m, now_files, now_folders) end)
        end
    end
    UIManager:show(menu)
    return menu
end

return PkStudies
