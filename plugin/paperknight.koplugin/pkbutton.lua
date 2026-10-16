local CenterContainer = require("ui/widget/container/centercontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local IconWidget = require("ui/widget/iconwidget")
local Screen = require("device").screen

-- Paperknight: subclass instead of patching KOReader's global Button:init
local KOButton = require("ui/widget/button")
local Button = KOButton:extend{
    no_feedback = false, -- true: a tap runs the callback without the highlight
}

-- Builds the icon widget (an absolute path is loaded as a file, pkicons.lua).
function Button:_iconWidget(icon)
    return IconWidget:new{
        icon = icon,
        file = icon and icon:sub(1, 1) == "/" and icon or nil,
        alpha = self.alpha,
        rotation_angle = self.icon_rotation_angle,
        dim = not self.enabled,
        width = self.icon_width,
        height = self.icon_height,
    }
end

-- KOReader's Button:init for icons only (text buttons use KOReader's Button,
-- unchanged): icons given as absolute paths, and `day_colors`.
function Button:init()
    assert(self.icon and not self.text, "PkButton is for icon buttons; use KOReader's Button for text")
    if not self.padding_h then
        self.padding_h = self.padding
    end
    if not self.padding_v then
        self.padding_v = self.padding
    end
    local outer_pad_width = 2*self.padding_h + 2*self.margin + 2*self.bordersize -- unscaled_size_check: ignore
    self.label_widget = self:_iconWidget(self.icon)
    self._min_needed_width = self.icon_width + outer_pad_width
    local widget_size = self.label_widget:getSize()
    local label_container_height = self.height or widget_size.h
    local inner_width
    if self.width then
        inner_width = self.width - outer_pad_width
    else
        inner_width = widget_size.w
    end
    self.label_container = CenterContainer:new{
        dimen = Geom:new{
            w = inner_width,
            h = label_container_height,
        },
        self.label_widget,
    }
    self.frame = FrameContainer:new{
        margin = self.margin,
        show_parent = self.show_parent,
        bordersize = self.bordersize,
        background = self.background,
        radius = self.radius,
        padding_top = self.padding_v,
        padding_bottom = self.padding_v,
        padding_left = self.padding_h,
        padding_right = self.padding_h,
        self.label_container
    }
    if self.preselect then
        self.frame.invert = true
    end
    -- Paperknight: day_colors keeps the original look in night mode, like
    -- KOReader does for images: night mode inverts the whole screen, so paint
    -- inverted. Hooked on the frame because Button:refresh repaints it directly.
    if self.day_colors then
        local paint = self.frame.paintTo
        self.frame.paintTo = function(frame, bb, x, y)
            paint(frame, bb, x, y)
            if Screen.night_mode then
                local size = frame:getSize()
                bb:invertRect(x, y, size.w, size.h)
            end
        end
    end
    self.dimen = self.frame:getSize()
    self[1] = self.frame
    self.ges_events = {
        TapSelectButton = {
            GestureRange:new{
                ges = "tap",
                range = self.dimen,
            },
        },
        HoldSelectButton = {
            GestureRange:new{
                ges = "hold",
                range = self.dimen,
            },
        },
        -- Safe-guard for when used inside a MovableContainer
        HoldReleaseSelectButton = {
            GestureRange:new{
                ges = "hold_release",
                range = self.dimen,
            },
        }
    }
end

--- Replaces the icon of an icon button of the same size: only the icon
-- widget changes (setIcon rebuilds the whole button: frame, containers,
-- gestures; and the frame loses its position until the next paint).
function Button:swapIcon(icon)
    if icon == self.icon then return end
    if not self.label_container then return self:setIcon(icon, self.width) end
    self.icon = icon
    self.label_widget:free()
    self.label_widget = self:_iconWidget(icon)
    self.label_container[1] = self.label_widget
end

-- `no_feedback` buttons (board squares) skip KOReader's tap feedback: an
-- inverted highlight refreshed in black and white ("fast", DU), then the
-- unhighlight, both flashing on e-ink, plus a forced repaint and a pause
-- before the callback. The board shows its own selection.
function Button:onTapSelectButton()
    if self.no_feedback and self.callback and (self.enabled or self.allow_tap_when_disabled) then
        self.callback()
        return true
    end
    return KOButton.onTapSelectButton(self)
end

--- Gives a button of a KOReader ButtonTable (which only takes icon names)
-- an icon file at an absolute path (e.g. a piece, pkicons.lua). Not to be
-- followed by setIcon/enableDisable, which would look the path up as a name.
function Button.setFileIcon(button, path)
    button.icon = path
    if button.label_widget then button.label_widget:free() end
    button.label_widget = Button._iconWidget(button, path)
    button.label_container[1] = button.label_widget
end

--- Drops the tap highlight of buttons `ids` of `button_table` (KOReader's
-- ButtonTable has no such option): for buttons pressed in a row (‹ ›), whose
-- effect on the board is the feedback.
function Button.noFeedback(button_table, ids)
    for _, id in ipairs(ids) do
        local button = button_table:getButtonById(id)
        button.no_feedback = true
        button.onTapSelectButton = Button.onTapSelectButton
    end
end

return Button
