require("shared_items")

local underground_len = 3
local num_input_belts = 2
local num_output_belts = 2
local belts_between_underground_end_and_splitter = 1

local x_add_to_end = 7.0 + underground_len + belts_between_underground_end_and_splitter + num_output_belts

local layout_skeleton = layouts.get_layout_skeleton("underground_splitter_line_multi_io", num_input_belts, true, underground_len, true, belts_between_underground_end_and_splitter, num_output_belts, true, true)

layout_skeleton.references = {
    source = {
      "source_chest_inline",
      "source_chest_north_left",
      "source_chest_north_right",
      "source_chest_south_left",
      "source_chest_south_right",
    },
    sink = {
      "sink_chest_inline",
      "sink_chest_north",
      "sink_chest_south",
    },
    input_inserter = {
      "input_inserter_inline",
      "input_inserter_north_left",
      "input_inserter_north_right",
      "input_inserter_south_left",
      "input_inserter_south_right",
    },
    output_inserter = {
      "output_inserter_inline",
      "output_inserter_north",
      "output_inserter_south",
    },
  }



local additional_entities = {
    {
      id = "source_chest_inline",
      name = "steel-chest",
      position = {
        x = layouts.x_start,
        y = layouts.y_line,
      },
    },
    {
      id = "input_inserter_inline",
      name = "burner-inserter",
      position = {
        x = layouts.x_start + 1.0,
        y = layouts.y_line,
      },
      direction = 12,
    },
    {
      id = "source_chest_north_left",
      name = "steel-chest",
      position = {
        x = layouts.x_start + 2.0,
        y = layouts.y_line - 2.0,
      },
    },
    {
      id = "input_inserter_north_left",
      name = "burner-inserter",
      position = {
        x = layouts.x_start + 2.0,
        y = layouts.y_line - 1.0,
      },
      direction = 0,
    },
    {
      id = "source_chest_north_right",
      name = "steel-chest",
      position = {
        x = layouts.x_start + 3.0,
        y = layouts.y_line - 2.0,
      },
    },
    {
      id = "input_inserter_north_right",
      name = "burner-inserter",
      position = {
        x = layouts.x_start + 3.0,
        y = layouts.y_line - 1.0,
      },
      direction = 0,
    },
    {
      id = "source_chest_south_left",
      name = "steel-chest",
      position = {
        x = layouts.x_start + 2.0,
        y = layouts.y_line + 2.0,
      },
    },
    {
      id = "input_inserter_south_left",
      name = "burner-inserter",
      position = {
        x = layouts.x_start + 2.0,
        y = layouts.y_line + 1.0,
      },
      direction = 8,
    },
    {
      id = "source_chest_south_right",
      name = "steel-chest",
      position = {
        x = layouts.x_start + 3.0,
        y = layouts.y_line + 2.0,
      },
    },
    {
      id = "input_inserter_south_right",
      name = "burner-inserter",
      position = {
        x = layouts.x_start + 3.0,
        y = layouts.y_line + 1.0,
      },
      direction = 8,
    },
    {
      id = "output_inserter_north",
      name = "burner-inserter",
      position = {
        x = layouts.x_start + x_add_to_end,
        y = layouts.y_line - 1.0,
      },
      direction = 8,
    },
    {
      id = "sink_chest_north",
      name = "steel-chest",
      position = {
        x = layouts.x_start + x_add_to_end,
        y = layouts.y_line - 2.0,
      },
    },
    {
      id = "output_inserter_south",
      name = "burner-inserter",
      position = {
        x = layouts.x_start + x_add_to_end,
        y = layouts.y_line + 1.0,
      },
      direction = 0,
    },
    {
      id = "sink_chest_south",
      name = "steel-chest",
      position = {
        x = layouts.x_start + x_add_to_end,
        y = layouts.y_line + 2.0,
      },
    },
    {
      id = "output_inserter_inline",
      name = "burner-inserter",
      position = {
        x = layouts.x_start + x_add_to_end + 1.0,
        y = layouts.y_line,
      },
      direction = 12,
    },
    {
      id = "sink_chest_inline",
      name = "steel-chest",
      position = {
        x = layouts.x_start + x_add_to_end + 2.0,
        y = layouts.y_line,
      },
    },
  }

for _, entity in ipairs(additional_entities) do
  table.insert(layout_skeleton.entities, entity)
end

return layout_skeleton
