local M = {}

function M.clear_area(surface, area)
	local entities = surface.find_entities_filtered{area = area}
	for _, entity in pairs(entities) do
		if entity and entity.valid then
			entity.destroy()
		end
	end
end

function M.resolve_inventory(entity)
	if not (entity and entity.valid) then
		return nil
	end
	if entity.type == "container" or entity.type == "logistic-container" then
		return entity.get_inventory(defines.inventory.chest)
	end
	if entity.type == "inserter" and entity.burner then
		return entity.burner.inventory
	end
	return nil
end

function M.stack_list_to_map(stacks)
	local mapped = {}
	for _, stack in pairs(stacks or {}) do
		if stack.name ~= nil then
			mapped[stack.name] = (mapped[stack.name] or 0) + (stack.count or 0)
		end
	end
	return mapped
end

local function sum_numeric(value)
	if type(value) == "number" then
		return value
	end
	if type(value) ~= "table" then
		return 0
	end
	local total = 0
	for _, nested in pairs(value) do
		total = total + sum_numeric(nested)
	end
	return total
end

function M.contents_to_name_count_map(contents)
	local mapped = {}
	if type(contents) ~= "table" then
		return mapped
	end

	for key, value in pairs(contents) do
		-- Factorio 2.0 style: array entries like {name="iron-ore", quality="normal", count=60}
		if type(value) == "table" and value.name ~= nil and value.count ~= nil then
			mapped[value.name] = (mapped[value.name] or 0) + sum_numeric(value.count)
		-- Legacy map style: key is item name (or ItemID-like table), value is count/quality map
		else
			local name = nil
			if type(key) == "string" then
				name = key
			elseif type(key) == "table" and key.name ~= nil then
				name = key.name
			end
			if name ~= nil then
				mapped[name] = (mapped[name] or 0) + sum_numeric(value)
			end
		end
	end

	return mapped
end

function M.maps_equal(a, b)
	for key, value in pairs(a) do
		if b[key] ~= value then
			return false
		end
	end
	for key, value in pairs(b) do
		if a[key] ~= value then
			return false
		end
	end
	return true
end

local function is_unpowered_name(name)
	return type(name) == "string" and string.find(name, "unpowered-", 1, true) == 1
end

function M.base_powered_name(name)
	if not is_unpowered_name(name) then
		return name
	end
	return string.sub(name, 11)
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

function M.get_planner_state(entity)
	if not (entity and entity.valid) then
		return {
			valid = false,
			deconstruction_marked = false,
			upgrade_marked = false,
			upgrade_target_name = nil,
		}
	end

	local upgrade_target_name = read_upgrade_target_name(entity)
	local belt_to_ground_type = nil
	if entity.type == "underground-belt" then
		belt_to_ground_type = entity.belt_to_ground_type
	end
	return {
		valid = true,
		name = entity.name,
		type = entity.type,
		direction = entity.direction,
		belt_to_ground_type = belt_to_ground_type,
		deconstruction_marked = read_deconstruction_mark(entity),
		upgrade_marked = read_upgrade_mark(entity) or upgrade_target_name ~= nil,
		upgrade_target_name = upgrade_target_name,
	}
end

