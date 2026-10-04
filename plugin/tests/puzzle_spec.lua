-- Puzzle session logic (pkpuzzle.lua) on real Lichess puzzles from the fixture.
local Chess = require("chess")
local PkPuzzle = require("pkpuzzle")

-- 004JD: white plays Kd2-e3, black mates with Na3-c2 (solver: black)
local MATE1_BLACK = { id = "004JD", fen = "3r4/R7/2p5/p1P2p2/1p4k1/nP6/P2KNP2/8 w - - 3 41",
                      moves = "d2e3 a3c2", solver = "b", rating = 1291 }
-- 0042j: mate in 2, solver white (4 moves: setup, solver, reply, solver)
local MATE2 = { id = "0042j", fen = "3r2k1/4nppp/pq1p1b2/1p2P3/2r2P2/2P1NR2/PP1Q2BP/3R2K1 b - - 0 24",
                moves = "d6e5 d2d8 b6d8 d1d8", solver = "w", rating = 550 }

local function play(game, uci)
    return game.move({ from = uci:sub(1, 2), to = uci:sub(3, 4), promotion = uci:sub(5, 5) ~= "" and uci:sub(5, 5) or nil })
end

return {
    { "start plays the opponent's setup move and hands the turn to the solver", function(t)
        local game = Chess:new()
        local s = PkPuzzle.new(MATE1_BLACK, game)
        local setup = s:start()
        t.eq(PkPuzzle.uciOf(setup), "d2e3", "setup move")
        t.eq(game.turn(), "b", "solver to move")
        t.eq(s:expected(), "a3c2", "expected move")
    end },
    { "correct final move solves the puzzle", function(t)
        local game = Chess:new()
        local s = PkPuzzle.new(MATE1_BLACK, game)
        s:start()
        t.eq(s:onUserMove(play(game, "a3c2")), "solved", "verdict")
        t.ok(s:isCleanSolve(), "clean solve")
        t.ok(s:isOver(), "over")
    end },
    { "wrong move is taken back and counted", function(t)
        local game = Chess:new()
        local s = PkPuzzle.new(MATE1_BLACK, game)
        s:start()
        local fen_before = game.fen()
        t.eq(s:onUserMove(play(game, "d8d1")), "wrong", "verdict")
        t.eq(game.fen(), fen_before, "position restored")
        t.eq(s.mistakes, 1, "mistakes")
        t.eq(s:onUserMove(play(game, "a3c2")), "solved", "then solved")
        t.ok(not s:isCleanSolve(), "not clean after a mistake")
    end },
    { "multi-move line: correct move triggers the opponent's reply", function(t)
        local game = Chess:new()
        local s = PkPuzzle.new(MATE2, game)
        s:start()
        local verdict, reply = s:onUserMove(play(game, "d2d8"))
        t.eq(verdict, "correct", "first solver move")
        t.eq(PkPuzzle.uciOf(reply), "b6d8", "opponent reply")
        t.eq(s:onUserMove(play(game, "d1d8")), "solved", "final move")
    end },
    { "any checkmating move is accepted even if it differs from the line", function(t)
        -- White to move after the setup; both Qd8# and Rd8# would mate here.
        local p = { id = "alt", fen = "6k1/5ppp/8/8/8/8/5PPP/3RQ1K1 b - - 0 1",
                    moves = "g8h8 d1d8", solver = "w", rating = 800 }
        local game = Chess:new()
        local s = PkPuzzle.new(p, game)
        s:start()
        t.eq(s:onUserMove(play(game, "e1e8")), "solved", "alternative mate")
    end },
    { "hint gives the from-square and marks help as used", function(t)
        local game = Chess:new()
        local s = PkPuzzle.new(MATE2, game)
        s:start()
        t.eq(s:hint(), "d2", "hint square")
        s:onUserMove(play(game, "d2d8")); s:onUserMove(play(game, "d1d8"))
        t.eq(s.state, "solved", "solved")
        t.ok(not s:isCleanSolve(), "hint prevents a clean solve")
    end },
    { "revealSolution plays the remaining line and fails the attempt", function(t)
        local game = Chess:new()
        local s = PkPuzzle.new(MATE2, game)
        s:start()
        local played = s:revealSolution()
        t.eq(#played, 3, "three moves revealed")
        t.eq(s.state, "failed", "failed")
        t.ok(game.in_checkmate(), "final position is mate")
        t.eq(s:expected(), nil, "nothing expected after the end")
    end },
    { "promotion letter is part of the expected move", function(t)
        -- White pawn on b7 must promote to a knight (fork), not a queen.
        local p = { id = "promo", fen = "3k4/1P6/8/8/8/8/8/4K3 b - - 0 1",
                    moves = "d8c7 b7b8n", solver = "w", rating = 1000 }
        local game = Chess:new()
        local s = PkPuzzle.new(p, game)
        s:start()
        t.eq(s:onUserMove(play(game, "b7b8q")), "wrong", "queen promotion is wrong")
        t.eq(s:onUserMove(play(game, "b7b8n")), "solved", "knight promotion")
    end },
}
