-- The plugin in French (pkgettext.lua, l10n/fr.po): KOReader's language
-- switched to French, the home screen, a puzzle and the settings speak it;
-- back in English after.
local UIManager = require("ui/uimanager")

return function(h)
    local gettext = require("gettext")
    local PkNav = require("pknav")
    local pk = h.ui.paperknight
    local function top() return UIManager._window_stack[#UIManager._window_stack].widget end
    local function menuItem(menu, text)
        for _, w in ipairs(menu.item_group) do
            if w.text and w.text:find(text, 1, true) then return w end
        end
    end
    local lang = gettext.current_lang
    gettext.changeLang("fr")
    local ok, err = pcall(function()
        h.check(gettext.current_lang == "fr", "KOReader in French: " .. tostring(gettext.current_lang))
        PkNav.home()
        h.settle()
        local home = top()
        h.check(menuItem(home, "Problèmes") and menuItem(home, "Études") and menuItem(home, "Ouvertures")
            and menuItem(home, "Parties de maîtres"), "the modes in French")
        h.check(not menuItem(home, "Puzzles"), "no English left on the home screen")
        h.check((home.item_table[1].mandatory or ""):find("Classement", 1, true),
            "the puzzles' status: " .. tostring(home.item_table[1].mandatory))
        h.shot("french-home")
        local view = pk:startPuzzles()
        h.settle()
        h.check(view and view.status.text:find("Trait aux", 1, true) and view.status.text:find("Trouvez le meilleur coup.", 1, true),
            "a puzzle, its side to move as chess books say it: " .. tostring(view and view.status.text))
        h.check(view.buttons:getButtonById("hint").text == "Indice", "its buttons")
        -- the theme names (made when pkthemes loads: KOReader's language is
        -- set before the plugin loads, here it changed after)
        package.loaded.pkthemes = nil
        local PkThemes = require("pkthemes")
        h.check(PkThemes.label("fork") == "Fourchette" and PkThemes.label("backRankMate") == "Mat du couloir",
            "the puzzle themes: " .. PkThemes.label("fork"))
        package.loaded.pkthemes = nil
        h.shot("french-puzzle")
        view:onClose()
        h.settle()
        PkNav.showSettings()
        h.settle()
        h.check(menuItem(top(), "Rechercher des mises à jour…"), "the settings")
        PkNav.home()
        h.settle()
        top():onClose() -- (KOReader restarts after a change of language: the screens are built again)
        h.settle()
    end)
    gettext.changeLang(lang)
    if not ok then error(err, 0) end
    PkNav.home()
    h.settle()
    h.check(menuItem(top(), "Puzzles"), "English again")
    top():onClose()
    h.settle()
end
