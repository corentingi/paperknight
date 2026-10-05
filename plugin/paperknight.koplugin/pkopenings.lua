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

-- Parsed repertoires by path, reused while the file is unchanged (parsing
-- and resolving every move is slow on an e-reader).
local cache = {}

--- Loads a repertoire file. Returns rep, or nil and an error message.
function PkOpenings.load(path)
    local attr = lfs.attributes(path) or {}
    local stamp = tostring(attr.modification) .. ":" .. tostring(attr.size)
    local hit = cache[path]
    if hit and hit.stamp == stamp then return hit.rep, hit.err end
    local rep, err = PkOpenings._load(path, attr.size)
    cache[path] = { stamp = stamp, rep = rep, err = err }
    return rep, err
end

function PkOpenings._load(path, size)
    if size and size > MAX_BYTES then
        return nil, T(_("too large for a repertoire (%1 MB, limit 2 MB)"), string.format("%.1f", size / 1048576))
    end
    local ok, study, err = pcall(PkStudy.open, path)
    if not ok then study, err = nil, study end
    if not study then return nil, tostring(err) end
    local rep_ok, rep = pcall(PkRepertoire.fromStudy, study, Chess:new())
    if not rep_ok then return nil, tostring(rep) end
    if #rep.lines == 0 then return nil, _("no moves to train for the side of each chapter") end
    return rep
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
    local rep, err = PkOpenings.load(path)
    if not rep then
        UIManager:show(InfoMessage:new{ text = T(_("Cannot open %1:\n%2"), util.fixUtf8(name, "?"), err) })
        return nil
    end
    local progress, db_err = openProgress()
    local ok, view = pcall(function()
        return PkDrillView:new{
            drill = newDrill(rep, progress),
            title = (rep.study.name or name),
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
    for _i, file in ipairs(PkStudies.listFiles(dir)) do
        local path = dir .. "/" .. file
        local rep, err = PkOpenings.load(path)
        local info
        local ok, c = false, nil
        if rep then
            ok, c = pcall(function() return newDrill(rep, progress):counts() end)
            if not ok then err = c end
        end
        if ok then
            info = T(_("%1 due · %2 new"), c.due, c.new_today)
        else
            logger.warn("Paperknight: cannot read repertoire", path, err)
            info = _("error")
        end
        items[#items + 1] = {
            text = util.fixUtf8((file:gsub("%.[Pp][Gg][Nn]$", "")), "?"),
            mandatory = info,
            callback = function() PkOpenings.openRepertoire(path) end,
        }
    end
    if progress then progress:close() end
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
    local menu = Menu:new{
        title = _("Openings"),
        item_table = listItems(dir),
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
