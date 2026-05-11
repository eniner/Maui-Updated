--[[
  GearScoreX — Obsidian Forge main window (presentation only).

  Test checklist:
  [ ] Bar anim on refresh (app.barAnim from GearScoreX.refresh)
  [ ] Section dividers before accessories (row 9) and weapons (row 19)
  [ ] Candidate banner pulse
  [ ] Tooltip themed in GearScoreX.itemTooltip
  [ ] Style stack: theme pushed in GearScoreX onGui only
]]

local theme = require('ui.theme')
local ui = require('ui.ui_helpers')

local M = {}
local E

function M.init(env)
    E = env
end

local SPIN_CHARS = { '⣾', '⣽', '⣻', '⢿', '⡿', '⣟', '⣯', '⣷' }

local COL_DOT, COL_SLOT, COL_ICO, COL_BAG, COL_BAR, COL_RTG, COL_DEL = 14, 68, 26, 160, 110, 40, 54

--- Section divider rows (matches items.SLOT_ORDER: armor 1–8, accessories 9–18, weapons 19–22).
local SECTION_ROW = { [9] = 'ACCESSORIES', [19] = 'WEAPONS' }

--- Space reserved under the gear table for the footer (must fit avg box + breakdown + legend).
local FOOTER_RESERVE = 142

--- MQ Lua ImGui often returns (x, y) as two numbers; some builds return vec-like userdata with .x / .y.
local function vec2XY(a, b)
    if type(a) == 'number' and type(b) == 'number' then
        return a, b
    end
    if a ~= nil and type(a) ~= 'number' then
        local okx, x = pcall(function() return a.x end)
        local oky, y = pcall(function() return a.y end)
        if okx and oky and type(x) == 'number' and type(y) == 'number' then
            return x, y
        end
    end
    return 0, 0
end

local function cursorScreenXY(ImGui)
    return vec2XY(ImGui.GetCursorScreenPosVec())
end

local function windowPosXY(ImGui)
    return vec2XY(ImGui.GetWindowPos())
end

local function windowSizeWH(ImGui)
    return vec2XY(ImGui.GetWindowSize())
end

local function itemRectMinXY(ImGui)
    return vec2XY(ImGui.GetItemRectMin())
end

local function contentRegionMinXY(ImGui)
    return vec2XY(ImGui.GetWindowContentRegionMin())
end

local function windowContentRegionWidth(ImGui)
    local w = ImGui.GetWindowContentRegionWidth()
    if type(w) == 'number' then return w end
    return regionAvailW()
end

local function alphaMul(hex, mul)
    mul = math.max(0, math.min(1, mul))
    local a = bit32.band(bit32.rshift(hex, 24), 0xFF)
    local na = math.floor(a * mul + 0.5)
    return bit32.bor(bit32.band(hex, 0x00FFFFFF), bit32.lshift(na, 24))
end

local function regionAvailW()
    return E.RegionAvailW()
end

local function slotR100(score, maxv)
    return E.slotRating100(score or 0, maxv or 1)
end

local function updateBarAnimClock(app)
    local now = os.clock()
    if not app._barClock then app._barClock = now end
    local dt = math.min(0.08, now - app._barClock)
    app._barClock = now
    app._barDt = dt > 0 and dt or (1 / 60)
end

local function getAnimatedRatingPct(app, slotKey, targetPct)
    local a = app.barAnim and app.barAnim[slotKey]
    if not a then return targetPct end
    local now = os.clock()
    if now < (a.start or 0) then return 0 end
    local dt = app._barDt or (1 / 60)
    a.v = (a.v or 0) + (targetPct - (a.v or 0)) * math.min(1, dt * 10)
    if math.abs(targetPct - a.v) < 0.2 then a.v = targetPct end
    return a.v
end

local function syncCandidateFade(app)
    local bid = (app.slotB and app.slotB.name) or ''
    if bid ~= app._lastBidName then
        app._lastBidName = bid
        app.deltaFadeT0 = os.clock()
    end
