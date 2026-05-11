--[[
  GearScoreX — Obsidian Forge DrawList helpers.

  Test checklist:
  [ ] Score bar layers + dashed empty track read clearly at 10px height.
  [ ] Status dot hollow vs filled.
]]

local ImGui = require('ImGui')
local theme = require('ui.theme')

local ui = {}

local function alphaMul(hex, mul)
    mul = math.max(0, math.min(1, mul))
    local a = bit32.band(bit32.rshift(hex, 24), 0xFF)
    local na = math.floor(a * mul + 0.5)
    return bit32.bor(bit32.band(hex, 0x00FFFFFF), bit32.lshift(na, 24))
end

function ui.calcTextWidth(s)
    local tw = ImGui.CalcTextSize(s)
    if type(tw) == 'number' then return tw end
    if type(tw) == 'table' and tw.x then return tw.x end
    return (#tostring(s)) * 7
end

--- @param ratingPct number 0–100 fill (animated)
--- @param tierHex number reference color (SCORE_*)
function ui.DrawScoreBar(dl, x, y, w, h, ratingPct, tierHex, emptySlot)
    tierHex = tierHex or theme.SCORE_POOR
    h = math.max(8, h or 10)
    w = math.max(4, w)
    local x1, y1 = x + w, y + h
    local bgDeep = theme.u32(theme.BACKGROUND_DEEP)
    local border = theme.u32(theme.BORDER_SUBTLE)

    if emptySlot then
        dl:AddRectFilled(ImVec2(x, y), ImVec2(x1, y1), bgDeep, 0)
        local sr, sg, sb = theme.rgba(theme.TEXT_SECONDARY)
        local g = ImGui.GetColorU32(sr, sg, sb, 0.3)
        local seg, gap = 5, 4
        local cx = x + 2
        while cx < x1 - 2 do
            local x2 = math.min(cx + seg, x1 - 2)
            dl:AddLine(ImVec2(cx, y + h * 0.5), ImVec2(x2, y + h * 0.5), g, 1)
            cx = x2 + gap
        end
        dl:AddRect(ImVec2(x, y), ImVec2(x1, y1), border, 0, 0, 1)
        return
    end

    local fill01 = math.max(0, math.min(1, (tonumber(ratingPct) or 0) / 100))
    local fillW = math.max(0, w * fill01)

    dl:AddRectFilled(ImVec2(x, y), ImVec2(x1, y1), bgDeep, 0)

    if fillW > 0.5 then
        for i = 0, 3 do
            local x0 = x + (i / 4) * fillW
            local x2 = x + ((i + 1) / 4) * fillW
            local a = 1.0 - i * 0.12
            dl:AddRectFilled(ImVec2(x0, y), ImVec2(x2, y1), theme.u32(alphaMul(tierHex, a)), 0)
        end
        dl:AddRectFilled(ImVec2(x, y), ImVec2(x + fillW, y + 2), ImGui.GetColorU32(1, 1, 1, 0.15), 0)
    end

    dl:AddRect(ImVec2(x, y), ImVec2(x1, y1), border, 0, 0, 1)
end

function ui.GetScoreColorHex(rating0_100)
    return theme.scoreTierColor(rating0_100)
end

function ui.DrawStatusDot(dl, cx, cy, slotRating, empty)
    if empty or (tonumber(slotRating) or 0) <= 0.001 then
        dl:AddCircle(ImVec2(cx, cy), 4, theme.u32(theme.TEXT_SECONDARY), 12, 1)
        return
    end
    local h = ui.GetScoreColorHex(slotRating)
    local col = theme.u32(h)
    dl:AddCircleFilled(ImVec2(cx, cy), 4, col, 12)
    dl:AddCircle(ImVec2(cx, cy), 6, theme.u32(alphaMul(h, 0.25)), 12, 2)
end

function ui.DrawSectionDivider(drawList, x, y, w, label)
    drawList:AddLine(ImVec2(x, y), ImVec2(x + w, y), theme.u32(theme.BORDER_ACCENT), 1)
    if label and label ~= '' then
        drawList:AddText(ImVec2(x + 6, y - 10), theme.u32(theme.TEXT_SECONDARY), label)
    end
end

function ui.DrawDeltaPill(dl, x, y, text, isUpgrade, neutral)
    neutral = neutral and true or false
    local txtCol = theme.u32(neutral and theme.DELTA_NEUTRAL or (isUpgrade and theme.DELTA_UPGRADE or theme.DELTA_DOWNGRADE))
    local bgHex = neutral and 0x332A2F38 or (isUpgrade and 0xFF1A2A1A or 0xFF2A1A1A)
    local textW = ui.calcTextWidth(text)
    local padX, padY = 5, 2
    local pillW, pillH = textW + padX * 2, 16
    dl:AddRectFilled(ImVec2(x, y), ImVec2(x + pillW, y + pillH), theme.u32(bgHex), 2, 0)
    dl:AddText(ImVec2(x + padX, y + padY), txtCol, text)
    return pillW, pillH
end

return ui
