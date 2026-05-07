--- Ultimate sidebar + validation strip (separate chunk; Lua 5.1 limits locals per chunk).
--- Visual language: dark violet shell, rounded nav pills, high-contrast validation strip (UltimateEQAssist redesign).
local mq = require('mq')
local ImGui = require('ImGui')
local Icons = require('mq/Icons')
local globals = require('globals')
local utils = require('maui.utils')

--- Prefer global palette so sidebar matches init.lua Ultimate widgets exactly.
local function UeaPalette()
    return rawget(_G, 'UltimateAssistPalette')
end

local FALL_NAV_BG = {0.07, 0.05, 0.14, 1.0}

local ULT_NAV = {
    {id = 'setup', label = 'Setup',       icon = Icons.FA_COG or ''},
    {id = 'general', label = 'General',   icon = Icons.FA_LIST_ALT or Icons.FA_BARS or ''},
    {id = 'combat', label = 'Combat',     icon = Icons.FA_CROSSHAIRS or Icons.FA_SHIELD or ''},
    --- Labels match UltimateEQAssist mockup (nav ids unchanged for routing).
    {id = 'buffs', label = 'Buffs & Cures', icon = Icons.FA_STAR or Icons.FA_MAGIC or ''},
    {id = 'heals', label = 'Healing',     icon = Icons.FA_HEART or ''},
    {id = 'pet', label = 'Pet',           icon = Icons.FA_PAW or ''},
    {id = 'movement', label = 'Movement', icon = Icons.FA_COMPASS or Icons.FA_LOCATION_ARROW or ''},
    {id = 'utility', label = 'Utility',   icon = Icons.FA_WRENCH or ''},
    {id = 'spellset', label = 'SpellSet', icon = Icons.FA_DIAMOND or Icons.FA_STAR or ''},
    {id = '_sep', label = '', icon = ''},
    {id = 'tools', label = 'Tools',       icon = Icons.FA_HAMMER or Icons.FA_WRENCH or ''},
    {id = 'raw', label = 'RAW',           icon = Icons.FA_FILE_TEXT_O or Icons.FA_FILE or ''},
    {id = 'readme', label = 'Readme',     icon = Icons.FA_BOOK or ''},
}

local function ComputeUltimateValidationState(api)
    api.RefreshDirtyState()
    local dpsEnabled = api.IsSectionEnabled('DPS')
    local buffsEnabled = api.IsSectionEnabled('Buffs')
    local healsEnabled = api.IsSectionEnabled('Heals')
    local petEnabled = api.IsSectionEnabled('Pet')
    local warnings, fails = 0, 0

    if dpsEnabled and api.GetNumericValue('DPS', 'DPSSize', 0) == 0 then warnings = warnings + 1 end
    if buffsEnabled and api.GetNumericValue('Buffs', 'BuffsSize', 0) == 0 then warnings = warnings + 1 end
    if healsEnabled and api.GetNumericValue('Heals', 'HealsSize', 0) == 0 then warnings = warnings + 1 end
    if api.IsSectionEnabled('Cures') and api.GetNumericValue('Cures', 'CuresSize', 0) == 0 then warnings = warnings + 1 end
    if petEnabled and api.IsNullOrEmpty(api.EnsureConfigSection('Pet').PetSpell) then warnings = warnings + 1 end
    if api.ParseToggleValue(api.EnsureConfigSection('General').ChaseAssist) and api.ParseToggleValue(api.EnsureConfigSection('General').ReturnToCamp) then
        fails = fails + 1
    end
    if not dpsEnabled and not buffsEnabled and not healsEnabled and not petEnabled then
        warnings = warnings + 1
    end
    if api.ParseToggleValue(api.EnsureConfigSection('General').MedOn) and (api.GetNumericValue('General', 'MedStart', 20) < 15 or api.GetNumericValue('General', 'MedStart', 20) > 50) then
        warnings = warnings + 1
    end

    local level = 'pass'
    if fails > 0 then
        level = 'fail'
    elseif warnings > 0 then
        level = 'warn'
    end
    return {level = level, fails = fails, warnings = warnings}
