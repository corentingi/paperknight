-- Side names with a disc marker: "○ White", "● Black". Night mode inverts
-- the whole screen, so there the glyphs are swapped (a stored ● shows as a
-- white disc), like the board's piece sets. Text already on screen when night
-- mode is toggled is fixed by PkSide.followNight.
local Device = require("device")
local _ = require("gettext")

local PkSide = {}

local WHITE_DISC, BLACK_DISC = "○", "●" -- U+25CB, U+25CF (as stored, day mode)

--- Marker of `color` ("w" or "b") as it must be stored to show right now.
function PkSide.mark(color)
    local white = color == "w"
    if Device.screen.night_mode then white = not white end
    return white and WHITE_DISC or BLACK_DISC
end

--- "○ White" / "● Black".
function PkSide.name(color)
    return PkSide.mark(color) .. " " .. (color == "w" and _("White") or _("Black"))
end

local SWAP = { [WHITE_DISC] = BLACK_DISC, [BLACK_DISC] = WHITE_DISC }

--- `text` with its markers swapped (after night mode was toggled).
function PkSide.swap(text)
    return (text:gsub("\226\151[\139\143]", SWAP))
end

--- Calls `refresh(view)` before `view` is painted after night mode was
-- toggled, so that it rewrites its texts with PkSide.swap.
function PkSide.followNight(view, refresh)
    view._pk_night = Device.screen.night_mode
    local paintTo = view.paintTo
    view.paintTo = function(v, bb, x, y)
        if v._pk_night ~= Device.screen.night_mode then
            v._pk_night = Device.screen.night_mode
            refresh(v)
        end
        return paintTo(v, bb, x, y)
    end
end

return PkSide
