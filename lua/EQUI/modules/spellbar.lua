--[[ EQUI — Spell gems + cast bar stub (auto-loaded). ]]

local mq = require('mq')
require('ImGui')

local Core

local function init(_Core)
    Core = _Core
    mq.cmd('/hidewindow CastingWindow')
end

local function render()
    if Core.State.get('gameState') ~= 'INGAME' or Core.State.get('isZoning') then return end
    if not Core.safe_tlo(function() return mq.TLO.Me() end, nil) then return end

    ImGui.SetNextWindowPos(340, 520, ImGuiCond.FirstUseEver)
    ImGui.Begin('EQUI Spellbar##equi_spellbar', true, bit32.bor(ImGuiWindowFlags.AlwaysAutoResize, ImGuiWindowFlags.NoSavedSettings))

    local cast = Core.safe_tlo(function() return mq.TLO.Me.Casting.Name() end, nil)
    if cast and tostring(cast) ~= '' then
        ImGui.TextColored(0.6, 0.85, 1, 1, 'Casting: %s', tostring(cast))
        local pct = Core.safe_tlo(function()
            local c = mq.TLO.Me.Casting
            if c and c.PctCastTime then return c.PctCastTime() end
            return nil
        end, nil)
        pct = tonumber(pct)
        if pct then
            ImGui.ProgressBar(pct / 100, 280, 16, string.format('%d%%', math.floor(pct)))
        end
        ImGui.Separator()
    end

    local ng = tonumber(Core.safe_tlo(function() return mq.TLO.Me.NumGems() end, 8)) or 8
    ImGui.TextDisabled('%d gems', ng)

    for i = 1, ng do
        local gem = mq.TLO.Me.Gem(i)
        local ok_slot = Core.safe_tlo(function() return gem and gem() end, false)
        local spell = ok_slot and Core.safe_tlo(function() return gem.Name() end, '') or ''
        ImGui.PushID(i)
        if ImGui.SmallButton(string.format('%d##gem', i)) then
            mq.cmd(string.format('/cast %d', i))
        end
        ImGui.SameLine()
        ImGui.TextWrapped('%s', spell ~= '' and spell or '(empty)')
        ImGui.PopID()
    end

    ImGui.End()
end

local function unload()
    mq.cmd('/showwindow CastingWindow')
end

return { init = init, render = render, unload = unload }
