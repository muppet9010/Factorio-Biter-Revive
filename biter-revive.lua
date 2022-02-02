local BiterRevive = {}
local Events = require("utility/events")
local Utils = require("utility/utils")
local Colors = require("utility/colors")
local Commands = require("utility/commands")

local UnitsIgnored = {character = "character", compilatron = "compilatron"}
local DelayGroupingTicks = 15 -- How many ticks between each goup of biters to revive.
local ForceEvoCacheTicks = 60 -- How long to cache a forces evo for before it is refreshed on next dead unit.

local Command_Attributes = {
    duration = "duration",
    settings = "settings",
    priority = "priority"
}
local Command_Priority = {
    enforced = "enforced",
    base = "base",
    add = "add"
}
local Command_SettingNames = {
    evoMin = "evoMin",
    evoMax = "evoMax",
    chanceBase = "chanceBase",
    chancePerEvo = "chancePerEvo",
    chanceFormula = "chanceFormula",
    delayMin = "delayMin",
    delayMax = "delayMax"
}

---@class ReviveQueueTickObject
---@field prototypeName string
---@field orientation RealOrientation
---@field force LuaForce
---@field surface LuaSurface
---@field position Position
---@field unitNumber UnitNumber -- Used to track the number of times the same unit is revived. -- TODO: needs logic adding for using this.
---@field corpses LuaEntity[] -- TODO: get from a seperate on_post_entity_died event using the unit number to match up.

---@class ForceReviveChanceObject
---@field reviveChance double @ Number between 0 and 1.
---@field oldEvolution double @ Number between 0 and 1.
---@field lastCheckedTick Tick
---@field force LuaForce
---@field forceId uint

BiterRevive.CreateGlobals = function()
    global.reviveQueue = global.reviveQueue or {} ---@type table<Tick, ReviveQueueTickObject[]> @ This will be a sparse table at both the Tick key level and in the array of ReviveQueueTickObjects once they start to be processed.
    global.forcesReviveChance = global.forcesReviveChance or {} ---@type table<Id, ForceReviveChanceObject> @ A table of force indexes and their revival chance data.

    global.evolutionRequirementMin = global.evolutionRequirementMin or 0 ---@type double @ Range of 0 to 1.
    global.evolutionRequirementMax = global.evolutionRequirementMax or 0 ---@type double @ Range of 0 to 1.
    global.reviveChanceBaseValue = global.reviveChanceBaseValue or 0 ---@type double @ Range of 0 to 1.
    global.reviveChancePerEvoPercentFormula = global.reviveChancePerEvoPercentFormula or "" ---@type string
    global.reviveChancePerEvoNumber = global.reviveChancePerEvoPercentNumber or 0 ---@type double @ Range of 0 to 1.
    global.reviveDelayMin = global.reviveDelayMin or 0 ---@type Tick
    global.reviveDelayMax = global.reviveDelayMax or 0 ---@type Tick

    global.modSettings_evolutionRequirementMin = global.modSettings_evolutionRequirementMin or 0 ---@type double @ Range of 0 to 1.
    global.modSettings_evolutionRequirementMax = global.modSettings_evolutionRequirementMax or 0 ---@type double @ Range of 0 to 1.
    global.modSettings_reviveChanceBaseValue = global.modSettings_reviveChanceBaseValue or 0 ---@type double @ Range of 0 to 1.
    global.modSettings_reviveChancePerEvoPercentFormula = global.modSettings_reviveChancePerEvoPercentFormula or "" ---@type string @ expects evolution to be provided as a "evo" variable with number equivilent of the evolution % above min revive evo. i.e. value of 2 for 2%.
    global.modSettings_reviveChancePerEvoNumber = global.modSettings_reviveChancePerEvoPercentNumber or 0 ---@type double @ Range of 0 to 1.
    global.modSettings_reviveDelayMin = global.modSettings_reviveDelayMin or 0 ---@type Tick
    global.modSettings_reviveDelayMax = global.modSettings_reviveDelayMax or 0 ---@type Tick

    global.blacklistedPrototypeNames = global.blacklistedPrototypeNames or {} ---@type table<string, True> @ The key and value are both the blacklisted prototype name.
    global.raw_BlacklistedPrototypeNames = global.raw_BlacklistedPrototypeNames or "" ---@type string @ The raw setting value.
    global.blacklisedForceIds = global.blacklisedForceIds or {} ---@type table<Id, True> @ The force Id as key, with the force name we match against the setting on as the value.
    global.raw_BlacklistedForceNames = global.raw_BlacklistedForceNames or "" ---@type string @ The raw setting value.

    global.revivesPerCycle = global.revivesPerCycle or 0 --- How many revives can be done per cycle. Every cycle in each second apart from the one excatly at the start of the second.
    global.revivesPerCycleOnStartOfSecond = global.revivesPerCycleOnStartOfSecond or 0 --- How many revives can be done on the cycle at the start of the second. This makes up for any odd dividing issues with the player setting being revives per second.
