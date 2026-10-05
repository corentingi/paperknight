-- Openings: repertoire PGNs in <data>/paperknight/repertoires (ADR-0012).
-- The list shows each repertoire with its due / new counts; opening one
-- starts a drill session (pkdrill.lua, pkdrillview.lua).
local DataStorage = require("datastorage")
local InfoMessage = require("ui/widget/infomessage")
local Menu = require("ui/widget/menu")
local Screen = require("device").screen
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local T = require("ffi/util").template

local Chess = require("chess")
local PkDrill = require("pkdrill")
local PkDrillView = require("pkdrillview")
local PkProgress = require("pkprogress")
local PkRepertoire = require("pkrepertoire")
local PkSrs = require("pksrs")
local PkStudies = require("pkstudies")
local PkStudy = require("pkstudy")

local PkOpenings = {}

local MAX_BYTES = 2 * 1024 * 1024

--- Repertoire folder (created if missing); PAPERKNIGHT_REPERTOIRES_DIR
-- overrides it (tests).
function PkOpenings.dir()
    local dir = os.getenv("PAPERKNIGHT_REPERTOIRES_DIR")
    if dir then return dir end
    local base = DataStorage:getFullDataDir() .. "/paperknight"
    dir = base .. "/repertoires"
    for _, d in ipairs({ base, dir }) do
        if lfs.attributes(d, "mode") ~= "directory" then
            local ok, err = lfs.mkdir(d)
            if not ok then logger.warn("Paperknight: cannot create", d, err) end
        end
    end
    return dir
end

local function openProgress()
    local ok, progress = pcall(PkProgress.open, DataStorage:getSettingsDir() .. "/paperknight/progress.sqlite")
    if ok then return progress end
    logger.warn("Paperknight: cannot open progress database:", progress)
    return nil, progress
end

