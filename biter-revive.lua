local BiterRevive = {}
local Utils = require("utility/utils")
local Colors = require("utility/colors")
local Commands = require("utility/commands")
local math_min, math_max, math_floor, math_random = math.min, math.max, math.floor, math.random

local DelayGroupingTicks = 15 -- How many ticks between each goup of biters to revive.
local ForceEvoCacheTicks = 600 -- How long to cache a forces evo for before it is refreshed on next dead unit. Currently 10 seconds as a balance between proper caching and reacting to a sudden evolution jump from a modded/scripted event.

local CommandAttributes = {
    duration = "duration",
    settings = "settings",
    priority = "priority"
}
---@class CommandPriority
local CommandPriority = {
    enforced = "enforced",
    base = "base",
    add = "add"
}
---@class CommandPriorityOrderedIndex @ Lower is better.
local CommandPriorityOrderedIndex = {
    enforced = 1,
    base = 2,
    modSetting = 3,
    add = 4
}
---@class CommandSettingNames
local CommandSettingNames = {
    evoMin = "evoMin",
    evoMax = "evoMax",
    chanceBase = "chanceBase",
    chancePerEvo = "chancePerEvo",
    chanceFormula = "chanceFormula",
    delayMin = "delayMin",
    delayMax = "delayMax",
    delayText = "delayText",
    maxRevives = "maxRevives"
}

---@class ReviveQueueTickObject
---@field unitNumber UnitNumber
---@field prototypeName string
---@field orientation RealOrientation
---@field force LuaForce
---@field surface LuaSurface
---@field position Position
---@field previousRevives uint
---@field corpses LuaEntity[]

---@class ForceReviveChanceObject
---@field reviveChance double @ Number between 0 and 1.
---@field lastCheckedTick Tick
---@field force LuaForce
---@field forceId uint

---@class CommandDetails
---@field id uint
---@field duration Tick
---@field removalTick Tick
---@field priority CommandPriority
---@field evoMin double @ Range of 0 to 1.
---@field evoMax double @ Range of 0 to 1.
---@field chanceBase double @ Range of 0 to 1.
---@field chancePerEvo double @ Range of 0 to 100.
---@field chanceFormula string
---@field delayMin Tick @ Range of >= 0.
---@field delayMax Tick @ Range of >= 0.
---@field delayText string @ nil or comma seperated string.
---@field maxRevives uint

BiterRevive.CreateGlobals = function()
    global.reviveQueue = global.reviveQueue or {} ---@type table<Tick, ReviveQueueTickObject[]> @ This will be a sparse table at both the Tick key level and in the array of ReviveQueueTickObjects once they start to be processed.
    global.reviveDetailsByUnitNumber = global.reviveDetailsByUnitNumber or {} ---@type table<UnitNumber, ReviveQueueTickObject> @ A queued revive details object referenced by its unit number.
    global.reviveQueueNextTickToProcess = global.reviveQueueNextTickToProcess or 0 ---@type Tick @ The next tick in the queue that will be processed.
    global.unitReviveCount = global.unitReviveCount or {} ---@type table<UnitNumber, uint> @ A table of the revived unit number and the number of previous revives its had.
    global.forcesReviveChance = global.forcesReviveChance or {} ---@type table<Id, ForceReviveChanceObject> @ A table of force indexes and their revival chance data.

    global.commands = global.commands or {} ---@type table<Id, CommandDetails>
    global.commandsNextId = global.commandsNextId or 0 ---@type uint
    global.nextCommandExpireTick = global.nextCommandExpireTick or 0 ---@type Tick @ Resets to 0 if no next expiring command.

    global.evolutionRequirementMin = global.evolutionRequirementMin or 0 ---@type double @ Range of 0 to 1.
    global.evolutionRequirementMax = global.evolutionRequirementMax or 0 ---@type double @ Range of 0 to 1.
    global.reviveChanceBaseValue = global.reviveChanceBaseValue or 0 ---@type double @ Range of 0 to 1.
    global.reviveChancePerEvoPercentFormula = global.reviveChancePerEvoPercentFormula or "" ---@type string @ expects evolution to be provided as a "evo" variable with number equivilent of the evolution % above min revive evo. i.e. value of 2 for 2%. Defaults to "" rather than nil.
    global.reviveChancePerEvoNumber = global.reviveChancePerEvoNumber or 0 ---@type double @ Range of 0 to 100.
    global.reviveDelayMin = global.reviveDelayMin or 0 ---@type Tick @ Range of >= 0.
    global.reviveDelayMax = global.reviveDelayMax or 0 ---@type Tick @ Range of >= 0.
    global.reviveDelayTexts = global.reviveDelayTexts or {} ---@type string[] @ An empty table if none.
    global.maxRevivesPerUnit = global.maxRevivesPerUnit or 0 ---@type uint @ 0 is infinite.

    global.modSettings_evolutionRequirementMin = global.modSettings_evolutionRequirementMin or 0 ---@type double @ Range of 0 to 1.
    global.modSettings_evolutionRequirementMax = global.modSettings_evolutionRequirementMax or 0 ---@type double @ Range of 0 to 1.
    global.modSettings_reviveChanceBaseValue = global.modSettings_reviveChanceBaseValue or 0 ---@type double @ Range of 0 to 1.
    global.modSettings_reviveChancePerEvoPercentFormula = global.modSettings_reviveChancePerEvoPercentFormula or "" ---@type string @ expects evolution to be provided as a "evo" variable with number equivilent of the evolution % above min revive evo. i.e. value of 2 for 2%. Defaults to "" rather than nil.
    global.modSettings_reviveChancePerEvo = global.modSettings_reviveChancePerEvo or 0 ---@type double @ Range of 0 to 100.
    global.modSettings_reviveDelayMin = global.modSettings_reviveDelayMin or 0 ---@type Tick @ Range of >= 0.
    global.modSettings_reviveDelayMax = global.modSettings_reviveDelayMax or 0 ---@type Tick @ Range of >= 0.
    global.modSettings_reviveDelayText = global.modSettings_reviveDelayText or "" ---@type string @ A blank string is none or a comma seperated string.
    global.modSettings_maxRevivesPerUnit = global.modSettings_maxRevivesPerUnit or 0 ---@type uint

    global.blacklistedPrototypeNames = global.blacklistedPrototypeNames or {} ---@type table<string, True> @ The key is blacklisted prototype name, with a value of true.
    global.raw_BlacklistedPrototypeNames = global.raw_BlacklistedPrototypeNames or "" ---@type string @ The raw setting value.
    global.blacklisedForceIds = global.blacklisedForceIds or {} ---@type table<Id, True> @ The force Id as key, with the force name we match against the setting on as the value.
    global.raw_BlacklistedForceNames = global.raw_BlacklistedForceNames or "" ---@type string @ The raw setting value.

    global.revivesPerCycle = global.revivesPerCycle or 0 --- How many revives can be done per cycle. Every cycle in each second apart from the one excatly at the start of the second.
    global.revivesPerCycleOnStartOfSecond = global.revivesPerCycleOnStartOfSecond or 0 --- How many revives can be done on the cycle at the start of the second. This makes up for any odd dividing issues with the player setting being revives per second.

    global.zeroTickErrors = global.zeroTickErrors or {} ---@type string[] @ Any errors raised during map startup (0 tick). They will be printed again on first non 0 tick cycle biter check cycle.
