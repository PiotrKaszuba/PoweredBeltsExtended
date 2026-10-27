local M = {}

function M.get_all()
    local scenarios = {}
    for _, fraction in ipairs({0.4, 1}) do
        scenarios[#scenarios + 1] = {
            id = "aai_connected_segment_" .. (fraction == 1 and "full" or "partial"),
            required_mods = {"PoweredBeltsExtended", "aai-loaders"},
            required_aai_loader_mode = "lubricated",
            layout_id = "aai_loader_dual_line_adjacent", max_tick = 500,
            actions = {
                {tick = 200, type = "seed_aai_segment", fraction = fraction},
                {tick = 200, type = "set_surface_daylight", mode = "midnight"},
                {tick = 201, type = "set_power_buffers", target_refs = {"loader_output_top"}, fraction = 0},
                {tick = 210, type = "set_surface_daylight", mode = "full-day"},
            },
            checkpoints = {
                {tick = 202, assertions = {{type = "aai_segment_balance", phase = "off"}, {type = "structural_consistency"}}},
                {tick = 500, assertions = {{type = "aai_segment_balance", phase = "on"}, {type = "structural_consistency"}}},
            },
        }
    end
    for _, tier in ipairs({"transport-belt", "fast-transport-belt", "express-transport-belt"}) do
        scenarios[#scenarios + 1] = {
            id = "floating_" .. tier .. "_outage",
            required_mods = {"PoweredBeltsExtended", "dredgeworks"},
            layout_id = "straight_line", inserter_name = "bulk-inserter", belt_name = "floating-" .. tier, max_tick = 2200,
            timing_probe = {refs = {"input_belt_1"}, off_tick = 220, on_tick = 380},
            actions = {
                {tick = 0, type = "paint_belt_tiles", name = "water"},
                {tick = 0, type = "fill_inventory", target_ref = "source", stacks = {{name = "iron-plate", count = 60}}},
                {tick = 220, type = "set_surface_daylight", mode = "midnight"},
                {tick = 380, type = "set_surface_daylight", mode = "full-day"},
            },
            checkpoints = {
                {tick = 900, assertions = {{type = "power_transition_spread_bounds", down_max_spread = 0, up_max_spread = 0}}},
                {tick = 2200, assertions = {
                    {type = "transfer_complete", source_ref = "source", sink_ref = "sink", expected_contents = {{name = "iron-plate", count = 60}}, source_should_be_empty = true},
                    {type = "structural_consistency"},
                }},
            },
        }
    end
    return scenarios
end

return M
