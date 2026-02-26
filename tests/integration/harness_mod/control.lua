local runtime = require("lib.runtime")

script.on_init(runtime.on_init)
script.on_configuration_changed(runtime.on_configuration_changed)
script.on_event(defines.events.on_tick, runtime.on_tick)

remote.add_interface("pbe_integration_harness", {
	run_scenario = runtime.run_scenario,
	capture_scenario_setup = runtime.capture_scenario_setup,
	prepare_scenario_setup = runtime.prepare_scenario_setup,
	set_build_order = runtime.set_build_order,
	get_build_order = runtime.get_build_order,
	run_suite = runtime.run_suite,
	get_results = runtime.get_results,
	reset_world = runtime.reset_world,
})
