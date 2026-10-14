-- Navigation (pknav.lua, ADR-0015): home screen, quick settings from the
-- title bar (a tap on the title, or ☰), switching modes, night mode,
-- frontlight. Taps land where a user would tap.
local Device = require("device")
local UIManager = require("ui/uimanager")

return function(h)
    local PkNav = require("pknav")
    local Screen = Device.screen
    local function top() return UIManager._window_stack[#UIManager._window_stack].widget end
    local function names()
        local out = {}
        for _, w in ipairs(PkNav.screens()) do out[#out + 1] = w.name end
        return table.concat(out, ",")
    end
    local function menuItem(menu, text)
        for _, w in ipairs(menu.item_group) do
            if w.text and w.text:find(text, 1, true) then return w end
        end
    end
    local function dialogButton(dialog, text)
        for _, row in ipairs(dialog.buttontable.buttons_layout) do
            for _, btn in ipairs(row) do
                if btn.text and btn.text:find(text, 1, true) then return btn end
            end
        end
    end
    local function tapTitle(widget)
        local d = widget.title_bar.dimen
        h.tap(d.x + math.floor(d.w / 2), d.y + math.floor(d.h / 3))
        h.wait(0.5)
    end

    -- 1. Home: the modes with a status, and the screen settings.
    PkNav.home()
    h.wait(1)
    local home = top()
    h.check(home.name == "paperknight_home", "home shown: " .. names())
    local puzzles = menuItem(home, "Puzzles")
    h.check(puzzles and menuItem(home, "Studies") and menuItem(home, "Openings"), "modes listed")
    h.check(home.item_table[1].mandatory and home.item_table[1].mandatory:find("Rating", 1, true),
        "puzzle status: " .. tostring(home.item_table[1].mandatory))
    h.check(menuItem(home, "Night mode: off"), "night mode item")
    h.shot("nav-home")
    -- repaints don't reopen the progress database (the status is cached
    -- until the puzzle screen closes)
    local PkProgress = require("pkprogress")
    local open, opens = PkProgress.open, 0
    PkProgress.open = function(...) opens = opens + 1; return open(...) end
    for _ = 1, 3 do
        require("ui/uimanager"):setDirty(home, "ui")
        h.wait(0.3)
    end
    h.check(opens == 0, "home repaints: no database open (" .. opens .. ")")
    PkNav.statusChanged()
    require("ui/uimanager"):setDirty(home, "ui")
    h.wait(0.3)
    PkProgress.open = open
    h.check(opens == 1, "status recomputed once after a change (" .. opens .. ")")

    -- 2. A mode opens above the home screen.
    h.tapWidget(puzzles)
    h.wait(1)
    local view = top()
    h.check(view.name == "paperknight_puzzles" and names() == "paperknight_puzzles,paperknight_home",
        "puzzles above home: " .. names())

    -- 3. A tap on the title opens the quick settings; switch to Studies.
    tapTitle(view)
    local quick = top()
    h.check(quick == PkNav.quick_dialog, "quick settings opened by a title tap")
    h.check(not dialogButton(quick, "Puzzles"), "the current mode is not offered")
    h.shot("nav-quick")
    h.tapWidget(dialogButton(quick, "Studies"))
    h.wait(1)
    h.check(names() == "paperknight_studies,paperknight_home", "switched to studies: " .. names())

    -- 4. Night mode from the ☰ menu of a list, and back.
    local studies = top()
    h.tapWidget(studies.title_bar.left_button)
    h.wait(0.5)
    h.check(top() == PkNav.quick_dialog, "☰ opens the quick settings")
    h.tapWidget(dialogButton(top(), "Night mode: off"))
    h.wait(1)
    h.check(Screen.night_mode, "night mode on")
    h.shot("nav-night")
    tapTitle(studies)
    h.tapWidget(dialogButton(top(), "Night mode: on"))
    h.wait(1)
    h.check(not Screen.night_mode, "night mode off")

    -- 5. The puzzle ☰ menu: theme first, then the quick settings.
    tapTitle(studies)
    h.tapWidget(dialogButton(top(), "Puzzles"))
    h.wait(1)
    view = top()
    h.tapWidget(view.title_bar.left_button)
    h.wait(0.5)
    h.check(view.menu_dialog and dialogButton(view.menu_dialog, "Theme") and dialogButton(view.menu_dialog, "Openings"),
        "puzzle menu: theme and modes")
    h.tapWidget(dialogButton(view.menu_dialog, "Home"))
    h.wait(1)
    h.check(names() == "paperknight_home", "back home: " .. names())

    -- 6. Frontlight: KOReader's own dialog (the desktop build has no
    -- frontlight: check the wiring with a stub).
    local has, show, shown = PkNav.hasFrontlight, PkNav.showFrontlight, 0
    PkNav.hasFrontlight = function() return true end
    PkNav.showFrontlight = function() shown = shown + 1 end
    UIManager:setDirty(home, "ui")
    h.wait(1) -- home rebuilds its items (Frontlight… appears)
    h.tapWidget(menuItem(home, "Frontlight"))
    h.wait(0.5)
    tapTitle(home)
    h.check(not dialogButton(top(), "Home"), "no Home button on the home screen")
    h.tapWidget(dialogButton(top(), "Frontlight"))
    h.wait(0.5)
    PkNav.hasFrontlight, PkNav.showFrontlight = has, show
    h.check(shown == 2, "frontlight from the home screen and the quick settings: " .. shown)

    -- 7. Closing home leaves Paperknight.
    home:onClose()
    h.wait(0.5)
    h.check(names() == "", "nothing left: " .. names())
end
