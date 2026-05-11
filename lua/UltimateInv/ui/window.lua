--[[
  UltimateInv — shared item icon drawing (A_DragItem atlas).
]]

local ImGui = require('ImGui')

local M = {}

local ICON_SIZE = 22

function M.draw_icon(anim_items, icon_id, offset)
    if not anim_items or not icon_id or icon_id <= 0 then
        ImGui.Dummy(ICON_SIZE, ICON_SIZE)
        return
    end
    anim_items:SetTextureCell(icon_id - offset)
    ImGui.DrawTextureAnimation(anim_items, ICON_SIZE, ICON_SIZE)
end

return M
