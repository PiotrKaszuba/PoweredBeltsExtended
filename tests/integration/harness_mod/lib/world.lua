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

function M.bootstrap_daytime_and_power(layout, surface, area, placed_entities)
	if not (surface and surface.valid) then
		return
	end

	set_surface_daylight(surface, "full-day")

	local min_x, max_x, _, _ = compute_entity_bounds(placed_entities, area)
	if min_x == nil or max_x == nil then
		return
	end
	local y_line = layout.y_line
	local left = math.floor(min_x) - 1
	local right = math.ceil(max_x) + 1
	local top_pole_y = y_line - 4
	local lane_pole_y = y_line + 3
	local solar_pole_y = lane_pole_y + 4
	local solar_y = solar_pole_y + 2

	for x = left, right, 7 do
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
		place_infrastructure_entity(surface, {
			name = "medium-electric-pole",
			position = {x = x + 0.5, y = top_pole_y},
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

local function normalize_inventory_collection(inventories)
	if inventories == nil then
		return {}
	end
	if type(inventories) == "table" then
		return inventories
	end
	-- Accept a single LuaInventory userdata (e.g. active.inventory).
	return {inventories}
end

function M.aggregate_inventory_contents(inventories)
	local totals = {}
	for _, inventory in ipairs(normalize_inventory_collection(inventories)) do
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
	for _, inventory in ipairs(normalize_inventory_collection(inventories)) do
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
	for _, inventory in ipairs(normalize_inventory_collection(inventories)) do
		local fingerprint = M.inventory_fingerprint(inventory)
		for signature, count in pairs(fingerprint) do
			combined[signature] = (combined[signature] or 0) + count
		end
	end
	return combined
end

local function add_item_counts(target, item_name, count)
	if type(item_name) ~= "string" or item_name == "" then
		return
	end
	if type(count) ~= "number" or count == 0 then
		return
	end
	target[item_name] = (target[item_name] or 0) + count
end

local function inventory_item_counts(inventory)
	if inventory == nil then
		return {}
	end
	local ok, contents = pcall(function()
		return inventory.get_contents()
	end)
	if not ok or contents == nil then
		return {}
	end
	return M.contents_to_name_count_map(contents)
end

local function collect_transport_line_counts(entity, entry)
	if not (entity and entity.valid) then
		return
	end
	local max_line_index = 0
	local ok_max, max_line = pcall(function()
		return entity.get_max_transport_line_index()
	end)
	if ok_max and type(max_line) == "number" then
		max_line_index = max_line
	end
	if max_line_index <= 0 then
		return
	end

	entry.transport_lines = {}
	for line_index = 1, max_line_index do
		local ok_line, line = pcall(function()
			return entity.get_transport_line(line_index)
		end)
		if ok_line and line ~= nil then
			local counts = {}
			local had_detailed = false
			local ok_detailed, detailed_contents = pcall(function()
				return line.get_detailed_contents()
			end)
			if ok_detailed and type(detailed_contents) == "table" then
				had_detailed = true
				for _, detailed_item in pairs(detailed_contents) do
					local stack = detailed_item and detailed_item.stack or nil
					if stack and stack.valid_for_read then
						add_item_counts(counts, stack.name, stack.count or 0)
						add_item_counts(entry.counts, stack.name, stack.count or 0)
					elseif type(detailed_item) == "table" and detailed_item.name ~= nil then
						add_item_counts(counts, detailed_item.name, detailed_item.count or 0)
						add_item_counts(entry.counts, detailed_item.name, detailed_item.count or 0)
					end
				end
			end
			if not had_detailed then
				local ok_contents, line_contents = pcall(function()
					return line.get_contents()
				end)
				if ok_contents and type(line_contents) == "table" then
					local normalized = M.contents_to_name_count_map(line_contents)
					for item_name, count in pairs(normalized) do
						add_item_counts(counts, item_name, count)
						add_item_counts(entry.counts, item_name, count)
					end
				end
			end
			entry.transport_lines[tostring(line_index)] = counts
		end
	end
end

local function collect_inserter_hand_counts(entity, entry)
	if not (entity and entity.valid and entity.type == "inserter") then
		return
	end
	local held_stack = entity.held_stack
	if held_stack ~= nil and held_stack.valid_for_read then
		add_item_counts(entry.counts, held_stack.name, held_stack.count or 0)
		entry.hand = {
			name = held_stack.name,
			count = held_stack.count or 0,
		}
	end
end

local function entity_item_snapshot(entity, entity_id)
	if not (entity and entity.valid) then
		return nil
	end
	local entry = {
		entity_id = entity_id,
		name = entity.name,
		type = entity.type,
		position = {x = entity.position.x, y = entity.position.y},
		counts = {},
	}
	if entity.name == "item-on-ground" and entity.stack ~= nil and entity.stack.valid_for_read then
		add_item_counts(entry.counts, entity.stack.name, entity.stack.count or 0)
		entry.ground_stack = {
			name = entity.stack.name,
			count = entity.stack.count or 0,
		}
	end
	local inventory = M.resolve_inventory(entity)
	if inventory ~= nil then
		for item_name, count in pairs(inventory_item_counts(inventory)) do
			add_item_counts(entry.counts, item_name, count)
		end
	end
	collect_inserter_hand_counts(entity, entry)
	collect_transport_line_counts(entity, entry)
	if next(entry.counts) == nil then
		return nil
	end
	return entry
end

local function entity_scan_key(entity)
	if not (entity and entity.valid) then
		return nil
	end
	if entity.unit_number ~= nil then
		return "unit:" .. tostring(entity.unit_number)
	end
	return string.format("%s@(%0.4f,%0.4f)", tostring(entity.name), entity.position.x, entity.position.y)
end

local function append_snapshot(payload, seen_entities, entity_id, entity, debug, source_tag)
	if not (entity and entity.valid) then
		if debug ~= nil then
			debug.invalid_candidates = (debug.invalid_candidates or 0) + 1
		end
		return false
	end
	local key = entity_scan_key(entity)
	if key ~= nil and seen_entities[key] then
		if debug ~= nil then
			debug.duplicate_candidates = (debug.duplicate_candidates or 0) + 1
		end
		return false
	end
	local snapshot = entity_item_snapshot(entity, entity_id)
	if snapshot == nil then
		if debug ~= nil then
			debug.empty_candidates = (debug.empty_candidates or 0) + 1
			if #debug.empty_candidate_samples < 20 then
				debug.empty_candidate_samples[#debug.empty_candidate_samples + 1] = {
					source = source_tag,
					entity_id = entity_id,
					name = entity.name,
					type = entity.type,
					position = {x = entity.position.x, y = entity.position.y},
				}
			end
		end
		return false
	end
	local location_id = string.format("%s@(%0.2f,%0.2f)", entity_id, entity.position.x, entity.position.y)
	payload.locations[location_id] = snapshot
	for item_name, count in pairs(snapshot.counts) do
		add_item_counts(payload.totals, item_name, count)
	end
	if key ~= nil then
		seen_entities[key] = true
	end
	if debug ~= nil then
		if source_tag == "reference" then
			debug.included_from_references = (debug.included_from_references or 0) + 1
		elseif source_tag == "surface" then
			debug.included_from_surface_scan = (debug.included_from_surface_scan or 0) + 1
		end
	end
	return true
end

local function nearby_entities_at_layout_position(active, position)
	if not (active and active.surface and active.surface.valid and type(position) == "table") then
		return {}
	end
	local entities = active.surface.find_entities_filtered{position = position, radius = 1.5} or {}
	local out = {}
	for _, entity in pairs(entities) do
		if entity and entity.valid then
			out[#out + 1] = {
				name = entity.name,
				type = entity.type,
				position = {x = entity.position.x, y = entity.position.y},
			}
		end
	end
	return out
end

function M.scan_chain_item_locations(active, options)
	local payload = {
		tick = game and game.tick or -1,
		scenario_id = active and active.scenario and active.scenario.id or "unknown",
		locations = {},
		totals = {},
	}
	local debug_enabled = type(options) == "table" and options.debug == true
	local debug = nil
	if debug_enabled then
		debug = {
			placed_entities_total = 0,
			placed_entities_valid = 0,
			resolution_attempts = 0,
			resolution_successes = 0,
			resolution_failures = 0,
			resolution_failure_samples = {},
			included_from_references = 0,
			included_from_surface_scan = 0,
			empty_candidates = 0,
			empty_candidate_samples = {},
			duplicate_candidates = 0,
			invalid_candidates = 0,
			surface_scan_candidates = 0,
		}
		payload.debug = debug
	end
	if active == nil then
		return payload
	end

	local seen_entities = {}

	for entity_id, entity in pairs(active.placed_entities or {}) do
		if debug ~= nil then
			debug.placed_entities_total = debug.placed_entities_total + 1
		end
		if entity ~= nil and (not entity.valid) then
			if debug ~= nil then
				debug.resolution_attempts = debug.resolution_attempts + 1
			end
			entity = resolve_current_entity(active, entity_id)
			active.placed_entities[entity_id] = entity
			if debug ~= nil then
				if entity ~= nil and entity.valid then
					debug.resolution_successes = debug.resolution_successes + 1
				else
					debug.resolution_failures = debug.resolution_failures + 1
					if #debug.resolution_failure_samples < 20 then
						local entry = {entity_id = entity_id}
						local expected = get_layout_entity_definition(active, entity_id)
						if expected ~= nil then
							entry.expected_name = expected.name
							entry.expected_type = expected.type
							entry.expected_position = expected.position
							entry.nearby_entities = nearby_entities_at_layout_position(active, expected.position)
						end
						debug.resolution_failure_samples[#debug.resolution_failure_samples + 1] = entry
					end
				end
			end
		end
		if entity and entity.valid then
			if debug ~= nil then
				debug.placed_entities_valid = debug.placed_entities_valid + 1
			end
			append_snapshot(payload, seen_entities, entity_id, entity, debug, "reference")
		end
	end

	if active.surface and active.surface.valid then
		local query = {}
		if active.layout and active.layout.area then
			query.area = active.layout.area
		end
		for _, entity in pairs(active.surface.find_entities_filtered(query) or {}) do
			if debug ~= nil then
				debug.surface_scan_candidates = debug.surface_scan_candidates + 1
			end
			append_snapshot(payload, seen_entities, "world_entity", entity, debug, "surface")
		end
	end

	local mine_inventory_counts = inventory_item_counts(active.inventory)
	if next(mine_inventory_counts) ~= nil then
		payload.locations["mine_inventory"] = {
			entity_id = "mine_inventory",
			name = "mine_inventory",
			type = "script-inventory",
			counts = mine_inventory_counts,
		}
		for item_name, count in pairs(mine_inventory_counts) do
			add_item_counts(payload.totals, item_name, count)
		end
	end

	return payload
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

local function is_marked_for_deconstruction(entity)
	if not (entity and entity.valid) then
		return false
	end
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

local function mine_entity(entity, inventory)
	if not (entity and entity.valid) then
		return false
	end
	-- local inv_contents = inventory.get_contents()
	-- DEBUG: before mining, print the inventory contents
	-- game.print(string.format("[PBE-HARNESS] before mining, inventory contents: %s", serpent.block(inv_contents)))
	local ok_mine, mined = pcall(function()
		return entity.mine{
			ignore_minable = true,
			raise_destroyed = true,
			inventory = inventory,
		}
	end)
	-- DEBUG: after mining, print the inventory contents
	-- inv_contents = inventory.get_contents()
	-- game.print(string.format("[PBE-HARNESS] after mining, inventory contents: %s", serpent.block(inv_contents)))
	return ok_mine and mined == true
end

local function find_entities_at_position(surface, position, entity_type)
	if not (surface and surface.valid and type(position) == "table") then
		return {}
	end
	local query = {position = position, radius = 0.2}
	if entity_type ~= nil then
		query.type = entity_type
	end
	return surface.find_entities_filtered(query) or {}
end

local function apply_mine_entities_at_position_action(active, action)
	if not (active.surface and active.surface.valid and type(action.position) == "table") then
		return
	end
	for _, entity in pairs(find_entities_at_position(active.surface, action.position, action.entity_type)) do
		if entity and entity.valid and (action.name == nil or entity.name == action.name) then
			mine_entity(entity, active.inventory)
		end
	end
end

local function apply_build_entity_action(active, action)
	if not (active.surface and active.surface.valid and type(action.position) == "table") then
		return
	end
	if type(action.name) ~= "string" or action.name == "" then
		return
	end
	place_infrastructure_entity(active.surface, {
		name = action.name,
		position = action.position,
		direction = action.direction,
		force = game.forces.player,
		raise_built = true,
	})

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

local function apply_mine_marked_entities_action(active, action)
	local refs = collect_target_references(action)

	local function mine_marked(entity)
		if is_marked_for_deconstruction(entity) then
			mine_entity(entity, active.inventory)
		end
	end

	if #refs == 0 then
		for _, entity in pairs(active.placed_entities or {}) do
			mine_marked(entity)
		end
		return
	end

	for _, reference_name in pairs(refs) do
		for _, entity in ipairs(M.get_referenced_entities(active, reference_name)) do
			mine_marked(entity)
		end
	end
end

local function apply_revive_ghosts_action(active, action)
	if not (active.surface and active.surface.valid) then
		return
	end
	for _, ghost in pairs(action.ghosts or {}) do
		for _, entity in pairs(find_entities_at_position(active.surface, ghost.position)) do
			if entity and entity.valid and entity.name == "entity-ghost" and (ghost.name == nil or entity.ghost_name == ghost.name) then
				pcall(function()
					entity.revive{raise_revive = true}
				end)
			end
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

	local script_inventory = nil
	local function cleanup_script_inventory()
		if script_inventory ~= nil then
			pcall(function()
				script_inventory.clear()
			end)
			pcall(function()
				script_inventory.destroy()
			end)
		end
	end

	local ok_inventory, inventory_or_error = pcall(function()
		return game.create_inventory(1)
	end)
	if not ok_inventory or inventory_or_error == nil then
		log("[PBE-HARNESS] build_blueprint skipped: failed to create script inventory: " .. tostring(inventory_or_error))
		return
	end
	script_inventory = inventory_or_error

	local blueprint_stack = script_inventory[1]
	if blueprint_stack == nil then
		log("[PBE-HARNESS] build_blueprint skipped: missing script inventory slot")
		cleanup_script_inventory()
		return
	end

	local ok_set, set_result = pcall(function()
		return blueprint_stack.set_stack{name = "blueprint", count = 1}
	end)
	if not ok_set or set_result == false or not blueprint_stack.valid_for_read then
		log("[PBE-HARNESS] build_blueprint skipped: failed to create blueprint stack")
		cleanup_script_inventory()
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
		blueprint_stack.set_blueprint_entities(entities)
	end)
	if not ok_entities then
		log("[PBE-HARNESS] build_blueprint skipped: invalid entities payload: " .. tostring(err_entities))
		cleanup_script_inventory()
		return
	end

	local ok_build, result_or_error = pcall(function()
		return blueprint_stack.build_blueprint{
			surface = active.surface,
			force = game.forces.player,
			position = action.position,
			direction = action.direction,
			build_mode = action.force_build == true and defines.build_mode.superforced or defines.build_mode.forced,
			skip_fog_of_war = true,
		}
	end)
	if not ok_build or result_or_error == false then
		log("[PBE-HARNESS] build_blueprint failed: " .. tostring(result_or_error))
	end

	cleanup_script_inventory()
end

local function apply_find_and_remove_matching_entities_action(active, action)
	if not (active.surface and active.surface.valid) then
		return
	end
	local query = {position=action.position, radius=action.radius}
	if action.entity_type ~= nil then
		query.type = action.entity_type
	end

	local entities = active.surface.find_entities_filtered(query)
	if #entities == 0 then
		return
	end
	for _, entity in ipairs(entities) do
		if entity.valid and entity.name == action.entity_name then
			mine_entity(entity, active.inventory)
		end
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
	elseif action.type == "mine_marked_entities" then
		apply_mine_marked_entities_action(active, action)
	elseif action.type == "mine_entities_at_position" then
		apply_mine_entities_at_position_action(active, action)
	elseif action.type == "revive_ghosts" then
		apply_revive_ghosts_action(active, action)
	elseif action.type == "build_entity" then
		apply_build_entity_action(active, action)
	elseif action.type == "insert_stateful_power_armor" then
		apply_insert_stateful_power_armor_action(active, action)
	elseif action.type == "build_blueprint" then
		apply_build_blueprint_action(active, action)
	elseif action.type == "find_and_remove_matching_entities" then
		apply_find_and_remove_matching_entities_action(active, action)
	elseif action.type == "run_full_scan" then
		call_main_mod("run_full_scan")
	elseif action.type == "set_test_overrides" then
		call_main_mod("set_test_overrides", action.overrides)
	elseif action.type == "scan_item_locations" then
		local payload = M.scan_chain_item_locations(active, {debug = action.debug_log == true})
		if action.debug_log == true then
			log("[PBE-HARNESS] chain-item-scan " .. helpers.table_to_json(payload))
		end
		local output_file = action.output_file
		if type(action.output_file_pattern) == "string" and action.output_file_pattern ~= "" then
			output_file = action.output_file_pattern
			output_file = string.gsub(output_file, "{tick}", tostring(payload.tick))
			output_file = string.gsub(output_file, "{scenario}", tostring(payload.scenario_id))
		end
		if type(output_file) == "string" and output_file ~= "" then
			helpers.write_file(output_file, helpers.table_to_json(payload), false)
		end
	end
end

return M
