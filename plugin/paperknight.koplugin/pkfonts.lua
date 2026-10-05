-- Emoji support: if a monochrome Noto Emoji font is installed (e.g. in
-- koreader/fonts), add it to KOReader's UI fallback fonts so the emojis
-- common in Lichess studies render instead of empty boxes. Same effect as
-- Settings → Device → Additional UI fallback fonts; idempotent.
local logger = require("logger")

local PkFonts = {}

-- Monochrome Noto Emoji files ("NotoEmoji-Regular.ttf", "NotoEmoji[wght].ttf",
-- …); the color version (bitmaps) cannot be drawn and is skipped.
local function isEmojiFont(path)
    local file = path:match("([^/]+)$") or path
    local lower = file:lower()
    return lower:find("notoemoji", 1, true) ~= nil and lower:find("color", 1, true) == nil
        and (lower:match("%.ttf$") or lower:match("%.otf$")) ~= nil
end

--- Adds the first emoji font of `font_list` (default: KOReader's font list)
-- to Font.fallbacks. Returns its file name, or nil if none is installed.
function PkFonts.addEmojiFallback(font_list, Font)
    Font = Font or require("ui/font")
    if not font_list then
        local ok, FontList = pcall(require, "fontlist")
        font_list = ok and FontList:getFontList() or {}
    end
    local found
    for _, path in ipairs(font_list) do
        if isEmojiFont(path) then found = path; break end
    end
    if not found then return nil end
    local name = found:match("([^/]+)$")
    for _, fb in ipairs(Font.fallbacks) do
        if fb == name or fb == found or (fb:match("([^/]+)$") == name) then return name end -- already there
    end
    table.insert(Font.fallbacks, Font.additional_fallback_insert_indice or 3, name)
    -- faces already used may have cached "no more fallbacks": recompute
    for _, face in pairs(Font.faces or {}) do face.fallbacks = nil end
    logger.info("Paperknight: emoji font added to UI fallbacks:", name)
    return name
end

PkFonts._isEmojiFont = isEmojiFont
return PkFonts