end

local function deltaFadeAlpha(app)
    local t0 = app.deltaFadeT0 or os.clock()
    local u = (os.clock() - t0) / 0.3
    return u > 1 and 1 or u
end

local function pushText(hex)
    local r, g, b, a = theme.rgba(hex)
    E.ImGui.PushStyleColor(ImGuiCol.Text, r, g, b, a)
end

local function drawForgeShelf()
    local ImGui = E.ImGui
    local _cpx, cpy = cursorScreenXY(ImGui)
    local wx = select(1, windowPosXY(ImGui))
    local ww = select(1, windowSizeWH(ImGui))
    local dl = ImGui.GetWindowDrawList()
    local y = cpy - 1
    dl:AddLine(ImVec2(wx, y), ImVec2(wx + ww, y), theme.u32(theme.TEXT_ACCENT), 1)
end

local function drawHeaderStrip(app)
    local ImGui = E.ImGui
    local mq = E.mq
    ImGui.BeginChild('gsx_hdr_strip', 0, 48, false, ImGuiWindowFlags.NoScrollbar)
    local p0x, p0y = cursorScreenXY(ImGui)
    local w = windowContentRegionWidth(ImGui)
    local dl = ImGui.GetWindowDrawList()
    dl:AddRectFilled(ImVec2(p0x, p0y), ImVec2(p0x + w, p0y + 48), theme.u32(theme.BACKGROUND_PANEL), 0)
    dl:AddRect(ImVec2(p0x, p0y), ImVec2(p0x + w, p0y + 48), theme.u32(theme.BORDER_ACCENT), 0, 0, 1)

    ImGui.SetCursorPos(10, 12)
    if ImGui.Button('REFRESH##hdr') then E.refresh(app) end
    ImGui.SameLine()
    if ImGui.Button('COPY SUMMARY##hdr') then E.copySummary(app) end
    ImGui.SameLine()
    ImGui.SetCursorPosX(ImGui.GetCursorPosX() + 16)
    pushText(theme.TEXT_SECONDARY)
    ImGui.Text('CLASS:')
    ImGui.PopStyleColor()
    ImGui.SameLine()
    pushText(theme.TEXT_ACCENT)
    ImGui.Text('%s', mq.TLO.Me.Class and mq.TLO.Me.Class() or '—')
    ImGui.PopStyleColor()
    ImGui.SameLine()
    pushText(theme.TEXT_SECONDARY)
    ImGui.Text('  PRESET:')
    ImGui.PopStyleColor()
    ImGui.SameLine()
    pushText(theme.TEXT_PRIMARY)
    ImGui.Text('Auto')
    ImGui.PopStyleColor()

    ImGui.EndChild()
end

local function wornScoreForSlot(app, slotKey)
    for _, r in ipairs(app.cachedRows or {}) do
        if r.slotKey == slotKey then return r.score or 0 end
    end
    return 0
end

