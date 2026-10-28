-- Master games (pkgames.lua): the file read, a Guess the move session, its
-- verdicts and score, saving and resuming. The fixture (fixtures/games.tsv,
-- written by the pipeline's games.write) has the Opera Game with made-up
-- scores: at each ply the master's move 100, the first other legal move
-- (UCI order) 90, the last -200; a key moment at 16. Qb8+ (ply 31). Then a
-- short draw.
local PkGames = require("pkgames")
PkGames.path = (PK_REPO_ROOT or ".") .. "/plugin/tests/fixtures/games.tsv"
PkGames.reset()

local function mv(uci)
    return { from = uci:sub(1, 2), to = uci:sub(3, 4), promotion = #uci > 4 and uci:sub(5, 5) or nil }
end

-- plays the session to the next guess: the other side's replies
local function replies(s)
    while s:replyNext() do s:reply() end
end

return {
    { "the games read from the file", function(t)
        local list = PkGames.list()
        t.eq(#list, 2)
        local opera = PkGames.get("opera")
        t.eq(opera.title, "The Opera Game"); t.eq(opera.white, "Morphy"); t.eq(opera.year, "1858")
        t.eq(PkGames.players(opera), "Morphy – Duke Karl Count Isouard")
        t.eq(PkGames.place(opera), "Paris 1858")
        t.eq(PkGames.winner(opera), "w"); t.eq(PkGames.winner(PkGames.get("draw")), nil)
        t.eq(PkGames.get("nope"), nil)
        PkGames.path = "/nonexistent/games.tsv"; PkGames.reset()
        t.eq(#PkGames.list(), 0, "no file: no games")
        PkGames.path = (PK_REPO_ROOT or ".") .. "/plugin/tests/fixtures/games.tsv"; PkGames.reset()
    end },
    { "a session: the opening played, the winner's side guessed", function(t)
        local s = PkGames.session(PkGames.get("opera"))
        t.eq(s.side, "w"); t.eq(s:ply(), 5, "the book: 1. e4 e5 2. Nf3 d6 3. d4")
        t.ok(s:replyNext() and not s:guessing(), "Black's reply first")
        t.eq(s:reply().san, "Bg4")
        t.ok(s:guessing())
        t.eq(s:hint(), "d4", "4. dxe5: the pawn on d4")
        local draw = PkGames.session(PkGames.get("draw"))
        t.eq(draw.side, "w", "a draw: White"); t.ok(draw:guessing(), "after 1. e4 e5")
        t.eq(PkGames.session(PkGames.get("opera"), "b").side, "b")
    end },
    { "verdicts: the master's move, a good move too, a miss; shown", function(t)
        local s = PkGames.session(PkGames.get("opera"))
        replies(s)
        local verdict, info = s:guess(mv("d4e5"))
        t.eq(verdict, "found"); t.eq(info.master, "dxe5"); t.eq(info.best, "dxe5")
        replies(s)
        -- 5. Qxf3: the first other legal move in UCI order is a2a3 (90)
        verdict, info = s:guess(mv("a2a3"))
        t.eq(verdict, "good", "within the margin of the master's move"); t.eq(info.guess, "a3")
        t.eq(info.master, "Qxf3"); t.eq(info.cp_guess, 90); t.eq(info.cp_master, 100)
        t.eq(s:ply(), 9, "the master's move played, not the guess")
        replies(s)
        -- 6. Bc4: a move Stockfish did not list
        verdict, info = s:guess(mv("b1c3"))
        t.eq(verdict, "miss"); t.eq(info.cp_guess, nil); t.eq(info.master, "Bc4")
        replies(s)
        local move = s:show()
        t.eq(move.san, "Qb3", "shown")
        t.eq(s.found, 1); t.eq(s.good, 1); t.eq(s.asked, 4)
        t.eq(s:scoreText(), "Found 1 of 4 · 1 good")
        local got, max = s:points()
        t.eq(got, 3); t.eq(max, 8)
        t.eq(s:guess(mv("e7e5")), nil, "not the user's turn")
    end },
    { "a bad move by the scores is a miss; key moments counted", function(t)
        local s = PkGames.session(PkGames.get("opera"))
        replies(s)
        t.eq(s:guess(mv("h2h4")), "miss", "-200: not a good move")
        while s:ply() < 30 do
            if s:guessing() then s:show() else s:reply() end
        end
        t.ok(s:guessing() and s:keyMoment(), "16. Qb8+ is a key moment")
        local verdict, info = s:guess(mv("b3b8"))
        t.eq(verdict, "found"); t.ok(info.key)
        t.eq(s.keys, 1); t.eq(s.keys_found, 1)
        replies(s)
        t.eq(s:guess(mv("d1d8")), "found")
        t.ok(s:over() and not s:guessing() and not s:replyNext(), "the game is over")
        t.eq(s:reply(), nil)
    end },
    { "a hint: the master's move then counts as a good move, not at a key moment", function(t)
        local s = PkGames.session(PkGames.get("opera"))
        replies(s)
        t.eq(s:hint(), "d4")
        local verdict = s:guess(mv("d4e5"))
        t.eq(verdict, "hinted"); t.eq(s.found, 0); t.eq(s.good, 1)
        replies(s)
        t.eq(s:guess(mv("d1f3")), "found", "the hint was for one move only")
        while s:ply() < 30 do
            if s:guessing() then s:show() else s:reply() end
        end
        s:hint()
        t.eq(s:guess(mv("b3b8")), "hinted")
        t.eq(s.keys, 1); t.eq(s.keys_found, 0, "a key moment found with a hint does not count")
        t.eq(PkGames.restore(s:serialize()).verdicts[31], "hinted")
    end },
    { "saved and resumed", function(t)
        local s = PkGames.session(PkGames.get("opera"), "b")
        t.ok(s:guessing(), "3... Bg4 to guess")
        s:guess(mv("c8g4"))
        s:reply()
        s:guess(mv("a7a6"))
        local text = s:serialize()
        local r = PkGames.restore(text)
        t.eq(r.side, "b"); t.eq(r:ply(), s:ply()); t.eq(r.found, 1); t.eq(r.asked, 2)
        t.eq(r.verdicts[6], "found"); t.eq(r.verdicts[8], "miss"); t.eq(r.verdicts[7], nil)
        t.eq(r:serialize(), text)
        t.eq(PkGames.restore("v1|gone|w|0|0|0|0|0|0|"), nil, "the game is gone")
        t.eq(PkGames.restore("garbage"), nil); t.eq(PkGames.restore(nil), nil)
    end },
    { "winning chances", function(t)
        t.eq(PkGames.win(0), 50)
        t.ok(PkGames.win(10000) > 99 and PkGames.win(-10000) < 1)
        t.eq(math.floor(PkGames.win(300) + 0.5), 75)
    end },
}
