local _Chess = require("pkchesslib/src/chess")

local Chess = {}
Chess.__index = Chess

setmetatable(Chess, {
                 __index = function(_, key)
                     return _Chess[key]
                 end,
})

function Chess:new()
    local instance = _Chess()
    instance.human_player = {
        [instance.WHITE] = true,
        [instance.BLACK] = true,
    }
    instance.redo_stack = {}
    instance.set_human = function(color, isHuman)
        assert(color == instance.WHITE or color == instance.BLACK,
               "Invalid color: " .. tostring(color))
        instance.human_player[color] = isHuman
    end

    instance.is_human = function(color)
        assert(color == instance.WHITE or color == instance.BLACK,
               "Invalid color: " .. tostring(color))
        return instance.human_player[color]
    end

    -- The moves played, kept as they are played and undone: the engine's
    -- history() undoes and replays the whole game, generating the legal
    -- moves at each ply (20 ms at ply 270 on a desktop, a second or more on
    -- the Kindle), and the screens ask for it at every move.
    local record = {}
    local base_history = instance.history
    instance._replayed_history = base_history -- (specs: the engine's own answer)
    local function rebuild() record = base_history({ verbose = true }) end

    --- The moves so far: their SAN, or with `{ verbose = true }` the move
    -- tables (from, to, san, piece, flags, promotion…); a new list each call.
    instance.history = function(options)
        local out = {}
        local verbose = options and options.verbose
        for i, m in ipairs(record) do
            if verbose then
                local copy = {}
                for k, v in pairs(m) do copy[k] = v end
                out[i] = copy -- (the caller's to change)
            else
                out[i] = m.san
            end
        end
        return out
    end

    -- override undo: call base, push onto redo_stack
    local _undo = instance.undo
    instance.undo = function()
        local move = _undo(instance)    -- call the base‐class undo

        if move then
            record[#record] = nil
            table.insert(instance.redo_stack, move)
        end
        return move
    end

    -- the redo history only lasts while the game is replayed: a new move,
    -- a reset or a loaded position ends it
    local redoing = false
    local base_move = instance.move
    instance.move = function(...)
        local move = base_move(...)
        if move then
            record[#record + 1] = move
            if not redoing then instance.redo_stack = {} end
        end
        return move
    end
    for _, name in ipairs({ "reset", "load", "load_pgn", "clear" }) do
        local base = instance[name]
        if base then
            instance[name] = function(...)
                instance.redo_stack = {}
                local result = base(...)
                -- a FEN that does not load changes nothing; a PGN brings its moves
                if name == "load_pgn" then rebuild()
                elseif name ~= "load" or result then record = {} end
                return result
            end
        end
    end

    -- redo: pop from redo_stack and re-apply; returns the move played (nil if
    -- none, or if it no longer applies: the rest of the history is dropped)
    instance.redo = function()
        local entry = table.remove(instance.redo_stack)
        if not entry then return nil end
        redoing = true
        local move = instance.move(entry)
        redoing = false
        if not move then instance.redo_stack = {} end
        return move
    end

    instance.redo_history = function()
        return instance.redo_stack
    end

    setmetatable(instance, Chess)

    return instance
end

return Chess
