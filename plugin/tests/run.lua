-- Minimal test runner for plugin logic that does not need KOReader's UI.
-- Usage: `make test-lua` (runs it from KOReader's directory, so specs that
-- need KOReader's modules run too), or luajit plugin/tests/run.lua [specs...].
-- Each spec file returns a list of { name, fn } pairs; fn receives assertions `t`.
local here = debug.getinfo(1, "S").source:gsub("^@", ""):match("(.*)/") or "."
local plugin_dir = here .. "/../paperknight.koplugin"
package.path = plugin_dir .. "/?.lua;" .. here .. "/?.lua;" .. package.path

-- When started from KOReader's assets directory (as `make test-lua` does), load
-- KOReader's environment so modules like lua-ljsqlite3 and logger work.
PK_KOREADER_ENV = pcall(require, "setupkoenv")
if PK_KOREADER_ENV then
    -- KOReader's frontend and common modules, as in reader.lua
    package.path = "frontend/?.lua;common/?.lua;" .. package.path
end
PK_REPO_ROOT = here .. "/../.."

local t = {}
local asserted -- the error comes from t.eq / t.ok (no traceback needed)
function t.eq(actual, expected, msg)
    if actual ~= expected then
        asserted = true
        error(("%s: expected %s, got %s"):format(msg or "eq", tostring(expected), tostring(actual)), 2)
    end
end
function t.ok(value, msg)
    if not value then
        asserted = true
        error((msg or "expected truthy value"), 2)
    end
end
-- failed assertion: its message; any other error: with a traceback
local function onError(err)
    if asserted then return tostring(err) end
    return debug.traceback(tostring(err))
end

local specs = { ... }
if #specs == 0 then
    local p = io.popen('ls "' .. here .. '"/*_spec.lua')
    for line in p:lines() do specs[#specs + 1] = line end
    p:close()
end

local passed, failed = 0, 0
for _, spec in ipairs(specs) do
    local loaded, cases = pcall(dofile, spec)
    if not loaded then -- counted, and the other specs still run
        failed = failed + 1
        print(("FAIL %s :: cannot load\n     %s"):format(spec:match("[^/]+$"), tostring(cases)))
        cases = {}
    end
    for _, case in ipairs(cases) do
        asserted = false
        local ok, err = xpcall(case[2], onError, t)
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