local function drawCandidateBanner(app)
    local ImGui = E.ImGui
    local compare = E.compare
    if not app.slotB or not app.slotB.name then return end

    local pulse = 0.7 + 0.3 * math.abs(math.sin(os.clock() * 1.5))
    local bgBase = theme.CANDIDATE_BADGE
    local aByte = math.floor(255 * pulse)
    local bgPulse = bit32.bor(bit32.band(bgBase, 0x00FFFFFF), bit32.lshift(aByte, 24))

    local rb = slotR100(app.slotB.score or 0, app.maxScore or 1)
    local sa = wornScoreForSlot(app, app.slotB.slotKey or '')
    local sb = app.slotB.score or 0
    local _, rp = compare.relativePercent(sa, sb)
    local upg = rp > 0.05
    local dng = rp < -0.05
    local deltaStr = (math.abs(rp) < 0.05) and '~'
        or string.format('%s %.1f%%', upg and '▲' or '▼', math.abs(rp))
    local deltaCol = theme.u32(theme.DELTA_NEUTRAL)
    if upg then deltaCol = theme.u32(theme.DELTA_UPGRADE) elseif dng then deltaCol = theme.u32(theme.DELTA_DOWNGRADE) end

    local p0x, p0y = cursorScreenXY(ImGui)
    local wAvail = regionAvailW()
    local hBan = 36
    ImGui.Dummy(wAvail, hBan)
    local dl = ImGui.GetWindowDrawList()
    dl:AddRectFilled(ImVec2(p0x, p0y), ImVec2(p0x + wAvail, p0y + hBan), theme.u32(bgPulse), 4, 0)
    dl:AddRect(ImVec2(p0x, p0y), ImVec2(p0x + wAvail, p0y + hBan), theme.u32(theme.BORDER_SUBTLE), 4, 0, 1)

    local tier = theme.scoreTierColor(rb)
    dl:AddText(ImVec2(p0x + 10, p0y + 10), theme.u32(theme.TEXT_SECONDARY), '⬡ COMPARING')

    local scoreTxt = string.format('%.0f / 100', rb)
    local padR, gap = 10, 12
    local sw = ui.calcTextWidth(scoreTxt)
    local dw = ui.calcTextWidth(deltaStr)
    local maxR = p0x + wAvail - padR
    local deltaX = maxR - dw
    local scoreX = maxR - dw - gap - sw

    local name = app.slotB.name or ''
    local nameX = p0x + 118
    local maxNamePx = scoreX - gap - nameX
    if maxNamePx < 140 then
        local maxC = math.max(16, math.floor(maxNamePx / 7))
        if #name > maxC then name = name:sub(1, maxC - 1) .. '…' end
    elseif #name > 42 then
        name = name:sub(1, 39) .. '…'
    end
    dl:AddText(ImVec2(nameX, p0y + 10), theme.u32(theme.TEXT_ACCENT), name)

    local cxDot = math.min(p0x + wAvail - 56, scoreX - 18)
    dl:AddCircleFilled(ImVec2(cxDot, p0y + hBan * 0.5), 5, theme.u32(tier), 12)

    dl:AddText(ImVec2(scoreX, p0y + 9), theme.u32(theme.TEXT_HIGHLIGHT), scoreTxt)
    dl:AddText(ImVec2(deltaX, p0y + 9), deltaCol, deltaStr)
end

local function drawGhostCompareToggle(app)
    local ImGui = E.ImGui
    local label = 'Stat compare'
    local sz = ImGui.CalcTextSize(label)
    local tw = (type(sz) == 'number') and sz or (sz and sz.x) or 80
    local th = ImGui.GetTextLineHeight()
    local pad = 8
    local bw, bh = tw + pad * 2, th + pad * 2
    local px, py = cursorScreenXY(ImGui)
    ImGui.InvisibleButton('ghost_cmp', bw, bh)
    local hov = ImGui.IsItemHovered()
    local dl = ImGui.GetWindowDrawList()
    local hot = hov or app.settings.compareMode
    local col = hot and theme.u32(theme.BORDER_ACCENT) or theme.u32(theme.BORDER_SUBTLE)
    dl:AddRect(ImVec2(px, py), ImVec2(px + bw, py + bh), col, 0, 0, 1)
    if hov then
        dl:AddRectFilled(ImVec2(px, py), ImVec2(px + bw, py + bh), theme.u32(0x33111318), 0)
    end
    dl:AddText(ImVec2(px + pad, py + pad * 0.5), theme.u32(theme.TEXT_PRIMARY), label)
    if ImGui.IsItemClicked(0) then
        app.settings.compareMode = not app.settings.compareMode
        if app.settings.compareMode then app.compareOpen = true end
    end
end

