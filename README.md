# Factorio-Biter-Revive
A mod that revives biters and supports RCON commands changing settings for streamer chat integrations.




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
        - Replace: replaces the mod settings value as the base current values.
        - Modify: added to the current values. These are added to the current value, so often a negative value will be used.
    - If multiple RCON commands are applied at a time they will all be applied for each of their own durations.
        - Any Replace Manipulation commands will have the largest range of their combined settings applied, i.e. the lowest minimum values and the greatest maximum values.
        - Any Modify Manipulation commands will be stacked on top of the current values.
Current mod values are calculated as: static mod setting/RCON Replace command, plus all RCON Modify command values applied.
Values are clamped between 0 and 100, except for delay which is greater or equal to 0.