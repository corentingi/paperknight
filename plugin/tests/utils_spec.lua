-- Engine pipe reader (pkutils.lua): lines split across reads, end of file.
if not PK_KOREADER_ENV then
    return { { "SKIPPED: run via `make test-lua` (needs KOReader env)", function(t) t.ok(false, "no KOReader env") end } }
end
local ffi = require("ffi")
-- the reader never schedules: a stub stands in for UIManager (no screen here)
package.loaded["ui/uimanager"] = package.loaded["ui/uimanager"] or { scheduleIn = function() end }
local Utils = require("pkutils")
local C = ffi.C

return {
    { "reader: a line split across reads arrives whole; end of file reported once", function(t)
        local fds = ffi.new("int[2]")
        t.eq(C.pipe(fds), 0, "pipe")
        local lines, eof = {}, 0
        local read = Utils.reader(fds[0], function(l) lines[#lines + 1] = l end, nil, function() eof = eof + 1 end)
        local function send(s) C.write(fds[1], s, #s) end
        send("id name Fake\nbestmo")
        read()
        t.eq(table.concat(lines, "|"), "id name Fake", "complete line only")
        send("ve e2e4 ponder e7e5\n")
        read()
        t.eq(lines[2], "bestmove e2e4 ponder e7e5", "split line joined")
        send("info depth 1")
        C.close(fds[1])
        read() -- the partial line
        read() -- end of file
        read()
        t.eq(lines[3], "info depth 1", "last line without newline delivered at the end")
        t.eq(eof, 1, "end of file reported once")
        C.close(fds[0])
    end },
}
