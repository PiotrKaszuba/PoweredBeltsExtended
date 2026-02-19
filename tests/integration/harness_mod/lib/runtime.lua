local scenarios = require("scenarios")
local layouts = require("layouts_generated.index")
local world = require("lib.world")
local assertions = require("lib.assertions")

local M = {}

local main_mod_remote_interface = "powered_belts_extended"
local results_output_file = "pbe-integration-results.json"
local test_game_speed = 1
local tick_log_interval = 60

local function deep_copy(value, seen)
	if type(value) ~= "table" then
		return value
	end
	seen = seen or {}
	if seen[value] ~= nil then
		return seen[value]
	end
	local copy = {}
	seen[value] = copy
	for key, entry in pairs(value) do
		copy[deep_copy(key, seen)] = deep_copy(entry, seen)
	end
	return copy
end

local function call_main_mod(function_name, ...)
	if not remote.interfaces[main_mod_remote_interface] then
		return nil
	end
	if not remote.interfaces[main_mod_remote_interface][function_name] then
		return nil
	end
	return remote.call(main_mod_remote_interface, function_name, ...)
end

local function is_main_mod_available()
	return remote.interfaces[main_mod_remote_interface] ~= nil
end

local function apply_test_game_speed()
	if game ~= nil and game.speed ~= test_game_speed then
		game.speed = test_game_speed
	end
end

