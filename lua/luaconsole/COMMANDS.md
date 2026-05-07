# LuaConsole Pro Command Guide

## Window / General

- `/luaconsole`
- `/lc`
  - Toggle LuaConsole Pro window.

- `/luahelp`
  - Print command help to console log.

- `/luaclear`
  - Clear output log.

- `/luadebug on|off`
  - Toggle internal debug logging.

- `/luats on|off`
  - Toggle timestamps in log output.

## REPL

- `/lua <code>`
  - Evaluate expression/chunk.

Chat fallback:
- `lua> <code>`
  - Evaluate from chat line.

History helpers:
- `/luaprev`
- `/luanext`

Session:
- `/luasave [path]`
- `/luaload [path]`

## Watches

- `/luawatch add "<expr>" "<label>"`
- `/luawatch add <expr>`
- `/luawatch del <id>`
- `/luawatch list`
- `/luawatch clear`
- `/luawatch export [path]`
- `/luawatch import [path]`

Examples:
- `/luawatch add "Me.PctHPs()" "My HP"`
- `/luawatch add "Target.Distance()" "Target Dist"`

## Triggers

- `/luatrigger add "<condition>" "<action>"`
- `/luatrigger add <condition> ;; <action>`
- `/luatrigger addc <cooldownSec> <condition> ;; <action>`
- `/luatrigger addcombat <condition> ;; <action>`
- `/luatrigger del <id>`
- `/luatrigger list`
- `/luatrigger clear`
- `/luatrigger export [path]`
- `/luatrigger import [path]`

Action shortcuts supported:
- `open console`
- `run snippet:Name`
- `run snippet 2`
- or raw Lua code

Examples:
- `/luatrigger add "Me.CombatState() == 'COMBAT'" "open console"`
- `/luatrigger add "Target.PctHPs() < 30" "print('burn now')"`

## Plots

- `/luaplot add "<expr>" ["<label>"] [samples]`
- `/luaplot del <id>`
- `/luaplot list`
- `/luaplot clear`

Examples:
- `/luaplot add "Me.PctMana()" "Mana" 300`
- `/luaplot add "Target.Distance()" "Range" 200`

## Inspect

- `/luainspect <expression>`
- `/luainspect me`
- `/luainspect target`
- `/luainspect cursor`
- `/luainspect groupavg`

Examples:
- `/luainspect Target.Buff(1)`
- `/luainspect mq.TLO.Window['ChatWindow'].Open()`

## Snippets

- `/luasnippet add <name> ;; <code>`
- `/luasnippet run <index>`
- `/luasnippet del <index>`
- `/luasnippet list`
- `/luasnippet clear`
- `/luasnippet export [path]`
- `/luasnippet import [path]`

Example:
- `/luasnippet add hpcheck ;; print(Me.PctHPs())`

## Bench / Profile

- `/luabench run "<code>" [iterations]`
- `/luabench last [iterations]`

- `/luaprofile [n]`
  - Execute current/last input repeatedly and profile average.

Examples:
- `/luabench run "for i=1,100 do local x=i*i end" 1000`
- `/luabench last 200`

## Share / Export

- `/luashare export [path]`
- `/luashare import [path]`

- `/luaexportlog [path]`

Share bundle includes watches, triggers, snippets, plots, and key UI prefs.

## Modes

- `/luamode combat`
- `/luamode merc`
- `/luamode nav`
- `/luamode repl`
- `/luamode monitor`

Applies layout/tab/top-ratio presets for common workflows.

## Macro Variable Bridge

- `/luavar sync <MacroVarName> [alias]`
- `/luavar unsync <id>`
- `/luavar list`
- `/luavar set <MacroVarName> <value>`

## Event Tester

- `/luaeventtest`
  - Run the current event tester handler.

## Persistence / Recovery Notes

- Autosave snapshots run periodically when enabled in Settings.
- On restart, a restore prompt appears if autosave snapshot exists.
- Per-character scoping affects all persistent files when enabled.
- Remote eval file polling can be enabled in Settings (`luaconsole_remote_eval.lua`).
