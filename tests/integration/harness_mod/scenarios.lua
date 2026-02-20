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
			tick = base.outage.off_tick or 80,
			type = "set_surface_daylight",
			mode = "midnight",
		}
		scenario.actions[#scenario.actions + 1] = {
			tick = base.outage.on_tick or 240,
			type = "set_surface_daylight",
			mode = "full-day",
		}
		scenario.checkpoints[#scenario.checkpoints + 1] = {
			tick = base.outage.assert_tick or 180,
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
				off_tick = 120,
				on_tick = 420,
				assert_tick = 300,
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
				off_tick = 120,
				on_tick = 420,
				assert_tick = 300,
				max_sink_during_outage = 58,
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
				off_tick = 180,
				on_tick = 480,
				assert_tick = 300,
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
				off_tick = 180,
				on_tick = 480,
				assert_tick = 300,
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
				off_tick = 120,
				on_tick = 420,
				assert_tick = 300,
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
