require("prototypes.technology")

local um = settings.startup["powered-belts-usage-multiplier"].value
local num_levels = 5 --settings.startup["powered-belts-num-upgrades"].value
local reduction = settings.startup["powered-belts-upgrade-reduction"].value
local usage_name = tostring(settings.startup["powered-belts-usage-multiplier"].value):gsub("%.", "_")
local upgrade_name = tostring(settings.startup["powered-belts-upgrade-reduction"].value):gsub("%.", "_")

for _, v in pairs(data.raw["transport-belt"]) do
    if not string.match(v.name, "unpowered%-")  then
        local e = 160*v.speed*um
        local x = table.deepcopy(v)
        x.name = "unpowered-"..x.name
        x.speed = 1e-308 --speed has to be positive, this is close enough to 0
        x.localised_name = {"entity-name." .. v.name}
        x.localised_description = {"entity-description." .. v.name}
        data:extend({
            {
            type = "item",
            name = x.name,
            icon = "__base__/graphics/icons/signal/signal_everything.png",
            icon_size = 64,
            icon_mipmaps = 1,
            --flags = data.raw.item.lab.flags,
            --subgroup = data.raw.item.lab.subgroup,
            --order = data.raw.item.lab.order,
            stack_size = 100,
            place_result = x.name,
          }

        })
        data:extend({x})
        for i= 0, num_levels+1 do
            local ei = e * ((1-reduction) ^ i)
            data:extend({
                {
                type = "electric-energy-interface",
                name = v.name .. "-" .. usage_name .. "-" .. upgrade_name ..  "-" .. i .. "-power",
                icon = v.icon,
                icon_size = v.icon_size, icon_mipmaps = v.icon_mipmaps,
                flags = {"player-creation", "not-deconstructable","not-blueprintable"},
                max_health = 1,
                resistances = resistances_immune,
                collision_mask = {"ghost-layer"},
                collision_box = v.collision_box,
                selection_box = v.selection_box,
                drawing_box = v.drawing_box,
                selectable_in_game = false,
                energy_source =
                {
                    type = "electric",
                    usage_priority = "secondary-input",
                    input_flow_limit= (ei+1).."kW",
                    buffer_capacity = (1*ei).."kJ"
                },
                energy_production = "0W",
                energy_usage = ei.."kW"
            }
        })
        end
    end
end
for _, v in pairs(data.raw["underground-belt"]) do
    if not string.match(v.name, "unpowered%-")  then
        local e = 160*v.speed*um*(v.max_distance+2)
        local x = table.deepcopy(v)
        x.name = "unpowered-"..x.name
        x.speed = 1e-308
        x.localised_name = {"entity-name." .. v.name}
        x.localised_description = {"entity-description." .. v.name}
        data:extend({
            {
            type = "item",
            name = x.name,
            icon = "__base__/graphics/icons/signal/signal_everything.png",
            icon_size = 64,
            icon_mipmaps = 1,
            --flags = data.raw.item.lab.flags,
            --subgroup = data.raw.item.lab.subgroup,
            --order = data.raw.item.lab.order,
            stack_size = 100,
            place_result = x.name,
          }

        })
        data:extend({x})
        for i= 0, num_levels+1 do
            local ei = e * ((1-reduction) ^ i)
            data:extend({
                {
                type = "electric-energy-interface",
                name = v.name .. "-" .. usage_name .. "-" .. upgrade_name ..  "-" .. i .. "-power",
                icon = v.icon,
                icon_size = v.icon_size, icon_mipmaps = v.icon_mipmaps,
                flags = {"player-creation", "not-deconstructable","not-blueprintable"},
                max_health = 1,
                resistances = resistances_immune,
                collision_mask = {"ghost-layer"},
                collision_box = v.collision_box,
                selection_box = v.selection_box,
                drawing_box = v.drawing_box,
                selectable_in_game = false,
                energy_source =
                {
                    type = "electric",
                    usage_priority = "secondary-input",
                    input_flow_limit= (ei+1).."kW",
                    buffer_capacity = (1*ei).."kJ"
                },
                energy_production = "0W",
                energy_usage = ei.."kW"
            }
        })
        end
    end