end

local function DrawUltimateValidationBar(api)
    local st = ComputeUltimateValidationState(api)
    local r, g, b = 0.25, 0.78, 0.42
    if st.level == 'warn' then
        r, g, b = 0.95, 0.72, 0.18
    elseif st.level == 'fail' then
        r, g, b = 0.82, 0.38, 0.52
    end
    ImGui.PushStyleColor(ImGuiCol.ChildBg, r * 0.22, g * 0.18, b * 0.2, 0.95)
    ImGui.BeginChild('##UEA_ValidationStrip', -1, 34, ImGuiChildFlags.Border)
    ImGui.TextColored(r, g, b, 1, (Icons.FA_CIRCLE or '•') .. '  ')
    ImGui.SameLine()
    if st.level == 'pass' then
        ImGui.TextColored(0.78, 0.98, 0.85, 1, 'Validation PASS — setup looks safe to run')
    elseif st.level == 'fail' then
        ImGui.TextColored(1, 0.85, 0.82, 1, string.format('Validation FAIL — %d blocking issue(s) (see Setup)', st.fails))
    else
        ImGui.TextColored(1, 0.92, 0.75, 1, string.format('Validation WARN — %d notice(s)', st.warnings))
    end
    local saveW = 104
    local dirtyStr = 'Unsaved changes  '
    local dirtyW = api.getIsDirty() and ImGui.CalcTextSize(dirtyStr) or 0
    ImGui.SameLine()
    ImGui.SetCursorPosX(ImGui.GetCursorPosX() + math.max(0, ImGui.GetContentRegionAvail() - saveW - dirtyW - 4))
    if api.getIsDirty() then
        ImGui.TextColored(0.94, 0.70, 0.42, 1.0, dirtyStr)
        ImGui.SameLine()
    end
    if ImGui.Button('Save Config##valstrip', saveW, 0) then
        api.Save()
        globals.INIFileContents = utils.ReadRawINIFile()
        api.setBottomActionMsg('Config saved to INI')
    end
    ImGui.EndChild()
    ImGui.PopStyleColor(1)
end

local function DrawRawEditorPanel()
    local activeRawPath = (globals.INIFile and globals.INIFile ~= '') and (mq.configDir..'/'..globals.INIFile) or ''
    if activeRawPath == '' or not utils.FileExists(activeRawPath) then
        ImGui.TextColored(1.0, 0.35, 0.35, 1.0, 'Active INI file is missing. Select/import a valid INI before editing RAW.')
    end
    if not globals.INIFileContents then
        globals.INIFileContents = utils.ReadRawINIFile()
    end
    globals.INIFileContents,_ = ImGui.InputTextMultiline('##UEA_RAW_INI', globals.INIFileContents or '', -1, -42)
    if ImGui.Button('Save Raw') then
        if globals.INIFile and globals.INIFile ~= '' then
            local path = mq.configDir..'/'..globals.INIFile
            local f = io.open(path, 'w')
            if f then
                f:write(globals.INIFileContents or '')
                f:close()
                local reload = rawget(_G, 'ReloadINIFromDisk')
                if type(reload) == 'function' then reload() end
            end
        end
    end
    ImGui.SameLine()
    if ImGui.Button('Reload Raw') then
        globals.INIFileContents = utils.ReadRawINIFile()
    end
end

