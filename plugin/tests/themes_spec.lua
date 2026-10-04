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
}
