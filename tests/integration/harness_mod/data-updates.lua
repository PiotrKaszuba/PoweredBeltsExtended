-- Synthetic valid upgrade chain with a nonstandard collision mask. This checks
-- the general clone contract behind issue #11, without claiming Dredgeworks support.
local added = {}
for _, source in ipairs({"transport-belt", "fast-transport-belt", "express-transport-belt"}) do
    local name = "pbe-fixture-floating-" .. source
    local belt = table.deepcopy(data.raw["transport-belt"][source])
    belt.name = name
    belt.collision_mask = {layers = {ground_tile = true, object = true, transport_belt = true}}
    belt.fast_replaceable_group = "pbe-fixture-floating"
    belt.next_upgrade = belt.next_upgrade and "pbe-fixture-floating-" .. belt.next_upgrade
    belt.minable = {mining_time = 0.1, result = name}
    local item = table.deepcopy(data.raw.item[source])
    item.name = name
    item.place_result = name
    added[#added + 1] = belt
    added[#added + 1] = item
end
data:extend(added)
