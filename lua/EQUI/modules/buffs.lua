--[[ EQUI — Buffs + short buff stub (auto-loaded). ]]

local mq = require('mq')
require('ImGui')

local Core

local function init(_Core)
    Core = _Core
    mq.cmd('/hidewindow BuffWindow')
    mq.cmd('/hidewindow ShortDurationBuffWindow')
end

local function render()
    if Core.State.get('gameState') ~= 'INGAME' or Core.State.get('isZoning') then return end
    if not Core.safe_tlo(function() return mq.TLO.Me() end, nil) then return end

    ImGui.SetNextWindowPos(1180, 120, ImGuiCond.FirstUseEver)
    ImGui.SetNextWindowSize(260, 320, ImGuiCond.FirstUseEver)
    ImGui.Begin('EQUI Buffs##equi_buffs', true, bit32.bor(ImGuiWindowFlags.NoSavedSettings))

    local nb = tonumber(Core.safe_tlo(function() return mq.TLO.Me.CountBuffs() end, 0)) or 0
    ImGui.Text('Buffs: %d', nb)
    ImGui.Separator()

    ImGui.BeginChild('buff_sc', 0, 180, true)
    for i = 1, math.min(nb, 40) do
        local b = mq.TLO.Me.Buff(i)
        if Core.safe_tlo(function() return b and b() end, false) then
            local nm = Core.safe_tlo(function() return b.Name() end, '?')
            local dur = Core.safe_tlo(function() return b.Duration() end, nil)
            ImGui.BulletText('%s  (%s)', tostring(nm), dur ~= nil and tostring(dur) or '—')
        end
    end
    ImGui.EndChild()

    ImGui.TextDisabled('Short buffs / songs')
    ImGui.BeginChild('song_sc', 0, 70, true)
    ImGui.TextWrapped('Song rows — expand with Me.Song / bard iteration.')
    ImGui.EndChild()

    ImGui.End()
end

local function unload()
    mq.cmd('/showwindow BuffWindow')
    mq.cmd('/showwindow ShortDurationBuffWindow')
end

return { init = init, render = render, unload = unload }