local function non_zero_snapshot_metrics(snapshot)
	if snapshot == nil or snapshot.totals == nil then
		return nil
	end
	local metric_names = {
		"missing_storage_entities",
		"missing_storage_power_entities",
		"missing_world_power_entities",
		"duplicate_world_power_entities",
		"invalid_storage_entities",
		"invalid_storage_power_entities",
		"stale_storage_entities",
		"stale_storage_power_entities",
		"orphan_world_power_entities",
		"wrong_power_entity_name",
		"wrong_power_entity_force",
	}
	local failing = {}
	for _, metric in pairs(metric_names) do
		local value = snapshot.totals[metric] or 0
		if value > 0 then
			failing[#failing + 1] = metric .. "=" .. value
		end
	end
	return failing
end

local function sort_by_tick(entries)
	for idx, entry in ipairs(entries) do
		entry.__order_idx = idx
	end
	table.sort(entries, function(a, b)
		local tick_a = a.tick or 0
		local tick_b = b.tick or 0
		if tick_a == tick_b then
			return (a.__order_idx or 0) < (b.__order_idx or 0)
		end
		return tick_a < tick_b
	end)
	for _, entry in ipairs(entries) do
		entry.__order_idx = nil
	end
	return entries
end

local function ensure_harness_storage()
	if storage.harness == nil then
		storage.harness = {}
	end
	local harness = storage.harness
	if harness.queue == nil then harness.queue = {} end
	if harness.active == nil then harness.active = nil end
	if harness.results == nil then
		harness.results = {
			run_started_tick = game.tick,
			run_finished_tick = nil,
			scenarios = {},
			summary = {
				total = 0,
				passed = 0,
				failed = 0,
				blocking_failed = 0,
				non_blocking_failed = 0,
				expected_non_blocking_failed = 0,
			},
		}
	end
	if harness.written_results == nil then
		harness.written_results = false
	end
	return harness
end

local function inventory_total_count(inventory)
	if inventory == nil then
		return -1
	end
	local total = 0
	local ok, contents = pcall(function()
		return inventory.get_contents()
	end)
	if not ok or contents == nil then
		return -1
	end

	local function add_numeric_values(value)
		if type(value) == "number" then
			total = total + value
			return
		end
		if type(value) ~= "table" then
			return
		end
		for _, nested in pairs(value) do
			add_numeric_values(nested)
		end
	end

	for _, count in pairs(contents) do
		add_numeric_values(count)
	end
	return total
end

local function burner_fuel_count(entity)
	if not (entity and entity.valid and entity.burner and entity.burner.inventory) then
		return -1
	end
	local ok, count = pcall(function()
		return entity.burner.inventory.get_item_count()
	end)
	if not ok then
		return -1
	end
	return count or 0
end

local function log_tick_heartbeat()
	if game == nil then return end
	if tick_log_interval <= 0 then return end
	if (game.tick % tick_log_interval) ~= 0 then return end

	local harness = ensure_harness_storage()
	local active_id = "none"
	local source_total = -1
	local sink_total = -1
	local input_fuel = -1
	local output_fuel = -1
	if harness.active ~= nil and harness.active.scenario ~= nil then
		active_id = tostring(harness.active.scenario.id or "unknown")
		local source = world.get_referenced_entity(harness.active, "source")
		local sink = world.get_referenced_entity(harness.active, "sink")
		local source_inventory = world.resolve_inventory(source)
		local sink_inventory = world.resolve_inventory(sink)
		source_total = inventory_total_count(source_inventory)
		sink_total = inventory_total_count(sink_inventory)

		local input_inserter = world.get_referenced_entity(harness.active, "input_inserter")
		local output_inserter = world.get_referenced_entity(harness.active, "output_inserter")
		input_fuel = burner_fuel_count(input_inserter)
		output_fuel = burner_fuel_count(output_inserter)
	end
	log(string.format(
		"[PBE-HARNESS] tick=%d speed=%.3f paused=%s active=%s queue=%d source=%d sink=%d input_fuel=%d output_fuel=%d",
		game.tick,
		game.speed or 0,
		tostring(game.tick_paused),
		active_id,
		#harness.queue,
		source_total,
		sink_total,
		input_fuel,
		output_fuel
	))
end

local function reset_results()
	local harness = ensure_harness_storage()
	harness.results = {
		run_started_tick = game.tick,
		run_finished_tick = nil,
		scenarios = {},
		summary = {
			total = 0,
			passed = 0,
			failed = 0,
			blocking_failed = 0,
			non_blocking_failed = 0,
			expected_non_blocking_failed = 0,
		},
	}
	harness.written_results = false
end

local function build_layout_for_scenario(layout, scenario)
	local inserter_name = scenario and scenario.inserter_name
	if inserter_name == nil or inserter_name == "" then
		return layout
	end

	local scenario_layout = deep_copy(layout)
	for _, entity_def in ipairs(scenario_layout.entities or {}) do
		if entity_def.id == "input_inserter" or entity_def.id == "output_inserter" then
			entity_def.name = inserter_name
		end
	end
	return scenario_layout
end

local function write_results_if_complete()
	local harness = ensure_harness_storage()
	if harness.written_results then return end
	if harness.active ~= nil then return end
	if #harness.queue > 0 then return end
	harness.results.run_finished_tick = game.tick
	local payload = helpers.table_to_json(harness.results)
	helpers.write_file(results_output_file, payload, false)
	harness.written_results = true
end

local function summarize_scenario(active)
	local has_any_failed = false
	local has_blocking_failed = false
	local blocking_failed_count = 0
	local non_blocking_failed_count = 0
	local expected_non_blocking_failed_count = 0
	for _, assertion_result in pairs(active.assertion_results) do
		if not assertion_result.passed then
			has_any_failed = true
			if assertion_result.blocking then
				has_blocking_failed = true
				blocking_failed_count = blocking_failed_count + 1
			elseif assertion_result.expected_failure then
				expected_non_blocking_failed_count = expected_non_blocking_failed_count + 1
			else
				non_blocking_failed_count = non_blocking_failed_count + 1
			end
		end
	end

	return {
		id = active.scenario.id,
		blocking = active.scenario.blocking,
		start_tick = active.start_tick,
		end_tick = game.tick,
		duration_ticks = game.tick - active.start_tick,
		has_any_failed = has_any_failed,
		has_blocking_failed = has_blocking_failed,
		blocking_failed_count = blocking_failed_count,
		non_blocking_failed_count = non_blocking_failed_count,
		expected_non_blocking_failed_count = expected_non_blocking_failed_count,
		passed = not has_blocking_failed,
		assertions = active.assertion_results,
	}
end

local function finalize_active_scenario()
	local harness = ensure_harness_storage()
	local active = harness.active
	if active == nil then return end
	local scenario_result = summarize_scenario(active)
	harness.results.scenarios[#harness.results.scenarios + 1] = scenario_result
	harness.results.summary.total = harness.results.summary.total + 1
	if scenario_result.passed then
		harness.results.summary.passed = harness.results.summary.passed + 1
	else
		harness.results.summary.failed = harness.results.summary.failed + 1
	end
	harness.results.summary.blocking_failed = harness.results.summary.blocking_failed + scenario_result.blocking_failed_count
	harness.results.summary.non_blocking_failed = harness.results.summary.non_blocking_failed + scenario_result.non_blocking_failed_count
	harness.results.summary.expected_non_blocking_failed = harness.results.summary.expected_non_blocking_failed + (scenario_result.expected_non_blocking_failed_count or 0)

	call_main_mod("set_test_overrides", nil)
	harness.active = nil
	write_results_if_complete()
end

local function start_scenario(scenario)
	local harness = ensure_harness_storage()
	apply_test_game_speed()
	local layout = layouts[scenario.layout_id]
	if layout == nil then
		error("Unknown layout id: " .. tostring(scenario.layout_id))
	end
	layout = build_layout_for_scenario(layout, scenario)

	local surface = game.surfaces["nauvis"] or game.surfaces[1]
	local area = layout.area or {left_top = {x = -32, y = -32}, right_bottom = {x = 32, y = 32}}
	world.clear_area(surface, area)

	call_main_mod("set_test_overrides", scenario.settings_overrides or {})
	local placed_entities = world.place_layout(layout, surface)
	world.bootstrap_daytime_and_power(surface, area, placed_entities)
	call_main_mod("run_full_scan")
	local post_scan = call_main_mod("get_state_snapshot", surface.index)
	local failing_metrics = non_zero_snapshot_metrics(post_scan)
	if failing_metrics ~= nil and #failing_metrics > 0 then
		log("[PBE-HARNESS] post-layout scan still inconsistent: " .. table.concat(failing_metrics, ", "))
	end

	local active = {
		scenario = deep_copy(scenario),
		layout = layout,
		surface = surface,
		placed_entities = placed_entities,
		main_mod_available = is_main_mod_available(),
		start_tick = game.tick,
		next_action_idx = 1,
		next_checkpoint_idx = 1,
		assertion_results = {},
		source_baseline_fingerprint = {},
		expected_contents = {},
	}
	active.scenario.actions = sort_by_tick(active.scenario.actions or {})
	active.scenario.checkpoints = sort_by_tick(active.scenario.checkpoints or {})

	while active.next_action_idx <= #active.scenario.actions and (active.scenario.actions[active.next_action_idx].tick or 0) <= 0 do
		world.apply_action(active, active.scenario.actions[active.next_action_idx], call_main_mod)
		active.next_action_idx = active.next_action_idx + 1
	end

	local source = world.get_referenced_entity(active, "source")
	local source_inventory = world.resolve_inventory(source)
	active.source_baseline_fingerprint = world.inventory_fingerprint(source_inventory)
	for _, action in pairs(active.scenario.actions) do
		if action.type == "fill_inventory" and action.target_ref == "source" then
			active.expected_contents = action.stacks or {}
			break
		end
	end

	harness.active = active
end

local function start_next_scenario_if_needed()
	local harness = ensure_harness_storage()
	if harness.active ~= nil then return end
	if #harness.queue == 0 then
		write_results_if_complete()
		return
	end
	local scenario = table.remove(harness.queue, 1)
	start_scenario(scenario)
end

local function run_active_scenario_tick()
	local harness = ensure_harness_storage()
	local active = harness.active
	if active == nil then return end

	local elapsed = game.tick - active.start_tick

	while active.next_action_idx <= #active.scenario.actions do
		local action = active.scenario.actions[active.next_action_idx]
		if (action.tick or 0) > elapsed then break end
		world.apply_action(active, action, call_main_mod)
		active.next_action_idx = active.next_action_idx + 1
	end

	while active.next_checkpoint_idx <= #active.scenario.checkpoints do
		local checkpoint = active.scenario.checkpoints[active.next_checkpoint_idx]
		if (checkpoint.tick or 0) > elapsed then break end
		for _, assertion in pairs(checkpoint.assertions or {}) do
			active.assertion_results[#active.assertion_results + 1] = assertions.run(active, checkpoint.tick or elapsed, assertion, call_main_mod)
		end
		active.next_checkpoint_idx = active.next_checkpoint_idx + 1
	end

	local max_tick = active.scenario.max_tick or 1200
	if elapsed >= max_tick then
		finalize_active_scenario()
	end
end

local function queue_scenarios(scenario_list)
	local harness = ensure_harness_storage()
	reset_results()
	harness.queue = {}
	harness.active = nil
	for _, scenario in pairs(scenario_list) do
		harness.queue[#harness.queue + 1] = deep_copy(scenario)
	end
end

local function get_default_suite()
	return scenarios.get_all()
end

local function get_filtered_suite(filter)
	if filter == nil then
		return get_default_suite()
	end
	if type(filter) == "string" then
		local matched = {}
		for _, scenario in pairs(get_default_suite()) do
			if string.find(scenario.id, filter, 1, true) then
				matched[#matched + 1] = scenario
			end
		end
		return matched
	end
	if type(filter) == "table" then
		local matched = {}
		for _, id in pairs(filter) do
			local scenario = scenarios.find_by_id(id)
			if scenario ~= nil then
				matched[#matched + 1] = scenario
			end
		end
		return matched
	end
	return {}
end

function M.on_init()
	ensure_harness_storage()
	apply_test_game_speed()
	log(string.format(
		"[PBE-HARNESS] init tick=%d speed=%.3f paused=%s",
		game.tick,
		game.speed or 0,
		tostring(game.tick_paused)
	))
	queue_scenarios(get_default_suite())
end

function M.on_configuration_changed(_event)
	ensure_harness_storage()
	apply_test_game_speed()
end

function M.on_tick(_event)
	start_next_scenario_if_needed()
	run_active_scenario_tick()
	start_next_scenario_if_needed()
	log_tick_heartbeat()
end

function M.run_scenario(id)
	local scenario = scenarios.find_by_id(id)
	if scenario == nil then
		return false
	end
	apply_test_game_speed()
	queue_scenarios({scenario})
	return true
end

function M.capture_scenario_setup(id, save_name)
	local scenario = scenarios.find_by_id(id)
	if scenario == nil then
		return {ok = false, error = "Unknown scenario id: " .. tostring(id)}
	end

	local harness = ensure_harness_storage()
	reset_results()
	harness.queue = {}
	harness.active = nil
	apply_test_game_speed()
	start_scenario(scenario)

	-- Freeze at setup state so the created save is an inspection baseline.
	game.tick_paused = true
	harness.active = nil
	harness.queue = {}

	local final_save_name = save_name
	if final_save_name == nil or final_save_name == "" then
		final_save_name = "pbe-setup-" .. tostring(id)
	end

	local ok, err = pcall(function()
		game.auto_save(final_save_name)
	end)
	if not ok then
		return {ok = false, error = "auto_save failed: " .. tostring(err)}
	end

	log(string.format("[PBE-HARNESS] setup snapshot saved: %s", final_save_name))
	return {
		ok = true,
		scenario_id = id,
		save_name = final_save_name,
		tick = game.tick,
	}
end

function M.run_suite(filter)
	local suite = get_filtered_suite(filter)
	apply_test_game_speed()
	queue_scenarios(suite)
	return #suite
end

function M.get_results()
	return ensure_harness_storage().results
end

function M.reset_world()
	local harness = ensure_harness_storage()
	local surface = game.surfaces["nauvis"] or game.surfaces[1]
	world.clear_area(surface, {left_top = {x = -64, y = -64}, right_bottom = {x = 128, y = 128}})
	call_main_mod("set_test_overrides", nil)
	harness.active = nil
	harness.queue = {}
	write_results_if_complete()
	return true
end

return M
