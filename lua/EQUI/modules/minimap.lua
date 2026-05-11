--[[ EQUI — Minimap stub (auto-loaded). Full mq2map integration optional. ]]

local mq = require('mq')
require('ImGui')

local Core

local function map_plugin_loaded()
    return Core.safe_tlo(function()
        local p = mq.TLO.Plugin('mq2map')
        if p and p.IsLoaded then return p.IsLoaded() end
        local q = mq.TLO.Plugin('MQ2Map')
        if q and q.IsLoaded then return q.IsLoaded() end
        return false
    end, false)
end

local function init(_Core)
    Core = _Core
end

local function render()
    if Core.State.get('gameState') ~= 'INGAME' or Core.State.get('isZoning') then return end

    ImGui.SetNextWindowPos(1120, 28, ImGuiCond.FirstUseEver)
    ImGui.SetNextWindowSize(200, 220, ImGuiCond.FirstUseEver)
    ImGui.Begin('EQUI Map##equi_map', true, ImGuiWindowFlags.NoSavedSettings)

    local zn = Core.safe_tlo(function() return mq.TLO.Zone.ShortName() end, '?')
    ImGui.TextDisabled('%s', tostring(zn))

    local draw = ImGui.GetWindowDrawList()
    local sx, sy = ImGui.GetCursorScreenPos()
    local cx = sx + 90
    local cy = sy + 85
    local center = ImVec2(cx, cy)
    draw:AddCircleFilled(center, 72, ImGui.GetColorU32(0.06, 0.07, 0.12, 0.85), 48)
    draw:AddCircle(center, 72, ImGui.GetColorU32(0.35, 0.45, 0.55, 0.9), 48, 2)
    draw:AddCircleFilled(center, 4, ImGui.GetColorU32(1, 1, 1, 1), 12)

    local head = tonumber(Core.safe_tlo(function() return mq.TLO.Me.Heading() end, 0)) or 0
    local rad = math.rad((head % 360) - 90)
    local ax = cx + math.cos(rad) * 28
    local ay = cy + math.sin(rad) * 28
    draw:AddLine(center, ImVec2(ax, ay), ImGui.GetColorU32(0.95, 0.85, 0.35, 1), 3)

    ImGui.Dummy(180, 170)

    if map_plugin_loaded() then
        ImGui.TextDisabled('mq2map loaded — spawn dots next.')
    else
        ImGui.TextColored(0.95, 0.55, 0.35, 1, 'mq2map not loaded')
    end

    ImGui.End()
end

local function unload()
end

return { init = init, render = render, unload = unload }
