--[[
  UltimateInv — single window, no tabs: stats + inventory + modifiers/currency (columns).
]]

local ImGui = require('ImGui')
local theme = require('UltimateInv.theme')
local inv_panel = require('UltimateInv.ui.inventory_panel')
local alt_currency = require('UltimateInv.core.alt_currency')

local M = {}

local function fit_window_to_screen()
    local vw, vh = 1280, 720
    local ok, vp = pcall(function()
        return ImGui.GetMainViewport()
    end)
    if ok and vp and vp.WorkSize then
        local ws = vp.WorkSize
        if type(ws.x) == 'number' and type(ws.y) == 'number' then
            vw, vh = ws.x, ws.y
        elseif ws[1] and ws[2] then
            vw, vh = ws[1], ws[2]
        end
    end

    local w = math.floor(math.min(vw * 0.32, 520))
    local h = math.floor(math.min(vh * 0.40, 480))
    w = math.max(380, math.min(w, math.floor(vw * 0.82)))
    h = math.max(300, math.min(h, math.floor(vh * 0.82)))

    pcall(function()
        ImGui.SetNextWindowSizeConstraints(360, 280, math.floor(vw * 0.88), math.floor(vh * 0.88))
    end)
    ImGui.SetNextWindowSize(w, h, ImGuiCond.FirstUseEver)
end

local function bar_w()
    local x = select(1, ImGui.GetContentRegionAvail())
    if type(x) ~= 'number' or x < 80 then
        return 200
    end
    return x
end

local function push_text_u32(u32)
    local r, g, b, a = theme.rgba_u32(u32)
    ImGui.PushStyleColor(ImGuiCol.Text, r, g, b, a)
end

local function section_title(text)
    ImGui.Spacing()
    push_text_u32(theme.ACCENT_GOLD)
    ImGui.TextUnformatted(text)
    ImGui.PopStyleColor()
    ImGui.Separator()
end

local function kv_line(label, value)
    push_text_u32(theme.TEXT_MUTED)
    ImGui.Text('%s', label)
    ImGui.PopStyleColor()
    ImGui.SameLine(118)
    ImGui.Text('%s', tostring(value))
end

local function draw_vital_bar(label, cur, maxv, pct, r, g, b)
    ImGui.TextColored(r, g, b, 1, '%s', label)
    ImGui.ProgressBar((pct or 0) / 100, bar_w(), 14, string.format('%s / %s', cur, maxv))
end

local function draw_left(profile)
    section_title('Identity')
    kv_line('Name', profile.identity.name)
    kv_line('Level', profile.identity.level)
    kv_line('Class', profile.identity.class)
    kv_line('Server', profile.identity.server)
    if profile.identity.aa_title ~= '' then
        kv_line('AA Title', profile.identity.aa_title)
    end

    section_title('Vitals')
    draw_vital_bar('HP', profile.vitals.hp_cur, profile.vitals.hp_max, profile.vitals.hp_pct, 0.35, 0.82, 0.45)
    draw_vital_bar('Mana', profile.vitals.mana_cur, profile.vitals.mana_max, profile.vitals.mana_pct, 0.35, 0.65, 0.98)
    draw_vital_bar('Endurance', profile.vitals.end_cur, profile.vitals.end_max, profile.vitals.end_pct, 0.72, 0.58, 0.95)

    section_title('Combat')
    kv_line('AC', profile.combat.ac)
    kv_line('ATK', profile.combat.atk)
    kv_line('Attack Speed', profile.combat.haste)

    section_title('Attributes')
    if ImGui.BeginTable('attr_tbl', 4, ImGuiTableFlags.BordersInnerV) then
        ImGui.TableSetupColumn('Stat')
        ImGui.TableSetupColumn('Total')
        ImGui.TableSetupColumn('Base')
        ImGui.TableSetupColumn('Heroic')
        ImGui.TableHeadersRow()
        for _, a in ipairs(profile.attrs) do
            ImGui.TableNextRow()
            ImGui.TableNextColumn()
            ImGui.Text('%s', a.tag)
            ImGui.TableNextColumn()
            ImGui.Text('%d', a.total)
            ImGui.TableNextColumn()
            ImGui.Text('%d', a.base)
            ImGui.TableNextColumn()
            ImGui.Text('%d', a.heroic)
        end
        ImGui.EndTable()
    end

    section_title('Resists')
    for _, rs in ipairs(profile.resists) do
        kv_line(rs.label, rs.v)
    end

    section_title('Weight & coins')
    local wtxt = profile.weight.cap and profile.weight.cap > 0
        and string.format('%d / %d', profile.weight.cur, profile.weight.cap)
        or string.format('%d', profile.weight.cur)
    kv_line('Weight', wtxt)
    kv_line('Platinum', profile.coins.platinum)
    kv_line('Gold', profile.coins.gold)
    kv_line('Silver', profile.coins.silver)
    kv_line('Copper', profile.coins.copper)