local function DrawUltimateSidebarNav(rt)
    local navId = rt.nav.id
    local P = UeaPalette()
    ImGui.PushStyleVar(ImGuiStyleVar.ItemSpacing, 6, 8)
    ImGui.PushStyleVar(ImGuiStyleVar.FrameRounding, 8)
    ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, 10, 9)
    for _, nav in ipairs(ULT_NAV) do
        if nav.id == '_sep' then
            ImGui.Spacing()
            ImGui.Separator()
            ImGui.Spacing()
        else
            local sel = (navId == nav.id)
            if sel then
                ImGui.PushStyleColor(ImGuiCol.Button, P and P.modeSel[1] or 0.38, P and P.modeSel[2] or 0.18, P and P.modeSel[3] or 0.62, P and P.modeSel[4] or 1)
                ImGui.PushStyleColor(ImGuiCol.ButtonHovered, P and P.modeSelHov[1] or 0.48, P and P.modeSelHov[2] or 0.24, P and P.modeSelHov[3] or 0.74, P and P.modeSelHov[4] or 1)
                ImGui.PushStyleColor(ImGuiCol.ButtonActive, P and P.modeSel[1] * 0.85 or 0.32, P and P.modeSel[2] * 0.85 or 0.14, P and P.modeSel[3] * 0.85 or 0.52, 1)
                ImGui.PushStyleColor(ImGuiCol.Text, 0.98, 0.96, 1.0, 1)
                ImGui.PushStyleColor(ImGuiCol.Border, P and P.modeSelBorder[1] or 0.55, P and P.modeSelBorder[2] or 0.35, P and P.modeSelBorder[3] or 0.85, P and P.modeSelBorder[4] or 0.85)
                ImGui.PushStyleVar(ImGuiStyleVar.FrameBorderSize, 1)
            else
                ImGui.PushStyleColor(ImGuiCol.Button, P and P.modeUnsel[1] or 0.12, P and P.modeUnsel[2] or 0.10, P and P.modeUnsel[3] or 0.20, P and P.modeUnsel[4] or 1)
                ImGui.PushStyleColor(ImGuiCol.ButtonHovered, P and P.modeUnselHov[1] or 0.20, P and P.modeUnselHov[2] or 0.16, P and P.modeUnselHov[3] or 0.32, P and P.modeUnselHov[4] or 1)
                ImGui.PushStyleColor(ImGuiCol.ButtonActive, P and P.modeUnsel[1] or 0.16, P and P.modeUnsel[2] or 0.13, P and P.modeUnsel[3] or 0.26, 1)
                ImGui.PushStyleColor(ImGuiCol.Text, P and P.textMuted[1] or 0.78, P and P.textMuted[2] or 0.74, P and P.textMuted[3] or 0.92, P and P.textMuted[4] or 1)
                ImGui.PushStyleColor(ImGuiCol.Border, P and P.modeUnselBorder[1] or 0.42, P and P.modeUnselBorder[2] or 0.26, P and P.modeUnselBorder[3] or 0.58, 0.45)
                ImGui.PushStyleVar(ImGuiStyleVar.FrameBorderSize, 1)
            end
            local label = (nav.icon ~= '' and (nav.icon .. '  ') or '') .. nav.label
            if ImGui.Button(label .. '##nav_' .. nav.id, -1, 0) then
                rt.nav.id = nav.id
            end
            ImGui.PopStyleVar(1)
            ImGui.PopStyleColor(5)
        end
    end
    ImGui.PopStyleVar(3)
    ImGui.Dummy(1, 6)
    ImGui.PushStyleVar(ImGuiStyleVar.FrameRounding, 6)
    if ImGui.Button('Classic - All Sections##nav_classic', -1, 0) then
        rt.nav.id = 'allsections'
    end
    ImGui.PopStyleVar(1)
end

local function SafeDrawSection(api, label, fn)
    local ok, err = pcall(fn)
    if not ok then
        print(string.format('[MAUI] UI section error [%s]: %s', tostring(label), tostring(err)))
        api.setBottomActionMsg(string.format('UI error in %s (see chat)', tostring(label)))
        ImGui.TextColored(1.0, 0.35, 0.35, 1.0, string.format('UI section failed: %s', tostring(label)))
    end
end

