-- The UCI line parser of the engine (pkuci.lua): what Stockfish prints,
-- turned into the engine's state and events.
if not PK_KOREADER_ENV then
    return { { "SKIPPED: run via `make test-lua` (needs KOReader env)", function(t) t.ok(false, "no KOReader env") end } }
end
local parse = require("pkuci")._parseLine

-- a state as UCIEngine:uci() makes it, with an engine recording its events
local function session()
    local events = {}
    local engine = { _trigger = function(_, name, ...) events[#events + 1] = { name, ... } end }
    local state = { options = {}, uciok = false, readyok = false, _engine = engine }
    local function feed(...)
        for _, line in ipairs({ ... }) do parse(line, state) end
    end
    local function count(name)
        local n = 0
        for _, e in ipairs(events) do if e[1] == name then n = n + 1 end end
        return n
    end
    return state, feed, events, count
end

return {
    { "the handshake: the banner names the engine, uciok once", function(t)
        local state, feed, _, count = session()
        feed("Stockfish 18 by the Stockfish developers (see AUTHORS file)")
        t.eq(state.id_name, "Stockfish 18 by the Stockfish developers (see AUTHORS file)", "a name from the banner")
        t.eq(count("uciok"), 0, "the banner is not uciok")
        feed("id name Stockfish 18", "id author the Stockfish developers (see AUTHORS file)", "uciok")
        t.eq(state.id_name, "Stockfish 18", "id name wins")
        t.eq(state.id_author, "the Stockfish developers (see AUTHORS file)")
        t.ok(state.uciok); t.eq(count("uciok"), 1, "uciok triggered once")
    end },
    { "options: names with spaces, types, defaults and bounds", function(t)
        local state, feed = session()
        feed("option name Skill Level type spin default 20 min 0 max 20",
            "option name UCI_LimitStrength type check default false",
            "option name UCI_Elo type spin default 1320 min 1320 max 3190",
            "option name SyzygyPath type string default <empty>",
            "option name Clear Hash type button")
        local skill = state.options["Skill Level"]
        t.ok(skill, "a name of two words")
        t.eq(skill.type, "spin"); t.eq(skill.default, "20"); t.eq(skill.min, "0"); t.eq(skill.max, "20")
        t.eq(skill.value, "20", "the value starts at the default")
        t.eq(state.options.UCI_LimitStrength.default, "false")
        t.eq(state.options.UCI_Elo.min, "1320"); t.eq(state.options.UCI_Elo.max, "3190")
        t.eq(state.options.SyzygyPath.default, "<empty>")
        t.eq(state.options["Clear Hash"].type, "button"); t.eq(state.options["Clear Hash"].default, nil)
    end },
    { "bestmove, with or without ponder", function(t)
        local state, feed, events = session()
        feed("bestmove e2e4 ponder e7e5")
        t.eq(state.bestmove, "e2e4"); t.eq(state.ponder, "e7e5")
        local last = events[#events]
        t.eq(last[1], "bestmove"); t.eq(last[2], "e2e4"); t.eq(last[3], "e7e5")
        feed("bestmove g1f3")
        t.eq(state.bestmove, "g1f3"); t.eq(state.ponder, nil, "no ponder")
        feed("bestmove e7e8q ponder")
        t.eq(state.bestmove, "e7e8q", "a promotion"); t.eq(state.ponder, nil, "ponder without a move")
        feed("bestmove (none)")
        t.eq(state.bestmove, "(none)", "no legal move: as Stockfish says it")
    end },
    { "readyok, info lines passed on, line ends and noise", function(t)
        local state, feed, events, count = session()
        feed("readyok\r")
        t.ok(state.readyok, "a CRLF line"); t.eq(count("readyok"), 1)
        feed("info depth 12 seldepth 18 multipv 1 score cp 31 nodes 120000 pv e2e4 e7e5")
        local last = events[#events]
        t.eq(last[1], "info"); t.ok(last[2]:find("score cp 31", 1, true), "the whole line")
        t.eq(state.info, nil, "info lines are not kept")
        local before = #events
        feed("", "   ", "something unknown", "info string NNUE evaluation using nn.nnue")
        t.eq(#events, before + 1, "only the info line is an event")
        feed("kill")
        t.eq(state.to_uciok, -1, "the child's exec failure ends the wait")
    end },
}
