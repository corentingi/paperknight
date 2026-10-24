-- E-ink refreshes for the board screens (study, drill, puzzles); see
-- docs/eink-refresh.md for how the Kindle and KOReader refresh the screen.
--  * A step (a move, a selection, the status line) is a "[partial]" refresh:
--    on the PW2 the same non-flashing waveform as KOReader's page turns
--    ("partial" is REAGL there, GL16_INV in night mode), but KOReader does
--    not count it towards its periodic flash, which would otherwise flash
--    the board region every few moves (a counted regional "partial" becomes
--    "flashui" every N, N being the user's full refresh rate).
--  * A page (a new puzzle, chapter or line) is a counted, whole-screen
--    "partial", like a book page: every N pages it becomes a full flash,
--    which clears the ghosting the steps leave.
-- Regions must stay tight: REAGL updates are sent as full updates, which
-- redraw every pixel of the region, and on the grey squares that redraw is
-- visible. The board refreshes the rectangle around the squares that changed
-- (Board.square_refresh, one refresh per update); the text below it is a
-- separate refresh (PkRefresh.below), never joined to the board's.
local Geometry = require("ui/geometry")
local UIManager = require("ui/uimanager")

local PkRefresh = {}

PkRefresh.STEP = "[partial]"

---------------------------------------------------------------------------
-- The board (ADR-0018, docs/eink-refresh.md §7) is
-- painted with the four DU4 grey levels only (0x00, 0x55, 0xAA, 0xFF) and
-- its squares are refreshed with DU4 in partial update mode: no flash, no
-- redraw of unchanged squares. KOReader has no refresh mode for DU4, so the
-- framebuffer is asked directly, from a setDirty function (after painting).

PkRefresh.DU4 = 7 -- WAVEFORM_MODE_DU4 (KOReader ffi/mxcfb_kindle_h.lua)

-- A refresh UIManager discards (1 px: "bogus region" in mxc_update), so that
-- it does not add its own whole-screen refresh when none is queued; the
-- weakest mode, so a merge with another refresh changes nothing.
local NO_REFRESH = Geometry:new{ x = 0, y = 0, w = 1, h = 1 }

-- Nearest of the four DU4 levels, for each 8-bit grey.
local LEVELS
local function levels()
    if LEVELS then return LEVELS end
    local ffi = require("ffi")
    LEVELS = ffi.new("uint8_t[256]")
    for v = 0, 255 do LEVELS[v] = math.floor((v * 3 + 127) / 255) * 0x55 end
    return LEVELS
end

--- Rounds the pixels of `rect` (screen coordinates) in an 8-bit blitbuffer
-- to the four DU4 levels (the pieces' anti-aliased edges). Other buffer
-- types are left alone (the desktop emulator's).
function PkRefresh.quantize4(bb, rect)
    local Blitbuffer = require("ffi/blitbuffer")
    if bb:getType() ~= Blitbuffer.TYPE_BB8 then return false end
    local ffi = require("ffi")
    local x, y, w, h = bb:getBoundedRect(rect.x, rect.y, rect.w, rect.h)
    x, y, w, h = bb:getPhysicalRect(x, y, w, h)
    local lut = levels()
    local data = ffi.cast("uint8_t*", bb.data)
    local stride = tonumber(bb.stride)
    for row = y, y + h - 1 do
        local p = data + row * stride + x
        for i = 0, w - 1 do p[i] = lut[p[i]] end
    end
    return true
end

--- Whether DU4 can be sent: an mxcfb Kindle (the PW2's driver).
function PkRefresh.du4Available()
    local Device = require("device")
    local screen = Device.screen
    return Device:isKindle() and screen.mech_refresh ~= nil
end

--- For a setDirty function, after painting: refreshes `region` of the board
-- with DU4 (quantized first) and returns what UIManager should do (nothing).
-- Without DU4 (emulator, other devices), returns `mode`, `region`.
function PkRefresh.boardRegion(mode, region)
    if not region or not PkRefresh.du4Available() then return mode, region end
    local screen = PkRefresh.screen or require("device").screen -- (a stub in tests)
    PkRefresh.quantize4(screen.full_bb or screen.bb, region)
    screen:mech_refresh(false, PkRefresh.DU4, region.x, region.y, region.w, region.h)
    return "fast", NO_REFRESH
end

--- Refreshes the part of `view` from widget `first` to widget `last`
-- (e.g. the board to the buttons) after a step: down to the bottom of the
-- view when `last` was just rebuilt (no position yet), the whole view when
-- `first` has no position either.
function PkRefresh.step(view, first, last)
    UIManager:setDirty(view, PkRefresh.STEP, PkRefresh.region(view, first, last))
end

--- Enables or disables `button` of `view`, and refreshes it when that
-- changes: for a button outside the regions a step refreshes (the analysis
-- board's bar under its full-height move list). Its place is taken before
-- enableDisable rebuilds it (no dimen until the next paint).
function PkRefresh.enable(view, button, enabled)
    enabled = enabled and true or false
    if (button.enabled and true or false) == enabled then return end
    local d = button[1] and button[1].dimen
    d = d and d.x and d:copy()
    button:enableDisable(enabled)
    if d then UIManager:setDirty(view, PkRefresh.STEP, d) end
end

--- Sets the subtitle of `view.title_bar` when it changed, refreshed as a
-- step (TitleBar's own refresh is "ui", GC16_FAST: it flickers the changed
-- text).
function PkRefresh.setSubTitle(view, text)
    local title_bar = view.title_bar
    -- a title bar made without a subtitle has no widget for one
    if not title_bar.subtitle_widget or text == title_bar.subtitle_widget.text then return end
    title_bar:setSubTitle(text, true)
    -- the bar is at the top of the view: its region is right even before
    -- the first paint (then the whole view is being painted anyway)
    UIManager:setDirty(view, PkRefresh.STEP, title_bar.dimen)
end

--- Refreshes the part of `view` below widget `above` (e.g. the board, which
-- refreshes its own squares) down to widget `last` (the bottom of the view
-- when it has no position yet): the text and buttons after a step.
function PkRefresh.below(view, above, last)
    local a, b = above and above.dimen, last and last.dimen
    local region
    if a and a.y then
        local top = a.y + a.h
        local bottom = (b and b.y) and (b.y + b.h) or (view.dimen.y or 0) + view.dimen.h
        region = Geometry:new{ x = 0, y = top, w = view.dimen.w, h = bottom - top }
    end
    UIManager:setDirty(view, PkRefresh.STEP, region)
end

--- The region PkRefresh.step refreshes (nil: the whole view).
function PkRefresh.region(view, first, last)
    local a, b = first and first.dimen, last and last.dimen
    if not (a and a.y) then return nil end
    local bottom = (b and b.y) and (b.y + b.h) or (view.dimen.y or 0) + view.dimen.h
    return Geometry:new{ x = 0, y = a.y, w = view.dimen.w, h = bottom - a.y }
end

--- Closes a full-screen view and refreshes the screen below it, like a
-- page. UIManager:close without a refresh mode repaints what is below but
-- refreshes nothing (KOReader's menus refresh themselves on close; our
-- board screens don't): the old screen would stay on the e-ink, or be
-- replaced only where a dialog was.
function PkRefresh.close(view)
    UIManager:close(view, "partial")
end

--- Refreshes the whole view (a new chapter, line or puzzle).
function PkRefresh.page(view)
    UIManager:setDirty(view, "partial")
end

return PkRefresh
