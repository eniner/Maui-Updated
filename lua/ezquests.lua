local mq = require('mq')

local script_path = mq.luaDir .. '/EZQuests-main/EZQuests-main/init.lua'
local chunk, err = loadfile(script_path)

if not chunk then
    printf('[EZQuests] Failed to load %s: %s', script_path, tostring(err))
    return
end

return chunk(...)