end

BiterRevive.OnStartup = function()
end

BiterRevive.OnLoad = function()
    Events.RegisterHandlerEvent(defines.events.on_entity_died, "BiterRevive.OnEntityDied", BiterRevive.OnEntityDied, {{filter = "type", type = "unit"}})
    script.on_nth_tick(DelayGroupingTicks, BiterRevive.ProcessQueue)
    Events.RegisterHandlerEvent(defines.events.on_forces_merged, "BiterRevive.OnForcesMerged", BiterRevive.OnForcesMerged)
    Events.RegisterHandlerEvent(defines.events.on_surface_deleted, "BiterRevive.OnSurfaceRemoved", BiterRevive.OnSurfaceRemoved)
    Events.RegisterHandlerEvent(defines.events.on_surface_cleared, "BiterRevive.OnSurfaceRemoved", BiterRevive.OnSurfaceRemoved)
    Commands.Register("biter_revive_add_modifier", {"command.biter_revive_add_modifier"}, BiterRevive.OnCommand_AddModifier, true)
end

---@param event on_runtime_mod_setting_changed|null
BiterRevive.OnSettingChanged = function(event)
    -- Event is nil when this is called from OnStartup for a new game or a mod change. In this case we update all settings.

    -- TODO: no need to cache setting values themselves, just run the function to work out the current value as if RCON has over ruled the value that is what goes in to global until RCON command expires and then that will trigger its own update to globals.

    -- These settings need processing to establish the current value as RCON commands can affect the final value in global.
    if event == nil or event.setting == "biter_revive-evolution_percent_minimum" then
        local settingValue = settings.global["biter_revive-evolution_percent_minimum"].value
        global.modSettings_evolutionRequirementMin = settingValue / 100
        BiterRevive.CalculateCurrentEvolutionMinimum()
    end
    if event == nil or event.setting == "biter_revive-evolution_percent_maximum" then
        local settingValue = settings.global["biter_revive-evolution_percent_maximum"].value
        global.modSettings_evolutionRequirementMax = settingValue / 100
        BiterRevive.CalculateCurrentEvolutionMaximum()
    end
    if event == nil or event.setting == "biter_revive-chance_base_percent" then
        local settingValue = settings.global["biter_revive-chance_base_percent"].value
        global.modSettings_reviveChanceBaseValue = settingValue / 100
        BiterRevive.CalculateCurrentChanceBase()
    end
    if event == nil or event.setting == "biter_revive-chance_percent_per_evolution_percent" then
        local settingValue = settings.global["biter_revive-chance_percent_per_evolution_percent"].value
        global.modSettings_reviveChancePerEvoPercentNumber = settingValue / 100
        BiterRevive.CalculateCurrentChancePerEvolution()
    end
    if event == nil or event.setting == "biter_revive-chance_formula" then
        local settingValue = settings.global["biter_revive-chance_formula"].value
        -- Check the formula and handle it specially.
        if settingValue ~= "" then
            -- Formula provided so needs checking.
            local validatedFormulaString = BiterRevive.GetValdiatedFormulaString(settingValue)
            if validatedFormulaString ~= "" then
                -- Formula is good to use.
                global.modSettings_reviveChancePerEvoPercentFormula = validatedFormulaString
            else
                -- Formula is bad.
                game.print("Biter Revive - Invalid revive chance formula provided in mod settings.", Colors.Red)
                global.modSettings_reviveChancePerEvoPercentFormula = ""
            end
        else
            -- No formula provided.
            global.modSettings_reviveChancePerEvoPercentFormula = ""
        end
        BiterRevive.CalculateCurrentChanceFormula()
    end
    if event == nil or event.setting == "biter_revive-delay_seconds_minimum" then
        local settingValue = settings.global["biter_revive-delay_seconds_minimum"].value
        global.modSettings_reviveDelayMin = settingValue * 60
        BiterRevive.CalculateCurrentDelayMinimum()
    end
    if event == nil or event.setting == "biter_revive-delay_seconds_maximum" then
        local settingValue = settings.global["biter_revive-delay_seconds_maximum"].value
        global.modSettings_reviveDelayMax = settingValue * 60
        BiterRevive.CalculateCurrentDelayMaximum()
    end

    -- These settings just need caching as can't be overridden by RCON command.
    if event == nil or event.setting == "biter_revive-revives_per_second" then
        local settingValue = settings.global["biter_revive-revives_per_second"].value
        global.revivesPerCycle = math.floor(settingValue / DelayGroupingTicks)
        global.revivesPerCycleOnStartOfSecond = math.floor(settingValue / DelayGroupingTicks) + settingValue % DelayGroupingTicks
    -- Nothing needs processing for this.
    end
    if event == nil or event.setting == "biter_revive-blacklisted_prototype_names" then
        local settingValue = settings.global["biter_revive-blacklisted_prototype_names"].value

        -- Check if was populated before as if not changed from before we don't want to confirm no change.
        local changed = settingValue == global.raw_BlacklistedPrototypeNames
        global.raw_BlacklistedPrototypeNames = settingValue

        global.blacklistedPrototypeNames = Utils.SplitStringOnCharacters(settingValue, ",", true)

        -- Only notify about the change if the setting was changed
        if changed then
            game.print("Biter Revive - Blacklisted prototype names changed to: " .. Utils.TableKeyToNumberedListString(global.blacklistedPrototypeNames))
        end
    end
    if event == nil or event.setting == "biter_revive-blacklisted_force_names" then
        local settingValue = settings.global["biter_revive-blacklisted_force_names"].value

        -- Check if was populated before as if not changed from before we don't want to confirm no change.
        local changed = settingValue == global.raw_BlacklistedForceNames
        global.raw_BlacklistedForceNames = settingValue

        local forceNames = Utils.SplitStringOnCharacters(settingValue, ",")
        -- Blank the global before adding the new ones every time.
        global.blacklisedForceIds = {}
        -- Only add valid force Id's to the global.
        for forceName in pairs(forceNames) do
            local force = game.forces[forceName]
            if force ~= nil then
                table.insert(global.blacklisedForceIds, force.index)
            else
                game.print("Biter Revive - Invalid force name provided: " .. forceName, Colors.Red)
            end
        end

        -- Only notify about the change if the setting was changed
        if changed then
            game.print("Biter Revive - Blacklisted force Ids changed to: " .. Utils.TableKeyToNumberedListString(global.blacklisedForceIds))
        end
    end
