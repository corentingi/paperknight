-- The daily copy of the progress file and its restore (pkprogress.lua).
local PkProgress = require("pkprogress")

local function tmpdb()
    local path = os.tmpname()
    os.remove(path)
    return path, function()
        for _, suffix in ipairs({ "", "-journal", ".bak", ".bak.part", ".broken", ".broken-journal" }) do
            os.remove(path .. suffix)
        end
    end
end

local function touch(path, ts)
    require("libs/libkoreader-lfs").touch(path, ts, ts)
end

return {
    { "a copy once a day, from a file that passes its check", function(t)
        local path, done = tmpdb()
        local p = PkProgress.open(path)
        p:setSetting("theme", "fork")
        t.eq(PkProgress.backupTime(path), nil, "no copy yet")
        t.ok(p:backupIfDue(), "the first copy")
        local made = PkProgress.backupTime(path)
        t.ok(made, "copied")
        t.ok(not p:backupIfDue(made + 3600), "not again within the day")
        touch(PkProgress.backupPath(path), made - 24 * 3600)
        p:setSetting("theme", "pin")
        t.ok(p:backupIfDue(), "a day later: a new copy")
        local copy = PkProgress.open(PkProgress.backupPath(path))
        t.eq(copy:getSetting("theme"), "pin", "the copy has the data"); t.eq(copy:schemaVersion(), p:schemaVersion())
        copy:close()
        -- a file failing its check is not copied over the good copy
        p.healthy = function() return false end
        touch(PkProgress.backupPath(path), made - 24 * 3600)
        t.ok(not p:backupIfDue(), "no copy of a damaged file")
        p:close()
        copy = PkProgress.open(PkProgress.backupPath(path))
        t.eq(copy:getSetting("theme"), "pin", "the good copy kept")
        copy:close()
        done()
    end },
    { "a damaged file is replaced by its copy, and kept aside", function(t)
        local path, done = tmpdb()
        local p = PkProgress.open(path)
        p:record{ puzzle_id = "A", puzzle_rating = 1500, success = true, solved = true, mistakes = 0,
                  used_help = false, ts = 1000 }
        local rating = p:rating()
        p:backup()
        p:close()
        local f = io.open(path, "wb"); f:write(("not a database "):rep(400)); f:close()
        t.ok(not pcall(PkProgress.open, path), "the damaged file cannot be opened")
        PkProgress.restoreBackup(path)
        p = PkProgress.open(path)
        t.eq(p:rating(), rating, "the progress is back"); t.eq(p:attemptCount(), 1)
        p:close()
        local broken = io.open(path .. ".broken", "rb")
        t.ok(broken and broken:read("*a"):find("not a database", 1, true), "the damaged file kept aside")
        if broken then broken:close() end
        done()
        t.ok(not pcall(PkProgress.restoreBackup, path), "no copy: an error")
    end },
    { "the shared handle makes the day's copy", function(t)
        local path, done = tmpdb()
        local default = PkProgress.defaultPath
        PkProgress.closeShared()
        PkProgress.defaultPath = function() return path end
        local ok, err = pcall(function()
            local p = PkProgress.open(path); p:setSetting("x", "1"); p:close()
            t.ok(not PkProgress.backupTime(path))
            PkProgress.readSetting("x")
            t.ok(PkProgress.backupTime(path), "copied when the app opens the file")
            PkProgress.closeShared()
            PkProgress.writeSetting("y", "2") -- the next session: the copy is recent, not made again
            PkProgress.restoreBackup()
            t.eq(PkProgress.readSetting("x"), "1", "restored: the copy of the first opening of the day")
            t.eq(PkProgress.readSetting("y"), nil, "what came after the copy is lost")
        end)
        PkProgress.closeShared()
        PkProgress.defaultPath = default
        done()
        if not ok then error(err, 0) end
    end },
}
