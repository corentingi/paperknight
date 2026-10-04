-- Promotion piece chooser shared by the play and puzzle screens (ADR-0009).
-- Extracted from Kochess's Paperknight:openPromotionDialog.
local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local InputDialog = require("ui/widget/inputdialog")
local MovableContainer = require("ui/widget/container/movablecontainer")
local Screen = require("device").screen
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")

local Chess = require("chess")
local PkButton = require("button") -- accepts absolute icon paths
local PkIcons = require("pkicons")

local PkPromotion = {}

local ORDER = { "q", "r", "b", "n" }
local PIECE = { q = Chess.QUEEN, r = Chess.ROOK, b = Chess.BISHOP, n = Chess.KNIGHT }

--- Shows the chooser. `on_chosen(letter)` receives "q", "r", "b" or "n".
-- @return the dialog widget (already shown)
function PkPromotion.show(pawn_color, on_chosen)
    local dialog = InputDialog:new{
        title = _("Choose Promotion Piece"),
        buttons = {},
    }
    local icon_size = math.floor(math.min(Screen:getWidth(), Screen:getHeight()) / 10)
    icon_size = math.max(60, math.min(96, icon_size))

    local buttons_group = VerticalGroup:new{ align = "center" }
    for _, letter in ipairs(ORDER) do
        table.insert(buttons_group, PkButton:new{
            icon = PkIcons.pieces[PIECE[letter]][pawn_color],
            icon_width = icon_size,
            icon_height = icon_size,
            id = "promote_" .. letter,
            callback = function()
                UIManager:close(dialog)
                on_chosen(letter)
            end,
        })
        table.insert(buttons_group, VerticalSpan:new{ width = Size.padding.large })
    end

    local content = FrameContainer:new{
        radius = Size.radius.window,
        bordersize = Size.border.window,
        background = Blitbuffer.COLOR_WHITE,
        padding = Size.padding.large,
        margin = 0,
        VerticalGroup:new{
            align = "center",
            dialog.title_bar,
            VerticalSpan:new{ width = Size.padding.large },
            TextWidget:new{
                text = _("Select the piece for promotion:"),
                face = Font:getFace("cfont", 22),
                max_width = dialog.width * 0.9,
            },
            VerticalSpan:new{ width = Size.padding.large },
            buttons_group,
        },
    }
    dialog.movable = MovableContainer:new{ content }
    dialog[1] = CenterContainer:new{ dimen = Screen:getSize(), dialog.movable }
    UIManager:show(dialog)
    return dialog
end

return PkPromotion
