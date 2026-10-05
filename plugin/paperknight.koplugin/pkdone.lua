-- "Done" marks on studies (a ✓ in the Studies list), stored as settings in
-- progress.sqlite: key "study_done:<file name>". `version` changes on every
-- toggle so open lists know to redraw.
local PkDone = { version = 0, MARK = "✓" }

local function key(file) return "study_done:" .. file end

--- File name part of a study path (the key ignores the folder, like flips).
function PkDone.fileOf(path)
    return path and path:match("([^/]+)$") or nil
end

function PkDone.isDone(progress, file)
    return progress ~= nil and file ~= nil and progress:getSetting(key(file)) == "1"
end

--- Set of done file names.
function PkDone.doneSet(progress)
    local set = {}
    if progress then
        for _, k in ipairs(progress:settingKeys("study_done:")) do set[k:sub(#"study_done:" + 1)] = true end
    end
    return set
end

function PkDone.set(progress, file, done)
    progress:setSetting(key(file), done and "1" or nil)
    PkDone.version = PkDone.version + 1
end

----------------------------------------------------------------------------
-- Chapters: "chapter_done:<file>#<n>", and the last chapter opened
-- ("study_last:<file>", for "Continue").
----------------------------------------------------------------------------

local function chapterKey(file, i) return "chapter_done:" .. file .. "#" .. i end

--- Set of done chapter indexes of a study file.
function PkDone.chapterDoneSet(progress, file)
    local set = {}
    if progress and file then
        local prefix = "chapter_done:" .. file .. "#"
        for _, k in ipairs(progress:settingKeys(prefix)) do
            local i = tonumber(k:sub(#prefix + 1))
            if i then set[i] = true end
        end
    end
    return set
end

function PkDone.isChapterDone(progress, file, i)
    return progress ~= nil and file ~= nil and progress:getSetting(chapterKey(file, i)) == "1"
end

--- Marks chapter `i` done or not. With `n_chapters`, marking the last
-- remaining chapter also marks the whole study done; returns true then.
function PkDone.setChapterDone(progress, file, i, done, n_chapters)
    progress:setSetting(chapterKey(file, i), done and "1" or nil)
    PkDone.version = PkDone.version + 1
    if done and n_chapters then
        local set = PkDone.chapterDoneSet(progress, file)
        for c = 1, n_chapters do
            if not set[c] then return false end
        end
        if not PkDone.isDone(progress, file) then
            PkDone.set(progress, file, true)
            return true
        end
    end
    return false
end

function PkDone.lastChapter(progress, file)
    return progress and file and tonumber(progress:getSetting("study_last:" .. file)) or nil
end

function PkDone.setLastChapter(progress, file, i)
    if progress:getSetting("study_last:" .. file) ~= tostring(i) then
        progress:setSetting("study_last:" .. file, i)
        PkDone.version = PkDone.version + 1
    end
end

--- Right-hand text of a chapter in lists: "lesson", "✓", "lesson ✓" or nil.
function PkDone.chapterInfo(gamebook, done)
    if gamebook and done then return "lesson " .. PkDone.MARK end
    if done then return PkDone.MARK end
    return gamebook and "lesson" or nil
end

return PkDone