--- MQ ImGui: BeginTabBar/BeginTabItem inside Columns+BeginChild corrupts the child stack (Missing EndChild).
--- Use pill buttons + single content pane instead (same sub ids as before).
local function DrawUltimateSubTabs(items, selectedId, idPrefix, onPick)
    local P = UeaPalette()
    ImGui.PushStyleVar(ImGuiStyleVar.FrameRounding, 8)
    ImGui.PushStyleVar(ImGuiStyleVar.ItemSpacing, 8, 6)
    ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, 10, 6)
    for i, sub in ipairs(items) do
        if i > 1 then
            ImGui.SameLine(0, 8)
        end
        local sel = (selectedId == sub)
        if sel then
            ImGui.PushStyleColor(ImGuiCol.Button, P and P.modeSel[1] or 0.38, P and P.modeSel[2] or 0.18, P and P.modeSel[3] or 0.62, P and P.modeSel[4] or 1)
            ImGui.PushStyleColor(ImGuiCol.ButtonHovered, P and P.modeSelHov[1] or 0.48, P and P.modeSelHov[2] or 0.24, P and P.modeSelHov[3] or 0.74, P and P.modeSelHov[4] or 1)
            ImGui.PushStyleColor(ImGuiCol.ButtonActive, P and P.modeSel[1] * 0.85 or 0.32, P and P.modeSel[2] * 0.85 or 0.14, P and P.modeSel[3] * 0.85 or 0.52, 1)
            ImGui.PushStyleColor(ImGuiCol.Text, 0.98, 0.96, 1.0, 1)
            ImGui.PushStyleColor(ImGuiCol.Border, P and P.modeSelBorder[1] or 0.55, P and P.modeSelBorder[2] or 0.35, P and P.modeSelBorder[3] or 0.85, P and P.modeSelBorder[4] or 0.85)
            ImGui.PushStyleVar(ImGuiStyleVar.FrameBorderSize, 1)
        else
            ImGui.PushStyleColor(ImGuiCol.Button, P and P.modeUnsel[1] or 0.12, P and P.modeUnsel[2] or 0.10, P and P.modeUnsel[3] or 0.20, P and P.modeUnsel[4] or 1)
            ImGui.PushStyleColor(ImGuiCol.ButtonHovered, P and P.modeUnselHov[1] or 0.20, P and P.modeUnselHov[2] or 0.16, P and P.modeUnselHov[3] or 0.32, P and P.modeUnselHov[4] or 1)
            ImGui.PushStyleColor(ImGuiCol.ButtonActive, P and P.modeUnsel[1] or 0.16, P and P.modeUnsel[2] or 0.13, P and P.modeUnsel[3] or 0.26, 1)
            ImGui.PushStyleColor(ImGuiCol.Text, P and P.textMuted[1] or 0.78, P and P.textMuted[2] or 0.74, P and P.textMuted[3] or 0.92, P and P.textMuted[4] or 1)
            ImGui.PushStyleColor(ImGuiCol.Border, P and P.modeUnselBorder[1] or 0.42, P and P.modeUnselBorder[2] or 0.26, P and P.modeUnselBorder[3] or 0.58, 0.45)
            ImGui.PushStyleVar(ImGuiStyleVar.FrameBorderSize, 1)
        end
        if ImGui.Button(sub .. '##' .. idPrefix .. '_' .. sub, 0, 28) then
            onPick(sub)
        end
        ImGui.PopStyleVar(1)
        ImGui.PopStyleColor(5)
    end
    ImGui.PopStyleVar(3)
    ImGui.Spacing()
end

