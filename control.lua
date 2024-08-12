---- INIT ----
script.on_init(function()
	global.entities = {}
	global.power_entities = {}
	global.belt_check_interval = 0.05
	global.belt_interval = 0.25
	global.ground_lanes_max_check = 1.0
	global.fill_trial_interval = 0.025
	global.ver = 102
	global.saved_items = {}
	global.spilled_items = {}
	global.sum_ticks = 0

	if global.saved_items == nil then
		global.saved_items = {}
	end
	if global.saved_items_true == nil then
		global.saved_items_true = {}
	end
	if global.saved_items_per_lane == nil then
		global.saved_items_per_lane = {}
	end
	
	if global.num_saved_items_per_lane == nil then
		global.num_saved_items_per_lane = {}
	end
	
	if global.spilled_items == nil then
		global.spilled_items = {}
	end
	global.total_num_saved_items = 0
	
	
end)


function get_entity_idx(entity)
	return entity.position.x .. " " .. entity.position.y
end

function clear_tile(pos)
	if global.entities[pos] ~= nil then
		global.entities[pos] = nil
    end

	if global.power_entities[pos] ~= nil then
		global.power_entities[pos].destroy()
		global.power_entities[pos] = nil
	end
end

---- ON EVENT ----
script.on_event({defines.events.on_robot_built_entity, defines.events.on_built_entity}, function(event)
	if event.created_entity.type == "transport-belt" or event.created_entity.type == "underground-belt" or event.created_entity.type == "splitter" or event.created_entity.type == "loader-1x1" or event.created_entity.type == "loader" then
		local pos = get_entity_idx(event.created_entity)
		--game.print(event.created_entity.name)
		--game.print(string.gsub(event.created_entity.name, "unpowered-", ""))
		
		clear_tile(pos)

		global.power_entities[pos] = event.created_entity.surface.create_entity{
			name = event.created_entity.name.."-power",
			position = event.created_entity.position,
			force = event.created_entity.force,
			direction = event.created_entity.direction,
			destructible = false
		}
		global.entities[pos] = event.created_entity
	end
end)

script.on_event({
	defines.events.on_entity_died,
	defines.events.on_robot_pre_mined,
	defines.events.on_pre_player_mined_item,
	}, function(event)
	local pos = get_entity_idx(event.entity)
    clear_tile(pos)
end)

function underground_length(underground)
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

function lane_max_check(underground, lane_idx, underground_len)
	if lane_idx == 1 or lane_idx == 2 then
		return global.ground_lanes_max_check
	end
	return global.ground_lanes_max_check + underground_len - 1.0
end

