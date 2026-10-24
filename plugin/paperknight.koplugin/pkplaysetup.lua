-- The new game dialog of Play (pkplayview.lua, ADR-0020): the opponent
-- (Stockfish or two players), then for Stockfish your side and its
-- strength, for two players face to face or not, and the clock. Radio
-- buttons; Start gives the settings (pkplay.lua) to `on_start`.
local Blitbuffer = require("ffi/blitbuffer")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geometry = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local RadioButtonTable = require("ui/widget/radiobuttontable")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")
local PkPlay = require("pkplay")
local Screen = Device.screen

local PkPlaySetup = InputContainer:extend{
    settings = nil,    -- the settings shown first (pkplay.lua)
    has_engine = true, -- Stockfish installed
    on_start = nil,    -- function(settings)
}

function PkPlaySetup:init()
    local s = {}
    for k, v in pairs(self.settings or PkPlay.DEFAULTS) do s[k] = v end
    if not self.has_engine then s.opponent = "human" end
    self.choice = s
    self.width = math.floor(math.min(Screen:getWidth(), Screen:getHeight()) * 0.92)
    if Device:hasKeys() then
        self.key_events = { Close = { { Device.input.group.Back } } }
    end
    self:_build()
end

-- `rows` of { text, value }: a radio table setting choice[key].
function PkPlaySetup:_radio(key, rows)
    local radio_rows = {}
    for i, row in ipairs(rows) do
        radio_rows[i] = {}
        for j, opt in ipairs(row) do
            radio_rows[i][j] = { text = opt[1], provider = opt[2], checked = self.choice[key] == opt[2],
                                 enabled = opt.enabled ~= false }
        end
    end
    local table_widget = RadioButtonTable:new{
        width = self.width - 2 * Size.padding.large,
        radio_buttons = radio_rows,
        face = Font:getFace("cfont", 18),
        show_parent = self,
        parent = self,
        button_select_callback = function(entry)
            local changed = self.choice[key] ~= entry.provider
            self.choice[key] = entry.provider
            -- another opponent: other questions
            if key == "opponent" and changed then self:_rebuild() end
        end,
    }
    self.radios = self.radios or {}
    self.radios[key] = table_widget
    return table_widget
end

function PkPlaySetup:_label(text)
    return TextBoxWidget:new{
        text = text,
        face = Font:getFace("cfont", 18),
        bold = true,
        width = self.width - 2 * Size.padding.large,
    }
end

function PkPlaySetup:_build()
    local c = self.choice
    self.radios = {}
    local group = VerticalGroup:new{ align = "center" }
    local function add(w) group[#group + 1] = w end
    local gap = VerticalSpan:new{ width = Size.padding.default }
    self.title_bar = TitleBar:new{
        width = self.width,
        title = _("New game"),
        with_bottom_line = true,
        close_callback = function() self:onClose() end,
        show_parent = self,
    }
    add(self.title_bar)
    add(gap)
    add(self:_label(_("Opponent")))
    add(self:_radio("opponent", {{ { _("Stockfish"), "engine", enabled = self.has_engine },
                                   { _("Two players"), "human" } }}))
    if not self.has_engine then
        add(self:_label(_("Stockfish is not installed: Settings → Stockfish: install…")))
    end
    if c.opponent == "engine" then
        add(self:_label(_("You play")))
        add(self:_radio("side", {{ { _("White"), "w" }, { _("Black"), "b" }, { _("Random"), "random" } }}))
        add(self:_label(_("Stockfish's strength (Elo)")))
        local levels, row = {}, {}
        for _i, level in ipairs(PkPlay.LEVELS) do
            row[#row + 1] = { level == 0 and _("Full") or tostring(level), level }
            if #row == 3 then levels[#levels + 1], row = row, {} end
        end
        if #row > 0 then levels[#levels + 1] = row end
        add(self:_radio("level", levels))
    else
        add(self:_label(_("Seats")))
        add(self:_radio("face", {{ { _("Face to face"), true }, { _("Side by side"), false } }}))
    end
    add(self:_label(_("Clock")))
    add(self:_radio("clock", {
        { { _("No clock"), "off" }, { _("5 min"), "5+0" }, { _("10 min"), "10+0" } },
        { { _("15 min + 10 s"), "15+10" }, { _("30 min"), "30+0" } },
    }))
    self.button_table = ButtonTable:new{
        width = self.width - 2 * Size.padding.default,
        buttons = {{
            { text = _("Cancel"), callback = function() self:onClose() end },
            { text = _("Start"), id = "start", callback = function() self:start() end },
        }},
        zero_sep = true,
        show_parent = self,
    }
    add(self.button_table)
    self.frame = FrameContainer:new{
        radius = Size.radius.window,
        bordersize = Size.border.window,
        background = Blitbuffer.COLOR_WHITE,
        padding = 0,
        group,
    }
    self.dimen = Geometry:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self[1] = CenterContainer:new{ dimen = self.dimen, self.frame }
end

function PkPlaySetup:_rebuild()
    -- (after the tap is handled: the radio button being tapped is replaced)
    UIManager:nextTick(function()
        self:_build()
        UIManager:setDirty("all", "ui")
    end)
end

function PkPlaySetup:start()
    UIManager:close(self, "ui", self.frame.dimen)
    if self.on_start then self.on_start(self.choice) end
end

function PkPlaySetup:onClose()
    UIManager:close(self, "ui", self.frame.dimen)
    return true
end

--- Shows the dialog; returns it.
function PkPlaySetup.show(opts)
    local dialog = PkPlaySetup:new(opts)
    UIManager:show(dialog, "ui")
    return dialog
end

return PkPlaySetup
