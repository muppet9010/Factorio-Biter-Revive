local BiterRevive = require("biter-revive")

local function CreateGlobals()
    BiterRevive.CreateGlobals()
end

local function OnLoad()
    --Any Remote Interface registration calls can go in here or in root of control.lua
    BiterRevive.OnLoad()
end

---@param event on_runtime_mod_setting_changed|null
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
