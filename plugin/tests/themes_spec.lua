-- Theme labels and menu order (pkthemes.lua).
package.loaded["gettext"] = package.loaded["gettext"] or function(s) return s end
local PkThemes = require("pkthemes")

return {
    { "labels: overrides and readable fallback", function(t)
        t.eq(PkThemes.label("mateIn2"), "Mate in 2", "override")
        t.eq(PkThemes.label("kingsideAttack"), "Kingside attack", "camelCase fallback")
        t.eq(PkThemes.label("fork"), "Fork", "single word")
        t.eq(PkThemes.label("xRayAttack"), "X-ray attack", "override with hyphen")
    end },
    { "sorted: featured first in order, then alphabetical by label", function(t)
        local out = PkThemes.sorted({
            { theme = "zugzwang" }, { theme = "fork" }, { theme = "mateIn1" }, { theme = "bishopEndgame" },
        })
        local keys = {}
        for i, th in ipairs(out) do keys[i] = th.theme end
        t.eq(table.concat(keys, " "), "mateIn1 fork bishopEndgame zugzwang", "order")
    end },
    { "shown: skill themes of a puzzle, in menu order", function(t)
        local labels = PkThemes.shown("backRankMate mate mateIn2 middlegame short")
        t.eq(table.concat(labels, ", "), "Mate in 2, Back rank mate, Middlegame", "length, mate dropped")
        t.eq(#PkThemes.shown("crushing master long"), 0, "nothing worth showing")
        t.eq(#PkThemes.shown(nil), 0, "no tags")
    end },
    { "isSkill: evaluation and source tags are not skills", function(t)
        t.ok(PkThemes.isSkill("fork") and PkThemes.isSkill("long") and PkThemes.isSkill("mate"), "skills")
        t.ok(not PkThemes.isSkill("crushing") and not PkThemes.isSkill("superGM"), "not skills")
    end },
}
