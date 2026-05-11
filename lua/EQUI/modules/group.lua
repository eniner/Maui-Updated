--[[ EQUI — Group window (auto-loaded). ]]

local mq = require('mq')
require('ImGui')

local Core

local function init(_Core)
    Core = _Core
    mq.cmd('/hidewindow GroupWindow')
end

local function render()
    if Core.State.get('gameState') ~= 'INGAME' or Core.State.get('isZoning') then return end

    ImGui.SetNextWindowPos(16, 200, ImGuiCond.FirstUseEver)
    ImGui.SetNextWindowSize(260, 180, ImGuiCond.FirstUseEver)
    ImGui.Begin('EQUI Group##equi_group', true, ImGuiWindowFlags.NoSavedSettings)

    if not mq.TLO.Group() then
        ImGui.TextDisabled('Not grouped')
        ImGui.End()
        return
    end

    local leader = Core.safe_tlo(function() return mq.TLO.Group.Leader() end, '')
    local n = tonumber(Core.safe_tlo(function() return mq.TLO.Group.Members() end, 0)) or 0

    for i = 0, n do
        local mem = mq.TLO.Group.Member(i)
        if mem and Core.safe_tlo(function() return mem() end, false) and Core.safe_tlo(function() return mem.Present() end, false) then
            local nm = Core.safe_tlo(function() return mem.Name() end, '?')
            local isMerc = Core.safe_tlo(function() return mem.Mercenary() end, false)
            local row = tostring(nm)
            if leader and tostring(leader) == tostring(nm) then
                row = '* ' .. row
            end
            if isMerc then
                ImGui.TextDisabled('%s  [MERC]', row)
            else
                ImGui.Text('%s', row)
            end
            local pct = tonumber(Core.safe_tlo(function() return mem.PctHPs() end, 0)) or 0
            local r = pct >= 50 and 0.22 or (pct >= 25 and 0.95 or 0.92)
            local g = pct >= 50 and 0.82 or (pct >= 25 and 0.55 or 0.28)
            local b = pct >= 50 and 0.42 or (pct >= 25 and 0.2 or 0.28)
            ImGui.PushStyleColor(ImGuiCol.PlotHistogram, r, g, b, 1)
            ImGui.ProgressBar(pct / 100, select(1, ImGui.GetContentRegionAvail()) > 60 and select(1, ImGui.GetContentRegionAvail()) or 220, 12, string.format('%.0f%%', pct))
            ImGui.PopStyleColor()
            ImGui.Spacing()
        end
    end

    ImGui.End()
end

local function unload()
    mq.cmd('/showwindow GroupWindow')
end

return { init = init, render = render, unload = unload }
