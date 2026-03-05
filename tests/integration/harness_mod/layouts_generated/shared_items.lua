
layouts = {}

layouts.y_line = 0.5
layouts.x_start = 0.5
layouts.y_width = 32.0
layouts.x_margin = 16.0

layouts.get_layout_skeleton = function(
    id,
    input_belt_num,
    use_underground_belt,
    underground_len,
    use_splitter_after_underground,
    belts_between_underground_end_and_splitter,
    output_belt_num,
    exclude_sink_source_chest_and_refs,
    exclude_input_output_inserter

    )
    local total_x_width = (4.0 + -- source/sink chest, inserters
    input_belt_num +
    (use_underground_belt and (2.0 + underground_len) or 0.0) +
    (use_splitter_after_underground and (2.0 + belts_between_underground_end_and_splitter) or 0.0) +
    output_belt_num)

    local x_end = layouts.x_start + total_x_width - 1.0
    local x_belt_start = layouts.x_start + 2.0
    local x_input_belt_end = x_belt_start + input_belt_num - 1.0
    local x_output_belt_end = x_end - 2.0
    local x_underground_start = x_input_belt_end + 1.0
    local x_underground_end = x_underground_start + underground_len + 1.0
    local x_splitter = x_underground_end + belts_between_underground_end_and_splitter + 1.0

    local sink_source_refs = {
        source = "source_chest",
        sink = "sink_chest",
    }


    local refs = exclude_sink_source_chest_and_refs and {} or sink_source_refs

    local sink_source_entities = {
        {
            id = "source_chest",
            name = "steel-chest",
            position = {
                x = layouts.x_start,
                y = layouts.y_line,
            },
        },
        {
            id = "sink_chest",
            name = "steel-chest",
            position = {
                x = x_end,
                y = layouts.y_line,
            },
        },
    }
    local extra_entities = {}
    if not exclude_sink_source_chest_and_refs then
        for _, entity in ipairs(sink_source_entities) do
            table.insert(extra_entities, entity)
        end
    end
    local input_output_inserter_entities = {
        {
            id = "input_inserter",
            name = "burner-inserter",
            position = {
                x = layouts.x_start + 1.0,
                y = layouts.y_line,
            },
            direction = 12,
        },
        {
            id = "output_inserter",
            name = "burner-inserter",
            position = {
                x = x_end - 1.0,
                y = layouts.y_line,
            },
            direction = 12,
        },
    }

    if not exclude_input_output_inserter then
        for _, entity in ipairs(input_output_inserter_entities) do
            table.insert(extra_entities, entity)
        end
    end


    local layout = {
        id = id,
        y_line = layouts.y_line,
        area = {
        left_top = {
            x = layouts.x_start - layouts.x_margin,
            y = layouts.y_line - layouts.y_width / 2.0,
        },
        right_bottom = {
            x = layouts.x_start + total_x_width + layouts.x_margin,
            y = layouts.y_line + layouts.y_width / 2.0,
        },
        },
        references = refs,
    
        entities = extra_entities,
    }
    for i = 1, input_belt_num do
        table.insert(layout.entities, {
            id = "input_belt_" .. i,
            name = "transport-belt",
            position = {
                x = x_belt_start + (i - 1),
                y = layouts.y_line,
            },
            direction = 4,
        })
    end
    for i = 1, output_belt_num do
        table.insert(layout.entities, {
            id = "output_belt_" .. i,
            name = "transport-belt",
            position = {
                x = x_output_belt_end - (i - 1),
                y = layouts.y_line,
            },
            direction = 4,
        })
    end
    -- underground belt is after the input belts

    if use_underground_belt then
        table.insert(layout.entities, {
            id = "underground_input",
            name = "underground-belt",
            position = {
                x = x_underground_start,
                y = layouts.y_line,
            },
            direction = 4,
            type = "input",
        })
        table.insert(layout.entities, {
            id = "underground_output",
            name = "underground-belt",
            position = {
                x = x_underground_end,
                y = layouts.y_line,
            },
            direction = 4,
            type = "output",
        })
    
        if use_splitter_after_underground then
            table.insert(layout.entities, {
                id = "line_splitter",
                name = "splitter",
                position = {
                    x = x_splitter,
                    y = layouts.y_line,
                },
                direction = 4,
            })
            -- belt after splitter at y_line and at y_line + 1.0 facing north
            table.insert(layout.entities, {
                id = "belt_after_splitter_straight",
                name = "transport-belt",
                position = {
                    x = x_splitter + 1.0,
                    y = layouts.y_line,
                },
                direction = 4,
            })
            table.insert(layout.entities, {
                id = "belt_after_splitter_north",
                name = "transport-belt",
                position = {
                    x = x_splitter + 1.0,
                    y = layouts.y_line + 1.0,
                },
                direction = 0,
            })

            -- belts before splitter after underground
            for i = 1, belts_between_underground_end_and_splitter do
                table.insert(layout.entities, {
                    id = "belt_before_splitter_" .. i,
                    name = "transport-belt",
                    position = {
                        x = x_underground_end + i,
                        y = layouts.y_line,
                    },
                    direction = 4,
                })
            end

        end
    end
    return layout
end
