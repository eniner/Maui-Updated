--[[ EQUI — HUD toggles for every module (auto-loaded; draws last). ]]

local mq = require('mq')
require('ImGui')

local Core

local function init(_Core)
    Core = _Core
end

local function render()
    -- Always available (even when zoning) so you can turn panels back on.
    ImGui.SetNextWindowPos(820, 620, ImGuiCond.FirstUseEver)
    ImGui.Begin('EQUI HUD##equi_menu', true, bit32.bor(ImGuiWindowFlags.AlwaysAutoResize, ImGuiWindowFlags.NoSavedSettings))

    ImGui.TextDisabled('Panels')
    ImGui.Separator()

    local order = Core.Modules.AUTOLOAD_ORDER
    for _, modName in ipairs(order) do
        if modName ~= 'menu' then
            local checked = Core.module_is_visible(modName)
            checked = ImGui.Checkbox(modName .. '##tog_' .. modName, checked)
            Core.set_module_visible(modName, checked)
        end
    end

    ImGui.Separator()
    if ImGui.SmallButton('All on##equi_all_on') then
        for _, modName in ipairs(order) do
            if modName ~= 'menu' then Core.set_module_visible(modName, true) end
        end
    end
    ImGui.SameLine()
    if ImGui.SmallButton('All off##equi_all_off') then
        for _, modName in ipairs(order) do
            if modName ~= 'menu' then Core.set_module_visible(modName, false) end
        end
    end

    ImGui.End()
end

local function unload()
end

return { init = init, render = render, unload = unload }