end

BiterRevive.OnStartup = function()
    -- Special to print any startup setting error messages after tick 0. Only needed if its tick 0 now.
    if game.tick == 0 then
        script.on_nth_tick(
            2,
            function(event)
                -- If its still tick 0 wait for later.
                if event.tick == 0 then
                    return
                end

                -- Print any errors and then remove them.
                for _, errorMessage in pairs(global.zeroTickErrors) do
                    game.print(errorMessage, Colors.lightred)
                end
                global.zeroTickErrors = {}

                -- Deregister this event as never needed again.
                script.on_nth_tick(2, nil)
            end
        )
    end
end

BiterRevive.OnLoad = function()
    -- Don't use Event libraries as simple usage case and not needed overheads in profiler.
    script.on_nth_tick(DelayGroupingTicks, BiterRevive.ProcessTasks)
    script.on_event(defines.events.on_entity_died, BiterRevive.OnEntityDied, {{filter = "type", type = "unit"}})
    script.on_event(defines.events.on_post_entity_died, BiterRevive.OnPostEntityDied, {{filter = "type", type = "unit"}})
    script.on_event(defines.events.on_forces_merged, BiterRevive.OnForcesMerged)
    script.on_event(defines.events.on_surface_deleted, BiterRevive.OnSurfaceRemoved)
    script.on_event(defines.events.on_surface_cleared, BiterRevive.OnSurfaceRemoved)
    Commands.Register("biter_revive_add_modifier", {"command.biter_revive_add_modifier"}, BiterRevive.OnCommand_AddModifier, true)
    Commands.Register("biter_revive_dump_state_data", {"command.biter_revive_dump_state_data"}, BiterRevive.OnCommand_DumptStateData, true)
end

--- When a monitored entity type has died review it and if approperiate add it to the revive queue.
---@param event on_entity_died
BiterRevive.OnEntityDied = function(event)
    -- Currently only even so filtered to "type = unit" and entity will always be valid as nothing within the mod can invalid it.
    local entity = event.entity

    -- Have to get unit_number to get any preivous revive count passed on from preivous iterations of the unit. Always clear the table entry to stop it infinitely growing. Do the clear here rather than in every return block for sanity.
    local entity_unitNumber = entity.unit_number
    local previousRevives = global.unitReviveCount[entity_unitNumber] or 0
    global.unitReviveCount[entity_unitNumber] = nil

    -- If there is a unit revive limit check if the unit has reached it.
    if global.maxRevivesPerUnit ~= 0 and previousRevives >= global.maxRevivesPerUnit then
        return
    end

    local entity_name = entity.name
    -- Check if the prototype name is blacklisted.
    if global.blacklistedPrototypeNames[entity_name] ~= nil then
        return
    end

    local unitsForce = entity.force
    local unitsForce_index = unitsForce.index
    -- Check if the force is blacklisted.
    if global.blacklisedForceIds[unitsForce_index] ~= nil then
        return
    end

    -- Get the revive chance data and update it if its too old. Cache valid for 1 minute. This data will be instantly replaced by RCON commands, but they will be rare compared to needing to track forces evo changes over time.
    local forceReviveChanceObject = global.forcesReviveChance[unitsForce_index]
    if forceReviveChanceObject == nil then
        -- Create the biter force as it doesn't exist. The large negative lastCheckedTick will ensure it is updated on first use.
        global.forcesReviveChance[unitsForce_index] = {force = unitsForce, forceId = unitsForce_index, lastCheckedTick = -9999999, reviveChance = nil}
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
    if math_random() > forceReviveChanceObject.reviveChance then
        -- Failed random so abort.
        return
    end

    -- Make the details object to be queued.
    ---@type ReviveQueueTickObject
    local reviveDetails = {
        unitNumber = entity_unitNumber,
        prototypeName = entity_name,
        orientation = entity.orientation,
        force = unitsForce,
        forceId = unitsForce_index,
        surface = entity.surface,
        position = nil, -- Populate by on_post_entity_died event as its a non API call then.
        previousRevives = previousRevives
    }

    -- Store a reference to the reviveDetails as we will add to it from another event.
    global.reviveDetailsByUnitNumber[entity_unitNumber] = reviveDetails

    -- Work out how much delay this will have and what grouping tick it should go in to.
    local delay = math_random(global.reviveDelayMin, global.reviveDelayMax)
    local delayGroupingTick = (math_floor((event.tick + delay) / DelayGroupingTicks) + 1) * DelayGroupingTicks -- At a minimum this will be the next grouping if the delayGrouping is 0.

    -- Add to queue in the correct grouping tick
    local tickQueue = global.reviveQueue[delayGroupingTick]
    if tickQueue == nil then
        global.reviveQueue[delayGroupingTick] = {}
        tickQueue = global.reviveQueue[delayGroupingTick]
    end
    table.insert(tickQueue, reviveDetails)
end

