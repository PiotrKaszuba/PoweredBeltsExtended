local utils = require("modules.utils")
local entities = require("modules.entities")

local undergrounds = {}

function undergrounds.underground_length(underground)
	if  underground.type ~= "underground-belt" then
		return nil
	end
    if underground and underground.belt_to_ground_type == "output" then
		underground = underground.neighbours
	end
	if (not underground) or (not underground.neighbours) then
		return 0.0
	end
	return math.abs(underground.position.x - underground.neighbours.position.x + underground.position.y - underground.neighbours.position.y)
end

function undergrounds.lane_max_check(underground, lane_idx, underground_len)
	if lane_idx == 1 or lane_idx == 2 then
		return storage.ground_lanes_max_check
	end
	return storage.ground_lanes_max_check + underground_len - 1.0
end

local function capture_line_item(lane, line_item, current_position, items, positions, replace_context)
	if not (line_item and line_item.valid_for_read) then
		return 0
	end

	local item_name = utils.get_item_name_for_stats(line_item)
	if replace_context == nil or (not replace_context.preserve_mode) then
		local removed = lane.remove_item(line_item)
		if removed > 0 then
			utils.append_items(items, positions, item_name, removed, current_position)
		end
		return removed
	end

	local removed = 0
	while line_item.valid_for_read and line_item.count > 0 do
		local slot_idx, slot = utils.reserve_preserve_temp_slot(replace_context)
		if slot_idx == nil or slot == nil then
			break
		end

		local moved = slot.transfer_stack(line_item, 1)
		if not moved then
			break
		end

		removed = removed + 1
		utils.append_item_token(items, positions, {name = item_name, slot = slot_idx}, current_position)
	end

	if line_item.valid_for_read and line_item.count > 0 then
		local fallback_removed = lane.remove_item(line_item)
		if fallback_removed > 0 then
			storage.preserve_mode_fallback_items = (storage.preserve_mode_fallback_items or 0) + fallback_removed
			utils.append_items(items, positions, item_name, fallback_removed, current_position)
			removed = removed + fallback_removed
		end
	end

	return removed
end