local function DrawUltimateNavContent(rt, api)
    local n = rt.nav
    if n.id == 'setup' then
        api.DrawSetupTab()
    elseif n.id == 'general' then
        api.DrawGeneralTab()
    elseif n.id == 'combat' then
        local subs = {'Aggro', 'Melee', 'DPS', 'Burn', 'GoM'}
        local okSub = false
        for _, s in ipairs(subs) do
            if n.combatSub == s then okSub = true break end
        end
        if not okSub then n.combatSub = 'Aggro' end
        DrawUltimateSubTabs(subs, n.combatSub, 'ult_c', function(sub)
            n.combatSub = sub
        end)
        SafeDrawSection(api, 'Combat/' .. n.combatSub, function()
            api.DrawSectionTab(n.combatSub)
        end)
    elseif n.id == 'buffs' then
        local subs = {'Buffs', 'Cures', 'AE'}
        local okSub = false
        for _, s in ipairs(subs) do
            if n.buffsSub == s then okSub = true break end
        end
        if not okSub then n.buffsSub = 'Buffs' end
        DrawUltimateSubTabs(subs, n.buffsSub, 'ult_b', function(sub)
            n.buffsSub = sub
        end)
        SafeDrawSection(api, 'Buffs/' .. n.buffsSub, function()
            api.DrawSectionTab(n.buffsSub)
        end)
    elseif n.id == 'heals' then
        local subs = {'Heals', 'OhShit', 'Mez'}
        local okSub = false
        for _, s in ipairs(subs) do
            if n.healsSub == s then okSub = true break end
        end
        if not okSub then n.healsSub = 'Heals' end
        DrawUltimateSubTabs(subs, n.healsSub, 'ult_h', function(sub)
            n.healsSub = sub
        end)
        SafeDrawSection(api, 'Heals/' .. n.healsSub, function()
            api.DrawSectionTab(n.healsSub)
        end)
    elseif n.id == 'pet' then
        SafeDrawSection(api, 'Pet', function()
            api.DrawSectionTab('Pet')
        end)
    elseif n.id == 'movement' then
        SafeDrawSection(api, 'Movement & Camping', api.DrawMovementCampingTab)
    elseif n.id == 'utility' then
        SafeDrawSection(api, 'Utility', api.DrawUtilityTab)
    elseif n.id == 'spellset' then
        rt.useGemRack = true
        SafeDrawSection(api, 'SpellSet', function()
            api.DrawSectionTab('SpellSet')
        end)
        rt.useGemRack = false
    elseif n.id == 'tools' then
        api.DrawIntegrationsTab()
    elseif n.id == 'raw' then
        DrawRawEditorPanel()
    elseif n.id == 'readme' then
        api.DrawReadmeTab()
    elseif n.id == 'allsections' then
        api.DrawWindowPanels()
    else
        ImGui.TextColored(1, 0.4, 0.4, 1, 'Unknown section')
    end
end

--- rt: MauiRuntime (nav subtable + useGemRack). api: closures from init.lua.
local function drawUltimateBody(rt, api)
    --- Reserve space for validation strip + 2–3 toolbar rows (wrapped on narrow windows).
    local footerH = 168
    -- MQ ImGui: Do NOT nest ImGui.Columns() with multiple BeginChild regions — stack corruption
    -- (Missing EndChild). Use sibling children: Nav EndChild -> SameLine -> Page BeginChild (Dear ImGui FAQ).
    ImGui.BeginChild('##UEA_MainStack', -1, -footerH, false)
    local navW = 204
    local gap = 8

    local Pn = UeaPalette()
    local nb = (Pn and Pn.navColumnBg) or FALL_NAV_BG
    ImGui.PushStyleColor(ImGuiCol.ChildBg, nb[1], nb[2], nb[3], nb[4])
    ImGui.BeginChild('##UEA_NavCol', navW, -1, ImGuiChildFlags.Border)
    DrawUltimateSidebarNav(rt)
    ImGui.EndChild()
    ImGui.PopStyleColor(1)

    --- Width MUST be taken after NavCol + SameLine — precomputed (avail - navW) ignores borders/padding
    --- and can make PageCol wider than the row, which corrupts MQ ImGui's child stack (Missing EndChild).
    ImGui.SameLine(0, gap)
    local pageW = ImGui.GetContentRegionAvail()
    if pageW < 1 then pageW = 1 end

    --- Inner padding so lists / InputInt steppers are not flush against the child border.
    ImGui.PushStyleVar(ImGuiStyleVar.WindowPadding, 12, 10)
    ImGui.PushStyleColor(ImGuiCol.ChildBg, 0.03, 0.04, 0.09, 1.0)
    ImGui.BeginChild('##UEA_PageCol', pageW, -1, ImGuiChildFlags.Border)
    SafeDrawSection(api, 'NavPage', function()
        DrawUltimateNavContent(rt, api)
    end)
    ImGui.EndChild()
    ImGui.PopStyleColor(1)
    ImGui.PopStyleVar(1)

    ImGui.EndChild()

    DrawUltimateValidationBar(api)
    SafeDrawSection(api, 'BottomBar', api.DrawUltimateBottomBar)
end

return {
    drawUltimateBody = drawUltimateBody,
}
