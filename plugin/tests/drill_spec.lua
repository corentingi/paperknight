-- Repertoire drill sessions (pkdrill.lua) and card storage (pkprogress.lua).
local Chess = require("pkchess")
local PkDrill = require("pkdrill")
local PkProgress = require("pkprogress")
local PkRepertoire = require("pkrepertoire")
local PkSrs = require("pksrs")
local PkStudy = require("pkstudy")

local FIXTURE = (PK_REPO_ROOT or ".") .. "/plugin/tests/fixtures/repertoires/repertoire.pgn"
local NOON = os.time{ year = 2026, month = 3, day = 10, hour = 12 }

local function setup(opts)
    opts = opts or {}
    local game = Chess:new()
    local rep = opts.rep or PkRepertoire.fromStudy(assert(PkStudy.open(FIXTURE)), game)
    local saved = {}
    local now = opts.now or NOON
    local d = PkDrill.new{
        rep = rep, game = game, cards = opts.cards,
        new_per_day = opts.new_per_day, introduced_today = opts.introduced_today,
        clock = function() now = now + 1; return now end, -- every call is a second later
        save = function(key, move, card) saved[key] = { move = move, card = card } end,
    }
    return d, saved, rep
end

local function play(d, uci)
    return d:onUserMove(uci:sub(1, 2), uci:sub(3, 4), uci:sub(5, 5) ~= "" and uci:sub(5, 5) or nil)
end

