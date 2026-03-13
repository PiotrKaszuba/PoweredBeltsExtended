require("shared_items")

local y = layouts.y_line
local x0 = layouts.x_start
local x_end = x0 + 6.0

return {
	id = "aai_loader_line",
	y_line = y,
	area = {
		left_top = {
			x = x0 - layouts.x_margin,
			y = y - layouts.y_width / 2.0,
		},
		right_bottom = {
			x = x_end + layouts.x_margin,
			y = y + layouts.y_width / 2.0,
		},
	},
	references = {
		source = "source_chest",
		sink = "sink_chest",
		loader_out = "loader_output",
		loader_in = "loader_input",
		loader_all = {"loader_output", "loader_input"},
	},
	entities = {
		{
			id = "source_chest",
			name = "steel-chest",
			position = {x = x0, y = y},
		},
		{
			id = "sink_chest",
			name = "steel-chest",
			position = {x = x_end, y = y},
		},
		{
			id = "loader_output",
			name = "aai-loader",
			position = {x = x0 + 1.0, y = y},
			direction = 4,
			type = "output",
		},
		{
			id = "belt_mid_1",
			name = "transport-belt",
			position = {x = x0 + 2.0, y = y},
			direction = 4,
		},
		{
			id = "belt_mid_2",
			name = "transport-belt",
			position = {x = x0 + 3.0, y = y},
			direction = 4,
		},
		{
			id = "belt_mid_3",
			name = "transport-belt",
			position = {x = x0 + 4.0, y = y},
			direction = 4,
		},
		{
			id = "loader_input",
			name = "aai-loader",
			position = {x = x0 + 5.0, y = y},
			direction = 4,
			type = "input",
		},
	},
}
