--[[
  UltimateInv — compact dark theme for standalone ImGui windows.
]]

local ImGui = require('ImGui')

local T = {}

T.BG_DEEP     = 0xFF0C0E14
T.BG_PANEL    = 0xFF13161D
T.BORDER      = 0xFF252A38
T.TEXT_MAIN   = 0xFFE8ECF4
T.TEXT_DIM    = 0xFF7C8498
T.TEXT_MUTED  = 0xFF7C8498
T.ACCENT      = 0xFF6E9FCC
T.ACCENT_GOLD = 0xFFE8C76A

function T.rgba_u32(hex)
    hex = hex % 0x100000000
    local a = bit32.rshift(hex, 24) / 255
    local r = bit32.band(bit32.rshift(hex, 16), 0xFF) / 255
    local g = bit32.band(bit32.rshift(hex, 8), 0xFF) / 255
    local b = bit32.band(hex, 0xFF) / 255
    return r, g, b, a
end

function T.push_window()
    do local r, g, b, a = T.rgba_u32(T.BG_DEEP)  ImGui.PushStyleColor(ImGuiCol.WindowBg, r, g, b, a) end
    do local r, g, b, a = T.rgba_u32(T.BG_PANEL) ImGui.PushStyleColor(ImGuiCol.ChildBg, r, g, b, a) end
    do local r, g, b, a = T.rgba_u32(T.BORDER)   ImGui.PushStyleColor(ImGuiCol.Border, r, g, b, a) end
    do local r, g, b, a = T.rgba_u32(T.BG_PANEL) ImGui.PushStyleColor(ImGuiCol.FrameBg, r, g, b, a) end
    do local r, g, b, a = T.rgba_u32(T.TEXT_MAIN) ImGui.PushStyleColor(ImGuiCol.Text, r, g, b, a) end
end

function T.pop_window()
    ImGui.PopStyleColor(5)
end

--- Stronger frame for full-screen-style dashboard.
function T.push_dashboard()
    local R = 10
    ImGui.PushStyleVar(ImGuiStyleVar.WindowRounding, R)
    ImGui.PushStyleVar(ImGuiStyleVar.FrameRounding, 6)
    ImGui.PushStyleVar(ImGuiStyleVar.CellPadding, 7, 5)
    ImGui.PushStyleVar(ImGuiStyleVar.ItemSpacing, 5, 6)
    ImGui.PushStyleVar(ImGuiStyleVar.WindowPadding, 10, 8)
    do local r, g, b, a = T.rgba_u32(T.BG_DEEP)    ImGui.PushStyleColor(ImGuiCol.WindowBg, r, g, b, a) end
    do local r, g, b, a = T.rgba_u32(0xFF141824)    ImGui.PushStyleColor(ImGuiCol.ChildBg, r, g, b, a) end
    do local r, g, b, a = T.rgba_u32(0xFF2A3142)    ImGui.PushStyleColor(ImGuiCol.Border, r, g, b, a) end
    do local r, g, b, a = T.rgba_u32(0xFF1A2030)    ImGui.PushStyleColor(ImGuiCol.FrameBg, r, g, b, a) end
    do local r, g, b, a = T.rgba_u32(T.TEXT_MAIN)    ImGui.PushStyleColor(ImGuiCol.Text, r, g, b, a) end
end

function T.pop_dashboard()
    ImGui.PopStyleColor(5)
    ImGui.PopStyleVar(5)
end

return T
