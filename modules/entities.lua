local utils = require("modules.utils")
local forces = require("modules.forces")

local entities = {}

function entities.get_entity_idx(entity)
	return entity.position.x .. " " .. entity.position.y
end

function entities.get_entity_idx_from_position(position)
	return position.x .. " " .. position.y
end

function entities.clear_power_entity(pos, surface)
	local surface_key, _, power_entities_by_surface = utils.get_surface_tables(surface, false)
	if power_entities_by_surface ~= nil and power_entities_by_surface[pos] ~= nil then
		local ent = power_entities_by_surface[pos]
		if ent.valid then
			ent.destroy()
		end
		power_entities_by_surface[pos] = nil
		utils.cleanup_empty_surface_tables(surface_key)
	end
end

function entities.clear_tile(pos, surface)
	local surface_key, entities_by_surface, _ = utils.get_surface_tables(surface, false)
	if entities_by_surface ~= nil and entities_by_surface[pos] ~= nil then
		entities_by_surface[pos] = nil
    end
	entities.clear_power_entity(pos, surface)
	utils.cleanup_empty_surface_tables(surface_key)
end

function entities.get_correct_power_entity_name(base_name, force)
	local correct_level = forces.get_correct_belt_level(force)
	local usage_name = tostring(settings.startup["powered-belts-usage-multiplier"].value):gsub("%.", "_")
	local upgrade_name = tostring(settings.startup["powered-belts-upgrade-reduction"].value):gsub("%.", "_")
	local name = base_name .. "-" .. usage_name .. "-" .. upgrade_name ..  "-" .. correct_level .. "-power"
	return name
end

function entities.create_power_entity(base_name, surface, position, force, direction, base_name_is_correct)
	local pos = entities.get_entity_idx_from_position(position)
	entities.clear_power_entity(pos, surface)
	local name = base_name
	if not base_name_is_correct then
		name = entities.get_correct_power_entity_name(base_name, force)
	end
	local _, _, power_entities_by_surface = utils.get_surface_tables(surface, true)
	power_entities_by_surface[pos] = surface.create_entity{
		name = name,
		position = position,
		force = force,
		direction = direction,
		destructible = false
	}
end

function entities.extract_base_name_from_entity_to_power(name)
	local base_name = name
	if string.match(name, "^unpowered%-%") then
		base_name = string.sub(name, 11)
	end
	return base_name
end

function entities.check_and_replace_power_entity(entity_to_power, power_entity)
	local base_name = entities.extract_base_name_from_entity_to_power(entity_to_power.name)
	
	local correct_name = entities.get_correct_power_entity_name(base_name, entity_to_power.force)
	if power_entity == nil or (not power_entity.valid) or correct_name ~= power_entity.name or entity_to_power.force.name ~= power_entity.force.name then
		entities.create_power_entity(correct_name, entity_to_power.surface, entity_to_power.position, entity_to_power.force, entity_to_power.direction, true)
	end

end

function entities.find_all_entities_to_power_at_position(surface, position, radius)
	local world_entities = surface.find_entities_filtered{position=position, radius=radius}
	local entities_to_power = {}
	for _,v in pairs(world_entities) do
		if (not string.endswith(v.name, '-power')) and utils.belt_entity_types[v.type] then
			entities_to_power[entities.get_entity_idx(v)] = v
		end
	end
	return entities_to_power
end

function entities.init_entity(entity)
	local pos = entities.get_entity_idx(entity)
	entities.clear_tile(pos, entity.surface)
	local _, entities_by_surface, power_entities_by_surface = utils.get_surface_tables(entity.surface, true)
	local correct_name = entities.get_correct_power_entity_name(entities.extract_base_name_from_entity_to_power(entity.name), entity.force)
	power_entities_by_surface[pos] = entity.surface.create_entity{
		name = correct_name,
		position = entity.position,
		force = entity.force,
		direction = entity.direction,
		destructible = false
	}
	entities_by_surface[pos] = entity
end

return entities
