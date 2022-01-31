local BiterRevive = {}
local Events = require("utility/events")

local UnitsIgnored = {character = "character", compilatron = "compilatron"}
local DelayTickGrouping = 30 -- How many ticks between each goup of biters to revive.

---@class ReviveQueueTickObject
---@field prototypeName string
---@field orientation RealOrientation
---@field force LuaForce
---@field surface LuaSurface
---@field position Position

---@class ForceReviveChanceObject
---@field reviveChance double @ Number between 0 and 1.
---@field oldEvolution double @ Number between 0 and 1.
---@field lastCheckedTick Tick

BiterRevive.CreateGlobals = function()
    global.reviveQueue = global.reviveQueue or {} ---@type table<Tick, ReviveQueueTickObject[]>
    global.forcesReviveChance = global.forcesReviveChance or {} ---@type table<Id, ForceReviveChanceObject> @ A table of force indexes and their revival chance data.

    global.evolutionRequirementMin = global.evolutionRequirementMin or 0
    global.evolutionRequirementMax = global.evolutionRequirementMax or 0
    global.reviveChanceMin = global.reviveChanceMin or 0
    global.reviveChanceMax = global.reviveChanceMax or 0
    global.reviveDelayMinGroupings = global.reviveDelayMinGroupings or 0
    global.reviveDelayMaxGroupings = global.reviveDelayMaxGroupings or 0

    global.blacklistedPrototypeNames = global.blacklistedPrototypeNames or {} ---@type table<string, string> @ The keya nd value are both the blacklisted prototype name.
end

BiterRevive.OnStartup = function()
end

BiterRevive.OnLoad = function()
    Events.RegisterHandlerEvent(defines.events.on_entity_died, "BiterRevive.OnEntityDied", BiterRevive.OnEntityDied, {{filter = "type", type = "unit"}})
    script.on_nth_tick(DelayTickGrouping, BiterRevive.ProcessQueue)
end

--- When a monitored entity type died review it and if approperiate add it to the revive queue.
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

    local biterForce = entity.force

    -- Get the revive chance data and update it if its too old. Cache valid for 1 minute. This data will be instantly replaced by RCON commands, but they will be rare compared to needing to track forces evo changes over time.
    local reviveChanceObject = global.forcesReviveChance[biterForce.index]
    if reviveChanceObject.lastCheckedTick < event.tick - 60 then
        local currentForceEvo = biterForce.evolution_factor
        if currentForceEvo ~= reviveChanceObject.oldEvolution then
            -- Evolution has changed so update the chance data.
            if currentForceEvo >= global.evolutionRequirementMin then
                -- Current evo is >= min required so work out proportional revive chance.
                local forceEvoInScale = currentForceEvo - global.evolutionRequirementMin
                local evoScale = global.evolutionRequirementMax - global.evolutionRequirementMin
                local chanceScale = global.reviveChanceMax - global.reviveChanceMin

                -- Current chance is the min chance plus the proportional chance from evo scale.
                reviveChanceObject.reviveChance = global.reviveChanceMin + ((forceEvoInScale / evoScale) * chanceScale)
            else
                -- Below min so no chance
                reviveChanceObject.reviveChance = 0
            end
        end
        reviveChanceObject.lastCheckedTick = event.tick
    end

    -- Random chance of entity being revived.
    if reviveChanceObject.reviveChance == 0 then
        -- No chance so just abort.
        return
    end
    if math.random() > reviveChanceObject.reviveChance then
        -- Failed random so abort.
        return
    end

    -- Make the details object to be queued.
    ---@type ReviveQueueTickObject
    local reviveDetails = {
        prototypeName = entity_name,
        orientation = entity.orientation,
        force = biterForce,
        surface = entity.surface,
        position = entity.position
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

--- Process any current queue of biter revives. Called once every DelayTickGrouping ticks.
---@param event NthTickEventData
BiterRevive.ProcessQueue = function(event)
end

return BiterRevive
