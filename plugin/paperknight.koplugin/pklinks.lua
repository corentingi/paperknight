-- Links in comment panels: tap a short link ("youtube.com ↗") to show a QR
-- code of the full address (scan it with a phone), or pick it from the
-- screen's ≡ menu. Uses KOReader's QRMessage, with the address under the code.
local Font = require("ui/font")
local QRMessage = require("ui/widget/qrmessage")
local Screen = require("device").screen
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")
local T = require("ffi/util").template

local PkText = require("pktext")

local PkLinks = {}

-- QRMessage with the address written under the code.
local LinkQR = QRMessage:extend{}

function LinkQR:init()
    QRMessage.init(self)
    local frame = self[1][1]
    local qr = frame[1]
    frame[1] = VerticalGroup:new{
        align = "center",
        qr,
        VerticalSpan:new{ width = Size.padding.large },
        TextBoxWidget:new{
            text = self.text,
            face = Font:getFace("cfont", 14),
            width = self.width - 2 * Size.padding.fullscreen,
            alignment = "center",
            -- long tracking URLs: at most 3 lines, cut with an ellipsis
            height = math.floor(3 * Font:getFace("cfont", 14).size * 1.5),
            height_adjust = true,
            height_overflow_show_ellipsis = true,
        },
    }
end

--- Shows the QR code of `link` ({ url, label }). Returns the widget.
function PkLinks.showQR(link)
    local size = math.floor(math.min(Screen:getWidth(), Screen:getHeight()) * 0.7)
    local url = link.url
    if not url:match("^%a[%w+.-]*://") then url = "https://" .. url end -- "www.…": phones need a scheme
    local widget = LinkQR:new{ text = url, width = size, height = size }
    UIManager:show(widget)
    return widget
end

--- The link under a tap on TextBoxWidget `tw`, or nil. getCharPosAtXY gives
-- a cursor position (a tap right of a line returns the next line's first
-- character, a tap below the last visible line a hidden line): only accept
-- a character on the tapped visible line, under the finger.
function PkLinks.linkAtTap(tw, links, ges)
    if not (tw and tw.dimen and ges and ges.pos and tw.line_height_px) then return nil end
    local x, y = ges.pos.x - tw.dimen.x, ges.pos.y - tw.dimen.y
    local row = math.floor(y / tw.line_height_px)
    if y < 0 or row >= tw:getVisLineCount() then return nil end
    local pos = tw:getCharPosAtXY(x, y)
    local link = PkText.linkAt(links, pos)
    if not link then return nil end
    local cx, cy = tw:_getXYForCharPos(pos)
    if math.floor(cy / tw.line_height_px) ~= row then return nil end -- another line
    if x < cx - tw.line_height_px then return nil end -- left margin, far from the text
    return link
end

--- Makes taps on link labels of `scroll` (a ScrollTextWidget showing a text
-- linkified by PkText) open the QR code; other taps scroll as usual.
function PkLinks.attach(scroll, links)
    if not links or #links == 0 then return end
    local default = scroll.onTapScrollText
    scroll.onTapScrollText = function(w, arg, ges)
        local link = PkLinks.linkAtTap(w.text_widget, links, ges)
        if link then
            PkLinks.showQR(link)
            return true
        end
        return default(w, arg, ges)
    end
end

--- Button row for a ButtonDialog: "Links (n)…" opening a list of the links,
-- or nil when there are none. `close` closes the calling dialog.
function PkLinks.menuRow(links, close)
    if not links or #links == 0 then return nil end
    return {{
        text = T(_("Links (%1)…"), #links),
        callback = function()
            close()
            local ButtonDialog = require("ui/widget/buttondialog")
            local dialog
            local rows = {}
            for i, link in ipairs(links) do
                -- same site twice: add the start of the path to tell them apart
                local text = link.label
                for j, other in ipairs(links) do
                    if j ~= i and other.label == link.label then
                        local path = link.url:match("^%a[%w+.-]*://[^/]+(/.*)$") or link.url:match("^[^/]+(/.*)$") or ""
                        text = link.label .. (path ~= "" and (" " .. path:sub(1, 24)) or (" #" .. i))
                        break
                    end
                end
                rows[#rows + 1] = {{ text = text, callback = function()
                    UIManager:close(dialog)
                    PkLinks.showQR(link)
                end }}
            end
            dialog = ButtonDialog:new{ title = _("Show the QR code of a link"), buttons = rows }
            -- the open dialog (tests), forgotten when it closes
            PkLinks.dialog = dialog
            local onCloseWidget = dialog.onCloseWidget
            dialog.onCloseWidget = function(d, ...)
                if PkLinks.dialog == d then PkLinks.dialog = nil end
                if onCloseWidget then return onCloseWidget(d, ...) end
            end
            UIManager:show(dialog)
        end,
    }}
end

return PkLinks
