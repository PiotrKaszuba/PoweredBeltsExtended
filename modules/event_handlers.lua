local utils = require("modules.utils")
local entities = require("modules.entities")
local compatibility = require("modules.compatibility")

local event_handlers = {}

function event_handlers.on_built_entity(event)
	local entity = event.entity or event.destination
	if entity and utils.belt_entity_types[entity.type] then
		local skip_init = compatibility.consume_skip_built_init_marker(entity)
		if not skip_init then
			entities.init_entity(entity)
		end
		compatibility.on_built_entity(entity)
	end
end

function event_handlers.on_removed_entity(event)
	if event.entity then
		compatibility.on_removed_entity(event.entity)
		local pos_key = utils.get_entity_position_key(event.entity)
		entities.clear_tile(pos_key, event.entity.surface)
	end
end

return event_handlers

