-- Puzzle stats screen: one row per theme with a bar of the attempts, clean
-- solves in black and missed ones in grey, then "clean/attempts · performance"
-- (pkpuzzlestats.lua). The first row is all themes. A tap on a row trains that
-- theme; pages turn with ‹ ›, swipes or the page keys. KOReader's Menu only
-- shows text, hence this screen.
local Blitbuffer = require("ffi/blitbuffer")
local ButtonTable = require("ui/widget/buttontable")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geometry = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local RightContainer = require("ui/widget/container/rightcontainer")
local Screen = require("device").screen
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local Widget = require("ui/widget/widget")
local _ = require("gettext")
local T = require("ffi/util").template
local PkRefresh = require("pkrefresh")
local PkSide = require("pkside")
local PkThemes = require("pkthemes")

-- Missed attempts: a mid grey, told apart from the black clean part and from
-- the white page (the bar is framed, so an all-missed bar still shows).
local MISSED_COLOR = Blitbuffer.COLOR_GRAY_B

local Bar = Widget:extend{
    width = 0,
    height = 0,
    clean = 0,
    n = 1,
}

function Bar:getSize()
    return Geometry:new{ w = self.width, h = self.height }
end

function Bar:paintTo(bb, x, y)
    self.dimen = Geometry:new{ x = x, y = y, w = self.width, h = self.height }
    local clean_w = math.floor(self.width * self.clean / self.n + 0.5)
    bb:paintRect(x, y, self.width, self.height, MISSED_COLOR)
    if clean_w > 0 then bb:paintRect(x, y, clean_w, self.height, Blitbuffer.COLOR_BLACK) end
    bb:paintBorder(x, y, self.width, self.height, Size.border.thin, Blitbuffer.COLOR_BLACK)
end

-- A tappable row; `on_tap` runs on a tap anywhere in it.
local Row = InputContainer:extend{
    on_tap = nil,
}

function Row:init()
    self.ges_events = {
        TapRow = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
    }
end

function Row:onTapRow()
    if self.on_tap then self.on_tap() end
    return true
end

local PkStatsView = InputContainer:extend{
    name = "paperknight_stats",
    covers_fullscreen = true,
    stats = nil,   -- PkPuzzleStats.compute result
    rating = nil,  -- the user's rating, for the subtitle
    on_pick = nil, -- function(theme): a row was tapped (theme nil: all themes)
}

-- Subtitle: the rating and what the bar colours mean. Night mode inverts the
-- screen: the clean part then shows white.
function PkStatsView:_legend()
    return T(Screen.night_mode and _("Your rating %1 · white: clean, grey: missed")
        or _("Your rating %1 · black: clean, grey: missed"), self.rating)
end

function PkStatsView:init()
    self.dimen = Geometry:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    if Device:hasKeys() then
        self.key_events = {
            Close = { { Device.input.group.Back } },
            Forward = { { Device.input.group.PgFwd } },
            Backward = { { Device.input.group.PgBack } },
        }
    end
    self.ges_events.PkSwipe = { GestureRange:new{ ges = "swipe", range = function() return self.dimen end } }
    -- one entry per row: { label, theme, clean, n, perf }
    self.entries = {}
    local total = self.stats.total
    if total.n > 0 then
        self.entries[1] = { label = _("All themes"), clean = total.clean, n = total.n, perf = total.perf }
        for _, g in ipairs(self.stats.themes) do
            self.entries[#self.entries + 1] = {
                label = PkThemes.label(g.theme), theme = g.theme, clean = g.clean, n = g.n, perf = g.perf,
            }
        end
    end
    self.title_bar = TitleBar:new{
        fullscreen = true,
        title = _("Puzzle stats"),
        subtitle = self:_legend(),
        with_bottom_line = true,
        close_callback = function() self:onClose() end,
    }
    self.row_h = Screen:scaleBySize(46)
    self.label_face = Font:getFace("cfont", 18)
    self.figures_face = Font:getFace("cfont", 16)
    self.page, self.pages = 1, 1
    -- night mode toggled while the page is open: the legend follows
    PkSide.followNight(self, function(v) v.title_bar:setSubTitle(v:_legend(), true) end)
    self:_build()
end

