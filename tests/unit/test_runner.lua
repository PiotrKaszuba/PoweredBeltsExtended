local sep = package.config:sub(1, 1)
local function p(path)
	return path:gsub("/", sep)
end
local extra_paths = table.concat({
	p("./?.lua"),
	p("../?.lua"),
	p("../../?.lua"),
	p("../../../?.lua"),
}, ";") .. ";"
package.path = extra_paths .. package.path

local ok, luaunit = pcall(require, "luaunit")
if not ok then
	io.stderr:write("luaunit is required. Install via luarocks: luarocks install luaunit\n")
	os.exit(2)
end

-- Minimal Factorio runtime stubs so control.lua can be loaded for local helper testing.
_G.__PBE_UNIT_TEST_MODE = true
_G.storage = {}
_G.settings = {global = {}, startup = {}}
_G.script = {
	on_event = function(...) end,
	on_init = function(...) end,
	on_configuration_changed = function(...) end,
}
_G.defines = {
	events = {
		on_robot_built_entity = 1,
		on_built_entity = 2,
		script_raised_built = 3,
		script_raised_revive = 4,
		on_entity_died = 5,
		on_robot_mined_entity = 6,
		on_player_mined_entity = 7,
		script_raised_destroy = 8,
		on_tick = 9,
		on_research_finished = 10,
	},
}
_G.commands = {add_command = function(...) end}
_G.remote = {add_interface = function(...) end, interfaces = {}}

local control_ok, control_err = pcall(dofile, "control.lua")
if not control_ok then
	io.stderr:write("Unable to load control.lua in unit test runner:\n" .. tostring(control_err) .. "\n")
	os.exit(3)
end
if _G.__PBE_TEST_API == nil then
	io.stderr:write("control.lua test exports were not created.\n")
	os.exit(4)
end

require("tests.unit.spec.test_underground_transfer_mode")

os.exit(luaunit.LuaUnit.run())