function position_capturing_algorithm(lane, max_check)
	local current_check = 0.0
	local items = {}
	local positions = {}
	local last_item = nil
	local removed = 0
	while (current_check < max_check and #lane > 0) do
		if not(lane.can_insert_at(current_check)) then
			last_item = lane[1].name
			removed = lane.remove_item(lane[1])
			if removed == 0 then
				game.print("Warning: did not remove an item!")
			else
				positions[#positions+1] = current_check
				items[#items+1] = last_item
			end
		else
			current_check = current_check + global.belt_check_interval
		end
	end
	
	if #lane ~= 0 then
	
		local space_left = max_check - current_check
		local space_required = (#lane + 1) * global.belt_interval
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
			current_check = current_check + global.belt_interval
			last_item = lane[1].name
			removed = lane.remove_item(lane[1])
			if removed == 0 then
				game.print("Warning: did not remove an item!")
			else
				positions[#positions+1] = current_check
				items[#items+1] = last_item
			end
		
		end
	end
	
	if #lane ~= 0 then
		game.print("Warning: did not remove all items; left (clearing now): " .. #lane)
		lane.clear()
	end
	
	return items, positions
end

function clearing_lane_algorithm(lane)
	local items = {}
	local positions = {}
	local last_item = nil
	local removed = 0
	local num_items = #lane
	for item_idx = 1, num_items do
		last_item = lane[1].name
		removed = lane.remove_item(lane[1])
		if removed == 0 then
			game.print("Warning: did not remove an item!")
		else
			positions[#positions+1] = 0.0
			items[#items+1] = last_item
		end
	end
	
	if #lane ~= 0 then
		game.print("Warning: did not remove all items; left (clearing now): " .. #lane)
		lane.clear()
	end
	
	return items, positions
	
end

function counting_algorithm(lane)
	local items = {}
	local positions = {}
	local last_item = nil
	local num_items = #lane
	for item_idx = 1, num_items do
		last_item = lane[1].name
		positions[#positions+1] = 0.0
		items[#items+1] = last_item
	end
	
	return items, positions
	
end


function check_and_clear_lane(lane, max_check, clear_lane, capture_positions)
	if clear_lane and capture_positions then
		return position_capturing_algorithm(lane, max_check)
	elseif clear_lane then
		return clearing_lane_algorithm(lane)
	else
		return counting_algorithm(lane)
	end
end

function check_and_clear_lanes(underground, underground_len, clear_ground_lanes, capture_positions)
	local n = underground.neighbours
	
	local lanes_items = {}
	local lanes_positions = {}
	
    for lane_idx = 1, 2 do
   		local lane = underground.get_transport_line(lane_idx)
		if lane then
			local max_check = lane_max_check(underground, lane_idx, underground_len)
			local items, positions = check_and_clear_lane(lane, max_check, clear_ground_lanes, capture_positions)
			lanes_items[lane_idx] = items
			lanes_positions[lane_idx] = positions
		end
		
	end
	
	if underground.belt_to_ground_type == "input" and n then
		for lane_idx = 3, 4 do
			local lane = underground.get_transport_line(lane_idx)
			if lane then
				local max_check = lane_max_check(underground, lane_idx, underground_len)
				local items, positions = check_and_clear_lane(lane, max_check, true, capture_positions)
				lanes_items[lane_idx] = items
				lanes_positions[lane_idx] = positions
			end
		end
	end
	
	return lanes_items, lanes_positions
end

function add_count(collection, key, count)
	if collection[key] == nil then
		collection[key] = count
	else
		collection[key] = collection[key] + count
	end
end

function collection_to_string(collection)
	local val = ''
	for k, v in pairs(collection) do
		val = val .. k .. ': ' .. v .. ', ' 
	end
	return val
end

function fill_lane(underground, lane_idx, items, positions, starting_item_idx, obey_positions, underground_len)
	local max_check = lane_max_check(underground, lane_idx, underground_len)
	local lane = underground.get_transport_line(lane_idx)
	local current_check = 0.0
	if positions and #positions > 0 and obey_positions then
		current_check = positions[starting_item_idx] - (global.belt_interval * 2)
	end
	current_check = math.max(0.0, current_check)
	
	local inserted = 0
	local item = nil
	local can_insert = false
	for item_idx = starting_item_idx, #items do
		item = items[item_idx]
		local position = positions[item_idx]
		if obey_positions then
			current_check = math.max(position - (global.belt_interval * 2) - (global.fill_trial_interval * 2 * inserted), current_check)
		end
		can_insert = lane.can_insert_at(current_check)
		if (not can_insert) then
			while (current_check < max_check and (not can_insert)) do
				current_check = current_check + global.fill_trial_interval
				current_check = math.min(current_check, max_check+0.01)
				can_insert = lane.can_insert_at(current_check)
			end
		end
		if can_insert then
			lane.insert_at(current_check, item)
			inserted = inserted + 1
			add_count(global.saved_items, item, 1)
			
		else
			break
		end
	end
	
	--[[
	if inserted < #items then
		current_check = 0.0
		can_insert = lane.can_insert_at(current_check)
		item = items[starting_item_idx - inserted]
		if can_insert then
			lane.insert_at(current_check, item)
			inserted = inserted + 1
		end
	end
	
	
	if obey_positions and inserted < #items then
		lane.clear()
		game.print("Warning: inserting items didn't succeed at the first try. Inserted " .. inserted .. ", left to insert: " .. #items - inserted .. ", max_check " .. max_check .. ",ulen " .. underground_len .. ", curr_check " .. current_check) 
		game.print("Warning: now trying to skip the positions of items")
		fill_lane(underground, lane_idx, items, positions, starting_item_idx, false, underground_len)
	end
	--]]
	local c = 0
	if inserted < #items then
		-- game.print("Warning: unable to insert items. Inserted " .. inserted .. ", left to insert: " .. #items - inserted .. ", max_check " .. max_check .. ",ulen " .. underground_len .. ", curr_check " .. current_check) 
		
		local counts = {}
		
		for item_idx = starting_item_idx+inserted, #items do
			item = items[item_idx]
			
			add_count(global.spilled_items, item, 1)
			add_count(global.saved_items, item, 1)
			add_count(counts, item, 1)
			c = c + 1
		end
		
		add_count(global.spilled_items, '_total', c)
		
		game.print("Spilled " .. c .. " items at  x=" .. underground.position.x .. ", y=" .. underground.position.y .. ": ")
		for k,v in pairs(counts) do
			underground.surface.spill_item_stack(underground.position, {name=k, count=v}, true, underground.force, false)
		end
		game.print(collection_to_string(counts))
	end
	add_count(global.saved_items, '_total', inserted + c)
end

-- Returns the Levenshtein distance between the two given strings
function string.levenshtein(str1, str2)
	local len1 = string.len(str1)
	local len2 = string.len(str2)
	local matrix = {}
	local cost = 0
	
        -- quick cut-offs to save time
	if (len1 == 0) then
		return len2
	elseif (len2 == 0) then
		return len1
	elseif (str1 == str2) then
		return 0
	end
	
        -- initialise the base matrix values
	for i = 0, len1, 1 do
		matrix[i] = {}
		matrix[i][0] = i
	end
	for j = 0, len2, 1 do
		matrix[0][j] = j
	end
	
        -- actual Levenshtein algorithm
	for i = 1, len1, 1 do
		for j = 1, len2, 1 do
			if (str1:byte(i) == str2:byte(j)) then
				cost = 0
			else
				cost = 1
			end
			
			matrix[i][j] = math.min(matrix[i-1][j] + 1, matrix[i][j-1] + 1, matrix[i-1][j-1] + cost)
		end
	end
	
        -- return the last value - this is the Levenshtein distance
	return matrix[len1][len2]
end

function EditDistance( s, t, lim )
    local s_len, t_len = #s, #t -- Calculate the sizes of the strings or arrays
    if lim and math.abs( s_len - t_len ) >= lim then -- If sizes differ by lim, we can stop here
        return lim
    end
    
    -- Convert string arguments to arrays of ints (ASCII values)
    if type( s ) == "string" then
        s = { string.byte( s, 1, s_len ) }
    end
    
    if type( t ) == "string" then
        t = { string.byte( t, 1, t_len ) }
    end
    
    local min = math.min -- Localize for performance
    local num_columns = t_len + 1 -- We use this a lot
    
    local d = {} -- (s_len+1) * (t_len+1) is going to be the size of this array
    -- This is technically a 2D array, but we're treating it as 1D. Remember that 2D access in the
    -- form my_2d_array[ i, j ] can be converted to my_1d_array[ i * num_columns + j ], where
    -- num_columns is the number of columns you had in the 2D array assuming row-major order and
    -- that row and column indices start at 0 (we're starting at 0).
    
    for i=0, s_len do
        d[ i * num_columns ] = i -- Initialize cost of deletion
    end
    for j=0, t_len do
        d[ j ] = j -- Initialize cost of insertion
    end
    
    for i=1, s_len do
        local i_pos = i * num_columns
        local best = lim -- Check to make sure something in this row will be below the limit
        for j=1, t_len do
            local add_cost = (s[ i ] ~= t[ j ] and 1 or 0)
            local val = min(
                d[ i_pos - num_columns + j ] + 1,                               -- Cost of deletion
                d[ i_pos + j - 1 ] + 1,                                         -- Cost of insertion
                d[ i_pos - num_columns + j - 1 ] + add_cost                     -- Cost of substitution, it might not cost anything if it's the same
            )
            d[ i_pos + j ] = val
            
            -- Is this eligible for tranposition?
            if i > 1 and j > 1 and s[ i ] == t[ j - 1 ] and s[ i - 1 ] == t[ j ] then
                d[ i_pos + j ] = min(
                    val,                                                        -- Current cost
                    d[ i_pos - num_columns - num_columns + j - 2 ] + add_cost   -- Cost of transposition
                )
            end
            
            if lim and val < best then
                best = val
            end
        end
        
        if lim and best >= lim then
            return lim
        end
    end
    
    return d[ #d ]
end

function get_max_lane_idx(underground)
	local max_lane_idx = 2
	if underground.belt_to_ground_type == 'input' then
		max_lane_idx = 4
	end
	return max_lane_idx
end

function get_lane_identifier(underground, lane_idx)
	return underground.belt_to_ground_type .. lane_idx
end

function get_saved_items(underground, lanes_items)
	local saved_items_per_lane = {}
	local num_saved_items_per_lane = {}
	local saved_items = {}
	local max_lane_idx = get_max_lane_idx(underground)
	local num_saved_items = 0
	for lane_idx = 1, max_lane_idx do
		saved_items_per_lane[get_lane_identifier(underground, lane_idx)] = {}
		local items = lanes_items[lane_idx]
		if items ~= nil then
			num_saved_items = num_saved_items + #items
			num_saved_items_per_lane[get_lane_identifier(underground, lane_idx)] = #items
			
			for item_idx = 1, #items do
				item = items[item_idx]
				add_count(saved_items, item, 1)
				add_count(saved_items_per_lane[get_lane_identifier(underground, lane_idx)], item, 1)
			end
		end
		
	end
	return saved_items, saved_items_per_lane, num_saved_items_per_lane, num_saved_items
end

function extra_and_saved_items_with_created_state(underground, saved_items, saved_items_per_lane, num_saved_items_per_lane, num_saved_items)
	local extra_items = {}
	local extra_items_per_lane = {}
	local num_extra_items_per_lane = {}
	local num_extra_items = 0
	local max_lane_idx = get_max_lane_idx(underground)
	
	for lane_idx = 1, max_lane_idx do
		local lane_identifier = get_lane_identifier(underground, lane_idx)
		extra_items_per_lane[lane_identifier] = {}
		num_extra_items_per_lane[lane_identifier] = 0
		local lane = underground.get_transport_line(lane_idx)
		
		for item_idx = 1, #lane do
			local item = lane[item_idx].name
			if saved_items[item] == nil or saved_items[item] == 0 then
				add_count(extra_items, item, 1)
				num_extra_items = num_extra_items + 1
			else
				add_count(saved_items, item, -1)
				num_saved_items = num_saved_items - 1
			end
			
			if saved_items_per_lane[lane_identifier][item] == nil or saved_items_per_lane[lane_identifier][item] == 0 then
				add_count(extra_items_per_lane[lane_identifier], item, 1)
				num_extra_items_per_lane[lane_identifier] = num_extra_items_per_lane[lane_identifier] + 1
			else
				add_count(saved_items_per_lane[lane_identifier], item, -1)
				num_saved_items_per_lane[lane_identifier] = num_saved_items_per_lane[lane_identifier] - 1
			end
			
			
		end
	end
	
	return extra_items, extra_items_per_lane, num_extra_items_per_lane, num_extra_items, num_saved_items
end

function add_counter(base_cnt, added_cnt)
	for k, v in pairs(added_cnt) do
		add_count(base_cnt, k, v)
	end
end

function add_counter_create_key(base_cnt, added_cnt, key)
	local key_cnt = base_cnt[key]
	if key_cnt == nil then
		base_cnt[key] = {}
		key_cnt = base_cnt[key]
	end
	add_counter(key_cnt, added_cnt)
end

function update_collection(base_cl, added_cl)
	for k, v in pairs(added_cl) do
		base_cl[k] = v
	end
end

function check_lanes(underground, neighbour, lanes_items, lanes_items_n)
	local saved_items, saved_items_per_lane, num_saved_items_per_lane, num_saved_items = get_saved_items(underground, lanes_items)
	local extra_items_n, extra_items_per_lane_n, num_extra_items_per_lane_n, num_extra_items_n = nil, nil, nil, 0 
	if neighbour and neighbour.valid and lanes_items_n then
		local saved_items_n, saved_items_per_lane_n, num_saved_items_per_lane_n, num_saved_items_n = get_saved_items(neighbour, lanes_items)
		add_counter(saved_items, saved_items_n)
		update_collection(saved_items_per_lane, saved_items_per_lane_n)
		update_collection(num_saved_items_per_lane, num_saved_items_per_lane_n)
		num_saved_items = num_saved_items + num_saved_items_n
	
		extra_items_n, extra_items_per_lane_n, num_extra_items_per_lane_n, num_extra_items_n, num_saved_items = extra_and_saved_items_with_created_state(neighbour, saved_items, saved_items_per_lane, num_saved_items_per_lane, num_saved_items)
	end
	
	local extra_items, extra_items_per_lane, num_extra_items_per_lane, num_extra_items = nil, nil, nil, 0 
	
	extra_items, extra_items_per_lane, num_extra_items_per_lane, num_extra_items, num_saved_items = extra_and_saved_items_with_created_state(underground, saved_items, saved_items_per_lane, num_saved_items_per_lane, num_saved_items)
	
	if extra_items_n then
		add_counter(extra_items, extra_items_n)
		update_collection(extra_items_per_lane, extra_items_per_lane_n)
		update_collection(num_extra_items_per_lane, num_extra_items_per_lane_n)
		num_extra_items = num_extra_items + num_extra_items_n
	end
	
	if num_extra_items > 0 then
		game.print("Warning: extra items present after creation! num_extra_items: " .. num_extra_items)

	end
	
	for k, v in pairs(saved_items_per_lane) do
		add_counter_create_key(global.saved_items_per_lane, v, k)
	end
	
	add_counter(global.num_saved_items_per_lane, num_saved_items_per_lane)
	add_counter(global.saved_items_true, saved_items)
	global.total_num_saved_items = global.total_num_saved_items + num_saved_items
	
end

function fill_lanes(underground, lanes_items, lanes_positions, underground_len, clear_ground_lanes)
	if lanes_items == nil then
		return
	end
	
	local clear_lane = true
	for lane_idx = 4, 1, -1 do
	
		if (not clear_ground_lanes) and (lane_idx == 1 or lane_idx == 2) then
			clear_lane = false
		end
	
		local items = lanes_items[lane_idx]
		if items ~= nil then
			local positions = lanes_positions[lane_idx]
			if clear_lane then
				fill_lane(underground, lane_idx, items, positions, 1, true, underground_len)
			end
		end
	end
end

function call_replace(entity_idx, entity_data)
	local new_entity = entity_data.surface.create_entity{
		name = entity_data.new_name,
		position = entity_data.position,
		force = entity_data.force,
		direction = entity_data.direction,
		type = entity_data.belt_to_ground_type,
		fast_replace = true,
		spill = false
	}
	
	global.entities[entity_idx] = new_entity
	return new_entity
	
end

function replace_entity(entity, entity_idx, check_for_neighbour, power_up, underground_len, clear_ground_lanes, capture_positions)
	local entity_data = {surface = entity.surface, name = entity.name, position = entity.position, force = entity.force, direction = entity.direction}
	local is_underground = entity.type == "underground-belt"
	local n = nil
	local lanes_items = nil
	local lanes_positions = nil
	if is_underground then
		n = entity.neighbours
		entity_data.belt_to_ground_type = entity.belt_to_ground_type
		lanes_items, lanes_positions = check_and_clear_lanes(entity, underground_len, clear_ground_lanes, capture_positions)
	end
	
	local new_name = nil
	if power_up then
		new_name = string.sub(entity_data.name, 11)
	else
		new_name = "unpowered-" .. entity_data.name
	end
	entity_data.new_name = new_name
	
	local neighbour_cond = check_for_neighbour and n ~= nil
	
	local n_lanes_items = nil
	local n_lanes_positions = nil
	local neighbour_idx = nil
	
	if neighbour_cond then
		neighbour_idx = get_entity_idx(n)
		n_lanes_items, n_lanes_positions = run_for_entity(n, neighbour_idx, false, underground_len, power_up, not power_up, clear_ground_lanes, capture_positions)
		--n_lanes_items, n_lanes_positions = replace_entity(n, neighbour_idx, false, power_up, underground_len, clear_ground_lanes, capture_positions)
	end
	
	local new_entity = call_replace(entity_idx, entity_data)
	
	if is_underground then
		if neighbour_cond then
			check_lanes(new_entity, global.entities[neighbour_idx], lanes_items, n_lanes_items)
			if new_entity.belt_to_ground_type == "input" then
				fill_lanes(new_entity, lanes_items, lanes_positions, underground_len, clear_ground_lanes)
				if n_lanes_items ~= nil and n_lanes_positions ~= nil then
					fill_lanes(global.entities[neighbour_idx], n_lanes_items, n_lanes_positions, underground_len, clear_ground_lanes)
				end
				
			else
				if n_lanes_items ~= nil and n_lanes_positions ~= nil then
					fill_lanes(global.entities[neighbour_idx], n_lanes_items, n_lanes_positions, underground_len, clear_ground_lanes)
				end
				fill_lanes(new_entity, lanes_items, lanes_positions, underground_len, clear_ground_lanes)
				
			end
			
		--elseif check_for_neighbour then
		elseif check_for_neighbour then
			fill_lanes(new_entity, lanes_items, lanes_positions, underground_len, clear_ground_lanes)
		
		end
	end
	return lanes_items, lanes_positions
	

end

function run_for_entity(entity, entity_idx, check_for_neighbour, underground_len, powerup_n, powerdown_n, clear_ground_lanes, capture_positions)
	--[[
	local is_underground = entity.type == "underground-belt"
	local n = nil
	local powerup_n = true
	local powerdown_n = true
	local neighbour_idx = nil
	
	if is_underground and check_for_neighbour then
		n = entity.neighbours
		if n ~= nil then
			neighbour_idx = get_entity_idx(n)
			powerup_n = global.power_entities[neighbour_idx].energy > settings.global["powered-belts-required-energy"].value
			powerdown_n = not powerup_n
		end
		
			powerup_n = global.power_entities[entity_idx].energy > settings.global["powered-belts-required-energy"].value
		powerdown_n = not powerup_n
	end
	--]]
	
	
	-- TODO/IDEA: only powered up when both neighbours powered up? otherwise both power down?
	if entity.valid and global.entities[entity_idx] ~= nil then
		if string.match(entity.name, "unpowered-") and (global.power_entities[entity_idx].energy > settings.global["powered-belts-required-energy"].value or powerup_n) then
			return replace_entity(entity, entity_idx, check_for_neighbour, true, underground_len, clear_ground_lanes, capture_positions)
			
		elseif (not string.match(entity.name, "unpowered-")) and (global.power_entities[entity_idx].energy <= settings.global["powered-belts-required-energy"].value or powerdown_n) then
			return replace_entity(entity, entity_idx, check_for_neighbour, false, underground_len, clear_ground_lanes, capture_positions)
		end
	end
	return nil, nil
end



---- ON TICK ----
script.on_event(defines.events.on_tick, function(event)
	if global.ver ~= 102 then
		global.belt_check_interval = 0.05
		global.belt_interval = 0.25
		global.ground_lanes_max_check = 1.0
		global.fill_trial_interval = 0.025
		if global.saved_items == nil then
			global.saved_items = {}
		end
		if global.saved_items_true == nil then
			global.saved_items_true = {}
		end
		if global.saved_items_per_lane == nil then
			global.saved_items_per_lane = {}
		end
		
		if global.num_saved_items_per_lane == nil then
			global.num_saved_items_per_lane = {}
		end
		
		if global.spilled_items == nil then
			global.spilled_items = {}
		end
		global.sum_ticks = 0
		global.total_num_saved_items = 0
		global.ver = 102
	end
	global.sum_ticks = global.sum_ticks + 1
    if global.power_entities ~= nil and global.entities ~= nil and next(global.power_entities) and next(global.entities) then
	
        for _ = 1, settings.global["powered-belts-operations-per-tick"].value do
            
			if next(global.power_entities) ~= nil and next(global.entities) ~= nil then
			
                if next(global.power_entities, k) == nil then
					k,_ = next(global.power_entities, nil) 
				else 
					k,_ = next(global.power_entities, k) 
				end
				if global.entities[k].valid then
					run_for_entity(global.entities[k], k, true, underground_length(global.entities[k]), false, false, true, true)
				end
            end
        end
    end
end)

remote.add_interface("powered_belts_extended", {
  get_global = function() return global end
})