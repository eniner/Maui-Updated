--[[
  GearScoreX — Obsidian Forge theme (MacroQuest ImGui).
  AARRGGBB palette + PushStyle helpers.

  Test checklist:
  [ ] theme.push_obsidian_frame / pop_obsidian_frame — balanced stacks (no leak).
]]

local ImGui = require('ImGui')

local theme = {}

theme.BACKGROUND_DEEP    = 0xFF0A0C10
theme.BACKGROUND_PANEL   = 0xFF111318
theme.BACKGROUND_ROW_ALT = 0xFF0F1115
theme.BACKGROUND_HOVER   = 0xFF1C2030
theme.BORDER_SUBTLE      = 0xFF1E2330
theme.BORDER_ACCENT      = 0xFF3D5A3E

theme.SCORE_EXCELLENT    = 0xFF4FC67A
theme.SCORE_GOOD         = 0xFF4A9ECC
theme.SCORE_AVERAGE      = 0xFFD4943A
theme.SCORE_POOR         = 0xFFB03A3A

theme.DELTA_UPGRADE      = 0xFF5AD67A
theme.DELTA_DOWNGRADE    = 0xFFD65A5A
theme.DELTA_NEUTRAL      = 0xFF8A8FA0

theme.TEXT_PRIMARY       = 0xFFE2E8F0
theme.TEXT_SECONDARY     = 0xFF6B7585
theme.TEXT_ACCENT        = 0xFFD4A84A
theme.TEXT_HIGHLIGHT     = 0xFFFFFFFF

theme.CANDIDATE_BADGE    = 0xFF2A3D5C

theme.BREAKDOWN_OFFENSE  = 0xFFD44A4A
theme.BREAKDOWN_DEFENSE  = 0xFF4A7FCC
theme.BREAKDOWN_UTILITY  = 0xFF4ACC8A

function theme.u32(hex)
    hex = hex % 0x100000000
    local a = bit32.rshift(hex, 24) / 255
    local r = bit32.band(bit32.rshift(hex, 16), 0xFF) / 255
    local g = bit32.band(bit32.rshift(hex, 8), 0xFF) / 255
    local b = bit32.band(hex, 0xFF) / 255
    return ImGui.GetColorU32(r, g, b, a)
end

function theme.rgba(hex)
    hex = hex % 0x100000000
    local a = bit32.rshift(hex, 24) / 255
    local r = bit32.band(bit32.rshift(hex, 16), 0xFF) / 255
    local g = bit32.band(bit32.rshift(hex, 8), 0xFF) / 255
    local b = bit32.band(hex, 0xFF) / 255
    return r, g, b, a
end

--- Score tier 0–100 (slot rating).
function theme.scoreTierColor(rating)
    local r = tonumber(rating) or 0
    if r >= 80 then return theme.SCORE_EXCELLENT end
    if r >= 60 then return theme.SCORE_GOOD end
    if r >= 40 then return theme.SCORE_AVERAGE end
    return theme.SCORE_POOR
end

local STYLE_COLOR_COUNT = 16

local function sc(hex)
    local r, g, b, a = theme.rgba(hex)
    return r, g, b, a
end

function theme.push_obsidian_frame()
    do local r, g, b, a = sc(theme.BACKGROUND_DEEP)    ImGui.PushStyleColor(ImGuiCol.WindowBg, r, g, b, a) end
    do local r, g, b, a = sc(theme.BACKGROUND_PANEL)   ImGui.PushStyleColor(ImGuiCol.ChildBg, r, g, b, a) end
    do local r, g, b, a = sc(theme.BORDER_SUBTLE)      ImGui.PushStyleColor(ImGuiCol.Border, r, g, b, a) end
    do local r, g, b, a = sc(theme.BACKGROUND_PANEL)   ImGui.PushStyleColor(ImGuiCol.FrameBg, r, g, b, a) end
    do local r, g, b, a = sc(theme.BACKGROUND_HOVER)    ImGui.PushStyleColor(ImGuiCol.FrameBgHovered, r, g, b, a) end
    do local r, g, b, a = sc(theme.BACKGROUND_HOVER)   ImGui.PushStyleColor(ImGuiCol.Header, r, g, b, a) end
    do local r, g, b, a = sc(theme.BACKGROUND_HOVER)   ImGui.PushStyleColor(ImGuiCol.HeaderHovered, r, g, b, a) end
    do local r, g, b, a = sc(theme.BACKGROUND_PANEL)   ImGui.PushStyleColor(ImGuiCol.Button, r, g, b, a) end
    do local r, g, b, a = sc(theme.BACKGROUND_HOVER)   ImGui.PushStyleColor(ImGuiCol.ButtonHovered, r, g, b, a) end
    do local r, g, b, a = sc(theme.BACKGROUND_PANEL)   ImGui.PushStyleColor(ImGuiCol.PopupBg, r, g, b, a) end
    do local r, g, b, a = sc(theme.BACKGROUND_DEEP)    ImGui.PushStyleColor(ImGuiCol.ScrollbarBg, r, g, b, a) end
    do local r, g, b, a = sc(0xFF2A3040)             ImGui.PushStyleColor(ImGuiCol.ScrollbarGrab, r, g, b, a) end
    do local r, g, b, a = sc(theme.TEXT_PRIMARY)      ImGui.PushStyleColor(ImGuiCol.Text, r, g, b, a) end
    do local r, g, b, a = sc(theme.BACKGROUND_PANEL) ImGui.PushStyleColor(ImGuiCol.MenuBarBg, r, g, b, a) end
    do local r, g, b, a = sc(theme.BACKGROUND_PANEL) ImGui.PushStyleColor(ImGuiCol.TitleBg, r, g, b, a) end
    do local r, g, b, a = sc(theme.BACKGROUND_PANEL) ImGui.PushStyleColor(ImGuiCol.TitleBgActive, r, g, b, a) end
    ImGui.PushStyleVar(ImGuiStyleVar.WindowPadding,   8, 6)
    ImGui.PushStyleVar(ImGuiStyleVar.FramePadding,   4, 3)
    ImGui.PushStyleVar(ImGuiStyleVar.ItemSpacing,    6, 3)
    ImGui.PushStyleVar(ImGuiStyleVar.WindowRounding, 0)
    ImGui.PushStyleVar(ImGuiStyleVar.FrameRounding,  0)
    ImGui.PushStyleVar(ImGuiStyleVar.WindowBorderSize, 1)
    ImGui.PushStyleVar(ImGuiStyleVar.ScrollbarSize,   8)
end

function theme.pop_obsidian_frame()
    ImGui.PopStyleVar(7)
    ImGui.PopStyleColor(STYLE_COLOR_COUNT)
end

function theme.push_tooltip_obsidian()
    do local r, g, b, a = sc(theme.BACKGROUND_PANEL) ImGui.PushStyleColor(ImGuiCol.PopupBg, r, g, b, a) end
    do local r, g, b, a = sc(theme.BORDER_ACCENT)   ImGui.PushStyleColor(ImGuiCol.Border, r, g, b, a) end
    do local r, g, b, a = sc(theme.TEXT_PRIMARY)    ImGui.PushStyleColor(ImGuiCol.Text, r, g, b, a) end
    ImGui.PushStyleVar(ImGuiStyleVar.WindowPadding, 10, 8)
end

function theme.pop_tooltip_obsidian()
    ImGui.PopStyleVar(1)
    ImGui.PopStyleColor(3)
end

return theme
