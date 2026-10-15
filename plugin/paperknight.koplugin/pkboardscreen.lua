-- What the study view and the openings drill share: a board above a
-- scrollable text panel and a button bar, the panel's text (links shown
-- short, tappable for a QR code), their e-ink refreshes, the opponent's
-- reply timer, and taking back a move the board played (the view decides
-- what the position is). Mixed into each view's class (PkBoardScreen.mixin);
-- a view provides title_bar, buttons, game, board_size, text_h and dimen,
-- and its own onBoardMove.
local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geometry = require("ui/geometry")
local ScrollTextWidget = require("ui/widget/scrolltextwidget")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local util = require("util")
local ChessBoard = require("pkboard")
local PkLinks = require("pklinks")
local PkPromotion = require("pkpromotion")
local PkRefresh = require("pkrefresh")
local PkText = require("pktext")

local PkBoardScreen = {}

--- (Re)builds the screen: the board only when its orientation changes, an
-- empty panel, the layout.
function PkBoardScreen:_buildScreen(flipped)
    if not self.board or self.board.flipped ~= flipped then
        if self.board then self.board:free() end
        self.board = ChessBoard:new{
            game = self.game,
            width = self.board_size,
            height = self.board_size,
            flipped = flipped,
            show_parent = self,
            moveCallback = function(move) self:onBoardMove(move) end,
            onPromotionNeeded = function(from, to, color)
                PkPromotion.show(color, function(letter)
                    local move = self.game.move({ from = from, to = to, promotion = letter })
                    if move then self.board:handleGameMove(move) end
                end)
            end,
        }
    end
    if self.text then self.text:free() end
    self.text = self:_textWidget("")
    self.vgroup = VerticalGroup:new{
        align = "center",
        self.title_bar,
        CenterContainer:new{
            dimen = Geometry:new{ w = self.dimen.w, h = self.board_size + Size.padding.default },
            self.board,
        },
        self.text,
        self.buttons,
    }
    self[1] = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        width = self.dimen.w,
        height = self.dimen.h,
        self.vgroup,
    }
end

function PkBoardScreen:_textWidget(text)
    return ScrollTextWidget:new{
        text = text,
        face = Font:getFace("cfont", 18),
        width = self.dimen.w - 2 * Size.padding.large,
        height = self.text_h,
        dialog = self,
    }
end

--- Replaces the panel's text (the refresh is scheduled by _redraw).
function PkBoardScreen:_setText(text)
    self.raw_text = text -- before linkify: rewritten when night mode is toggled
    text = util.fixUtf8(text, "?") -- e.g. Latin-1 PGNs from older tools
    text, self.links = PkText.linkify(text) -- web addresses shown short
    self.panel_text = text
    local old = self.text
    self.text = self:_textWidget(text)
    PkLinks.attach(self.text, self.links) -- tap a link: QR code
    for i, w in ipairs(self.vgroup) do
        if w == old then self.vgroup[i] = self.text end
    end
    old:free()
    self.vgroup:resetLayout()
end

--- Schedules the screen update after a step: the area below the board (the
-- board refreshes its own squares), or the whole view for a jump (`page`).
-- See pkrefresh.lua.
function PkBoardScreen:_redraw(page)
    if page then return PkRefresh.page(self) end
    PkRefresh.below(self, self.board, self.buttons)
end

--- Drops a scheduled opponent reply.
function PkBoardScreen:_cancelReply()
    if self._reply_task then
        UIManager:unschedule(self._reply_task)
        self._reply_task = nil
    end
end

--- Takes back the move the board just played in the game: the view decides
-- what the position is (its cursor), not the board.
function PkBoardScreen:_takeBackMove()
    self.game.undo()
    if self.game.redo_stack then table.remove(self.game.redo_stack) end
end

--- Adds these methods to a view class.
function PkBoardScreen.mixin(class)
    for name, fn in pairs(PkBoardScreen) do
        if name ~= "mixin" then class[name] = fn end
    end
    return class
end

return PkBoardScreen
