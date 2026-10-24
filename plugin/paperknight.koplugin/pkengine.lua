-- Stockfish for the Kindle (docs/stockfish.md): <plugin>/bin/stockfish,
-- installed by install.sh. Used by the analysis board and Play.
local lfs = require("libs/libkoreader-lfs")

local PkEngine = {
    PATH = require("pkicons").plugin_dir .. "/bin/stockfish",
}

--- Whether the engine binary is there (`path`: tests give a fake engine).
function PkEngine.installed(path)
    return lfs.attributes(path or PkEngine.PATH, "mode") == "file"
end

return PkEngine
