-- Populate the new global.nextCommandExpireTick if there are any active commands. As otherwise they would never end given they were added under the old Scheduler library.
if next(global.commands) ~= nil then
    -- Set it to 1 as that will mean the mod checks and updates the values to be as expected upon next task process loop.
    global.nextCommandExpireTick = 1
end

-- Remove any previously scheduled events just to keep the global tidy.
global.UTILITYSCHEDULEDFUNCTIONS = nil
