-- Study viewer (ADR-0011, docs/studies.md): board + comment panel + navigation.
-- Tree logic lives in pkstudy.lua; this file only displays and dispatches.
local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geometry = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local Menu = require("ui/widget/menu")
local Screen = Device.screen
local ScrollTextWidget = require("ui/widget/scrolltextwidget")
local Size = require("ui/size")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template

local Chess = require("chess")
local ChessBoard = require("board")
local PkPromotion = require("pkpromotion")
local PkStudy = require("pkstudy")

local PkStudyView = InputContainer:extend{
    name = "paperknight_study",
    covers_fullscreen = true,
    study = nil,         -- PkStudy
    chapter_index = 1,
}

function PkStudyView:init()
    self.dimen = Geometry:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    if Device:hasKeys() then
        self.key_events = {
            Close = { { Device.input.group.Back } },
            Forward = { { Device.input.group.PgFwd } },
            Backward = { { Device.input.group.PgBack } },
        }
    end
    self.game = Chess:new()
    self.title_bar = TitleBar:new{
        fullscreen = true,
        title = "",
        subtitle = "",
        title_shrink_font_to_fit = true,
        with_bottom_line = true,
        left_icon = "appbar.menu",
        left_icon_tap_callback = function() self:showChapterMenu() end,
        close_callback = function() self:onClose() end,
    }
    self.buttons = ButtonTable:new{
        width = self.dimen.w - 2 * Size.padding.default,
        buttons = {{
            { id = "start", icon = "chevron.first", callback = function() self:toStart() end },
            { id = "back", icon = "chevron.left", callback = function() self:back() end },
            { id = "lines", text = _("Lines"), callback = function() self:showLines() end },
            { id = "forward", icon = "chevron.right", callback = function() self:forward() end },
            { id = "end", icon = "chevron.last", callback = function() self:toEnd() end },
        }},
        zero_sep = true,
    }
    local free_h = self.dimen.h - self.title_bar:getHeight() - self.buttons:getSize().h
    self.board_size = math.min(self.dimen.w, math.floor(free_h * 0.68))
    self.text_h = free_h - self.board_size - 3 * Size.padding.default
    self:loadChapter(self.chapter_index)
end

