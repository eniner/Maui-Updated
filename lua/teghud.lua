--[[
  teghud — combat HUD EQ's XML cannot draw (RmlUi via rmlhud).

  /lua run teghud
  /teghud            toggle HUD visibility
  /teghud hideeq     close native player / target / buff windows
  /teghud showeq     open them again
  /teghud quit
]]

local mq = require('mq')
local hud = require('rmlhud.hud')
local rmlui = require('rmlui')

local running = true
local visible = true

local function hide_eq(hide)
    local cmd = hide and 'close' or 'open'
    for _, w in ipairs({
        'PlayerWindow', 'TargetWindow', 'BuffWindow',
        'ShortDurationBuffWindow', 'ExtendedTargetWindow',
    }) do
        pcall(function() mq.cmdf('/windowstate %s %s', w, cmd) end)
    end
end

local ctx, err = hud.open()
if not ctx then
    printf('\ar[teghud]\ax %s', err)
    return
end

local win = ctx.win

local function cmd(...)
    local a = tostring(select(1, ...) or ''):lower()
    if a == 'quit' or a == 'exit' then
        running = false
        ctx.running = false
        return
    end
    if a == 'hideeq' then
        hide_eq(true)
        return
    end
    if a == 'showeq' then
        hide_eq(false)
        return
    end
    visible = not visible
end

mq.bind('/teghud', cmd)
hide_eq(true)
mq.cmd('/echo [teghud] combat HUD up.  /teghud   /teghud hideeq   /teghud quit')

local function cleanup()
    pcall(function() mq.unbind('/teghud') end)
    pcall(function() ctx:close() end)
    pcall(function() rmlui.close_all() end)
    mq.cmd('/echo [teghud] stopped.')
end

local ok, err = pcall(function()
    while running and ctx.running and win:is_open() do
        ctx:process_events()
        win:show(visible)
        if visible then
            ctx:tick()
        end
        mq.delay(16)
    end
end)
if not ok and err then print('[teghud] stop: ' .. tostring(err)) end
cleanup()
