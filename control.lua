local current_version = 120
local belt_entity_types = {
	["transport-belt"] = true,
	["underground-belt"] = true,
	["splitter"] = true,
	["loader"] = true,
	["loader-1x1"] = true,
}
local belt_entity_type_list = {"transport-belt", "underground-belt", "splitter", "loader", "loader-1x1"}
local underground_transfer_modes = {
	["name-only"] = true,
	["preserve-full-state"] = true,
	["disabled"] = true,
}
local default_underground_transfer_mode = "name-only"
local underground_transfer_mode_setting_name = "powered-belts-underground-item-transfer-mode"

local function get_surface_key(surface)
	if not surface then
		return nil
	end
	return surface.index
end

local function migrate_surface_partition(storage_key)
	local table_root = storage[storage_key]
	if table_root == nil then
		storage[storage_key] = {}
		return
	end

	local needs_migration = false
	for _, value in pairs(table_root) do
		if type(value) ~= "table" then
			needs_migration = true
		end
		break
	end

	if not needs_migration then
		return
	end

	local migrated = {}
	for pos, entity in pairs(table_root) do
		if entity and entity.valid and entity.surface then
			local surface_key = get_surface_key(entity.surface)
			if migrated[surface_key] == nil then
				migrated[surface_key] = {}
			end
			migrated[surface_key][pos] = entity
		end
	end

	storage[storage_key] = migrated
end

local function get_surface_tables(surface, create_if_missing)
	local surface_key = get_surface_key(surface)
	if surface_key == nil then
		return nil, nil, nil
	end

	local entities_by_surface = storage.entities[surface_key]
	local power_entities_by_surface = storage.power_entities[surface_key]

	if create_if_missing then
		if entities_by_surface == nil then
			entities_by_surface = {}
			storage.entities[surface_key] = entities_by_surface
		end
		if power_entities_by_surface == nil then
			power_entities_by_surface = {}
			storage.power_entities[surface_key] = power_entities_by_surface
		end
	end

	return surface_key, entities_by_surface, power_entities_by_surface
end

local function cleanup_empty_surface_tables(surface_key)
	if surface_key == nil then
		return
	end

	local entities_by_surface = storage.entities[surface_key]
	if entities_by_surface ~= nil and next(entities_by_surface) == nil then
		storage.entities[surface_key] = nil
	end

	local power_entities_by_surface = storage.power_entities[surface_key]
	if power_entities_by_surface ~= nil and next(power_entities_by_surface) == nil then
		storage.power_entities[surface_key] = nil
	end
end

local function prune_deleted_surfaces()
	if not game then
		return
	end

	for surface_key, _ in pairs(storage.entities) do
		if game.surfaces[surface_key] == nil then
			storage.entities[surface_key] = nil
		end
	end

	for surface_key, _ in pairs(storage.power_entities) do
		if game.surfaces[surface_key] == nil then
			storage.power_entities[surface_key] = nil
		end
	end
end

local function get_next_power_entity_iterator()
	local current_surface_key = storage.tick_surface_iterator_key
	local current_entity_key = storage.tick_iterator_key
	local current_surface_table = nil

	if current_surface_key ~= nil then
		current_surface_table = storage.power_entities[current_surface_key]
		if current_surface_table == nil then
			current_surface_key = nil
			current_entity_key = nil
		elseif current_entity_key ~= nil and current_surface_table[current_entity_key] == nil then
			current_entity_key = nil
		end
	end

	if current_surface_table ~= nil then
		local next_entity_key = next(current_surface_table, current_entity_key)
		if next_entity_key ~= nil then
			return current_surface_key, next_entity_key
		end
	end

	local next_surface_key = next(storage.power_entities, current_surface_key)
	while next_surface_key ~= nil do
		local surface_table = storage.power_entities[next_surface_key]
		if surface_table ~= nil then
			local first_entity_key = next(surface_table, nil)
			if first_entity_key ~= nil then
				return next_surface_key, first_entity_key
			end
		end
		next_surface_key = next(storage.power_entities, next_surface_key)
	end

	if current_surface_key ~= nil then
		next_surface_key = next(storage.power_entities, nil)
		while next_surface_key ~= nil and next_surface_key ~= current_surface_key do
			local surface_table = storage.power_entities[next_surface_key]
			if surface_table ~= nil then
				local first_entity_key = next(surface_table, nil)
				if first_entity_key ~= nil then
					return next_surface_key, first_entity_key
				end
			end
			next_surface_key = next(storage.power_entities, next_surface_key)
		end
	end

	return nil, nil
end

