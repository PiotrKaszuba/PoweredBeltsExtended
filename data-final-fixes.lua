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
local tech_factor = 1 - reduction

local belt_type_configs = {
	{"transport-belt", 1},
	{"underground-belt", nil}, -- uses underground_belt_mult
	{"splitter", 5},
	{"loader-1x1", 5},
	{"loader", 10},
}

local function underground_belt_mult(v)
	-- underground belt max_distance is the distance between the two ends:
	-- so max_distance + 1 is the total length of that belt-segment
	-- using max_distance + 3 as a way to simulate power usage
	-- of going underground and back
	-- then dividing by 2 to get usage for each underground entity/endpoint
	return (v.max_distance + 3) / 2
end

local function create_power_entity_def(v, i, ei, usage_name, upgrade_name)
	return {
		type = "electric-energy-interface",
		name = v.name .. "-" .. usage_name .. "-" .. upgrade_name .. "-" .. i .. "-power",
		localised_name = {"entity-name." .. v.name},
		localised_description = {"entity-description." .. v.name},
		icon = v.icon,
		icon_size = v.icon_size,
		flags = {"not-deconstructable", "not-blueprintable", "not-upgradable", "not-on-map", "not-in-kill-statistics", "not-in-made-in" },
		allow_copy_paste = false,
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
		energy_usage = ei .. "kW",
		hidden = true,
		hidden_in_factoriopedia = true,
	}
end

local function format_kw(value)
	if value >= 100 then
		return string.format("%.0f", value)
	elseif value >= 10 then
		return string.format("%.1f", value)
	end
	return string.format("%.2f", value)
end

local function process_belt_type(raw_key, mult)
	for _, v in pairs(data.raw[raw_key] or {}) do
		if not string.match(v.name, "^unpowered%-") then
			local e = 160 * v.speed * um * (mult or underground_belt_mult(v))
			local min_e = e * (tech_factor ^ num_levels)
			v.custom_tooltip_fields = {{
				name = {"powered-belts-tooltip.power-usage-name"},
				value = {"powered-belts-tooltip.power-usage-formula", format_kw(e), string.format("%.2f", tech_factor), tostring(num_levels), format_kw(min_e)}
			}}
			local x = table.deepcopy(v)
			x.name = "unpowered-" .. x.name
			x.speed = 1e-308  -- speed has to be positive, this is close enough to 0
			x.hidden_in_factoriopedia = true

			if data.raw.item[v.name] then
				x.placeable_by = {item = v.name, count = 1}
			else
				x.placeable_by = v.placeable_by
			end
			
			x.localised_name = {"entity-name." .. v.name}
			x.localised_description = {"entity-description." .. v.name}
			

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