local function drawToolbarRow(app)
    local ImGui = E.ImGui
    local mq = E.mq
    ImGui.BeginGroup()
    if ImGui.SmallButton('?##gsx_help') then end
    if ImGui.IsItemHovered() then
        ImGui.BeginTooltip()
        ImGui.PushTextWrapPos(ImGui.GetFontSize() * 36)
        ImGui.TextWrapped(
            'Rating = strength vs your best worn slot (100 = top piece). Average = mean across worn slots. '
                .. 'Compare (B) from Bags. Δ uses the same 0–100 scale. Weights follow class automatically.')
        ImGui.PopTextWrapPos()
        ImGui.EndTooltip()
    end
    ImGui.SameLine()
    drawGhostCompareToggle(app)
    ImGui.SameLine()

    ImGui.SameLine()
    if app.refreshBusy then
        local idx = math.floor(os.clock() * 8) % 8 + 1
        pushText(theme.TEXT_SECONDARY)
        ImGui.Text('%s Refreshing…', SPIN_CHARS[idx])
        ImGui.PopStyleColor()
        local t = mq.gettime()
        if t > (app.refreshAnimStart or 0) + 400 then app.refreshBusy = false end
    end

    ImGui.SameLine()
    do
        local r, g, b, a = theme.rgba(theme.BACKGROUND_PANEL)
        local rh, gh, bh, ah = theme.rgba(theme.BACKGROUND_HOVER)
        ImGui.PushStyleColor(ImGuiCol.Button, r, g, b, a)
        ImGui.PushStyleColor(ImGuiCol.ButtonHovered, rh, gh, bh, ah)
        pushText(theme.TEXT_ACCENT)
        if ImGui.Button('Refresh worn##gsx_ref2') then E.refresh(app) end
        ImGui.PopStyleColor()
        ImGui.PopStyleColor(2)
    end

    ImGui.EndGroup()
end

local function drawSectionDividerRow(label)
    local ImGui = E.ImGui
    ImGui.TableNextRow()
    for ci = 1, 8 do
        ImGui.TableNextColumn()
        ImGui.Dummy(1, 18)
    end
    local dl = ImGui.GetWindowDrawList()
    local wpx = select(1, windowPosXY(ImGui))
    local mnx = select(1, contentRegionMinXY(ImGui))
    local wx = wpx + mnx
    local ww = windowContentRegionWidth(ImGui)
    local _cpx, cpy = cursorScreenXY(ImGui)
    local cy = cpy - 10
    ui.DrawSectionDivider(dl, wx, cy, ww, label)
end

