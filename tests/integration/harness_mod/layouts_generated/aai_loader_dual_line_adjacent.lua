require("shared_items")

local y_top = layouts.y_line
local y_bottom = layouts.y_line + 1.0
local x0 = layouts.x_start
local x_end = x0 + 6.0

return {
	id = "aai_loader_dual_line_adjacent",
	y_line = y_top,
	area = {
		left_top = {
			x = x0 - layouts.x_margin,
			y = y_top - layouts.y_width / 2.0,
		},
		right_bottom = {
			x = x_end + layouts.x_margin,
			y = y_bottom + layouts.y_width / 2.0,
		},
	},
	references = {
		source = {"source_chest_top", "source_chest_bottom"},
		sink = {"sink_chest_top", "sink_chest_bottom"},
		source_top = "source_chest_top",
		source_bottom = "source_chest_bottom",
		loader_out = {"loader_output_top", "loader_output_bottom"},
		loader_in = {"loader_input_top", "loader_input_bottom"},
		loader_all = {"loader_output_top", "loader_input_top", "loader_output_bottom", "loader_input_bottom"},
	},
	entities = {
		{
			id = "source_chest_top",
			name = "steel-chest",
			position = {x = x0, y = y_top},
		},
		{
			id = "sink_chest_top",
			name = "steel-chest",
			position = {x = x_end, y = y_top},
		},
		{
			id = "loader_output_top",
			name = "aai-loader",
			position = {x = x0 + 1.0, y = y_top},
			direction = 4,
			type = "output",
		},
		{
			id = "belt_top_1",
			name = "transport-belt",
			position = {x = x0 + 2.0, y = y_top},
			direction = 4,
		},
		{
			id = "belt_top_2",
			name = "transport-belt",
			position = {x = x0 + 3.0, y = y_top},
			direction = 4,
		},
		{
			id = "belt_top_3",
			name = "transport-belt",
			position = {x = x0 + 4.0, y = y_top},
			direction = 4,
		},
		{
			id = "loader_input_top",
			name = "aai-loader",
			position = {x = x0 + 5.0, y = y_top},
			direction = 4,
			type = "input",
		},
		{
			id = "source_chest_bottom",
			name = "steel-chest",
			position = {x = x0, y = y_bottom},
		},
		{
			id = "sink_chest_bottom",
			name = "steel-chest",
			position = {x = x_end, y = y_bottom},
		},
		{
			id = "loader_output_bottom",
			name = "aai-loader",
			position = {x = x0 + 1.0, y = y_bottom},
			direction = 4,
			type = "output",
		},
		{
			id = "belt_bottom_1",
			name = "transport-belt",
			position = {x = x0 + 2.0, y = y_bottom},
			direction = 4,
		},
		{
			id = "belt_bottom_2",
			name = "transport-belt",
			position = {x = x0 + 3.0, y = y_bottom},
			direction = 4,
		},
		{
			id = "belt_bottom_3",
			name = "transport-belt",
			position = {x = x0 + 4.0, y = y_bottom},
			direction = 4,
		},
		{
			id = "loader_input_bottom",
			name = "aai-loader",
			position = {x = x0 + 5.0, y = y_bottom},
			direction = 4,
			type = "input",
		},
	},
}
