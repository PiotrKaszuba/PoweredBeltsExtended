require("prototypes.technology")

-- 2.0: resistances_immune for entities that should take no damage (base mod may not expose this in data-final-fixes)
local resistances_immune = {
	{type = "physical", decrease = 0, percent = 100},
	{type = "impact", decrease = 0, percent = 100},
	{type = "fire", decrease = 0, percent = 100},
	{type = "laser", decrease = 0, percent = 100},
	{type = "electric", decrease = 0, percent = 100},
	{type = "explosion", decrease = 0, percent = 100},
	{type = "acid", decrease = 0, percent = 100},
	{type = "poison", decrease = 0, percent = 100}
}

local um = settings.startup["powered-belts-usage-multiplier"].value
local num_levels = 5 --settings.startup["powered-belts-num-upgrades"].value
local reduction = settings.startup["powered-belts-upgrade-reduction"].value
local usage_name = tostring(settings.startup["powered-belts-usage-multiplier"].value):gsub("%.", "_")
local upgrade_name = tostring(settings.startup["powered-belts-upgrade-reduction"].value):gsub("%.", "_")

local belt_type_configs = {
	{"transport-belt", 1},
	{"underground-belt", nil},  -- uses (v.max_distance+2)
	{"splitter", 5},
	{"loader-1x1", 5},
	{"loader", 10},
}

local function create_power_entity_def(v, i, ei, usage_name, upgrade_name)
	return {
		type = "electric-energy-interface",
		name = v.name .. "-" .. usage_name .. "-" .. upgrade_name .. "-" .. i .. "-power",
		icon = v.icon,
		icon_size = v.icon_size,
		flags = {"player-creation", "not-deconstructable", "not-blueprintable"},
		max_health = 1,
		resistances = resistances_immune,
		collision_mask = {layers = {}, colliding_with_tiles_only = true},
		collision_box = v.collision_box,
		selection_box = nil,
		selectable_in_game = false,
		energy_source = {
			type = "electric",
			usage_priority = "secondary-input",
			input_flow_limit = (ei + 1) .. "kW",
			buffer_capacity = (1 * ei) .. "kJ"
		},
		energy_production = "0W",
		energy_usage = ei .. "kW"
	}
end

local function process_belt_type(raw_key, mult)
	for _, v in pairs(data.raw[raw_key] or {}) do
		if not string.match(v.name, "^unpowered%-") then
			local e = 160 * v.speed * um * (mult or (v.max_distance + 2))
			local x = table.deepcopy(v)
			x.name = "unpowered-" .. x.name
			x.speed = 1e-308  -- speed has to be positive, this is close enough to 0
			x.localised_name = {"entity-name." .. v.name}
			x.localised_description = {"entity-description." .. v.name}
			data:extend({
				{
					type = "item",
					name = x.name,
					icon = "__base__/graphics/icons/signal/signal_everything.png",
					icon_size = 64,
					stack_size = 100,
					place_result = x.name,
				}
			})
			data:extend({x})
			for i = 0, num_levels + 1 do
				local ei = e * ((1 - reduction) ^ i)
				data:extend({create_power_entity_def(v, i, ei, usage_name, upgrade_name)})
			end
		end
	end
end

for _, config in ipairs(belt_type_configs) do
	process_belt_type(config[1], config[2])
end
