--[[
  EQUI — MacroQuest Lua + ImGui overlay framework.

  Run in-game:  /lua run EQUI
  Commands:     /equi help

  Loads `ui_core`, then autoloads every module under lua/EQUI/modules/ (vitals, target, buffs, …).
  Toggle the readme shell: /equi core   Toggle panels: window "EQUI HUD".
]]

local Core = require('EQUI.ui_core')
Core.start()