local function drawGearTable(app)
    local ImGui = E.ImGui
    local items = E.items
    local drag = E.drag

    updateBarAnimClock(app)
    syncCandidateFade(app)

    local tblFlags = bit32.bor(ImGuiTableFlags.RowBg, ImGuiTableFlags.BordersInnerH, ImGuiTableFlags.SizingStretchProp)

    if ImGui.BeginTable('gear_tbl_ob', 8, tblFlags) then
        ImGui.TableSetupColumn('##dot', ImGuiTableColumnFlags.WidthFixed, COL_DOT)
        ImGui.TableSetupColumn('Slot', ImGuiTableColumnFlags.WidthFixed, COL_SLOT)
        ImGui.TableSetupColumn('Ico', ImGuiTableColumnFlags.WidthFixed, COL_ICO)
        ImGui.TableSetupColumn('Worn', ImGuiTableColumnFlags.WidthStretch)
        ImGui.TableSetupColumn('Bags', ImGuiTableColumnFlags.WidthFixed, COL_BAG)
        ImGui.TableSetupColumn('Bar', ImGuiTableColumnFlags.WidthFixed, COL_BAR)
        ImGui.TableSetupColumn('Rtg', ImGuiTableColumnFlags.WidthFixed, COL_RTG)
        ImGui.TableSetupColumn('Δ', ImGuiTableColumnFlags.WidthFixed, COL_DEL)

        pcall(function() ImGui.TableSetupScrollFreeze(0, 1) end)
        ImGui.TableHeadersRow()

        local maxS = app.maxScore or 1
        for ri, row in ipairs(app.cachedRows or {}) do
            if SECTION_ROW[ri] then
                drawSectionDividerRow(SECTION_ROW[ri])
            end

            ImGui.TableNextRow()

            local rating100 = slotR100(row.score or 0, maxS)
            local tierHex = ui.GetScoreColorHex(rating100)
            local animPct = getAnimatedRatingPct(app, row.slotKey, rating100)

            pcall(function()
                if ri % 2 == 1 then
                    ImGui.TableSetBgColor(ImGuiTableBgTarget.RowBg1, theme.rgba(theme.BACKGROUND_ROW_ALT))
                end
            end)

            ImGui.PushID(ri)

            ImGui.TableNextColumn()
            ImGui.Dummy(COL_DOT, 24)
            local cpx, cpy = itemRectMinXY(ImGui)
            local dl = ImGui.GetWindowDrawList()
            ui.DrawStatusDot(dl, cpx + COL_DOT * 0.5, cpy + 12, rating100, row.empty or not row.stats)

            ImGui.TableNextColumn()
            pushText(theme.TEXT_SECONDARY)
            ImGui.SetWindowFontScale(0.92)
            local slotTxt = row.slotLabel or ''
            if math.abs(rating100 - 100) < 0.6 and not row.empty then slotTxt = slotTxt .. ' ★' end
            ImGui.Text('%s', slotTxt)
            ImGui.SetWindowFontScale(1.0)
            ImGui.PopStyleColor()

            ImGui.TableNextColumn()
            ImGui.InvisibleButton('ico_' .. ri, 22, 24)
            if row.stats and not row.empty then
                if ImGui.BeginDragDropSource(ImGuiDragDropFlags.None) then
                    local tok = drag.put({
                        slotKey = row.slotKey, slotLabel = row.slotLabel, itemName = row.stats.Name,
                        itemID = row.stats.ID, score = row.score, stats = row.stats,
                    })
                    ImGui.SetDragDropPayload('GEARSCORE_ITEM', tok)
                    ImGui.Text(row.stats.Name or '')
                    ImGui.EndDragDropSource()
                end
            end
            local rminx, rminy = itemRectMinXY(ImGui)
            dl = ImGui.GetWindowDrawList()
            dl:AddRectFilled(ImVec2(rminx, rminy), ImVec2(rminx + 20, rminy + 20), theme.u32(theme.BACKGROUND_PANEL), 0)
            dl:AddRect(ImVec2(rminx, rminy), ImVec2(rminx + 20, rminy + 20), theme.u32(theme.BORDER_SUBTLE), 0, 0, 1)
            if row.stats and row.stats.Icon and not row.empty then
                E.icons.DrawItemIconAt(rminx, rminy, row.stats.Icon, 20)
            end

            ImGui.TableNextColumn()
            local candStripe = app.slotB and app.slotB.slotKey == row.slotKey
            local label = row.stats and row.stats.Name or '—'
            if string.len(label) > 36 then label = label:sub(1, 33) .. '…' end
            pushText(theme.TEXT_PRIMARY)
            ImGui.Text('%s', label)
            ImGui.PopStyleColor()
            if candStripe then
                local prx, pry = itemRectMinXY(ImGui)
                dl:AddRectFilled(ImVec2(prx - 4, pry), ImVec2(prx - 1, pry + ImGui.GetTextLineHeight()),
                    theme.u32(theme.CANDIDATE_BADGE), 0)
            end
            if ImGui.IsItemHovered() and row.stats then
                E.itemTooltip(row.stats, row.slotLabel, row.score, maxS)
            end
            if ImGui.IsItemClicked(0) and row.stats then
                app.slotA = {
                    slotKey = row.slotKey, name = row.stats.Name, id = row.stats.ID,
                    stats = row.stats, score = row.score, icon = row.stats.Icon,
                }
                if app.slotB and app.slotB.stats then app.slotB.slotKey = row.slotKey end
                if E.openComparePanel and app.slotB and app.slotB.stats then E.openComparePanel(app) end
            end
            if ImGui.IsItemClicked(1) and row.stats then
                app.slotB = {
                    slotKey = row.slotKey, name = row.stats.Name, id = row.stats.ID,
                    stats = row.stats, score = row.score, icon = row.stats.Icon,
                }
                if E.openComparePanel and app.slotA and app.slotA.stats then E.openComparePanel(app) end
            end

            ImGui.TableNextColumn()
            do
                local r, g, b, a = theme.rgba(theme.BACKGROUND_DEEP)
                local rb, gb, bb, ba = theme.rgba(theme.BORDER_SUBTLE)
                ImGui.PushStyleColor(ImGuiCol.FrameBg, r, g, b, a)
                ImGui.PushStyleColor(ImGuiCol.Border, rb, gb, bb, ba)
                local sn = items.WORN_SLOT_NUM[row.slotKey]
                local opts = (sn ~= nil and app.bagSlotOptions and app.bagSlotOptions[sn]) or {}
                local preview = '— pick —'
                if app.slotB and app.slotB.slotKey == row.slotKey and app.slotB.name then
                    preview = app.slotB.name
                    if string.len(preview) > 22 then preview = preview:sub(1, 19) .. '…' end
                end
                ImGui.PushItemWidth(-1)
                if ImGui.BeginCombo('bags##' .. ri, preview) then
                    if ImGui.Selectable('(clear compare B)', false) then app.slotB = nil end
                    if #opts == 0 then
                        ImGui.TextDisabled('No items in bags for this slot')
                    else
                        for _, nm in ipairs(opts) do
                            local sel = app.slotB and app.slotB.name == nm and app.slotB.slotKey == row.slotKey
                            if ImGui.Selectable(nm, sel) then
                                local fi = items.findItemTLOByName(nm)
                                if fi then
                                    local st = items.extractStats(fi)
                                    if st then E.assignCompareB(app, st, { slotKey = row.slotKey }) end
                                end
                            end
                        end
                    end
                    ImGui.EndCombo()
                end
                ImGui.PopItemWidth()
                ImGui.PopStyleColor(2)
            end

            ImGui.TableNextColumn()
            ImGui.Dummy(COL_BAR, 24)
            local rMinx, rMiny = itemRectMinXY(ImGui)
            dl = ImGui.GetWindowDrawList()
            local bx, by = rMinx + 2, rMiny + 7
            ui.DrawScoreBar(dl, bx, by, COL_BAR - 8, 10, animPct, tierHex, row.empty)

            ImGui.TableNextColumn()
            do
                if row.empty then
                    pushText(theme.TEXT_SECONDARY)
                    ImGui.Text('—')
                    ImGui.PopStyleColor()
                else
                    local txt = string.format('%.0f', rating100)
                    local px, py = cursorScreenXY(ImGui)
                    if math.abs(rating100 - 100) < 0.51 then
                        dl:AddText(ImVec2(px + 1, py + 1), theme.u32(alphaMul(tierHex, 0.45)), txt)
                        pushText(theme.TEXT_HIGHLIGHT)
                        ImGui.Text('%s', txt)
                        ImGui.PopStyleColor()
                    else
                        local rr, gg, bb, aa = theme.rgba(tierHex)
                        ImGui.PushStyleColor(ImGuiCol.Text, rr, gg, bb, aa)
                        ImGui.Text('%s', txt)
                        ImGui.PopStyleColor()
                    end
                end
            end

            ImGui.TableNextColumn()
            local badge = E.deltaBadge(app, row)
            if badge == '' or not app.slotB then
                pushText(theme.TEXT_SECONDARY)
                ImGui.Text('—')
                ImGui.PopStyleColor()
            else
                local neg = badge:find('▼')
                local neut = badge == '~'
                local dl2 = ImGui.GetWindowDrawList()
                local px, py = cursorScreenXY(ImGui)
                py = py + 4
                deltaFadeAlpha(app)
                ui.DrawDeltaPill(dl2, px, py, badge, not neg and not neut, neut)
            end

            if ImGui.BeginDragDropTarget() then
                local pl = ImGui.AcceptDragDropPayload('GEARSCORE_ITEM')
                if pl ~= nil then
                    local data = drag.take(pl.Data)
                    if data and data.stats then
                        app.slotB = {
                            slotKey = data.slotKey, name = data.itemName, id = data.itemID,
                            stats = data.stats, score = data.score, icon = data.stats.Icon,
                        }
                    end
                end
                ImGui.EndDragDropTarget()
            end

            ImGui.PopID()
        end

        ImGui.EndTable()
    end
