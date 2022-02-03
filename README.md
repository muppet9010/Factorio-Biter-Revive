# Factorio-Biter-Revive

Any biter that dies will have a chance to revive back to life based on mod settings and temporary settings from RCON commands. The mod is focused on facilitating streamer integrations and so uses a layered settings approach, but can be used standalone using mod settings alone.

The chance of the revival is based on a configurable scale driven by the enemy force's evolution. With various configurable options controlling revive delay



Notes
-----

- Any "unit" entity that breathes air is included in the revive logic by default. This will include all vanilla Factorio biters and I assume modded enemies as well.
- There is a mod setting to exclude prototype names from ever reviving, with compilatron included by default. There is also a mod setting to exclude specific force's from ever reviving.
- Revive chance is a scale based on configurable settings using a min and max evolution range for a min and max revive chance. This should allow any desired effect to be achieved.
- Multiple times a second the biters awaiting reviving will be processed and up to the maximum (max revives per second mod setting) performed. This is done to both allow an optional delay in reviving and to avoid loops of biters being revived and instantly dieing.
- Revives have a random delay between configurable min and max seconds from 0 upwards. To avoid infinite revive/death loops a 0 second revive won't happen the moment the biter dies, but instead a fraction of a second later.



Revive Chance Formula
---------------------

This is a special setting for when you want nonlinear revive chance growth in relation to evolution. When the default value of the setting is blank/empty then the simpler "Chance of revive % per evolution %" setting value will be used by the mod. When the formula setting is populated it will take priority over the simpler setting.

The formula must be valid Lua written as suitable for use after the keyword "return" and will be run within the mod. The biter's force evolution above the minimum runtime setting will be passed in as a Lua variable "evo" as a numeric value of the evolution percentage. So if the minimum is 70 (%) and the biters force evo is 72 (%) the "evo" variable will have a value of 2.

Example of valid formula string:    `evo * 1.5`



RCON Command
------------

The command concept is designed as a highly flexible way of applying setting values and modifiers. Commands apply for a limited duration and the mod supports multiple being active at one time and "stacking" with each other. When a biter dies the mod evaluates all active command settings and the mod settings in a hierarchical manner to establish the correct current runtime settings.

Each command will include:

- Duration: how long in seconds the command will be active for.
- Settings: one or more settings that this command includes values for. These settings will correspond to the mod's settings. While the mod setting values are restricted in range, command setting values can be at any scale of the correct type (i.e. integer) and the final result will be clamped to between 0% and 100%. This is to allow unusual streamer requirements.
- Priority: this commands hierarchical state during the evaluation for current runtime settings. Types are: Enforced, Base, Add.

When the mod is evaluating command and mod settings to identify the current runtime settings it follows the below logic. It reviews all active commands for inclusion of the current setting, with the exception of the "chanceFormula" setting (see its command setting for details).

1. If any have the Enforced priority then only these commands contribute to the runtime value of the setting. All other non Enforced priority commands and the mod setting are ignored for this. If multiple commands have Enforced priority then the "widest" value will be used, i.e the lowest if the setting is a minimum and the largest if the setting is a maximum.
2. If any have the Base priority then these commands will set the base value of the setting, replacing the mod setting. Any Add priority commands will be applied on top of this. If multiple commands have Base priority then the "widest" value will be used, i.e the lowest if the setting is a minimum and the largest if the setting is a maximum.
3. If no command had Enforce or Base priority for this setting then the mod setting value will provide the base value.
4. All commands with the Add priority will be added to the base value. If these are negative values then they will be deducted. This allows multiple Add commands to apply their cumulative effect.
5. The final value for evolution and revive chance settings will be clamped between 0% and 100%. With duration min/max settings being prevented going below 0 seconds.

Command name: biter_revive_add_modifier

Commands are provided with a single JSON argument with the below structure:

- duration = number of seconds the command will be active for (integer).
- settings = a table (dictionary) of setting name (string) and value (double). The setting names supported are:
  - evoMin = the evolution minimum required for reviving to start % as a number (double), i.e. 50 = 50% - equivalent to the mod setting "Evolution % minimum for reviving".
  - evoMax = the evolution maximum when the revive chance doesn't increase any more % as a number (double), i.e. 80 = 80% - equivalent to the mod setting "Evolution % for maximum reviving chance".
  - chanceBase = the revive chance % when at minimum evolution as a number (double), i.e. 5 = 5% - Equivalent of mod setting "Chance of revival starting %".
  - chancePerEvo = the revive chance % increase per evolution % up to the max evolution limit as a number (double), i.e. 2 = 2% - equivalent to the mod setting "Chance of revive % per evolution %".
  - chanceFormula = the revival chance formula as a text string. - Equivalent of mod setting "Chance of revive formula". NOTE: only a single active command of the highest priority order will set the formula. The exact applied highest priority command will be random due to internal Lua table ordering. This isn't deemed an issue as the concept of adding raw formulas together or finding the largest formula in a mod wide abstract way doesn't make sense. Priority order is: enforced command, base command, mod setting, add command.
  - delayMin = the revive delay minimum in seconds as a number (integer), i.e. 0 = 0 seconds - equivalent to the mod setting "Revive delay minimum seconds".
  - delayMax = the revive delay maximum in seconds as a number (integer), i.e. 5 = 5 seconds - equivalent to the mod setting "Revive delay maximum seconds".
- priority = the priority for this command as a text string. Supported values "enforced", "base", "add".

Example Commands with their JSON string:

1. Make biters revive in all cases for 1 minute, assuming there is no revive formula setting present in the mods usage:
   > `/biter_revive_add_modifier {"duration":60, "settings":{ "evoMin":0, "evoMax":100, "chanceBase":100, "chancePerEvo":0}, "priority":"enforced"}`
2. Make biters have a base delayed revive time of between 1 and 2 minutes for 5 minutes, with any other runtime settings being applied still:
   > `/biter_revive_add_modifier {"duration":300, "settings":{ "delayMin":60, "delayMax":120}, "priority":"base"}`
3. Make biters 5% more likely to revive than the current runtime settings would be otherwise, for 3 minutes:
   > `/biter_revive_add_modifier {"duration":180, "settings":{ "chanceBase":5 }, "priority":"add"}`


Debug Command
-------------

There is a debug command that will write out state data to assist with any issue debugging. It writes the state data to a file in the players Factorio script-data folder called "biter_revive_state_data.csv". It will overwrite any previous debug data file of the same name.

Command Name: `biter_revive_dump_state_data`



Future Ideas
------------

- Mod setting for max revives per unit. Avoid infinitely reviving the same biter every tick. Not needed in commands. Does require getting unit_number of each entity scheduled for revival and tracking forwards into new unit_number and checking each dead entity to tidy up the table if it's not chosen for a repeat revival.
- Mod setting for zzz (configurable text) floating text over units delayed for reviving when they are delayed for more than 2 (test this looks right) seconds.
- The parsing through commands full data is quite inefficient, although very natural data structure. If it causes any UPS issues then look at storing command setting values by setting name and priority so that parsing them is very light weight. Will be more complicated code for command creation and removal though.
- Track biters marked for reviving corpses so we can remove them when the biter revives. Would need to monitor additional events to populate the corpse list and link the 2 events together.
