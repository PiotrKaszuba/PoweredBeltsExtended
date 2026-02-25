local utils = require("modules.utils")
local entities = require("modules.entities")

local stats = {}

local function push_snapshot_detail(collection, value, max_entries)
	if #collection < max_entries then
		collection[#collection + 1] = value
	end
end

local function get_surface_state_snapshot(surface, max_details)
	local surface_key = utils.get_surface_key(surface)
	local entities_by_surface = storage.entities[surface_key] or {}
	local power_entities_by_surface = storage.power_entities[surface_key] or {}
	local world_entities = surface.find_entities_filtered{type = utils.belt_entity_type_list}
	local world_all_power_entities = surface.find_entities_filtered{type = "electric-energy-interface"}

	local world_entities_by_pos = {}
	local world_power_counts_by_pos = {}
	local world_power_by_pos = {}
	local world_power_entities = {}

	for _, entity in pairs(world_entities) do
		if entity and entity.valid then
			world_entities_by_pos[entities.get_entity_idx(entity)] = entity
		end
	end

	for _, power_entity in pairs(world_all_power_entities) do
		if power_entity and power_entity.valid and string.endswith(power_entity.name, "-power") then
			local pos = entities.get_entity_idx(power_entity)
			world_power_counts_by_pos[pos] = (world_power_counts_by_pos[pos] or 0) + 1
			if world_power_by_pos[pos] == nil then
				world_power_by_pos[pos] = power_entity
			end
			world_power_entities[#world_power_entities + 1] = power_entity
		end
	end

	local details = {
		missing_storage_entities = {},
		missing_storage_power_entities = {},
		missing_world_power_entities = {},
		duplicate_world_power_entities = {},
		invalid_storage_entities = {},
		invalid_storage_power_entities = {},
		stale_storage_entities = {},
		stale_storage_power_entities = {},
		orphan_world_power_entities = {},
		wrong_power_entity_name = {},
		wrong_power_entity_force = {},
	}

	local counts = {
		world_entities = 0,
		world_power_entities = #world_power_entities,
		storage_entities = 0,
		storage_power_entities = 0,
		missing_storage_entities = 0,
		missing_storage_power_entities = 0,
		missing_world_power_entities = 0,
		duplicate_world_power_entities = 0,
		invalid_storage_entities = 0,
		invalid_storage_power_entities = 0,
		stale_storage_entities = 0,
		stale_storage_power_entities = 0,
		orphan_world_power_entities = 0,
		wrong_power_entity_name = 0,
		wrong_power_entity_force = 0,
	}

	for pos, entity in pairs(world_entities_by_pos) do
		counts.world_entities = counts.world_entities + 1
		local stored_entity = entities_by_surface[pos]
		if stored_entity ~= entity then
			counts.missing_storage_entities = counts.missing_storage_entities + 1
			push_snapshot_detail(details.missing_storage_entities, pos, max_details)
		end

		local stored_power_entity = power_entities_by_surface[pos]
		if stored_power_entity == nil or (not stored_power_entity.valid) then
			counts.missing_storage_power_entities = counts.missing_storage_power_entities + 1
			push_snapshot_detail(details.missing_storage_power_entities, pos, max_details)
		end

		local world_power_count = world_power_counts_by_pos[pos] or 0
		if world_power_count == 0 then
			counts.missing_world_power_entities = counts.missing_world_power_entities + 1
			push_snapshot_detail(details.missing_world_power_entities, pos, max_details)
		elseif world_power_count > 1 then
			counts.duplicate_world_power_entities = counts.duplicate_world_power_entities + 1
			push_snapshot_detail(details.duplicate_world_power_entities, pos, max_details)
		end

		local world_power_entity = world_power_by_pos[pos]
		if world_power_entity ~= nil then
			local expected_name = entities.get_correct_power_entity_name(entities.extract_base_name_from_entity_to_power(entity.name), entity.force)
			if world_power_entity.name ~= expected_name then
				counts.wrong_power_entity_name = counts.wrong_power_entity_name + 1
				push_snapshot_detail(details.wrong_power_entity_name, {
					pos = pos,
					expected = expected_name,
					actual = world_power_entity.name,
				}, max_details)
			end
			if world_power_entity.force.name ~= entity.force.name then
				counts.wrong_power_entity_force = counts.wrong_power_entity_force + 1
				push_snapshot_detail(details.wrong_power_entity_force, {
					pos = pos,
					expected = entity.force.name,
					actual = world_power_entity.force.name,
				}, max_details)
			end
		end
	end

	for pos, stored_entity in pairs(entities_by_surface) do
		counts.storage_entities = counts.storage_entities + 1
		if stored_entity == nil or (not stored_entity.valid) then
			counts.invalid_storage_entities = counts.invalid_storage_entities + 1
			push_snapshot_detail(details.invalid_storage_entities, pos, max_details)
		elseif world_entities_by_pos[pos] ~= stored_entity then
			counts.stale_storage_entities = counts.stale_storage_entities + 1
			push_snapshot_detail(details.stale_storage_entities, pos, max_details)
		end
	end

	for pos, stored_power_entity in pairs(power_entities_by_surface) do
		counts.storage_power_entities = counts.storage_power_entities + 1
		if stored_power_entity == nil or (not stored_power_entity.valid) then
			counts.invalid_storage_power_entities = counts.invalid_storage_power_entities + 1
			push_snapshot_detail(details.invalid_storage_power_entities, pos, max_details)
		elseif world_power_by_pos[pos] ~= stored_power_entity then
			counts.stale_storage_power_entities = counts.stale_storage_power_entities + 1
			push_snapshot_detail(details.stale_storage_power_entities, pos, max_details)
		end
	end

	for pos, world_power_entity in pairs(world_power_by_pos) do
		if world_entities_by_pos[pos] == nil then
			counts.orphan_world_power_entities = counts.orphan_world_power_entities + 1
			push_snapshot_detail(details.orphan_world_power_entities, {
				pos = pos,
				name = world_power_entity.name
			}, max_details)
		end
	end

	return {
		surface_index = surface_key,
		counts = counts,
		details = details,
	}
end

function stats.get_state_snapshot(surface_index)
	local requested_surface = nil
	if surface_index ~= nil then
		requested_surface = game.surfaces[surface_index]
	end
	local max_details = 128
	local snapshot = {
		tick = game.tick,
		underground_item_transfer_mode = utils.get_effective_underground_transfer_mode(),
		required_energy_percentage_setting = utils.get_required_energy_percentage_setting(),
		operations_per_tick_setting = utils.get_operations_per_tick_setting(),
		surfaces = {},
		totals = {
			world_entities = 0,
			world_power_entities = 0,
			storage_entities = 0,
			storage_power_entities = 0,
			missing_storage_entities = 0,
			missing_storage_power_entities = 0,
			missing_world_power_entities = 0,
			duplicate_world_power_entities = 0,
			invalid_storage_entities = 0,
			invalid_storage_power_entities = 0,
			stale_storage_entities = 0,
			stale_storage_power_entities = 0,
			orphan_world_power_entities = 0,
			wrong_power_entity_name = 0,
			wrong_power_entity_force = 0,
		}
	}

	local function add_surface(surface)
		local surface_snapshot = get_surface_state_snapshot(surface, max_details)
		snapshot.surfaces[surface.index] = surface_snapshot
		for metric, value in pairs(surface_snapshot.counts) do
			snapshot.totals[metric] = (snapshot.totals[metric] or 0) + value
		end
	end

	if requested_surface ~= nil then
		add_surface(requested_surface)
	else
		for _, surface in pairs(game.surfaces) do
			add_surface(surface)
		end
	end
	return snapshot
end

return stats