end

local function drawFooter(app)
    local ImGui = E.ImGui
    local dl = ImGui.GetWindowDrawList()
    local wx = select(1, windowPosXY(ImGui))
    local ww = regionAvailW()
    local _cpx, cpy = cursorScreenXY(ImGui)
    dl:AddLine(ImVec2(wx, cpy), ImVec2(wx + ww, cpy), theme.u32(theme.BORDER_ACCENT), 1)

    ImGui.BeginChild('gsx_footer', 0, FOOTER_RESERVE - 8, false)
    ImGui.Columns(2, 'gsx_foot_cols', false)
    ImGui.SetColumnWidth(0, 280)

    do
        local avg = app.overallRating or 0
        local px, py = cursorScreenXY(ImGui)
        dl:AddRectFilled(ImVec2(px, py), ImVec2(px + 80, py + 44), theme.u32(theme.BACKGROUND_PANEL), 0)
        dl:AddRect(ImVec2(px, py), ImVec2(px + 80, py + 44), theme.u32(theme.BORDER_ACCENT), 0, 0, 1)
        dl:AddText(ImVec2(px + 6, py + 4), theme.u32(theme.TEXT_SECONDARY), 'AVG SCORE')
        dl:AddText(ImVec2(px + 22, py + 14), theme.u32(theme.TEXT_ACCENT), string.format('%.0f', avg))
        local tier = theme.scoreTierColor(avg)
        dl:AddRectFilled(ImVec2(px + 6, py + 38), ImVec2(px + 6 + 68 * (avg / 100), py + 42), theme.u32(tier), 0)
        ImGui.Dummy(84, 48)
        pushText(theme.TEXT_SECONDARY)
        ImGui.SetWindowFontScale(0.78)
        ImGui.TextWrapped('Mean of worn slot ratings')
        ImGui.SetWindowFontScale(1.0)
        ImGui.PopStyleColor()

        local cpx, cpy = cursorScreenXY(ImGui)
        ImGui.InvisibleButton('cp_clip', 150, 22)
        local h = ImGui.IsItemHovered()
        if h then
            dl:AddRectFilled(ImVec2(cpx, cpy), ImVec2(cpx + 150, cpy + 22), theme.u32(0x66111318), 0)
        end
        dl:AddRect(ImVec2(cpx, cpy), ImVec2(cpx + 150, cpy + 22), theme.u32(theme.BORDER_ACCENT), 0, 0, 1)
        dl:AddText(ImVec2(cpx + 8, cpy + 3), theme.u32(theme.TEXT_ACCENT), '📋 Copy to Clipboard')
        if ImGui.IsItemClicked(0) then E.copySummary(app) end
    end

    ImGui.NextColumn()

    do
        local bd = app.breakdownTotal or { offensive = 1, defensive = 1, utility = 1 }
        local tot = math.max(app.totalScore or 1, 0.001)
        local po = (bd.offensive or 0) / tot
        local pd = (bd.defensive or 0) / tot
        local pu = (bd.utility or 0) / tot
        local px, py = cursorScreenXY(ImGui)
        py = py + 6
        local barW = math.max(120, regionAvailW() - 40)
        local barH = 18
        dl:AddText(ImVec2(px, py - 14), theme.u32(theme.TEXT_SECONDARY), 'SCORE BREAKDOWN')

        local x0 = px
        local oW = barW * po
        local dW = barW * pd
        local uW = barW * pu
        dl:AddRectFilled(ImVec2(x0, py), ImVec2(x0 + oW, py + barH), theme.u32(theme.BREAKDOWN_OFFENSE), 0)
        x0 = x0 + oW
        dl:AddRectFilled(ImVec2(x0, py), ImVec2(x0 + dW, py + barH), theme.u32(theme.BREAKDOWN_DEFENSE), 0)
        x0 = x0 + dW
        dl:AddRectFilled(ImVec2(x0, py), ImVec2(x0 + uW, py + barH), theme.u32(theme.BREAKDOWN_UTILITY), 0)
        local s1 = px + oW
        local s2 = px + oW + dW
        dl:AddLine(ImVec2(s1, py), ImVec2(s1, py + barH), ImGui.GetColorU32(1, 1, 1, 1), 1)
        dl:AddLine(ImVec2(s2, py), ImVec2(s2, py + barH), ImGui.GetColorU32(1, 1, 1, 1), 1)

        ImGui.Dummy(barW, barH + 22)
        local ly = py + barH + 8
        local lx = px
        local labU32 = theme.u32(theme.TEXT_SECONDARY)
        local hiU32 = theme.u32(theme.TEXT_HIGHLIGHT)
        local tri = {
            { 'Offense', 100 * po },
            { 'Defense', 100 * pd },
            { 'Utility', 100 * pu },
        }
        for ti, t in ipairs(tri) do
            if ti > 1 then
                dl:AddText(ImVec2(lx, ly), labU32, '   ')
                lx = lx + ui.calcTextWidth('   ')
            end
            dl:AddText(ImVec2(lx, ly), labU32, t[1])
            lx = lx + ui.calcTextWidth(t[1])
            local ps = string.format(' %.1f%%', t[2])
            dl:AddText(ImVec2(lx, ly), hiU32, ps)
            lx = lx + ui.calcTextWidth(ps)
        end
    end

    ImGui.Columns(1)
    ImGui.EndChild()
