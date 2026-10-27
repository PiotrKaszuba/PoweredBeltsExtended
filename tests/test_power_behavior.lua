-- Pure policy/cache checks complement the real LuaCustomTable engine regression.
local behavior = require("modules.power_behavior")
local utils = require("modules.utils")
local count = 0
local function check(actual, expected)
    assert(math.abs(actual - expected) < 1e-9, tostring(actual) .. " != " .. tostring(expected))
    count = count + 1
end
settings = {startup = {}, global = {}}
storage = {test_overrides = {}}
game = {tick = 1}
local names = behavior.setting_names
settings.startup[names.startup_preset] = {value = "custom"}
settings.global[names.required_pct] = {value = 50}
settings.global[names.required_flat] = {value = 10}
settings.global[names.hysteresis_pct] = {value = 20}
check(utils.get_energy_threshold_config().down_pct, 48)
check(utils.get_energy_threshold_config().up_pct, 72)
local cached = utils.get_energy_threshold_config()
assert(utils.get_energy_threshold_config() == cached, "Repeated reads should reuse the configuration")
settings.global[names.required_flat] = {value = 0}
game.tick = 2
check(utils.get_energy_threshold_config().down_pct, 40)
check(utils.get_energy_threshold_config().up_pct, 60)
storage.test_overrides = {required_energy_percentage = 25}
check(utils.get_energy_threshold_config().down_pct, 20)
check(utils.get_energy_threshold_config().up_pct, 30)
settings.startup[names.startup_preset] = {value = "responsive"}
game.tick = 3
check(utils.get_energy_threshold_config().down_pct, 45)
check(utils.get_energy_threshold_config().up_pct, 55)
local flow, buffer = behavior.compute_power_source_values(5, behavior.resolve_startup_settings(settings.startup))
check(flow, 25)
check(buffer, 1.25)
print("Power policy/cache: " .. count .. " numeric checks and cache identity passed")
