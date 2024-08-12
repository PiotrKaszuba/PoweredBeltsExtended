local efficient_belts_icon = "__base__/graphics/icons/transport-belt.png"
local reduction = tostring(settings.startup["powered-belts-upgrade-reduction"].value * 100)

data:extend(
{
  {
    type = "technology",
    name = "efficient-belts-1",
    icon_size = 64, icon_mipmaps = 1,
    icon = efficient_belts_icon,
    --util.technology_icon_constant_speed(efficient_belts_icon),
    effects =
    {
      {
        type = "nothing",
		effect_description = "Reduce energy usage of belts, splitters and loaders by " .. reduction  .. "%"
      }
    },
    prerequisites = {"logistics"},

    unit =
    {
      count = 50*1,
      ingredients =
      {
        {"automation-science-pack", 1}
      },
      time = 30
    },
    upgrade = true,
    order = "e-l-a"
  },
  {
    type = "technology",
    name = "efficient-belts-2",
    icon_size = 64, icon_mipmaps = 1,
    icon = efficient_belts_icon,
    effects =
    {
      {
        type = "nothing",
		effect_description = "Reduce energy usage of belts, splitters and loaders by another " .. reduction  .. "%"
      }
    },
    prerequisites = {"efficient-belts-1", "logistic-science-pack"},
    unit =
    {
      count = 50*2,
      ingredients =
      {
        {"automation-science-pack", 1},
        {"logistic-science-pack", 1}
      },
      time = 45
    },
    upgrade = true,
    order = "e-l-b"
  },
	{
    type = "technology",
    name = "efficient-belts-3",
    icon_size = 64, icon_mipmaps = 1,
    icon = efficient_belts_icon,
    effects =
    {
      {
        type = "nothing",
		effect_description = "Reduce energy usage of belts, splitters and loaders by another " .. reduction  .. "%"
      }
    },
    prerequisites = {"efficient-belts-2", "chemical-science-pack", "logistics-2"},
    unit =
    {
      count = 50*3,
      ingredients =
      {
        {"automation-science-pack", 1},
        {"logistic-science-pack", 1},
		{"chemical-science-pack", 1}
      },
      time = 60
    },
    upgrade = true,
    order = "e-l-c"
  },
  {
    type = "technology",
    name = "efficient-belts-4",
    icon_size = 64, icon_mipmaps = 1,
    icon = efficient_belts_icon,
    effects =
    {
      {
        type = "nothing",
		effect_description = "Reduce energy usage of belts, splitters and loaders by another " .. reduction  .. "%"
      }
    },
    prerequisites = {"efficient-belts-3", "production-science-pack"},
    unit =
    {
      count = 50*4,
      ingredients =
      {
        {"automation-science-pack", 1},
        {"logistic-science-pack", 1},
        {"chemical-science-pack", 1},
		{"production-science-pack", 1}
      },
      time = 60
    },
    upgrade = true,
    order = "e-l-d"
  },
   {
    type = "technology",
    name = "efficient-belts-5",
    icon_size = 64, icon_mipmaps = 1,
    icon = efficient_belts_icon,
    effects =
    {
      {
        type = "nothing",
		effect_description = "Reduce energy usage of belts, splitters and loaders by another " .. reduction  .. "%"
      }
    },
    prerequisites = {"efficient-belts-4", "utility-science-pack", "logistics-3"},
    unit =
    {
      count = 50*5,
      ingredients =
      {
        {"automation-science-pack", 1},
        {"logistic-science-pack", 1},
        {"chemical-science-pack", 1},
		{"production-science-pack", 1},
        {"utility-science-pack", 1}
      },
      time = 60
    },
     upgrade = true,
    order = "e-l-e"
  }
  
})
