local M = {}

local palette = {
  windowBg       = {0.03, 0.05, 0.10, 1.00},
  childBg        = {0.02, 0.03, 0.08, 1.00},
  titleBg        = {0.02, 0.03, 0.07, 1.00},
  titleBgActive  = {0.03, 0.05, 0.12, 1.00},
  button         = {0.10, 0.18, 0.31, 0.95},
  buttonHovered  = {0.16, 0.27, 0.44, 1.00},
  buttonActive   = {0.21, 0.33, 0.52, 1.00},
  frameBg        = {0.09, 0.15, 0.26, 0.95},
  frameBgHovered = {0.14, 0.22, 0.36, 1.00},
  header         = {0.10, 0.18, 0.31, 0.95},
  text           = {1.00, 0.95, 0.20, 1.00},
  border         = {0.74, 0.66, 0.34, 0.95},
  separator      = {0.44, 0.52, 0.72, 0.90},
  checkMark      = {0.96, 0.86, 0.30, 1.00},
}

local buttonVariants = {
  primary = {
    btn = {0.10, 0.18, 0.31, 0.95},
    hov = {0.16, 0.27, 0.44, 1.00},
    act = {0.21, 0.33, 0.52, 1.00},
  },
  success = {
    btn = {0.14, 0.50, 0.20, 1.00},
    hov = {0.22, 0.66, 0.29, 1.00},
    act = {0.10, 0.39, 0.16, 1.00},
  },
  warning = {
    btn = {0.66, 0.49, 0.10, 1.00},
    hov = {0.80, 0.60, 0.14, 1.00},
    act = {0.53, 0.38, 0.07, 1.00},
  },
}

function M.get_palette()
  return palette
end

function M.push_button_variant(ImGui, variant)
  local v = buttonVariants[variant or "primary"] or buttonVariants.primary
  ImGui.PushStyleColor(ImGuiCol.Button, v.btn[1], v.btn[2], v.btn[3], v.btn[4])
  ImGui.PushStyleColor(ImGuiCol.ButtonHovered, v.hov[1], v.hov[2], v.hov[3], v.hov[4])
  ImGui.PushStyleColor(ImGuiCol.ButtonActive, v.act[1], v.act[2], v.act[3], v.act[4])
  ImGui.PushStyleVar(ImGuiStyleVar.FrameRounding, 6.0)
  ImGui.PushStyleVar(ImGuiStyleVar.FrameBorderSize, 1.0)
  return {vars = 2, colors = 3}
end

function M.pop_button_variant(ImGui, count)
  local c = count or {vars = 2, colors = 3}
  if c.colors and c.colors > 0 then ImGui.PopStyleColor(c.colors) end
  if c.vars and c.vars > 0 then ImGui.PopStyleVar(c.vars) end
end

