local BiterRevive = require("biter-revive")

local function CreateGlobals()
    BiterRevive.CreateGlobals()
end

local function OnLoad()
    remote.remove_interface("biter_revive")
    remote.add_interface("biter_revive", {
        add_modifier = BiterRevive.AddModifier_Remote,
    })

    BiterRevive.OnLoad()
end

---@param event on_runtime_mod_setting_changed|nil
local function OnSettingChanged(event)
    BiterRevive.OnSettingChanged(event)
end

local function OnStartup()
    CreateGlobals()
    OnLoad()
    OnSettingChanged(nil)

    BiterRevive.OnStartup()
end

script.on_init(OnStartup)
script.on_configuration_changed(OnStartup)
script.on_event(defines.events.on_runtime_mod_setting_changed, OnSettingChanged)
script.on_load(OnLoad)
