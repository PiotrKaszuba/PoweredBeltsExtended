data:extend({
    {
        type = "int-setting",
        name = "powered-belts-operations-per-tick",
        setting_type = "runtime-global",
        default_value = 16,
        minimum_value = 1,
        order = "a"
    },
    {
        type = "double-setting",
        name = "powered-belts-usage-multiplier",
        setting_type = "startup",
        default_value = 1,
        minimum_value = 0,
        order = "a"
    },
    {
        type = "double-setting",
        name = "powered-belts-required-energy",
        setting_type = "runtime-global",
        default_value = 500,
        minimum_value = 0,
        order = "a"
    }

})