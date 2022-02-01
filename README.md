# Factorio-Biter-Revive

Any biter that dies will have a chance to revive back to life based on mod settings and temporary settings from RCON commands. The mod is focused on facilitating streamer integrations.
The chance of the revive is based on a configurable scale driven by the enemy force's evolution.


Notes
-----

- Any "unit" entity that breathes air is included in the revivie logic by default. This will include all vanilla Factorio biters and I assume most modded enemies as well.
- At present the player's character and compilatron are excluded from reviving. There is also a mod setting to add additional prototype names for exclusion.
- Revive chance is a scale based on mod and RCON settings using a min and max evolution range for a min and max revive chance. This should allow any desired effect to be achieved.
- Multiple times a second the biters awaiting reviving will be processed and up to the maximum (max revives per second mod setting) performed. This is done to both allow an optional delay in reviving and to avoid loops of biters being revived and instantly dieing.





Mod values that control the revival behaviour:
    - minimum evolution: when the biters force evolution reaches this level the revival logic will start.
    - minimum revive chance: the chance a biter will revive at "minimum evolution" level.
    - maximum revive chance: the chance a biter will revive at "maximum evolution" level.
    - maximum evolution: the evolution level when the maximum revive chance will be reached.
    - revive delay min: the minimum time before a biter will revive.
    - revive delay max: the maximum time before a biter will revive.
Evolution between the min and max will have a proportionate rate of revival chance between its min and max.
Biters will revive in a random time between the min and max delay.

The mod values have a current value which is primarily dictated by static mod settings. With one setting per mod value.
Optional RCON command can be used to set temporary values for a set period of time.
    - Each RCON command can have one or more of the mod values with any omitted values remaining unchanged.
    - RCON commands only apply for the duration of their time period.
    - An RCON command will have a Manipulation type for how its values are applied:
        - Enforce: sets the current value to be this command value and no other non enforce commands will be applied.
        - Replace: replaces the mod settings value as the base current values.
        - Modify: added to the current values. These are added to the current value, so often a negative value will be used.
    - If multiple RCON commands are applied at a time they will all be applied for each of their own durations.
        - Any Replace Manipulation commands will have the largest range of their combined settings applied, i.e. the lowest minimum values and the greatest maximum values.
        - Any Modify Manipulation commands will be stacked on top of the current values.
Current mod values are calculated as: Enforce command alone. Else Replace command or otherwise static mod setting, plus all RCON Modify command values applied.
Values are clamped between 0 and 100, except for delay which is greater or equal to 0.

Mod setting to blacklist biter prototypes by the user. These won't revive ever.
Mod setting for max revives per unit. Avoid infintely reviving the same biter every tick.
Mod setting to set a maximum number of revives per second to avoid excessive burst UPS load.
Mod setting to blacklist forces units from reviving.
Mod setting for zzz (configurable text) floating text over units delayed for reviving when they are delayed for more than 2 (test this looks right) seconds.

Handle some changes via event to save runtime checks being needed as very unlikely to ever occur.
    - If a force is merged via event. As will need any revives on the old force moved to the new one.
    - If a surface is cleared or deleted via event. As both will need us to delete all queued revives on those surfaces.




Add timer/clock to the text display mod so it can be used with time limited abilities via rcon on screen nicely.
Muppet GUI needs a check on old pc between committed and local files. As on new machine weird doubling up of all folders had occured. i.e. scripts (1) and notes (1). The doubling up notes TODO had different contents.

Push the updated Utils from this mod back in Utils Git and apply to railway tunnel mod.