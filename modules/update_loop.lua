local utils = require("modules.utils")
local entities = require("modules.entities")
local undergrounds = require("modules.undergrounds")
local migrations = require("modules.migrations")

local update_loop = {}

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

function update_loop.on_tick(event)
	if storage.ver ~= utils.current_version then
		migrations.init_globals()
	end
	storage.sum_ticks = storage.sum_ticks + 1
    if storage.power_entities ~= nil and storage.entities ~= nil and next(storage.power_entities) then
		for _ = 1, utils.get_operations_per_tick_setting() do
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
				entities.clear_tile(entity_key, surface)
			elseif power_entities_by_surface ~= nil and power_entities_by_surface[entity_key] ~= nil then
				undergrounds.run_for_entity(entity, surface, entity_key, true, undergrounds.underground_length(entity), false, false)
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
end

return update_loop
