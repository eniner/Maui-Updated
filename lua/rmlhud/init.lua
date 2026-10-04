--[[
  rmlhud - player vitals / target HUD rendered with RmlUi (MQ2RmlUi).

    /lua run rmlhud
    /rmlhud reload     re-read vitals.rml / rmlhud.rcss (live edit the files, then reload)
    /rmlhud debug      open the RmlUi visual debugger on this window (/rmlhud nodebug closes it)
    /rmlhud reset      move the window back to its default spot
    /rmlhud theme X    accent: azure, violet, ember, jade, rose
    /rmlhud stop       close the HUD
]]

local mq = require('mq')
local rmlui = require('rmlui')
local hud = require('rmlhud.hud')

local ctx, err = hud.open()
if not ctx then
    printf('\ar[rmlhud]\ax %s', err)
    return
end

local win = ctx.win
local DEFAULT = hud.default_pos()

mq.bind('/rmlhud', function(arg)
    arg = (arg or ''):lower()
    if arg == 'reload' then
        print(win:reload() and '\ag[rmlhud]\ax reloaded' or '\ar[rmlhud]\ax reload failed')
    elseif arg == 'debug' then
        win:debugger(true)
    elseif arg == 'nodebug' then
        win:debugger(false)
    elseif arg == 'reset' then
        win:place(DEFAULT.x, DEFAULT.y, DEFAULT.width, DEFAULT.height)
    elseif arg:match('^theme ') then
        win:theme(arg:sub(7))
    elseif arg == 'stop' then
        ctx.running = false
    else
        print('\at[rmlhud]\ax /rmlhud reload | debug | nodebug | reset | theme azure|violet|ember|jade|rose | stop')
    end
end)

local function cleanup()
    pcall(function() mq.unbind('/rmlhud') end)
    pcall(function() ctx:close() end)
    pcall(function() rmlui.close_all() end)
end

local ok, stopErr = pcall(function()
    while ctx.running and win:is_open() do
        ctx:process_events()
        ctx:tick()
        mq.delay(16)
    end
end)
if not ok and stopErr then print('[rmlhud] stop: ' .. tostring(stopErr)) end
cleanup()
