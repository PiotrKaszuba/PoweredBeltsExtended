local world = require("lib.world")

local M = {}

local function make_assertion_result(active, checkpoint_tick, assertion, passed, message, extra)
	local blocking = assertion.blocking
	if blocking == nil then
		blocking = active.scenario.blocking
	end
	local expected_failure = assertion.expected_failure == true
	return {
		checkpoint_tick = checkpoint_tick,
		type = assertion.type,
		blocking = blocking,
		passed = passed,
		expected_failure = expected_failure,
		message = message or "",
		extra = extra,
	}
end

function M.run(active, checkpoint_tick, assertion, call_main_mod)
	if assertion.type == "structural_consistency" then
		local snapshot = call_main_mod("get_state_snapshot", active.surface.index)
		if snapshot == nil or snapshot.totals == nil then
			if active.main_mod_available == false then
				return make_assertion_result(active, checkpoint_tick, assertion, true, "Skipped: main mod disabled")
			end
			return make_assertion_result(active, checkpoint_tick, assertion, false, "Missing state snapshot")
		end
		local totals = snapshot.totals
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
			local value = totals[metric] or 0
			if value > 0 then
				failing[#failing + 1] = metric .. "=" .. value
			end
		end
		if #failing > 0 then
			return make_assertion_result(active, checkpoint_tick, assertion, false, table.concat(failing, ", "), snapshot.totals)
		end
		return make_assertion_result(active, checkpoint_tick, assertion, true, "State is consistent", snapshot.totals)
	end

	if assertion.type == "transfer_complete" then
		local source = world.get_referenced_entity(active, assertion.source_ref)
		local sink = world.get_referenced_entity(active, assertion.sink_ref)
		local source_inventory = world.resolve_inventory(source)
		local sink_inventory = world.resolve_inventory(sink)
		if source_inventory == nil or sink_inventory == nil then
			return make_assertion_result(active, checkpoint_tick, assertion, false, "Missing transfer inventories")
		end
		local expected = world.stack_list_to_map(assertion.expected_contents)
		local sink_contents_raw = sink_inventory.get_contents()
		local sink_contents = world.contents_to_name_count_map(sink_contents_raw)
		local passed = world.maps_equal(expected, sink_contents)
		local message = "Sink contents match expected"
		if not passed then
			message = "Sink contents mismatch"
		end
		if assertion.source_should_be_empty then
			local source_total = source_inventory.get_item_count()
			if source_total > 0 then
				passed = false
				message = message .. "; source not empty"
			end
		end
		if assertion.compare_stack_fingerprints then
			local sink_fingerprint = world.inventory_fingerprint(sink_inventory)
			if not world.maps_equal(active.source_baseline_fingerprint or {}, sink_fingerprint) then
				passed = false
				message = message .. "; stack fingerprints differ"
			end
		end
		return make_assertion_result(active, checkpoint_tick, assertion, passed, message, {
			expected = expected,
			sink = sink_contents,
			sink_raw = sink_contents_raw,
		})
	end

	if assertion.type == "sink_count_less_than" then
		local sink = world.get_referenced_entity(active, assertion.sink_ref)
		local sink_inventory = world.resolve_inventory(sink)
		if sink_inventory == nil then
			return make_assertion_result(active, checkpoint_tick, assertion, false, "Missing sink inventory")
		end
		local count = sink_inventory.get_item_count(assertion.item_name)
		local max_count = assertion.max_count or 0
		local passed = count <= max_count
		return make_assertion_result(active, checkpoint_tick, assertion, passed, "sink=" .. count .. ", max=" .. max_count, {
			item_name = assertion.item_name,
			sink_count = count,
			max_count = max_count,
		})
	end

	if assertion.type == "canary_transfer_metrics" then
		local source = world.get_referenced_entity(active, assertion.source_ref)
		local sink = world.get_referenced_entity(active, assertion.sink_ref)
		local source_inventory = world.resolve_inventory(source)
		local sink_inventory = world.resolve_inventory(sink)
		local source_count = 0
		local sink_count = 0
		if source_inventory ~= nil then source_count = source_inventory.get_item_count() end
		if sink_inventory ~= nil then sink_count = sink_inventory.get_item_count() end
		local expected_total = 0
		for _, stack in pairs(active.expected_contents or {}) do
			expected_total = expected_total + (stack.count or 0)
		end
		local remaining_total = source_count + sink_count
		local delta = remaining_total - expected_total
		local passed = delta == 0
		return make_assertion_result(active, checkpoint_tick, assertion, passed, "canary delta=" .. delta, {
			expected_total = expected_total,
			remaining_total = remaining_total,
			delta = delta,
		})
	end

	return make_assertion_result(active, checkpoint_tick, assertion, false, "Unknown assertion type: " .. tostring(assertion.type))
end

return M
