-- luacheck (make lint): KOReader's LuaJIT, its globals, the plugin's style.
std = "luajit"
max_line_length = 130
self = false -- methods need not use self
-- unused names starting with _ say so on purpose (loop counters, callback arguments)
ignore = { "21[123]/_.*" }
read_globals = { "G_reader_settings" }
exclude_files = { "plugin/paperknight.koplugin/pkchesslib/**", "build/**" }

-- KOReader reads it before the plugin loads: a long description on one line
files["plugin/paperknight.koplugin/_meta.lua"] = { max_line_length = false }
-- the spec runner's globals; check messages may be long
files["plugin/tests"] = { globals = { "PK_KOREADER_ENV", "PK_REPO_ROOT" }, max_line_length = false }
-- scenarios read step by step: a name is reused for the next step's value
files["tools/emulator"] = { max_line_length = false, ignore = { "21[123]/_.*", "4[123]." } }
