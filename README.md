# Factorio-Biter-Revive

Any biter that dies will have a chance to revive back to life based on mod settings and temporary settings from commands (RCON).

![Biter Revive Example](https://giant.gfycat.com/ChillyKnobbyAffenpinscher.mp4)

The mod is focused on facilitating streamer integrations and so uses a layered settings approach, but can be used standalone using mod settings alone.



Details
=======

- Any "unit" entity is available for revival with various mod settings allowing fine tuning of what's excluded by entity and force name. By default the mod settings are configured only for the compilatron unit to be excluded.
- Revive chance is a scale based on configurable settings using a min and max evolution range for a min and max revive chance. This should allow any desired effect to be achieved.
- Multiple times a second the biters awaiting reviving will be processed and up to the maximum (max revives per second mod setting) performed. This is done to both allow an optional delay in reviving and to avoid loops of biters being revived and instantly dieing.
- Revives have a random delay between configurable min and max seconds from 0 upwards. To avoid infinite revive/death loops a 0 second revive won't happen the moment the biter dies, but instead a fraction of a second later.
- Biters waiting their delay time to revive can have text shown above them until they revive. This is highly configurable and will only appear if the delay is more than 2 seconds. --TODO
- There is a mod setting to limit how many times the same unit can be revived. It defaults to unlimited. Its useful for cases of very high revive rate when you don't want the risk of near infinite revivals due to random chances.
- If a biter revive location is blocked by buildings after the biter has died then the biter will revive in the nearest available location. This is to prevent griefing by building large walls or buildings over delayed revival biters.



Revive Chance Formula
=====================

This is a special setting for when you want nonlinear revive chance growth in relation to evolution. When the default value of the setting is blank/empty then the simpler "Chance of revive % per evolution %" setting value will be used by the mod. When the formula setting is populated it will take priority over the simpler setting.

The formula must be valid Lua written as suitable for use after the keyword "return" and will be run within the mod. The biter's force evolution above the minimum runtime setting will be passed in as a Lua variable "evo" as a numeric value of the evolution percentage. So if the minimum is 70 (%) and the biters force evo is 72 (%) the "evo" variable will have a value of 2.

Example of valid formula string: `evo * 1.5`



Command (RCON)
==============

The command concept is designed as a highly flexible way of applying setting values and modifiers. Commands apply for a limited duration and the mod supports multiple being active at one time and "stacking" with each other. When a biter dies the mod evaluates all active command settings and the mod settings in a hierarchical manner to establish the correct current runtime settings.


Logic
-----

Each command will include:

- Duration: how long in seconds the command will be active for.
- Settings: one or more settings that this command includes values for. These settings will correspond to the mod's settings. While the mod setting values are restricted in range, command setting values can be at any scale of the correct type (i.e. integer) and the final result will be clamped to between 0% and 100%. This is to allow unusual streamer requirements.
- Priority: this commands hierarchical state during the evaluation for current runtime settings. Types are: Enforced, Base, Add.

When the mod is evaluating command and mod settings to identify the current runtime settings it follows the below logic. It reviews all active commands for inclusion of the current setting.

1. If any have the Enforced priority then only these commands contribute to the runtime value of the setting. All other non Enforced priority commands and the mod setting are ignored for this. If multiple commands have Enforced priority then the "widest" value will be used, i.e the lowest if the setting is a minimum and the largest if the setting is a maximum.
2. If any have the Base priority then these commands will set the base value of the setting, replacing the mod setting. Any Add priority commands will be applied on top of this. If multiple commands have Base priority then the "widest" value will be used, i.e the lowest if the setting is a minimum and the largest if the setting is a maximum.
3. If no command had Enforce or Base priority for this setting then the mod setting value will provide the base value.
4. All commands with the Add priority will be added to the base value. If these are negative values then they will be deducted. This allows multiple Add commands to apply their cumulative effect.
5. The final value for evolution and revive chance settings will be clamped between 0% and 100%. With duration min/max settings being prevented going below 0 seconds.

#### Exceptions

2 settings are exceptions to the above evaluation logic: `chanceFormula` and `delayText`

For these settings only the highest priority order active command will set the current value. If multiple commands are equally the highest priority one will be selected at random. This isn't deemed an issue as the concept of adding text strings together or finding the largest one doesn't make sense. Priority order is: enforced command, base command, mod setting, add command.


Syntax
------

Command name: `biter_revive_add_modifier`

Commands are provided with a single JSON argument with the below structure:

- duration = number of seconds the command will be active for (integer).
- settings = a table (dictionary) of setting name (string) and value (double). The setting names supported are:
  - evoMin = the evolution minimum required for reviving to start % as a number (double), i.e. 50 = 50% - equivalent to the mod setting "Evolution % minimum for reviving".
  - evoMax = the evolution maximum when the revive chance doesn't increase any more % as a number (double), i.e. 80 = 80% - equivalent to the mod setting "Evolution % for maximum reviving chance".
  - chanceBase = the revival chance % when at minimum evolution as a number (double), i.e. 5 = 5% - Equivalent of mod setting "Chance of revival starting %".
  - chancePerEvo = the revive chance % increase per evolution % up to the max evolution limit as a number (double), i.e. 2 = 2% - equivalent to the mod setting "Chance of revive % per evolution %".
  - chanceFormula = the revival chance formula as a text string - Equivalent of mod setting "Chance of revive formula". Note: this setting is an exception to the standard command evaluation logic.
  - delayMin = the revive delay minimum in seconds as a number (integer), i.e. 0 = 0 seconds - equivalent to the mod setting "Revive delay minimum seconds".
  - delayMax = the revive delay maximum in seconds as a number (integer), i.e. 5 = 5 seconds - equivalent to the mod setting "Revive delay maximum seconds".
  - delayText = the text to be shown above biters that are waiting their delay to revive, as a comma separated string list (string) - equivalent to the mod setting "Delayed revive text". Note: this setting is an exception to the standard command evaluation logic.
  - maxRevives = the maximum number of times a single unit can be revived (integer), with 0 being unlimited (nearly) - equivalent to the mod setting "Maximum revives per unit".
- priority = the priority for this command as a text string. Supported values "enforced", "base", "add".

#### Example Commands

These are provided as JSON strings and can be copy pasted straight into the Factorio console. If sending via RCON ensure you consider appropriate escaping of the quotes for your RCON integration tool.

1. Make biters revive in all cases for 1 minute and have zombie delay text, assuming there is no revive formula setting present in the mods usage:
   > `/biter_revive_add_modifier {"duration":60, "settings":{ "evoMin":0, "evoMax":100, "chanceBase":100, "chancePerEvo":0, "delayText":"uuggghh, raaaugh, blaaagh"}, "priority":"enforced"}`
2. Make biters have a base delayed revive time of between 1 and 2 minutes for 5 minutes, with any other runtime settings being applied still:
   > `/biter_revive_add_modifier {"duration":300, "settings":{ "delayMin":60, "delayMax":120}, "priority":"base"}`
3. Make biters 5% more likely to revive than the current runtime settings would be otherwise, for 3 minutes:
   > `/biter_revive_add_modifier {"duration":180, "settings":{ "chanceBase":5 }, "priority":"add"}`



Debug Command
=============

There is a debug command that will write out state data to assist with any issue debugging. It writes the state data to a file in the players Factorio script-data folder called "biter_revive_state_data.csv". It will overwrite any previous debug data file of the same name.

Command Name: `biter_revive_dump_state_data`
