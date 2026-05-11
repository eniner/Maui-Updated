--[[ EQUI — Player vitals (auto-loaded). Replaces Player/Breath native windows when active. ]]

local mq = require('mq')
require('ImGui')

local Core

local function bar_w()
    local x = select(1, ImGui.GetContentRegionAvail())
    if type(x) ~= 'number' or x < 80 then return 220 end
    return x
end

local function hp_rgb(pct)
    if pct >= 0.60 then return 0.22, 0.82, 0.42 end
    if pct >= 0.40 then return 0.95, 0.85, 0.25 end
    if pct >= 0.20 then return 0.95, 0.55, 0.20 end
    return 0.92, 0.28, 0.28
end

local function init(_Core)
    Core = _Core
    mq.cmd('/hidewindow PlayerWindow')
    mq.cmd('/hidewindow BreathWindow')
end

local function render()
    if Core.State.get('gameState') ~= 'INGAME' or Core.State.get('isZoning') then return end
    if not Core.safe_tlo(function() return mq.TLO.Me() end, nil) then return end

    ImGui.SetNextWindowPos(16, 380, ImGuiCond.FirstUseEver)
    ImGui.Begin('EQUI Vitals##equi_vitals', true, ImGuiWindowFlags.NoSavedSettings)

    local name = Core.safe_tlo(function() return mq.TLO.Me.Name() end, '?')
    local lvl = Core.safe_tlo(function() return mq.TLO.Me.Level() end, 0)
    local cls = Core.safe_tlo(function() return mq.TLO.Me.Class.ShortName() end, '')
    ImGui.Text('%s   L%d %s', tostring(name), tonumber(lvl) or 0, tostring(cls))

    local hp = tonumber(Core.safe_tlo(function() return mq.TLO.Me.CurrentHPs() end, 0)) or 0
    local maxhp = tonumber(Core.safe_tlo(function() return mq.TLO.Me.MaxHPs() end, 1)) or 1
    local hpp = maxhp > 0 and (hp / maxhp) or 0
    local r, g, b = hp_rgb(hpp)
    if hpp < 0.20 then
        ImGui.PushStyleColor(ImGuiCol.Border, 0.95, 0.2, 0.2, 1)
    end
    ImGui.PushStyleColor(ImGuiCol.PlotHistogram, r, g, b, 1)
    ImGui.ProgressBar(hpp, bar_w(), 14, string.format('%d / %d', hp, maxhp))
    ImGui.PopStyleColor()
    if hpp < 0.20 then
        ImGui.PopStyleColor()
    end

    local sn = (tostring(cls or '')):upper()
    local nomana = sn == 'WAR' or sn == 'MNK' or sn == 'ROG' or sn == 'BER'
    if not nomana then
        local mana = tonumber(Core.safe_tlo(function() return mq.TLO.Me.CurrentMana() end, 0)) or 0
        local maxm = tonumber(Core.safe_tlo(function() return mq.TLO.Me.MaxMana() end, 1)) or 1
        local mp = maxm > 0 and (mana / maxm) or 0
        ImGui.PushStyleColor(ImGuiCol.PlotHistogram, 0.28, 0.52, 0.98, 1)
        ImGui.ProgressBar(mp, bar_w(), 14, string.format('%d / %d', mana, maxm))
        ImGui.PopStyleColor()
    end

    local ec = tonumber(Core.safe_tlo(function() return mq.TLO.Me.CurrentEndurance() end, 0)) or 0
    local em = tonumber(Core.safe_tlo(function() return mq.TLO.Me.MaxEndurance() end, 1)) or 1
    local ep = em > 0 and (ec / em) or 0
    ImGui.PushStyleColor(ImGuiCol.PlotHistogram, 0.96, 0.76, 0.28, 1)
    ImGui.ProgressBar(ep, bar_w(), 14, string.format('%d / %d', ec, em))
    ImGui.PopStyleColor()

    local xp = tonumber(Core.safe_tlo(function() return mq.TLO.Me.PctExp() end, 0)) or 0
    ImGui.ProgressBar(xp / 100, bar_w(), 12, string.format('XP %.3f%%', xp))

    local aa = tonumber(Core.safe_tlo(function() return mq.TLO.Me.PctAAExp() end, nil))
    if aa then
        ImGui.PushStyleColor(ImGuiCol.PlotHistogram, 0.93, 0.72, 0.28, 1)
        ImGui.ProgressBar(aa / 100, bar_w(), 12, string.format('AA XP %.3f%%', aa))
        ImGui.PopStyleColor()
    end

    local hpr = Core.safe_tlo(function() return mq.TLO.Me.HPRegen() end, nil)
    local mnr = Core.safe_tlo(function() return mq.TLO.Me.ManaRegen() end, nil)
    if hpr or mnr then
        ImGui.Separator()
        ImGui.TextDisabled('Regen  HP %s  Mana %s / tick', tostring(hpr or '—'), tostring(mnr or '—'))
    end

    ImGui.End()
end

local function unload()
    mq.cmd('/showwindow PlayerWindow')
    mq.cmd('/showwindow BreathWindow')
end

return { init = init, render = render, unload = unload }
