--[[
  UltimateInv — grid + list inventory views with EQ /itemnotify actions.
]]

local ImGui = require('ImGui')
local theme = require('UltimateInv.theme')
local snapshot_mod = require('UltimateInv.core.snapshot')
local icons = require('UltimateInv.ui.window')

local M = {}

local CELL_DEFAULT = 40

local function push_text_muted(msg)
    local r, g, b, a = theme.rgba_u32(theme.TEXT_MUTED)
    ImGui.TextColored(r, g, b, a, '%s', msg)
end

local function matches_search(text, needle)
    if not needle or needle == '' then
        return true
    end
    return tostring(text or ''):lower():find(needle:lower(), 1, true) ~= nil
end

local function draw_cell(app, row, uid)
    local mq = app.mq
    local anim_items = app.anim_items
    local anim_box = app.anim_box
    local offset = app.icon_offset
    local cell = app.cell_size or CELL_DEFAULT

    local cx, cy = ImGui.GetCursorPos()
    if anim_box then
        ImGui.DrawTextureAnimation(anim_box, cell, cell)
    end
    if row.icon and row.icon > 0 and anim_items then
        ImGui.SetCursorPos(cx, cy)
        anim_items:SetTextureCell(row.icon - offset)
        ImGui.DrawTextureAnimation(anim_items, cell, cell)
    end

    local qty = tonumber(row.qty) or 1
    if qty > 1 then
        ImGui.SetWindowFontScale(0.72)
        local stackStr = tostring(qty)
        local tw = select(1, ImGui.CalcTextSize(stackStr))
        ImGui.SetCursorPos(cx + cell - tw - 3, cy + cell - 16)
        ImGui.TextUnformatted(stackStr)
        ImGui.SetWindowFontScale(1.0)
    end

    ImGui.SetCursorPos(cx, cy)
    ImGui.PushStyleColor(ImGuiCol.Button, 0, 0, 0, 0)
    ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 0.25, 0.35, 0.55, 0.35)
    ImGui.PushStyleColor(ImGuiCol.ButtonActive, 0.35, 0.45, 0.65, 0.45)
    ImGui.Button('##c_' .. uid, cell, cell)
    ImGui.PopStyleColor(3)

    if ImGui.IsItemHovered() then
        ImGui.BeginTooltip()
        ImGui.TextUnformatted(row.name or 'Unknown')
        if row.where then
            local r, g, b, a = theme.rgba_u32(theme.TEXT_MUTED)
            ImGui.TextColored(r, g, b, a, '%s', row.where)
        end
        if row.notify_cmd then
            ImGui.Separator()
            ImGui.TextWrapped('Left-click = EQ slot click\n%s', row.notify_cmd)
            ImGui.TextWrapped('Right-click = /useitem (when supported)')
        end
        ImGui.EndTooltip()
    end

    if row.notify_cmd and ImGui.IsItemClicked(ImGuiMouseButton.Left) then
        pcall(function() mq.cmd(row.notify_cmd) end)
    end

    if row.name and row.name ~= '' and ImGui.IsItemClicked(ImGuiMouseButton.Right) then
        pcall(function() mq.cmdf('/useitem "%s"', row.name) end)
    end
end

function M.slot_cell(app, row, uid)
    draw_cell(app, row, uid)
end

local function row_from_equipped(e)
    return {
        icon = e.icon,
        name = e.name,
        qty = e.qty,
        where = e.label,
        notify_cmd = string.format('/nomodkey /shift /itemnotify %d leftmouseup', e.slot),
    }
end

local function row_from_pack_top(pack)
    return {
        icon = pack.icon,
        name = pack.name,
        qty = pack.qty,
        where = string.format('Pack %d bag', pack.pack_num),
        notify_cmd = string.format('/nomodkey /shift /itemnotify %d leftmouseup', pack.inv_slot),
    }
end

local function row_from_pack_item(pack, it)
    return {
        icon = it.icon,
        name = it.name,
        qty = it.qty,
        where = it.label,
        notify_cmd = string.format('/nomodkey /shift /itemnotify in pack%d %d leftmouseup', pack.pack_num, it.bag_slot),
    }
end