end

--- When a monitored entity type has died review it and if approperiate add it to the revive queue.
---@param event on_entity_died
BiterRevive.OnEntityDied = function(event)
    -- Current ly only even so filtered to "type = unit" and entity will always be valid as nothing within the mod can invalid it.
    local entity = event.entity
    if not entity.has_flag("breaths-air") then
        return
    end

    local entity_name = entity.name
    if UnitsIgnored[entity_name] ~= nil or global.blacklistedPrototypeNames[entity_name] ~= nil then
        return
    end

    local unitsForce = entity.force
    local unitsForce_index = unitsForce.index

    if global.blacklisedForceIds[unitsForce_index] ~= nil then
        return
    end

    -- Get the revive chance data and update it if its too old. Cache valid for 1 minute. This data will be instantly replaced by RCON commands, but they will be rare compared to needing to track forces evo changes over time.
    local forceReviveChanceObject = global.forcesReviveChance[unitsForce_index]
    if forceReviveChanceObject == nil then
        -- Create the biter force as it doesn't exist. The negative lastCheckedTick will ensure it is updated on first use,
        global.forcesReviveChance[unitsForce_index] = {force = unitsForce, forceId = unitsForce_index, lastCheckedTick = -200, oldEvolution = nil, reviveChance = nil}
        forceReviveChanceObject = global.forcesReviveChance[unitsForce_index]
    end
    if forceReviveChanceObject.lastCheckedTick < event.tick - ForceEvoCacheTicks then
        BiterRevive.UpdateForceData(forceReviveChanceObject, event.tick)
    end

    -- Random chance of entity being revived.
    if forceReviveChanceObject.reviveChance == 0 then
        -- No chance so just abort.
        return
    end
    if math.random() > forceReviveChanceObject.reviveChance then
        -- Failed random so abort.
        return
    end

    -- Make the details object to be queued.
    ---@type ReviveQueueTickObject
    local reviveDetails = {
        prototypeName = entity_name,
        orientation = entity.orientation,
        force = unitsForce,
        forceId = unitsForce_index,
        surface = entity.surface,
        position = entity.position,
        unitNumber = entity.unit_number,
        corpses = nil -- Populated by a later event.
    }

    -- Work out how much delay this will have and what grouping tick it should go in to.
    local delay = math.random(global.reviveDelayMin, global.reviveDelayMax)
    local delayGroupingTick = (math.floor(event.tick / DelayGroupingTicks) + 1 + delay) * DelayGroupingTicks -- At a minimum this will be the next grouping if the delayGrouping is 0.

    -- Add to queue in the correct grouping tick
    local tickQueue = global.reviveQueue[delayGroupingTick]
    if tickQueue == nil then
        global.reviveQueue[delayGroupingTick] = {}
        tickQueue = global.reviveQueue[delayGroupingTick]
    end
    table.insert(tickQueue, reviveDetails)
