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
			underground_item_transfer_mode = base.underground_item_transfer_mode or "name-only",
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
	local refs = base.target_refs or {"belt_2", "underground_input", "line_splitter"}
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
			underground_item_transfer_mode = base.underground_item_transfer_mode or "name-only",
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
			target_refs = {"belt_2", "underground_input", "underground_output", "line_splitter"},
			mark_action = {
				type = "order_deconstruction",
				target_refs = {"belt_2", "underground_input", "underground_output", "line_splitter"},
			},
			extra_actions = {
				{
					tick = 640,
					type = "cancel_deconstruction",
					target_refs = {"belt_2", "underground_input", "underground_output", "line_splitter"},
				},
			},
		},
		make_planner_state_outage_scenario{
			id = "planner_upgrade_outage_persistence",
			assertion_type = "entities_marked_for_upgrade",
			include_ground_items = true,
			target_refs = {"belt_2", "underground_input", "underground_output", "line_splitter"},
			expected_targets = {
				belt_2 = "fast-transport-belt",
				underground_input = "fast-underground-belt",
				underground_output = "fast-underground-belt",
				line_splitter = "fast-splitter",
			},
			mark_action = {
				type = "order_upgrade",
				orders = {
					{target_ref = "belt_2", target_name = "fast-transport-belt"},
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
			max_tick = 420,
			settings_overrides = {
				underground_item_transfer_mode = "name-only",
				operations_per_tick = 128,
			},
			actions = {
				{tick = 0, type = "fuel_burner_inserters", count = 50},
				{
					tick = 120,
					type = "build_blueprint",
					position = {x = 6.5, y = 2.5},
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
					position = {x = 9.5, y = 0.5},
					force_build = true,
				},
			},
			checkpoints = {
				{
					tick = 260,
					assertions = {
						{
							type = "blueprint_build_result",
							expected_ghosts = {
								{name = "small-electric-pole", position = {x = 6.5, y = 2.5}},
								{name = "small-electric-pole", position = {x = 9.5, y = 0.5}},
								{name = "underground-belt", position = {x = 8.5, y = 0.5}},
								{name = "underground-belt", position = {x = 10.5, y = 0.5}},
							},
							expected_missing_ghosts = {
								{name = "small-electric-pole", position = {x = 3.5, y = 0.5}},
							},
							expected_deconstruction_marked = {
								{name = "transport-belt", position = {x = 9.5, y = 0.5}},
								{name = "transport-belt", position = {x = 10.5, y = 0.5}},
								{name = "underground-belt", position = {x = 8.5, y = 0.5}},
							},
							expected_not_deconstruction_marked = {
								{name = "transport-belt", position = {x = 3.5, y = 0.5}},
							},
						},
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
				underground_item_transfer_mode = "name-only",
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
