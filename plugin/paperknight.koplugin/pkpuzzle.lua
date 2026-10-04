-- Puzzle session: judges the solver's moves against a puzzle line.
-- Pure logic on top of the rules engine, no UI (ADR-0009). Semantics follow
-- docs/pack-format.md "Solving rules".
--
-- Usage:
--   local s = PkPuzzle.new(puzzle_row, game)   -- game: Chess:new()
--   local setup = s:start()                    -- opponent's first move (applied)
--   -- after the user's move has been applied to `game`:
--   local verdict, reply = s:onUserMove(move)  -- "correct"|"solved"|"wrong"
local PkPuzzle = {}
PkPuzzle.__index = PkPuzzle

local function splitMoves(moves)
    if type(moves) == "table" then return moves end
    local out = {}
    for uci in tostring(moves):gmatch("%S+") do out[#out + 1] = uci end
    return out
end

local function uciOf(move)
    return move.from .. move.to .. (move.promotion or "")
end
PkPuzzle.uciOf = uciOf

local function moveFromUci(uci)
    return {
        from = uci:sub(1, 2),
        to = uci:sub(3, 4),
        promotion = (#uci == 5) and uci:sub(5, 5) or nil,
    }
end

--- puzzle: { id, fen, moves (string or array), solver = "w"|"b", rating, ... }
function PkPuzzle.new(puzzle, game)
    local self = setmetatable({}, PkPuzzle)
    self.puzzle = puzzle
    self.game = game
    self.moves = splitMoves(puzzle.moves)
    self.index = 1        -- index in self.moves of the next move to be played
    self.mistakes = 0
    self.used_help = false
    self.state = "new"    -- new | playing | solved | failed
    return self
end

-- Plays self.moves[self.index] on the board (opponent move or revealed solution).
function PkPuzzle:_playNext()
    local uci = self.moves[self.index]
    local move = uci and self.game.move(moveFromUci(uci))
    if not move then
        error(("puzzle %s: cannot play move %d (%s)"):format(
            tostring(self.puzzle.id), self.index, tostring(uci)))
    end
    self.index = self.index + 1
    return move
end

--- Loads the position and plays the opponent's setup move.
-- @return the setup move object
function PkPuzzle:start()
    assert(self.game.load(self.puzzle.fen), "invalid FEN for puzzle " .. tostring(self.puzzle.id))
    self.index, self.mistakes, self.used_help = 1, 0, false
    local setup = self:_playNext()
    self.state = "playing"
    return setup
end

function PkPuzzle:solverColor()
    return self.puzzle.solver
end

function PkPuzzle:isOver()
    return self.state == "solved" or self.state == "failed"
end

--- UCI of the move the solver is expected to play next (nil when over).
function PkPuzzle:expected()
    if self.state ~= "playing" then return nil end
    return self.moves[self.index]
end

--- Judges a solver move that has already been applied to the game.
-- A wrong move is taken back. Any checkmating move is accepted.
-- @return verdict ("correct", "solved" or "wrong"), and the opponent's reply
--         move object when verdict is "correct".
function PkPuzzle:onUserMove(move)
    assert(self.state == "playing", "puzzle is not in progress")
    local expected = self.moves[self.index]
    if uciOf(move) ~= expected and not self.game.in_checkmate() then
        self.game.undo()
        self.mistakes = self.mistakes + 1
        return "wrong"
    end
    self.index = self.index + 1
    if self.index > #self.moves or self.game.in_checkmate() then
        self.state = "solved"
        return "solved"
    end
    local reply = self:_playNext()
    return "correct", reply
end

--- Square of the piece that should move next (a hint). Marks help as used.
function PkPuzzle:hint()
    local expected = self:expected()
    if not expected then return nil end
    self.used_help = true
    return expected:sub(1, 2)
end

--- Plays the rest of the line (solver and opponent moves) and ends the puzzle.
-- @return list of move objects played
function PkPuzzle:revealSolution()
    local played = {}
    if self.state ~= "playing" then return played end
    self.used_help = true
    while self.index <= #self.moves do
        played[#played + 1] = self:_playNext()
    end
    self.state = "failed"
    return played
end

--- True when the attempt counts as a success for rating purposes (ADR-0010).
function PkPuzzle:isCleanSolve()
    return self.state == "solved" and self.mistakes == 0 and not self.used_help
end

return PkPuzzle
