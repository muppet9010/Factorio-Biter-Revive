data:extend(
    {
        {
            name = "biter_revive-evolution_percent_minimum",
            type = "double-setting",
            default_value = 70,
            minimum_vale = 0,
            maximum_value = 100,
            setting_type = "runtime-global",
            order = "1001"
        },
        {
            name = "biter_revive-evolution_percent_maximum",
            type = "double-setting",
            default_value = 100,
            minimum_vale = 0,
            maximum_value = 100,
            setting_type = "runtime-global",
            order = "1002"
        },
        {
            name = "biter_revive-chance_base_percent",
            type = "double-setting",
            default_value = 5,
            minimum_vale = 0,
            maximum_value = 100,
            setting_type = "runtime-global",
            order = "1003"
        },
        {
            name = "biter_revive-chance_percent_per_evolution_percent",
            type = "double-setting",
            default_value = 0.5,
            minimum_vale = 0,
            maximum_value = 100,
            setting_type = "runtime-global",
            order = "1004"
        },
        {
            name = "biter_revive-chance_formula",
            type = "string-setting",
            default_value = "",
            setting_type = "runtime-global",
            order = "1005"
        },
        {
            name = "biter_revive-delay_seconds_minimum",
            type = "int-setting",
            default_value = 0,
            minimum_vale = 0,
            setting_type = "runtime-global",
            order = "1006"
        },
        {
            name = "biter_revive-delay_seconds_maximum",
            type = "int-setting",
            default_value = 10,
            minimum_vale = 0,
            setting_type = "runtime-global",
            order = "1007"
        },
        {
            name = "biter_revive-revives_per_second",
            type = "int-setting",
            default_value = 50,
            minimum_vale = 0,
            setting_type = "runtime-global",
            order = "1008"
        },
        {
            name = "biter_revive-blacklisted_prototype_names",
            type = "string-setting",
            default_value = "",
            setting_type = "runtime-global",
            order = "2001"
        },
        {
            name = "biter_revive-blacklisted_force_names",
            type = "string-setting",
            default_value = "",
            setting_type = "runtime-global",
            order = "2002"
        }
    }
)
