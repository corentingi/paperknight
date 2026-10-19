-- Studies browser: PGN files in the studies folder, then their chapters
-- (ADR-0011). Opening a chapter shows pkstudyview.
local DataStorage = require("datastorage")
local ButtonDialog = require("ui/widget/buttondialog")
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
local PkNav = require("pknav")
local PkProgress = require("pkprogress")
local PkRefresh = require("pkrefresh")
local PkStudy = require("pkstudy")
local PkStudyView = require("pkstudyview")

local PkStudies = {}

--- Paperknight folder `name` in KOReader's data dir (created if missing);
-- the environment variable `env_var` overrides it (tests).
function PkStudies.dataDir(name, env_var)
    local dir = os.getenv(env_var)
    if dir then return dir end
    local base = DataStorage:getFullDataDir() .. "/paperknight"
    dir = base .. "/" .. name
    for _, d in ipairs({ base, dir }) do
        if lfs.attributes(d, "mode") ~= "directory" then
            local ok, err = lfs.mkdir(d)
            if not ok then logger.warn("Paperknight: cannot create", d, err) end
        end
    end
    return dir
end

--- Studies folder: <KOReader data dir>/paperknight/studies.
function PkStudies.dir()
    return PkStudies.dataDir("studies", "PAPERKNIGHT_STUDIES_DIR")
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

