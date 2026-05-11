--[[ EQUI — Hotbar placeholder (auto-loaded). Does not hide EQ hotbars by default. ]]

local mq = require('mq')
require('ImGui')

local Core

local function init(_Core)
    Core = _Core
end

local function render()
    if Core.State.get('gameState') ~= 'INGAME' or Core.State.get('isZoning') then return end

    ImGui.SetNextWindowPos(340, 620, ImGuiCond.FirstUseEver)
    ImGui.Begin('EQUI Hotbar##equi_hotbar', true, bit32.bor(ImGuiWindowFlags.AlwaysAutoResize, ImGuiWindowFlags.NoSavedSettings))

    ImGui.TextDisabled('Custom hotbar — drag/edit/buttons coming.')
    for slot = 1, 6 do
        ImGui.PushID(slot)
        if ImGui.Button('##' .. slot, 36, 36) then
            print(('[EQUI] Hotbar slot %d — assign actions in module'):format(slot))
        end
        if slot < 6 then ImGui.SameLine() end
        ImGui.PopID()
    end

    ImGui.End()
end

local function unload()
end

return { init = init, render = render, unload = unload }
