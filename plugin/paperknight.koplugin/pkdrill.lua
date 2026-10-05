-- Repertoire drill session (ADR-0012). Pure logic over PkRepertoire, PkSrs
-- and a PkStudy cursor, no UI:
--   local d = PkDrill.new{ rep = rep, game = game, cards = stored_cards,
--                          save = function(key, move, card) end,
--                          new_per_day = 10, introduced_today = n }
--   d:nextLine()   -- picks a line (most overdue card first, then new cards),
--                  -- or returns nil when nothing is due and the cap is reached
--   while d.state == "reply" do d:opponentReply() end   -- the view paces these
--   d:mode()       -- "intro" (new move: shown, then played), "test" (due card),
--                  -- "free" (known, not due: wrong answers still count)
--   local verdict, node = d:onUserMove(from, to, promotion)
--     "good"  right move, played;  "end" right move and the line is over
--     "wrong" not the move (retry);  "bad" a known mistake in the PGN (node =
--     that move, its comment explains; retry)
-- States: idle | play | reply | end | done
local PkRepertoire = require("pkrepertoire")
local PkSrs = require("pksrs")

local PkDrill = {}
PkDrill.__index = PkDrill

-- True if `node` of `line` is a move of the user (the side drilled).
local function isUserNode(line, node)
    return (node.parent.fen:match("^%S+%s+([wb])") or "w") == line.student
end

PkDrill.NEW_PER_DAY = 10

function PkDrill.new(o)
    local self = setmetatable({}, PkDrill)
    self.rep = assert(o.rep)
    self.game = assert(o.game)
    self.stored = o.cards or {}
    self.save = o.save or function() end
    self.clock = o.clock or os.time
    self.new_per_day = o.new_per_day or PkDrill.NEW_PER_DAY
    self.introduced_today = o.introduced_today or 0
    self.today = PkSrs.today(self.clock())
    self.order_index = {}
    for i, key in ipairs(self.rep.order) do self.order_index[key] = i end
    self.state = "idle"
    self.reviewed, self.failed = 0, 0
    return self
end

--- Scheduling state of card `key` (a stored state for another move, after
-- the PGN changed, counts as a new card).
function PkDrill:card(key)
    local stored = self.stored[key]
    local expected = self.rep.cards[key]
    if stored and expected and stored.move == expected.uci then return stored end
    return PkSrs.new()
end

local function before(self, a, b)
    local ca, cb = self:card(a), self:card(b)
    if ca.due ~= cb.due then return ca.due < cb.due end
    -- same day: cards reviewed longest ago first (a card just failed waits)
    if (ca.last or 0) ~= (cb.last or 0) then return (ca.last or 0) < (cb.last or 0) end
    return self.order_index[a] < self.order_index[b]
end

--- Counts for display: cards due today, new cards still allowed today,
-- new cards left in the repertoire.
function PkDrill:counts()
    local due, new = 0, 0
    for _, key in ipairs(self.rep.order) do
        local c = self:card(key)
        if PkSrs.isNew(c) then new = new + 1 elseif PkSrs.isDue(c, self.today) then due = due + 1 end
    end
    return { due = due, new = new, new_today = math.max(0, math.min(new, self.new_per_day - self.introduced_today)) }
end

-- A line containing card `key`: preferably one with no new card before it
-- (after PGN edits, a new move order can reach a known position).
function PkDrill:_lineFor(key)
    local first
    for _, line in ipairs(self.rep.lines) do
        local idx = PkRepertoire.cardIndex(line, key)
        if idx then
            first = first or line
            local clean = true
            for k = 1, idx - 1 do
                local node = line.nodes[k]
                if isUserNode(line, node) and PkSrs.isNew(self:card(self:_keyOf(node))) then
                    clean = false
                    break
                end
            end
            if clean then return line, idx end
        end
    end
    return first, first and PkRepertoire.cardIndex(first, key)
end



