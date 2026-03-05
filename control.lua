local utils = require("modules.utils")
local scans = require("modules.scans")
local forces = require("modules.forces")
local migrations = require("modules.migrations")
local event_handlers = require("modules.event_handlers")
local update_loop = require("modules.update_loop")
local stats = require("modules.stats")
local tests = require("modules.tests")

script.on_init(function()
	migrations.init_globals()
	scans.find_all_power_entities()
end)

script.on_configuration_changed(function()
	migrations.init_globals()
	scans.find_all_power_entities()
end)

script.on_event({
	defines.events.on_robot_built_entity,
	defines.events.on_built_entity,
	defines.events.script_raised_built,
	defines.events.script_raised_revive,
	defines.events.on_entity_cloned,
	defines.events.on_space_platform_built_entity
}, event_handlers.on_built_entity)

script.on_event({
	defines.events.on_entity_died,
	defines.events.on_robot_mined_entity,
	defines.events.on_player_mined_entity,
	defines.events.script_raised_destroy,
	defines.events.on_space_platform_mined_entity,
}, event_handlers.on_removed_entity)

script.on_event(defines.events.on_tick, update_loop.on_tick)
script.on_event({defines.events.on_research_finished}, forces.tech_check)
commands.add_command("PBE_CheckPowerEntities", "Checks and cleans power entities on all surfaces", scans.find_all_power_entities)
remote.add_interface("powered_belts_extended", {
	get_storage = function() return storage end,
	run_full_scan = scans.run_full_scan,
	get_state_snapshot = stats.get_state_snapshot,
	set_test_overrides = tests.set_test_overrides,
})

tests.register_test_api()
