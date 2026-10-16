-- Piece icon paths, resolved inside the plugin folder.
-- KOReader only scans the user icons directory if it exists at startup, so we
-- reference our SVGs by absolute path instead of copying them there.
local Chess = require("pkchesslib/src/chess")

-- On devices KOReader loads plugins from the relative path "plugins/", so the
-- source path is relative: anchor it to the working directory, because
-- pkbutton.lua only treats absolute paths as files.
local function pluginDir()
    local source = debug.getinfo(1, "S").source:gsub("^@", "")
    local dir = source:match("(.*)/pkicons%.lua$") or "."
    if dir:sub(1, 1) ~= "/" then
        local ok, lfs = pcall(require, "libs/libkoreader-lfs")
        local cwd = ok and lfs.currentdir() or os.getenv("PWD") or "."
        dir = cwd .. "/" .. dir:gsub("^%./", "")
    end
    return dir
end

local PLUGIN_DIR = pluginDir()
local DIR = PLUGIN_DIR .. "/icons/chess/"

local function path(name)
    return DIR .. name .. ".svg"
end

local PkIcons = {
    plugin_dir = PLUGIN_DIR, -- absolute (data files: pkopeningnames.lua)
    empty = DIR .. "empty.svg",
    pieces = {},
}
for _, piece in ipairs({ Chess.PAWN, Chess.KNIGHT, Chess.BISHOP, Chess.ROOK, Chess.QUEEN, Chess.KING }) do
    local letter = piece:upper()
    PkIcons.pieces[piece] = {
        [Chess.WHITE] = path("w" .. letter),
        [Chess.BLACK] = path("b" .. letter),
    }
end

return PkIcons
