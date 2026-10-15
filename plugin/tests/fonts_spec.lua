-- Emoji fallback font (pkfonts.lua): added once, after the CJK font, only
-- for a monochrome Noto Emoji file.
local PkFonts = require("pkfonts")

local function fakeFont()
    return {
        fallbacks = { "NotoSans-Regular.ttf", "NotoSansCJKsc-Regular.otf", "nerdfonts/symbols.ttf" },
        additional_fallback_insert_indice = 3,
        faces = { a = { fallbacks = { false } } },
    }
end

return {
    { "emoji font added to the UI fallbacks, once", function(t)
        local Font = fakeFont()
        local name = PkFonts.addEmojiFallback({ "/x/fonts/FreeSans.ttf", "/mnt/us/koreader/fonts/NotoEmoji-Regular.ttf" }, Font, {})
        t.eq(name, "NotoEmoji-Regular.ttf", "found")
        t.eq(Font.fallbacks[3], "NotoEmoji-Regular.ttf", "inserted after the CJK font")
        t.eq(Font.faces.a.fallbacks, nil, "cached fallbacks reset")
        PkFonts.addEmojiFallback({ "/mnt/us/koreader/fonts/NotoEmoji-Regular.ttf" }, Font, {})
        t.eq(#Font.fallbacks, 4, "not added twice")
    end },
    { "not added when the user's additional fallbacks are at KOReader's limit", function(t)
        local Font = fakeFont()
        Font.additional_fallback_max_nb = 2
        local name = PkFonts.addEmojiFallback({ "/f/NotoEmoji-Regular.ttf" }, Font, { "a.ttf", "b.ttf" })
        t.eq(name, nil, "limit reached")
        t.eq(#Font.fallbacks, 3, "unchanged")
        t.eq(PkFonts.addEmojiFallback({ "/f/NotoEmoji-Regular.ttf" }, Font, { "a.ttf" }), "NotoEmoji-Regular.ttf", "under the limit")
    end },
    { "no emoji font, or only the color one: nothing changes", function(t)
        local Font = fakeFont()
        t.eq(PkFonts.addEmojiFallback({ "/f/FreeSans.ttf" }, Font, {}), nil, "none installed")
        t.eq(PkFonts.addEmojiFallback({ "/f/NotoColorEmoji.ttf" }, Font, {}), nil, "color font skipped")
        t.eq(#Font.fallbacks, 3, "unchanged")
        t.ok(PkFonts._isEmojiFont("/f/NotoEmoji[wght].ttf"), "variable font name")
    end },
}
