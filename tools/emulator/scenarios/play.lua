-- Play (pkplayview.lua, ADR-0020): the new game dialog, a game against a
-- fake Stockfish (scripted replies; it logs what it is sent), take-back,
-- resuming, resigning, two players face to face (Black's pieces upside
-- down) with a clock, checkmate, the flag, saving, the analysis board.
-- Squares are tapped like a user would.
local UIManager = require("ui/uimanager")

return function(h)
    local pk = h.ui.paperknight
    local PkProgress = require("pkprogress")
    local home = os.getenv("HOME")
    local function top() return UIManager._window_stack[#UIManager._window_stack].widget end
    local function read(path)
        local f = io.open(path)
        if not f then return "" end
        local s = f:read("*a")
        f:close()
        return s
    end

    -- the fake engine: a reply per position (the moves after "moves")
    local log = home .. "/engine.log"
    local script = home .. "/fake-stockfish.sh"
    local f = assert(io.open(script, "w"))
    f:write('#!/bin/sh\nmoves=\nwhile read l; do echo "$l" >> "' .. log .. '"; case "$l" in\n'
        .. '  uci) echo "id name FakeFish"; echo uciok;;\n'
        .. '  isready) echo readyok;;\n'
        .. '  position*) moves="${l#*moves }"; [ "$moves" = "$l" ] && moves=;;\n'
        .. '  go*) case "$moves" in\n'
        .. '      "") echo "bestmove e2e4";;\n'
        .. '      "e2e4 e7e5") echo "bestmove g1f3";;\n'
        .. '      "e2e4 c7c5") echo "bestmove g1f3";;\n'
        .. '      *) echo "bestmove 0000";;\n'
        .. '    esac;;\n'
        .. '  quit) exit 0;;\nesac; done\n')
    f:close()
    os.execute("chmod +x '" .. script .. "'")

    local view
    local function sq(square) return view.board.table:getButtonById(view.board.chessToId(square)) end
    local function move(from, to) h.tapWidget(sq(from)); h.tapWidget(sq(to)) end
    local function history() return table.concat(view.game.history(), " ") end
    local function panel() return view.panel_text or "" end
    local function radio(setup, key, text)
        local found
        for _, row in ipairs(setup.radios[key].radio_buttons_layout) do
            for _, b in ipairs(row) do if b.text == text then found = b end end
        end
        return found
    end

    -- 1. Against Stockfish, as Black: it opens by itself. (A dialog closed
    -- without a game: it comes back next time.)
    view = pk:startGame{ engine_path = script }
    h.settle()
    view.setup:onClose()
    view:onClose()
    h.settle()
    view = pk:startGame{ engine_path = script }
    h.settle()
    local setup = view.setup
    h.check(setup and setup.has_engine and setup.choice.opponent == "engine", "dialog: Stockfish by default")
    h.tapWidget(radio(setup, "side", "Black"))
    h.tapWidget(radio(setup, "level", "1800"))
    h.check(setup.choice.side == "b" and setup.choice.level == 1800, "side and strength chosen")
    h.shot("play-setup")
    h.tapWidget(h.findButton(setup, "Start"))
    h.settle()
    h.check(view.board.flipped, "Black: the board from Black's side")
    h.check(h.waitFor(function() return history() == "e4" end, 5), "Stockfish opened: " .. history())
    local sent = read(log)
    h.check(sent:find("setoption name UCI_LimitStrength value true", 1, true)
        and sent:find("setoption name UCI_Elo value 1800", 1, true), "strength set: " .. sent)
    h.check(sent:find("go movetime 1000", 1, true), "thinking time of the level")
    h.check(view.title_bar.subtitle_widget.text:find("Stockfish 1800", 1, true), "subtitle: "
        .. view.title_bar.subtitle_widget.text)
    h.check(panel():find("Your move.", 1, true), "your move: " .. panel())
    h.check(not view.buttons:getButtonById("takeback").enabled, "nothing of yours to take back")
    move("e7", "e5")
    h.check(h.waitFor(function() return history() == "e4 e5 Nf3" end, 5), "Stockfish replied: " .. history())
    h.check(panel():find("King's Knight Opening", 1, true), "the opening named: " .. panel())
    h.shot("play-engine")

    -- 2. Take back: your move and its reply.
    h.tapWidget(view.buttons:getButtonById("takeback"))
    h.check(history() == "e4" and view.play:isUserTurn(), "taken back to your move: " .. history())

    -- 3. Closed and opened again: the game comes back, without the dialog.
    move("c7", "c5")
    h.check(h.waitFor(function() return history() == "e4 c5 Nf3" end, 5), "played on: " .. history())
    view:onClose()
    h.settle()
    view = pk:startGame{ engine_path = script }
    h.settle()
    h.check(view.resumed and not view.setup and history() == "e4 c5 Nf3", "resumed: " .. history())
    h.check(view.play.user_side == "b" and view.board.flipped, "as Black again")

    -- 4. Resigning ends it: the next opening asks for a new game.
    view:resign()
    h.settle()
    h.check(panel():find("Stockfish wins by resignation.", 1, true), "resigned: " .. panel())
    h.check(PkProgress.readSetting("play.current") == nil, "a finished game is not kept")
    h.check(view.board.locked, "the board takes no more moves")

    -- 5. Two players face to face, with a clock: Black's pieces upside down.
    setup = view:showSetup()
    h.settle()
    h.tapWidget(radio(setup, "opponent", "Two players"))
    h.settle() -- (the dialog rebuilds with the questions for two players)
    h.check(radio(setup, "face", "Face to face") and radio(setup, "face", "Face to face").checked, "face to face by default")
    h.tapWidget(radio(setup, "clock", "5 min"))
    h.tapWidget(h.findButton(setup, "Start"))
    h.settle()
    h.check(not view.board.flipped and view.board.rotate_black, "White's side, Black's pieces turned")
    h.check(sq("e8").icon_rotation_angle == 180 and (sq("e1").icon_rotation_angle or 0) == 0,
        "the black king upside down, the white one upright")
    h.check(view.title_bar.subtitle_widget.text:find("5:00 · ", 1, true), "clocks: " .. view.title_bar.subtitle_widget.text)
    h.check(panel():find("The clock starts with the next move.", 1, true), "clock waits: " .. panel())
    h.shot("play-face-to-face")
    move("f2", "f3")
    h.check(view.timer.running and view.timer.currentPlayer == "b", "Black's clock runs")
    h.check(sq("f3").icon_rotation_angle == 0 or sq("f3").icon_rotation_angle == nil, "a moved white pawn upright")
    move("e7", "e5")
    h.check(sq("e5").icon_rotation_angle == 180, "a moved black pawn stays upside down")
    move("g2", "g4"); move("d8", "h4")
    h.check(panel():find("Black wins by checkmate.", 1, true), "mate: " .. panel())
    h.check(not view.timer.running and view.board.locked, "clock stopped, board locked")
    h.check(view.board.mate_square == "e1", "# on the mated king")

    -- 6. Saved as a study, and on the analysis board.
    local dir = home .. "/games"
    local path = view:saveGame("Fool's mate", dir)
    h.check(path and read(path):find("1. f3 e5 2. g4 Qh4# 0-1", 1, true), "saved: " .. read(path or ""))
    h.tapWidget(view.buttons:getButtonById("analyse"))
    h.settle()
    local av = top()
    h.check(av.name == "paperknight_analysis" and av.pos == 4 and #av.line == 4, "the game on the analysis board")
    av:onClose()
    h.settle()

    -- 7. A take-back after the end: the game goes on; then the flag falls.
    h.tapWidget(view.buttons:getButtonById("takeback"))
    h.check(history() == "f3 e5 g4" and view.play.result == nil, "the mate taken back: " .. history())
    move("d8", "h4")
    h.check(view.play.result, "mated again")
    h.tapWidget(view.buttons:getButtonById("takeback"))
    move("a7", "a6") -- Black's move: White's clock runs
    view.timer:stop()
    view.timer.time.w = 0 -- (White's time is up: the next tick sees it)
    view.timer:start()
    h.check(h.waitFor(function() return view.play.result ~= nil end, 8), "flag fell")
    h.check(panel():find("Black wins on time.", 1, true), "on time: " .. panel())

    view:onClose()
    h.settle()
end
