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

return PkDone