end

--- Update the reviveChacneObject as required. Always updates the lastCheckedTick when run.
---@param forceReviveChanceObject ForceReviveChanceObject
---@param currentTick Tick
BiterRevive.UpdateForceData = function(forceReviveChanceObject, currentTick)
    local currentForceEvo = forceReviveChanceObject.force.evolution_factor
    if currentForceEvo ~= forceReviveChanceObject.oldEvolution then
        -- Evolution has changed so update the chance data.
        if currentForceEvo >= global.evolutionRequirementMin then
            -- Current evo is >= min required so work out approperaite revive chance.
            local forceEvoAboveMin = currentForceEvo - global.evolutionRequirementMin

            local chanceForEvo

            -- If the chance per evo formula is blank then use the number setting, otherwise we use the formula.
            if global.reviveChancePerEvoPercentFormula ~= "" then
                -- Formula is blank so use the number
                chanceForEvo = forceEvoAboveMin * global.reviveChancePerEvoNumber
            else
                -- Try and apply the current formula to the evo.
                local success
                success, chanceForEvo =
                    pcall(
                    function()
                        return load("local evo = " .. forceEvoAboveMin .. "; return " .. global.reviveChancePerEvoPercentFormula)()
                    end
                )

                if not success then
                    game.print("Revive chance formula failed when being applied with 'evo' value of: " .. forceEvoAboveMin)
                    chanceForEvo = 0
                end
            end

            -- Check the value isn't a NaN.
            if chanceForEvo ~= chanceForEvo then
                -- reviveChance is NaN so set it to 0.
                game.print("Revive chance result ended up as invalid number, error in mod setting value. The 'evo' above minimum was: " .. forceEvoAboveMin)
                chanceForEvo = 0
            end

            -- Current chance is the min chance plus the proportional chance from evo scale.
            local reviveChance = global.reviveChanceBaseValue + chanceForEvo
            -- Clamp the chance result between 0 and 1.
            forceReviveChanceObject.reviveChance = math.min(math.max(reviveChance, 0), 1)
        else
            -- Below min so no chance
            forceReviveChanceObject.reviveChance = 0
        end
    end
    forceReviveChanceObject.lastCheckedTick = currentTick
