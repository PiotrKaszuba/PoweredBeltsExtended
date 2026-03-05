local utils = {}

utils.current_version = 120
utils.belt_entity_types = {
	["transport-belt"] = true,
	["underground-belt"] = true,
	["splitter"] = true,
	["loader"] = true,
	["loader-1x1"] = true,
}
utils.belt_entity_type_list = {"transport-belt", "underground-belt", "splitter", "loader", "loader-1x1"}
utils.underground_transfer_modes = {
	["name-only"] = true,
	["preserve-full-state"] = true,
	["disabled"] = true,
}
utils.default_underground_transfer_mode = "name-only"
utils.underground_transfer_mode_setting_name = "powered-belts-underground-item-transfer-mode"

local preserve_mode_temp_inventory_initial_size = 64
local preserve_mode_temp_inventory_max_size = 65535

function string:endswith(suffix)
    return self:sub(-#suffix) == suffix
end

function string:startswith(prefix)
    return self:sub(1, #prefix) == prefix
end

function utils.get_surface_key(surface)
	if not surface then
		return nil
	end
	return surface.index
end

function utils.get_surface_tables(surface, create_if_missing)
	local surface_key = utils.get_surface_key(surface)
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

function utils.cleanup_empty_surface_tables(surface_key)
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

function utils.read_deconstruction_mark(entity)
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

function utils.capture_entity_planner_state(entity)
	if not (entity and entity.valid) then
		return nil
	end
	local upgrade_target_name = read_upgrade_target_name(entity)
	return {
		deconstruction_marked = utils.read_deconstruction_mark(entity),
		upgrade_marked = read_upgrade_mark(entity) or upgrade_target_name ~= nil,
		upgrade_target_name = upgrade_target_name,
	}
end

function utils.apply_entity_planner_state(entity, planner_state)
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

function utils.normalize_underground_transfer_mode(mode)
	if type(mode) ~= "string" then
		return utils.default_underground_transfer_mode
	end
	if utils.underground_transfer_modes[mode] then
		return mode
	end
	return utils.default_underground_transfer_mode
end

function utils.get_effective_underground_transfer_mode()
	if storage and storage.test_overrides and storage.test_overrides.underground_item_transfer_mode ~= nil then
		return utils.normalize_underground_transfer_mode(storage.test_overrides.underground_item_transfer_mode)
	end
	local setting = settings.global[utils.underground_transfer_mode_setting_name]
	if setting == nil then
		return utils.default_underground_transfer_mode
	end
	return utils.normalize_underground_transfer_mode(setting.value)
end

function utils.preserve_mode_enabled(mode)
	local effective_mode = mode
	if effective_mode == nil then
		effective_mode = utils.get_effective_underground_transfer_mode()
	end
	return utils.normalize_underground_transfer_mode(effective_mode) == "preserve-full-state"
end

function utils.underground_item_transfer_disabled(mode)
	local effective_mode = mode
	if effective_mode == nil then
		effective_mode = utils.get_effective_underground_transfer_mode()
	end
	return utils.normalize_underground_transfer_mode(effective_mode) == "disabled"
end

function utils.normalize_required_energy_percentage(value)
	if type(value) ~= "number" then
		return 50
	end
	return math.min(100, math.max(0, value))
end

function utils.get_required_energy_percentage_setting()
	if storage and storage.test_overrides and type(storage.test_overrides.required_energy_percentage) == "number" then
		return utils.normalize_required_energy_percentage(storage.test_overrides.required_energy_percentage)
	end
	local setting = settings.global["powered-belts-required-energy-percentage"]
	if setting ~= nil then
		return utils.normalize_required_energy_percentage(setting.value)
	end
	return 50
end

function utils.get_operations_per_tick_setting()
	if storage and storage.test_overrides and type(storage.test_overrides.operations_per_tick) == "number" then
		return math.max(1, math.floor(storage.test_overrides.operations_per_tick))
	end
	local setting = settings.global["powered-belts-operations-per-tick"]
	if setting ~= nil then
		return math.max(1, math.floor(setting.value))
	end
	return 16
end

function utils.get_item_name_for_stats(item)
	if type(item) == "string" then
		return item
	end
	if item ~= nil and item.name ~= nil then
		return item.name
	end
	return "_unknown-item"
end

function utils.append_items(items, positions, item_name, item_count, position)
	if item_name == nil then
		return
	end
	local count = math.max(0, math.floor(item_count or 0))
	for _ = 1, count do
		items[#items + 1] = item_name
		positions[#positions + 1] = position
	end
end

function utils.append_item_token(items, positions, token, position)
	items[#items + 1] = token
	positions[#positions + 1] = position
end

function utils.ensure_preserve_temp_inventory(replace_context)
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

function utils.reserve_preserve_temp_slot(replace_context)
	if not utils.ensure_preserve_temp_inventory(replace_context) then
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

function utils.get_item_identification_for_transfer(item, replace_context)
	if type(item) == "table" and item.slot ~= nil then
		if replace_context ~= nil and replace_context.temp_inventory ~= nil and replace_context.temp_inventory.valid then
			local slot = replace_context.temp_inventory[item.slot]
			if slot ~= nil and slot.valid_for_read then
				return slot, true
			end
		end
		storage.preserve_mode_fallback_items = (storage.preserve_mode_fallback_items or 0) + 1
		return utils.get_item_name_for_stats(item), false
	end
	return item, false
end

function utils.consume_preserved_item_token(item, replace_context)
	if type(item) == "table" and item.slot ~= nil and replace_context ~= nil and replace_context.temp_inventory ~= nil and replace_context.temp_inventory.valid then
		local slot = replace_context.temp_inventory[item.slot]
		if slot ~= nil and slot.valid_for_read then
			slot.clear()
		end
	end
end

return utils
