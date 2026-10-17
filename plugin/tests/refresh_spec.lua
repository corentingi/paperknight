-- DU4 board refreshes (pkrefresh.lua, experiment exp/du4-board).
if not PK_KOREADER_ENV then
    return { { "SKIPPED: run via `make test-lua` (needs KOReader env)", function(t) t.ok(false, "no KOReader env") end } }
end
package.loaded["ui/uimanager"] = package.loaded["ui/uimanager"] or { setDirty = function() end }
local Blitbuffer = require("ffi/blitbuffer")
local Geometry = require("ui/geometry")
local PkRefresh = require("pkrefresh")

return {
    { "quantize4: every grey of the rectangle becomes 0x00, 0x55, 0xAA or 0xFF; outside untouched", function(t)
        local bb = Blitbuffer.new(8, 2, Blitbuffer.TYPE_BB8)
        local greys = { 0x00, 0x20, 0x40, 0x7F, 0x80, 0xBB, 0xDD, 0xFF }
        for x = 0, 7 do
            bb:setPixel(x, 0, Blitbuffer.Color8(greys[x + 1]))
            bb:setPixel(x, 1, Blitbuffer.Color8(0xDD))
        end
        t.ok(PkRefresh.quantize4(bb, Geometry:new{ x = 0, y = 0, w = 8, h = 1 }), "an 8-bit buffer")
        local want = { 0x00, 0x00, 0x55, 0x55, 0xAA, 0xAA, 0xFF, 0xFF }
        for x = 0, 7 do
            t.eq(bb:getPixel(x, 0):getColor8().a, want[x + 1], ("0x%02X"):format(greys[x + 1]))
        end
        t.eq(bb:getPixel(3, 1):getColor8().a, 0xDD, "the row below is left alone")
        bb:free()
        local rgb = Blitbuffer.new(2, 2, Blitbuffer.TYPE_BBRGB32)
        t.eq(PkRefresh.quantize4(rgb, Geometry:new{ x = 0, y = 0, w = 2, h = 2 }), false, "other buffers: untouched")
        rgb:free()
    end },
    { "boardRegion: DU4 on the Kindle (quantized, partial), else the usual refresh", function(t)
        local available = PkRefresh.du4Available
        local r = Geometry:new{ x = 1, y = 1, w = 4, h = 4 }
        PkRefresh.du4Available = function() return false end
        local mode, region = PkRefresh.boardRegion("[partial]", r)
        t.eq(mode, "[partial]", "not a Kindle: mode"); t.eq(region, r, "region")
        local sent
        local bb = Blitbuffer.new(8, 8, Blitbuffer.TYPE_BB8)
        bb:fill(Blitbuffer.Color8(0xDD))
        PkRefresh.du4Available = function() return true end
        PkRefresh.screen = { bb = bb, mech_refresh = function(_, flashing, wf, x, y, w, h)
            sent = { flashing = flashing, wf = wf, x = x, y = y, w = w, h = h }
        end }
        mode, region = PkRefresh.boardRegion("[partial]", r)
        t.ok(sent and sent.wf == PkRefresh.DU4 and sent.flashing == false and sent.w == 4, "DU4 sent, not flashing")
        t.eq(bb:getPixel(2, 2):getColor8().a, 0xFF, "quantized before")
        t.eq(bb:getPixel(6, 6):getColor8().a, 0xDD, "only the region")
        t.ok(mode == "fast" and region.w == 1 and region.h == 1, "UIManager: a refresh it discards")
        PkRefresh.du4Available, PkRefresh.screen = available, nil
        bb:free()
    end },
}
