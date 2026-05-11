--[[ EQUI — Combat feed stub (auto-loaded). Chat stays visible; overlay only. ]]

local mq = require('mq')
require('ImGui')

local Core

local lines = {}
local max_lines = 80

local function push_line(s)
    lines[#lines + 1] = tostring(s)
    while #lines > max_lines do
        table.remove(lines, 1)
    end
end

local function init(_Core)
    Core = _Core
    push_line('[EQUI] Combat overlay ready — wire mq.event patterns next.')
end

local function render()
    if Core.State.get('gameState') ~= 'INGAME' then return end

    ImGui.SetNextWindowPos(560, 340, ImGuiCond.FirstUseEver)
    ImGui.SetNextWindowSize(420, 220, ImGuiCond.FirstUseEver)
    ImGui.Begin('EQUI Combat##equi_combat', true, ImGuiWindowFlags.NoSavedSettings)

    ImGui.BeginChild('clog', 0, 0, true)
    for _, ln in ipairs(lines) do
        ImGui.TextWrapped('%s', ln)
    end
    ImGui.EndChild()

    ImGui.End()
end

local function unload()
end

return { init = init, render = render, unload = unload }
