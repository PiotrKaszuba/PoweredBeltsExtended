local runtime = require("lib.runtime")

script.on_init(runtime.on_init)
script.on_configuration_changed(runtime.on_configuration_changed)
script.on_event(defines.events.on_tick, runtime.on_tick)

remote.add_interface("pbe_integration_harness", {
	run_scenario = runtime.run_scenario,
	get_scenario_definition = runtime.get_scenario_definition,
	capture_scenario_setup = runtime.capture_scenario_setup,
	prepare_scenario_setup = runtime.prepare_scenario_setup,
	set_build_order = runtime.set_build_order,
	get_build_order = runtime.get_build_order,
	run_suite = runtime.run_suite,
	list_scenario_ids = runtime.list_scenario_ids,
	get_results = runtime.get_results,
	reset_world = runtime.reset_world,
	queue_pause_at_tick = runtime.queue_pause_at_tick,
	add_action_to_active_scenario = runtime.add_action_to_active_scenario,
	run_item_location_scan_now = runtime.run_item_location_scan_now,
	record_update_loop_iteration_probe = runtime.record_update_loop_iteration_probe,
	get_active_action_history = runtime.get_active_action_history,
})