end

local function draw_center(profile, app)
    section_title('Experience')
    ImGui.Text('Level')
    ImGui.ProgressBar(profile.progress.pct_exp / 100, bar_w(), 14, string.format('%.1f%%', profile.progress.pct_exp))
    ImGui.Text('Alternate Advancement')
    ImGui.ProgressBar(profile.progress.pct_aa / 100, bar_w(), 14, string.format('%.1f%%', profile.progress.pct_aa))

    section_title('Inventory')
    inv_panel.render_center(app)
end

local function draw_right(profile, app)
    section_title('Modifiers')
    if ImGui.BeginChild('mods_child', 0, 130, true) then
        for _, m in ipairs(profile.mods) do
            if m.value ~= nil then
                kv_line(m.label, m.value)
            end
        end
        ImGui.EndChild()
    end

    section_title('Skills')
    push_text_u32(theme.TEXT_MUTED)
    ImGui.TextWrapped('Extend core/me_profile.lua if you need Me.Skill() rows.')
    ImGui.PopStyleColor()

    section_title('Alternate currency')
    if app.altcur_show_zero == nil then
        app.altcur_show_zero = false
    end
    app.altcur_show_zero = ImGui.Checkbox('Show zero balances##acz', app.altcur_show_zero)
    if ImGui.BeginChild('tier_child', 0, 150, true) then
        local cur_rows = alt_currency.snapshot(app.mq, { show_zero = app.altcur_show_zero })
        if #cur_rows == 0 then
            local r, g, b, a = theme.rgba_u32(theme.TEXT_MUTED)
            ImGui.TextColored(r, g, b, a, '%s', 'No rows (edit UltimateInv/core/alt_currency.lua).')
        elseif ImGui.BeginTable('tier_tbl', 2, ImGuiTableFlags.RowBg) then
            ImGui.TableSetupColumn('Currency')
            ImGui.TableSetupColumn('Qty', ImGuiTableColumnFlags.WidthFixed, 88)
            ImGui.TableHeadersRow()
            for _, t in ipairs(cur_rows) do
                ImGui.TableNextRow()
                ImGui.TableNextColumn()
                ImGui.TextWrapped('%s', t.name)
                ImGui.TableNextColumn()
                ImGui.Text('%s', tostring(t.qty))
            end
            ImGui.EndTable()
        end
        ImGui.EndChild()
    end
end

local function draw_bottom_bar(app, mq)
    if ImGui.Button('EQ inventory') then pcall(function() mq.cmd('/inventory') end) end
    ImGui.SameLine()
    if ImGui.Button('Skills') then pcall(function() mq.cmd('/skills') end) end
    ImGui.SameLine()
    if ImGui.Button('Alt. Adv.') then pcall(function() mq.cmd('/aa') end) end
    ImGui.SameLine()
    if ImGui.Button('Face') then pcall(function() mq.cmd('/face') end) end
    ImGui.SameLine()
    if ImGui.Button('Dye') then pcall(function() mq.cmd('/dye') end) end
    ImGui.SameLine()
    if ImGui.Button('Done') then
        app.visible = false
        app.win_open = false
    end
end

function M.render(app)
    local mq = app.mq
    if not app.visible then
        return
    end

    fit_window_to_screen()

    theme.push_dashboard()

    app.win_open, _ = ImGui.Begin('UltimateInv', app.win_open, ImGuiWindowFlags.None)

    push_text_u32(theme.TEXT_MUTED)
    ImGui.TextWrapped('Overlay: /itemnotify clicks · Use EQ inventory for drag/drop.')
    ImGui.PopStyleColor()

    local prof = app.get_profile()

    if ImGui.BeginTable('##main_board', 3, bit32.bor(ImGuiTableFlags.SizingFixedFit, ImGuiTableFlags.BordersInnerV)) then
        ImGui.TableSetupColumn('##a', ImGuiTableColumnFlags.WidthFixed, 228)
        ImGui.TableSetupColumn('##b', ImGuiTableColumnFlags.WidthStretch)
        ImGui.TableSetupColumn('##c', ImGuiTableColumnFlags.WidthFixed, 236)
        ImGui.TableNextRow()
        ImGui.TableNextColumn()
        if ImGui.BeginChild('col_left', 0, 0, false) then
            draw_left(prof)
            ImGui.EndChild()
        end
        ImGui.TableNextColumn()
        if ImGui.BeginChild('col_mid', 0, 0, false) then
            draw_center(prof, app)
            ImGui.EndChild()
        end
        ImGui.TableNextColumn()
        if ImGui.BeginChild('col_right', 0, 0, false) then
            draw_right(prof, app)
            ImGui.EndChild()
        end
        ImGui.EndTable()
    end

    ImGui.Spacing()
    draw_bottom_bar(app, mq)

    ImGui.End()
    theme.pop_dashboard()

    if not app.win_open then
        app.visible = false
    end
end

return M
