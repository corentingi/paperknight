-- Study state moved on rename (PkDone.rename / applyRenames).
local PkDone = require("pkdone")
local PkProgress = require("pkprogress")

local function db()
    local path = os.tmpname()
    os.remove(path)
    local p = PkProgress.open(path)
    return p, function() p:close(); os.remove(path) end
end

local function seed(p, file)
    PkDone.set(p, file, true)
    p:setSetting("study_last:" .. file, 3)
    p:setSetting("chapter_done:" .. file .. "#1", "1")
    p:setSetting("chapter_done:" .. file .. "#12", "1")
    p:setSetting("study_flip:" .. file .. "#2", "1")
end

return {
    { "marks, Continue, chapter marks and flips follow the new name", function(t)
        local p, close = db()
        seed(p, "Opening - Caro-Kann Défense 🏰.pgn")
        seed(p, "Opening - Caro-Kann Défense 🏰.pgn.bak") -- a longer name with the same prefix
        local v = PkDone.version
        t.ok(PkDone.rename(p, "Opening - Caro-Kann Défense 🏰.pgn", "Caro-Kann Défense 🏰.pgn"), "moved")
        t.ok(PkDone.version > v, "lists told")
        local new = "Caro-Kann Défense 🏰.pgn"
        t.ok(PkDone.isDone(p, new), "done")
        t.eq(PkDone.lastChapter(p, new), 3, "continue")
        local set = PkDone.chapterDoneSet(p, new)
        t.ok(set[1] and set[12], "chapter marks")
        t.eq(p:getSetting("study_flip:" .. new .. "#2"), "1", "flip")
        t.eq(#p:settingKeys("study_done:Opening - Caro-Kann Défense 🏰.pgn"), 1, "only the .bak study left under the old prefix")
        t.ok(PkDone.isDone(p, "Opening - Caro-Kann Défense 🏰.pgn.bak"), "other study untouched")
        t.eq(p:getSetting("study_last:Opening - Caro-Kann Défense 🏰.pgn"), nil, "old keys removed")
        close()
    end },
    { "never overwrites, and a second run does nothing", function(t)
        local p, close = db()
        seed(p, "a.pgn")
        PkDone.set(p, "b.pgn", true)
        t.ok(not PkDone.rename(p, "a.pgn", "b.pgn"), "target has state: kept as is")
        t.eq(PkDone.lastChapter(p, "a.pgn"), 3, "source kept")
        local text = "a.pgn\tc.pgn\nmissing.pgn\td.pgn\r\nbad line\n"
        t.eq(PkDone.applyRenames(p, text), 1, "one study moved")
        t.eq(PkDone.applyRenames(p, text), 0, "idempotent")
        t.ok(PkDone.isDone(p, "c.pgn"), "moved by the file")
        close()
    end },
}
