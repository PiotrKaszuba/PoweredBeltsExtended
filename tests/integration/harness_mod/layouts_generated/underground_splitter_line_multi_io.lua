return {
  id = "underground_splitter_line_multi_io",
  version = 1,
  area = {
    left_top = {
      x = -6.0,
      y = -8.0,
    },
    right_bottom = {
      x = 30.0,
      y = 18.0,
    },
  },
  references = {
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
  },
  entities = {
    {
      id = "source_chest_inline",
      name = "steel-chest",
      position = {
        x = 0.5,
        y = 0.5,
      },
    },
    {
      id = "input_inserter_inline",
      name = "burner-inserter",
      position = {
        x = 1.5,
        y = 0.5,
      },
      direction = 12,
    },
    {
      id = "source_chest_north_left",
      name = "steel-chest",
      position = {
        x = 2.5,
        y = -1.5,
      },
    },
    {
      id = "input_inserter_north_left",
      name = "burner-inserter",
      position = {
        x = 2.5,
        y = -0.5,
      },
      direction = 0,
    },
    {
      id = "source_chest_north_right",
      name = "steel-chest",
      position = {
        x = 3.5,
        y = -1.5,
      },
    },
    {
      id = "input_inserter_north_right",
      name = "burner-inserter",
      position = {
        x = 3.5,
        y = -0.5,
      },
      direction = 0,
    },
    {
      id = "source_chest_south_left",
      name = "steel-chest",
      position = {
        x = 2.5,
        y = 2.5,
      },
    },
    {
      id = "input_inserter_south_left",
      name = "burner-inserter",
      position = {
        x = 2.5,
        y = 1.5,
      },
      direction = 8,
    },
    {
      id = "source_chest_south_right",
      name = "steel-chest",
      position = {
        x = 3.5,
        y = 2.5,
      },
    },
    {
      id = "input_inserter_south_right",
      name = "burner-inserter",
      position = {
        x = 3.5,
        y = 1.5,
      },
      direction = 8,
    },
    {
      id = "belt_1",
      name = "transport-belt",
      position = {
        x = 2.5,
        y = 0.5,
      },
      direction = 4,
    },
    {
      id = "belt_2",
      name = "transport-belt",
      position = {
        x = 3.5,
        y = 0.5,
      },
      direction = 4,
    },
    {
      id = "underground_input",
      name = "underground-belt",
      position = {
        x = 4.5,
        y = 0.5,
      },
      direction = 4,
      type = "input",
    },
    {
      id = "underground_output",
      name = "underground-belt",
      position = {
        x = 8.5,
        y = 0.5,
      },
      direction = 4,
      type = "output",
    },
    {
      id = "belt_3",
      name = "transport-belt",
      position = {
        x = 9.5,
        y = 0.5,
      },
      direction = 4,
    },
    {
      id = "belt_4",
      name = "transport-belt",
      position = {
        x = 10.5,
        y = 0.5,
      },
      direction = 4,
    },
    {
      id = "line_splitter",
      name = "splitter",
      position = {
        x = 11.0,
        y = 0.5,
      },
      direction = 4,
    },
    {
      id = "belt_5",
      name = "transport-belt",
      position = {
        x = 12.5,
        y = 0.5,
      },
      direction = 4,
    },
    {
      id = "belt_merge_north",
      name = "transport-belt",
      position = {
        x = 12.5,
        y = 1.5,
      },
      direction = 0,
    },
    {
      id = "belt_6",
      name = "transport-belt",
      position = {
        x = 13.5,
        y = 0.5,
      },
      direction = 4,
    },
    {
      id = "output_inserter_north",
      name = "burner-inserter",
      position = {
        x = 13.5,
        y = -0.5,
      },
      direction = 8,
    },
    {
      id = "sink_chest_north",
      name = "steel-chest",
      position = {
        x = 13.5,
        y = -1.5,
      },
    },
    {
      id = "output_inserter_south",
      name = "burner-inserter",
      position = {
        x = 13.5,
        y = 1.5,
      },
      direction = 0,
    },
    {
      id = "sink_chest_south",
      name = "steel-chest",
      position = {
        x = 13.5,
        y = 2.5,
      },
    },
    {
      id = "output_inserter_inline",
      name = "burner-inserter",
      position = {
        x = 14.5,
        y = 0.5,
      },
      direction = 12,
    },
    {
      id = "sink_chest_inline",
      name = "steel-chest",
      position = {
        x = 15.5,
        y = 0.5,
      },
    },
  },
}