end

--- Process any current queue of biter revives. Called once every DelayGroupingTicks ticks.
---@param event NthTickEventData
BiterRevive.ProcessQueue = function(event)
    -- If nothing to do just abort.
    if next(global.reviveQueue) == nil then
        return
    end

    -- Make sure over a second we do a max of the exact number of revivies per second setting regardless of how many cycles we devide it in to.
    local revivesRemainingThisCycle
    if event.tick % 60 == 0 then
        revivesRemainingThisCycle = global.revivesPerCycleOnStartOfSecond
    else
        revivesRemainingThisCycle = global.revivesPerCycle
    end

    -- Start at the beginning (oldest) of the queued revive Ticks and work forwards until we reach a future tick from now, or we do our max revives this cycle.
    local spawnPosition
    for tick, reviveQueueTickObjects in pairs(global.reviveQueue) do
        if tick > event.tick then
            -- Done all we should so stop.
            return
        end

        for reviveIndex, reviveDetails in pairs(reviveQueueTickObjects) do
            -- We handle surface's being deleted and forces merged via events so no need to check them per execution here.

            -- Do the actual revive asuming a suitable position is found.
            spawnPosition = reviveDetails.surface.find_non_colliding_position(reviveDetails.prototypeName, reviveDetails.position, 5, 0.1)
            if spawnPosition ~= nil then
                reviveDetails.surface.create_entity {
                    name = reviveDetails.prototypeName,
                    position = spawnPosition,
                    force = reviveDetails.force,
                    orientation = reviveDetails.orientation,
                    create_build_effect_smoke = false,
                    raise_built = true
                }

                -- Remove any corpses as the unit isn't dead any more.
                if reviveDetails.corpses ~= nil then
                    for _, corpse in pairs(reviveDetails.corpses) do
                        corpse.destroy {raise_destroy = true}
                    end
                end
            end

            -- Remove this revive from the current tick as done.
            reviveQueueTickObjects[reviveIndex] = nil

            -- Count our revive and stop processing if we have done our number for this cycle.
            revivesRemainingThisCycle = revivesRemainingThisCycle - 1
            if revivesRemainingThisCycle == 0 then
                return
            end
        end

        -- If reached here then this tick's revives are all complete so remove it.
        global.reviveQueue[tick] = nil
    end
end

--- Called when forces are merged and we need to update any scheduled revives of the removed force.
---@param event on_forces_merged
BiterRevive.OnForcesMerged = function(event)
    local destination_index = event.destination.index
    for _, tickRevives in pairs(global.reviveQueue) do
        for _, reviveDetails in pairs(tickRevives) do
            if reviveDetails.forceId == event.source_index then
                -- This revive was for the removed force, so set them to the new force.
                reviveDetails.forceId = destination_index
                reviveDetails.force = event.destination
            end
        end
    end
end

