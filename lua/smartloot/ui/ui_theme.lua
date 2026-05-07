local M = {}

function M.push(ImGui)
    local vars, colors = 0, 0

    ImGui.PushStyleVar(ImGuiStyleVar.WindowRounding, 0.0); vars = vars + 1
    ImGui.PushStyleVar(ImGuiStyleVar.FrameRounding, 6.0); vars = vars + 1
    ImGui.PushStyleVar(ImGuiStyleVar.TabRounding, 0.0); vars = vars + 1
    ImGui.PushStyleVar(ImGuiStyleVar.FrameBorderSize, 1.0); vars = vars + 1
    ImGui.PushStyleVar(ImGuiStyleVar.WindowPadding, 6.0, 6.0); vars = vars + 1
    ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, 4.0, 2.0); vars = vars + 1
    ImGui.PushStyleVar(ImGuiStyleVar.ItemSpacing, 8.0, 8.0); vars = vars + 1

    ImGui.PushStyleColor(ImGuiCol.WindowBg, 0.03, 0.05, 0.10, 0.94); colors = colors + 1
    ImGui.PushStyleColor(ImGuiCol.ChildBg, 0.02, 0.03, 0.08, 0.98); colors = colors + 1
    ImGui.PushStyleColor(ImGuiCol.TitleBg, 0.02, 0.03, 0.07, 1.00); colors = colors + 1
    ImGui.PushStyleColor(ImGuiCol.TitleBgActive, 0.03, 0.05, 0.12, 1.00); colors = colors + 1
    ImGui.PushStyleColor(ImGuiCol.Button, 0.10, 0.18, 0.31, 0.95); colors = colors + 1
    ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 0.16, 0.27, 0.44, 1.00); colors = colors + 1
    ImGui.PushStyleColor(ImGuiCol.ButtonActive, 0.21, 0.33, 0.52, 1.00); colors = colors + 1
    ImGui.PushStyleColor(ImGuiCol.FrameBg, 0.09, 0.15, 0.26, 0.95); colors = colors + 1
    ImGui.PushStyleColor(ImGuiCol.FrameBgHovered, 0.14, 0.22, 0.36, 1.00); colors = colors + 1
    ImGui.PushStyleColor(ImGuiCol.FrameBgActive, 0.14, 0.22, 0.36, 1.00); colors = colors + 1
    ImGui.PushStyleColor(ImGuiCol.Header, 0.10, 0.18, 0.31, 0.95); colors = colors + 1
    ImGui.PushStyleColor(ImGuiCol.HeaderHovered, 0.16, 0.27, 0.44, 1.00); colors = colors + 1
    ImGui.PushStyleColor(ImGuiCol.HeaderActive, 0.21, 0.33, 0.52, 1.00); colors = colors + 1
    ImGui.PushStyleColor(ImGuiCol.Separator, 0.44, 0.52, 0.72, 0.90); colors = colors + 1
    ImGui.PushStyleColor(ImGuiCol.Border, 0.74, 0.66, 0.34, 0.95); colors = colors + 1
    ImGui.PushStyleColor(ImGuiCol.Text, 1.00, 0.95, 0.20, 1.00); colors = colors + 1
    ImGui.PushStyleColor(ImGuiCol.TextDisabled, 0.72, 0.72, 0.72, 1.00); colors = colors + 1
    ImGui.PushStyleColor(ImGuiCol.CheckMark, 0.96, 0.86, 0.30, 1.00); colors = colors + 1
    ImGui.PushStyleColor(ImGuiCol.Tab, 0.09, 0.15, 0.26, 1.00); colors = colors + 1
    ImGui.PushStyleColor(ImGuiCol.TabHovered, 0.14, 0.22, 0.36, 1.00); colors = colors + 1
    ImGui.PushStyleColor(ImGuiCol.TabActive, 0.10, 0.18, 0.31, 1.00); colors = colors + 1

    return vars, colors
end

function M.pop(ImGui, vars, colors)
    if colors and colors > 0 then ImGui.PopStyleColor(colors) end
    if vars and vars > 0 then ImGui.PopStyleVar(vars) end
end

return M
