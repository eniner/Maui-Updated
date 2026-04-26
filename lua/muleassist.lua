local mq = require('mq')

local entry = string.format('%s/muleassist/init.lua', mq.luaDir)
local chunk, err = loadfile(entry)
if not chunk then
    error(string.format('Failed to load muleassist entrypoint: %s', tostring(err)))
end

return chunk(...)
