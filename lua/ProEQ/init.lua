--[[ ProEQ entry — forwards to UltimateEQ RmlUi HUD; saves stay in lua/ProEQ/ ]]

local mq = require('mq')

local dir = (debug.getinfo(1, 'S').source:gsub('^@', ''):match('^(.*[\\/])')) or ''
_G.UEQ_DATA_DIR = dir

dofile(mq.luaDir .. '/UltimateEQ/init.lua')
