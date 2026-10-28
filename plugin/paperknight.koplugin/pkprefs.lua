-- The user's preferences (the Settings screen): on/off switches, saved in
-- progress.sqlite ("pref.<key>": "1" or "0") and kept in memory once read.
local PkPrefs = {
    DEFAULTS = {
        coordinates = true, -- a–h / 1–8 around the board (and the turn marker in its corner)
        legal_moves = false, -- dots on the squares the selected piece can reach
    },
}

local cache = {}

function PkPrefs.get(key)
    if cache[key] == nil then
        local v = require("pkprogress").readSetting("pref." .. key)
        if v == nil then
            cache[key] = PkPrefs.DEFAULTS[key]
        else
            cache[key] = v == "1"
        end
    end
    return cache[key]
end

function PkPrefs.set(key, value)
    cache[key] = value and true or false
    require("pkprogress").writeSetting("pref." .. key, value and "1" or "0")
end

function PkPrefs.toggle(key)
    PkPrefs.set(key, not PkPrefs.get(key))
end

--- Forgets the values read (tests).
function PkPrefs.reset() cache = {} end

return PkPrefs
