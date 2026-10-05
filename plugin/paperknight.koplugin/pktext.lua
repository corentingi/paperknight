-- Text helpers for the comment panels: links. A web address can't be opened
-- on an e-reader; it is shown short ("youtube.com ↗") and the panel offers a
-- QR code to scan with a phone.
local PkText = {}

PkText.LINK_MARK = " ↗"

-- Number of UTF-8 characters in `s` (TextBoxWidget positions count characters).
local function ulen(s)
    local _, n = s:gsub("[^\128-\191]", "")
    return n
end
PkText.ulen = ulen

--- Short label of a URL: its host without "www." (and port).
function PkText.linkLabel(url)
    if url:match("^%a[%w+.-]*://") and not url:match("^%a[%w+.-]*://[^/?#]") then return "link" end
    local host = url:match("^%a[%w+.-]*://([^/?#]+)") or url:match("^([^/?#]+)") or url
    host = host:gsub("^[^@]*@", ""):gsub(":%d+$", ""):gsub("^[Ww][Ww][Ww]%.", "")
    if not host:find("%w") then return "link" end
    return host
end

local URL_CHARS = "[%w%-%._~:/%?#%[%]@!%$&'%(%)%*%+,;=%%]"

-- Next web address at or after `pos`: "http(s)://…" (any case) or "www.…".
local function nextUrl(text, pos)
    local s1, e1 = text:find("[Hh][Tt][Tt][Pp][Ss]?://" .. URL_CHARS .. "+", pos)
    local s2, e2
    local from = pos
    while true do
        s2, e2 = text:find("[Ww][Ww][Ww]%.[%w%-]+%." .. URL_CHARS .. "+", from)
        if not s2 then break end
        local before = s2 > 1 and text:sub(s2 - 1, s2 - 1) or ""
        if not before:match("[%w/%.]") then break end -- part of a longer address
        from = e2 + 1
    end
    if s1 and (not s2 or s1 <= s2) then return s1, e1 end
    return s2, e2
end

-- Removes sentence punctuation after an address, one character at a time;
-- a ")" stays while the address has an unmatched "(".
local function trimUrl(url)
    while #url > 0 do
        local last = url:sub(-1)
        if last:match("[%.,;:!%?'\"%]]") then
            url = url:sub(1, -2)
        elseif last == ")" then
            local _, opens = url:gsub("%(", "")
            local _, closes = url:gsub("%)", "")
            if closes > opens then url = url:sub(1, -2) else break end
        else
            break
        end
    end
    return url
end

--- Replaces web addresses in `text` with short labels. Returns the display
-- text and the links { url, label, first, last } (character positions of the
-- label in the display text, for taps).
function PkText.linkify(text)
    local links = {}
    local out, pos, chars = {}, 1, 0
    while true do
        local s, e = nextUrl(text, pos)
        if not s then break end
        local url = trimUrl(text:sub(s, e))
        e = s + #url - 1
        local before = text:sub(pos, s - 1)
        out[#out + 1] = before
        chars = chars + ulen(before)
        local label = PkText.linkLabel(url)
        local shown = label .. PkText.LINK_MARK
        links[#links + 1] = { url = url, label = label, first = chars + 1, last = chars + ulen(shown) }
        out[#out + 1] = shown
        chars = chars + ulen(shown)
        pos = e + 1
    end
    out[#out + 1] = text:sub(pos)
    return table.concat(out), links
end

--- The link whose label covers character `index`, or nil.
function PkText.linkAt(links, index)
    for _, l in ipairs(links or {}) do
        if index >= l.first and index <= l.last then return l end
    end
end

return PkText