function init_globals()
	if storage.entities == nil then
		storage.entities = {}
	end
	if storage.power_entities == nil then
		storage.power_entities = {}
	end
	if storage.sum_ticks == nil then storage.sum_ticks = 0 end
	if storage.total_num_saved_items == nil then storage.total_num_saved_items = 0 end

	if storage.saved_items == nil then
		storage.saved_items = {}
	end
	if storage.saved_items_true == nil then
		storage.saved_items_true = {}
	end
	if storage.saved_items_per_lane == nil then
		storage.saved_items_per_lane = {}
	end
	
	if storage.num_saved_items_per_lane == nil then
		storage.num_saved_items_per_lane = {}
	end
	
	if storage.spilled_items == nil then
		storage.spilled_items = {}
	end
	if storage.preserve_mode_fallback_items == nil then
		storage.preserve_mode_fallback_items = 0
	end
	if storage.preserve_mode_slot_overflow_items == nil then
		storage.preserve_mode_slot_overflow_items = 0
	end

	if not storage.player_forces then storage.player_forces = {} end
	if storage.test_overrides == nil then
		storage.test_overrides = {}
	end

	migrate_surface_partition("entities")
	migrate_surface_partition("power_entities")
	prune_deleted_surfaces()

	storage.tick_iterator_key = nil
	storage.tick_surface_iterator_key = nil

	storage.belt_check_interval = 0.05
	storage.belt_interval = 0.25
	storage.ground_lanes_max_check = 1.0
	storage.fill_trial_interval = 0.025
	storage.ver = current_version
end

---- INIT ----
script.on_init(function()
	init_globals()
	find_all_power_entities()
end)

script.on_configuration_changed(function()
	init_globals()
	find_all_power_entities()
end)

function get_correct_belt_level(force)
	local force_name = force.name
	local belt_level = 0
	if storage.player_forces[force_name] and storage.player_forces[force_name]['belt_level'] then
		belt_level = storage.player_forces[force_name]['belt_level']
	end
	belt_level = math.max(0, math.floor(belt_level))
	local max_level_setting = settings.startup["powered-belts-num-upgrades"]
	local max_level = 5
	if max_level_setting ~= nil then
		max_level = math.max(0, math.floor(max_level_setting.value))
	end
	if belt_level > max_level then
		belt_level = max_level
	end
	return belt_level
end

function extract_number_from_string(str)
    local number = str:match("%d+")
    return tonumber(number)
end

function tech_check(event)
	--game.print(event.research.name)
	--game.print(event.research.level)
	if string.match(event.research.name, "efficient%-belts%-") then
		local force_name = event.research.force.name
		
		if storage.player_forces[force_name] == nil then
			storage.player_forces[force_name] = {}
		end
		local tech_level = extract_number_from_string(event.research.name)
		if tech_level ~= nil then
			storage.player_forces[force_name]['belt_level'] = tech_level
		end
	end
end

