--[[
  Force-close known MQ2RmlUi windows left behind after /lua stop
  (when scripts had autoclose=false).

  /lua run rmlclose
]]

local rml = require('rmlui')

local NAMES = {
    'UEQLauncher',
    'ProEQHud',
    'SpawnWatchRml',
    'GodTierProgress',
    'GodTierTalents',
    'GMConsole',
    'Vitals',
    'RmlUiDemo',
}

local closed = 0
for _, name in ipairs(NAMES) do
    if rml.close(name) then
        closed = closed + 1
        print('[rmlclose] closed ' .. name)
    end
end

print(('[rmlclose] Closed %d window(s). Reload MQ2RmlUi if anything still sticks.'):format(closed))
