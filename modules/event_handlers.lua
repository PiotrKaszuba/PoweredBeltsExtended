local utils = require("modules.utils")
local entities = require("modules.entities")

local event_handlers = {}

function event_handlers.on_built_entity(event)
	local entity = event.entity
	if entity and utils.belt_entity_types[entity.type] then
		entities.init_entity(entity)
	end
end

function event_handlers.on_removed_entity(event)
	if event.entity then
		local pos = entities.get_entity_idx(event.entity)
		entities.clear_tile(pos, event.entity.surface)
	end
end

return event_handlers