--- Called after the entity has died and the corpse is present.
---@param event on_post_entity_died
BiterRevive.OnPostEntityDied = function(event)
    -- If no revive details then this event isn't for a unit that we care about.
    local reviveDetails = global.reviveDetailsByUnitNumber[event.unit_number]
    if reviveDetails == nil then
        return
    end

    -- Populate the extra data we need from this event in to the reviveDetails.
    reviveDetails.position = event.position
    reviveDetails.corpses = event.corpses

    -- Add the delay text if approperiate. Target it at the first corpse as this is hopefully the main one so when the corpse goes the text goes with it.
    if #global.reviveDelayTexts > 0 and #reviveDetails.corpses > 0 then
        local textString = global.reviveDelayTexts[math.random(1, #global.reviveDelayTexts)]
        rendering.draw_text {
            text = textString,
            color = Colors.white,
            surface = event.surface_index,
            target = reviveDetails.corpses[1]
        }
    end

    -- Remove the revive details from its global lookup as its been handled.
    global.reviveDetailsByUnitNumber[event.unit_number] = nil
end

--- Update the reviveChanceObject as required. Always updates the lastCheckedTick when run.
---@param forceReviveChanceObject ForceReviveChanceObject
---@param currentTick Tick
BiterRevive.UpdateForceData = function(forceReviveChanceObject, currentTick)
    -- The current evo will have changed every time run so always recalculate this data.
    local currentForceEvo = forceReviveChanceObject.force.evolution_factor
    if currentForceEvo >= global.evolutionRequirementMin then
        -- Current evo is >= min required so work out approperaite revive chance.

        -- Work out how much evo is above min, up to the max setting.
        local rawForceAboveMin = currentForceEvo - global.evolutionRequirementMin
        local maxForceDifAllowed = math.max(global.evolutionRequirementMax - global.evolutionRequirementMin, 0)
        local forceEvoAboveMin = math_min(rawForceAboveMin, maxForceDifAllowed)
        local chanceForEvo

        -- If the chance per evo formula is blank then use the number setting, otherwise we use the formula.
        if global.reviveChancePerEvoPercentFormula == "" then
            -- Formula is blank so use the number
            chanceForEvo = forceEvoAboveMin * global.reviveChancePerEvoNumber
        else
            -- It expects evo to be as a percentage
            forceEvoAboveMin = forceEvoAboveMin * 100

            -- Try and apply the current formula to the evo.
            local success
            success, chanceForEvo =
                pcall(
                function()
                    return load("local evo = " .. forceEvoAboveMin .. "; return " .. global.reviveChancePerEvoPercentFormula)()
                end
            )

            if not success then
                game.print("Revive chance formula failed when being applied with 'evo' value of: " .. forceEvoAboveMin, Colors.lightred)
                chanceForEvo = 0
            end
        end

        -- Check the value isn't a NaN.
        if chanceForEvo ~= chanceForEvo then
            -- reviveChance is NaN so set it to 0.
            game.print("Revive chance result ended up as invalid number, error in mod setting value. The 'evo' above minimum was: " .. forceEvoAboveMin, Colors.lightred)
            chanceForEvo = 0
        end

        -- Current chance is the min chance plus the proportional chance from evo scale.
        local reviveChance = global.reviveChanceBaseValue + chanceForEvo
        -- Clamp the chance result between 0 and 1.
        forceReviveChanceObject.reviveChance = math_min(math_max(reviveChance, 0), 1)
    else
        -- Below min so no chance
        forceReviveChanceObject.reviveChance = 0
    end

    -- Update the last tick checked.
    forceReviveChanceObject.lastCheckedTick = currentTick
end

--- Process anything needed on the cycle. current queue of biter revives and any expiring commands. Called once every DelayGroupingTicks ticks.
---@param event NthTickEventData
BiterRevive.ProcessTasks = function(event)
    BiterRevive.CheckExpiredCommands(event)
    BiterRevive.ProcessReviveQueue(event)
end

--- Check for any expired commands and handle them. Called once every DelayGroupingTicks ticks.
---@param event NthTickEventData
BiterRevive.CheckExpiredCommands = function(event)
    if global.nextCommandExpireTick ~= 0 and event.tick >= global.nextCommandExpireTick then
        local nextCommandExpireTick = 0 ---@type Tick
        local commandDetails  ---@type CommandDetails
        local removeIndex  ---@type boolean

        -- Work through the commands lookign for any that have expired. As its a sparse array have to iterate carefully.
        local commandDetailsIndex = next(global.commands)
        while commandDetailsIndex ~= nil do
            commandDetails = global.commands[commandDetailsIndex]

            -- Identify if a command has expired and should be removed.
            if commandDetails.removalTick <= event.tick then
                removeIndex = commandDetailsIndex
            else
                removeIndex = nil
                -- If its not being removed then track the next command to be removed so we can set the global again.
                if nextCommandExpireTick == 0 or commandDetails.removalTick < nextCommandExpireTick then
                    nextCommandExpireTick = commandDetails.removalTick
                end
            end

            -- Get the next entry in the table before we do anything.
            commandDetailsIndex = next(global.commands, commandDetailsIndex)

            -- Remove an expired entry after we have got the next one to avoid nil index errors. Also update the current value post its removal.
            if removeIndex then
                global.commands[removeIndex] = nil
                BiterRevive.CallUpdateFunctionsForCommandDetails(commandDetails, event.tick)
            end
        end

        global.nextCommandExpireTick = nextCommandExpireTick
    end
end

--- Process any queued revives. Called once every DelayGroupingTicks ticks.
---@param event NthTickEventData
BiterRevive.ProcessReviveQueue = function(event)
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

    -- If very low revives per second mod setting then it can be 0 max revives in some cycles.
    if revivesRemainingThisCycle == 0 then
        return
    end

    -- Check each group's tick for any entries we need to process. In general it will just be 1 tick groups worth, but if there are more revivies than max allowed then it may have to check multiple tick groups until it has caught up.
    -- As dictionary keys aren't sorted and this is a sparse array of tick keys they won't be in sequential order when new ones are added.
    local spawnPosition, nextTickToProcess
    local reviveQueueTickObjects  ---@type ReviveQueueTickObject[]
    for groupTick = global.reviveQueueNextTickToProcess, event.tick, DelayGroupingTicks do
        reviveQueueTickObjects = global.reviveQueue[groupTick]
        if reviveQueueTickObjects ~= nil then
            for reviveIndex, reviveDetails in pairs(reviveQueueTickObjects) do
                -- We handle surface's being deleted and forces merged via events so no need to check them per execution here.
                local revivedBiter

                -- Biters don't block other biters placement locations. So only if the player builds over a reviving biter or a player blocks the placement by character or vehicle will the reivivng biter look further out to find somewhere to revive. Can't just revive the biter in position blindly as it will be created on top of the blocking entity.
                spawnPosition = reviveDetails.surface.find_non_colliding_position(reviveDetails.prototypeName, reviveDetails.position, 20, 0.1)
                -- If no spawning point is found just forget about this revive as very unlikely to happen.
                if spawnPosition ~= nil then
                    revivedBiter =
                        reviveDetails.surface.create_entity {
                        name = reviveDetails.prototypeName,
                        position = spawnPosition,
                        force = reviveDetails.force,
                        orientation = reviveDetails.orientation,
                        create_build_effect_smoke = false,
                        raise_built = true
                    }
                end

                -- If the unit was revived do some further tasks.
                if revivedBiter ~= nil then
                    -- Record the revive count for the new unit.
                    global.unitReviveCount[revivedBiter.unit_number] = reviveDetails.previousRevives + 1

                    -- Remove any corpses for the revived unit.
                    for _, corpse in pairs(reviveDetails.corpses) do
                        -- Corpse could have been removed with water fill, building, scripted, etc.
                        if corpse.valid then
                            corpse.destroy()
                        end
                    end
                end

                -- Remove this revive from the current tick as done.
                reviveQueueTickObjects[reviveIndex] = nil

                -- Count our revive and stop processing if we have done our number for this cycle.
                revivesRemainingThisCycle = revivesRemainingThisCycle - 1
                if revivesRemainingThisCycle == 0 then
                    -- Cache the current tick as last completed.
                    if #reviveQueueTickObjects == 0 then
                        -- Ths tick was actually just all done on the last allowed revived.
                        nextTickToProcess = groupTick + DelayGroupingTicks
                    else
                        -- More revivies this tick to be done, so we need to continue this tick next cycle.
                        nextTickToProcess = groupTick
                    end
                    break
                end
            end

            -- Remove the tick's queue entry if its all completed.
            if #reviveQueueTickObjects == 0 then
                global.reviveQueue[groupTick] = nil
            end

            -- If we have done all we can in this cycle then stop looking at new ticks.
            if revivesRemainingThisCycle == 0 then
                break
            end
        end
    end

    -- Record what the last competed tick was.
    if revivesRemainingThisCycle > 0 then
        -- We ran to the end of the current tick and had spare revives available
        global.reviveQueueNextTickToProcess = event.tick + DelayGroupingTicks
    else
        -- Ran out of revives mid processing the last tick so use the nextTick as worked out within the logic.
        global.reviveQueueNextTickToProcess = nextTickToProcess
    end
end

--- Called when forces are merged and we need to update all data for this.
---@param event on_forces_merged
BiterRevive.OnForcesMerged = function(event)
    local destination_index = event.destination.index

    -- Check any scheduled revives for being related to the removed force.
    for _, tickRevives in pairs(global.reviveQueue) do
        for _, reviveDetails in pairs(tickRevives) do
            if reviveDetails.forceId == event.source_index then
                -- This revive was for the removed force, so set them to the new force.
                reviveDetails.forceId = destination_index
                reviveDetails.force = event.destination
            end
        end
    end

    -- If there was a cached force chance object remove it.
    global.forcesReviveChance[event.source_index] = nil
end

--- Called when a surface is removed or cleared and we need to remove any scheduled revives on that surface and other cached data.
---@param event on_surface_cleared|on_surface_deleted
BiterRevive.OnSurfaceRemoved = function(event)
    -- Just empty the reviveQueue per tick grouping object and don't bother to remove it. As removing will be a pain with a sparse array and the processing will handle empty tick groups by default.
    for _, ticksRevives in pairs(global.reviveQueue) do
        for reviveIndex, reviveDetails in pairs(ticksRevives) do
            if not reviveDetails.surface.valid or reviveDetails.surface.index == event.surface_index then
                ticksRevives[reviveIndex] = nil
                global.reviveDetailsByUnitNumber[reviveDetails.unitNumber] = nil
                global.unitReviveCount[reviveDetails.unitNumber] = nil
            end
        end
    end
end

--- Call the approperiate update functions for the runtime globals based on which fields were included in the command details.
---@param commandDetails CommandDetails
---@param currentTick Tick
BiterRevive.CallUpdateFunctionsForCommandDetails = function(commandDetails, currentTick)
    local updateAllForceData = false

    if commandDetails.evoMin ~= nil then
        BiterRevive.CalculateCurrentEvolutionMinimum()
        updateAllForceData = true
    end
    if commandDetails.evoMax ~= nil then
        BiterRevive.CalculateCurrentEvolutionMaximum()
        updateAllForceData = true
    end
    if commandDetails.chanceBase ~= nil then
        BiterRevive.CalculateCurrentChanceBase()
        updateAllForceData = true
    end
    if commandDetails.chancePerEvo ~= nil then
        BiterRevive.CalculateCurrentChancePerEvolution()
        updateAllForceData = true
    end
    if commandDetails.chanceFormula ~= nil then
        BiterRevive.CalculateCurrentChanceFormula()
        updateAllForceData = true
    end
    if commandDetails.delayMin ~= nil then
        BiterRevive.CalculateCurrentDelayMinimum()
    end
    if commandDetails.delayMax ~= nil then
        BiterRevive.CalculateCurrentDelayMaximum()
    end
    if commandDetails.delayText ~= nil then
        BiterRevive.CalculateCurrentDelayText()
    end
    if commandDetails.maxRevives ~= nil then
        BiterRevive.CalculateCurrentMaxRevivesPerUnit()
    end

    -- Update all cached force data if its needed after settings changd.
    if updateAllForceData then
        BiterRevive.UpdateAllForcesData(currentTick)
    end
end

-- These Calculate functions aren't very effecient, but they will run very infrequently over small data sets.
BiterRevive.CalculateCurrentEvolutionMinimum = function()
    global.evolutionRequirementMin = BiterRevive.CalculateCurrentValue(CommandSettingNames.evoMin, "min", "modSettings_evolutionRequirementMin", false)
end
BiterRevive.CalculateCurrentEvolutionMaximum = function()
    global.evolutionRequirementMax = BiterRevive.CalculateCurrentValue(CommandSettingNames.evoMax, "max", "modSettings_evolutionRequirementMax", false)
end
BiterRevive.CalculateCurrentChanceBase = function()
    global.reviveChanceBaseValue = BiterRevive.CalculateCurrentValue(CommandSettingNames.chanceBase, "max", "modSettings_reviveChanceBaseValue", false)
end
BiterRevive.CalculateCurrentChancePerEvolution = function()
    global.reviveChancePerEvoNumber = BiterRevive.CalculateCurrentValue(CommandSettingNames.chancePerEvo, "max", "modSettings_reviveChancePerEvo", false)
end
BiterRevive.CalculateCurrentChanceFormula = function()
    -- Is special in that we record the first highest priority formula we find and use that.
    local currentFormula  ---@type string
    local currentFormulaPriorityOrderedIndex = 10 ---@type CommandPriorityOrderedIndex
    for _, command in pairs(global.commands) do
        -- Will be a non existant setting in the command and not an empty string like the mod setting.
        if command[CommandSettingNames.chanceFormula] ~= nil then
            local commandPriorityOrderedIndex = CommandPriorityOrderedIndex[command.priority]
            if commandPriorityOrderedIndex < currentFormulaPriorityOrderedIndex then
                currentFormula = command.chanceFormula
                currentFormulaPriorityOrderedIndex = commandPriorityOrderedIndex
                if commandPriorityOrderedIndex == 1 then
                    -- Nothing can be higher priority and we use the first one found of a priority.
                    break
                end
            end
        end
    end

    -- Check if the mod setting should set the formula over an "add" command. The mod setting is stored as an empty string and not nil as its a global.
    if currentFormulaPriorityOrderedIndex > CommandPriorityOrderedIndex.modSetting and global.modSettings_reviveChancePerEvoPercentFormula ~= "" then
        currentFormula = global.modSettings_reviveChancePerEvoPercentFormula
    end

    global.reviveChancePerEvoPercentFormula = currentFormula or ""
end
BiterRevive.CalculateCurrentDelayMinimum = function()
    global.reviveDelayMin = BiterRevive.CalculateCurrentValue(CommandSettingNames.delayMin, "min", "modSettings_reviveDelayMin", false)
end
BiterRevive.CalculateCurrentDelayMaximum = function()
    global.reviveDelayMax = BiterRevive.CalculateCurrentValue(CommandSettingNames.delayMax, "max", "modSettings_reviveDelayMax", false)
end
BiterRevive.CalculateCurrentDelayText = function()
    -- Is special in that we record the first highest priority text string we find and use that.
    local currentDelayText  ---@type string
    local currentDelayTextPriorityOrderedIndex = 10 ---@type CommandPriorityOrderedIndex
    for _, command in pairs(global.commands) do
        -- Will be a non existant setting in the command and not an empty string like the mod setting.
        if command[CommandSettingNames.delayText] ~= nil then
            local commandPriorityOrderedIndex = CommandPriorityOrderedIndex[command.priority]
            if commandPriorityOrderedIndex < currentDelayTextPriorityOrderedIndex then
                currentDelayText = command.delayText
                currentDelayTextPriorityOrderedIndex = commandPriorityOrderedIndex
                if commandPriorityOrderedIndex == 1 then
                    -- Nothing can be higher priority and we use the first one found of a priority.
                    break
                end
            end
        end
    end

    -- Check if the mod setting should set the delay text over an "add" command. The mod setting is stored as an empty string and not nil as its a global.
    if currentDelayTextPriorityOrderedIndex > CommandPriorityOrderedIndex.modSetting and global.modSettings_reviveDelayText ~= "" then
        currentDelayText = global.modSettings_reviveDelayText
    end

    -- Reset the texts and populate with the entries in the current comma seperated string value.
    if currentDelayText ~= nil then
        global.reviveDelayTexts = Utils.SplitStringOnCharacters(currentDelayText, ",", false)
    else
        global.reviveDelayTexts = {}
    end
end
BiterRevive.CalculateCurrentMaxRevivesPerUnit = function()
    global.maxRevivesPerUnit = BiterRevive.CalculateCurrentValue(CommandSettingNames.maxRevives, "max", "modSettings_maxRevivesPerUnit", true)
end

--- Generic processing of settings.
---@param settingName CommandSettingNames
---@param minOrMax "'min'"|"'max'" @ If this uses the min or max value for multiple enforce or base priority commands.
---@param modSettingCacheName string @ The global cache value of the mod setting for use if no enforced or base commands.
---@param zeroIsInfinitelyLarge boolean @ If true then a zero value is the largest value at infinitely large.
---@return number currentValue
BiterRevive.CalculateCurrentValue = function(settingName, minOrMax, modSettingCacheName, zeroIsInfinitelyLarge)
    local currentValue

    -- Sort the active commands in to their priority types for this setting.
    local commandsForSetting = {enforced = {}, base = {}, add = {}}
    for _, command in pairs(global.commands) do
        if command[settingName] ~= nil then
            table.insert(commandsForSetting[command.priority], command[settingName])
        end
    end

    if #commandsForSetting.enforced > 0 then
        -- Theres some "enforced" commands so use these to set the value permenantly.
        if #commandsForSetting.enforced == 1 then
            -- Just 1 command so set the value.
            currentValue = commandsForSetting.enforced[1]
            if zeroIsInfinitelyLarge and currentValue == 0 then
                currentValue = 4294967295
            end
        else
            -- Multiple commands so get the lowe st/highest based on setting type.
            for _, value in pairs(commandsForSetting.enforced) do
                if zeroIsInfinitelyLarge and value == 0 then
                    value = 4294967295
                end
                if currentValue == nil then
                    currentValue = value
                elseif minOrMax == "min" and value < currentValue then
                    currentValue = value
                elseif minOrMax == "max" and value > currentValue then
                    currentValue = value
                end
            end
        end
        -- No more processing required if theres an "enforced" priority command.
        return currentValue
    elseif #commandsForSetting.base > 0 then
        -- Theres some "base" commands so use these to set the initial value.
        if #commandsForSetting.base == 1 then
            -- Just 1 command so set the value.
            currentValue = commandsForSetting.base[1]
            if zeroIsInfinitelyLarge and currentValue == 0 then
                currentValue = 4294967295
            end
        else
            -- Multiple commands so get the lowest/highest based on setting type.
            for _, value in pairs(commandsForSetting.base) do
                if zeroIsInfinitelyLarge and value == 0 then
                    value = 4294967295
                end
                if currentValue == nil then
                    currentValue = value
                elseif minOrMax == "min" and value < currentValue then
                    currentValue = value
                elseif minOrMax == "max" and value > currentValue then
                    currentValue = value
                end
            end
        end
    elseif #commandsForSetting.base == 0 then
        -- No "base" commands so use the mod setting for the initial value.
        currentValue = global[modSettingCacheName]
        if zeroIsInfinitelyLarge and currentValue == 0 then
            currentValue = 4294967295
        end
    end

    -- Apply any "add" commands
    for _, value in pairs(commandsForSetting.add) do
        if zeroIsInfinitelyLarge and value == 0 then
            value = 4294967295
        end
        currentValue = currentValue + value
    end

    return currentValue
end

--- Called to update all forces cached data after a setting has been changed that will affect revive chances.
---@param currentTick Tick
BiterRevive.UpdateAllForcesData = function(currentTick)
    for _, forceReviveChanceObject in pairs(global.forcesReviveChance) do
        BiterRevive.UpdateForceData(forceReviveChanceObject, currentTick)
    end
end

---@param event on_runtime_mod_setting_changed|null
BiterRevive.OnSettingChanged = function(event)
    -- Event is nil when this is called from OnStartup for a new game or a mod change. In this case we update all settings.

    local updateAllForceData = false
    local settingErrorMessages = {} ---@type string[]
    local settingErrorMessage  ---@type string

    ------------------------------------------------------------
    -- These settings need processing to establish the current value as RCON commands can affect the final value in global.
    ------------------------------------------------------------
    if event == nil or event.setting == "biter_revive-evolution_percent_minimum" then
        local settingValue = settings.global["biter_revive-evolution_percent_minimum"].value
        global.modSettings_evolutionRequirementMin = settingValue / 100
        BiterRevive.CalculateCurrentEvolutionMinimum()
        updateAllForceData = true
    end
    if event == nil or event.setting == "biter_revive-evolution_percent_maximum" then
        local settingValue = settings.global["biter_revive-evolution_percent_maximum"].value
        global.modSettings_evolutionRequirementMax = settingValue / 100
        BiterRevive.CalculateCurrentEvolutionMaximum()
        updateAllForceData = true
    end
    if event == nil or event.setting == "biter_revive-chance_base_percent" then
        local settingValue = settings.global["biter_revive-chance_base_percent"].value
        global.modSettings_reviveChanceBaseValue = settingValue / 100
        BiterRevive.CalculateCurrentChanceBase()
        updateAllForceData = true
    end
    if event == nil or event.setting == "biter_revive-chance_percent_per_evolution_percent" then
        local settingValue = settings.global["biter_revive-chance_percent_per_evolution_percent"].value
        global.modSettings_reviveChancePerEvo = settingValue
        BiterRevive.CalculateCurrentChancePerEvolution()
        updateAllForceData = true
    end
    if event == nil or event.setting == "biter_revive-chance_formula" then
        local settingValue = settings.global["biter_revive-chance_formula"].value
        -- Check the formula and handle it specially.
        if settingValue ~= "" then
            -- Formula provided so needs checking.
            local validatedFormulaString, errorMessage = BiterRevive.GetValdiatedFormulaString(settingValue)
            if errorMessage == nil then
                -- Formula is good to use.
                global.modSettings_reviveChancePerEvoPercentFormula = validatedFormulaString
            else
                -- Formula is bad.
                settingErrorMessage = "Biter Revive - Invalid revive chance formula provided in mod settings so it's being ignored. Error: " .. errorMessage
                game.print(settingErrorMessage, Colors.lightred)
                table.insert(settingErrorMessages, settingErrorMessage)
                global.modSettings_reviveChancePerEvoPercentFormula = ""
            end
        else
            -- No formula provided.
            global.modSettings_reviveChancePerEvoPercentFormula = ""
        end
        BiterRevive.CalculateCurrentChanceFormula()
        updateAllForceData = true
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
    if event == nil or event.setting == "biter_revive-delay_text" then
        local settingValue = settings.global["biter_revive-delay_text"].value
        global.modSettings_reviveDelayText = settingValue
        BiterRevive.CalculateCurrentDelayText()
    end
    if event == nil or event.setting == "biter_revive-maximum_revives_per_unit" then
        local settingValue = settings.global["biter_revive-maximum_revives_per_unit"].value
        global.modSettings_maxRevivesPerUnit = settingValue
        BiterRevive.CalculateCurrentMaxRevivesPerUnit()
    end

    ------------------------------------------------------------
    -- These settings just need caching as can't be overridden by RCON command.
    ------------------------------------------------------------
    if event == nil or event.setting == "biter_revive-revives_per_second" then
        local settingValue = settings.global["biter_revive-revives_per_second"].value
        -- Make the revivesPerCycle be a round part of the total, with the nStartOfSecond having the left over odd count.
        local groupsPerSecond = math_floor(60 / DelayGroupingTicks)
        global.revivesPerCycle = math_floor(settingValue / groupsPerSecond)
        global.revivesPerCycleOnStartOfSecond = global.revivesPerCycle + (settingValue - (global.revivesPerCycle * groupsPerSecond))
    -- Nothing needs processing for this.
    end
    if event == nil or event.setting == "biter_revive-blacklisted_prototype_names" then
        local settingValue = settings.global["biter_revive-blacklisted_prototype_names"].value

        -- Check if was populated before as if not changed from before we don't want to confirm no change.
        local changed = settingValue ~= global.raw_BlacklistedPrototypeNames
        global.raw_BlacklistedPrototypeNames = settingValue

        global.blacklistedPrototypeNames = Utils.SplitStringOnCharacters(settingValue, ",", true)

        -- Only check and notify if the setting value was actually changed from before.
        if changed then
            -- Check each prototype name is valid and tell the playe about any that aren't. Don't block the update though as it does no harm.
            local count = 1
            for name in pairs(global.blacklistedPrototypeNames) do
                local prototype = game.entity_prototypes[name]
                if prototype == nil then
                    settingErrorMessage = "Biter Revive - unrecognised prototype name '" .. name .. "' in blacklisted prototype names. Is number " .. tostring(count) .. " in the list."
                    game.print(settingErrorMessage, Colors.lightred)
                    table.insert(settingErrorMessages, settingErrorMessage)
                elseif prototype.type ~= "unit" then
                    settingErrorMessage = "Biter Revive - prototype name '" .. name .. "' in blacklisted prototype names isn't of type 'unit' and so could never be revived anyways."
                    game.print(settingErrorMessage, Colors.lightred)
                    table.insert(settingErrorMessages, settingErrorMessage)
                end
                count = count + 1
            end

            -- Confirm back to the player the prototypes identified from the list.
            game.print("Biter Revive - Blacklisted prototype names changed to: " .. Utils.TableKeyToNumberedListString(global.blacklistedPrototypeNames))
        end
    end
    if event == nil or event.setting == "biter_revive-blacklisted_force_names" then
        local settingValue = settings.global["biter_revive-blacklisted_force_names"].value

        -- Check if was populated before as if not changed from before we don't want to confirm no change.
        local changed = settingValue ~= global.raw_BlacklistedForceNames
        global.raw_BlacklistedForceNames = settingValue

        local forceNames = Utils.SplitStringOnCharacters(settingValue, ",", true)
        -- Blank the global before adding the new ones every time.
        global.blacklisedForceIds = {}
        -- Only add valid force Id's to the global.
        for forceName in pairs(forceNames) do
            local force = game.forces[forceName]
            if force ~= nil then
                global.blacklisedForceIds[force.index] = true
            else
                settingErrorMessage = "Biter Revive - Invalid force name provided: " .. forceName
                game.print(settingErrorMessage, Colors.lightred)
                table.insert(settingErrorMessages, settingErrorMessage)
            end
        end

        -- Only notify about the change if the setting was changed
        if changed then
            game.print("Biter Revive - Blacklisted force Ids changed to: " .. Utils.TableKeyToNumberedListString(forceNames))
        end
    end

    -- Update all cached force data if its needed after settings changd.
    if updateAllForceData then
        local currentTick
        if event == nil then
            currentTick = game.tick
        else
            currentTick = event.tick
        end
        BiterRevive.UpdateAllForcesData(currentTick)
    end

    -- If its 0 tick (initial map start and there were errors add them to be written out after a few ticks)
    if game.tick == 0 and #settingErrorMessages > 0 then
        global.zeroTickErrors = settingErrorMessages
    end
end

--- Handler of the RCON command "biter_revive_add_modifier".
---@param command CustomCommandData
BiterRevive.OnCommand_AddModifier = function(command)
    local args = Commands.GetArgumentsFromCommand(command.parameter)
    local errorMessageStart = "Biter Revive - command biter_revive_add_modifier "

    -- Check the top level JSON object table.
    local data = args[1]
    if not Commands.ParseTableArgument(data, true, command.name, "Json object", CommandAttributes) then
        return
    end

    -- Check the main attributes of the object.

    local durationSeconds = data.duration ---@type Second
    if not Commands.ParseNumberArgument(durationSeconds, "integer", true, command.name, "duration", 0) then
        return
    end

    local priority = data.priority ---@type CommandPriority
    if not Commands.ParseStringArgument(priority, true, command.name, "priority", CommandPriority) then
        return
    end

    local settings = data.settings
    if not Commands.ParseTableArgument(settings, true, command.name, "settings", CommandSettingNames) then
        return
    end

    -- Check the settings specific fields in the object. Note that none of the settings force value ranges.

    local evoMinPercent_raw = settings.evoMin ---@type double
    if not Commands.ParseNumberArgument(evoMinPercent_raw, "double", false, command.name, "evoMin") then
        return
    end
    local evoMin  ---@type double
    if evoMinPercent_raw ~= nil then
        evoMin = evoMinPercent_raw / 100
    end

    local evoMaxPercent_raw = settings.evoMax ---@type double
    if not Commands.ParseNumberArgument(evoMaxPercent_raw, "double", false, command.name, "evoMax") then
        return
    end
    local evoMax  ---@type double
    if evoMaxPercent_raw ~= nil then
        evoMax = evoMaxPercent_raw / 100
    end

    local chanceBasePercent_raw = settings.chanceBase ---@type double
    if not Commands.ParseNumberArgument(chanceBasePercent_raw, "double", false, command.name, "chanceBase") then
        return
    end
    local chanceBase  ---@type double
    if chanceBasePercent_raw ~= nil then
        chanceBase = chanceBasePercent_raw / 100
    end

    -- No modifier on this one.
    local chancePerEvo = settings.chancePerEvo ---@type double
    if not Commands.ParseNumberArgument(chancePerEvo, "double", false, command.name, "chancePerEvo") then
        return
    end

    local chanceFormula_raw = settings.chanceFormula ---@type string
    if not Commands.ParseStringArgument(chanceFormula_raw, false, command.name, "chanceFormula") then
        return
    end
    local chanceFormula  ---@type string
    if chanceFormula_raw ~= nil then
        if chanceFormula_raw ~= "" then
            -- Check the formula string is valid.
            local errorMessage  ---@type string
            chanceFormula, errorMessage = BiterRevive.GetValdiatedFormulaString(chanceFormula_raw)
            if errorMessage ~= nil then
                -- Formula is bad.
                game.print(errorMessageStart .. "Invalid revive chance formula provided so it's being ignored. Error: " .. errorMessage, Colors.lightred)
                return
            end
        else
            -- Set the formula blank string to nil as its more logical to check commands with it as optional setting that way. People may enter it as a blank string as thats what the mod setting requires. The global cached mod setting uses a blank string and not nil however.
            chanceFormula = nil
        end
    end

    local delayMinSeconds_raw = settings.delayMin ---@type Second
    if not Commands.ParseNumberArgument(delayMinSeconds_raw, "integer", false, command.name, "delayMin") then
        return
    end
    local delayMin  ---@type Tick
    if delayMinSeconds_raw ~= nil then
        delayMin = delayMinSeconds_raw * 60
    end

    local delayMaxSeconds_raw = settings.delayMax ---@type Second
    if not Commands.ParseNumberArgument(delayMaxSeconds_raw, "integer", false, command.name, "delayMax") then
        return
    end
    local delayMax  ---@type Tick
    if delayMaxSeconds_raw ~= nil then
        delayMax = delayMaxSeconds_raw * 60
    end

    local delayText_raw = settings.delayText ---@type string
    if not Commands.ParseStringArgument(delayText_raw, false, command.name, "delayText") then
        return
    end
    local delayText  ---@type string
    if delayText_raw ~= nil then
        if delayText_raw ~= "" then
            delayText = delayText_raw
        else
            -- Set the delay text blank string to nil as its more logical to check commands with it as optional setting that way. People may enter it as a blank string as thats what the mod setting requires. The global cached mod setting uses a blank string and not nil however.
            delayText = nil
        end
    end

    -- No modifier on this one.
    local maxRevives = settings.maxRevives ---@type uint
    if not Commands.ParseNumberArgument(maxRevives, "integer", false, command.name, "maxRevives") then
        return
    end

    -- Check that one or more settings where included, otherwise the command will do nothing.
    if evoMin == nil and evoMax == nil and chanceBase == nil and chancePerEvo == nil and chanceFormula == nil and delayMin == nil and delayMax == nil and delayText == nil and maxRevives == nil then
        game.print(errorMessageStart .. "no actual setting was included within the settings table.", Colors.lightred)
        return
    end

    -- Add command results in to commands table.
    global.commandsNextId = global.commandsNextId + 1
    ---@type CommandDetails
    local commandDetails = {
        id = global.commandsNextId,
        duration = durationSeconds * 60,
        removalTick = command.tick + (durationSeconds * 60),
        priority = priority,
        evoMin = evoMin,
        evoMax = evoMax,
        chanceBase = chanceBase,
        chancePerEvo = chancePerEvo,
        chanceFormula = chanceFormula,
        delayMin = delayMin,
        delayMax = delayMax,
        delayText = delayText,
        maxRevives = maxRevives
    }
    global.commands[commandDetails.id] = commandDetails

    -- If this command is the next expiring then update the check tick flag.
    if global.nextCommandExpireTick == 0 or commandDetails.removalTick < global.nextCommandExpireTick then
        global.nextCommandExpireTick = commandDetails.removalTick
    end

    BiterRevive.CallUpdateFunctionsForCommandDetails(commandDetails, command.tick)
end

--- Checks a forumla string handles an evo value of 0% (0) and 100% (100). If it does returns the formula string, otherwise returns a blank string "" and the error message.
---@param formulaStringToTest string
---@return string validatedFormulaString @ Either the validated string or blank string "".
---@return string|null failureReason @ A message of why it failed validation or nil if it passed.
BiterRevive.GetValdiatedFormulaString = function(formulaStringToTest)
    for _, testEvo in pairs({0, 100}) do
        local success, result =
            pcall(
            function()
                return load("local evo = " .. testEvo .. "; return " .. formulaStringToTest)()
            end
        )
        -- Check for erors and inspect the result.
        if not success then
            -- Test failed
            return "", "syntax error of some type processing for test value: " .. tostring(testEvo)
        else
            -- Test succeded s check the result
            if type(result) ~= "number" then
                return "", "result wasn't a number for test value: " .. tostring(testEvo)
            elseif result ~= result then
                return "", "result was NaN (not a number) for test value: " .. tostring(testEvo)
            end
        end
    end
    return formulaStringToTest, nil
end

--- Dumps the mod setting cache, active commands and runtime setting values to a text file on the players pc.
---@param command CustomCommandData
BiterRevive.OnCommand_DumptStateData = function(command)
    local dumptext = ""

    -- Mod settings cache
    dumptext = dumptext .. "Mod Settings" .. "\r\n"
    dumptext = dumptext .. "evolutionRequirementMin, " .. tostring(global.modSettings_evolutionRequirementMin) .. "\r\n"
    dumptext = dumptext .. "evolutionRequirementMax, " .. tostring(global.modSettings_evolutionRequirementMax) .. "\r\n"
    dumptext = dumptext .. "reviveChanceBaseValue, " .. tostring(global.modSettings_reviveChanceBaseValue) .. "\r\n"
    dumptext = dumptext .. "reviveChancePerEvo, " .. tostring(global.modSettings_reviveChancePerEvo) .. "\r\n"
    dumptext = dumptext .. "reviveChancePerEvoPercentFormula, " .. tostring(global.modSettings_reviveChancePerEvoPercentFormula) .. "\r\n"
    dumptext = dumptext .. "reviveDelayMin, " .. tostring(global.modSettings_reviveDelayMin) .. "\r\n"
    dumptext = dumptext .. "reviveDelayMax, " .. tostring(global.modSettings_reviveDelayMax) .. "\r\n"
    dumptext = dumptext .. "reviveDelayText, " .. tostring(string.gsub(global.modSettings_reviveDelayText, ",", ";")) .. "\r\n"
    dumptext = dumptext .. "maxRevivesPerUnit, " .. tostring(global.modSettings_maxRevivesPerUnit) .. "\r\n"

    -- Commands
    dumptext = dumptext .. "\r\n\r\n"
    dumptext = dumptext .. "Commands" .. "\r\n"
    dumptext = dumptext .. "id, priority, duration, removalTick, evoMin, evoMax, chanceBase, chancePerEvo, chanceFormula, delayMin, delayMax, delayText, maxRevives" .. "\r\n"
    for _, commandDetails in pairs(global.commands) do
        dumptext = dumptext .. tostring(commandDetails.id) .. ", " .. tostring(commandDetails.priority) .. ", " .. tostring(commandDetails.duration) .. ", " .. tostring(commandDetails.removalTick) .. ", " .. tostring(commandDetails.evoMin) .. ", " .. tostring(commandDetails.evoMax) .. ", " .. tostring(commandDetails.chanceBase) .. ", " .. tostring(commandDetails.chancePerEvo) .. ", " .. tostring(commandDetails.chanceFormula) .. ", " .. tostring(commandDetails.delayMin) .. ", " .. tostring(commandDetails.delayMax) .. ", " .. tostring(string.gsub(commandDetails.delayText, ",", ";")) .. ", " .. tostring(commandDetails.maxRevives) .. "\r\n"
    end

    -- Runtime settings
    dumptext = dumptext .. "\r\n\r\n"
    dumptext = dumptext .. "Runtime Settings" .. "\r\n"
    dumptext = dumptext .. "evolutionRequirementMin, " .. tostring(global.evolutionRequirementMin) .. "\r\n"
    dumptext = dumptext .. "evolutionRequirementMax, " .. tostring(global.evolutionRequirementMax) .. "\r\n"
    dumptext = dumptext .. "reviveChanceBaseValue, " .. tostring(global.reviveChanceBaseValue) .. "\r\n"
    dumptext = dumptext .. "reviveChancePerEvoNumber, " .. tostring(global.reviveChancePerEvoNumber) .. "\r\n"
    dumptext = dumptext .. "reviveChancePerEvoPercentFormula, " .. tostring(global.reviveChancePerEvoPercentFormula) .. "\r\n"
    dumptext = dumptext .. "reviveDelayMin, " .. tostring(global.reviveDelayMin) .. "\r\n"
    dumptext = dumptext .. "reviveDelayMax, " .. tostring(global.reviveDelayMax) .. "\r\n"
    dumptext = dumptext .. "reviveDelayText, " .. tostring(string.gsub(Utils.TableValueToCommaString(global.reviveDelayTexts), ",", ";")) .. "\r\n"
    dumptext = dumptext .. "maxRevivesPerUnit, " .. tostring(global.maxRevivesPerUnit) .. "\r\n"

    -- Write out the file to disk and message the player.
    game.write_file("biter_revive_state_data.csv", dumptext, false, command.player_index)
    game.get_player(command.player_index).print("Biter Revive - state data written to Factorio/script-output/biter_revive_state_data.csv", Colors.green)
end

return BiterRevive