-- Parsing a repertoire and resolving every move is slow on an e-reader, and
-- a parsed tree is big. Kept per path while the file and its flips are
-- unchanged: a small summary (enough for the list's counts) for every file,
-- the full repertoire only for the last one opened.
local summaries = {} -- path -> { stamp, summary, err }
local full = nil     -- { path, stamp, rep }

local function fileStamp(path)
    local attr = lfs.attributes(path) or {}
    return tostring(attr.modification) .. ":" .. tostring(attr.size), attr.size
end

-- Flip settings of a repertoire file: key "rep_flip:<file>#<chapter>".
local function flipKey(file, chapter)
    return "rep_flip:" .. file .. "#" .. chapter
end

local function flips(progress, file)
    local set = {}
    if progress then
        for _, key in ipairs(progress:settingKeys(flipKey(file, ""))) do
            set[tonumber(key:match("#(%d+)$")) or 0] = true
        end
    end
    return set
end

local function flipStamp(set)
    local list = {}
    for i in pairs(set) do list[#list + 1] = i end
    table.sort(list)
    return table.concat(list, ",")
end

--- Loads a repertoire file. Returns rep (or its summary { name, order,
-- cards } when `summary_only`), or nil and an error message.
function PkOpenings.load(path, progress, summary_only)
    local file = path:match("([^/]+)$") or path
    local fstamp, size = fileStamp(path)
    local set = flips(progress, file)
    local stamp = fstamp .. "|" .. flipStamp(set)
    if full and full.path == path and full.stamp == stamp then
        return summary_only and summaries[path].summary or full.rep
    end
    local hit = summaries[path]
    if summary_only and hit and hit.stamp == stamp then return hit.summary, hit.err end
    local rep, err = PkOpenings._load(path, size, set)
    local summary
    if rep then
        local cards = {}
        for key, c in pairs(rep.cards) do cards[key] = { uci = c.uci } end
        summary = { name = rep.name, order = rep.order, cards = cards }
        full = { path = path, stamp = stamp, rep = rep }
    end
    summaries[path] = { stamp = stamp, summary = summary, err = err }
    if summary_only then return summary, err end
    return rep, err
end

--- True if loading `path` would parse it (used to show a loading message).
function PkOpenings.needsParse(path, progress)
    local file = path:match("([^/]+)$") or path
    local stamp = fileStamp(path) .. "|" .. flipStamp(flips(progress, file))
    local hit = summaries[path]
    return not (hit and hit.stamp == stamp)
end

function PkOpenings._load(path, size, flipped)
    if size and size > MAX_BYTES then
        return nil, T(_("too large for a repertoire (%1 MB, limit 2 MB)"), string.format("%.1f", size / 1048576))
    end
    local ok, study, err = pcall(PkStudy.open, path)
    if not ok then study, err = nil, study end
    if not study then return nil, tostring(err) end
    local function orientation(i)
        if not flipped or not flipped[i] then return nil end
        return study.chapters[i].orientation == "black" and "white" or "black"
    end
    local rep_ok, rep = pcall(PkRepertoire.fromStudy, study, Chess:new(), orientation)
    if not rep_ok then return nil, tostring(rep) end
    if #rep.lines == 0 then return nil, _("no moves to train for the side of each chapter") end
    return rep
end

--- Switches the side played in chapter `chapter` of a repertoire file.
function PkOpenings.toggleFlip(path, chapter)
    local progress = openProgress()
    if not progress then return false end
    local key = flipKey(path:match("([^/]+)$") or path, chapter)
    local ok = pcall(function()
        progress:setSetting(key, progress:getSetting(key) ~= "1" and "1" or nil)
    end)
    progress:close()
    return ok
end

-- A drill over `rep`, with its stored cards.
local function newDrill(rep, progress)
    local today = PkSrs.today()
    return PkDrill.new{
        rep = rep,
        game = Chess:new(),
        cards = progress and progress:loadCards(rep.name) or {},
        introduced_today = progress and progress:introducedOn(rep.name, today) or 0,
        save = function(key, move, card)
            if not progress then return end
            local ok, err = pcall(progress.saveCard, progress, rep.name, key, move, card)
            if not ok then logger.warn("Paperknight: cannot save a card:", err) end
        end,
    }
end

--- Opens a repertoire file and starts a drill. Returns the view.
function PkOpenings.openRepertoire(path)
    if PkOpenings.view then return nil end -- e.g. a double tap on slow e-ink
    local name = path:match("([^/]+)$") or path
    local progress, db_err = openProgress()
    local rep, err = PkOpenings.load(path, progress)
    if not rep then
        if progress then progress:close() end
        UIManager:show(InfoMessage:new{ text = T(_("Cannot open %1:\n%2"), util.fixUtf8(name, "?"), err) })
        return nil
    end
    local ok, view = pcall(function()
        return PkDrillView:new{
            drill = newDrill(rep, progress),
            title = (rep.study.name or name),
            on_flip = function(chapter)
                -- after the view closed (and its database handle with it)
                UIManager:nextTick(function()
                    if PkOpenings.toggleFlip(path, chapter) then PkOpenings.openRepertoire(path) end
                end)
            end,
            on_close = function()
                if progress then progress:close() end
                PkOpenings.view = nil
                if PkOpenings.list then PkOpenings.refreshList() end
            end,
        }
    end)
    if not ok then
        logger.warn("Paperknight: cannot start the drill:", view)
        if progress then progress:close() end
        UIManager:show(InfoMessage:new{ text = T(_("Cannot open %1:\n%2"), util.fixUtf8(name, "?"), tostring(view)) })
        return nil
    end
    if rep.conflicts > 0 then
        logger.info("Paperknight:", name, "has", rep.conflicts, "lines cut by conflicting moves")
    end
    PkOpenings.view = view
    UIManager:show(view)
    if not progress then
        UIManager:show(InfoMessage:new{ text = _("Your progress cannot be saved:") .. "\n" .. tostring(db_err) })
    end
    return view
end

local function listItems(dir)
    local items = {}
    local progress = openProgress()
    local ok, err = pcall(function()
        local files = PkStudies.listFiles(dir)
        local loading
        for _i, file in ipairs(files) do
            if PkOpenings.needsParse(dir .. "/" .. file, progress) then
                -- parsing takes seconds for big files on an e-reader: say so
                loading = InfoMessage:new{ text = _("Loading repertoires…") }
                UIManager:show(loading)
                UIManager:forceRePaint()
                break
            end
        end
        for _i, file in ipairs(files) do
            local path = dir .. "/" .. file
            local summary, load_err = PkOpenings.load(path, progress, true)
            local info
            local c_ok, c = false, load_err
            if summary then
                c_ok, c = pcall(function() return newDrill(summary, progress):counts() end)
            end
            if c_ok then
                info = T(_("%1 due · %2 new"), c.due, c.new_today)
            else
                logger.warn("Paperknight: cannot read repertoire", path, c)
                info = _("error")
            end
            items[#items + 1] = {
                text = util.fixUtf8((file:gsub("%.[Pp][Gg][Nn]$", "")), "?"),
                mandatory = info,
                callback = function() PkOpenings.openRepertoire(path) end,
            }
        end
        if loading then UIManager:close(loading) end
    end)
    if progress then progress:close() end
    if not ok then error(err, 0) end
    if #items == 0 then
        items[1] = { text = T(_("No repertoires in %1"), dir), callback = function() end }
    end
    return items
end

--- Rebuilds the open list (counts change after a session).
function PkOpenings.refreshList()
    local menu = PkOpenings.list
    if not menu then return end
    local first = ((menu.page or 1) - 1) * (menu.perpage or 1) + 1
    menu:switchItemTable(nil, listItems(menu._pk_dir), first)
end

--- Repertoire list. `dir` defaults to PkOpenings.dir().
function PkOpenings.show(dir)
    dir = dir or PkOpenings.dir()
    local ok, items = pcall(listItems, dir)
    if not ok then
        logger.warn("Paperknight: cannot list repertoires:", items)
        items = { { text = T(_("Cannot list %1"), dir), callback = function() end } }
    end
    local menu = Menu:new{
        title = _("Openings"),
        item_table = items,
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
    }
    menu._pk_dir = dir
    -- no close_callback (Menu calls it after every pick): the list stays
    -- open under a drill, and forgets itself when closed
    local onCloseWidget = menu.onCloseWidget
    menu.onCloseWidget = function(m, ...)
        if PkOpenings.list == m then PkOpenings.list = nil end
        if onCloseWidget then return onCloseWidget(m, ...) end
    end
    PkOpenings.list = menu
    UIManager:show(menu)
    return menu
end

return PkOpenings
