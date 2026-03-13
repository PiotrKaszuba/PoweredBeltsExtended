local scenarios = {}

local function make_transfer_scenario(base)
	local inserter_name = base.inserter_name or "bulk-inserter"
	local transfer_assertion_type = "transfer_complete"
	if base.expect_transfer_incomplete then
		transfer_assertion_type = "transfer_not_complete"
	end

	local scenario = {
		id = base.id,
		layout_id = base.layout_id,
		inserter_name = inserter_name,
		researched_technologies = base.researched_technologies,
		max_tick = base.max_tick or 1200,
		expected_failed_mod_enabled = base.expected_failed_mod_enabled or 0,
		expected_failed_mod_disabled = base.expected_failed_mod_disabled or 0,
		settings_overrides = {
			underground_item_transfer_mode = base.underground_item_transfer_mode or "preserve-full-state",
			operations_per_tick = base.operations_per_tick or 128,
		},
		actions = {
			{
				tick = 0,
				type = "fill_inventory",
				target_ref = "source",
				stacks = base.item_stacks,
			},
		},
		checkpoints = {
			{
				tick = 120,
				assertions = {
					{type = "structural_consistency"},
				},
			},
			{
				tick = base.max_tick or 1200,
				assertions = {
					{
						type = transfer_assertion_type,
						source_ref = "source",
						sink_ref = "sink",
						expected_contents = base.item_stacks,
						source_should_be_empty = true,
						compare_stack_fingerprints = base.compare_stack_fingerprints or false,
						include_ground_items = (base.include_ground_items == true) or (base.outage ~= nil and base.include_ground_items ~= false),
						ground_item_names = base.ground_item_names,
						ground_items_area = base.ground_items_area,
					},
					{type = "structural_consistency"},
				},
			},
		},
	}

	if inserter_name == "burner-inserter" or base.fuel_burner_inserters then
		scenario.actions[#scenario.actions + 1] = {
			tick = 0,
			type = "fuel_burner_inserters",
			count = base.fuel_count or 100,
		}
	end

	if base.outage then
		scenario.actions[#scenario.actions + 1] = {
			tick = base.outage.off_tick or 220,
			type = "set_surface_daylight",
			mode = "midnight",
		}
		scenario.actions[#scenario.actions + 1] = {
			tick = base.outage.on_tick or 380,
			type = "set_surface_daylight",
			mode = "full-day",
		}
		scenario.checkpoints[#scenario.checkpoints + 1] = {
			tick = base.outage.assert_tick or 320,
			assertions = {
				{
					type = "sink_count_less_than",
					sink_ref = "sink",
					item_name = base.item_stacks[1] and base.item_stacks[1].name or "iron-ore",
					max_count = base.outage.max_sink_during_outage or (base.item_stacks[1] and math.max(1, math.floor(base.item_stacks[1].count * 0.95)) or 1),
				},
			},
		}
	end

	if base.extra_actions then
		for _, action in pairs(base.extra_actions) do
			scenario.actions[#scenario.actions + 1] = action
		end
	end

	if base.extra_checkpoints then
		for _, checkpoint in pairs(base.extra_checkpoints) do
			scenario.checkpoints[#scenario.checkpoints + 1] = checkpoint
		end
	end

	return scenario
end

local function make_planner_state_outage_scenario(base)
	local refs = base.target_refs or {"input_belt_2", "underground_input", "line_splitter"}
	local mark_action = {}
	for key, value in pairs(base.mark_action or {}) do
		mark_action[key] = value
	end
	mark_action.tick = base.mark_tick or mark_action.tick or 220

	local function build_assertion()
		local assertion = {
			type = base.assertion_type,
			target_refs = refs,
		}
		if base.expected_targets ~= nil then
			assertion.expected_targets = base.expected_targets
		end
		return assertion
	end

	local max_tick = base.max_tick or 1800
	local off_tick = base.off_tick or 260
	local on_tick = base.on_tick or 500
	local pre_outage_check_tick = base.pre_outage_check_tick or 240
	local outage_check_tick = base.outage_check_tick or 380
	local post_restore_check_tick = base.post_restore_check_tick or 600
	local transfer_stacks = base.transfer_stacks or {
		{name = "iron-ore", count = 20},
	}
	local actions = {
		{
			tick = 0,
			type = "fill_inventory",
			target_ref = "source",
			stacks = transfer_stacks,
		},
		{
			tick = 0,
			type = "fuel_burner_inserters",
			count = base.fuel_count or 100,
		},
		mark_action,
		{
			tick = off_tick,
			type = "set_surface_daylight",
			mode = "midnight",
		},
		{
			tick = on_tick,
			type = "set_surface_daylight",
			mode = "full-day",
		},
	}
	if type(base.extra_actions) == "table" then
		for _, action in pairs(base.extra_actions) do
			actions[#actions + 1] = action
		end
	end

	return {
		id = base.id,
		layout_id = base.layout_id or "underground_splitter_line",
		inserter_name = base.inserter_name or "bulk-inserter",
		max_tick = max_tick,
		expected_failed_mod_enabled = base.expected_failed_mod_enabled or 0,
		expected_failed_mod_disabled = base.expected_failed_mod_disabled or 0,
		settings_overrides = {
			underground_item_transfer_mode = base.underground_item_transfer_mode or "preserve-full-state",
			operations_per_tick = base.operations_per_tick or 128,
		},
		actions = actions,
		checkpoints = {
			{
				tick = pre_outage_check_tick,
				assertions = {
					build_assertion(),
					{type = "structural_consistency"},
				},
			},
			{
				tick = outage_check_tick,
				assertions = {
					build_assertion(),
				},
			},
			{
				tick = post_restore_check_tick,
				assertions = {
					build_assertion(),
					{type = "structural_consistency"},
				},
			},
			{
				tick = max_tick,
				assertions = {
					{
						type = "transfer_complete",
						source_ref = "source",
						sink_ref = "sink",
						expected_contents = transfer_stacks,
						source_should_be_empty = true,
						include_ground_items = base.include_ground_items == true,
						ground_item_names = base.ground_item_names,
						ground_items_area = base.ground_items_area,
					},
					{type = "structural_consistency"},
				},
			},
		},
	}
end

local function append_periodic_pole_flicker_actions(actions, config)
	local cycle_count = config.cycle_count or 2
	local phase_interval = config.phase_interval or 80
	local cycle_gap = config.cycle_gap or 120
	local start_tick = config.start_tick or 0

	local function add(tick, action)
		action.tick = tick
		actions[#actions + 1] = action
	end

	local build_pole_a_action = function() return {
		type = "build_entity",
		name = "small-electric-pole",
		position = config.pole_a_position,
	} end
	local build_pole_b_action = function() return {
		type = "build_entity",
			name = "small-electric-pole",
			position = config.pole_b_position,
	} end
	

	add(0, build_pole_a_action())
	add(0, build_pole_b_action())

	for cycle = 0, cycle_count - 1 do
		local cycle_start = start_tick + cycle * ((phase_interval * 4) + cycle_gap)

		add(cycle_start + 0 * phase_interval, {type = "mine_entities_at_position", name = "small-electric-pole", position = config.pole_a_position})
		add(cycle_start + 1 * phase_interval, {type = "mine_entities_at_position", name = "small-electric-pole", position = config.pole_b_position})
		add(cycle_start + 2 * phase_interval, build_pole_a_action())
		add(cycle_start + 3 * phase_interval, build_pole_b_action())
	end
end

local function sort_actions_by_tick(actions)
	table.sort(actions, function(a, b)
		return a.tick < b.tick
	end)
end

local function make_multi_io_planner_blueprint_flicker_scenario()
	local phase_interval = 90
	local cycle_span = phase_interval * 4
	local cycle_gap = 120
	local cycle_count = 22
	local first_major_tick = 120
	local major_spacing = cycle_span * 2 + cycle_gap
	local y_line = 0.5

	local actions = {
		{
			tick = 0,
			type = "find_and_remove_matching_entities",
			position = {x = 4.5, y = y_line},
			radius = 4.0,
			entity_name = "medium-electric-pole",
			entity_type = "electric-pole",
		},
		{
			tick = 0,
			type = "find_and_remove_matching_entities",
			position = {x = 8.5, y = y_line},
			radius = 4.0,
			entity_name = "medium-electric-pole",
			entity_type = "electric-pole",
		},
		{
			tick = 0,
			type = "fill_inventory",
			target_ref = "source",
			stacks = {
				{name = "iron-plate", count = 60, target_ref = "source_chest_inline"},
				{name = "iron-plate", count = 60, target_ref = "source_chest_north_left"},
				{name = "iron-plate", count = 60, target_ref = "source_chest_north_right"},
				{name = "iron-plate", count = 60, target_ref = "source_chest_south_left"},
				{name = "iron-plate", count = 60, target_ref = "source_chest_south_right"},
			},
		},

		{
			tick = 0,
			type = "set_surface_daylight",
			mode = "full-day",
		},
		
		{
			tick = first_major_tick + major_spacing,
			type = "build_blueprint",
			position = {x = 3.5, y = y_line},
			force_build = false,
		},
		{
			tick = first_major_tick + major_spacing * 2,
			type = "build_blueprint",
			position = {x = 8.5, y = y_line},
			force_build = true,
		},
		{
			tick = first_major_tick + major_spacing * 2 + 1,
			type = "mine_entities_at_position",
			name = "entity-ghost",
			position = {x = 8.5, y = y_line},
		},
		{
			tick = first_major_tick + major_spacing * 3,
			type = "mine_marked_entities",
			target_refs = {"underground_output", "belt_before_splitter_1"},
		},
		{
			tick = first_major_tick + major_spacing * 4,
			type = "revive_ghosts",
			ghosts = {
				{name = "underground-belt", position = {x = 9.5, y = y_line}},
			},
		},

		{
			tick = first_major_tick + major_spacing * 5,
			type = "build_blueprint",
			position = {x = 5.5, y = y_line},
			force_build = true,
			entities = {
				{entity_number = 1, name = "underground-belt", position = {x = 0, y = 0}, direction = 4, type = "input"},
			},
		},
		{
			tick = first_major_tick + major_spacing * 6,
			type = "revive_ghosts",
			ghosts = {
				{name = "underground-belt", position = {x = 5.5, y = y_line}},
			},
		},

		{
			tick = first_major_tick + major_spacing * 7,
			type = "set_surface_daylight",
			mode = "full-day",
		},

		{
			tick = first_major_tick + major_spacing * 7 + 1,
			type = "build_blueprint",
			position = {x = 8.5, y = y_line},
			force_build = true,
			entities = {
				{entity_number = 1, name = "underground-belt", position = {x = 0, y = 0}, direction = 4, type = "output"},
			},
		},
		{
			tick = first_major_tick + major_spacing * 8,
			type = "mine_entities_at_position",
			entity_type = "underground-belt",
			position = {x = 4.5, y = y_line},
		},
		{
			tick = first_major_tick + major_spacing * 8 + 1,
			type = "build_entity",
			name = "transport-belt",
			position = {x = 4.5, y = y_line},
			direction = 4,
		},
		{
			tick = first_major_tick + major_spacing * 9,
			type = "revive_ghosts",
			ghosts = {
				{name = "underground-belt", position = {x = 8.5, y = y_line}},
			},
		},
		{
			tick = first_major_tick + major_spacing * 10,
			type = "mine_entities_at_position",
			entity_type = "underground-belt",
			position = {x = 9.5, y = y_line},
		},
		{
			tick = first_major_tick + major_spacing * 10 + 1,
			type = "build_entity",
			name = "transport-belt",
			position = {x = 9.5, y = y_line},
			direction = 4,
		},
	}

	append_periodic_pole_flicker_actions(actions, {
		start_tick = first_major_tick + phase_interval,
		phase_interval = phase_interval,
		cycle_gap = cycle_gap,
		cycle_count = cycle_count,
		pole_a_position = {x = 4.5, y = y_line + 1.0},
		pole_b_position = {x = 8.5, y = y_line + 1.0},
	})

	sort_actions_by_tick(actions)

	return {
		id = "planner_blueprint_build_and_force_build_multi_io_flicker",
		layout_id = "underground_splitter_line_multi_io",
		inserter_name = "bulk-inserter",
		researched_technologies = {"inserter-capacity-bonus-1"},
		max_tick = first_major_tick + major_spacing * 12 + 2500,
		settings_overrides = {
			underground_item_transfer_mode = "preserve-full-state",
			operations_per_tick = 128,
		},
		actions = actions,
		checkpoints = {
			{tick = first_major_tick + major_spacing * 4, assertions = {{type = "structural_consistency"}}},
			{tick = first_major_tick + major_spacing * 8, assertions = {{type = "structural_consistency"}}},
			{
				tick = first_major_tick + major_spacing * 12 + 2500,
				assertions = {
					{
						type = "transfer_complete",
						source_ref = "source",
						sink_ref = "sink",
						expected_contents = {
							{name = "iron-plate", count = 60, target_ref = "source_chest_inline"},
							{name = "iron-plate", count = 60, target_ref = "source_chest_north_left"},
							{name = "iron-plate", count = 60, target_ref = "source_chest_north_right"},
							{name = "iron-plate", count = 60, target_ref = "source_chest_south_left"},
							{name = "iron-plate", count = 60, target_ref = "source_chest_south_right"},
						},
						source_should_be_empty = true,
						include_ground_items = true,
						include_mine_inventory = true,
						ground_item_names = {"iron-plate"},
					},
	
					{type = "structural_consistency"},
				},
			},
		},
	}
end

local function default_scenarios()
	return {
		make_transfer_scenario{
			id = "transfer_straight_name_only_basic",
			layout_id = "straight_line",
			underground_item_transfer_mode = "name-only",
			item_stacks = {
				{name = "iron-ore", count = 60},
			},
			max_tick = 2000,
		},
		make_transfer_scenario{
			id = "transfer_straight_name_only_mixed",
			layout_id = "straight_line",
			underground_item_transfer_mode = "name-only",
			item_stacks = {
				{name = "iron-ore", count = 30},
				{name = "copper-ore", count = 30},
				{name = "coal", count = 30},
			},
			max_tick = 3000,
		},
		make_transfer_scenario{
			id = "transfer_underground_outage_restore_name_only",
			layout_id = "underground_splitter_line",
			underground_item_transfer_mode = "name-only",
			item_stacks = {
				{name = "iron-plate", count = 60},
			},
			max_tick = 2200,
			outage = {
				max_sink_during_outage = 58,
			},
		},
		make_transfer_scenario{
			id = "transfer_underground_outage_restore_preserve",
			layout_id = "underground_splitter_line",
			underground_item_transfer_mode = "preserve-full-state",
			item_stacks = {
				{name = "iron-plate", count = 60},
			},
			max_tick = 2200,
			outage = {
				max_sink_during_outage = 58,
			},
		},
		make_transfer_scenario{
			id = "transfer_underground_multi_io_outage_restore_disabled_negative",
			layout_id = "underground_splitter_line_multi_io",
			underground_item_transfer_mode = "disabled",
			expect_transfer_incomplete = true,
			expected_failed_mod_disabled = 2,
			researched_technologies = {"inserter-capacity-bonus-1"},
			item_stacks = {
				{name = "iron-plate", count = 60, target_ref = "source_chest_inline"},
				{name = "iron-plate", count = 60, target_ref = "source_chest_north_left"},
				{name = "iron-plate", count = 60, target_ref = "source_chest_north_right"},
				{name = "iron-plate", count = 60, target_ref = "source_chest_south_left"},
				{name = "iron-plate", count = 60, target_ref = "source_chest_south_right"},
			},
			max_tick = 3000,
			outage = {
				off_tick = 400,
				on_tick = 600,
				assert_tick = 520,
				max_sink_during_outage = 280,
			},
			extra_checkpoints = {
				{
					tick = 3000,
					assertions = {
						{type = "item_not_conserved", source_ref = "source", sink_ref = "sink"},
					},
				},
			},
		},
		make_transfer_scenario{
			id = "transfer_underground_multi_io_outage_restore_name_only",
			layout_id = "underground_splitter_line_multi_io",
			underground_item_transfer_mode = "name-only",
			researched_technologies = {"inserter-capacity-bonus-1"},
			item_stacks = {
				{name = "iron-plate", count = 60, target_ref = "source_chest_inline"},
				{name = "iron-plate", count = 60, target_ref = "source_chest_north_left"},
				{name = "iron-plate", count = 60, target_ref = "source_chest_north_right"},
				{name = "iron-plate", count = 60, target_ref = "source_chest_south_left"},
				{name = "iron-plate", count = 60, target_ref = "source_chest_south_right"},
			},
			max_tick = 3000,
			outage = {
				off_tick = 400,
				on_tick = 600,
				assert_tick = 520,
				max_sink_during_outage = 280,
			},
		},
		make_transfer_scenario{
			id = "transfer_underground_multi_io_outage_restore_preserve",
			layout_id = "underground_splitter_line_multi_io",
			underground_item_transfer_mode = "preserve-full-state",
			researched_technologies = {"inserter-capacity-bonus-1"},
			item_stacks = {
				{name = "iron-plate", count = 60, target_ref = "source_chest_inline"},
				{name = "iron-plate", count = 60, target_ref = "source_chest_north_left"},
				{name = "iron-plate", count = 60, target_ref = "source_chest_north_right"},
				{name = "iron-plate", count = 60, target_ref = "source_chest_south_left"},
				{name = "iron-plate", count = 60, target_ref = "source_chest_south_right"},
			},
			max_tick = 3000,
			outage = {
				off_tick = 400,
				on_tick = 600,
				assert_tick = 520,
				max_sink_during_outage = 280,
			},
		},
		make_transfer_scenario{
			id = "transfer_underground_stateful_preserve",
			layout_id = "underground_splitter_line",
			underground_item_transfer_mode = "preserve-full-state",
			item_stacks = {
				{name = "power-armor", count = 1},
			},
			compare_stack_fingerprints = true,
			max_tick = 2200,
			outage = {
				off_tick = 200,
				on_tick = 360,
				assert_tick = 280,
				max_sink_during_outage = 1,
			},
			extra_actions = {
				{
					tick = 0,
					type = "insert_stateful_power_armor",
					target_ref = "source",
					armor_name = "power-armor",
					equipment_name = "battery-mk2-equipment",
					equipment_position = {0, 0},
					energy_fraction = 0.5,
				},
			},
		},
		make_transfer_scenario{
			id = "transfer_underground_stateful_name_only_negative",
			layout_id = "underground_splitter_line",
			underground_item_transfer_mode = "name-only",
			expect_transfer_incomplete = true,
			expected_failed_mod_disabled = 1,
			item_stacks = {
				{name = "power-armor", count = 1},
			},
			compare_stack_fingerprints = true,
			max_tick = 2200,
			outage = {
				off_tick = 200,
				on_tick = 360,
				assert_tick = 280,
				max_sink_during_outage = 1,
			},
			extra_actions = {
				{
					tick = 0,
					type = "insert_stateful_power_armor",
					target_ref = "source",
					armor_name = "power-armor",
					equipment_name = "battery-mk2-equipment",
					equipment_position = {0, 0},
					energy_fraction = 0.5,
				},
			},
			extra_checkpoints = {
				{
					tick = 2200,
					assertions = {
						{type = "item_conservation", source_ref = "source", sink_ref = "sink"},
					},
				},
			},
		},
		make_transfer_scenario{
			id = "transfer_underground_disabled_negative",
			layout_id = "underground_splitter_line",
			underground_item_transfer_mode = "disabled",
			expect_transfer_incomplete = true,
			expected_failed_mod_disabled = 2,
			item_stacks = {
				{name = "iron-plate", count = 60},
			},
			max_tick = 2200,
			outage = {
				max_sink_during_outage = 60,
			},
			extra_checkpoints = {
				{
					tick = 2200,
					assertions = {
						{type = "item_not_conserved", source_ref = "source", sink_ref = "sink"},
					},
				},
			},
		},
		make_planner_state_outage_scenario{
			id = "planner_deconstruction_outage_persistence",
			assertion_type = "entities_marked_for_deconstruction",
			include_ground_items = true,
			target_refs = {"input_belt_2", "underground_input", "underground_output", "line_splitter"},
			mark_action = {
				type = "order_deconstruction",
				target_refs = {"input_belt_2", "underground_input", "underground_output", "line_splitter"},
			},
			extra_actions = {
				{
					tick = 640,
					type = "cancel_deconstruction",
					target_refs = {"input_belt_2", "underground_input", "underground_output", "line_splitter"},
				},
			},
		},
		make_planner_state_outage_scenario{
			id = "planner_upgrade_outage_persistence",
			assertion_type = "entities_marked_for_upgrade",
			include_ground_items = true,
			target_refs = {"input_belt_2", "underground_input", "underground_output", "line_splitter"},
			expected_targets = {
				input_belt_2 = "fast-transport-belt",
				underground_input = "fast-underground-belt",
				underground_output = "fast-underground-belt",
				line_splitter = "fast-splitter",
			},
			mark_action = {
				type = "order_upgrade",
				orders = {
					{target_ref = "input_belt_2", target_name = "fast-transport-belt"},
					{target_ref = "underground_input", target_name = "fast-underground-belt"},
					{target_ref = "underground_output", target_name = "fast-underground-belt"},
					{target_ref = "line_splitter", target_name = "fast-splitter"},
				},
			},
		},

		{
			id = "planner_blueprint_build_and_force_build",
			layout_id = "underground_splitter_line",
			inserter_name = "burner-inserter",
			max_tick = 2400,
			settings_overrides = {
				underground_item_transfer_mode = "preserve-full-state",
				operations_per_tick = 128,
			},
			actions = {
				{
					tick = 0,
					type = "fill_inventory",
					target_ref = "source",
					stacks = {
						{name = "iron-plate", count = 20},
					},
				},
				{tick = 0, type = "fuel_burner_inserters", count = 50},

				{
					tick = 120,
					type = "build_blueprint",
					position = {x = 6.5, y = 1.5},
					force_build = false,
				},
				{
					tick = 160,
					type = "build_blueprint",
					position = {x = 3.5, y = 0.5},
					force_build = false,
				},
				{
					tick = 200,
					type = "build_blueprint",
					position = {x = 8.5, y = 0.5},
					force_build = true,
				},
				{
					tick = 280,
					type = "mine_marked_entities",
					target_refs = {"underground_output", "belt_before_splitter_1", },
				},
				{
					tick = 320,
					type = "revive_ghosts",
					ghosts = {
						{name = "underground-belt", position = {x = 9.5, y = 0.5}},
					},
				},

			},
			checkpoints = {
				{
					tick = 260,
					assertions = {
						{
							type = "blueprint_build_result",
							expected_ghosts = {
								{name = "small-electric-pole", position = {x = 8.5, y = 0.5}},
								{name = "underground-belt", position = {x = 9.5, y = 0.5}},
							},
							expected_deconstruction_marked = {
								{name = "transport-belt", position = {x = 9.5, y = 0.5}},
								{name = "underground-belt", position = {x = 8.5, y = 0.5}},
							},
							expected_not_deconstruction_marked = {
								{name = "transport-belt", position = {x = 3.5, y = 0.5}},
							},
						},
					},
				},
				{
					tick = 500,
					assertions = {
						{
							type = "blueprint_build_result",
							expected_missing_ghosts = {
								{name = "underground-belt", position = {x = 8.5, y = 0.5}},
							},
							expected_not_deconstruction_marked = {
								{name = "underground-belt", position = {x = 9.5, y = 0.5}},
							},
						},
					},
				},
				{
					tick = 2400,
					assertions = {
						{
							type = "transfer_complete",
							source_ref = "source",
							sink_ref = "sink",
							expected_contents = {
								{name = "iron-plate", count = 20},
							},
							source_should_be_empty = true,
						},
						{type = "structural_consistency"},
					},
				},
			},
		},
		make_multi_io_planner_blueprint_flicker_scenario(),
				{
			id = "aai_lubricated_no_lubricant_after_powerup",
			layout_id = "aai_loader_line",
			required_mods = {"aai-loaders"},
			required_aai_loader_mode = "lubricated",
			max_tick = 900,
			settings_overrides = {
				underground_item_transfer_mode = "preserve-full-state",
				operations_per_tick = 128,
			},
			actions = {
				{tick = 0, type = "fill_inventory", target_ref = "source", stacks = {{name = "iron-plate", count = 40}}},
				{tick = 0, type = "set_surface_daylight", mode = "midnight"},
				{tick = 180, type = "set_surface_daylight", mode = "full-day"},
			},
			checkpoints = {
				{
					tick = 460,
					assertions = {
						{type = "loader_active_state", target_refs = {"loader_out", "loader_in"}, expected_active = false},
						{type = "aai_pipe_count", loader_refs = {"loader_out", "loader_in"}, expected_count = 1},
						{type = "structural_consistency"},
					},
				},
				{
					tick = 900,
					assertions = {
						{type = "sink_count_less_than", sink_ref = "sink", item_name = "iron-plate", max_count = 0},
						{type = "loader_active_state", target_refs = {"loader_out", "loader_in"}, expected_active = false},
						{type = "structural_consistency"},
					},
				},
			},
		},
		{
			id = "aai_lubricated_power_cycle_fluid_continuity",
			layout_id = "aai_loader_line",
			required_mods = {"aai-loaders"},
			required_aai_loader_mode = "lubricated",
			max_tick = 1000,
			settings_overrides = {
				underground_item_transfer_mode = "preserve-full-state",
				operations_per_tick = 128,
			},
			actions = {
				{tick = 0, type = "fill_inventory", target_ref = "source", stacks = {{name = "iron-plate", count = 80}}},
				{tick = 0, type = "set_loader_pipe_fluid", target_ref = "loader_all", fluid_name = "lubricant", amount = 30},
				{tick = 300, type = "set_surface_daylight", mode = "midnight"},
				{tick = 400, type = "set_surface_daylight", mode = "full-day"},
			},
			checkpoints = {
				{
					tick = 280,
					assertions = {
						{type = "loader_active_state", target_refs = {"loader_out", "loader_in"}, expected_active = true},
						{type = "aai_pipe_count", loader_refs = {"loader_out", "loader_in"}, expected_count = 1},
						{type = "aai_pipe_fluid", loader_refs = {"loader_out", "loader_in"}, fluid_name = "lubricant", min_amount = 0.1},
						{type = "structural_consistency"},
					},
				},
				{
					tick = 260,
					assertions = {
						{type = "sink_count_less_than", sink_ref = "sink", item_name = "iron-plate", max_count = 79},
						{type = "structural_consistency"},
					},
				},
				{
					tick = 680,
					assertions = {
						{type = "loader_active_state", target_refs = {"loader_out", "loader_in"}, expected_active = true},
						{type = "aai_pipe_count", loader_refs = {"loader_out", "loader_in"}, expected_count = 1},
						{type = "aai_pipe_fluid", loader_refs = {"loader_out", "loader_in"}, fluid_name = "lubricant", min_amount = 0.1},
						{type = "structural_consistency"},
					},
				},
				{
					tick = 1000,
					assertions = {
						{
							type = "transfer_complete",
							source_ref = "source",
							sink_ref = "sink",
							expected_contents = {{name = "iron-plate", count = 80}},
							source_should_be_empty = true,
						},
						{type = "structural_consistency"},
					},
				},
			},
		},
		{
			id = "aai_lubricated_adjacent_repeated_power_cycles",
			layout_id = "aai_loader_dual_line_adjacent",
			required_mods = {"aai-loaders"},
			required_aai_loader_mode = "lubricated",
			max_tick = 1300,
			settings_overrides = {
				underground_item_transfer_mode = "preserve-full-state",
				operations_per_tick = 128,
			},
			actions = {
				{
					tick = 0,
					type = "fill_inventory",
					target_ref = "source",
					stacks = {
						{name = "iron-plate", count = 80, target_ref = "source_top"},
						{name = "iron-plate", count = 80, target_ref = "source_bottom"},
					},
				},
				{tick = 0, type = "set_loader_pipe_fluid", target_ref = "loader_all", fluid_name = "lubricant", amount = 40},
				{tick = 160, type = "set_surface_daylight", mode = "midnight"},
				{tick = 240, type = "set_surface_daylight", mode = "full-day"},
				{tick = 320, type = "set_surface_daylight", mode = "midnight"},
				{tick = 400, type = "set_surface_daylight", mode = "full-day"},
				{tick = 480, type = "set_surface_daylight", mode = "midnight"},
				{tick = 560, type = "set_surface_daylight", mode = "full-day"},
				{tick = 640, type = "set_surface_daylight", mode = "midnight"},
				{tick = 720, type = "set_surface_daylight", mode = "full-day"},
			},
			checkpoints = {
				{
					tick = 1000,
					assertions = {
						{type = "loader_active_state", target_refs = {"loader_out", "loader_in"}, expected_active = true},
						{type = "aai_pipe_count", loader_ref = "loader_all", expected_count = 1},
						{type = "structural_consistency"},
					},
				},
				{
					tick = 1300,
					assertions = {
						{
							type = "transfer_complete",
							source_ref = "source",
							sink_ref = "sink",
							expected_contents = {{name = "iron-plate", count = 160}},
							source_should_be_empty = true,
						},
						{type = "structural_consistency"},
					},
				},
			},
		},
		{
			id = "aai_expensive_power_only_gate",
			layout_id = "aai_loader_line",
			required_mods = {"aai-loaders"},
			required_aai_loader_mode = "expensive",
			max_tick = 900,
			settings_overrides = {
				underground_item_transfer_mode = "preserve-full-state",
				operations_per_tick = 128,
			},
			actions = {
				{tick = 0, type = "fill_inventory", target_ref = "source", stacks = {{name = "iron-plate", count = 60}}},
				{tick = 160, type = "set_surface_daylight", mode = "midnight"},
				{tick = 320, type = "set_surface_daylight", mode = "full-day"},
			},
			checkpoints = {
				{
					tick = 260,
					assertions = {
						{type = "sink_count_less_than", sink_ref = "sink", item_name = "iron-plate", max_count = 59},
						{type = "structural_consistency"},
					},
				},
				{
					tick = 600,
					assertions = {
						{type = "loader_active_state", target_refs = {"loader_out", "loader_in"}, expected_active = true},
						{type = "structural_consistency"},
					},
				},
				{
					tick = 900,
					assertions = {
						{
							type = "transfer_complete",
							source_ref = "source",
							sink_ref = "sink",
							expected_contents = {{name = "iron-plate", count = 60}},
							source_should_be_empty = true,
						},
						{type = "structural_consistency"},
					},
				},
			},
		},
		{
			id = "scan_recovery_smoke",
			layout_id = "straight_line",
			inserter_name = "bulk-inserter",
			max_tick = 900,
			settings_overrides = {
				underground_item_transfer_mode = "preserve-full-state",
				operations_per_tick = 128,
			},
			actions = {
				{tick = 0, type = "fill_inventory", target_ref = "source", stacks = {{name = "iron-ore", count = 20}}},
				{tick = 120, type = "run_full_scan"},
			},
			checkpoints = {
				{tick = 160, assertions = {{type = "structural_consistency"}}},
				{
					tick = 900,
					assertions = {
						{
							type = "transfer_complete",
							source_ref = "source",
							sink_ref = "sink",
							expected_contents = {{name = "iron-ore", count = 20}},
							source_should_be_empty = true,
						},
					},
				},
			},
		},
	}
end

function scenarios.get_all()
	return default_scenarios()
end

function scenarios.find_by_id(id)
	for _, scenario in pairs(default_scenarios()) do
		if scenario.id == id then
			return scenario
		end
	end
	return nil
end

return scenarios