function PkStatsView:_footer()
    local footer = ButtonTable:new{
        width = self.dimen.w - 2 * Size.padding.default,
        buttons = {{
            { id = "prev", icon = "chevron.left", callback = function() self:turn(-1) end },
            { id = "page", text = T(_("Page %1 of %2"), self.page, self.pages), enabled = false },
            { id = "next", icon = "chevron.right", callback = function() self:turn(1) end },
        }},
        zero_sep = true,
    }
    footer:getButtonById("prev"):enableDisable(self.page > 1)
    footer:getButtonById("next"):enableDisable(self.page < self.pages)
    return footer
end

function PkStatsView:_row(entry)
    local pad = Size.padding.large
    local inner_w = self.dimen.w - 2 * pad
    local label_w = math.floor(inner_w * 0.38)
    local figures_w = math.floor(inner_w * 0.24)
    local gap = Size.padding.default
    local bar_w = inner_w - label_w - figures_w - 2 * gap
    local figures = T("%1/%2", entry.clean, entry.n)
    if entry.perf then figures = figures .. " · " .. entry.perf end
    local h = self.row_h - Size.line.thin
    return Row:new{
        on_tap = function() self:pick(entry) end,
        entry = entry,
        VerticalGroup:new{
            HorizontalGroup:new{
                align = "center",
                HorizontalSpan:new{ width = pad },
                LeftContainer:new{
                    dimen = Geometry:new{ w = label_w, h = h },
                    TextWidget:new{ text = entry.label, face = self.label_face, max_width = label_w },
                },
                HorizontalSpan:new{ width = gap },
                Bar:new{ width = bar_w, height = math.floor(h * 0.4), clean = entry.clean, n = entry.n },
                HorizontalSpan:new{ width = gap },
                RightContainer:new{
                    dimen = Geometry:new{ w = figures_w, h = h },
                    TextWidget:new{ text = figures, face = self.figures_face, max_width = figures_w },
                },
                HorizontalSpan:new{ width = pad },
            },
            LineWidget:new{
                dimen = Geometry:new{ w = self.dimen.w, h = Size.line.thin },
                background = Blitbuffer.COLOR_LIGHT_GRAY,
            },
        },
    }
end

-- (Re)builds the screen for the current page.
function PkStatsView:_build()
    if not self.footer_h then -- measured once (the same height on every page)
        local probe = self:_footer()
        self.footer_h = probe:getSize().h
        probe:free()
    end
    local list_h = self.dimen.h - self.title_bar:getHeight() - self.footer_h
    self.per_page = math.max(1, math.floor(list_h / self.row_h))
    self.pages = math.max(1, math.ceil(#self.entries / self.per_page))
    self.page = math.max(1, math.min(self.page, self.pages))
    local list = VerticalGroup:new{ align = "left" }
    self.rows = {}
    if #self.entries == 0 then
        list[1] = LeftContainer:new{
            dimen = Geometry:new{ w = self.dimen.w, h = self.row_h },
            HorizontalGroup:new{
                HorizontalSpan:new{ width = Size.padding.large },
                TextWidget:new{ text = _("No puzzles played yet."), face = self.label_face },
            },
        }
    end
    local first = (self.page - 1) * self.per_page + 1
    for i = first, math.min(#self.entries, first + self.per_page - 1) do
        local row = self:_row(self.entries[i])
        self.rows[#self.rows + 1] = row
        list[#list + 1] = row
    end
    self.footer = self:_footer()
    self[1] = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        width = self.dimen.w,
        height = self.dimen.h,
        VerticalGroup:new{
            align = "left",
            self.title_bar,
            FrameContainer:new{
                bordersize = 0, padding = 0,
                width = self.dimen.w, height = list_h,
                list,
            },
            self.footer,
        },
    }
end

--- Turns `delta` pages, if there are.
function PkStatsView:turn(delta)
    local page = self.page + delta
    if page < 1 or page > self.pages then return end
    self.page = page
    self:_build()
    PkRefresh.page(self)
end

function PkStatsView:pick(entry)
    self:onClose()
    if self.on_pick then self.on_pick(entry.theme) end
end

function PkStatsView:onPkSwipe(_, ges)
    if ges.direction == "west" then self:turn(1) elseif ges.direction == "east" then self:turn(-1) else return false end
    return true
end

function PkStatsView:onForward() self:turn(1); return true end
function PkStatsView:onBackward() self:turn(-1); return true end

function PkStatsView:onClose()
    PkRefresh.close(self)
    return true
end

function PkStatsView:onShow()
    PkRefresh.page(self)
end

return PkStatsView