function undergrounds.position_capturing_algorithm(lane, max_check, replace_context)
	if not (lane and lane.valid) then
		return {}, {}
	end
	local current_check = 0.0
	local items = {}
	local positions = {}
	local removed = 0
	while (lane.valid and current_check < max_check and #lane > 0) do
		if not(lane.can_insert_at(current_check)) then
			local line_item = lane[1]
			if not (line_item and line_item.valid_for_read) then
				break
			end
			removed = capture_line_item(lane, line_item, current_check, items, positions, replace_context)
			if removed == 0 then
				game.print("[PBE] Warning: did not remove an item!")
			end
		else
			current_check = current_check + storage.belt_check_interval
		end
	end
	
	if lane.valid and #lane ~= 0 then
	
		local space_left = max_check - current_check
		local space_required = (#lane + 1) * storage.belt_interval
		local space_to_make = space_required - space_left
		
		if space_to_make > 0 then
			for pos_idx = 1, #positions do
				positions[pos_idx] = positions[pos_idx] - space_to_make
			end
		end
		if #positions > 0 then
			current_check = positions[#positions]
		else
			current_check = 0.0
		end
		local num_left_items = #lane
		for _ = 1, num_left_items do
			if (not lane.valid) or #lane == 0 then
				break
			end
			current_check = current_check + storage.belt_interval
			local line_item = lane[1]
			if not (line_item and line_item.valid_for_read) then
				break
			end
			removed = capture_line_item(lane, line_item, current_check, items, positions, replace_context)
			if removed == 0 then
				game.print("[PBE] Warning: did not remove an item!")
			end
		
		end
	end
	
	if lane.valid and #lane ~= 0 then
		game.print("[PBE] Warning: did not remove all items; left (clearing now): " .. #lane)
		lane.clear()
	end
	
	return items, positions
end

function undergrounds.check_and_clear_lane(lane, max_check, replace_context)
	if not (lane and lane.valid) then
		return {}, {}
	end
	return undergrounds.position_capturing_algorithm(lane, max_check, replace_context)
end

function undergrounds.check_and_clear_lanes(underground, underground_len, replace_context)
	local n = underground.neighbours
	
	local lanes_items = {}
	local lanes_positions = {}
	
    for lane_idx = 1, 2 do
   		local lane = underground.get_transport_line(lane_idx)
		if lane and lane.valid then
			local max_check = undergrounds.lane_max_check(underground, lane_idx, underground_len)
			local items, positions = undergrounds.check_and_clear_lane(lane, max_check, replace_context)
			lanes_items[lane_idx] = items
			lanes_positions[lane_idx] = positions
		end
		
	end
	
	if underground.belt_to_ground_type == "input" or n == nil then
		for lane_idx = 3, 4 do
			local lane = underground.get_transport_line(lane_idx)
			if lane and lane.valid then
				local max_check = undergrounds.lane_max_check(underground, lane_idx, underground_len)
				local items, positions = undergrounds.check_and_clear_lane(lane, max_check, replace_context)
				lanes_items[lane_idx] = items
				lanes_positions[lane_idx] = positions
			end
		end
	end
	
	return lanes_items, lanes_positions
end

function undergrounds.add_count(collection, key, count)
	if collection[key] == nil then
		collection[key] = count
	else
		collection[key] = collection[key] + count
	end
end

function undergrounds.collection_to_string(collection)
	local val = ''
	for k, v in pairs(collection) do
		val = val .. k .. ': ' .. v .. ', ' 
	end
	return val
end

function undergrounds.fill_lane(underground, lane_idx, items, positions, starting_item_idx, obey_positions, underground_len, replace_context)
	local max_check = undergrounds.lane_max_check(underground, lane_idx, underground_len)
	local lane = underground.get_transport_line(lane_idx)
	if not (lane and lane.valid) then
		return
	end
	local current_check = 0.0
	if positions and #positions > 0 and obey_positions then
		current_check = positions[starting_item_idx] - (storage.belt_interval * 2)
	end
	current_check = math.max(0.0, current_check)
	
	local inserted = 0
	local item = nil
	local can_insert = false
	for item_idx = starting_item_idx, #items do
		if not lane.valid then
			break
		end
		item = items[item_idx]
		local item_name = utils.get_item_name_for_stats(item)
		local position = positions[item_idx]
		if obey_positions then
			current_check = math.max(position - (storage.belt_interval * 2) - (storage.fill_trial_interval * 2 * inserted), current_check)
		end
		can_insert = lane.can_insert_at(current_check)
		if (not can_insert) then
			while (current_check < max_check and (not can_insert)) do
				current_check = current_check + storage.fill_trial_interval
				current_check = math.min(current_check, max_check+0.01)
				can_insert = lane.can_insert_at(current_check)
			end
		end
		if can_insert then
			local item_identification, requires_consume = utils.get_item_identification_for_transfer(item, replace_context)
			if lane.insert_at(current_check, item_identification) then
				if requires_consume then
					utils.consume_preserved_item_token(item, replace_context)
				end
				inserted = inserted + 1
				undergrounds.add_count(storage.saved_items, item_name, 1)
			else
				break
			end
			
		else
			break
		end
	end
	
	local c = 0
	if inserted < #items then
		
		local counts = {}
		local grouped_spills = {}
		
		for item_idx = starting_item_idx+inserted, #items do
			item = items[item_idx]
			local item_name = utils.get_item_name_for_stats(item)
			local item_identification, requires_consume = utils.get_item_identification_for_transfer(item, replace_context)
			
			undergrounds.add_count(storage.spilled_items, item_name, 1)
			undergrounds.add_count(storage.saved_items, item_name, 1)
			undergrounds.add_count(counts, item_name, 1)
			if requires_consume then
				underground.surface.spill_item_stack{
					position = underground.position,
					stack = item_identification,
					enable_looted = true,
					force = underground.force,
					allow_belts = false
				}
				utils.consume_preserved_item_token(item, replace_context)
			else
				undergrounds.add_count(grouped_spills, item_name, 1)
			end
			c = c + 1
		end
		
		undergrounds.add_count(storage.spilled_items, '_total', c)
		
		game.print("[PBE] Spilled " .. c .. " items at  x=" .. underground.position.x .. ", y=" .. underground.position.y .. ": ")
		for k, v in pairs(grouped_spills) do
			underground.surface.spill_item_stack{
				position = underground.position,
				stack = {name = k, count = v},
				enable_looted = true,
				force = underground.force,
				allow_belts = false
			}
		end
		game.print("[PBE] " .. undergrounds.collection_to_string(counts))
	end
	undergrounds.add_count(storage.saved_items, '_total', inserted + c)
end

function undergrounds.get_max_lane_idx(underground)
	local max_lane_idx = 2
	if underground.belt_to_ground_type == 'input' then
		max_lane_idx = 4
	end
	return max_lane_idx
end

function undergrounds.get_lane_identifier(underground, lane_idx)
	return underground.belt_to_ground_type .. lane_idx
end

function undergrounds.get_saved_items(underground, lanes_items)
	local saved_items_per_lane = {}
	local num_saved_items_per_lane = {}
	local saved_items = {}
	local max_lane_idx = undergrounds.get_max_lane_idx(underground)
	local num_saved_items = 0
	for lane_idx = 1, max_lane_idx do
		saved_items_per_lane[undergrounds.get_lane_identifier(underground, lane_idx)] = {}
		local items = lanes_items[lane_idx]
		if items ~= nil then
			num_saved_items = num_saved_items + #items
			num_saved_items_per_lane[undergrounds.get_lane_identifier(underground, lane_idx)] = #items
			
			for item_idx = 1, #items do
				local item_name = utils.get_item_name_for_stats(items[item_idx])
				undergrounds.add_count(saved_items, item_name, 1)
				undergrounds.add_count(saved_items_per_lane[undergrounds.get_lane_identifier(underground, lane_idx)], item_name, 1)
			end
		end
		
	end
	return saved_items, saved_items_per_lane, num_saved_items_per_lane, num_saved_items
end

function undergrounds.extra_and_saved_items_with_created_state(underground, saved_items, saved_items_per_lane, num_saved_items_per_lane, num_saved_items)
	local extra_items = {}
	local extra_items_per_lane = {}
	local num_extra_items_per_lane = {}
	local num_extra_items = 0
	local max_lane_idx = undergrounds.get_max_lane_idx(underground)
	
	for lane_idx = 1, max_lane_idx do
		local lane_identifier = undergrounds.get_lane_identifier(underground, lane_idx)
		extra_items_per_lane[lane_identifier] = {}
		num_extra_items_per_lane[lane_identifier] = 0
		local lane = underground.get_transport_line(lane_idx)

		if lane and lane.valid then
			for _, detailed_item in pairs(lane.get_detailed_contents()) do
				local line_item = detailed_item.stack
				if line_item and line_item.valid_for_read then
					local item = utils.get_item_name_for_stats(line_item)
					local item_count = math.max(0, math.floor(line_item.count or 0))
					for _ = 1, item_count do
						if saved_items[item] == nil or saved_items[item] == 0 then
							undergrounds.add_count(extra_items, item, 1)
							num_extra_items = num_extra_items + 1
						else
							undergrounds.add_count(saved_items, item, -1)
							num_saved_items = num_saved_items - 1
						end
						
						if saved_items_per_lane[lane_identifier][item] == nil or saved_items_per_lane[lane_identifier][item] == 0 then
							undergrounds.add_count(extra_items_per_lane[lane_identifier], item, 1)
							num_extra_items_per_lane[lane_identifier] = num_extra_items_per_lane[lane_identifier] + 1
						else
							undergrounds.add_count(saved_items_per_lane[lane_identifier], item, -1)
							num_saved_items_per_lane[lane_identifier] = num_saved_items_per_lane[lane_identifier] - 1
						end
					end
				end
			end
		end
	end
	
	return extra_items, extra_items_per_lane, num_extra_items_per_lane, num_extra_items, num_saved_items
end

function undergrounds.add_counter(base_cnt, added_cnt)
	for k, v in pairs(added_cnt) do
		undergrounds.add_count(base_cnt, k, v)
	end
end

function undergrounds.add_counter_create_key(base_cnt, added_cnt, key)
	local key_cnt = base_cnt[key]
	if key_cnt == nil then
		base_cnt[key] = {}
		key_cnt = base_cnt[key]
	end
	undergrounds.add_counter(key_cnt, added_cnt)
end

function undergrounds.update_collection(base_cl, added_cl)
	for k, v in pairs(added_cl) do
		base_cl[k] = v
	end
end

function undergrounds.check_lanes(underground, neighbour, lanes_items, lanes_items_n)
	local saved_items, saved_items_per_lane, num_saved_items_per_lane, num_saved_items = undergrounds.get_saved_items(underground, lanes_items)
	local extra_items_n, extra_items_per_lane_n, num_extra_items_per_lane_n, num_extra_items_n = nil, nil, nil, 0 
	if neighbour and neighbour.valid and lanes_items_n then
		local saved_items_n, saved_items_per_lane_n, num_saved_items_per_lane_n, num_saved_items_n = undergrounds.get_saved_items(neighbour, lanes_items_n)
		undergrounds.add_counter(saved_items, saved_items_n)
		undergrounds.update_collection(saved_items_per_lane, saved_items_per_lane_n)
		undergrounds.update_collection(num_saved_items_per_lane, num_saved_items_per_lane_n)
		num_saved_items = num_saved_items + num_saved_items_n
	
		extra_items_n, extra_items_per_lane_n, num_extra_items_per_lane_n, num_extra_items_n, num_saved_items = undergrounds.extra_and_saved_items_with_created_state(neighbour, saved_items, saved_items_per_lane, num_saved_items_per_lane, num_saved_items)
	end
	
	local extra_items, extra_items_per_lane, num_extra_items_per_lane, num_extra_items = nil, nil, nil, 0 
	
	extra_items, extra_items_per_lane, num_extra_items_per_lane, num_extra_items, num_saved_items = undergrounds.extra_and_saved_items_with_created_state(underground, saved_items, saved_items_per_lane, num_saved_items_per_lane, num_saved_items)
	
	if extra_items_n then
		undergrounds.add_counter(extra_items, extra_items_n)
		undergrounds.update_collection(extra_items_per_lane, extra_items_per_lane_n)
		undergrounds.update_collection(num_extra_items_per_lane, num_extra_items_per_lane_n)
		num_extra_items = num_extra_items + num_extra_items_n
	end
	
	if num_extra_items > 0 then
		game.print("[PBE] Warning: extra items present after creation! num_extra_items: " .. num_extra_items)

	end
	
	for k, v in pairs(saved_items_per_lane) do
		undergrounds.add_counter_create_key(storage.saved_items_per_lane, v, k)
	end
	
	undergrounds.add_counter(storage.num_saved_items_per_lane, num_saved_items_per_lane)
	undergrounds.add_counter(storage.saved_items_true, saved_items)
	storage.total_num_saved_items = storage.total_num_saved_items + num_saved_items
	
end

function undergrounds.fill_lanes(underground, lanes_items, lanes_positions, underground_len, replace_context)
	if lanes_items == nil then
		return
	end
	
	for lane_idx = 4, 1, -1 do
		local items = lanes_items[lane_idx]
		if items ~= nil then
			local positions = lanes_positions[lane_idx]
			undergrounds.fill_lane(underground, lane_idx, items, positions, 1, true, underground_len, replace_context)
		end
	end
end

function undergrounds.call_replace(surface, entity_idx, entity_data)
	local new_entity = entity_data.surface.create_entity{
		name = entity_data.new_name,
		position = entity_data.position,
		force = entity_data.force,
		direction = entity_data.direction,
		type = entity_data.belt_to_ground_type,
		fast_replace = true,
		spill = false
	}
	
	local _, entities_by_surface = utils.get_surface_tables(surface, true)
	entities_by_surface[entity_idx] = new_entity
	return new_entity
	
end

function undergrounds.replace_entity(entity, surface, entity_idx, check_for_neighbour, power_up, underground_len, replace_context)
	local own_replace_context = false
	if replace_context == nil then
		local underground_transfer_mode = utils.get_effective_underground_transfer_mode()
		replace_context = {
			underground_transfer_mode = underground_transfer_mode,
			preserve_mode = utils.preserve_mode_enabled(underground_transfer_mode),
			disable_item_transfer = utils.underground_item_transfer_disabled(underground_transfer_mode),
			temp_inventory = nil,
			temp_inventory_next_slot = 1
		}
		own_replace_context = true
	end

	local planner_state = utils.capture_entity_planner_state(entity)
	local entity_data = {surface = entity.surface, name = entity.name, position = entity.position, force = entity.force, direction = entity.direction}
	local is_underground = entity.type == "underground-belt"
	local neighbour_entity = nil
	local lanes_items = nil
	local lanes_positions = nil
	if is_underground then
		neighbour_entity = entity.neighbours
		entity_data.belt_to_ground_type = entity.belt_to_ground_type
		if not replace_context.disable_item_transfer then
			lanes_items, lanes_positions = undergrounds.check_and_clear_lanes(entity, underground_len, replace_context)
		end
	end
	
	local new_name = nil
	if power_up then
		new_name = string.sub(entity_data.name, 11)
	else
		new_name = "unpowered-" .. entity_data.name
	end
	entity_data.new_name = new_name
	
	local neighbour_cond = check_for_neighbour and neighbour_entity ~= nil
	
	local n_lanes_items = nil
	local n_lanes_positions = nil
	local neighbour_idx = nil
	if neighbour_cond then
		neighbour_idx = entities.get_entity_idx(neighbour_entity)
		n_lanes_items, n_lanes_positions, neighbour_entity = undergrounds.run_for_entity(neighbour_entity, surface, neighbour_idx, false, underground_len, power_up, not power_up, replace_context)
	end

	local new_entity = undergrounds.call_replace(surface, entity_idx, entity_data)

	local _, entities_by_surface = utils.get_surface_tables(surface, false)
	
	if is_underground then
		if (not replace_context.disable_item_transfer) and neighbour_cond then
			if (neighbour_entity == nil or not neighbour_entity.valid) and entities_by_surface ~= nil then
				neighbour_entity = entities_by_surface[neighbour_idx]
			end
			undergrounds.check_lanes(new_entity, neighbour_entity, lanes_items, n_lanes_items)
			if new_entity.belt_to_ground_type == "input" then
				undergrounds.fill_lanes(new_entity, lanes_items, lanes_positions, underground_len, replace_context)
				if n_lanes_items ~= nil and n_lanes_positions ~= nil and neighbour_entity ~= nil then
					undergrounds.fill_lanes(neighbour_entity, n_lanes_items, n_lanes_positions, underground_len, replace_context)
				end
				
			else
				if n_lanes_items ~= nil and n_lanes_positions ~= nil and neighbour_entity ~= nil then
					undergrounds.fill_lanes(neighbour_entity, n_lanes_items, n_lanes_positions, underground_len, replace_context)
				end
				undergrounds.fill_lanes(new_entity, lanes_items, lanes_positions, underground_len, replace_context)
				
			end
			
		elseif (not replace_context.disable_item_transfer) and check_for_neighbour then
			undergrounds.fill_lanes(new_entity, lanes_items, lanes_positions, underground_len, replace_context)
		
		end
	end

	utils.apply_entity_planner_state(new_entity, planner_state)

	if own_replace_context and replace_context.temp_inventory ~= nil and replace_context.temp_inventory.valid then
		replace_context.temp_inventory.destroy()
	end
	return lanes_items, lanes_positions, new_entity
	

end

function undergrounds.run_for_entity(entity, surface, entity_idx, check_for_neighbour, underground_len, powerup_n, powerdown_n, replace_context)
	-- TODO/IDEA: only powered up when both neighbours powered up? otherwise both power down?
	local _, entities_by_surface, power_entities_by_surface = utils.get_surface_tables(surface, true)
	if entity.valid and entities_by_surface ~= nil and entities_by_surface[entity_idx] ~= nil then
		entities.check_and_replace_power_entity(entity, power_entities_by_surface and power_entities_by_surface[entity_idx] or nil)
		local power_entity = power_entities_by_surface and power_entities_by_surface[entity_idx] or nil
		if power_entity == nil or (not power_entity.valid) then
			return nil, nil, nil
		end
		local required_energy = power_entity.electric_buffer_size * (utils.get_required_energy_percentage_setting() / 100)
		if string.match(entity.name, "^unpowered%-") and (power_entity.energy >= required_energy or powerup_n) then
			return undergrounds.replace_entity(entity, surface, entity_idx, check_for_neighbour, true, underground_len, replace_context)
			
		elseif (not string.match(entity.name, "^unpowered%-")) and (power_entity.energy < required_energy or powerdown_n) then
			return undergrounds.replace_entity(entity, surface, entity_idx, check_for_neighbour, false, underground_len, replace_context)
		end
	end
	return nil, nil, nil
end

return undergrounds
