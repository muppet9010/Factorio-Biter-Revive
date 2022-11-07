local BiterRevive = require("biter-revive")

local function CreateGlobals()
    BiterRevive.CreateGlobals()
end

local function OnLoad()
    remote.remove_interface("biter_revive")
    remote.add_interface("biter_revive", {
        add_modifier = BiterRevive.AddModifier_Remote,
        get_biter_will_be_revived_event_id = BiterRevive.GetBiterWillBeRevivedEventId_Remote,
        get_biter_wont_be_revived_event_id = BiterRevive.GetBiterWontBeRevivedEventId_Remote,
        get_biter_revive_failed_event_id = BiterRevive.GetBiterReviveFailedEventId_Remote,
        get_biter_revive_success_event_id = BiterRevive.GetBiterReviveSuccessEventId_Remote,
        get_worm_revive_setting_changed_event_id = BiterRevive.GetWormReviveSettingChangedEventId_Remote
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
