--[[
  UltimateInv — standalone inventory overlay for MacroQuest (Lua + ImGui).

  Independent source tree; does not bundle EZInventory.

  Run:    /lua run UltimateInv
  Toggle: /uinv
  Quit:   /uinvquit
]]

local mq = require('mq')

local snapshot_mod = require('UltimateInv.core.snapshot')
local me_profile = require('UltimateInv.core.me_profile')
local dash = require('UltimateInv.ui.dashboard')

local SCRIPT_ID = 'UltimateInv'

local app = {
    mq = mq,
    running = true,
    visible = true,
    win_open = true,
    include_bank = true,
    search_buf = '',
    anim_items = mq.FindTextureAnimation('A_DragItem'),
    anim_box = mq.FindTextureAnimation('A_RecessedBox'),
    icon_offset = snapshot_mod.EQ_ICON_OFFSET,
    _snap_cache = nil,
    _snap_at = 0,
    _snap_bank = nil,
    _prof_cache = nil,
    _prof_at = 0,
}

local SNAP_MS = 300
local PROFILE_MS = 220

local function now_ms()
    if mq.gettime then
        local ok, t = pcall(mq.gettime)
        if ok and type(t) == 'number' then return t end
    end
    return math.floor(os.clock() * 1000)
end

function app.get_snapshot()
    local t = now_ms()
    if app._snap_cache and app._snap_bank == app.include_bank and (t - app._snap_at) < SNAP_MS then
        return app._snap_cache
    end
    app._snap_cache = snapshot_mod.build(mq, { include_bank = app.include_bank })
    app._snap_bank = app.include_bank
    app._snap_at = t
    return app._snap_cache
end

function app.get_profile()
    local t = now_ms()
    if app._prof_cache and (t - app._prof_at) < PROFILE_MS then
        return app._prof_cache
    end
    app._prof_cache = me_profile.build(mq)
    app._prof_at = t
    return app._prof_cache
end

local function on_gui()
    dash.render(app)
end

mq.bind('/uinvquit', function()
    app.running = false
end)

mq.bind('/uinv', function()
    app.visible = not app.visible
    if app.visible then
        app.win_open = true
    end
    app._snap_cache = nil
    app._prof_cache = nil
end)

mq.imgui.init(SCRIPT_ID, on_gui)

print('\ag[UltimateInv]\ax Loaded (single window, no tabs). \at/uinv\ax toggle  \at/uinvquit\ax stop.')

while app.running do
    mq.delay(0)
    if mq.doevents then mq.doevents() end
end

pcall(function() mq.imgui.destroy(SCRIPT_ID) end)
mq.exit()
