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
        default_value = 0.2,
        minimum_value = 0,
        order = "a"
    },
    {
        type = "double-setting",
        name = "powered-belts-speed-exponent",
        setting_type = "startup",
        default_value = 1.0,
        minimum_value = 0.0,
        maximum_value = 3.0,
        order = "a"
    },
    {
        type = "double-setting",
        name = "powered-belts-required-energy",
        setting_type = "runtime-global",
        default_value = 500,
        minimum_value = 0,
        hidden = true,
        order = "a"
    },
    {
        type = "string-setting",
        name = "powered-belts-underground-item-transfer-mode",
        setting_type = "runtime-global",
        default_value = "preserve-full-state",
        allow_blank = false,
        allowed_values = {"name-only", "preserve-full-state", "disabled"},
        hidden = true,
        order = "a"
    },
    {
        type = "int-setting",
        name = "powered-belts-efficiency-tech-cost-per-level",
        setting_type = "startup",
        default_value = 50,
        minimum_value = 25,
        maximum_value = 200,
        order = "a"
    },
    {
        type = "int-setting",
        name = "powered-belts-num-upgrades",
        setting_type = "startup",
        default_value = 5,
        minimum_value = 0,
        maximum_value = 10,
        order = "a"
    },
    {
        type = "double-setting",
        name = "powered-belts-upgrade-reduction",
        setting_type = "startup",
        default_value = 0.2,
        minimum_value = 0,
        maximum_value = 1.0,
        order = "a"
    },
})
