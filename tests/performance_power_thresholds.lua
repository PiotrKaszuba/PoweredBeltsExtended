-- Focused mock CPU comparison, not native UPS or a whole-update-loop benchmark.
-- Optional argument: exported pre-change modules/utils.lua for matched comparison.
local utils = arg[1] and assert(loadfile(arg[1]))() or require("modules.utils")
settings = {startup = {["powered-belts-energy-behavior-preset"] = {value = "default"}}, global = {}}
storage = {test_overrides = {}}
game = {tick = 0}
for _, operations in ipairs({16, 1024}) do
    local function workload()
        local total = 0
        for tick = 1, 1000 do
            game.tick = tick
            for i = 1, operations do
                -- Same two-getter access pattern on both versions: isolates caching.
                total = total + utils.get_power_down_required_energy_percentage_setting()
                    + utils.get_power_up_required_energy_percentage_setting()
            end
        end
        assert(total == operations * 1000 * 100)
    end
    workload()
    collectgarbage("collect")
    local start = os.clock()
    workload()
    print(string.format("%d,%.6f", operations, os.clock() - start))
end
