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

    -- override undo: call base, push onto redo_stack
    local _undo = instance.undo
    instance.undo = function()
        local move = _undo(instance)    -- call the base‐class undo

        if move then
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
        if move and not redoing then instance.redo_stack = {} end
        return move
    end
    for _, name in ipairs({ "reset", "load", "load_pgn", "clear" }) do
        local base = instance[name]
        if base then
            instance[name] = function(...)
                instance.redo_stack = {}
                return base(...)
            end
        end
    end

    -- redo: pop from redo_stack and re-apply; returns the move played (nil if
    -- none, or if it no longer applies: the rest of the history is dropped)
    instance.redo = function()
        local entry = table.remove(instance.redo_stack)
        if not entry then return nil end
        redoing = true
        local move = base_move(entry)
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
