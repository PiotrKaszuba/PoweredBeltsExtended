return {
  id = "underground_splitter_line",
  version = 1,
  area = {
    left_top = {
      x = -5.0,
      y = -5.0,
    },
    right_bottom = {
      x = 30.0,
      y = 15.0,
    },
  },
  references = {
    source = "source_chest",
    sink = "sink_chest",
  },
  entities = {
    {
      id = "source_chest",
      name = "steel-chest",
      position = {
        x = 0.5,
        y = 0.5,
      },
    },
    {
      id = "input_inserter",
      name = "burner-inserter",
      position = {
        x = 1.5,
        y = 0.5,
      },
      direction = 12,
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
      id = "output_inserter",
      name = "burner-inserter",
      position = {
        x = 14.5,
        y = 0.5,
      },
      direction = 12,
    },
    {
      id = "sink_chest",
      name = "steel-chest",
      position = {
        x = 15.5,
        y = 0.5,
      },
    },
  },
}