function M.inventory_fingerprint(inventory)
	if inventory == nil then
		return {}
	end
	local fingerprint = {}

	local function equipment_grid_signature(slot)
		local ok_grid, grid = pcall(function() return slot.grid end)
		if not ok_grid then
			return nil
		end
		if grid == nil then
			return nil
		end
		local equipment_entries = {}
		for _, equipment in pairs(grid.equipment) do
			equipment_entries[#equipment_entries + 1] = {
				name = equipment.name,
				position = {x = equipment.position.x, y = equipment.position.y},
				energy = equipment.energy or 0,
			}
		end
		table.sort(equipment_entries, function(a, b)
			if a.position.x ~= b.position.x then return a.position.x < b.position.x end
			if a.position.y ~= b.position.y then return a.position.y < b.position.y end
			return a.name < b.name
		end)
		return equipment_entries
	end

	local function stack_signature(slot)
		local function try_read(reader)
			local ok, value = pcall(reader)
			if ok then
				return value
			end
			return nil
		end

		local ok, exported = pcall(function()
			return slot.export_stack()
		end)
		if ok and exported ~= nil then
			return helpers.table_to_json(exported)
		end

		-- Some stacks are not exportable; fall back to a stable, comparable shape.
		local fallback = {
			name = slot.name,
			count = slot.count,
		}
		local health = try_read(function() return slot.health end)
		if health ~= nil then fallback.health = health end
		local durability = try_read(function() return slot.durability end)
		if durability ~= nil then fallback.durability = durability end
		local ammo = try_read(function() return slot.ammo end)
		if ammo ~= nil then fallback.ammo = ammo end
		local quality = try_read(function() return slot.quality end)
		if quality ~= nil then fallback.quality = quality.name end

		local grid_signature = equipment_grid_signature(slot)
		if grid_signature ~= nil then
			fallback.grid = grid_signature
		end
		return helpers.table_to_json(fallback)
	end

	for i = 1, #inventory do
		local slot = inventory[i]
		if slot and slot.valid_for_read then
			local signature = stack_signature(slot)
			fingerprint[signature] = (fingerprint[signature] or 0) + 1
		end
	end
	return fingerprint
end

local function compute_entity_bounds(placed_entities, area)
	local min_x, max_x, min_y, max_y = nil, nil, nil, nil
	for _, entity in pairs(placed_entities or {}) do
		if entity and entity.valid then
			local pos = entity.position
			if min_x == nil or pos.x < min_x then min_x = pos.x end
			if max_x == nil or pos.x > max_x then max_x = pos.x end
			if min_y == nil or pos.y < min_y then min_y = pos.y end
			if max_y == nil or pos.y > max_y then max_y = pos.y end
		end
	end

	if min_x == nil and area ~= nil then
		min_x = area.left_top.x + 1
		max_x = area.right_bottom.x - 1
		min_y = area.left_top.y + 1
		max_y = area.right_bottom.y - 1
	end
	return min_x, max_x, min_y, max_y
end

local function place_infrastructure_entity(surface, params)
	local entity = surface.create_entity(params)
	if entity ~= nil then
		return entity
	end
	return nil
end

local function enforce_direction(entity, desired_direction, entity_id)
	if desired_direction == nil or entity == nil or (not entity.valid) then
		return
	end
	if entity.direction == desired_direction then
		return
	end

	pcall(function()
		entity.direction = desired_direction
	end)
	if entity.direction == desired_direction then
		return
	end

	for _ = 1, 8 do
		local ok_rotate, rotated = pcall(function()
			return entity.rotate{reverse = false}
		end)
		if not ok_rotate or not rotated then
			break
		end
		if entity.direction == desired_direction then
			return
		end
	end

	log(string.format(
		"[PBE-HARNESS] direction mismatch for %s: expected=%s actual=%s name=%s",
		tostring(entity_id or "?"),
		tostring(desired_direction),
		tostring(entity.direction),
		tostring(entity.name)
	))
end

local function set_surface_daylight(surface, mode)
	local effective_mode = mode or "full-day"
	if effective_mode == "midnight" then
		-- Freeze at midnight to stop solar production while allowing accumulators
		-- and entity buffers to drain naturally.
		surface.always_day = false
		surface.daytime = 0.5
		surface.freeze_daytime = true
		return
	end
	if effective_mode == "full-day" or effective_mode == "day" then
		-- Deterministic full daylight with max solar production.
		surface.always_day = true
		surface.daytime = 0
		surface.freeze_daytime = false
		return
	end
	if effective_mode == "normal-cycle" then
		surface.always_day = false
		surface.freeze_daytime = false
		return
	end
	error("Unknown daylight mode: " .. tostring(effective_mode))
end