-- A list screen; `actions(close)` (optional) gives the rows (lists of
-- buttons) of its ☰ menu:
-- actions on the list as a whole (the title tap has the quick settings).
local function fullscreenMenu(title, items, actions)
    local menu = Menu:new{
        title = title,
        item_table = items,
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        name = "paperknight_studies",
        title_bar_left_icon = actions and "appbar.menu" or nil,
    }
    if actions then
        menu.onLeftButtonTap = function()
            local dialog
            local function close() UIManager:close(dialog); menu.menu_dialog = nil end
            local rows = actions(close)
            rows[#rows + 1] = PkNav.moreRow(close, "studies")
            dialog = ButtonDialog:new{ buttons = rows }
            menu.menu_dialog = dialog -- tests
            UIManager:show(dialog)
        end
    end
    PkNav.tapTitle(menu, function() return menu.title_bar end, "studies")
    -- no close_callback: picking an item leaves the list open underneath,
    -- so closing a chapter or study returns to it
    return menu
end

-- larger PGN files are game databases, not studies or repertoires
PkStudies.MAX_BYTES = 2 * 1024 * 1024
local MAX_STUDY_BYTES = PkStudies.MAX_BYTES

local ERRORS = {
    empty = _("This file contains no games."),
    not_pgn = _("This file is not a PGN file."),
}

-- Runs fn(progress) with the progress database (nil if it cannot be opened).
local function withProgress(fn)
    local ok, progress = pcall(PkProgress.open, PkProgress.defaultPath())
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

-- Recent studies: the paths of the last studies opened, the latest first
-- (setting "studies.recent", one path per line).
PkStudies.RECENT_MAX = 10

--- The recent list `value` (setting text, or nil) after opening `path`.
function PkStudies.pushRecent(value, path, max)
    local out = { path }
    for line in (value or ""):gmatch("[^\n]+") do
        if line ~= path and #out < (max or PkStudies.RECENT_MAX) then out[#out + 1] = line end
    end
    return table.concat(out, "\n")
end

PkStudies.recent_version = 0 -- changes with the list (the lists showing it follow)

local function recordRecent(path)
    PkStudies.recent_version = PkStudies.recent_version + 1
    withProgress(function(progress)
        if not progress then return end
        progress:setSetting("studies.recent", PkStudies.pushRecent(progress:getSetting("studies.recent"), path))
    end)
end

--- The recent studies that still exist, the latest first.
function PkStudies.recent()
    local value = withProgress(function(progress) return progress and progress:getSetting("studies.recent") end)
    local out = {}
    for line in (value or ""):gmatch("[^\n]+") do
        if lfs.attributes(line, "mode") == "file" then out[#out + 1] = line end
    end
    return out
end

--- The recent studies list: a tap opens one (its chapters, with Continue).
function PkStudies.showRecent()
    local root = PkStudies.dir()
    local items = {}
    for _i, path in ipairs(PkStudies.recent()) do
        local folder = path:match("^(.*)/[^/]+$")
        items[#items + 1] = {
            text = util.fixUtf8((path:match("([^/]+)$"):gsub("%.[Pp][Gg][Nn]$", "")), "?"),
            mandatory = folder ~= root and util.fixUtf8(folder:match("([^/]+)$") or "", "?") or nil,
            callback = function() PkStudies.openStudy(path) end,
        }
    end
    if #items == 0 then items[1] = { text = _("(no study opened yet)"), callback = function() end } end
    local menu = fullscreenMenu(_("Recent studies"), items)
    UIManager:show(menu)
    return menu
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
    recordRecent(path)
    local file = PkDone.fileOf(study.path)
    local menu = fullscreenMenu(util.fixUtf8(study.name, "?"), PkStudies.chapterItems(study), file and function(close)
        local done = withProgress(function(progress) return progress and PkDone.isDone(progress, file) end)
        return { { { text = done and _("Mark study as not done") or _("Mark study as done ✓"), callback = function()
            close()
            PkStudies.toggleDone(file) -- the list is rebuilt when painted (marks changed)
        end } } }
    end)
    -- the marks and "Continue" change while a chapter is open: rebuild the
    -- list when coming back to it
    local function version() return PkDone.version .. "/" .. PkDone.chapter_version end
    menu._pk_version = version()
    local paintTo = menu.paintTo
    menu.paintTo = function(m, bb, x, y)
        paintTo(m, bb, x, y)
        if m._pk_version ~= version() then
            m._pk_version = version()
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
-- Whether done studies are hidden from the lists (☰, remembered).
local function hideDone()
    return withProgress(function(progress)
        return progress and progress:getSetting("studies.hide_done") == "1"
    end) == true
end

-- `here`: this list's title; `parent`: the parent list's title (a
-- sub-folder: a "../" line first, back to it; the ✕ does the same, less
-- obviously).
local function listItems(dir, files, folders, is_root, here, parent)
    local items = {}
    if parent then
        items[1] = { text = T(_("../  Back to %1"), parent), _pk_up = true }
    elseif is_root and #PkStudies.recent() > 0 then
        items[1] = { text = _("Recent studies…"), callback = function() PkStudies.showRecent() end }
    end
    local done = withProgress(PkDone.doneSet) or {}
    local hide, hidden = hideDone(), 0
    for _i, folder in ipairs(folders) do
        local all = studiesUnder(dir .. "/" .. folder, 3)
        local n_done = 0
        for _j, f in ipairs(all) do if done[f] then n_done = n_done + 1 end end
        items[#items + 1] = {
            text = util.fixUtf8(folder, "?") .. "/",
            mandatory = n_done > 0 and T("%1/%2 %3", n_done, #all, PkDone.MARK) or tostring(#all),
            callback = function()
                PkStudies.show(dir .. "/" .. folder, folder, here)
            end,
        }
    end
    for _i, file in ipairs(files) do
        if hide and done[file] then
            hidden = hidden + 1
            goto continue
        end
        items[#items + 1] = {
            text = util.fixUtf8((file:gsub("%.[Pp][Gg][Nn]$", "")), "?"),
            mandatory = done[file] and PkDone.MARK or nil, -- ✓ on the far right
            _pk_file = file,
            callback = function() PkStudies.openStudy(dir .. "/" .. file) end,
        }
        ::continue::
    end
    if hidden > 0 then
        items[#items + 1] = { text = T(_("(%1 done hidden: ☰ to show them)"), hidden), callback = function() end }
    end
    if not is_root then
        if #items == 1 then items[2] = { text = _("(empty folder)"), callback = function() end } end
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
    if #files == 0 and #folders == 0 then
        items[#items].text = items[#items].text .. "  " .. T(_("(no studies in %1)"), dir)
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
        .. "|" .. PkStudies.recent_version
end

--- Studies list of `dir` (default PkStudies.dir(), the top level; tests
-- pass their own); `title`: a sub-folder's name. Sub-folders open their
-- own list, `parent` being the title of the one they come from. The list
-- follows the folder and the done marks: each repaint (e.g. back from a
-- study) rebuilds the items if the files, folders or marks changed.
-- Long-press on a study toggles its done mark.
function PkStudies.show(dir, title, parent)
    local is_root = title == nil
    dir = dir or PkStudies.dir()
    if is_root then applyRenames(dir) end
    local files, folders = PkStudies.listEntries(dir)
    local here = title and util.fixUtf8(title, "?") or _("Studies")
    local menu
    local function rebuild(m, now_files, now_folders)
        local first = ((m.page or 1) - 1) * (m.perpage or 1) + 1 -- stay on the current page
        m:switchItemTable(nil, listItems(dir, now_files, now_folders, is_root, here, parent), first)
    end
    menu = fullscreenMenu(here, listItems(dir, files, folders, is_root, here, parent), function(close)
            local hide = hideDone()
            return { { { text = hide and _("Show done studies") or _("Hide done studies"), callback = function()
                close()
                withProgress(function(progress)
                    if progress then progress:setSetting("studies.hide_done", (not hide) and "1" or nil) end
                end)
                local now_files, now_folders = PkStudies.listEntries(dir)
                rebuild(menu, now_files, now_folders)
            end } } }
        end)
    menu._pk_files = entriesKey(files, folders)
    if parent then
        -- "../": back to the parent list (underneath), like the ✕
        local onMenuSelect = menu.onMenuSelect
        menu.onMenuSelect = function(m, item, ...)
            if item and item._pk_up then
                PkRefresh.close(m)
                return true
            end
            return onMenuSelect(m, item, ...)
        end
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
    -- what changes the list: the folder (its modification time, cheap to
    -- read) and the done marks; the folder is listed again only then
    -- (nil when the folder changed within the last second: the time has a
    -- one-second resolution, so it is not trusted then)
    local function stamp()
        local mtime = lfs.attributes(dir, "modification")
        if not mtime or mtime >= os.time() - 1 then return nil end
        return mtime .. "|" .. PkDone.version .. "|" .. PkStudies.recent_version
    end
    menu._pk_stamp = stamp()
    local paintTo = menu.paintTo
    menu.paintTo = function(m, bb, x, y)
        paintTo(m, bb, x, y)
        local now_stamp = stamp()
        if now_stamp and now_stamp == m._pk_stamp then return end
        m._pk_stamp = now_stamp
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
