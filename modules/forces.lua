local forces = {}

function forces.get_correct_belt_level(force)
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

function forces.extract_number_from_string(str)
    local number = str:match("%d+")
    return tonumber(number)
end

function forces.tech_check(event)
	if string.match(event.research.name, "efficient%-belts%-") then
		local force_name = event.research.force.name
		
		if storage.player_forces[force_name] == nil then
			storage.player_forces[force_name] = {}
		end
		local tech_level = forces.extract_number_from_string(event.research.name)
		if tech_level ~= nil then
			storage.player_forces[force_name]['belt_level'] = tech_level
		end
	end
end

return forces
