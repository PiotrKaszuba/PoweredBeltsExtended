local utils = require("modules.utils")
local entities = require("modules.entities")
local stats = require("modules.stats")

local scans = {}

function scans.find_all_entities_powered()
	game.print("[PBE] Checking all entities to be powered..")

	local num_wrongly_present_and_valid = 0
	local num_wrongly_present = 0
	local num_nil = 0
	local num_entity_invalid = 0
	local num_init = 0
	local num_stale_entries = 0

	for _, surface in pairs(game.surfaces) do
		local surface_key = utils.get_surface_key(surface)
		local world_entities = surface.find_entities_filtered{type = utils.belt_entity_type_list}
		local seen_positions = {}
		for _, v in pairs(world_entities) do
			if v.valid then
				local pos = entities.get_entity_idx(v)
				seen_positions[pos] = true
				local entities_by_surface = storage.entities[surface_key]
				local power_entities_by_surface = storage.power_entities[surface_key]
				local stored_entity = nil
				if entities_by_surface ~= nil then
					stored_entity = entities_by_surface[pos]
				end
				if stored_entity ~= v then
					if stored_entity == nil then
						num_nil = num_nil + 1
					elseif stored_entity.valid then
						num_wrongly_present_and_valid = num_wrongly_present_and_valid + 1
					else
						num_wrongly_present = num_wrongly_present + 1
					end
					entities.init_entity(v)
					num_init = num_init + 1
				else
					entities.check_and_replace_power_entity(v, power_entities_by_surface and power_entities_by_surface[pos] or nil)
				end
			else
				num_entity_invalid = num_entity_invalid + 1
			end
		end

		local entities_by_surface = storage.entities[surface_key]
		if entities_by_surface ~= nil then
			local stale_positions = {}
			for pos, _ in pairs(entities_by_surface) do
				if not seen_positions[pos] then
					stale_positions[#stale_positions + 1] = pos
				end
			end
			for _, pos in pairs(stale_positions) do
				entities.clear_tile(pos, surface)
				num_stale_entries = num_stale_entries + 1
			end
		end

		utils.cleanup_empty_surface_tables(surface_key)
	end

	if num_entity_invalid > 0 then game.print("[PBE] Warning: num entity invalid: " .. num_entity_invalid) end
	if num_wrongly_present > 0 then game.print("[PBE] Warning: num wrongly present (invalid): " .. num_wrongly_present) end
	if num_wrongly_present_and_valid > 0 then game.print("[PBE] Warning: num wrongly present and valid: " .. num_wrongly_present_and_valid) end
	if num_stale_entries > 0 then game.print("[PBE] Warning: num stale entity-table entries removed: " .. num_stale_entries) end
	game.print("[PBE] PBE_CheckPowerEntities command repaired: " .. num_init .. " entities.")
end

function scans.find_all_power_entities()
	scans.find_all_entities_powered()
	game.print("[PBE] Checking all power entities..")
	local num_destroyed_entities = 0
	local num_remapped_power_entries = 0
	local num_removed_invalid_power_entries = 0
	for _, surface in pairs(game.surfaces) do
		local surface_key = utils.get_surface_key(surface)
		local power_entities_by_surface = storage.power_entities[surface_key]
		if power_entities_by_surface ~= nil then
			local remove_keys = {}
			local remap_entries = {}
			for stored_pos, stored_entity in pairs(power_entities_by_surface) do
				if stored_entity == nil or (not stored_entity.valid) then
					remove_keys[#remove_keys + 1] = stored_pos
					num_removed_invalid_power_entries = num_removed_invalid_power_entries + 1
				elseif stored_entity.surface ~= surface then
					remove_keys[#remove_keys + 1] = stored_pos
					local target_pos = entities.get_entity_idx(stored_entity)
					local _, _, target_power_entities_by_surface = utils.get_surface_tables(stored_entity.surface, true)
					if target_power_entities_by_surface[target_pos] == nil then
						target_power_entities_by_surface[target_pos] = stored_entity
					end
					num_remapped_power_entries = num_remapped_power_entries + 1
				else
					local actual_pos = entities.get_entity_idx(stored_entity)
					if actual_pos ~= stored_pos then
						remove_keys[#remove_keys + 1] = stored_pos
						remap_entries[#remap_entries + 1] = {pos = actual_pos, entity = stored_entity}
						num_remapped_power_entries = num_remapped_power_entries + 1
					end
				end
			end
			for _, remove_key in pairs(remove_keys) do
				power_entities_by_surface[remove_key] = nil
			end
			for _, remap_entry in pairs(remap_entries) do
				if power_entities_by_surface[remap_entry.pos] == nil then
					power_entities_by_surface[remap_entry.pos] = remap_entry.entity
				end
			end
		end
		local world_entities = surface.find_entities_filtered{type = "electric-energy-interface"}
		local power_entities_temp = {}
		for _, v in pairs(world_entities) do
			if string.endswith(v.name, '-power') then
				local pos = entities.get_entity_idx(v)
				local valid_entity = true
				if power_entities_temp[pos] ~= nil then
					game.print('[PBE] Warning: double power entity (destroying it now) at position: ' .. pos)
					v.destroy()
					valid_entity = false
					num_destroyed_entities = num_destroyed_entities + 1
				end
				
				local entities_to_power = nil
				if valid_entity then
					entities_to_power = entities.find_all_entities_to_power_at_position(surface, v.position, 1)
					if entities_to_power[pos] == nil then
						v.destroy()
						local entities_by_surface = storage.entities[surface_key]
						local power_entities_by_surface = storage.power_entities[surface_key]
						if power_entities_by_surface ~= nil then power_entities_by_surface[pos] = nil end
						if entities_by_surface ~= nil then entities_by_surface[pos] = nil end
						valid_entity = false
						num_destroyed_entities = num_destroyed_entities + 1
					end
				end
				local entities_by_surface = storage.entities[surface_key]
				local power_entities_by_surface = storage.power_entities[surface_key]
				if valid_entity and (entities_by_surface == nil or entities_by_surface[pos] == nil) then
					game.print('[PBE] Warning: power entity does not have entry in entities table (checking whether object exists), position: ' .. pos)
					
					if entities_to_power[pos] ~= nil then
						game.print("[PBE] Warning: ... AND entity to be powered exists at this position (assigning it now)!: " .. entities_to_power[pos].name)
						local _, entities_by_surface_new = utils.get_surface_tables(surface, true)
						entities_by_surface_new[pos] = entities_to_power[pos]
					else
						game.print("[PBE] Warning: ... AND entity to be powered DOES NOT exist at this position (removing power entity now)!")
						v.destroy()
						if power_entities_by_surface ~= nil then power_entities_by_surface[pos] = nil end
						valid_entity = false
						num_destroyed_entities = num_destroyed_entities + 1
					end
					
				
				elseif valid_entity and (power_entities_by_surface == nil or power_entities_by_surface[pos] ~= v) then
					game.print('[PBE] Warning: this power entity does not have entry in power entities table, position: (assigning it now)' .. pos)
					local _, _, power_entities_by_surface_new = utils.get_surface_tables(surface, true)
					power_entities_by_surface_new[pos] = v
				end
				
				if valid_entity then power_entities_temp[pos] = v end
			end
		end
		utils.cleanup_empty_surface_tables(surface_key)
	end

	if num_removed_invalid_power_entries > 0 then game.print("[PBE] Warning: removed invalid power-table entries: " .. num_removed_invalid_power_entries) end
	if num_remapped_power_entries > 0 then game.print("[PBE] Warning: remapped misplaced power-table entries: " .. num_remapped_power_entries) end
	game.print("[PBE] PBE_CheckPowerEntities command cleaned up: " .. num_destroyed_entities .. " power entities.")

end

function scans.run_full_scan()
	scans.find_all_power_entities()
	return stats.get_state_snapshot()
end

return scans