function M.push_ezinventory_theme(ImGui)
  local pushedVars = 0
  local pushedColors = 0

  ImGui.PushStyleVar(ImGuiStyleVar.WindowRounding, 0.0);         pushedVars = pushedVars + 1
  ImGui.PushStyleVar(ImGuiStyleVar.FrameRounding, 6.0);          pushedVars = pushedVars + 1
  ImGui.PushStyleVar(ImGuiStyleVar.ChildRounding, 0.0);          pushedVars = pushedVars + 1
  ImGui.PushStyleVar(ImGuiStyleVar.PopupRounding, 8.0);          pushedVars = pushedVars + 1
  ImGui.PushStyleVar(ImGuiStyleVar.GrabRounding, 6.0);           pushedVars = pushedVars + 1
  ImGui.PushStyleVar(ImGuiStyleVar.TabRounding, 0.0);            pushedVars = pushedVars + 1
  ImGui.PushStyleVar(ImGuiStyleVar.WindowBorderSize, 1.0);       pushedVars = pushedVars + 1
  ImGui.PushStyleVar(ImGuiStyleVar.FrameBorderSize, 1.0);        pushedVars = pushedVars + 1
  ImGui.PushStyleVar(ImGuiStyleVar.ChildBorderSize, 1.0);        pushedVars = pushedVars + 1
  ImGui.PushStyleVar(ImGuiStyleVar.WindowPadding, 6.0, 6.0);     pushedVars = pushedVars + 1
  ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, 4.0, 2.0);      pushedVars = pushedVars + 1
  ImGui.PushStyleVar(ImGuiStyleVar.ItemSpacing, 8.0, 8.0);       pushedVars = pushedVars + 1

  ImGui.PushStyleColor(ImGuiCol.WindowBg, palette.windowBg[1], palette.windowBg[2], palette.windowBg[3], palette.windowBg[4]); pushedColors = pushedColors + 1
  ImGui.PushStyleColor(ImGuiCol.ChildBg, palette.childBg[1], palette.childBg[2], palette.childBg[3], palette.childBg[4]); pushedColors = pushedColors + 1
  ImGui.PushStyleColor(ImGuiCol.TitleBg, palette.titleBg[1], palette.titleBg[2], palette.titleBg[3], palette.titleBg[4]); pushedColors = pushedColors + 1
  ImGui.PushStyleColor(ImGuiCol.TitleBgActive, palette.titleBgActive[1], palette.titleBgActive[2], palette.titleBgActive[3], palette.titleBgActive[4]); pushedColors = pushedColors + 1
  ImGui.PushStyleColor(ImGuiCol.Button, palette.button[1], palette.button[2], palette.button[3], palette.button[4]); pushedColors = pushedColors + 1
  ImGui.PushStyleColor(ImGuiCol.ButtonHovered, palette.buttonHovered[1], palette.buttonHovered[2], palette.buttonHovered[3], palette.buttonHovered[4]); pushedColors = pushedColors + 1
  ImGui.PushStyleColor(ImGuiCol.ButtonActive, palette.buttonActive[1], palette.buttonActive[2], palette.buttonActive[3], palette.buttonActive[4]); pushedColors = pushedColors + 1
  ImGui.PushStyleColor(ImGuiCol.FrameBg, palette.frameBg[1], palette.frameBg[2], palette.frameBg[3], palette.frameBg[4]); pushedColors = pushedColors + 1
  ImGui.PushStyleColor(ImGuiCol.FrameBgHovered, palette.frameBgHovered[1], palette.frameBgHovered[2], palette.frameBgHovered[3], palette.frameBgHovered[4]); pushedColors = pushedColors + 1
  ImGui.PushStyleColor(ImGuiCol.FrameBgActive, palette.frameBgHovered[1], palette.frameBgHovered[2], palette.frameBgHovered[3], 1.0); pushedColors = pushedColors + 1
  ImGui.PushStyleColor(ImGuiCol.Header, palette.header[1], palette.header[2], palette.header[3], palette.header[4]); pushedColors = pushedColors + 1
  ImGui.PushStyleColor(ImGuiCol.HeaderHovered, palette.buttonHovered[1], palette.buttonHovered[2], palette.buttonHovered[3], 1.0); pushedColors = pushedColors + 1
  ImGui.PushStyleColor(ImGuiCol.HeaderActive, palette.buttonActive[1], palette.buttonActive[2], palette.buttonActive[3], 1.0); pushedColors = pushedColors + 1
  ImGui.PushStyleColor(ImGuiCol.Text, palette.text[1], palette.text[2], palette.text[3], palette.text[4]); pushedColors = pushedColors + 1
  ImGui.PushStyleColor(ImGuiCol.Border, palette.border[1], palette.border[2], palette.border[3], palette.border[4]); pushedColors = pushedColors + 1
  ImGui.PushStyleColor(ImGuiCol.Separator, palette.separator[1], palette.separator[2], palette.separator[3], palette.separator[4]); pushedColors = pushedColors + 1
  ImGui.PushStyleColor(ImGuiCol.TextDisabled, 0.72, 0.72, 0.72, 1.00); pushedColors = pushedColors + 1
  ImGui.PushStyleColor(ImGuiCol.CheckMark, palette.checkMark[1], palette.checkMark[2], palette.checkMark[3], palette.checkMark[4]); pushedColors = pushedColors + 1
  ImGui.PushStyleColor(ImGuiCol.PopupBg, palette.childBg[1], palette.childBg[2], palette.childBg[3], 0.98); pushedColors = pushedColors + 1
  ImGui.PushStyleColor(ImGuiCol.Tab, palette.frameBg[1], palette.frameBg[2], palette.frameBg[3], 1.00); pushedColors = pushedColors + 1
  ImGui.PushStyleColor(ImGuiCol.TabHovered, palette.frameBgHovered[1], palette.frameBgHovered[2], palette.frameBgHovered[3], 1.00); pushedColors = pushedColors + 1
  ImGui.PushStyleColor(ImGuiCol.TabActive, palette.header[1], palette.header[2], palette.header[3], 1.00); pushedColors = pushedColors + 1

  return {vars = pushedVars, colors = pushedColors}
end

function M.pop_ezinventory_theme(ImGui, count)
  if type(count) == "table" then
    if (count.colors or 0) > 0 then
      ImGui.PopStyleColor(count.colors)
    end
    if (count.vars or 0) > 0 then
      ImGui.PopStyleVar(count.vars)
    end
    return
  end

  if count and count > 0 then
    ImGui.PopStyleVar(count)
  end
end

return M
