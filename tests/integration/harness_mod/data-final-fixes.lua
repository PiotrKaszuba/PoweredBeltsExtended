if mods.PoweredBeltsExtended then
    for _, tier in ipairs({"transport-belt", "fast-transport-belt", "express-transport-belt"}) do
        local name = "pbe-fixture-floating-" .. tier
        local source = assert(data.raw["transport-belt"][name])
        local clone = assert(data.raw["transport-belt"]["unpowered-" .. name], "Missing synthetic floating clone")
        assert(clone.next_upgrade == source.next_upgrade, "Unexpected clone upgrade target")
        for layer, value in pairs(source.collision_mask.layers) do
            assert(clone.collision_mask.layers[layer] == value, "Floating collision-mask mismatch")
        end
    end
end
