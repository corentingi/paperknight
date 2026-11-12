-- The plugin's translations (docs/translations.md): `_ = require("pkgettext")`
-- in place of KOReader's gettext. A string is looked up in the plugin's own
-- catalogue for KOReader's language (l10n/<lang>.po, read on first use),
-- then in KOReader's (its common words: "Cancel"…), else shown as written.
-- KOReader translates only the strings of its own catalogue, which has none
-- of the plugin's.
local gettext = require("gettext")

local PkGettext = {
    dir = nil, -- default: <plugin>/l10n (tests set another)
}

local catalogs = {} -- lang -> { msgid -> msgstr }, false if none

local ESCAPES = { n = "\n", t = "\t", ['"'] = '"', ["\\"] = "\\" }
local function unescape(s)
    return (s:gsub("\\(.)", function(c) return ESCAPES[c] or ("\\" .. c) end))
end

--- The entries of a .po file's text: { msgid -> msgstr } (the untranslated
-- ones left out). No plurals or contexts: the plugin uses none.
function PkGettext.parse(text)
    local entries, msgid, msgstr, field = {}, nil, nil, nil
    local function flush()
        if msgid and msgid ~= "" and msgstr and msgstr ~= "" then entries[msgid] = msgstr end
    end
    for line in (text .. "\n"):gmatch("(.-)\r?\n") do
        line = line:match("^%s*(.-)%s*$")
        local key, value = line:match('^(msg%a+)%s+"(.*)"$')
        if key == "msgid" then
            flush()
            msgid, msgstr, field = unescape(value), nil, "msgid"
        elseif key == "msgstr" then
            msgstr, field = unescape(value), "msgstr"
        elseif line:match('^"(.*)"$') and field then
            local more = unescape(line:match('^"(.*)"$'))
            if field == "msgid" then msgid = msgid .. more else msgstr = (msgstr or "") .. more end
        end
    end
    flush()
    return entries
end

local function dir()
    return PkGettext.dir or (require("pkicons").plugin_dir .. "/l10n")
end

-- The catalogue of `lang` ("fr", or "fr_FR": then "fr" if there is no
-- fr_FR.po), false if there is none.
local function catalog(lang)
    if catalogs[lang] ~= nil then return catalogs[lang] end
    catalogs[lang] = false
    for _, name in ipairs({ lang, lang:match("^(%a+)[_-]") }) do
        local f = io.open(dir() .. "/" .. name .. ".po", "rb")
        if f then
            local text = f:read("*a")
            f:close()
            local ok, entries = pcall(PkGettext.parse, text)
            if ok then
                catalogs[lang] = entries
                break
            end
            require("logger").warn("Paperknight: cannot read the translation", name, entries)
        end
    end
    return catalogs[lang]
end

--- KOReader's language ("C": none).
function PkGettext.lang()
    return gettext.current_lang or "C"
end

--- Forgets the catalogues read (tests; a new file).
function PkGettext.reset() catalogs = {} end

setmetatable(PkGettext, {
    __call = function(_, msgid)
        local lang = PkGettext.lang()
        if lang ~= "C" and lang ~= "en" then
            local entries = catalog(lang)
            local msgstr = entries and entries[msgid]
            if msgstr then return msgstr end
        end
        return gettext(msgid)
    end,
})

return PkGettext
