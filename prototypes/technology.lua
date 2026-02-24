local efficient_belts_icon = "__base__/graphics/icons/transport-belt.png"
local reduction = string.format("%g", settings.startup["powered-belts-upgrade-reduction"].value * 100)
local num_levels = settings.startup["powered-belts-num-upgrades"].value
local tech_cost_per_level = settings.startup["powered-belts-efficiency-tech-cost-per-level"].value
local tech_cost_multiplier = tech_cost_per_level / 50

local level_science = {
	[1] = {
		{"automation-science-pack", 1}
	},
	[2] = {
		{"automation-science-pack", 1},
		{"logistic-science-pack", 1}
	},
	[3] = {
		{"automation-science-pack", 1},
		{"logistic-science-pack", 1},
		{"chemical-science-pack", 1}
	},
	[4] = {
		{"automation-science-pack", 1},
		{"logistic-science-pack", 1},
		{"chemical-science-pack", 1},
		{"production-science-pack", 1}
	},
	[5] = {
		{"automation-science-pack", 1},
		{"logistic-science-pack", 1},
		{"chemical-science-pack", 1},
		{"production-science-pack", 1},
		{"utility-science-pack", 1}
	},
	[6] = {
		{"automation-science-pack", 1},
		{"logistic-science-pack", 1},
		{"chemical-science-pack", 1},
		{"production-science-pack", 1},
		{"utility-science-pack", 1},
		{"space-science-pack", 1}
	}
}

local level_prerequisites = {
	[1] = {"logistics"},
	[2] = {"logistic-science-pack"},
	[3] = {"chemical-science-pack", "logistics-2"},
	[4] = {"production-science-pack"},
	[5] = {"utility-science-pack", "logistics-3"},
	[6] = {"space-science-pack"}
}

local level_time = {
	[1] = 30,
	[2] = 45,
	[3] = 60,
	[4] = 60,
	[5] = 60,
	[6] = 60
}

local function get_order(level)
	return "e-l-" .. string.char(string.byte("a") + level - 1)
end

local function copy_ingredients(ingredients)
	local copy = {}
	for _, ingredient in ipairs(ingredients) do
		copy[#copy + 1] = {ingredient[1], ingredient[2]}
	end
	return copy
end

local function get_research_count(level)
	local base_count
	if level <= 6 then
		base_count = 50 * level
	else
		local count = 300
		for current_level = 7, level do
			count = count + 50 * (current_level - 5)
		end
		base_count = count
	end

	return math.floor(base_count * tech_cost_multiplier)
end

local technologies = {}
for level = 1, num_levels do
	local uses_unique_recipe = level <= 6
	local ingredients = level_science[uses_unique_recipe and level or 6]
	local prerequisites = {}

	if level == 1 then
		for _, prereq in ipairs(level_prerequisites[1]) do
			prerequisites[#prerequisites + 1] = prereq
		end
	else
		prerequisites[#prerequisites + 1] = "efficient-belts-" .. (level - 1)
		if level_prerequisites[level] ~= nil then
			for _, prereq in ipairs(level_prerequisites[level]) do
				prerequisites[#prerequisites + 1] = prereq
			end
		end
	end

	local effect_description = "Reduce energy usage of belts, splitters and loaders by another " .. reduction .. "%"
	if level == 1 then
		effect_description = "Reduce energy usage of belts, splitters and loaders by " .. reduction .. "%"
	end

	technologies[#technologies + 1] = {
		type = "technology",
		name = "efficient-belts-" .. level,
		icon_size = 64,
		icon = efficient_belts_icon,
		effects = {
			{
				type = "nothing",
				effect_description = effect_description
			}
		},
		prerequisites = prerequisites,
		unit = {
			count = get_research_count(level),
			ingredients = copy_ingredients(ingredients),
			time = level_time[uses_unique_recipe and level or 6]
		},
		upgrade = true,
		order = get_order(level)
	}
end

if #technologies > 0 then
	data:extend(technologies)
end