end
for _, v in pairs(data.raw["splitter"]) do
    if not string.match(v.name, "unpowered%-")  then
        local e = 160*v.speed*um*5
        local x = table.deepcopy(v)
        x.name = "unpowered-"..x.name
        x.speed = 1e-308
        x.localised_name = {"entity-name." .. v.name}
        x.localised_description = {"entity-description." .. v.name}
        data:extend({
            {
            type = "item",
            name = x.name,
            icon = "__base__/graphics/icons/signal/signal_everything.png",
            icon_size = 64,
            icon_mipmaps = 1,
            --flags = data.raw.item.lab.flags,
            --subgroup = data.raw.item.lab.subgroup,
            --order = data.raw.item.lab.order,
            stack_size = 100,
            place_result = x.name,
          }

        })
        data:extend({x})
        for i= 0, num_levels+1 do
            local ei = e * ((1-reduction) ^ i)
            data:extend({
                {
                type = "electric-energy-interface",
                name = v.name .. "-" .. usage_name .. "-" .. upgrade_name ..  "-" .. i .. "-power",
                icon = v.icon,
                icon_size = v.icon_size, icon_mipmaps = v.icon_mipmaps,
                flags = {"player-creation", "not-deconstructable","not-blueprintable"},
                max_health = 1,
                resistances = resistances_immune,
                collision_mask = {"ghost-layer"},
                collision_box = v.collision_box,
                selection_box = v.selection_box,
                drawing_box = v.drawing_box,
                selectable_in_game = false,
                energy_source =
                {
                    type = "electric",
                    usage_priority = "secondary-input",
                    input_flow_limit= (ei+1).."kW",
                    buffer_capacity = (1*ei).."kJ"
                },
                energy_production = "0W",
                energy_usage = ei.."kW"
            }
        })
        end
    end
end
for _, v in pairs(data.raw["loader-1x1"]) do
    if not string.match(v.name, "unpowered%-")  then
        local e = 160*v.speed*um*5
        local x = table.deepcopy(v)
        x.name = "unpowered-"..x.name
        x.speed = 1e-308
        x.localised_name = {"entity-name." .. v.name}
        x.localised_description = {"entity-description." .. v.name}
        data:extend({
            {
            type = "item",
            name = x.name,
            icon = "__base__/graphics/icons/signal/signal_everything.png",
            icon_size = 64,
            icon_mipmaps = 1,
            --flags = data.raw.item.lab.flags,
            --subgroup = data.raw.item.lab.subgroup,
            --order = data.raw.item.lab.order,
            stack_size = 100,
            place_result = x.name,
          }

        })
        data:extend({x})
        for i= 0, num_levels+1 do
            local ei = e * ((1-reduction) ^ i)
            data:extend({
                {
                type = "electric-energy-interface",
                name = v.name .. "-" .. usage_name .. "-" .. upgrade_name ..  "-" .. i .. "-power",
                icon = v.icon,
                icon_size = v.icon_size, icon_mipmaps = v.icon_mipmaps,
                flags = {"player-creation", "not-deconstructable","not-blueprintable"},
                max_health = 1,
                resistances = resistances_immune,
                collision_mask = {"ghost-layer"},
                collision_box = v.collision_box,
                selection_box = v.selection_box,
                drawing_box = v.drawing_box,
                selectable_in_game = false,
                energy_source =
                {
                    type = "electric",
                    usage_priority = "secondary-input",
                    input_flow_limit= (ei+1).."kW",
                    buffer_capacity = (1*ei).."kJ"
                },
                energy_production = "0W",
                energy_usage = ei.."kW"
            }
        })
        end
    end
end
for _, v in pairs(data.raw["loader"]) do
    if not string.match(v.name, "unpowered%-")  then
        local e = 160*v.speed*um*10
        local x = table.deepcopy(v)
        x.name = "unpowered-"..x.name
        x.speed = 1e-308
        x.localised_name = {"entity-name." .. v.name}
        x.localised_description = {"entity-description." .. v.name}
        data:extend({
            {
            type = "item",
            name = x.name,
            icon = "__base__/graphics/icons/signal/signal_everything.png",
            icon_size = 64,
            icon_mipmaps = 1,
            --flags = data.raw.item.lab.flags,
            --subgroup = data.raw.item.lab.subgroup,
            --order = data.raw.item.lab.order,
            stack_size = 100,
            place_result = x.name,
          }

        })
        data:extend({x})
        for i= 0, num_levels+1 do
            local ei = e * ((1-reduction) ^ i)
            data:extend({
                {
                type = "electric-energy-interface",
                name = v.name .. "-" .. usage_name .. "-" .. upgrade_name ..  "-" .. i .. "-power",
                icon = v.icon,
                icon_size = v.icon_size, icon_mipmaps = v.icon_mipmaps,
                flags = {"player-creation", "not-deconstructable","not-blueprintable"},
                max_health = 1,
                resistances = resistances_immune,
                collision_mask = {"ghost-layer"},
                collision_box = v.collision_box,
                selection_box = v.selection_box,
                drawing_box = v.drawing_box,
                selectable_in_game = false,
                energy_source =
                {
                    type = "electric",
                    usage_priority = "secondary-input",
                    input_flow_limit= (ei+1).."kW",
                    buffer_capacity = (1*ei).."kJ"
                },
                energy_production = "0W",
                energy_usage = ei.."kW"
            }
        })
        end
    end
end