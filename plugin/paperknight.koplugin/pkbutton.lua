local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local IconWidget = require("ui/widget/iconwidget")
local LeftContainer = require("ui/widget/container/leftcontainer")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local _ = require("gettext")
local Screen = require("device").screen

-- Paperknight: subclass instead of patching KOReader's global Button:init
local KOButton = require("ui/widget/button")
local Button = KOButton:extend{
    no_feedback = false, -- true: a tap runs the callback without the highlight
}

function Button:init()
    if self.menu_style then
        self.align = "left"
        self.padding_h = Size.padding.large
        self.text_font_face = "smallinfofont"
        self.text_font_size = 22
        self.text_font_bold = false
    end

    -- Prefer an optional text_func over text
    if self.text_func and type(self.text_func) == "function" then
        self.text = self.text_func()
    end

    -- Point tap_input to hold_input if requested
    if self.call_hold_input_on_tap then
        self.tap_input = self.hold_input
    end

    if not self.padding_h then
        self.padding_h = self.padding
    end
    if not self.padding_v then
        self.padding_v = self.padding
    end

    local outer_pad_width = 2*self.padding_h + 2*self.margin + 2*self.bordersize -- unscaled_size_check: ignore

    -- If this button could be made smaller while still not needing truncation
    -- or a smaller font size, we'll set this: it may allow an upper widget to
    -- resize/relayout itself to look more compact/nicer (as this size would
    -- depends on translations)
    self._min_needed_width = nil

    -- Our button's text may end up using a smaller font size, and/or be multiline.
    -- We will give the button the height it would have if no such tweaks were
    -- made. LeftContainer and CenterContainer will vertically center the
    -- TextWidget or TextBoxWidget in that height (hopefully no ink will overflow)
    local reference_height = self.height
    if self.text then
        local text = self.checked_func == nil and self.text or self:getDisplayText()
        local fgcolor = self.enabled and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_DARK_GRAY
        local face = Font:getFace(self.text_font_face, self.text_font_size)
        local max_width = self.max_width or self.width
        if max_width then
            max_width = max_width - outer_pad_width
        end
        self.label_widget = TextWidget:new{
            text = text,
            lang = self.lang,
            max_width = max_width,
            fgcolor = fgcolor,
            bold = self.text_font_bold,
            face = face,
        }
        reference_height = reference_height or self.label_widget:getSize().h
        if not self.label_widget:isTruncated() then
            local checkmark_width = 0
            if self.checked_func and not self.checked_func() then
                local tmp = TextWidget:new{
                    text = self.checkmark,
                    face = face,
                }
                checkmark_width = tmp:getSize().w
                tmp:free()
            end
            self._min_needed_width = self.label_widget:getSize().w + checkmark_width + outer_pad_width
        end
        self.did_truncation_tweaks = false
        if self.avoid_text_truncation and self.label_widget:isTruncated() then
            self.did_truncation_tweaks = true
            local font_size_2_lines = TextBoxWidget:getFontSizeToFitHeight(reference_height, 2, 0)
            while self.label_widget:isTruncated() do
                local new_size = self.label_widget.face.orig_size - 1
                if new_size <= font_size_2_lines then
                    -- Switch to a 2-lines TextBoxWidget
                    self.label_widget:free(true)
                    self.label_widget = TextBoxWidget:new{
                        text = text,
                        lang = self.lang,
                        line_height = 0,
                        alignment = self.align,
                        width = max_width,
                        height = reference_height,
                        height_adjust = true,
                        height_overflow_show_ellipsis = true,
                        fgcolor = fgcolor,
                        bold = self.text_font_bold,
                        face = Font:getFace(self.text_font_face, new_size),
                    }
                    if not self.label_widget.has_split_inside_word then
                        break
                    end
                    -- No good wrap opportunity (split inside a word): ignore this TextBoxWidget
                    -- and go on with a TextWidget with the smaller font size
                end
                if new_size < 8 then -- don't go too small
                    break
                end
                self.label_widget:free(true)
                self.label_widget = TextWidget:new{
                    text = text,
                    lang = self.lang,
                    max_width = max_width,
                    fgcolor = fgcolor,
                    bold = self.text_font_bold,
                    face = Font:getFace(self.text_font_face, new_size),
                }
            end
        end
    else
        self.label_widget = IconWidget:new{
            icon = self.icon,
            -- Paperknight: an absolute path is loaded as a file (see pkicons.lua)
            file = self.icon and self.icon:sub(1, 1) == "/" and self.icon or nil,
            alpha = self.alpha,
            rotation_angle = self.icon_rotation_angle,
            dim = not self.enabled,
            width = self.icon_width,
            height = self.icon_height,
        }
        self._min_needed_width = self.icon_width + outer_pad_width
    end
    local widget_size = self.label_widget:getSize()
    local label_container_height = reference_height or widget_size.h
    local inner_width
    if self.width then
        inner_width = self.width - outer_pad_width
    else
        inner_width = widget_size.w
    end
    -- set FrameContainer content
    if self.align == "left" then
        self.label_container = LeftContainer:new{
            dimen = Geom:new{
                w = inner_width,
                h = label_container_height,
            },
            self.label_widget,
        }
    else
        self.label_container = CenterContainer:new{
            dimen = Geom:new{
                w = inner_width,
                h = label_container_height,
            },
            self.label_widget,
        }
    end
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