return {
    { "session: introduce under the cap, test, fail, relearn, done", function(t)
        local d, saved, rep = setup{ new_per_day = 2 }
        local e4_key = rep.order[1]
        t.ok(d:nextLine(), "a line to learn")
        t.eq(d.state, "play", "White moves first"); t.eq(d:mode(), "intro", "new move is introduced")
        t.eq(d:expected().move.san, "e4", "expected e4")
        t.eq(play(d, "e2e4"), "good", "e4 played")
        t.eq(d:opponentReply().move.san, "e5", "line reply")
        t.eq(d:mode(), "intro", "Nf3 introduced")
        t.eq(play(d, "g1f3"), "good", "Nf3")
        d:opponentReply()
        t.eq(d.state, "end", "cap of 2 new moves: the line stops before Bc4")
        t.eq(saved[e4_key].card.introduced, PkSrs.today(NOON), "introduction saved")

        t.ok(d:nextLine(), "introduced moves are due again today")
        t.eq(d:mode(), "test", "e4 tested")
        t.eq(play(d, "a2a3"), "wrong", "wrong answer")
        t.eq(d.state, "play", "retry")
        t.eq(play(d, "e2e4"), "good", "then the right move")
        t.eq(saved[e4_key].card.reps, 0, "e4 failed: relearn")
        t.eq(saved[e4_key].card.due, PkSrs.today(NOON), "due again today")
        d:opponentReply()
        t.eq(d:mode(), "test", "Nf3 tested"); play(d, "g1f3")
        t.eq(saved[rep.order[2]].card.reps, 1, "Nf3 passed")
        d:opponentReply()

        t.ok(d:nextLine(), "the failed move comes back")
        t.eq(d:expected().move.san, "e4", "e4 again")
        play(d, "e2e4"); d:opponentReply()
        t.eq(saved[e4_key].card.reps, 1, "relearned")
        t.eq(d:mode(), "free", "Nf3 is known and not due")
        t.eq(play(d, "g1f3"), "good", "free move")
        t.eq(saved[rep.order[2]].card.reps, 1, "free move not rescheduled")
        t.eq(d:nextLine(), nil, "nothing due, cap reached"); t.eq(d.state, "done", "session done")
        t.eq(d.reviewed, 3, "three reviews"); t.eq(d.failed, 1, "one failure")
    end },
    { "next day: stored cards are due, counts", function(t)
        local today = PkSrs.today(NOON)
        local d, _, rep = setup{ new_per_day = 2 }
        d:nextLine(); play(d, "e2e4"); d:opponentReply(); play(d, "g1f3")
        local cards = d.stored
        local d2 = setup{ rep = rep, cards = cards, now = NOON + PkSrs.DAY, new_per_day = 2 }
        local c = d2:counts()
        t.eq(c.due, 2, "both introduced moves due"); t.eq(c.new, 12, "12 new left"); t.eq(c.new_today, 2, "2 new allowed")
        t.eq(PkSrs.today(NOON + PkSrs.DAY), today + 1, "next day")
    end },
    { "known mistakes, hints and solutions", function(t)
        local d = setup()
        d:nextLine()
        play(d, "e2e4"); d:opponentReply(); play(d, "g1f3"); d:opponentReply()
        local verdict, node = play(d, "f1b5")
        t.eq(verdict, "bad", "Bb5?! is a known mistake")
        t.ok(node.comment and node.comment:find("Not our line"), "its comment")
        t.ok(not d.missed, "no penalty while learning")
        t.eq(play(d, "f1c4"), "good", "Bc4")
        -- second pass: hint on a tested move fails it
        local d2, saved, rep = setup{ cards = d.stored, rep = d.rep }
        d2:nextLine()
        t.eq(d2:mode(), "test", "e4 due")
        t.eq(d2:hint(), "e2", "hint square")
        play(d2, "e2e4")
        t.eq(saved[rep.order[1]].card.reps, 0, "hint counts as a failure")
        d2:opponentReply()
        t.eq(d2:solution(), "good", "solution plays the move")
        t.eq(saved[rep.order[2]].card.reps, 0, "solution counts as a failure")
    end },
    { "black repertoire starts with the opponent's move; changed PGN resets a card", function(t)
        local game = Chess:new()
        local rep = PkRepertoire.fromStudy(PkStudy.fromText(
            '[Event "ck"]\n[Orientation "black"]\n\n1. e4 c6 2. d4 d5 *\n'), game)
        local d = setup{ rep = rep }
        d:nextLine()
        t.eq(d.state, "reply", "White moves first")
        t.eq(d:opponentReply().move.san, "e4", "1. e4")
        t.eq(d:expected().move.san, "c6", "Black answers c6")
        local key = rep.order[1]
        local stale = { [key] = { move = "e7e5", due = 0, interval = 5, ease = 2.5, reps = 3, lapses = 0, last = 1, introduced = 0 } }
        local d2 = setup{ rep = rep, cards = stale }
        t.ok(PkSrs.isNew(d2:card(key)), "stored state for another move counts as new")
    end },
    { "progress database: cards round trip, introductions per day", function(t)
        local path = os.tmpname()
        local p = PkProgress.open(path)
        local card = PkSrs.introduce(PkSrs.new(), NOON)
        p:saveCard("r.pgn", "fen1", "e2e4", card)
        p:saveCard("r.pgn", "fen2", "d2d4", PkSrs.grade(card, true, NOON))
        p:saveCard("other.pgn", "fen1", "c2c4", card)
        p:close()
        p = PkProgress.open(path)
        local cards = p:loadCards("r.pgn")
        t.eq(cards.fen1.move, "e2e4", "move"); t.eq(cards.fen2.reps, 1, "reps")
        t.eq(type(cards.fen2.due), "number", "numbers, not int64 cdata")
        t.eq(cards.fen2.ease, card.ease + 0.05, "ease (REAL)")
        t.eq(p:introducedOn("r.pgn", PkSrs.today(NOON)), 2, "two introduced today in r.pgn")
        t.eq(p:loadCards("other.pgn").fen1.move, "c2c4", "repertoires kept apart")
        p:close()
        os.remove(path)
    end },
    { "a known card reached after a new move order is drilled through a clean line", function(t)
        local game = Chess:new()
        local rep = PkRepertoire.fromStudy(PkStudy.fromText('[Event "qg"]\n[Orientation "white"]\n\n'
            .. '1. d4 e6 (1... Nf6 2. c4 e6 3. Nc3) 2. c4 Nf6 3. Nc3 *\n'), game)
        local function sanOf(key) return rep.cards[key].san end
        t.eq(#rep.order, 4, "d4, c4 (after e6), Nc3, c4 (after Nf6)")
        local today = PkSrs.today(NOON)
        local cards = {}
        for i, key in ipairs(rep.order) do
            if i ~= 2 then -- "2. c4 after 1... e6" was just added to the PGN: new
                cards[key] = { move = rep.cards[key].uci, due = today - (sanOf(key) == "Nc3" and 5 or 1),
                               interval = 3, ease = 2.5, reps = 2, lapses = 0, last = NOON - 3 * PkSrs.DAY, introduced = today - 10 }
            end
        end
        local d = setup{ rep = rep, cards = cards, new_per_day = 0 }
        d:nextLine()
        t.eq(d.target, rep.order[3], "most overdue: Nc3")
        t.eq(d.line, rep.lines[2], "the line without the new move")
        play(d, "d2d4"); d:opponentReply(); play(d, "c2c4"); d:opponentReply()
        t.eq(d:expected().move.san, "Nc3", "the target is asked")
        t.eq(d:mode(), "test", "and tested")
        -- no clean line: the new move before the target is introduced anyway
        local only = PkRepertoire.fromStudy(PkStudy.fromText('[Event "x"]\n\n1. d4 e6 2. c4 Nf6 3. Nc3 *\n'), game)
        local c2 = {}
        for i, key in ipairs(only.order) do
            if i ~= 2 then c2[key] = { move = only.cards[key].uci, due = today - (i == 3 and 2 or 0), interval = 1, ease = 2.5,
                                       reps = 1, lapses = 0, last = NOON - PkSrs.DAY, introduced = today - 1 } end
        end
        local d2 = setup{ rep = only, cards = c2, new_per_day = 0 }
        d2:nextLine(); play(d2, "d2d4"); d2:opponentReply()
        t.eq(d2.state, "play", "not stopped by the cap before the target")
        t.eq(d2:mode(), "intro", "c4 introduced")
    end },
    { "cap of zero: nothing new; day rollover resets the count; cards from the database", function(t)
        local d = setup{ new_per_day = 0 }
        t.eq(d:nextLine(), nil, "no new card allowed, none due")
        local d2, saved, rep = setup{ new_per_day = 1, introduced_today = 1, now = NOON + 15 * 3600 }
        t.eq(d2:nextLine(), nil, "cap reached at 3 am")
        d2.clock = function() return NOON + 17 * 3600 end -- 5 am: a new day
        t.ok(d2:nextLine(), "new day: one new move allowed again")
        local path = os.tmpname()
        local p = PkProgress.open(path)
        local d3 = setup{ rep = rep, new_per_day = 1 }
        d3.save = function(key, move, card) p:saveCard(rep.name, key, move, card) end
        d3:nextLine(); play(d3, "e2e4")
        local d4 = setup{ rep = rep, cards = p:loadCards(rep.name), new_per_day = 1, introduced_today = p:introducedOn(rep.name, PkSrs.today(NOON)) }
        t.eq(d4:counts().due, 1, "introduced card due, read back from the database")
        t.eq(d4:counts().new_today, 0, "cap counted from the database")
        p:close(); os.remove(path)
    end },
    { "settings by prefix with non-ASCII file names", function(t)
        local PkDone = require("pkdone")
        local path = os.tmpname()
        local p = PkProgress.open(path)
        PkDone.setChapterDone(p, "♞ Étude.pgn", 2, true)
        PkDone.setChapterDone(p, "♞ Étude.pgn", 10, true)
        PkDone.setChapterDone(p, "♞ Étude.pgn.bak", 3, true)
        local set = PkDone.chapterDoneSet(p, "♞ Étude.pgn")
        t.ok(set[2] and set[10] and not set[1] and not set[3], "chapters 2 and 10 of the right file")
        t.eq(#p:settingKeys("rep_flip:♞"), 0, "no false matches")
        t.eq(PkDone.setChapterDone(p, "solo.pgn", 1, true, 1), true, "last chapter done marks the study done")
        -- an intro chapter without moves (1) doesn't count
        t.eq(PkDone.setChapterDone(p, "intro.pgn", 2, true, { 2, 3 }), false, "chapter 3 still to do")
        t.eq(PkDone.setChapterDone(p, "intro.pgn", 3, true, { 2, 3 }), true, "done without the intro")
        t.ok(PkDone.isDone(p, "solo.pgn"), "study done")
        p:close(); os.remove(path)
    end },
}