local function row_from_bank_top(b)
    return {
        icon = b.icon,
        name = b.name,
        qty = b.qty,
        where = b.label,
        notify_cmd = string.format('/nomodkey /shift /itemnotify bank%d leftmouseup', b.bank_slot),
    }
end

local function row_from_bank_item(b, it)
    return {
        icon = it.icon,
        name = it.name,
        qty = it.qty,
        where = it.label,
        notify_cmd = string.format('/nomodkey /shift /itemnotify in bank%d %d leftmouseup', b.bank_slot, it.bag_slot),
    }
end

function M.render_grid(app, snap, needle)
    ImGui.Spacing()

    local worn_title = string.format('Worn · %d piece(s)', #(snap.equipped or {}))
    if ImGui.CollapsingHeader(worn_title, ImGuiTreeNodeFlags.DefaultOpen) then
        local cols = app.grid_cols or 8
        local n = 0
        local col = 0
        if ImGui.BeginTable('worn_grid', cols, ImGuiTableFlags.BordersInner) then
            for _, e in ipairs(snap.equipped or {}) do
                local r = row_from_equipped(e)
                if matches_search(r.name, needle) then
                    if col == 0 then
                        ImGui.TableNextRow()
                    end
                    ImGui.TableNextColumn()
                    draw_cell(app, r, 'w' .. e.slot)
                    col = col + 1
                    if col >= cols then
                        col = 0
                    end
                    n = n + 1
                end
            end
            ImGui.EndTable()
        end
        if n == 0 then
            push_text_muted('No worn items match filter.')
        end
    end

    local packKeys = {}
    for k in pairs(snap.packs or {}) do
        packKeys[#packKeys + 1] = k
    end
    table.sort(packKeys)

    for _, invSlot in ipairs(packKeys) do
        local pack = snap.packs[invSlot]
        if pack then
            local title = string.format('Pack %d · %s', pack.pack_num, pack.name or 'Bag')
            if ImGui.CollapsingHeader(title) then
                local top = row_from_pack_top(pack)
                if matches_search(top.name, needle) then
                    ImGui.TextUnformatted('Bag on character')
                    ImGui.SameLine()
                    draw_cell(app, top, 'pt' .. pack.inv_slot)
                    ImGui.Spacing()
                end
                local inner_n = 0
                local col = 0
                local cols = app.grid_cols or 6
                if ImGui.BeginTable('pk_' .. pack.pack_num, cols, ImGuiTableFlags.BordersInner) then
                    for _, it in ipairs(pack.contents or {}) do
                        local r = row_from_pack_item(pack, it)
                        if matches_search(r.name, needle) then
                            if col == 0 then
                                ImGui.TableNextRow()
                            end
                            ImGui.TableNextColumn()
                            draw_cell(app, r, string.format('p%d_%d', pack.pack_num, it.bag_slot))
                            col = col + 1
                            if col >= cols then
                                col = 0
                            end
                            inner_n = inner_n + 1
                        end
                    end
                    ImGui.EndTable()
                end
                if inner_n == 0 then
                    push_text_muted('No items in this bag (or hidden by filter).')
                end
            end
        end
    end

    if app.include_bank then
        if ImGui.CollapsingHeader('Bank') then
            for _, b in ipairs(snap.bank or {}) do
                ImGui.PushID('bk' .. b.bank_slot)
                local top = row_from_bank_top(b)
                if matches_search(top.name, needle) then
                    ImGui.TextUnformatted(string.format('Bank slot %d', b.bank_slot))
                    ImGui.SameLine()
                    draw_cell(app, top, 'bt' .. b.bank_slot)
                    ImGui.Spacing()
                end
                local col = 0
                local cols = app.grid_cols or 6
                if ImGui.BeginTable('bnk_' .. b.bank_slot, cols, ImGuiTableFlags.BordersInner) then
                    for _, it in ipairs(b.contents or {}) do
                        local r = row_from_bank_item(b, it)
                        if matches_search(r.name, needle) then
                            if col == 0 then
                                ImGui.TableNextRow()
                            end
                            ImGui.TableNextColumn()
                            draw_cell(app, r, string.format('bi%d_%d', b.bank_slot, it.bag_slot))
                            col = col + 1
                            if col >= cols then
                                col = 0
                            end
                        end
                    end
                    ImGui.EndTable()
                end
                ImGui.PopID()
            end
        end
    end
end

local LIST_FLAGS = bit32.bor(ImGuiTableFlags.Resizable, ImGuiTableFlags.RowBg, ImGuiTableFlags.BordersOuter,
    ImGuiTableFlags.ScrollY, ImGuiTableFlags.SizingStretchProp)

function M.render_list(app, rows, avail_h)
    local table_h = math.max(220, (type(avail_h) == 'number' and avail_h) or 280)

    if ImGui.BeginTable('inv_list', 5, LIST_FLAGS, -1, table_h) then
        ImGui.TableSetupScrollFreeze(0, 1)
        ImGui.TableSetupColumn('##ic', ImGuiTableColumnFlags.WidthFixed, 36)
        ImGui.TableSetupColumn('Item', ImGuiTableColumnFlags.WidthStretch)
        ImGui.TableSetupColumn('Qty', ImGuiTableColumnFlags.WidthFixed, 44)
        ImGui.TableSetupColumn('Where', ImGuiTableColumnFlags.WidthStretch)
        ImGui.TableSetupColumn('Pick', ImGuiTableColumnFlags.WidthFixed, 44)
        ImGui.TableHeadersRow()

        for idx, r in ipairs(rows) do
            ImGui.TableNextRow()
            ImGui.TableNextColumn()
            icons.draw_icon(app.anim_items, r.icon, app.icon_offset)
            ImGui.TableNextColumn()
            local cx = select(1, ImGui.GetCursorPos())
            ImGui.PushTextWrapPos(cx + ImGui.GetFontSize() * 52)
            ImGui.TextWrapped('%s', r.name or '')
            ImGui.PopTextWrapPos()
            ImGui.TableNextColumn()
            ImGui.Text('%s', tostring(r.qty or 0))
            ImGui.TableNextColumn()
            do
                local r1, g1, b1, a1 = theme.rgba_u32(theme.TEXT_MUTED)
                ImGui.TextColored(r1, g1, b1, a1, '%s', r.where or '')
            end
            ImGui.TableNextColumn()
            if r.notify_cmd then
                if ImGui.SmallButton('Pick##' .. idx) then
                    pcall(function() app.mq.cmd(r.notify_cmd) end)
                end
            end
        end
        ImGui.EndTable()
    end
end

function M.render_center(app)
    app.include_bank = ImGui.Checkbox('Include bank rows##bank', app.include_bank)

    if app.view_grid == nil then
        app.view_grid = true
    end
    app.view_grid = ImGui.Checkbox('Grid view##vg', app.view_grid)

    app.search_buf = ImGui.InputText('##inv_search', app.search_buf or '')
    ImGui.SameLine()
    do
        local r, g, b, a = theme.rgba_u32(theme.TEXT_MUTED)
        ImGui.TextColored(r, g, b, a, '%s', 'Filter')
    end

    if app.view_grid then
        app.grid_cols = app.grid_cols or 8
        local nc = ImGui.SliderInt('Icons per row', app.grid_cols, 4, 12)
        if type(nc) == 'number' then app.grid_cols = nc end
        app.cell_size = app.cell_size or CELL_DEFAULT
        local cs = ImGui.SliderInt('Icon size', app.cell_size, 32, 64)
        if type(cs) == 'number' then app.cell_size = cs end
    end

    local snap = app.get_snapshot()
    local needle = app.search_buf or ''

    if app.view_grid then
        M.render_grid(app, snap, needle)
    else
        local rows = {}
        for _, r in ipairs(snapshot_mod.flatten(snap)) do
            if matches_search(r.name, needle) or matches_search(r.where, needle) then
                rows[#rows + 1] = r
            end
        end
        do
            local r, g, b, a = theme.rgba_u32(theme.TEXT_MUTED)
            ImGui.TextColored(r, g, b, a, '%s', string.format('%d row(s)', #rows))
        end
        local _, ah = ImGui.GetContentRegionAvail()
        M.render_list(app, rows, ah)
    end
end

return M