function M.bootstrap_daytime_and_power(surface, area, placed_entities)
	if not (surface and surface.valid) then
		return
	end

	set_surface_daylight(surface, "full-day")

	local min_x, max_x, min_y = compute_entity_bounds(placed_entities, area)
	if min_x == nil or max_x == nil or min_y == nil then
		return
	end

	local left = math.floor(min_x) - 1
	local right = math.ceil(max_x) + 1
	local lane_pole_y = math.floor(min_y + 2) + 0.5
	local solar_pole_y = lane_pole_y + 4
	local solar_y = solar_pole_y + 2

	for x = left, right, 6 do
		place_infrastructure_entity(surface, {
			name = "medium-electric-pole",
			position = {x = x + 0.5, y = lane_pole_y},
			force = game.forces.player,
		})
		place_infrastructure_entity(surface, {
			name = "medium-electric-pole",
			position = {x = x + 0.5, y = solar_pole_y},
			force = game.forces.player,
		})
	end

	for x = left, right, 3 do
		place_infrastructure_entity(surface, {
			name = "solar-panel",
			position = {x = x + 0.5, y = solar_y},
			force = game.forces.player,
		})
	end
end

local function build_placement_order(entities, build_order)
	if type(entities) ~= "table" then
		return {}
	end
	local ordered = {}
	for _, entity_def in ipairs(entities) do
		ordered[#ordered + 1] = {entity_def = entity_def}
	end
	if type(build_order) ~= "table" or build_order.mode == nil or build_order.mode == "normal" then
		return ordered
	end
	if build_order.mode == "reversed" then
		local reversed = {}
		for i = #ordered, 1, -1 do
			reversed[#reversed + 1] = ordered[i]
		end
		return reversed
	end
	if build_order.mode == "random" then
		local seed = build_order.seed
		if type(seed) ~= "number" then
			seed = game and game.tick or #ordered
		end
		local state = math.abs(math.floor(seed)) + 1
		local function next_random(max)
			state = (1103515245 * state + 12345) % 2147483648
			return (state % max) + 1
		end
		for i = #ordered, 2, -1 do
			local j = next_random(i)
			ordered[i], ordered[j] = ordered[j], ordered[i]
		end
		return ordered
	end
	return ordered
end

function M.place_layout(layout, surface, build_order)
	local created = {}
	for _, placement in ipairs(build_placement_order(layout.entities or {}, build_order)) do
		local entity_def = placement.entity_def
		local create_params = {
			name = entity_def.name,
			position = entity_def.position,
			direction = entity_def.direction,
			force = game.forces.player,
		}
		if entity_def.raise_built ~= false then
			create_params.raise_built = true
		end
		if entity_def.type ~= nil then
			create_params.type = entity_def.type
		end
		if entity_def.recipe ~= nil then
			create_params.recipe = entity_def.recipe
		end
		local entity = surface.create_entity(create_params)
		if entity == nil and create_params.raise_built ~= nil then
			create_params.raise_built = nil
			entity = surface.create_entity(create_params)
		end
		if entity == nil then
			error("Failed to place entity " .. (entity_def.id or entity_def.name))
		end
		enforce_direction(entity, entity_def.direction, entity_def.id)
		created[entity_def.id] = entity
	end
	return created
end

function M.get_referenced_entity(active, reference_name)
	local entities = M.get_referenced_entities(active, reference_name)
	for _, entity in ipairs(entities) do
		if entity and entity.valid then
			return entity
		end
	end
	return nil
end

local function resolve_reference_entity_ids(active, reference_name)
	local entity_id = reference_name
	if active.layout.references and active.layout.references[reference_name] ~= nil then
		entity_id = active.layout.references[reference_name]
	end
	if type(entity_id) == "table" then
		return entity_id
	end
	return {entity_id}
end

local function get_layout_entity_definition(active, entity_id)
	if active == nil or active.layout == nil or type(active.layout.entities) ~= "table" then
		return nil
	end
	for _, entity_def in ipairs(active.layout.entities) do
		if entity_def.id == entity_id then
			return entity_def
		end
	end
	return nil
end

local function get_position_key(position)
	if type(position) ~= "table" or position.x == nil or position.y == nil then
		return nil
	end
	return tostring(position.x) .. " " .. tostring(position.y)
end

local function resolve_entity_from_main_mod_storage(active, entity_id)
	if active == nil or active.surface == nil or (not active.surface.valid) then
		return nil
	end
	if not (remote.interfaces and remote.interfaces.powered_belts_extended and remote.interfaces.powered_belts_extended.get_storage) then
		return nil
	end

	local entity_def = get_layout_entity_definition(active, entity_id)
	if entity_def == nil then
		return nil
	end

	local pos_key = get_position_key(entity_def.position)
	if pos_key == nil then
		return nil
	end

	local ok_storage, storage = pcall(function()
		return remote.call("powered_belts_extended", "get_storage")
	end)
	if (not ok_storage) or type(storage) ~= "table" or type(storage.entities) ~= "table" then
		return nil
	end

	local by_surface = storage.entities[active.surface.index]
	if type(by_surface) ~= "table" then
		return nil
	end

	local entity = by_surface[pos_key]
	if entity and entity.valid then
		return entity
	end
	return nil
end

local function resolve_entity_from_surface(active, entity_id)
	if active == nil or active.surface == nil or (not active.surface.valid) then
		return nil
	end

	local entity_def = get_layout_entity_definition(active, entity_id)
	if entity_def == nil or type(entity_def.position) ~= "table" then
		return nil
	end

	local entities = active.surface.find_entities_filtered{
		position = entity_def.position,
		radius = 1.0,
	}
	if type(entities) ~= "table" then
		return nil
	end

	for _, entity in ipairs(entities) do
		if entity and entity.valid and entity.name ~= nil and string.find(entity.name, "%-power$", 1) == nil and M.base_powered_name(entity.name) == entity_def.name then
			return entity
		end
	end
	return nil
end

local function resolve_current_entity(active, entity_id)
	local entity = resolve_entity_from_main_mod_storage(active, entity_id)
	if entity ~= nil then
		return entity
	end
	return resolve_entity_from_surface(active, entity_id)
end

function M.get_referenced_entities(active, reference_name)
	local entity_ids = resolve_reference_entity_ids(active, reference_name)
	local entities = {}
	local function append_entity(entity_id)
		local entity = active.placed_entities[entity_id]
		if entity ~= nil and (not entity.valid) then
			entity = resolve_current_entity(active, entity_id)
			active.placed_entities[entity_id] = entity
		elseif entity == nil then
			entity = resolve_current_entity(active, entity_id)
			active.placed_entities[entity_id] = entity
		end
		if entity ~= nil then
			entities[#entities + 1] = entity
		end
	end
	for _, entity_id in ipairs(entity_ids) do
		append_entity(entity_id)
	end
	if #entities == 0 then
		for _, entity_id in pairs(entity_ids) do
			append_entity(entity_id)
		end
	end
	return entities
end

function M.get_referenced_inventories(active, reference_name)
	local inventories = {}
	for _, entity in ipairs(M.get_referenced_entities(active, reference_name)) do
		local inventory = M.resolve_inventory(entity)
		if inventory ~= nil then
			inventories[#inventories + 1] = inventory
		end
	end
	return inventories
end

function M.aggregate_inventory_contents(inventories)
	local totals = {}
	for _, inventory in ipairs(inventories or {}) do
		local ok, contents = pcall(function()
			return inventory.get_contents()
		end)
		if ok and contents ~= nil then
			local mapped = M.contents_to_name_count_map(contents)
			for item_name, count in pairs(mapped) do
				totals[item_name] = (totals[item_name] or 0) + count
			end
		end
	end
	return totals
end

function M.aggregate_inventory_total_count(inventories, item_name)
	local total = 0
	for _, inventory in ipairs(inventories or {}) do
		local ok, count = pcall(function()
			if item_name ~= nil then
				return inventory.get_item_count(item_name)
			end
			return inventory.get_item_count()
		end)
		if ok and type(count) == "number" then
			total = total + count
		end
	end
	return total
end

function M.aggregate_inventory_fingerprint(inventories)
	local combined = {}
	for _, inventory in ipairs(inventories or {}) do
		local fingerprint = M.inventory_fingerprint(inventory)
		for signature, count in pairs(fingerprint) do
			combined[signature] = (combined[signature] or 0) + count
		end
	end
	return combined
end

local function build_name_filter_lookup(item_names)
	if type(item_names) ~= "table" then
		return nil
	end
	local lookup = {}
	for _, item_name in pairs(item_names) do
		if type(item_name) == "string" and item_name ~= "" then
			lookup[item_name] = true
		end
	end
	if next(lookup) == nil then
		return nil
	end
	return lookup
end

function M.aggregate_ground_item_contents(surface, area, item_names)
	local totals = {}
	if not (surface and surface.valid) then
		return totals
	end

	local query = {name = "item-on-ground"}
	if type(area) == "table" then
		query.area = area
	end

	local name_filter = build_name_filter_lookup(item_names)
	local entities = surface.find_entities_filtered(query)
	for _, entity in pairs(entities or {}) do
		if entity and entity.valid and entity.stack and entity.stack.valid_for_read then
			local stack = entity.stack
			local item_name = stack.name
			if name_filter == nil or name_filter[item_name] then
				totals[item_name] = (totals[item_name] or 0) + (stack.count or 0)
			end
		end
	end

	return totals
end

local function apply_fill_inventory_action(active, action)
	local inventories = M.get_referenced_inventories(active, action.target_ref)
	if #inventories == 0 then
		return
	end
	for _, inventory in ipairs(inventories) do
		inventory.clear()
	end

	local function resolve_stack_target_inventories(stack)
		local target_ref = stack.target_ref or stack.target_entity_id
		if target_ref == nil then
			return inventories
		end
		local targeted = M.get_referenced_inventories(active, target_ref)
		if #targeted == 0 then
			return inventories
		end
		return targeted
	end

	local function insert_exported_stack(exported, target_inventories)
		for _, inventory in ipairs(target_inventories) do
			for i = 1, #inventory do
				local slot = inventory[i]
				if not slot.valid_for_read then
					local ok_import, imported = pcall(function()
						return slot.import_stack(exported)
					end)
					if ok_import and imported then
						return true
					end
				end
			end
		end
		return false
	end

	local function insert_named_stack(item_name, item_count, target_inventories)
		local remaining = item_count or 1
		for _, inventory in ipairs(target_inventories) do
			if remaining <= 0 then
				break
			end
			local inserted = inventory.insert{name = item_name, count = remaining}
			remaining = remaining - (inserted or 0)
		end
	end

	for _, stack in pairs(action.stacks or {}) do
		local target_inventories = resolve_stack_target_inventories(stack)
		if stack.exported ~= nil then
			insert_exported_stack(stack.exported, target_inventories)
		elseif stack.name ~= nil then
			insert_named_stack(stack.name, stack.count or 1, target_inventories)
		end
	end
end

local function apply_fuel_burner_inserters_action(active, action)
	local fuel_count = action.count or 50
	for _, entity in pairs(active.placed_entities) do
		if entity and entity.valid and entity.type == "inserter" and entity.burner and entity.burner.inventory then
			entity.burner.inventory.insert{name = "coal", count = fuel_count}
		end
	end
end

local function apply_set_surface_daylight_action(active, action)
	local mode = action.mode or "full-day"
	set_surface_daylight(active.surface, mode)
	log(string.format("[PBE-HARNESS] daylight mode set to %s", tostring(mode)))
end

local function collect_target_references(action)
	local refs = {}
	if type(action.target_ref) == "string" and action.target_ref ~= "" then
		refs[#refs + 1] = action.target_ref
	end
	if type(action.target_refs) == "table" then
		for _, ref in pairs(action.target_refs) do
			if type(ref) == "string" and ref ~= "" then
				refs[#refs + 1] = ref
			end
		end
	end
	return refs
end

local function order_deconstruction_for_entity(entity)
	if not (entity and entity.valid) then
		return false
	end
	local ok = pcall(function()
		entity.order_deconstruction(entity.force)
	end)
	return ok == true
end

local function cancel_deconstruction_for_entity(entity)
	if not (entity and entity.valid) then
		return false
	end
	local ok = pcall(function()
		entity.cancel_deconstruction(entity.force)
	end)
	if ok then
		return true
	end
	ok = pcall(function()
		entity.cancel_deconstruction()
	end)
	return ok == true
end

local function align_upgrade_target_to_entity(entity, target_name)
	if type(target_name) ~= "string" or target_name == "" then
		return nil
	end
	if is_unpowered_name(entity.name) then
		if is_unpowered_name(target_name) then
			return target_name
		end
		local unpowered_target = "unpowered-" .. target_name
		if prototypes.entity[unpowered_target] ~= nil then
			return unpowered_target
		end
		return target_name
	end
	return M.base_powered_name(target_name)
end

local function order_upgrade_for_entity(entity, explicit_target_name)
	if not (entity and entity.valid) then
		return false
	end

	local target_name = align_upgrade_target_to_entity(entity, explicit_target_name)
	if target_name == nil then
		local next_upgrade = entity.prototype and entity.prototype.next_upgrade or nil
		if next_upgrade and next_upgrade.valid and next_upgrade.name ~= nil then
			target_name = next_upgrade.name
		end
	end

	if target_name ~= nil then
		local target_prototype = prototypes.entity[target_name]
		if target_prototype ~= nil then
			local ok = pcall(function()
				entity.order_upgrade{force = entity.force, target = target_prototype}
			end)
			if ok then
				return true
			end
		end
	end

	local ok = pcall(function()
		entity.order_upgrade{force = entity.force}
	end)
	return ok == true
end

local function apply_order_deconstruction_action(active, action)
	for _, reference_name in pairs(collect_target_references(action)) do
		for _, entity in ipairs(M.get_referenced_entities(active, reference_name)) do
			order_deconstruction_for_entity(entity)
		end
	end
end

local function apply_cancel_deconstruction_action(active, action)
	for _, reference_name in pairs(collect_target_references(action)) do
		for _, entity in ipairs(M.get_referenced_entities(active, reference_name)) do
			cancel_deconstruction_for_entity(entity)
		end
	end
end

local function apply_order_upgrade_action(active, action)
	if type(action.orders) == "table" then
		for _, order in pairs(action.orders) do
			local reference_name = order.target_ref or order.ref
			if type(reference_name) == "string" and reference_name ~= "" then
				for _, entity in ipairs(M.get_referenced_entities(active, reference_name)) do
					order_upgrade_for_entity(entity, order.target_name)
				end
			end
		end
		return
	end

	for _, reference_name in pairs(collect_target_references(action)) do
		for _, entity in ipairs(M.get_referenced_entities(active, reference_name)) do
			order_upgrade_for_entity(entity, action.target_name)
		end
	end
end

local function apply_insert_stateful_power_armor_action(active, action)
	local inventories = M.get_referenced_inventories(active, action.target_ref)
	if #inventories == 0 then
		return
	end
	for _, inventory in ipairs(inventories) do
		inventory.clear()
	end
	local inventory = inventories[1]
	local slot = nil
	for i = 1, #inventory do
		if not inventory[i].valid_for_read then
			slot = inventory[i]
			break
		end
	end
	if slot == nil then
		return
	end

	local armor_name = action.armor_name or "power-armor"
	local ok_set, set_result = pcall(function()
		return slot.set_stack{name = armor_name, count = 1}
	end)
	if not ok_set or set_result == false or not slot.valid_for_read or slot.name ~= armor_name then
		log(string.format(
			"[PBE-HARNESS] insert_stateful_power_armor skipped: set_stack failed (ok=%s result=%s name=%s expected=%s)",
			tostring(ok_set),
			tostring(set_result),
			tostring(slot.name),
			armor_name
		))
		return
	end

	if action.with_grid == false then
		return
	end

	local ok_grid, grid = pcall(function()
		return slot.grid
	end)
	if not ok_grid then
		grid = nil
	end
	if grid == nil then
		local ok_create, created_grid = pcall(function()
			return slot.create_grid()
		end)
		if ok_create and created_grid then
			grid = slot.grid
		end
	end
	if grid == nil then
		log(string.format("[PBE-HARNESS] insert_stateful_power_armor skipped: no equipment grid for %s", armor_name))
		return
	end

	local ok_put, equipment = pcall(function()
		return grid.put{
			name = action.equipment_name or "battery-mk2-equipment",
			position = action.equipment_position or {0, 0}
		}
	end)
	if not ok_put or equipment == nil then
		log("[PBE-HARNESS] insert_stateful_power_armor skipped: failed to add equipment to grid")
		return
	end

	if equipment.max_energy ~= nil then
		equipment.energy = math.floor(equipment.max_energy * (action.energy_fraction or 0.5))
	end
end

local function apply_build_blueprint_action(active, action)
	if not (active.surface and active.surface.valid) then
		return
	end

	local player = game and game.get_player and game.get_player(1) or nil
	if not (player and player.valid) then
		log("[PBE-HARNESS] build_blueprint skipped: player 1 unavailable")
		return
	end

	player.clear_cursor()
	local cursor = player.cursor_stack
	if not (cursor and cursor.valid_for_read == false) then
		pcall(function()
			cursor.clear()
		end)
	end

	local ok_set = pcall(function()
		cursor.set_stack{name = "blueprint", count = 1}
	end)
	if not ok_set or not (cursor and cursor.valid_for_read) then
		log("[PBE-HARNESS] build_blueprint skipped: failed to create blueprint stack")
		return
	end

	local entities = action.entities
	if type(entities) ~= "table" or #entities == 0 then
		entities = {
			{
				entity_number = 1,
				name = action.entity_name or "small-electric-pole",
				position = {x = 0, y = 0},
			},
		}
	end

	local ok_entities, err_entities = pcall(function()
		cursor.set_blueprint_entities(entities)
	end)
	if not ok_entities then
		log("[PBE-HARNESS] build_blueprint skipped: invalid entities payload: " .. tostring(err_entities))
		return
	end

	local ok_build, result_or_error = pcall(function()
		return cursor.build_blueprint{
			surface = active.surface,
			force = game.forces.player,
			position = action.position,
			direction = action.direction,
			force_build = action.force_build == true,
			skip_fog_of_war = true,
			by_player = player,
		}
	end)
	if not ok_build then
		log("[PBE-HARNESS] build_blueprint failed: " .. tostring(result_or_error))
	end

	if action.clear_cursor ~= false then
		player.clear_cursor()
	end
end

function M.apply_action(active, action, call_main_mod)
	if action.type == "fill_inventory" then
		apply_fill_inventory_action(active, action)
	elseif action.type == "fuel_burner_inserters" then
		apply_fuel_burner_inserters_action(active, action)
	elseif action.type == "set_surface_daylight" then
		apply_set_surface_daylight_action(active, action)
	elseif action.type == "order_deconstruction" then
		apply_order_deconstruction_action(active, action)
	elseif action.type == "cancel_deconstruction" then
		apply_cancel_deconstruction_action(active, action)
	elseif action.type == "order_upgrade" then
		apply_order_upgrade_action(active, action)
	elseif action.type == "insert_stateful_power_armor" then
		apply_insert_stateful_power_armor_action(active, action)
	elseif action.type == "build_blueprint" then
		apply_build_blueprint_action(active, action)
	elseif action.type == "run_full_scan" then
		call_main_mod("run_full_scan")
	elseif action.type == "set_test_overrides" then
		call_main_mod("set_test_overrides", action.overrides)
	end
end

return M
