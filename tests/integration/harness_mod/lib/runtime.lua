local scenarios = require("scenarios")
local layouts = require("layouts_generated.index")
local world = require("lib.world")
local assertions = require("lib.assertions")
local loaded_build_order_config = nil

do
	local ok, value = pcall(require, "lib.build_order_config")
	if ok and type(value) == "table" then
		loaded_build_order_config = value
	end
end

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

local function append_actions(base_actions, extra_actions)
	local actions = {}
	for _, action in ipairs(base_actions or {}) do
		actions[#actions + 1] = deep_copy(action)
	end
	for _, action in ipairs(extra_actions or {}) do
		actions[#actions + 1] = deep_copy(action)
	end
	return actions
end

local function normalize_probe_ticks(value)
	if type(value) ~= "table" then
		return nil
	end
	local ticks = {}
	for _, tick in pairs(value) do
		if type(tick) == "number" then
			ticks[#ticks + 1] = math.floor(tick)
		end
	end
	if #ticks == 0 then
		return nil
	end
	table.sort(ticks)
	return ticks
end

local function normalize_non_negative_tick(value, field_name)
	if type(value) ~= "number" then
		return nil, tostring(field_name or "tick") .. " must be a number"
	end
	local tick = math.floor(value)
	if tick < 0 then
		return nil, tostring(field_name or "tick") .. " must be >= 0"
	end
	return tick, nil
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
			},
		}
	end
	if harness.written_results == nil then
		harness.written_results = false
	end
	if harness.build_order == nil then
		harness.build_order = {
			mode = loaded_build_order_config and loaded_build_order_config.default_mode or "normal",
			seed = loaded_build_order_config and loaded_build_order_config.default_seed or nil,
		}
	end
	return harness
end

local function normalize_build_order(mode, seed)
	if mode == nil then
		mode = "normal"
	end
	if type(mode) ~= "string" then
		return nil, "build_order mode must be a string"
	end
	local normalized_mode = string.lower(mode)
	if normalized_mode == "reverse" then
		normalized_mode = "reversed"
	end
	if normalized_mode ~= "normal" and normalized_mode ~= "reversed" and normalized_mode ~= "random" then
		return nil, "invalid build_order mode: " .. tostring(mode)
	end

	local normalized_seed = nil
	if seed ~= nil then
		if type(seed) ~= "number" then
			return nil, "build_order seed must be a number"
		end
		normalized_seed = math.floor(seed)
	end

	if normalized_mode ~= "random" then
		normalized_seed = nil
	end
	return {
		mode = normalized_mode,
		seed = normalized_seed,
	}
end

local function read_build_order_from_setup_options(setup_options)
	if type(setup_options) ~= "table" then
		return nil, nil, false
	end
	if type(setup_options.build_order) == "table" then
		local build_order, err = normalize_build_order(setup_options.build_order.mode, setup_options.build_order.seed)
		return build_order, err, true
	end
	if setup_options.build_order_mode ~= nil or setup_options.build_order_seed ~= nil then
		local build_order, err = normalize_build_order(setup_options.build_order_mode, setup_options.build_order_seed)
		return build_order, err, true
	end
	return nil, nil, false
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

local function burner_fuel_count_by_reference(active, reference_name)
	local entities = world.get_referenced_entities(active, reference_name)
	if #entities == 0 then
		return -1
	end
	local total = 0
	local has_any = false
	for _, entity in ipairs(entities) do
		local count = burner_fuel_count(entity)
		if count >= 0 then
			total = total + count
			has_any = true
		end
	end
	if not has_any then
		return -1
	end
	return total
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
		local source_inventories = world.get_referenced_inventories(harness.active, "source")
		local sink_inventories = world.get_referenced_inventories(harness.active, "sink")
		if #source_inventories > 0 then
			source_total = world.aggregate_inventory_total_count(source_inventories)
		end
		if #sink_inventories > 0 then
			sink_total = world.aggregate_inventory_total_count(sink_inventories)
		end

		input_fuel = burner_fuel_count_by_reference(harness.active, "input_inserter")
		output_fuel = burner_fuel_count_by_reference(harness.active, "output_inserter")
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
		if type(entity_def.id) == "string" and string.find(entity_def.id, "inserter", 1, true) ~= nil then
			entity_def.name = inserter_name
		end
	end
	return scenario_layout
end

local function collect_researched_technology_names(scenario, setup_options)
	local names = {}
	local function add_all(values)
		if type(values) ~= "table" then
			return
		end
		for _, value in pairs(values) do
			if type(value) == "string" and value ~= "" then
				names[value] = true
			end
		end
	end
	add_all(scenario and scenario.researched_technologies)
	add_all(setup_options and setup_options.researched_technologies)
	return names
end

local function apply_scenario_research(scenario, setup_options)
	local force = game and game.forces and game.forces.player
	if not (force and force.valid and force.technologies) then
		return
	end
	local researched_names = collect_researched_technology_names(scenario, setup_options)
	for name, technology in pairs(force.technologies) do
		if technology and technology.valid and technology.researched ~= nil then
			local should_be_researched = researched_names[name] == true
			if technology.researched ~= should_be_researched then
				pcall(function()
					technology.researched = should_be_researched
				end)
			end
		end
	end
	pcall(function()
		force.reset_technology_effects()
	end)
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

local function get_expected_failed_assertions(scenario, main_mod_available)
	if scenario == nil then
		return 0
	end
	local expected = nil
	if main_mod_available then
		expected = scenario.expected_failed_mod_enabled
	else
		expected = scenario.expected_failed_mod_disabled
	end
	if type(expected) ~= "number" then
		return 0
	end
	return math.max(0, math.floor(expected))
end

local function summarize_scenario(active)
	local has_any_failed = false
	local failed_count = 0
	for _, assertion_result in pairs(active.assertion_results) do
		if not assertion_result.passed then
			has_any_failed = true
			failed_count = failed_count + 1
		end
	end
	local expected_failed_assertions = get_expected_failed_assertions(active.scenario, active.main_mod_available)

	return {
		id = active.scenario.id,
		start_tick = active.start_tick,
		end_tick = game.tick,
		duration_ticks = game.tick - active.start_tick,
		has_any_failed = has_any_failed,
		failed_count = failed_count,
		expected_failed_assertions = expected_failed_assertions,
		build_order = active.build_order,
		passed = failed_count == expected_failed_assertions,
		assertions = active.assertion_results,
		update_loop_probe_report = deep_copy(active.update_loop_probe_report),
	}
end

local function finalize_active_scenario()
	local harness = ensure_harness_storage()
	local active = harness.active
	if active == nil then return end
	if active.inventory ~= nil and active.inventory.valid then
		active.inventory.destroy()
	end
	local scenario_result = summarize_scenario(active)
	harness.results.scenarios[#harness.results.scenarios + 1] = scenario_result
	harness.results.summary.total = harness.results.summary.total + 1
	if scenario_result.passed then
		harness.results.summary.passed = harness.results.summary.passed + 1
	else
		harness.results.summary.failed = harness.results.summary.failed + 1
	end

	call_main_mod("set_test_overrides", nil)
	harness.active = nil
	write_results_if_complete()
end

local function start_scenario(scenario, setup_options)
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
	apply_scenario_research(scenario, setup_options)

	local scenario_start_tick = game.tick
	local scenario_overrides = deep_copy(scenario.settings_overrides or {})
	local probe_ticks = normalize_probe_ticks(setup_options and setup_options.update_loop_probe_ticks)
	local probe_ticks_absolute = nil
	if probe_ticks ~= nil then
		probe_ticks_absolute = {}
		for _, tick in ipairs(probe_ticks) do
			probe_ticks_absolute[#probe_ticks_absolute + 1] = scenario_start_tick + tick
		end
		scenario_overrides.update_iteration_probe_ticks = probe_ticks_absolute
	end
	call_main_mod("set_test_overrides", scenario_overrides)
	local build_order = nil
	local resolved_build_order, resolved_build_order_error = read_build_order_from_setup_options(setup_options)
	if resolved_build_order_error ~= nil then
		error(resolved_build_order_error)
	end
	build_order = resolved_build_order
	if build_order == nil then
		build_order = deep_copy(harness.build_order)
	end
	local placed_entities = world.place_layout(layout, surface, build_order)
	world.bootstrap_daytime_and_power(layout, surface, area, placed_entities)
	call_main_mod("run_full_scan")
	local post_scan = call_main_mod("get_state_snapshot", surface.index)
	local failing_metrics = non_zero_snapshot_metrics(post_scan)
	if failing_metrics ~= nil and #failing_metrics > 0 then
		log("[PBE-HARNESS] post-layout scan still inconsistent: " .. table.concat(failing_metrics, ", "))
	end
	
	
	local mine_inventory = game.create_inventory(1024)
	
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
		build_order = build_order,
		source_baseline_fingerprint = {},
		expected_contents = {},
		inventory = mine_inventory,
		action_history = {},
		update_loop_probe_report = probe_ticks and {
			ticks = probe_ticks,
			abs_tick_start = scenario_start_tick,
			abs_ticks = probe_ticks_absolute,
			iterations = {},
		} or nil,
	}
	active.scenario.actions = append_actions(active.scenario.actions or {}, setup_options and setup_options.extra_actions or nil)
	if setup_options ~= nil and setup_options.pause_at_tick ~= nil then
		active.scenario.actions[#active.scenario.actions + 1] = {
			tick = setup_options.pause_at_tick,
			type = "pause_game",
		}
	end
	active.scenario.actions = sort_by_tick(active.scenario.actions or {})
	active.scenario.checkpoints = sort_by_tick(active.scenario.checkpoints or {})

	while active.next_action_idx <= #active.scenario.actions and (active.scenario.actions[active.next_action_idx].tick or 0) <= 0 do
		local action = active.scenario.actions[active.next_action_idx]
		world.apply_action(active, action, call_main_mod)
		active.action_history[#active.action_history + 1] = {tick = 0, action = deep_copy(action)}
		active.next_action_idx = active.next_action_idx + 1
	end

	local source_inventories = world.get_referenced_inventories(active, "source")
	active.source_baseline_fingerprint = world.aggregate_inventory_fingerprint(source_inventories)
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
		-- DEBUG: print pending action
		-- game.print(string.format("[PBE-HARNESS] applying action %s at tick %d", active.scenario.actions[active.next_action_idx].type, active.scenario.actions[active.next_action_idx].tick))
		if (action.tick or 0) > elapsed then break end
		world.apply_action(active, action, call_main_mod)
		active.action_history[#active.action_history + 1] = {tick = elapsed, action = deep_copy(action)}
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

function M.get_scenario_definition(id)
	local scenario = scenarios.find_by_id(id)
	if scenario == nil then
		return nil
	end
	return deep_copy(scenario)
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

local function setup_scenario_state(id, save_name, setup_options)
	local scenario = scenarios.find_by_id(id)
	if scenario == nil then
		return {ok = false, error = "Unknown scenario id: " .. tostring(id)}
	end
	local _, build_order_error, has_explicit_build_order = read_build_order_from_setup_options(setup_options)
	if has_explicit_build_order and build_order_error ~= nil then
		return {ok = false, error = build_order_error}
	end
	local normalized_pause_tick = nil
	if type(setup_options) == "table" and setup_options.pause_at_tick ~= nil then
		local pause_tick_error = nil
		normalized_pause_tick, pause_tick_error = normalize_non_negative_tick(setup_options.pause_at_tick, "pause_at_tick")
		if pause_tick_error ~= nil then
			return {ok = false, error = pause_tick_error}
		end
	end

	local harness = ensure_harness_storage()
	reset_results()
	harness.queue = {}
	harness.active = nil
	apply_test_game_speed()
	local effective_setup_options = setup_options
	if type(setup_options) == "table" then
		effective_setup_options = deep_copy(setup_options)
		effective_setup_options.pause_at_tick = normalized_pause_tick
	end
	start_scenario(scenario, effective_setup_options)

	local should_pause = setup_options == nil or setup_options.pause ~= false
	if should_pause then
		game.tick_paused = true
	end

	local should_save = setup_options == nil or setup_options.save_snapshot ~= false
	local final_save_name = nil
	if should_save then
		final_save_name = save_name
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
	end

	local keep_active = setup_options ~= nil and setup_options.keep_active == true
	if not keep_active then
		harness.active = nil
		harness.queue = {}
	end

	return {
		ok = true,
		scenario_id = id,
		save_name = final_save_name,
		tick = game.tick,
		active = keep_active,
	}
end

function M.capture_scenario_setup(id, save_name, setup_options)
	local positional_mode = nil
	local positional_seed = nil
	if save_name == "normal" or save_name == "reversed" or save_name == "reverse" or save_name == "random" then
		positional_mode = save_name
		save_name = nil
		if type(setup_options) == "number" then
			positional_seed = setup_options
			setup_options = nil
		end
	end
	local options = {
		keep_active = false,
		pause = true,
		save_snapshot = true,
		researched_technologies = nil,
		build_order_mode = positional_mode,
		build_order_seed = positional_seed,
	}
	if type(setup_options) == "table" then
		options.researched_technologies = setup_options.researched_technologies
		if setup_options.build_order_mode ~= nil then
			options.build_order_mode = setup_options.build_order_mode
		end
		if setup_options.build_order_seed ~= nil then
			options.build_order_seed = setup_options.build_order_seed
		end
		if type(setup_options.build_order) == "table" then
			options.build_order_mode = setup_options.build_order.mode
			options.build_order_seed = setup_options.build_order.seed
		end
	end
	return setup_scenario_state(id, save_name, options)
end

function M.prepare_scenario_setup(id, save_name, setup_options)
	local positional_mode = nil
	local positional_seed = nil
	if save_name == "normal" or save_name == "reversed" or save_name == "reverse" or save_name == "random" then
		positional_mode = save_name
		save_name = nil
		if type(setup_options) == "number" then
			positional_seed = setup_options
			setup_options = nil
		end
	end
	local options = {
		keep_active = true,
		pause = true,
		save_snapshot = true,
		researched_technologies = nil,
		extra_actions = nil,
		update_loop_probe_ticks = nil,
		pause_at_tick = nil,
		build_order_mode = positional_mode,
		build_order_seed = positional_seed,
	}
	if type(setup_options) == "table" then
		if setup_options.save_snapshot == false then
			options.save_snapshot = false
		end
		if setup_options.pause == false then
			options.pause = false
		end
		options.researched_technologies = setup_options.researched_technologies
		if type(setup_options.extra_actions) == "table" then
			options.extra_actions = setup_options.extra_actions
		end
		if type(setup_options.update_loop_probe_ticks) == "table" then
			options.update_loop_probe_ticks = setup_options.update_loop_probe_ticks
		end
		if setup_options.pause_at_tick ~= nil then
			options.pause_at_tick = setup_options.pause_at_tick
		end
		if setup_options.build_order_mode ~= nil then
			options.build_order_mode = setup_options.build_order_mode
		end
		if setup_options.build_order_seed ~= nil then
			options.build_order_seed = setup_options.build_order_seed
		end
		if type(setup_options.build_order) == "table" then
			options.build_order_mode = setup_options.build_order.mode
			options.build_order_seed = setup_options.build_order.seed
		end
	end
	return setup_scenario_state(id, save_name, options)
end

function M.queue_pause_at_tick(tick)
	local harness = ensure_harness_storage()
	if harness.active == nil then
		return {ok = false, error = "No active scenario"}
	end
	local normalized_tick, tick_error = normalize_non_negative_tick(tick, "tick")
	if tick_error ~= nil then
		return {ok = false, error = tick_error}
	end
	harness.active.scenario.actions[#harness.active.scenario.actions + 1] = {
		tick = normalized_tick,
		type = "pause_game",
	}
	harness.active.scenario.actions = sort_by_tick(harness.active.scenario.actions)
	if harness.active.next_action_idx < 1 then
		harness.active.next_action_idx = 1
	end
	return {ok = true, tick = normalized_tick, action_count = #harness.active.scenario.actions}
end

function M.add_action_to_active_scenario(action)
	local harness = ensure_harness_storage()
	if harness.active == nil then
		return {ok = false, error = "No active scenario"}
	end
	if type(action) ~= "table" then
		return {ok = false, error = "Action must be a table"}
	end
	harness.active.scenario.actions[#harness.active.scenario.actions + 1] = deep_copy(action)
	harness.active.scenario.actions = sort_by_tick(harness.active.scenario.actions)
	if harness.active.next_action_idx < 1 then
		harness.active.next_action_idx = 1
	end
	return {ok = true, action_count = #harness.active.scenario.actions}
end

function M.run_item_location_scan_now(options)
	local harness = ensure_harness_storage()
	if harness.active == nil then
		return {ok = false, error = "No active scenario"}
	end
	local action = {
		type = "scan_item_locations",
		debug_log = options ~= nil and options.debug_log == true,
		output_file = options and options.output_file or nil,
	}
	world.apply_action(harness.active, action, call_main_mod)
	return {ok = true, tick = game.tick}
end

function M.record_update_loop_iteration_probe(payload)
	local harness = ensure_harness_storage()
	if harness.active == nil then
		return false
	end
	local report = harness.active.update_loop_probe_report
	if report == nil then
		return false
	end
	if type(payload) ~= "table" then
		payload = {}
	end
	local entry = deep_copy(payload)
	if type(entry.tick) == "number" and type(report.abs_tick_start) == "number" then
		entry.abs_tick = entry.tick
		entry.tick = entry.tick - report.abs_tick_start
	end
	entry.scan = world.scan_chain_item_locations(harness.active)
	report.iterations[#report.iterations + 1] = entry
	return true
end

function M.get_active_action_history()
	local harness = ensure_harness_storage()
	if harness.active == nil then
		return {}
	end
	return deep_copy(harness.active.action_history or {})
end

function M.set_build_order(mode, seed)
	local harness = ensure_harness_storage()
	local build_order, err = normalize_build_order(mode, seed)
	if build_order == nil then
		return {ok = false, error = err}
	end
	harness.build_order = build_order
	return {ok = true, build_order = deep_copy(build_order)}
end

function M.get_build_order()
	local harness = ensure_harness_storage()
	return deep_copy(harness.build_order)
end

function M.run_suite(filter)
	local suite = get_filtered_suite(filter)
	apply_test_game_speed()
	queue_scenarios(suite)
	return #suite
end

function M.list_scenario_ids(filter)
	local suite = get_filtered_suite(filter)
	local ids = {}
	for _, scenario in pairs(suite) do
		if scenario ~= nil and scenario.id ~= nil then
			ids[#ids + 1] = tostring(scenario.id)
		end
	end
	table.sort(ids)
	return ids
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
