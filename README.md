# Factorio-Biter-Revive

Any biter or worm (option) that dies will have a chance to revive back to life.

![Biter Revive Example](https://giant.gfycat.com/ChillyKnobbyAffenpinscher.mp4)

Includes a large selection of mod settings to control base revival chance and behaviours. To facilitating streamer integrations layered temporary settings can be applied as well via Remote Interface Calls or Factorio Commands.



Details
=======

- Any `unit` or worm entity is available for revival with various mod settings allowing fine tuning of what's excluded by entity and force name. By default the mod settings are configured for the `compilatron` unit and the `player` force to be excluded. Worm's are one of the `turret` entity types that have the `breath-air` prototype flag.
- Revive chance is a scale based on configurable settings using a min and max evolution range for a min and max revive chance. This should allow any desired effect to be achieved.
- Multiple times a second the enemies awaiting reviving will be processed and up to the maximum revives done, controlled by the max revives per second mod setting. This process avoids excessive revives being done at a time, so limits UPS impact during excessive biter death periods.
- Revives have a random delay between configurable min and max seconds from 0 upwards. To avoid infinite revive/death loops a 0 second revive won't happen the moment the enemy dies, but instead a fraction of a second later.
- Enemies waiting their delay time to revive can have configurable text shown above them until they revive, i.e. snore, BRB, its just a flesh wound, etc.
- There is a mod setting to limit how many times the same unit can be revived. It defaults to unlimited. Its useful for cases of very high revive rate when you don't want the risk of near infinite revivals due to random chances.
- If a biter revive location is blocked by buildings after the enemy has died then the biter will revive in the nearest available location. This is to prevent griefing by building large walls or buildings over delayed revival biters.
- A revived biter will have its pre death attack command applied back to it if possible. Otherwise the revived biters will be controlled by Factorio as normal.
- When a worm revives (mod option) it will revive to the exact same position, pushing anything it can out of the way. Anything that can't be moved will be destroyed by the force of the worm returning.



Revive Chance Formula
=====================

This is a special setting for when you want non linear revive chance growth in relation to evolution. When the default value of the setting is blank/empty then the simpler `Chance of revive % per evolution %` setting value will be used by the mod. When the formula setting is populated it will take priority over the simpler value setting.

The formula must be valid Lua written as suitable for use after the keyword `return` and will be run within the mod. The enemy's force evolution above the minimum runtime setting will be passed in as a Lua variable `evo` as a numeric value of the evolution percentage. So if the minimum is 70 (%) and the enemies force evo is 72 (%) the `evo` variable will have a value of 2.

Example of valid formula string: `evo * 1.5`

-----------------------

-----------------------

-----------------------



Modifiers (RCON)
==============

The modifiers concept is designed as a highly flexible way of applying setting values and modifiers to them. Modifiers apply for a limited duration and the mod supports multiple being active at one time and "stacking" with each other. When an enemy dies the mod evaluates all active modifier settings and the mod settings in a hierarchical manner to establish the correct current runtime settings.



#### Logic

Each modifier will include:

- Duration: how long in seconds the modifier will be active for.
- Settings: one or more settings that this modifier includes values for. These settings will correspond to the mod's settings. While the mod setting values are restricted in range, modifier setting values can be at any scale of the correct type (i.e. integer) and the final result will be clamped to between 0% and 100%. This is to allow unusual streamer requirements.
- Priority: this modifiers hierarchical state during the evaluation for current runtime settings. Types are: `Enforced`, `Base`, `Add`.

When the mod is evaluating modifiers and mod settings to identify the current runtime values it follows the below logic. It reviews all active modifiers for inclusion of the current setting.

1. If any have the `Enforced` priority then only these modifiers contribute to the runtime value of the setting. All other non `Enforced` priority modifiers and the mod setting are ignored for this. If multiple modifiers have `Enforced` priority then the widest value range will be used, i.e the lowest if the setting is a minimum and the largest if the setting is a maximum.
2. If any have the `Base` priority then these modifiers will set the base value of the setting, replacing the mod setting. Any `Add` priority modifiers will be applied on top of this. If multiple modifiers have `Base` priority then the widest value will be used, i.e the lowest if the setting is a minimum and the largest if the setting is a maximum.
3. If no modifier had `Enforce` or `Base` priority for this setting then the mod setting value will be used as the base value.
4. All modifiers with the `Add` priority will be added to the base value. If these are negative values then they will be deducted. This allows multiple `Add` modifiers to apply their cumulative effect.
5. The final value for evolution and revive chance settings will be clamped between 0% and 100%. With duration min/max settings being prevented going below 0 seconds.

#### Exceptions

2 settings are exceptions to the above evaluation logic: `chanceFormula` and `delayText`

- For these settings only the highest priority order active modifier will set the current value. If multiple modifiers are equally the highest priority one will be selected at random. This isn't deemed an issue as the concept of adding text strings together or finding the largest one doesn't make sense. Priority order is: enforced modifier, base modifier, mod setting, add modifier.

----------------------------



#### Options

Modifier options are provided with a single Lua object of the below structure:

| Option Group | Option Name | Mandatory | Value Type | Details |
| --- | --- | --- | --- | --- |
|  | duration | mandatory | int | Number of seconds the command will be active for. |
| settings | evoMin | optional | double | The evolution % minimum required for reviving to start, i.e. 50 = 50% - equivalent to the mod setting `Evolution % minimum for reviving`. |
| settings | evoMax | optional | double | The evolution % maximum when the revive chance doesn't increase any more, i.e. 80 = 80% - equivalent to the mod setting `Evolution % for maximum reviving chance`. |
| settings | chanceBase | optional | double | The revival chance % when at minimum evolution, i.e. 5 = 5% - Equivalent of mod setting `Chance of revival starting %`.
| settings | chancePerEvo | optional | double | The revive chance % increase per evolution % up to the max evolution limit, i.e. 2 = 2% - equivalent to the mod setting `Chance of revive % per evolution %`. |
| settings | chanceFormula | optional | string | The revival chance formula as a text string - Equivalent of mod setting `Chance of revive formula`. Note: this setting is an exception to the standard command evaluation logic, see Logic Exceptions above. |
| settings | delayMin | optional | int | The revive delay minimum in seconds, i.e. 0 = 0 seconds - equivalent to the mod setting `Revive delay minimum seconds`. |
| settings | delayMax | optional | int | The revive delay maximum in seconds , i.e. 5 = 5 seconds - equivalent to the mod setting `Revive delay maximum seconds`. |
| settings | delayText | optional | string | The text to be shown above enemies that are waiting their delay to revive, as a comma separated string list (string) - equivalent to the mod setting `Delayed revive text`. Note: this setting is an exception to the standard command evaluation logic, see Logic Exceptions above. |
| settings | maxRevives | optional | int | The maximum number of times a single unit can be revived, with 0 being unlimited (nearly) - equivalent to the mod setting `Maximum revives per unit`. |
|  | priority | mandatory | string | The priority for this command as a text string. Supported values `enforced`, `base`, `add`. |

The options are defined to the command/remote call as a Lua object of Option Group fields. With each option group field being an object of it's fields. The Options with no group just go directing under the main object.

Format: table<string, any | table<string, any> >
Partial example: { duration = 5, settings = {evoMin=50, evoMax=100} }

----------------------------



#### Remote Interface

Remote Interface Syntax: `/sc remote.call('biter_revive', 'add_modifier', [OPTIONS TABLE])`

The options must be provided as a Lua table.

Examples:

1. Make enemies revive in all cases for 1 minute and have zombie delay text:
   > `/sc remote.call('biter_revive', 'add_modifier', {duration=60, settings={ evoMin=0, evoMax=100, chanceBase=100, chanceFormula="", chancePerEvo=0, delayText="uuggghh, raaaugh, blaaagh"}, priority="enforced"} )`
2. Make enemies have a base delayed revive time of between 1 and 2 minutes for 5 minutes, with any other runtime settings being applied still:
   > `/sc remote.call('biter_revive', 'add_modifier', {duration=300, settings={ delayMin=60, delayMax=120}, priority="base"} )`
3. Make enemies 5% more likely to revive than the current runtime settings would be otherwise, for 3 minutes:
   > `/sc remote.call('biter_revive', 'add_modifier', {duration=180, settings={ chanceBase=5 }, priority="add"} )`

----------------------------



#### Factorio Commands

Command Syntax: `/biter_revive_add_modifier [OPTIONS TABLE AS JSON STRING]`

The modifiers options must be provided as a JSON string of a table.

Examples:

1. Make enemies revive in all cases for 1 minute and have zombie delay text:
   > `/biter_revive_add_modifier {"duration":60, "settings":{ "evoMin":0, "evoMax":100, "chanceBase":100, "chanceFormula":"", "chancePerEvo":0, "delayText":"uuggghh, raaaugh, blaaagh"}, "priority":"enforced"}`
2. Make enemies have a base delayed revive time of between 1 and 2 minutes for 5 minutes, with any other runtime settings being applied still:
   > `/biter_revive_add_modifier {"duration":300, "settings":{ "delayMin":60, "delayMax":120}, "priority":"base"}`
3. Make enemies 5% more likely to revive than the current runtime settings would be otherwise, for 3 minutes:
   > `/biter_revive_add_modifier {"duration":180, "settings":{ "chanceBase":5 }, "priority":"add"}`

-------------------------------

-------------------------------

-------------------------------



Debug Command
=============

There is a debug command that will write out state data to assist with any issue debugging. It writes the state data to a file in the players Factorio script-data folder called `biter_revive_state_data.csv`. It will overwrite any previous debug data file of the same name.

Command Name: `biter_revive_dump_state_data`

-----------------------

-----------------------

-----------------------



Mod Compatibility Events
=============

The mod raises a number of custom events based around if it will/won't revive enemies (biters or worms) and if the revives are successful or not. This allows other mods to react to non revived enemies (truly dead) and avoid reacting to enemies that are revived as if they actually died.

This logic is utilised by my Biter Reincarnation mod to only reincarnate truly dead biters in to trees. As such it is initially designed around its requirements.

Modding details of these events can be found here: https://github.com/muppet9010/Factorio-Biter-Revive/blob/main/MOD-COMPATIBILITY.md