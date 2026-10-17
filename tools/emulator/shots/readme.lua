-- Screenshots for the README that no test scenario takes (not part of
-- `make e2e`): make e2e E2E_SCENARIOS=tools/emulator/shots/readme.lua,
-- then copy build/e2e/readme-*.png to docs/screenshots/ (docs/development.md).
return function(h)
    local PkAnalysis = require("pkanalysis")
    -- an Italian Game (the line of the study fixture, python-chess checked)
    local view = PkAnalysis.show{}
    h.settle()
    for _, san in ipairs({ "e4", "e5", "Nf3", "Nc6", "Bc4", "Bc5", "c3", "Nf6", "d4", "exd4",
                           "cxd4", "Bb4+", "Bd2", "Bxd2+", "Nbxd2", "d5" }) do
        local m = view.game.move(san)
        h.check(m, "move " .. san)
        view.board:updateBoard()
        view:onBoardMove(m)
    end
    h.settle()
    h.shot("readme-analysis")
    view:onClose()
    h.settle()
end
