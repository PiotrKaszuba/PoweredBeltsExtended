-- Native contracts for the 2.1 port; no production hooks or runtime overrides.
local M = {}

local function loader_pipe(active, world, ref)
    local loader = assert(world.get_referenced_entity(active, ref))
    local name = world.base_powered_name(loader.name) .. "-pipe"
    return active.surface.find_entities_filtered{
        name = name, position = {loader.position.x, loader.position.y + 1 / 32}, radius = 0.12
    }[1]
end

function M.seed_segment(active, action, world)
    local pipe = assert(loader_pipe(active, world, "loader_output_top"), "Missing AAI pipe")
    local peer = assert(loader_pipe(active, world, "loader_output_bottom"))
    assert(pipe.get_fluid_segment_id(1) == peer.get_fluid_segment_id(1), "Fixture pipes must connect")
    local capacity = pipe.get_fluid_segment_capacity(1)
    assert(capacity > pipe.get_fluid_capacity(1), "Fixture must have multiple fluid storages")
    pipe.clear_fluid_segment_fluid(1)
    local amount = capacity * action.fraction
    assert(math.abs(pipe.add_fluid_segment_fluid(1, {name = "lubricant", amount = amount}) - amount) < 0.001)
    active.segment_trial = {amount = amount, expect_snapshot = action.fraction == 1}
end

function M.check_segment(active, assertion, world)
    local trial = assert(active.segment_trial)
    local peer = loader_pipe(active, world, "loader_output_bottom")
    if not peer then return false, "Surviving AAI pipe missing" end
    local fluid = peer.get_fluid_segment_fluid(1)
    local total = fluid and fluid.amount or 0
    local snapshots = remote.call("powered_belts_extended", "get_storage").compatibility.aai_pipe_fluid_snapshots
    local saved = 0
    for _, snapshot in pairs(snapshots[active.surface.index] or {}) do
        saved = saved + snapshot.fluid.amount
    end
    total = total + saved
    local top = world.get_referenced_entity(active, "loader_output_top")
    local off = top and string.find(top.name, "^unpowered%-") ~= nil
    local expected_off = assertion.phase == "off"
    local ok = off == expected_off and total <= trial.amount + 0.001
        and total + 0.001 >= trial.amount - (assertion.phase == "off" and 2 or 5)
    if expected_off then
        ok = ok and ((saved > 0) == trial.expect_snapshot)
    else
        ok = ok and saved == 0
    end
    return ok, "Connected AAI segment balance", {total = total, seeded = trial.amount, saved = saved, off = off}
end

function M.paint_belt_tiles(active, action, world)
    local tiles = {}
    for _, def in ipairs(active.layout.entities) do
        local entity = world.get_referenced_entity(active, def.id)
        if entity and entity.type == "transport-belt" then
            tiles[#tiles + 1] = {name = action.name, position = entity.position}
        end
    end
    active.surface.set_tiles(tiles)
end

return M
