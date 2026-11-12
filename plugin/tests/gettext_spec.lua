-- The plugin's translations (pkgettext.lua): reading a catalogue, the
-- lookup by KOReader's language, the fallbacks. The catalogues themselves
-- are checked by tools/l10n/l10n.py (make lint).
local PkGettext = require("pkgettext")
local gettext = require("gettext")

local PO = [[
# a comment
msgid ""
msgstr ""
"Content-Type: text/plain; charset=UTF-8\n"

#: x.lua:1
msgid "Puzzles"
msgstr "Problèmes"

msgid "Line one\nLine \"two\""
msgstr "Ligne un\n"
"Ligne « deux »"

msgid "Not translated yet"
msgstr ""

msgid "Back\\slash %1"
msgstr "Barre\\oblique %1"
]]

local function withCatalog(name, text, fn)
    local dir = os.tmpname()
    os.remove(dir)
    os.execute("mkdir -p '" .. dir .. "'")
    local f = assert(io.open(dir .. "/" .. name, "w"))
    f:write(text)
    f:close()
    local lang = gettext.current_lang
    PkGettext.dir = dir
    PkGettext.reset()
    local ok, err = pcall(fn)
    gettext.current_lang = lang
    PkGettext.dir = nil
    PkGettext.reset()
    os.execute("rm -rf '" .. dir .. "'")
    if not ok then error(err, 0) end
end

return {
    { "a catalogue: entries, escapes, strings on several lines", function(t)
        local e = PkGettext.parse(PO)
        t.eq(e["Puzzles"], "Problèmes")
        t.eq(e['Line one\nLine "two"'], "Ligne un\nLigne « deux »", "escapes and continued strings")
        t.eq(e["Not translated yet"], nil, "an empty msgstr: left out")
        t.eq(e["Back\\slash %1"], "Barre\\oblique %1", "a backslash")
        t.eq(e[""], nil, "the header is not an entry")
    end },
    { "the lookup follows KOReader's language, then falls back", function(t)
        withCatalog("fr.po", PO, function()
            gettext.current_lang = "fr"
            t.eq(PkGettext("Puzzles"), "Problèmes")
            t.eq(PkGettext("Not translated yet"), "Not translated yet", "not translated: as written")
            t.eq(PkGettext("Unknown string"), "Unknown string")
            PkGettext.reset()
            gettext.current_lang = "fr_CA"
            t.eq(PkGettext("Puzzles"), "Problèmes", "fr_CA: the fr catalogue")
            gettext.current_lang = "C"
            t.eq(PkGettext("Puzzles"), "Puzzles", "English")
            gettext.current_lang = "de"
            t.eq(PkGettext("Puzzles"), "Puzzles", "no catalogue for German: English")
        end)
    end },
    { "the French catalogue shipped with the plugin", function(t)
        local lang = gettext.current_lang
        PkGettext.reset()
        gettext.current_lang = "fr"
        local ok, err = pcall(function()
            t.eq(PkGettext("Puzzles"), "Problèmes")
            t.eq(PkGettext("Master games"), "Parties de maîtres")
            local T = require("ffi/util").template
            t.eq(T(PkGettext("Rating: %1"), 1500), "Classement\u{a0}: 1500", "a template keeps its placeholder")
        end)
        gettext.current_lang = lang
        PkGettext.reset()
        if not ok then error(err, 0) end
    end },
}
