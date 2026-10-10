-- Display names and menu order for Lichess puzzle theme keys.
-- Keys come from the pack's `themes` table; unknown keys get a readable
-- fallback ("kingsideAttack" -> "Kingside attack"), so new themes still work.
local _ = require("gettext")

local PkThemes = {}

local NAMES = {
    mateIn1 = _("Mate in 1"), mateIn2 = _("Mate in 2"), mateIn3 = _("Mate in 3"),
    mateIn4 = _("Mate in 4"), mateIn5 = _("Mate in 5 or more"),
    attackingF2F7 = _("Attacking f2/f7"), xRayAttack = _("X-ray attack"),
    enPassant = _("En passant"), underPromotion = _("Underpromotion"),
    oneMove = _("One-move puzzle"), short = _("Short puzzle"), long = _("Long puzzle"),
    veryLong = _("Very long puzzle"), master = _("Master games"),
    masterVsMaster = _("Master vs master games"), superGM = _("Super GM games"),
    morphysMate = _("Morphy's mate"), pillsburysMate = _("Pillsbury's mate"),
    anastasiaMate = _("Anastasia's mate"), bodenMate = _("Boden's mate"),
    hangingPiece = _("Hanging piece"), quietMove = _("Quiet move"),
}

-- Shown first, in this order (when present in the pack); the rest follow alphabetically.
local FEATURED = {
    "mateIn1", "mateIn2", "mateIn3", "fork", "pin", "skewer", "discoveredAttack",
    "doubleCheck", "sacrifice", "deflection", "attraction", "backRankMate",
    "hangingPiece", "trappedPiece", "quietMove", "endgame", "opening", "middlegame",
}

function PkThemes.label(key)
    if NAMES[key] then return NAMES[key] end
    local words = key:gsub("(%u)", " %1"):gsub("(%d+)", " %1"):lower()
    return (words:gsub("^%l", string.upper))
end

-- Tags that say nothing about the skill trained: evaluation of the final
-- position and the source of the game. Left out of the stats.
local NOT_SKILL = {
    advantage = true, crushing = true, equality = true,
    master = true, masterVsMaster = true, superGM = true,
}
-- Also left out of a solved puzzle's theme line: the length (seen while
-- solving) and the generic "mate" (mateInN says more).
local NOT_SHOWN = { short = true, long = true, veryLong = true, oneMove = true, mate = true }

--- True if theme `key` measures a skill (kept in the stats).
function PkThemes.isSkill(key)
    return not NOT_SKILL[key]
end

--- Labels of a puzzle's themes worth showing once it is over (`tags`: the
-- pack's space-separated keys), in menu order.
function PkThemes.shown(tags)
    local list = {}
    for key in (tags or ""):gmatch("%S+") do
        if not NOT_SKILL[key] and not NOT_SHOWN[key] then list[#list + 1] = { theme = key } end
    end
    local labels = {}
    for i, t in ipairs(PkThemes.sorted(list)) do labels[i] = PkThemes.label(t.theme) end
    return labels
end

--- Orders `themes` ({ {theme=, count=}, ... }) for a menu: featured first.
function PkThemes.sorted(themes)
    local rank = {}
    for i, key in ipairs(FEATURED) do rank[key] = i end
    local out = {}
    for _, t in ipairs(themes) do out[#out + 1] = t end
    table.sort(out, function(a, b)
        local ra, rb = rank[a.theme], rank[b.theme]
        if ra and rb then return ra < rb end
        if ra or rb then return ra ~= nil end
        return PkThemes.label(a.theme) < PkThemes.label(b.theme)
    end)
    return out
end

return PkThemes
