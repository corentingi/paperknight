-- "Done" marks on studies (a ✓ in the Studies list), stored as settings in
-- progress.sqlite: key "study_done:<file name>". `version` changes on every
-- study mark change (the studies lists redraw), `chapter_version` on every
-- chapter state change (done marks, last chapter: the chapter list redraws),
-- so that opening a chapter does not rebuild the studies lists.
local PkDone = { version = 0, chapter_version = 0, MARK = "✓" }

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

--- Marks chapter `i` done or not. With `counted` (a list of the chapter
-- indexes that count, e.g. those with moves; or a number n for 1..n),
-- marking the last remaining one also marks the whole study done; returns
-- true then.
function PkDone.setChapterDone(progress, file, i, done, counted)
    progress:setSetting(chapterKey(file, i), done and "1" or nil)
    PkDone.chapter_version = PkDone.chapter_version + 1
    if done and counted then
        if type(counted) == "number" then
            local list = {}
            for c = 1, counted do list[c] = c end
            counted = list
        end
        local set = PkDone.chapterDoneSet(progress, file)
        for _, c in ipairs(counted) do
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
        PkDone.chapter_version = PkDone.chapter_version + 1
    end
end

--- Right-hand text of a chapter in lists: "lesson", "✓", "lesson ✓" or nil.
function PkDone.chapterInfo(gamebook, done)
    if gamebook and done then return "lesson " .. PkDone.MARK end
    if done then return PkDone.MARK end
    return gamebook and "lesson" or nil
end

----------------------------------------------------------------------------
-- Renames: a study file renamed (e.g. a reorganised collection) keeps its
-- marks, flips and "Continue" when the old -> new names are known.
----------------------------------------------------------------------------

local EXACT = { "study_done:", "study_last:" }
local PER_CHAPTER = { "chapter_done:", "study_flip:" } -- "<prefix><file>#<n>"

--- Moves the state of study file `old` to `new` (file names). Does nothing
-- if `new` already has state (never overwrites). Returns true if moved.
function PkDone.rename(progress, old, new)
    if old == new then return false end
    local function keysOf(file)
        local keys = {}
        for _, p in ipairs(EXACT) do
            if progress:getSetting(p .. file) ~= nil then keys[#keys + 1] = p .. file end
        end
        for _, p in ipairs(PER_CHAPTER) do
            for _, k in ipairs(progress:settingKeys(p .. file .. "#")) do keys[#keys + 1] = k end
        end
        return keys
    end
    local old_keys = keysOf(old)
    if #old_keys == 0 or #keysOf(new) > 0 then return false end
    progress.conn:exec("BEGIN")
    local ok, err = pcall(function()
        for _, k in ipairs(old_keys) do
            local prefix = k:sub(1, k:find(":", 1, true))
            local rest = k:sub(#prefix + #old + 1) -- "" or "#<n>"
            progress:setSetting(prefix .. new .. rest, progress:getSetting(k))
            progress:setSetting(k, nil)
        end
    end)
    progress.conn:exec(ok and "COMMIT" or "ROLLBACK")
    if not ok then error(err, 0) end
    PkDone.version = PkDone.version + 1
    return true
end

--- Applies a renames file: one "old name<TAB>new name" per line (file
-- names, not paths). Returns the number of studies whose state moved.
function PkDone.applyRenames(progress, text)
    local n = 0
    for line in (text or ""):gmatch("[^\r\n]+") do
        local old, new = line:match("^([^\t]+)\t([^\t]+)$")
        if old and PkDone.rename(progress, old, new) then n = n + 1 end
    end
    return n
end

return PkDone
