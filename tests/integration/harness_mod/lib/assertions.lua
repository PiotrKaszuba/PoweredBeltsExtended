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
	local ground_contents = {}
	if assertion.include_ground_items then
		local ground_item_names = assertion.ground_item_names
		if type(ground_item_names) ~= "table" then
			ground_item_names = {}
			for item_name, _ in pairs(expected) do
				ground_item_names[#ground_item_names + 1] = item_name
			end
		end
		local ground_area = assertion.ground_items_area
		if ground_area == nil and active.layout and active.layout.area then
			ground_area = active.layout.area
		end
		ground_contents = world.aggregate_ground_item_contents(active.surface, ground_area, ground_item_names)
		for item_name, count in pairs(ground_contents) do
			sink_contents[item_name] = (sink_contents[item_name] or 0) + count
		end
	end
	if assertion.include_mine_inventory then
		local mine_inventory = active.inventory
		local mine_contents = world.aggregate_inventory_contents(mine_inventory)
		for item_name, count in pairs(mine_contents) do
			sink_contents[item_name] = (sink_contents[item_name] or 0) + count
		end
	end

	-- Compare only expected item names by default; unrelated mined/extra item
	-- types should not fail transfer assertions.
	local compared_sink = {}
	for item_name, expected_count in pairs(expected) do
		local actual_count = sink_contents[item_name] or 0
		if assertion.allow_expected_item_overflow == true then
			compared_sink[item_name] = math.max(actual_count, expected_count)
		else
			compared_sink[item_name] = actual_count
		end
	end

	local passed = world.maps_equal(expected, compared_sink)
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
		compared_sink = compared_sink,
		sink = sink_contents,
		sink_raw = sink_contents_raw,
		ground = ground_contents,
		allow_expected_item_overflow = assertion.allow_expected_item_overflow == true,
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

local function collect_target_references(assertion)
	local refs = {}
	if type(assertion.target_ref) == "string" and assertion.target_ref ~= "" then
		refs[#refs + 1] = assertion.target_ref
	end
	if type(assertion.target_refs) == "table" then
		for _, ref in pairs(assertion.target_refs) do
			if type(ref) == "string" and ref ~= "" then
				refs[#refs + 1] = ref
			end
		end
	end
	return refs
end

local function evaluate_entity_planner_marks(active, assertion, mark_type)
	local refs = collect_target_references(assertion)
	if #refs == 0 then
		return false, "No target references provided", nil
	end

	local failures = {}
	local extra = {entities = {}}
	for _, reference_name in pairs(refs) do
		local entities = world.get_referenced_entities(active, reference_name)
		if #entities == 0 then
			failures[#failures + 1] = reference_name .. ":missing"
		end
		for idx, entity in ipairs(entities) do
			local state = world.get_planner_state(entity)
			local key = reference_name .. "#" .. idx
			extra.entities[key] = state
			if not state.valid then
				failures[#failures + 1] = key .. ":invalid"
			elseif mark_type == "deconstruction" and not state.deconstruction_marked then
				failures[#failures + 1] = key .. ":not-deconstruction-marked"
			elseif mark_type == "upgrade" and not state.upgrade_marked then
				failures[#failures + 1] = key .. ":not-upgrade-marked"
			end
		end
	end

	if #failures > 0 then
		return false, table.concat(failures, ", "), extra
	end

	return true, "All entities keep planner marks", extra
end

local function evaluate_upgrade_targets(active, assertion)
	local expected_targets = assertion.expected_targets
	if type(expected_targets) ~= "table" then
		return true, "No explicit upgrade target expectations", {expected_targets = nil}
	end

	local failures = {}
	local extra = {entities = {}}
	for reference_name, expected_target in pairs(expected_targets) do
		local entities = world.get_referenced_entities(active, reference_name)
		if #entities == 0 then
			failures[#failures + 1] = reference_name .. ":missing"
		end
		for idx, entity in ipairs(entities) do
			local state = world.get_planner_state(entity)
			local key = reference_name .. "#" .. idx
			extra.entities[key] = state
			if state.valid then
				local actual_target = world.base_powered_name(state.upgrade_target_name)
				local expected_base = world.base_powered_name(expected_target)
				if actual_target ~= expected_base then
					failures[#failures + 1] = key .. ":target-mismatch(" .. tostring(actual_target) .. "!=" .. tostring(expected_base) .. ")"
				end
			else
				failures[#failures + 1] = key .. ":invalid"
			end
		end
	end

	if #failures > 0 then
		return false, table.concat(failures, ", "), extra
	end
	return true, "Upgrade targets match expected", extra
end

local function positions_equal(a, b)
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	return a.x == b.x and a.y == b.y
end

local function find_entities_at_position(surface, position)
	if not (surface and surface.valid and type(position) == "table") then
		return {}
	end
	return surface.find_entities_filtered{position = position, radius = 0.2} or {}
end

local function evaluate_blueprint_result(active, assertion)
	local failures = {}
	local extra = {ghosts = {}, marks = {}}

	for _, expected_ghost in pairs(assertion.expected_ghosts or {}) do
		local entities = find_entities_at_position(active.surface, expected_ghost.position)
		local found = false
		for _, entity in pairs(entities) do
			if entity and entity.valid and entity.name == "entity-ghost" then
				local ghost_name = entity.ghost_name
				extra.ghosts[#extra.ghosts + 1] = {
					position = entity.position,
					name = ghost_name,
				}
				if ghost_name == expected_ghost.name and positions_equal(entity.position, expected_ghost.position) then
					found = true
				end
			end
		end
		if not found then
			failures[#failures + 1] = string.format(
				"missing-ghost(%s@%.1f,%.1f)",
				tostring(expected_ghost.name),
				expected_ghost.position.x,
				expected_ghost.position.y
			)
		end
	end

	for _, expected_missing_ghost in pairs(assertion.expected_missing_ghosts or {}) do
		local entities = find_entities_at_position(active.surface, expected_missing_ghost.position)
		for _, entity in pairs(entities) do
			if entity and entity.valid and entity.name == "entity-ghost" and entity.ghost_name == expected_missing_ghost.name then
				failures[#failures + 1] = string.format(
					"unexpected-ghost(%s@%.1f,%.1f)",
					tostring(expected_missing_ghost.name),
					expected_missing_ghost.position.x,
					expected_missing_ghost.position.y
				)
				break
			end
		end
	end

	local function verify_mark(expect_marked, entries)
		for _, expected in pairs(entries or {}) do
			local entities = find_entities_at_position(active.surface, expected.position)
			local matched = false
			for _, entity in pairs(entities) do
				if entity and entity.valid and entity.name ~= "entity-ghost" and (expected.name == nil or entity.name == expected.name) then
					local marked = false
					pcall(function()
						marked = entity.to_be_deconstructed(entity.force) == true
					end)
					extra.marks[#extra.marks + 1] = {
						position = entity.position,
						name = entity.name,
						marked = marked,
					}
					if marked == expect_marked then
						matched = true
					end
				end
			end
			if not matched then
				local descriptor = expect_marked and "missing-marked" or "unexpected-marked"
				failures[#failures + 1] = string.format(
					"%s(%s@%.1f,%.1f)",
					descriptor,
					tostring(expected.name or "any"),
					expected.position.x,
					expected.position.y
				)
			end
		end
	end

	verify_mark(true, assertion.expected_deconstruction_marked)
	verify_mark(false, assertion.expected_not_deconstruction_marked)

	if #failures > 0 then
		return false, table.concat(failures, ", "), extra
	end
	return true, "Blueprint state matches expectations", extra
end

local function read_entity_active(entity)
	if not (entity and entity.valid) then
		return nil
	end
	local ok, active = pcall(function()
		return entity.active
	end)
	if not ok then
		return nil
	end
	return active == true
end

local function evaluate_loader_active_state(active, assertion)
	local refs = collect_target_references(assertion)
	if #refs == 0 then
		return false, "No target references provided", nil
	end

	local expected_active = assertion.expected_active ~= false
	local failures = {}
	local extra = {entities = {}}

	for _, reference_name in pairs(refs) do
		local entities = world.get_referenced_entities(active, reference_name)
		if #entities == 0 then
			failures[#failures + 1] = reference_name .. ":missing"
		end
		for idx, entity in ipairs(entities) do
			local key = reference_name .. "#" .. idx
			local actual_active = read_entity_active(entity)
			extra.entities[key] = {
				valid = entity and entity.valid == true,
				name = entity and entity.name or nil,
				active = actual_active,
			}
			if actual_active == nil then
				failures[#failures + 1] = key .. ":invalid"
			elseif actual_active ~= expected_active then
				failures[#failures + 1] = key .. ":active-mismatch(" .. tostring(actual_active) .. "!=" .. tostring(expected_active) .. ")"
			end
		end
	end

	if #failures > 0 then
		return false, table.concat(failures, ", "), extra
	end
	return true, "Loader active state matches expected", extra
end

local function collect_loader_refs(assertion)
	local refs = {}
	if type(assertion.loader_ref) == "string" and assertion.loader_ref ~= "" then
		refs[#refs + 1] = assertion.loader_ref
	end
	if type(assertion.loader_refs) == "table" then
		for _, ref in pairs(assertion.loader_refs) do
			if type(ref) == "string" and ref ~= "" then
				refs[#refs + 1] = ref
			end
		end
	end
	if #refs == 0 then
		refs = collect_target_references(assertion)
	end
	return refs
end

local function find_aai_pipe_entities(surface, pipe_name, position, radius, force_name)
	if not (surface and surface.valid and type(pipe_name) == "string" and pipe_name ~= "" and type(position) == "table") then
		return {}
	end
	local query = {
		name = pipe_name,
		position = position,
		radius = radius,
	}
	local entities = surface.find_entities_filtered(query) or {}
	local matches = {}
	for _, entity in pairs(entities) do
		if entity and entity.valid and (force_name == nil or (entity.force and entity.force.name == force_name)) then
			matches[#matches + 1] = entity
		end
	end
	return matches
end

local function resolve_pipe_state_for_loaders(active, assertion)
	local loader_refs = collect_loader_refs(assertion)
	if #loader_refs == 0 then
		return nil, "No loader references provided"
	end

	local radius = assertion.radius or 0.12
	local x_offset = assertion.pipe_x_offset or 0
	local y_offset = assertion.pipe_y_offset or (1 / 32)
	local require_force_match = assertion.match_force ~= false

	local resolved = {}
	local failures = {}
	for _, reference_name in pairs(loader_refs) do
		local loaders = world.get_referenced_entities(active, reference_name)
		if #loaders == 0 then
			failures[#failures + 1] = reference_name .. ":missing"
		end
		for idx, loader in ipairs(loaders) do
			local key = reference_name .. "#" .. idx
			if not (loader and loader.valid and loader.surface and loader.surface.valid) then
				failures[#failures + 1] = key .. ":invalid"
			else
				local pipe_name = assertion.pipe_name or (world.base_powered_name(loader.name) .. "-pipe")
				local pipe_position = {
					x = loader.position.x + x_offset,
					y = loader.position.y + y_offset,
				}
				local force_name = nil
				if require_force_match and loader.force and loader.force.name ~= nil then
					force_name = loader.force.name
				end
				local pipes = find_aai_pipe_entities(loader.surface, pipe_name, pipe_position, radius, force_name)
				resolved[#resolved + 1] = {
					key = key,
					loader = loader,
					pipe_name = pipe_name,
					position = pipe_position,
					pipes = pipes,
				}
			end
		end
	end

	if #failures > 0 then
		return nil, table.concat(failures, ", ")
	end
	return resolved, nil
end

local function evaluate_aai_pipe_count(active, assertion)
	local expected_count = assertion.expected_count
	if type(expected_count) ~= "number" then
		expected_count = 1
	end
	expected_count = math.max(0, math.floor(expected_count))

	local resolved, err = resolve_pipe_state_for_loaders(active, assertion)
	if resolved == nil then
		return false, err, nil
	end

	local failures = {}
	local extra = {pipes = {}}
	for _, entry in ipairs(resolved) do
		local count = #entry.pipes
		extra.pipes[entry.key] = {
			count = count,
			pipe_name = entry.pipe_name,
			position = entry.position,
		}
		if count ~= expected_count then
			failures[#failures + 1] = entry.key .. ":count-mismatch(" .. tostring(count) .. "!=" .. tostring(expected_count) .. ")"
		end
	end

	if #failures > 0 then
		return false, table.concat(failures, ", "), extra
	end
	return true, "AAI helper pipe count matches expected", extra
end

local function evaluate_aai_pipe_fluid(active, assertion)
	local resolved, err = resolve_pipe_state_for_loaders(active, assertion)
	if resolved == nil then
		return false, err, nil
	end

	local min_amount = assertion.min_amount
	if type(min_amount) ~= "number" then
		min_amount = 0
	end
	local max_amount = assertion.max_amount
	if type(max_amount) ~= "number" then
		max_amount = nil
	end
	local expected_fluid_name = assertion.fluid_name
	if type(expected_fluid_name) ~= "string" or expected_fluid_name == "" then
		expected_fluid_name = nil
	end

	local failures = {}
	local extra = {pipes = {}}
	for _, entry in ipairs(resolved) do
		local pipe = entry.pipes[1]
		if pipe == nil then
			failures[#failures + 1] = entry.key .. ":missing-pipe"
			extra.pipes[entry.key] = {
				pipe_name = entry.pipe_name,
				position = entry.position,
				fluid_name = nil,
				amount = 0,
			}
		else
			local fluid = pipe.get_fluid(1)
			local amount = 0
			local fluid_name = nil
			if fluid ~= nil then
				amount = fluid.amount or 0
				fluid_name = fluid.name
			end
			extra.pipes[entry.key] = {
				pipe_name = entry.pipe_name,
				position = entry.position,
				fluid_name = fluid_name,
				amount = amount,
			}

			if expected_fluid_name ~= nil and fluid_name ~= expected_fluid_name then
				failures[#failures + 1] = entry.key .. ":fluid-name-mismatch(" .. tostring(fluid_name) .. "!=" .. tostring(expected_fluid_name) .. ")"
			end
			if amount + 0.0001 < min_amount then
				failures[#failures + 1] = entry.key .. ":amount-below-min(" .. tostring(amount) .. "<" .. tostring(min_amount) .. ")"
			end
			if max_amount ~= nil and amount - 0.0001 > max_amount then
				failures[#failures + 1] = entry.key .. ":amount-above-max(" .. tostring(amount) .. ">" .. tostring(max_amount) .. ")"
			end
		end
	end

	if #failures > 0 then
		return false, table.concat(failures, ", "), extra
	end
	return true, "AAI helper pipe fluid matches expected", extra
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

	if assertion.type == "entities_marked_for_deconstruction" then
		local passed, message, extra = evaluate_entity_planner_marks(active, assertion, "deconstruction")
		return make_assertion_result(checkpoint_tick, assertion, passed, message, extra)
	end

	if assertion.type == "entities_marked_for_upgrade" then
		local marks_ok, marks_message, marks_extra = evaluate_entity_planner_marks(active, assertion, "upgrade")
		local targets_ok, targets_message, targets_extra = evaluate_upgrade_targets(active, assertion)
		local passed = marks_ok and targets_ok
		local message = marks_message
		if not targets_ok then
			message = message .. "; " .. targets_message
		end
		local extra = {
			marks = marks_extra,
			targets = targets_extra,
		}
		return make_assertion_result(checkpoint_tick, assertion, passed, message, extra)
	end

	if assertion.type == "blueprint_build_result" then
		local passed, message, extra = evaluate_blueprint_result(active, assertion)
		return make_assertion_result(checkpoint_tick, assertion, passed, message, extra)
	end

	if assertion.type == "loader_active_state" then
		local passed, message, extra = evaluate_loader_active_state(active, assertion)
		return make_assertion_result(checkpoint_tick, assertion, passed, message, extra)
	end

	if assertion.type == "aai_pipe_count" then
		local passed, message, extra = evaluate_aai_pipe_count(active, assertion)
		return make_assertion_result(checkpoint_tick, assertion, passed, message, extra)
	end

	if assertion.type == "aai_pipe_fluid" then
		local passed, message, extra = evaluate_aai_pipe_fluid(active, assertion)
		return make_assertion_result(checkpoint_tick, assertion, passed, message, extra)
	end

	return make_assertion_result(checkpoint_tick, assertion, false, "Unknown assertion type: " .. tostring(assertion.type))
end

return M
