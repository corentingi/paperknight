-- Play mode logic (pkplay.lua): settings, sides, take-backs, results, the
-- saved game. Positions checked with python-chess.
local PkPlay = require("pkplay")

local function settings(over)
    local s = { opponent = "engine", side = "w", level = 1500, face = true, clock = "off" }
    for k, v in pairs(over or {}) do s[k] = v end
    return s
end

local function uci(game, moves)
    for m in moves:gmatch("%S+") do
        assert(game:play({ from = m:sub(1, 2), to = m:sub(3, 4), promotion = m:sub(5, 5) ~= "" and m:sub(5, 5) or nil }, true), m)
    end
end

return {
    { "settings: defaults, saved and read back, unknown values dropped", function(t)
        local store = {}
        local function read(k) return store[k] end
        local s = PkPlay.loadSettings(read)
        t.eq(s.opponent, "engine"); t.eq(s.side, "w"); t.eq(s.level, 1500); t.eq(s.face, true); t.eq(s.clock, "off")
        PkPlay.saveSettings(settings({ opponent = "human", side = "random", level = 0, face = false, clock = "15+10" }),
            function(k, v) store[k] = v end)
        s = PkPlay.loadSettings(read)
        t.eq(s.opponent, "human"); t.eq(s.side, "random"); t.eq(s.level, 0); t.eq(s.face, false); t.eq(s.clock, "15+10")
        store["play.level"], store["play.clock"], store["play.side"] = "1234", "1+1", "x"
        s = PkPlay.loadSettings(read)
        t.eq(s.level, 1500, "not a level"); t.eq(s.clock, "off", "not a time control"); t.eq(s.side, "w")
    end },
    { "time controls and names", function(t)
        local base, inc = PkPlay.clockSpec("15+10")
        t.eq(base, 900); t.eq(inc, 10)
        t.eq(PkPlay.clockSpec("off"), nil)
        t.eq(PkPlay.clockName("5+0"), "5 min"); t.eq(PkPlay.clockName("15+10"), "15 min + 10 s")
        t.eq(PkPlay.clockName("off"), "No clock")
        t.eq(PkPlay.levelName(0), "full strength"); t.eq(PkPlay.levelName(1800), "1800")
    end },
    { "sides against the engine; random; no engine: two players", function(t)
        local g = PkPlay.new(settings({ side = "b" }))
        t.eq(g.user_side, "b"); t.eq(g.engine_side, "w")
        t.ok(g:isEngineTurn(), "the engine opens"); t.ok(not g:isUserTurn())
        t.eq(g:play({ from = "e2", to = "e4" }), nil, "the user cannot move for the engine")
        t.ok(g:play({ from = "e2", to = "e4" }, true), "the engine's move")
        t.ok(g:isUserTurn())
        t.eq(PkPlay.new(settings({ side = "random" }), { random = function() return 2 end }).user_side, "b")
        t.eq(PkPlay.new(settings({ side = "random" }), { random = function() return 1 end }).user_side, "w")
        local h = PkPlay.new(settings(), { engine = false })
        t.ok(not h:vsEngine() and h.settings.opponent == "human", "no Stockfish: two players")
        t.ok(h:isUserTurn())
    end },
    { "take back: to the user's last move against the engine, one ply between players", function(t)
        local g = PkPlay.new(settings({ side = "b" }))
        uci(g, "e2e4")
        t.eq(g:takeBackPlies(), 0, "only the engine's opening move")
        uci(g, "e7e5 g1f3")
        t.eq(g:takeBackPlies(), 2, "the user's move and the engine's reply")
        t.eq(g:takeBack(), 2); t.eq(g:uciMoves(), "e2e4")
        uci(g, "c7c5")
        t.eq(g:takeBackPlies(), 1, "the engine is thinking: the user's move")
        local h = PkPlay.new(settings({ opponent = "human" }))
        t.eq(h:takeBackPlies(), 0)
        uci(h, "e2e4 e7e5")
        t.eq(h:takeBack(), 1); t.eq(h:uciMoves(), "e2e4")
    end },
    { "results: checkmate, stalemate, resignation, time; a take-back reopens the game", function(t)
        local g = PkPlay.new(settings({ side = "b" }))
        uci(g, "f2f3 e7e5 g2g4 d8h4")
        t.eq(g.result.score, "0-1"); t.eq(g:resultText(), "You win by checkmate.")
        t.ok(not g:isUserTurn() and not g:isEngineTurn(), "nobody moves")
        t.eq(g:play({ from = "a2", to = "a3" }, true), nil, "no move after the end")
        t.eq(g:takeBack(), 1, "the mating move"); t.eq(g.result, nil); t.ok(g:isUserTurn())
        local s = PkPlay.new(settings({ opponent = "human" }), { fen = "k7/8/1K6/8/8/8/8/2Q5 w - - 0 1" })
        uci(s, "c1c7")
        t.eq(s:resultText(), "Draw: stalemate.")
        local r = PkPlay.new(settings({ opponent = "human" }))
        r:resign("w"); t.eq(r:resultText(), "Black wins by resignation.")
        local f = PkPlay.new(settings())
        f:flag("w"); t.eq(f:resultText(), "Stockfish wins on time.")
        f:flag("b"); t.eq(f.result.score, "0-1", "the first result stays")
    end },
    { "the game as PGN", function(t)
        local g = PkPlay.new(settings({ side = "b", level = 1800 }))
        uci(g, "f2f3 e7e5 g2g4 d8h4")
        local pgn = g:pgn('My "game"')
        t.ok(pgn:find('[Event "My \\"game\\""]', 1, true), "quotes escaped: " .. pgn)
        t.ok(pgn:find('[White "Stockfish 1800"]', 1, true) and pgn:find('[Black "You"]', 1, true), "players")
        t.ok(pgn:find('[Result "0-1"]', 1, true) and pgn:find('[Orientation "black"]', 1, true), "result, side")
        t.ok(pgn:find("\n\n1. f3 e5 2. g4 Qh4# 0-1\n", 1, true), "moves: " .. pgn)
        local h = PkPlay.new(settings({ opponent = "human" }))
        t.ok(h:pgn("x"):find('[White "White"]', 1, true) and h:pgn("x"):find("\n\n*\n", 1, true), "two players, no move")
    end },
    { "thinking time by level, bounded by the clock", function(t)
        t.eq(PkPlay.new(settings({ level = 1350 })):movetime(), 1000)
        t.eq(PkPlay.new(settings({ level = 2400 })):movetime(), 2000)
        t.eq(PkPlay.new(settings({ level = 0 })):movetime(), 5000)
        t.eq(PkPlay.new(settings({ level = 0 })):movetime(60), 2000, "a thirtieth of a minute")
        t.eq(PkPlay.new(settings({ level = 0 })):movetime(1), 200, "at least 0.2 s")
    end },
    { "the game in progress: saved and restored, not once over", function(t)
        local g = PkPlay.new(settings({ side = "random", level = 2100, clock = "5+0" }), { random = function() return 2 end })
        uci(g, "e2e4 c7c5 g1f3")
        local text = g:serialize({ w = 290.4, b = 281 })
        local r, times = PkPlay.restore(text)
        t.eq(r.user_side, "b", "the side drawn kept"); t.eq(r.settings.level, 2100); t.eq(r.settings.clock, "5+0")
        t.eq(r:uciMoves(), "e2e4 c7c5 g1f3"); t.ok(r:isUserTurn())
        t.eq(times.w, 290); t.eq(times.b, 281)
        local _, no_times = PkPlay.restore(PkPlay.new(settings()):serialize())
        t.eq(no_times, nil, "no clock")
        local m = PkPlay.new(settings({ opponent = "human" }))
        uci(m, "f2f3 e7e5 g2g4 d8h4")
        t.eq(PkPlay.restore(m:serialize()), nil, "a finished game is not resumed")
        t.eq(PkPlay.restore("garbage"), nil); t.eq(PkPlay.restore(nil), nil)
        local e = PkPlay.restore(g:serialize(), { engine = false })
        t.ok(not e:vsEngine(), "Stockfish gone since: two players")
    end },
}