function PkStudyView:_build()
    local orientation_black = self.chapter.orientation == "black"
    if not self.board or self.board.flipped ~= orientation_black then
        if self.board then self.board:free() end
        self.board = ChessBoard:new{
            game = self.game,
            width = self.board_size,
            height = self.board_size,
            flipped = orientation_black,
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

function PkStudyView:_textWidget(text)
    return ScrollTextWidget:new{
        text = text,
        face = Font:getFace("cfont", 18),
        width = self.dimen.w - 2 * Size.padding.large,
        height = self.text_h,
        dialog = self,
    }
end

-- ScrollTextWidget has no setText: replace the panel widget.
function PkStudyView:_setText(text)
    self.panel_text = text
    local old = self.text
    self.text = self:_textWidget(text)
    for i, w in ipairs(self.vgroup) do
        if w == old then self.vgroup[i] = self.text end
    end
    old:free()
    self.vgroup:resetLayout()
    UIManager:setDirty(self, "ui")
end

--- Opens chapter `index` at its start position.
function PkStudyView:loadChapter(index)
    self.chapter_index = index
    self.chapter = self.study.chapters[index]
    local cursor, err = self.study:cursor(index, self.game)
    if not cursor then
        logger.warn("Paperknight: cannot open chapter", index, err)
        self.cursor = nil
        self.game.reset()
        self:_build()
        self.board:updateBoard()
        self.board:setHighlights({})
        self.board:setShapes(nil)
        self.board.locked = true
        for _, id in ipairs({ "start", "back", "lines", "forward", "end" }) do
            self.buttons:getButtonById(id):enableDisable(false)
        end
        self.title_bar:setTitle(self.chapter.title)
        self:_setText(T(_("Cannot open this chapter: %1"), tostring(err)))
        UIManager:setDirty(self, "full")
        return
    end
    for _, id in ipairs({ "start", "back", "forward", "end" }) do
        self.buttons:getButtonById(id):enableDisable(true)
    end
    self.cursor = cursor
    self:_build()
    self.title_bar:setTitle(self.chapter.title)
    self:refresh()
    UIManager:setDirty(self, "full")
end

-- Text panel: current move (or intro), comment, then what comes next.
function PkStudyView:_panelText()
    local node = self.cursor.node
    local parts = {}
    if node == self.cursor.root then
        parts[#parts + 1] = self.chapter.gamebook and _("Interactive lesson") or _("Start of the chapter")
    else
        parts[#parts + 1] = PkStudy.moveLabel(node)
    end
    if node.comment then parts[#parts + 1] = node.comment end
    local children = node.children
    if #children == 0 then
        parts[#parts + 1] = (node == self.cursor.root) and _("(no moves)") or _("— End of line —")
    elseif #children > 1 then
        local alts = {}
        for i, child in ipairs(children) do
            local label = self.cursor:resolve(child) and PkStudy.moveLabel(child) or child.san
            alts[#alts + 1] = (i == 1) and (label .. " " .. _("(main)")) or label
        end
        parts[#parts + 1] = T(_("Next: %1"), table.concat(alts, " · "))
    end
    return table.concat(parts, "\n\n")
end

--- Redraws board, highlights, shapes, panel and subtitle for the current node.
-- `prefix`: optional message shown above the panel text.
function PkStudyView:refresh(prefix)
    local node = self.cursor.node
    self.board:updateBoard()
    if node.move then
        self.board:setHighlights({ node.move.from, node.move.to })
    else
        self.board:setHighlights({})
    end
    self.board:setShapes(node.shapes)
    self.board.locked = false
    self:_setText(prefix and (prefix .. "\n\n" .. self:_panelText()) or self:_panelText())
    local lines_button = self.buttons:getButtonById("lines")
    lines_button:enableDisable(#node.children > 1)
    self.title_bar:setSubTitle(T(_("%1 · Chapter %2/%3"), self.study.name, self.chapter_index, #self.study.chapters))
    UIManager:setDirty(self, "ui")
end

function PkStudyView:_show(node, err)
    if not node and err and err ~= "end of line" then
        self:_setText(T(_("Cannot play the next move: %1"), err))
        UIManager:setDirty(self, "ui")
        return
    end
    if node then self:refresh() end
end

function PkStudyView:forward(i) if self.cursor then self:_show(self.cursor:forward(i)) end end
function PkStudyView:back() if self.cursor and self.cursor:back() then self:refresh() end end
function PkStudyView:toStart() if self.cursor then self.cursor:toStart(); self:refresh() end end
function PkStudyView:toEnd() if self.cursor then self.cursor:toEnd(); self:refresh() end end
function PkStudyView:onForward() self:forward(); return true end
function PkStudyView:onBackward() self:back(); return true end

--- Alternatives at the next move: main move first, then variations.
function PkStudyView:showLines()
    if not self.cursor then return end
    local children = self.cursor.node.children
    if #children < 2 then return end
    local rows = {}
    for i, child in ipairs(children) do
        local label = self.cursor:resolve(child) and PkStudy.moveLabel(child) or child.san
        if i == 1 then label = label .. "  " .. _("(main line)") end
        rows[#rows + 1] = {{
            text = label,
            callback = function()
                UIManager:close(self.lines_dialog)
                self.lines_dialog = nil
                self:forward(i)
            end,
        }}
    end
    self.lines_dialog = ButtonDialog:new{ title = _("Choose a line"), buttons = rows }
    UIManager:show(self.lines_dialog)
end

--- A move played on the board follows the study if it exists at this point.
function PkStudyView:onBoardMove(move)
    local promotion = move.promotion
    self.game.undo() -- the cursor decides what the position is
    if self.game.redo_stack then table.remove(self.game.redo_stack) end
    if not self.cursor then return end
    local child, i = self.cursor:childForMove(move.from, move.to, promotion)
    if child then
        self:forward(i)
    else
        self:refresh(_("This move is not in the study."))
    end
end

function PkStudyView:showChapterMenu()
    local items = {}
    for i, ch in ipairs(self.study.chapters) do
        local text = ch.title
        if i == self.chapter_index then text = "✓ " .. text end
        items[#items + 1] = {
            text = text,
            mandatory = ch.gamebook and _("lesson") or nil,
            callback = function() self:loadChapter(i) end,
        }
    end
    self.chapter_menu = Menu:new{
        title = self.study.name,
        item_table = items,
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
    }
    self.chapter_menu.close_callback = function()
        UIManager:close(self.chapter_menu)
        self.chapter_menu = nil
    end
    -- open on the page of the current chapter
    self.chapter_menu:switchItemTable(nil, items, self.chapter_index)
    UIManager:show(self.chapter_menu)
end

function PkStudyView:onClose()
    UIManager:close(self)
    return true
end

function PkStudyView:onCloseWidget()
    if self.board then self.board:free() end
    if self.text then self.text:free() end
end

return PkStudyView
