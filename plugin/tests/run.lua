-- Minimal test runner for plugin logic that does not need KOReader's UI.
-- Usage: luajit plugin/tests/run.lua [spec files...]   (run from the repo root)
-- Each spec file returns a list of { name, fn } pairs; fn receives assertions `t`.
local here = debug.getinfo(1, "S").source:gsub("^@", ""):match("(.*)/") or "."
local plugin_dir = here .. "/../paperknight.koplugin"
package.path = plugin_dir .. "/?.lua;" .. here .. "/?.lua;" .. package.path

local t = {}
function t.eq(actual, expected, msg)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(msg or "eq", tostring(expected), tostring(actual)), 2)
    end
end
function t.ok(value, msg)
    if not value then error((msg or "expected truthy value"), 2) end
end

local specs = { ... }
if #specs == 0 then
    local p = io.popen('ls "' .. here .. '"/*_spec.lua')
    for line in p:lines() do specs[#specs + 1] = line end
    p:close()
end

local passed, failed = 0, 0
for _, spec in ipairs(specs) do
    local cases = dofile(spec)
    for _, case in ipairs(cases) do
        local ok, err = pcall(case[2], t)
        if ok then
            passed = passed + 1
        else
            failed = failed + 1
            print(("FAIL %s :: %s\n     %s"):format(spec:match("[^/]+$"), case[1], err))
        end
    end
end
print(("%d passed, %d failed"):format(passed, failed))
if passed + failed == 0 then
    print("no tests found")
    os.exit(1)
end
os.exit(failed == 0 and 0 or 1)
