local world = require("lib.world")

local M = {}

local function make_assertion_result(checkpoint_tick, assertion, passed, message, extra)
	return {
		checkpoint_tick = checkpoint_tick,
		type = assertion.type,
		passed = passed,
		message = message or "",
		extra = extra,
	}
end

local function evaluate_transfer(active, assertion)
	local source_inventories = world.get_referenced_inventories(active, assertion.source_ref)
	local sink_inventories = world.get_referenced_inventories(active, assertion.sink_ref)
	if #source_inventories == 0 or #sink_inventories == 0 then
		return false, "Missing transfer inventories", nil
	end
	local expected = world.stack_list_to_map(assertion.expected_contents)
	local sink_contents_raw = world.aggregate_inventory_contents(sink_inventories)
	local sink_contents = world.contents_to_name_count_map(sink_contents_raw)
	local passed = world.maps_equal(expected, sink_contents)
	local message = "Sink contents match expected"
	if not passed then
		message = "Sink contents mismatch"
	end
	if assertion.source_should_be_empty then
		local source_total = world.aggregate_inventory_total_count(source_inventories)
		if source_total > 0 then
			passed = false
			message = message .. "; source not empty"
		end
	end
	if assertion.compare_stack_fingerprints then
		local sink_fingerprint = world.aggregate_inventory_fingerprint(sink_inventories)
		if not world.maps_equal(active.source_baseline_fingerprint or {}, sink_fingerprint) then
			passed = false
			message = message .. "; stack fingerprints differ"
		end
	end
	return passed, message, {
		expected = expected,
		sink = sink_contents,
		sink_raw = sink_contents_raw,
	}
end

local function evaluate_item_conservation(active, assertion)
	local source_inventories = world.get_referenced_inventories(active, assertion.source_ref)
	local sink_inventories = world.get_referenced_inventories(active, assertion.sink_ref)
	if #source_inventories == 0 or #sink_inventories == 0 then
		return false, "Missing transfer inventories", nil
	end

	local source_count = world.aggregate_inventory_total_count(source_inventories)
	local sink_count = world.aggregate_inventory_total_count(sink_inventories)
	local expected_total = 0
	for _, stack in pairs(active.expected_contents or {}) do
		expected_total = expected_total + (stack.count or 0)
	end

	local remaining_total = source_count + sink_count
	local delta = remaining_total - expected_total
	local extra = {
		expected_total = expected_total,
		remaining_total = remaining_total,
		delta = delta,
	}

	if assertion.type == "item_not_conserved" then
		return delta ~= 0, "item delta=" .. delta, extra
	end
	return delta == 0, "item delta=" .. delta, extra
end

function M.run(active, checkpoint_tick, assertion, call_main_mod)
	if assertion.type == "structural_consistency" then
		local snapshot = call_main_mod("get_state_snapshot", active.surface.index)
		if snapshot == nil or snapshot.totals == nil then
			if active.main_mod_available == false then
				return make_assertion_result(checkpoint_tick, assertion, true, "Skipped: main mod disabled")
			end
			return make_assertion_result(checkpoint_tick, assertion, false, "Missing state snapshot")
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
			return make_assertion_result(checkpoint_tick, assertion, false, table.concat(failing, ", "), snapshot.totals)
		end
		return make_assertion_result(checkpoint_tick, assertion, true, "State is consistent", snapshot.totals)
	end

	if assertion.type == "transfer_complete" then
		local passed, message, extra = evaluate_transfer(active, assertion)
		return make_assertion_result(checkpoint_tick, assertion, passed, message, extra)
	end

	if assertion.type == "transfer_not_complete" then
		local transfer_passed, _, transfer_extra = evaluate_transfer(active, assertion)
		if transfer_passed then
			return make_assertion_result(checkpoint_tick, assertion, false, "Transfer unexpectedly completed", transfer_extra)
		end
		return make_assertion_result(checkpoint_tick, assertion, true, "Transfer incomplete as expected", transfer_extra)
	end

	if assertion.type == "sink_count_less_than" then
		local sink_inventories = world.get_referenced_inventories(active, assertion.sink_ref)
		if #sink_inventories == 0 then
			return make_assertion_result(checkpoint_tick, assertion, false, "Missing sink inventory")
		end
		local count = world.aggregate_inventory_total_count(sink_inventories, assertion.item_name)
		local max_count = assertion.max_count or 0
		local passed = count <= max_count
		return make_assertion_result(checkpoint_tick, assertion, passed, "sink=" .. count .. ", max=" .. max_count, {
			item_name = assertion.item_name,
			sink_count = count,
			max_count = max_count,
		})
	end

	if assertion.type == "item_conservation" or assertion.type == "item_not_conserved" then
		local passed, message, extra = evaluate_item_conservation(active, assertion)
		return make_assertion_result(checkpoint_tick, assertion, passed, message, extra)
	end

	return make_assertion_result(checkpoint_tick, assertion, false, "Unknown assertion type: " .. tostring(assertion.type))
end

return M