end

function M.draw(app)
    local ImGui = E.ImGui
    if not E then return end

    ImGui.SetNextWindowSizeConstraints(ImVec2(480, 380), ImVec2(1280, 860))
    ImGui.SetNextWindowSize(ImVec2(620, 500), ImGuiCond.FirstUseEver)

    local flags = bit32.bor(ImGuiWindowFlags.NoCollapse, ImGuiWindowFlags.NoScrollbar)
    local open, drawWin = ImGui.Begin('GearScoreX', app.open, flags)
    app.open = open
    if not drawWin then ImGui.End(); return end

    E.ensureCache(app)
    do
        local w, sc = E.config.effectiveWeightsAndScale(app.settings)
        if app.slotA and app.slotA.stats then
            app.slotA.score = select(1, E.scoring.scoreItem(app.slotA.stats, w, sc))
        end
        if app.slotB and app.slotB.stats then
            app.slotB.score = select(1, E.scoring.scoreItem(app.slotB.stats, w, sc))
        end
    end

    drawForgeShelf()

    drawHeaderStrip(app)
    drawCandidateBanner(app)
    ImGui.Spacing()
    drawToolbarRow(app)

    ImGui.Spacing()
    ImGui.BeginChild('gsx_table_scroll', 0, -FOOTER_RESERVE, true, ImGuiWindowFlags.AlwaysVerticalScrollbar)
    drawGearTable(app)
    ImGui.EndChild()

    drawFooter(app)

    ImGui.End()
end

return M
