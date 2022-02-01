local BiterRevive = {}
local Events = require("utility/events")

local UnitsIgnored = {character = "character", compilatron = "compilatron"}
local DelayTickGrouping = 15 -- How many ticks between each goup of biters to revive.
local ForceEvoCacheTicks = 60 -- How long to cache a forces evo for before it is refreshed on next dead unit.

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
    global.reviveDelayMinGroupings = global.reviveDelayMinGroupings or 0
    global.reviveDelayMaxGroupings = global.reviveDelayMaxGroupings or 0

    global.blacklistedPrototypeNames = global.blacklistedPrototypeNames or {} ---@type table<string, string> @ The key and value are both the blacklisted prototype name.
    global.blacklisedForceIds = global.blacklisedForceIds or {} ---@type table<Id, string> @ The force Id as key, with the force name we match against the setting on as the value.

    global.revivesPerCycle = global.revivesPerCycle or 0 --- How many revives can be done per cycle. Every cycle in each second apart from the one excatly at the start of the second.
    global.revivesPerCycleOnStartOfSecond = global.revivesPerCycleOnStartOfSecond or 0 --- How many revives can be done on the cycle at the start of the second. This makes up for any odd dividing issues with the player setting being revives per second.
end

BiterRevive.OnStartup = function()
end

BiterRevive.OnLoad = function()
    Events.RegisterHandlerEvent(defines.events.on_entity_died, "BiterRevive.OnEntityDied", BiterRevive.OnEntityDied, {{filter = "type", type = "unit"}})
    script.on_nth_tick(DelayTickGrouping, BiterRevive.ProcessQueue)
    Events.RegisterHandlerEvent(defines.events.on_forces_merged, "BiterRevive.OnForcesMerged", BiterRevive.OnForcesMerged)
    Events.RegisterHandlerEvent(defines.events.on_surface_deleted, "BiterRevive.OnSurfaceRemoved", BiterRevive.OnSurfaceRemoved)
    Events.RegisterHandlerEvent(defines.events.on_surface_cleared, "BiterRevive.OnSurfaceRemoved", BiterRevive.OnSurfaceRemoved)
end

---@param event on_runtime_mod_setting_changed|null
BiterRevive.OnSettingChanged = function(event)
    -- Event is nil when this is called from OnStartup for a new game or a mod change. In this case we update all settings.

    -- TODO: no need to cache setting values themselves, just run the function to work out the current value as if RCON has over ruled the value that is what goes in to global until RCON command expires and then that will trigger its own update to globals.
    if event == nil or event.setting == "xxxxx" then
        local x = tonumber(settings.global["xxxxx"].value)
    end
end

--- When a monitored entity type has died review it and if approperiate add it to the revive queue.
---@param event on_entity_died
BiterRevive.OnEntityDied = function(event)
    -- Currently only even so filtered to "type = unit" and entity will always be valid as nothing within the mod can invalid it.
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
    local delayGrouping = math.random(global.reviveDelayMinGroupings, global.reviveDelayMaxGroupings)
    local groupingTick = (math.floor(event.tick / DelayTickGrouping) + 1 + delayGrouping) * DelayTickGrouping -- At a minimum this will be the next grouping if the delayGrouping is 0.

    -- Add to queue in the correct grouping tick
    local tickQueue = global.reviveQueue[groupingTick]
    if tickQueue == nil then
        global.reviveQueue[groupingTick] = {}
        tickQueue = global.reviveQueue[groupingTick]
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

--- Process any current queue of biter revives. Called once every DelayTickGrouping ticks.
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
            -- We will handle surface's being deleted and forces removed/merged via events so no need to track them here.

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

-- TODO: mod settings being changed.
-- TODO: RCON commands being recieved and processed.
-- TODO: updating the global values when mod settings are changed or RCOn commands recieved.

return BiterRevive