function string:endswith(suffix)
    return self:sub(-#suffix) == suffix
end

function string:startswith(prefix)
    return self:sub(1, #prefix) == prefix
end

local function is_unpowered_name(name)
	return type(name) == "string" and string.match(name, "^unpowered%-") ~= nil
end

local function base_powered_name(name)
	if not is_unpowered_name(name) then
		return name
	end
	return string.sub(name, 11)
end

local function adapt_upgrade_target_name_for_entity(target_name, entity_name)
	if type(target_name) ~= "string" then
		return nil
	end
	if is_unpowered_name(entity_name) then
		if is_unpowered_name(target_name) then
			return target_name
		end
		return "unpowered-" .. target_name
	end
	return base_powered_name(target_name)
end

local function read_deconstruction_mark(entity)
	local ok, marked = pcall(function()
		return entity.to_be_deconstructed(entity.force)
	end)
	if ok then
		return marked == true
	end
	ok, marked = pcall(function()
		return entity.to_be_deconstructed()
	end)
	if ok then
		return marked == true
	end
	return false
end

local function read_upgrade_mark(entity)
	local ok, marked = pcall(function()
		return entity.to_be_upgraded(entity.force)
	end)
	if ok then
		return marked == true
	end
	ok, marked = pcall(function()
		return entity.to_be_upgraded()
	end)
	if ok then
		return marked == true
	end
	return false
end

local function read_upgrade_target_name(entity)
	local ok, target = pcall(function()
		return entity.get_upgrade_target()
	end)
	if ok and target ~= nil and target.valid and target.name ~= nil then
		return target.name
	end
	return nil
end

local function capture_entity_planner_state(entity)
	if not (entity and entity.valid) then
		return nil
	end
	local upgrade_target_name = read_upgrade_target_name(entity)
	return {
		deconstruction_marked = read_deconstruction_mark(entity),
		upgrade_marked = read_upgrade_mark(entity) or upgrade_target_name ~= nil,
		upgrade_target_name = upgrade_target_name,
	}
end

local function apply_entity_planner_state(entity, planner_state)
	if not (entity and entity.valid and planner_state ~= nil) then
		return
	end

	if planner_state.deconstruction_marked then
		pcall(function()
			entity.order_deconstruction(entity.force)
		end)
	end

	if planner_state.upgrade_marked then
		local target_name = adapt_upgrade_target_name_for_entity(planner_state.upgrade_target_name, entity.name)
		local ordered = false
		if target_name ~= nil and game ~= nil and prototypes.entity ~= nil then
			local target_prototype = prototypes.entity[target_name]
			if target_prototype ~= nil then
				local ok = pcall(function()
					entity.order_upgrade{force = entity.force, target = target_prototype}
				end)
				ordered = ok == true
			end
		end
		if not ordered then
			pcall(function()
				entity.order_upgrade{force = entity.force}
			end)
		end
	end
end

function get_entity_idx(entity)
	return entity.position.x .. " " .. entity.position.y
end

function get_entity_idx_from_position(position)
	return position.x .. " " .. position.y
end

function clear_power_entity(pos, surface)
	local surface_key, _, power_entities_by_surface = get_surface_tables(surface, false)
	if power_entities_by_surface ~= nil and power_entities_by_surface[pos] ~= nil then
		local ent = power_entities_by_surface[pos]
		if ent.valid then
			ent.destroy()
		end
		power_entities_by_surface[pos] = nil
		cleanup_empty_surface_tables(surface_key)
	end
end

function clear_tile(pos, surface)
	local surface_key, entities_by_surface, _ = get_surface_tables(surface, false)
	if entities_by_surface ~= nil and entities_by_surface[pos] ~= nil then
		entities_by_surface[pos] = nil
    end
	clear_power_entity(pos, surface)
	cleanup_empty_surface_tables(surface_key)
end

function get_correct_power_entity_name(base_name, force)
	local correct_level = get_correct_belt_level(force)
	local usage_name = tostring(settings.startup["powered-belts-usage-multiplier"].value):gsub("%.", "_")
	local upgrade_name = tostring(settings.startup["powered-belts-upgrade-reduction"].value):gsub("%.", "_")
	local name = base_name .. "-" .. usage_name .. "-" .. upgrade_name ..  "-" .. correct_level .. "-power"
	return name
end

function create_power_entity(base_name, surface, position, force, direction, base_name_is_correct)
	local pos = get_entity_idx_from_position(position)
	clear_power_entity(pos, surface)
	local name = base_name
	if not base_name_is_correct then
		name = get_correct_power_entity_name(base_name, force)
	end
	local _, _, power_entities_by_surface = get_surface_tables(surface, true)
	power_entities_by_surface[pos] = surface.create_entity{
		name = name,
		position = position,
		force = force,
		direction = direction,
		destructible = false
	}
end

function extract_base_name_from_entity_to_power(name)
	local base_name = name
	if string.match(name, "^unpowered%-") then
		base_name = string.sub(name, 11)
	end
	return base_name
end

function check_and_replace_power_entity(entity_to_power, power_entity)
	local base_name = extract_base_name_from_entity_to_power(entity_to_power.name)
	
	local correct_name = get_correct_power_entity_name(base_name, entity_to_power.force)
	if power_entity == nil or (not power_entity.valid) or correct_name ~= power_entity.name or entity_to_power.force.name ~= power_entity.force.name then
		create_power_entity(correct_name, entity_to_power.surface, entity_to_power.position, entity_to_power.force, entity_to_power.direction, true)
	end

end

function find_all_entities_to_power_at_position(surface, position, radius)
	local entities = surface.find_entities_filtered{position=position, radius=radius}
	local entities_to_power = {}
	for k,v in pairs(entities) do
		if (not string.endswith(v.name, '-power')) and belt_entity_types[v.type] then
			entities_to_power[get_entity_idx(v)] = v
			--game.print("ent: " .. get_entity_idx(v))
		end
	end
	return entities_to_power
end

function init_entity(entity)
	local pos = get_entity_idx(entity)
	clear_tile(pos, entity.surface)
	local _, entities_by_surface, power_entities_by_surface = get_surface_tables(entity.surface, true)
	local correct_name = get_correct_power_entity_name(extract_base_name_from_entity_to_power(entity.name), entity.force)
	power_entities_by_surface[pos] = entity.surface.create_entity{
		name = correct_name,
		position = entity.position,
		force = entity.force,
		direction = entity.direction,
		destructible = false
	}
	entities_by_surface[pos] = entity
end

function find_all_entities_powered()
	game.print("Checking entities to be powered..")

	local num_wrongly_present_and_valid = 0
	local num_wrongly_present = 0
	local num_nil = 0
	local num_entity_invalid = 0
	local num_init = 0
	local num_stale_entries = 0

	for _, surface in pairs(game.surfaces) do
		local surface_key = get_surface_key(surface)
		local entities = surface.find_entities_filtered{type = belt_entity_type_list}
		local seen_positions = {}
		for _, v in pairs(entities) do
			if v.valid then
				local pos = get_entity_idx(v)
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
					init_entity(v)
					num_init = num_init + 1
				else
					check_and_replace_power_entity(v, power_entities_by_surface and power_entities_by_surface[pos] or nil)
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
				clear_tile(pos, surface)
				num_stale_entries = num_stale_entries + 1
			end
		end

		cleanup_empty_surface_tables(surface_key)
	end

	if num_entity_invalid > 0 then game.print("Warning: num entity invalid: " .. num_entity_invalid) end
	--game.print("Num nil: " .. num_nil)
	if num_wrongly_present > 0 then game.print("Warning: num wrongly present (invalid): " .. num_wrongly_present) end
	if num_wrongly_present_and_valid > 0 then game.print("Warning: num wrongly present and valid: " .. num_wrongly_present_and_valid) end
	if num_stale_entries > 0 then game.print("Warning: num stale entity-table entries removed: " .. num_stale_entries) end
	game.print("PBE_CheckPowerEntities command repaired: " .. num_init .. " entities.")
end

function find_all_power_entities()
	find_all_entities_powered()
	game.print("Checking power entities..")
	local num_destroyed_entities = 0
	local num_remapped_power_entries = 0
	local num_removed_invalid_power_entries = 0
	for _, surface in pairs(game.surfaces) do
		local surface_key = get_surface_key(surface)
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
					local target_pos = get_entity_idx(stored_entity)
					local _, _, target_power_entities_by_surface = get_surface_tables(stored_entity.surface, true)
					if target_power_entities_by_surface[target_pos] == nil then
						target_power_entities_by_surface[target_pos] = stored_entity
					end
					num_remapped_power_entries = num_remapped_power_entries + 1
				else
					local actual_pos = get_entity_idx(stored_entity)
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
		local entities = surface.find_entities_filtered{type = "electric-energy-interface"}
		local power_entities_temp = {}
		for _, v in pairs(entities) do
			if string.endswith(v.name, '-power') then
				local pos = get_entity_idx(v)
				local valid_entity = true
				if power_entities_temp[pos] ~= nil then
					game.print('Warning: double power entity (destroying it now) at position: ' .. pos)
					v.destroy()
					valid_entity = false
					num_destroyed_entities = num_destroyed_entities + 1
				end
				
				local entities_to_power = nil
				if valid_entity then
					entities_to_power = find_all_entities_to_power_at_position(surface, v.position, 1)
					if entities_to_power[pos] == nil then
						--game.print("Warning: ... entity to be powered DOES NOT exist the position of power entity (removing power entity now), position: " .. pos)
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
					game.print('Warning: power entity does not have entry in entities table (checking whether object exists), position: ' .. pos)
					
					if entities_to_power[pos] ~= nil then -- entities_to_power won't be nil because valid_entity check as when setting entities_to_power
						game.print("Warning: ... AND entity to be powered exists at this position (assigning it now)!: " .. entities_to_power[pos].name)
						local _, entities_by_surface_new = get_surface_tables(surface, true)
						entities_by_surface_new[pos] = entities_to_power[pos]
					else
						game.print("Warning: ... AND entity to be powered DOES NOT exist at this position (removing power entity now)!")
						v.destroy()
						if power_entities_by_surface ~= nil then power_entities_by_surface[pos] = nil end
						valid_entity = false
						num_destroyed_entities = num_destroyed_entities + 1
					end
					
				
				elseif valid_entity and (power_entities_by_surface == nil or power_entities_by_surface[pos] ~= v) then
					game.print('Warning: this power entity does not have entry in power entities table, position: (assigning it now)' .. pos)
					local _, _, power_entities_by_surface_new = get_surface_tables(surface, true)
					power_entities_by_surface_new[pos] = v
				end
				
				if valid_entity then power_entities_temp[pos] = v end
			end
		end
		cleanup_empty_surface_tables(surface_key)
	end

	if num_removed_invalid_power_entries > 0 then game.print("Warning: removed invalid power-table entries: " .. num_removed_invalid_power_entries) end
	if num_remapped_power_entries > 0 then game.print("Warning: remapped misplaced power-table entries: " .. num_remapped_power_entries) end
	game.print("PBE_CheckPowerEntities command cleaned up: " .. num_destroyed_entities .. " power entities.")

end



---- ON EVENT ----
script.on_event({
	defines.events.on_robot_built_entity,
	defines.events.on_built_entity,
	defines.events.script_raised_built,
	defines.events.script_raised_revive,
}, function(event)
	local entity = event.entity
	if entity and belt_entity_types[entity.type] then
		init_entity(entity)
	end
end)

script.on_event({
	defines.events.on_entity_died,
	defines.events.on_robot_mined_entity,
	defines.events.on_player_mined_entity,
	defines.events.script_raised_destroy,
	}, function(event)
	if event.entity then
		local pos = get_entity_idx(event.entity)
		clear_tile(pos, event.entity.surface)
	end
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
		return storage.ground_lanes_max_check
	end
	return storage.ground_lanes_max_check + underground_len - 1.0
end

local preserve_mode_temp_inventory_initial_size = 64
local preserve_mode_temp_inventory_max_size = 65535

local function normalize_underground_transfer_mode(mode)
	if type(mode) ~= "string" then
		return default_underground_transfer_mode
	end
	if underground_transfer_modes[mode] then
		return mode
	end
	return default_underground_transfer_mode
end

local function get_effective_underground_transfer_mode()
	if storage and storage.test_overrides and storage.test_overrides.underground_item_transfer_mode ~= nil then
		return normalize_underground_transfer_mode(storage.test_overrides.underground_item_transfer_mode)
	end
	local setting = settings.global[underground_transfer_mode_setting_name]
	if setting == nil then
		return default_underground_transfer_mode
	end
	return normalize_underground_transfer_mode(setting.value)
end

local function preserve_mode_enabled(mode)
	local effective_mode = mode
	if effective_mode == nil then
		effective_mode = get_effective_underground_transfer_mode()
	end
	return normalize_underground_transfer_mode(effective_mode) == "preserve-full-state"
end

local function underground_item_transfer_disabled(mode)
	local effective_mode = mode
	if effective_mode == nil then
		effective_mode = get_effective_underground_transfer_mode()
	end
	return normalize_underground_transfer_mode(effective_mode) == "disabled"
end

local function get_required_energy_setting()
	if storage and storage.test_overrides and type(storage.test_overrides.required_energy) == "number" then
		return storage.test_overrides.required_energy
	end
	local setting = settings.global["powered-belts-required-energy"]
	if setting ~= nil then
		return setting.value
	end
	return 500
end

local function get_operations_per_tick_setting()
	if storage and storage.test_overrides and type(storage.test_overrides.operations_per_tick) == "number" then
		return math.max(1, math.floor(storage.test_overrides.operations_per_tick))
	end
	local setting = settings.global["powered-belts-operations-per-tick"]
	if setting ~= nil then
		return math.max(1, math.floor(setting.value))
	end
	return 16
end

local function get_item_name_for_stats(item)
	if type(item) == "string" then
		return item
	end
	if item ~= nil and item.name ~= nil then
		return item.name
	end
	return "_unknown-item"
end

local function append_items(items, positions, item_name, item_count, position)
	if item_name == nil then
		return
	end
	local count = math.max(0, math.floor(item_count or 0))
	for _ = 1, count do
		items[#items + 1] = item_name
		positions[#positions + 1] = position
	end
end

local function append_item_token(items, positions, token, position)
	items[#items + 1] = token
	positions[#positions + 1] = position
end

local function ensure_preserve_temp_inventory(replace_context)
	if replace_context == nil or (not replace_context.preserve_mode) then
		return false
	end

	if replace_context.temp_inventory ~= nil and replace_context.temp_inventory.valid then
		return true
	end

	replace_context.temp_inventory = game.create_inventory(preserve_mode_temp_inventory_initial_size)
	replace_context.temp_inventory_next_slot = 1
	return replace_context.temp_inventory ~= nil and replace_context.temp_inventory.valid
end

local function reserve_preserve_temp_slot(replace_context)
	if not ensure_preserve_temp_inventory(replace_context) then
		return nil, nil
	end

	local inventory = replace_context.temp_inventory
	local slot_idx = replace_context.temp_inventory_next_slot or 1

	if slot_idx > preserve_mode_temp_inventory_max_size then
		storage.preserve_mode_slot_overflow_items = (storage.preserve_mode_slot_overflow_items or 0) + 1
		return nil, nil
	end

	if slot_idx > #inventory then
		local resized_to = math.min(preserve_mode_temp_inventory_max_size, math.max(slot_idx, #inventory * 2))
		inventory.resize(resized_to)
	end

	local slot = inventory[slot_idx]
	if slot == nil then
		storage.preserve_mode_slot_overflow_items = (storage.preserve_mode_slot_overflow_items or 0) + 1
		return nil, nil
	end

	replace_context.temp_inventory_next_slot = slot_idx + 1
	return slot_idx, slot
end

local function capture_line_item(lane, line_item, current_position, items, positions, replace_context)
	if not (line_item and line_item.valid_for_read) then
		return 0
	end

	local item_name = get_item_name_for_stats(line_item)
	if replace_context == nil or (not replace_context.preserve_mode) then
		local removed = lane.remove_item(line_item)
		if removed > 0 then
			append_items(items, positions, item_name, removed, current_position)
		end
		return removed
	end

	local removed = 0
	while line_item.valid_for_read and line_item.count > 0 do
		local slot_idx, slot = reserve_preserve_temp_slot(replace_context)
		if slot_idx == nil or slot == nil then
			break
		end

		local moved = slot.transfer_stack(line_item, 1)
		if not moved then
			break
		end

		removed = removed + 1
		append_item_token(items, positions, {name = item_name, slot = slot_idx}, current_position)
	end

	if line_item.valid_for_read and line_item.count > 0 then
		local fallback_removed = lane.remove_item(line_item)
		if fallback_removed > 0 then
			storage.preserve_mode_fallback_items = (storage.preserve_mode_fallback_items or 0) + fallback_removed
			append_items(items, positions, item_name, fallback_removed, current_position)
			removed = removed + fallback_removed
		end
	end

	return removed
end

local function get_item_identification_for_transfer(item, replace_context)
	if type(item) == "table" and item.slot ~= nil then
		if replace_context ~= nil and replace_context.temp_inventory ~= nil and replace_context.temp_inventory.valid then
			local slot = replace_context.temp_inventory[item.slot]
			if slot ~= nil and slot.valid_for_read then
				return slot, true
			end
		end
		storage.preserve_mode_fallback_items = (storage.preserve_mode_fallback_items or 0) + 1
		return get_item_name_for_stats(item), false
	end
	return item, false
end

local function consume_preserved_item_token(item, replace_context)
	if type(item) == "table" and item.slot ~= nil and replace_context ~= nil and replace_context.temp_inventory ~= nil and replace_context.temp_inventory.valid then
		local slot = replace_context.temp_inventory[item.slot]
		if slot ~= nil and slot.valid_for_read then
			slot.clear()
		end
	end
end

function position_capturing_algorithm(lane, max_check, replace_context)
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
				game.print("Warning: did not remove an item!")
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
				game.print("Warning: did not remove an item!")
			end
		
		end
	end
	
	if lane.valid and #lane ~= 0 then
		game.print("Warning: did not remove all items; left (clearing now): " .. #lane)
		lane.clear()
	end
	
	return items, positions
end

function check_and_clear_lane(lane, max_check, replace_context)
	if not (lane and lane.valid) then
		return {}, {}
	end
	return position_capturing_algorithm(lane, max_check, replace_context)
end

function check_and_clear_lanes(underground, underground_len, replace_context)
	local n = underground.neighbours
	
	local lanes_items = {}
	local lanes_positions = {}
	
    for lane_idx = 1, 2 do
   		local lane = underground.get_transport_line(lane_idx)
		--[[
		if not (lane and lane.valid) then
			game.print("Warning: invalid line")
		end
		--]]
		if lane and lane.valid then
			local max_check = lane_max_check(underground, lane_idx, underground_len)
			local items, positions = check_and_clear_lane(lane, max_check, replace_context)
			lanes_items[lane_idx] = items
			lanes_positions[lane_idx] = positions
		end
		
	end
	
	if underground.belt_to_ground_type == "input" or n == nil then
		for lane_idx = 3, 4 do
			local lane = underground.get_transport_line(lane_idx)
			--[[
			if not (lane and lane.valid) then
				game.print("Warning: invalid line")
			end
			--]]
			if lane and lane.valid then
				local max_check = lane_max_check(underground, lane_idx, underground_len)
				local items, positions = check_and_clear_lane(lane, max_check, replace_context)
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

function fill_lane(underground, lane_idx, items, positions, starting_item_idx, obey_positions, underground_len, replace_context)
	local max_check = lane_max_check(underground, lane_idx, underground_len)
	local lane = underground.get_transport_line(lane_idx)
	if not (lane and lane.valid) then
		return
	end
	--[[
	if not (lane and lane.valid) then
		game.print("Warning: invalid line")
	end
	--]]
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
		local item_name = get_item_name_for_stats(item)
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
			local item_identification, requires_consume = get_item_identification_for_transfer(item, replace_context)
			if lane.insert_at(current_check, item_identification) then
				if requires_consume then
					consume_preserved_item_token(item, replace_context)
				end
				inserted = inserted + 1
				add_count(storage.saved_items, item_name, 1)
			else
				break
			end
			
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
		local grouped_spills = {}
		
		for item_idx = starting_item_idx+inserted, #items do
			item = items[item_idx]
			local item_name = get_item_name_for_stats(item)
			local item_identification, requires_consume = get_item_identification_for_transfer(item, replace_context)
			
			add_count(storage.spilled_items, item_name, 1)
			add_count(storage.saved_items, item_name, 1)
			add_count(counts, item_name, 1)
			if requires_consume then
				underground.surface.spill_item_stack{
					position = underground.position,
					stack = item_identification,
					enable_looted = true,
					force = underground.force,
					allow_belts = false
				}
				consume_preserved_item_token(item, replace_context)
			else
				add_count(grouped_spills, item_name, 1)
			end
			c = c + 1
		end
		
		add_count(storage.spilled_items, '_total', c)
		
		game.print("Spilled " .. c .. " items at  x=" .. underground.position.x .. ", y=" .. underground.position.y .. ": ")
		for k, v in pairs(grouped_spills) do
			underground.surface.spill_item_stack{
				position = underground.position,
				stack = {name = k, count = v},
				enable_looted = true,
				force = underground.force,
				allow_belts = false
			}
		end
		game.print(collection_to_string(counts))
	end
	add_count(storage.saved_items, '_total', inserted + c)
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
				local item_name = get_item_name_for_stats(items[item_idx])
				add_count(saved_items, item_name, 1)
				add_count(saved_items_per_lane[get_lane_identifier(underground, lane_idx)], item_name, 1)
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
		--[[
		if not (lane and lane.valid) then
			game.print("Warning: invalid line")
		end
		--]]
		if lane and lane.valid then
			for _, detailed_item in pairs(lane.get_detailed_contents()) do
				local line_item = detailed_item.stack
				if line_item and line_item.valid_for_read then
					local item = get_item_name_for_stats(line_item)
					local item_count = math.max(0, math.floor(line_item.count or 0))
					for _ = 1, item_count do
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
		local saved_items_n, saved_items_per_lane_n, num_saved_items_per_lane_n, num_saved_items_n = get_saved_items(neighbour, lanes_items_n)
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
		add_counter_create_key(storage.saved_items_per_lane, v, k)
	end
	
	add_counter(storage.num_saved_items_per_lane, num_saved_items_per_lane)
	add_counter(storage.saved_items_true, saved_items)
	storage.total_num_saved_items = storage.total_num_saved_items + num_saved_items
	
end

function fill_lanes(underground, lanes_items, lanes_positions, underground_len, replace_context)
	if lanes_items == nil then
		return
	end
	
	for lane_idx = 4, 1, -1 do
		local items = lanes_items[lane_idx]
		if items ~= nil then
			local positions = lanes_positions[lane_idx]
			fill_lane(underground, lane_idx, items, positions, 1, true, underground_len, replace_context)
		end
	end
end

function call_replace(surface, entity_idx, entity_data)
	local new_entity = entity_data.surface.create_entity{
		name = entity_data.new_name,
		position = entity_data.position,
		force = entity_data.force,
		direction = entity_data.direction,
		type = entity_data.belt_to_ground_type,
		fast_replace = true,
		spill = false
	}
	
	local _, entities_by_surface = get_surface_tables(surface, true)
	entities_by_surface[entity_idx] = new_entity
	return new_entity
	
end

function replace_entity(entity, surface, entity_idx, check_for_neighbour, power_up, underground_len, replace_context)
	local own_replace_context = false
	if replace_context == nil then
		local underground_transfer_mode = get_effective_underground_transfer_mode()
		replace_context = {
			underground_transfer_mode = underground_transfer_mode,
			preserve_mode = preserve_mode_enabled(underground_transfer_mode),
			disable_item_transfer = underground_item_transfer_disabled(underground_transfer_mode),
			temp_inventory = nil,
			temp_inventory_next_slot = 1
		}
		own_replace_context = true
	end

	local planner_state = capture_entity_planner_state(entity)
	local entity_data = {surface = entity.surface, name = entity.name, position = entity.position, force = entity.force, direction = entity.direction}
	local is_underground = entity.type == "underground-belt"
	local n = nil
	local lanes_items = nil
	local lanes_positions = nil
	if is_underground then
		n = entity.neighbours
		entity_data.belt_to_ground_type = entity.belt_to_ground_type
		if not replace_context.disable_item_transfer then
			lanes_items, lanes_positions = check_and_clear_lanes(entity, underground_len, replace_context)
		end
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
		n_lanes_items, n_lanes_positions = run_for_entity(n, surface, neighbour_idx, false, underground_len, power_up, not power_up, replace_context)
		--n_lanes_items, n_lanes_positions = replace_entity(n, neighbour_idx, false, power_up, underground_len)
	end
	
	local new_entity = call_replace(surface, entity_idx, entity_data)
	local _, entities_by_surface = get_surface_tables(surface, false)
	
	if is_underground then
		if (not replace_context.disable_item_transfer) and neighbour_cond then
			local neighbour_entity = nil
			if entities_by_surface ~= nil then
				neighbour_entity = entities_by_surface[neighbour_idx]
			end
			check_lanes(new_entity, neighbour_entity, lanes_items, n_lanes_items)
			if new_entity.belt_to_ground_type == "input" then
				fill_lanes(new_entity, lanes_items, lanes_positions, underground_len, replace_context)
				if n_lanes_items ~= nil and n_lanes_positions ~= nil and neighbour_entity ~= nil then
					fill_lanes(neighbour_entity, n_lanes_items, n_lanes_positions, underground_len, replace_context)
				end
				
			else
				if n_lanes_items ~= nil and n_lanes_positions ~= nil and neighbour_entity ~= nil then
					fill_lanes(neighbour_entity, n_lanes_items, n_lanes_positions, underground_len, replace_context)
				end
				fill_lanes(new_entity, lanes_items, lanes_positions, underground_len, replace_context)
				
			end
			
		--elseif check_for_neighbour then
		elseif (not replace_context.disable_item_transfer) and check_for_neighbour then
			fill_lanes(new_entity, lanes_items, lanes_positions, underground_len, replace_context)
		
		end
	end

	apply_entity_planner_state(new_entity, planner_state)

	if own_replace_context and replace_context.temp_inventory ~= nil and replace_context.temp_inventory.valid then
		replace_context.temp_inventory.destroy()
	end
	return lanes_items, lanes_positions
	

end

function run_for_entity(entity, surface, entity_idx, check_for_neighbour, underground_len, powerup_n, powerdown_n, replace_context)
	-- TODO/IDEA: only powered up when both neighbours powered up? otherwise both power down?
	local _, entities_by_surface, power_entities_by_surface = get_surface_tables(surface, true)
	if entity.valid and entities_by_surface ~= nil and entities_by_surface[entity_idx] ~= nil then
		check_and_replace_power_entity(entity, power_entities_by_surface and power_entities_by_surface[entity_idx] or nil)
		local power_entity = power_entities_by_surface and power_entities_by_surface[entity_idx] or nil
		if power_entity == nil or (not power_entity.valid) then
			return nil, nil
		end
		local required_energy = math.min(get_required_energy_setting(), power_entity.electric_buffer_size * 0.75)
		if string.match(entity.name, "^unpowered%-") and (power_entity.energy >= required_energy or powerup_n) then
			return replace_entity(entity, surface, entity_idx, check_for_neighbour, true, underground_len, replace_context)
			
		elseif (not string.match(entity.name, "^unpowered%-")) and (power_entity.energy < required_energy or powerdown_n) then
			return replace_entity(entity, surface, entity_idx, check_for_neighbour, false, underground_len, replace_context)
		end
	end
	return nil, nil
end

local function push_snapshot_detail(collection, value, max_entries)
	if #collection < max_entries then
		collection[#collection + 1] = value
	end
end

local function get_surface_state_snapshot(surface, max_details)
	local surface_key = get_surface_key(surface)
	local entities_by_surface = storage.entities[surface_key] or {}
	local power_entities_by_surface = storage.power_entities[surface_key] or {}
	local world_entities = surface.find_entities_filtered{type = belt_entity_type_list}
	local world_all_power_entities = surface.find_entities_filtered{type = "electric-energy-interface"}

	local world_entities_by_pos = {}
	local world_power_counts_by_pos = {}
	local world_power_by_pos = {}
	local world_power_entities = {}

	for _, entity in pairs(world_entities) do
		if entity and entity.valid then
			world_entities_by_pos[get_entity_idx(entity)] = entity
		end
	end

	for _, power_entity in pairs(world_all_power_entities) do
		if power_entity and power_entity.valid and string.endswith(power_entity.name, "-power") then
			local pos = get_entity_idx(power_entity)
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
			local expected_name = get_correct_power_entity_name(extract_base_name_from_entity_to_power(entity.name), entity.force)
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

function get_state_snapshot(surface_index)
	local requested_surface = nil
	if surface_index ~= nil then
		requested_surface = game.surfaces[surface_index]
	end
	local max_details = 128
	local snapshot = {
		tick = game.tick,
		underground_item_transfer_mode = get_effective_underground_transfer_mode(),
		required_energy_setting = get_required_energy_setting(),
		operations_per_tick_setting = get_operations_per_tick_setting(),
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

function set_test_overrides(overrides)
	if type(overrides) ~= "table" then
		storage.test_overrides = {}
		return storage.test_overrides
	end

	local sanitized = {}
	if overrides.underground_item_transfer_mode ~= nil then
		sanitized.underground_item_transfer_mode = normalize_underground_transfer_mode(overrides.underground_item_transfer_mode)
	end
	if type(overrides.required_energy) == "number" then
		sanitized.required_energy = math.max(0, overrides.required_energy)
	end
	if type(overrides.operations_per_tick) == "number" then
		sanitized.operations_per_tick = math.max(1, math.floor(overrides.operations_per_tick))
	end

	storage.test_overrides = sanitized
	return storage.test_overrides
end

function run_full_scan()
	find_all_power_entities()
	return get_state_snapshot()
end

if rawget(_G, "__PBE_UNIT_TEST_MODE") then
	_G.__PBE_TEST_API = {
		normalize_underground_transfer_mode = normalize_underground_transfer_mode,
		preserve_mode_enabled = preserve_mode_enabled,
		underground_item_transfer_disabled = underground_item_transfer_disabled,
	}
end



---- ON TICK ----
script.on_event(defines.events.on_tick, function(event)
	if storage.ver ~= current_version then
		init_globals()
	end
	storage.sum_ticks = storage.sum_ticks + 1
    if storage.power_entities ~= nil and storage.entities ~= nil and next(storage.power_entities) then
		for _ = 1, get_operations_per_tick_setting() do
			local surface_key, entity_key = get_next_power_entity_iterator()
			if surface_key == nil or entity_key == nil then
				storage.tick_surface_iterator_key = nil
				storage.tick_iterator_key = nil
				break
			end
			local surface = game.surfaces[surface_key]
			local entities_by_surface = storage.entities[surface_key]
			local power_entities_by_surface = storage.power_entities[surface_key]
			local entity = entities_by_surface and entities_by_surface[entity_key] or nil
			if surface == nil then
				storage.entities[surface_key] = nil
				storage.power_entities[surface_key] = nil
			elseif entity == nil or (not entity.valid) then
				clear_tile(entity_key, surface)
			elseif power_entities_by_surface ~= nil and power_entities_by_surface[entity_key] ~= nil then
				run_for_entity(entity, surface, entity_key, true, underground_length(entity), false, false)
			end
			if storage.power_entities[surface_key] ~= nil and storage.power_entities[surface_key][entity_key] ~= nil then
				storage.tick_surface_iterator_key = surface_key
				storage.tick_iterator_key = entity_key
			else
				if storage.power_entities[surface_key] ~= nil then
					storage.tick_surface_iterator_key = surface_key
				else
					storage.tick_surface_iterator_key = nil
				end
				storage.tick_iterator_key = nil
			end
		end
	end
end)
script.on_event({defines.events.on_research_finished}, tech_check)
commands.add_command("PBE_CheckPowerEntities", "Checks and cleans power entities on all surfaces", find_all_power_entities)
remote.add_interface("powered_belts_extended", {
  get_storage = function() return storage end,
  run_full_scan = run_full_scan,
  get_state_snapshot = get_state_snapshot,
  set_test_overrides = set_test_overrides,
})
