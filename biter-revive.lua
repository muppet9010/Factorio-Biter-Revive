local BiterRevive = {}
local Events = require("utility/events")

local UnitsIgnored = {character = "character", compilatron = "compilatron"}
local DelayTickGrouping = 15 -- How many ticks between each goup of biters to revive.
local ForceEvoCacheTicks = 60 -- How long to cache a forces evo for before it is refreshed on next dead unit.

---@class ReviveQueueTickObject
---@field prototypeName string
---@field orientation RealOrientation
---@field force LuaForce
---@field surfaceIndex uint
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

    global.evolutionRequirementMin = global.evolutionRequirementMin or 0
    global.evolutionRequirementMax = global.evolutionRequirementMax or 0
    global.reviveChanceMin = global.reviveChanceMin or 0
    global.reviveChanceMax = global.reviveChanceMax or 0
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

    -- TODO: profile test if its an API call for event data each time. If so add TODO to Tunnel mod to always cache them.
    local x = event.tick
    local y = event.tick
    local z = event.tick

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
            -- Current evo is >= min required so work out proportional revive chance.
            local forceEvoInScale = currentForceEvo - global.evolutionRequirementMin
            local evoScale = global.evolutionRequirementMax - global.evolutionRequirementMin
            local chanceScale = global.reviveChanceMax - global.reviveChanceMin

            -- Current chance is the min chance plus the proportional chance from evo scale.
            forceReviveChanceObject.reviveChance = global.reviveChanceMin + ((forceEvoInScale / evoScale) * chanceScale)
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
    -- Make sure over a second we do a max of the exact number of revivies per second setting regardless of how many cycles we devide it in to.
    local revivesRemainingThisCycle
    if event.tick % 60 == 0 then
        revivesRemainingThisCycle = global.revivesPerCycleOnStartOfSecond
    else
        revivesRemainingThisCycle = global.revivesPerCycle
    end

    -- Start at the beginning (oldest) of the queued revive Ticks and work forwards until we reach a future tick from now, or we do our max revives this cycle.
    for tick, reviveQueueTickObjects in pairs(global.reviveQueue) do
        if tick > event.tick then
            -- Done all we should so stop.
            return
        end

        for reviveIndex, reviveDetails in pairs(reviveQueueTickObjects) do
            -- We will handle surface's being deleted and forces removed/merged via events so no need to track them here.

            -- Do the actual revive asuming a suitable position is found.
            local newPosition = reviveDetails.surface.find_non_colliding_position(reviveDetails.prototypeName, reviveDetails.position, 5, 0.1)
            if newPosition ~= nil then
                reviveDetails.surface.create_entity {
                    name = reviveDetails.prototypeName,
                    position = newPosition,
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

-- TODO: mod settings being changed.
-- TODO: RCON commands being recieved and processed.
-- TODO: udpating the global values when mod settings are changed or RCOn commands recieved.
-- TODO: handle surface clears & deletions, and forces merged events.

return BiterRevive