--- Chooses the next line and goes to its start. Returns the line, or nil
-- (state "done") when no card is due and no new card is allowed today.
function PkDrill:nextLine()
    local today = PkSrs.today(self.clock())
    if today ~= self.today then -- the session went past 4 am: a new day
        self.today, self.introduced_today = today, 0
    end
    local target
    for _, key in ipairs(self.rep.order) do
        local c = self:card(key)
        if PkSrs.isDue(c, self.today) and (not target or before(self, key, target)) then target = key end
    end
    if not target and self.introduced_today < self.new_per_day then
        for _, key in ipairs(self.rep.order) do
            if PkSrs.isNew(self:card(key)) then target = key; break end
        end
    end
    if not target then
        self.state, self.line, self.target = "done", nil, nil
        return nil
    end
    self.line, self.target_index = self:_lineFor(target)
    self.target = target
    self.cursor = assert(self.rep.study:cursor(self.line.chapter, self.game))
    self.index = 0 -- nodes played in the line
    self:_updateState()
    return self.line
end

-- The next node of the line, or nil.
function PkDrill:_next()
    return self.line and self.line.nodes[self.index + 1]
end

function PkDrill:_keyOf(node)
    return PkRepertoire.normalizeFen(node.parent.fen)
end

function PkDrill:_updateState()
    local node = self:_next()
    if not node then
        self.state = "end"
    elseif isUserNode(self.line, node) then
        -- past today's cap, a new card after the target ends the line (one
        -- before it is introduced anyway, or the target would never be asked)
        if PkSrs.isNew(self:card(self:_keyOf(node))) and self.introduced_today >= self.new_per_day
            and self.index + 1 > self.target_index then
            self.state = "end"
        else
            self.state = "play"
            self.missed, self.used_help = false, false
        end
    else
        self.state = "reply"
    end
    return self.state
end

--- Mode of the move expected now (state "play").
function PkDrill:mode()
    if self.state ~= "play" then return nil end
    local c = self:card(self:_keyOf(self:_next()))
    if PkSrs.isNew(c) then return "intro" end
    if PkSrs.isDue(c, self.today) then return "test" end
    return "free"
end

--- Expected node at the user's turn, or nil.
function PkDrill:expected()
    return self.state == "play" and self:_next() or nil
end

function PkDrill:_advance()
    local node = self:_next()
    self.index = self.index + 1
    self.cursor:jump(node)
    return node
end

function PkDrill:_store(key, card)
    self.stored[key] = card
    card.move = self.rep.cards[key].uci
    self.save(key, card.move, card)
end

-- Records the answer to the current card once, when the right move is played.
function PkDrill:_record(node)
    local key = self:_keyOf(node)
    local c = self:card(key)
    local now = self.clock()
    local mode = self:mode()
    if mode == "intro" then
        self:_store(key, PkSrs.introduce(c, now))
        self.introduced_today = self.introduced_today + 1
    elseif mode == "test" or self.missed or self.used_help then
        local good = not (self.missed or self.used_help)
        self:_store(key, PkSrs.grade(c, good, now))
        self.reviewed = self.reviewed + 1
        if not good then self.failed = self.failed + 1 end
    end
end

--- Judges a move at the user's turn.
function PkDrill:onUserMove(from, to, promotion)
    assert(self.state == "play", "not the user's turn")
    local node = self:_next()
    local m = node.move
    if m.from == from and m.to == to and (m.promotion or nil) == (promotion or nil) then
        self:_record(node)
        self:_advance()
        if self:_updateState() == "end" then return "end", node end
        return "good", node
    end
    -- a wrong answer counts against a known card (not while learning it)
    if self:mode() ~= "intro" then self.missed = true end
    local sibling = self.cursor:childForMove(from, to, promotion)
    if sibling then return "bad", sibling end
    return "wrong"
end

--- Plays the opponent's move of the line. Returns the node, or nil.
function PkDrill:opponentReply()
    if self.state ~= "reply" then return nil end
    local node = self:_advance()
    self:_updateState()
    return node
end

--- Square of the piece to move. Counts as help (the card is failed).
function PkDrill:hint()
    local node = self:expected()
    if not node then return nil end
    if self:mode() ~= "intro" then self.used_help = true end
    return node.move.from
end

--- Plays the expected move for the user (counts as help).
function PkDrill:solution()
    local node = self:expected()
    if not node then return nil end
    if self:mode() ~= "intro" then self.used_help = true end
    local m = node.move
    return self:onUserMove(m.from, m.to, m.promotion)
end

return PkDrill