--- Called when a surface is removed or cleared and we need to remove any scheduled revives on that surface.
---@param event on_surface_cleared|on_surface_deleted
BiterRevive.OnSurfaceRemoved = function(event)
    for _, tickRevives in pairs(global.reviveQueue) do
        for reviveIndex, reviveDetails in pairs(tickRevives) do
            if reviveDetails.surface.index == event.surface_index then
                tickRevives[reviveIndex] = nil
            end
        end
    end
end

--- Checks a forumla string handles an evo value of 10% (10). If it does returns the formula string, otherwise returns a blank string.
---@param formulaStringToTest string
---@return string validatedFormulaString
BiterRevive.GetValdiatedFormulaString = function(formulaStringToTest)
    local success =
        pcall(
        function()
            return load("local evo = 10; return " .. formulaStringToTest)()
        end
    )
    if success then
        return formulaStringToTest
    else
        return ""
    end
end

-- TODO: updating the global values when mod settings are changed or RCON commands recieved.
BiterRevive.CalculateCurrentEvolutionMinimum = function()
end
BiterRevive.CalculateCurrentEvolutionMaximum = function()
end
BiterRevive.CalculateCurrentChanceBase = function()
end
BiterRevive.CalculateCurrentChancePerEvolution = function()
end
BiterRevive.CalculateCurrentChanceFormula = function()
end
BiterRevive.CalculateCurrentDelayMinimum = function()
end
BiterRevive.CalculateCurrentDelayMaximum = function()
end

--- Handler of the RCON command "biter_revive_add_modifier".
---@param command CustomCommandData
BiterRevive.OnCommand_AddModifier = function(command)
    local args = Commands.GetArgumentsFromCommand(command.parameter)
    local errorMessageStart = "Biter Revive - command biter_revive_add_modifier "

    -- Check the top level JSON object table.
    local data = args[1]
    if not Commands.ParseTableArgument(data, true, command.name, "Json object", Command_Attributes) then
        return
    end

    -- Check the main attributes of the object.
    local duration = data.duration
    if not Commands.ParseNumberArgument(duration, "integer", true, command.name, "duration", 0) then
        return
    end

    local priority = data.priority
    if not Commands.ParseStringArgument(priority, true, command.name, "priority", Command_Priority) then
        return
    end

    local settings = data.settings
    if not Commands.ParseTableArgument(settings, true, command.name, settings, Command_SettingNames) then
        return
    end

    -- Check the settings specific fields in the object. Note that none of the settings force value ranges.
    local evoMin = settings.evoMin
    if not Commands.ParseNumberArgument(evoMin, "integer", false, command.name, "evoMin") then
        return
    end

    local evoMax = settings.evoMax
    if not Commands.ParseNumberArgument(evoMax, "integer", false, command.name, "evoMax") then
        return
    end

    local chanceBase = settings.chanceBase
    if not Commands.ParseNumberArgument(chanceBase, "integer", false, command.name, "chanceBase") then
        return
    end

    local chancePerEvo = settings.chancePerEvo
    if not Commands.ParseNumberArgument(chancePerEvo, "integer", false, command.name, "chancePerEvo") then
        return
    end

    local chanceFormula = settings.chanceFormula
    if not Commands.ParseStringArgument(chanceFormula, "string", false, command.name, "chanceFormula") then
        return
    end

    local delayMin = settings.delayMin
    if not Commands.ParseNumberArgument(delayMin, "integer", false, command.name, "delayMin") then
        return
    end

    local delayMax = settings.delayMax
    if not Commands.ParseNumberArgument(delayMax, "integer", false, command.name, "delayMax") then
        return
    end

    -- Check that one or more settings where included, otherwise the command will do nothing.
    if evoMin == nil and evoMax == nil and chanceBase == nil and chancePerEvo == nil and chanceFormula == nil and delayMin == nil and delayMax == nil then
        game.print(errorMessageStart .. "no actual setting was included within the settings table.")
        return
    end

    -- TODO: add comamnd results in to commands table
    -- TODO: schedule removal from commands table at duration.
    -- TODO: force update of current runtime values.
end

return BiterRevive
