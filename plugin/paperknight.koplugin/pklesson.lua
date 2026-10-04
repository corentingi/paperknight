-- Interactive lesson on a study chapter (docs/studies.md, Lichess gamebook
-- rules). Pure logic over a PkStudy cursor, no UI:
--   local l = PkLesson.new(cursor, "w", { variations_are_mistakes = true })
--   l:start()                          -- back to the chapter start (nothing played)
--   while l.state == "reply" do l:opponentReply() end   -- the view paces these
--   local verdict, info = l:onStudentMove(from, to, promotion)
--     "good"      main-line move played; then l:opponentReply() (the view paces it)
--     "end"       main-line move played and the chapter is over
--     "bad"       move exists as a variation (a known mistake): info = that node
--                 (its comment explains); position unchanged, retry
--     "sideline"  move exists as a variation in a non-gamebook chapter: retry
--     "wrong"     move not in the study: retry
-- States: play (student to move) | reply (opponent to move) | end |
--         error (the next main-line move is illegal in the PGN: l.error)
local PkLesson = {}
PkLesson.__index = PkLesson

--- `student` is "w" or "b". opts.variations_are_mistakes: true for gamebook
-- chapters (Lichess semantics); false when training an ordinary chapter.
function PkLesson.new(cursor, student, opts)
    opts = opts or {}
    local self = setmetatable({}, PkLesson)
    self.cursor = cursor
    self.student = student
    self.variations_are_mistakes = opts.variations_are_mistakes == true
    self.mistakes = 0
    self.used_help = false
    self.state = "new" -- new | play | reply | end
    return self
end

function PkLesson:_studentToMove()
    return self.cursor.game.turn() == self.student
end

function PkLesson:_updateState()
    local next_main = self.cursor.node.children[1]
    if not next_main then
        self.state = "end"
    elseif not self.cursor:resolve(next_main) then
        self.state, self.error = "error", next_main.error
    elseif self:_studentToMove() then
        self.state = "play"
    else
        self.state = "reply"
    end
    return self.state
end

--- Goes back to the chapter start. Nothing is played: if the opponent moves
-- first (state "reply"), the caller paces opponentReply() so the chapter
-- intro can be read first.
function PkLesson:start()
    self.cursor:toStart()
    self.mistakes, self.used_help, self.error = 0, false, nil
    return self:_updateState()
end

function PkLesson:isOver()
    return self.state == "end"
end

--- Expected main-line node at the student's turn (resolved), or nil.
function PkLesson:expected()
    if self.state ~= "play" then return nil end
    local child = self.cursor.node.children[1]
    if child and self.cursor:resolve(child) then return child end
    return nil
end

--- Judges a move the student wants to play (not yet applied anywhere).
function PkLesson:onStudentMove(from, to, promotion)
    assert(self.state == "play", "not the student's turn")
    local child, index = self.cursor:childForMove(from, to, promotion)
    if child and index == 1 then
        self.cursor:forward(1)
        if self:_updateState() == "end" then return "end", child end
        return "good", child
    end
    if child then
        if self.variations_are_mistakes then
            self.mistakes = self.mistakes + 1
            return "bad", child
        end
        return "sideline", child
    end
    self.mistakes = self.mistakes + 1
    return "wrong"
end

--- Plays the opponent's main-line reply (after a "good" verdict). Returns the
-- node played, or nil. Several opponent moves in a row are played one per call.
function PkLesson:opponentReply()
    if self.state ~= "reply" then return nil end
    local node = self.cursor:forward(1) -- resolvable: checked by _updateState
    self:_updateState()
    return node
end

--- Square of the piece to move (a hint). Marks help as used.
function PkLesson:hint()
    local child = self:expected()
    if not child then return nil end
    self.used_help = true
    return child.move.from
end

--- Plays the expected move for the student. Returns verdict like onStudentMove.
function PkLesson:solution()
    local child = self:expected()
    if not child then return nil end
    self.used_help = true
    local m = child.move
    local verdict = self:onStudentMove(m.from, m.to, m.promotion)
    return verdict, child
end

return PkLesson
