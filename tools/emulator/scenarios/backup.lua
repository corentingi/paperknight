-- The daily copy of the progress file (pkprogress.lua): shown in the
-- settings, restored from there, and offered when the file is damaged.
local UIManager = require("ui/uimanager")

return function(h)
    local PkNav = require("pknav")
    local PkProgress = require("pkprogress")
    local pk = h.ui.paperknight
    local function top() return UIManager._window_stack[#UIManager._window_stack].widget end
    local function menuItem(menu, text)
        for _, w in ipairs(menu.item_group) do
            if w.text and w.text:find(text, 1, true) then return w end
        end
    end
    local path = PkProgress.defaultPath()

    -- 1. The copy: made when the app first opens the file that day.
    PkProgress.closeShared()
    os.remove(PkProgress.backupPath(path))
    PkProgress.writeSetting("backup.test", "before")
    h.check(PkProgress.backupTime(path), "a copy made on opening")
    PkProgress.shared():backup() -- now holding backup.test
    PkProgress.writeSetting("backup.test", "after")

    -- 2. The settings show it and restore it.
    PkNav.showSettings()
    h.settle()
    local settings = top()
    local item = menuItem(settings, "Restore progress from its copy…")
    h.check(item and item.mandatory == os.date("%Y-%m-%d", PkProgress.backupTime(path)), "the copy's day shown")
    h.tapWidget(item)
    h.settle()
    h.check(top().text and top().text:find("Put back the copy of your progress made on", 1, true),
        "asked first: " .. tostring(top().text))
    UIManager:close(top()) -- cancelled
    h.settle()
    h.check(PkProgress.readSetting("backup.test") == "after", "cancelled: nothing changed")
    h.tapWidget(menuItem(settings, "Restore progress from its copy…"))
    h.settle()
    h.tapWidget(h.findButton(top(), "Restore"))
    h.settle()
    h.check(top().text and top().text:find("Your progress is restored.", 1, true), "restored: " .. tostring(top().text))
    h.check(PkProgress.readSetting("backup.test") == "before", "the copy's data back")
    UIManager:close(top())
    h.settle()
    PkNav.home()
    h.settle()

    -- 3. A damaged file: Puzzles offers the copy, then opens.
    PkProgress.closeShared()
    local f = assert(io.open(path, "wb"))
    f:write(("damaged "):rep(500))
    f:close()
    h.check(pk:startPuzzles() == nil, "puzzles not opened on a damaged file")
    h.settle()
    h.check(top().text and top().text:find("Your progress file cannot be opened.", 1, true)
        and top().text:find("Put back the copy", 1, true), "the copy offered: " .. tostring(top().text))
    h.shot("backup-offer")
    h.tapWidget(h.findButton(top(), "Restore"))
    h.settle()
    local view
    for _, w in ipairs(UIManager._window_stack) do
        if w.widget.name == "paperknight_puzzles" then view = w.widget end
    end
    h.check(view, "the puzzles open once restored")
    h.check(PkProgress.readSetting("backup.test") == "before", "the progress back")
    local broken = io.open(path .. ".broken", "rb")
    h.check(broken and broken:read("*a"):find("damaged", 1, true), "the damaged file kept aside")
    if broken then broken:close() end
    while #UIManager._window_stack > 0 and top().name ~= "paperknight_puzzles" do UIManager:close(top()) end
    if view then view:onClose() end
    h.settle()
    PkProgress.writeSetting("backup.test", nil)
end
