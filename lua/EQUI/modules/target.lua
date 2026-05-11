--[[ EQUI — Target panel (auto-loaded). ]]

local mq = require('mq')
require('ImGui')

local Core

local function con_rgb(name)
    local n = (name or ''):lower()
    if n:find('green') then return 0.35, 0.9, 0.45 end
    if n:find('blue') then return 0.45, 0.65, 1 end
    if n:find('light.?blue') or n:find('cyan') then return 0.5, 0.85, 1 end
    if n:find('yellow') then return 0.95, 0.9, 0.35 end
    if n:find('red') then return 0.95, 0.35, 0.35 end
    return 0.92, 0.94, 0.97
end

local function init(_Core)
    Core = _Core
    mq.cmd('/hidewindow TargetWindow')
end

local function render()
    if Core.State.get('gameState') ~= 'INGAME' or Core.State.get('isZoning') then return end

    ImGui.SetNextWindowPos(360, 28, ImGuiCond.FirstUseEver)
    ImGui.SetNextWindowSize(340, 160, ImGuiCond.FirstUseEver)
    ImGui.Begin('EQUI Target##equi_target', true, ImGuiWindowFlags.NoSavedSettings)

    local tid = tonumber(Core.safe_tlo(function() return mq.TLO.Target.ID() end, 0)) or 0
    local has = mq.TLO.Target() and tid > 0

    if not has then
        ImGui.TextDisabled('No Target')
        ImGui.End()
        return
    end

    local clean = Core.safe_tlo(function() return mq.TLO.Target.CleanName() end, '?')
    local con = Core.safe_tlo(function() return mq.TLO.Target.ConColor() end, '')
    local r, g, b = con_rgb(tostring(con))
    ImGui.TextColored(r, g, b, 1, '%s', tostring(clean))

    local tl = Core.safe_tlo(function() return mq.TLO.Target.Level() end, '')
    local tc = Core.safe_tlo(function() return mq.TLO.Target.Class.Name() end, '')
    ImGui.TextDisabled('L%s  %s', tostring(tl), tostring(tc))

    local gld = Core.safe_tlo(function() return mq.TLO.Target.Guild() end, '')
    if gld and tostring(gld) ~= '' then
        ImGui.TextDisabled('< %s >', tostring(gld))
    end

    local pct = tonumber(Core.safe_tlo(function() return mq.TLO.Target.PctHPs() end, 0)) or 0
    local typ = Core.safe_tlo(function() return mq.TLO.Target.Type() end, '')
    local hp_txt
    if typ == 'PC' then
        local ch = tonumber(Core.safe_tlo(function() return mq.TLO.Target.CurrentHPs() end, 0)) or 0
        local mh = tonumber(Core.safe_tlo(function() return mq.TLO.Target.MaxHPs() end, 1)) or 1
        hp_txt = string.format('%d / %d  (%.0f%%)', ch, mh, pct)
    else
        hp_txt = string.format('%.0f%%', pct)
    end
    local hr = pct >= 60 and 0.22 or (pct >= 25 and 0.95 or 0.92)
    local hg = pct >= 60 and 0.82 or (pct >= 25 and 0.55 or 0.28)
    local hb = pct >= 60 and 0.42 or (pct >= 25 and 0.2 or 0.28)
    ImGui.PushStyleColor(ImGuiCol.PlotHistogram, hr, hg, hb, 1)
    ImGui.ProgressBar(pct / 100, select(1, ImGui.GetContentRegionAvail()) > 80 and select(1, ImGui.GetContentRegionAvail()) or 280, 14, hp_txt)
    ImGui.PopStyleColor()

    local dist = tonumber(Core.safe_tlo(function() return mq.TLO.Target.Distance() end, 0)) or 0
    if dist > 200 then
        ImGui.TextColored(0.95, 0.35, 0.35, 1, 'Distance %.1f', dist)
    else
        ImGui.Text('Distance %.1f', dist)
    end

    local cast = Core.safe_tlo(function() return mq.TLO.Target.Casting.Name() end, nil)
    if cast and cast ~= '' then
        ImGui.TextDisabled('Casting: %s', tostring(cast))
    end

    local tot = mq.TLO.Target.TargetOfTarget()
    if tot and Core.safe_tlo(function() return mq.TLO.Target.TargetOfTarget.ID() end, 0) ~= 0 then
        local sid = tonumber(Core.safe_tlo(function() return mq.TLO.Me.ID() end, 0)) or 0
        local totid = tonumber(Core.safe_tlo(function() return mq.TLO.Target.TargetOfTarget.ID() end, 0)) or 0
        if totid ~= sid then
            ImGui.Separator()
            ImGui.Text('ToT: %s', tostring(Core.safe_tlo(function() return mq.TLO.Target.TargetOfTarget.CleanName() end, '?')))
            local tp = tonumber(Core.safe_tlo(function() return mq.TLO.Target.TargetOfTarget.PctHPs() end, 0)) or 0
            ImGui.ProgressBar(tp / 100, select(1, ImGui.GetContentRegionAvail()) > 80 and select(1, ImGui.GetContentRegionAvail()) or 280, 10, string.format('%.0f%%', tp))
        end
    end

    ImGui.End()
end

local function unload()
    mq.cmd('/showwindow TargetWindow')
end

return { init = init, render = render, unload = unload }
