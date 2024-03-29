-- Settings that have RCON commands.
data:extend(
    {
        {
            name = "biter_revive-evolution_percent_minimum",
            type = "double-setting",
            default_value = 50,
            minimum_value = 0,
            maximum_value = 100,
            setting_type = "runtime-global",
            order = "1001"
        },
        {
            name = "biter_revive-evolution_percent_maximum",
            type = "double-setting",
            default_value = 100,
            minimum_value = 0,
            maximum_value = 100,
            setting_type = "runtime-global",
            order = "1002"
        },
        {
            name = "biter_revive-chance_base_percent",
            type = "double-setting",
            default_value = 5,
            minimum_value = 0,
            maximum_value = 100,
            setting_type = "runtime-global",
            order = "1003"
        },
        {
            name = "biter_revive-chance_percent_per_evolution_percent",
            type = "double-setting",
            default_value = 0.5,
            minimum_value = 0,
            maximum_value = 100,
            setting_type = "runtime-global",
            order = "1004"
        },
        {
            name = "biter_revive-chance_formula",
            type = "string-setting",
            allow_blank = true,
            default_value = "",
            setting_type = "runtime-global",
            order = "1005"
        },
        {
            name = "biter_revive-delay_seconds_minimum",
            type = "int-setting",
            default_value = 2,
            minimum_value = 0,
            setting_type = "runtime-global",
            order = "1006"
        },
        {
            name = "biter_revive-delay_seconds_maximum",
            type = "int-setting",
            default_value = 5,
            minimum_value = 0,
            setting_type = "runtime-global",
            order = "1007"
        },
        {
            name = "biter_revive-delay_text",
            type = "string-setting",
            allow_blank = true,
            default_value = "zzz, snore",
            setting_type = "runtime-global",
            order = "1008"
        },
        {
            name = "biter_revive-maximum_revives_per_unit",
            type = "int-setting",
            default_value = 0,
            minimum_value = 0,
            setting_type = "runtime-global",
            order = "1009"
        }
    }
)

-- Settings without RCON commands.
data:extend(
    {
        {
            name = "biter_revive-revives_per_second",
            type = "int-setting",
            default_value = 50,
            minimum_value = 0,
            setting_type = "runtime-global",
            order = "2000"
        },
        {
            name = "biter_revive-include_biological_turrets",
            type = "bool-setting",
            default_value = false,
            setting_type = "runtime-global",
            order = "2001"
        },
        {
            name = "biter_revive-blacklisted_prototype_names",
            type = "string-setting",
            allow_blank = true,
            default_value = "compilatron",
            setting_type = "runtime-global",
            order = "2002"
        },
        {
            name = "biter_revive-blacklisted_force_names",
            type = "string-setting",
            allow_blank = true,
            default_value = "player",
            setting_type = "runtime-global",
            order = "2003"
        }
    }
)
