--[[ EQUI — Inventory overview (auto-loaded). Does not hide native inventory. ]]

local mq = require('mq')
require('ImGui')

local Core

local function init(_Core)
    Core = _Core
end

local function render()
    if Core.State.get('gameState') ~= 'INGAME' or Core.State.get('isZoning') then return end
    if not Core.safe_tlo(function() return mq.TLO.Me() end, nil) then return end

    ImGui.SetNextWindowPos(720, 220, ImGuiCond.FirstUseEver)
    ImGui.SetNextWindowSize(280, 200, ImGuiCond.FirstUseEver)
    ImGui.Begin('EQUI Inventory##equi_inv', true, ImGuiWindowFlags.NoSavedSettings)

    local free = Core.safe_tlo(function() return mq.TLO.Me.FreeInventory() end, nil)

    local pp = tonumber(Core.safe_tlo(function() return mq.TLO.Me.Platinum() end, 0)) or 0
    local gg = tonumber(Core.safe_tlo(function() return mq.TLO.Me.Gold() end, 0)) or 0
    local ss = tonumber(Core.safe_tlo(function() return mq.TLO.Me.Silver() end, 0)) or 0
    local cc = tonumber(Core.safe_tlo(function() return mq.TLO.Me.Copper() end, 0)) or 0

    ImGui.Text('Free bag slots: %s', free ~= nil and tostring(free) or '—')
    ImGui.Separator()
    ImGui.Text('%d pp  %dg  %ds  %dc', pp, gg, ss, cc)
    ImGui.Separator()
    ImGui.TextWrapped('Bag grid / gear paper-doll — extend with InvSlot + item tooltips.')

    ImGui.End()
end

local function unload()
end

return { init = init, render = render, unload = unload }
