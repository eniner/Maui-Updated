local mq = require('mq')
local imgui = require('ImGui')

local themesModule = require('themes')
local progression = require('data_progression')
local content = require('content')

local openGUI = true
local selectedCategory = '11.1'
local currentTheme = 1
local autoTrackEnabled = false
local autoTrackLastMsg = ''
local sidebarSearchText = ''
local defaultWindowW, defaultWindowH = 1150, 850
local settingsFile = 'pro_settings.lua'
local minWindowW, minWindowH = 980, 700
local maxWindowW, maxWindowH = 1800, 1200

do
    local mqRoot = mq.TLO and mq.TLO.MacroQuest and mq.TLO.MacroQuest.Path and mq.TLO.MacroQuest.Path()
    if mqRoot and mqRoot ~= '' then
        settingsFile = mqRoot .. '\\lua\\pro\\pro_settings.lua'
    end
end

local defaultTextColors = {
    title = { 0.95, 0.82, 0.32, 1.0 },
    section = { 0.86, 0.62, 0.96, 1.0 },
    subsection = { 0.73, 0.80, 1.0, 1.0 },
    body = { 0.92, 0.92, 0.95, 1.0 },
    bullet = { 0.60, 0.88, 0.98, 1.0 },
    emphasis = { 1.0, 0.88, 0.45, 1.0 },
    warning = { 1.0, 0.52, 0.52, 1.0 },
}

local textPresets = {
    {
        name = 'Balanced',
        colors = {
            title = { 0.95, 0.82, 0.32, 1.0 },
            section = { 0.86, 0.62, 0.96, 1.0 },
            subsection = { 0.73, 0.80, 1.0, 1.0 },
            body = { 0.92, 0.92, 0.95, 1.0 },
            bullet = { 0.60, 0.88, 0.98, 1.0 },
            emphasis = { 1.0, 0.88, 0.45, 1.0 },
            warning = { 1.0, 0.52, 0.52, 1.0 },
        }
    },
    {
        name = 'Cool Blue',
        colors = {
            title = { 0.70, 0.88, 1.0, 1.0 },
            section = { 0.58, 0.76, 1.0, 1.0 },
            subsection = { 0.64, 0.90, 1.0, 1.0 },
            body = { 0.88, 0.94, 1.0, 1.0 },
            bullet = { 0.55, 0.90, 1.0, 1.0 },
            emphasis = { 0.82, 0.95, 1.0, 1.0 },
            warning = { 1.0, 0.58, 0.58, 1.0 },
        }
    },
    {
        name = 'Warm Gold',
        colors = {
            title = { 1.0, 0.84, 0.35, 1.0 },
            section = { 0.98, 0.72, 0.48, 1.0 },
            subsection = { 1.0, 0.86, 0.60, 1.0 },
            body = { 0.96, 0.92, 0.84, 1.0 },
            bullet = { 1.0, 0.82, 0.52, 1.0 },
            emphasis = { 1.0, 0.92, 0.60, 1.0 },
            warning = { 1.0, 0.56, 0.46, 1.0 },
        }
    },
    {
        name = 'Monochrome',
        colors = {
            title = { 0.95, 0.95, 0.95, 1.0 },
            section = { 0.82, 0.82, 0.82, 1.0 },
            subsection = { 0.72, 0.72, 0.72, 1.0 },
            body = { 0.90, 0.90, 0.90, 1.0 },
            bullet = { 0.78, 0.78, 0.78, 1.0 },
            emphasis = { 1.0, 1.0, 1.0, 1.0 },
            warning = { 1.0, 0.62, 0.62, 1.0 },
        }
    },
    {
        name = 'Violet Mist',
        colors = {
            title = { 0.93, 0.78, 1.0, 1.0 },
            section = { 0.80, 0.66, 0.96, 1.0 },
            subsection = { 0.72, 0.74, 1.0, 1.0 },
            body = { 0.93, 0.90, 0.98, 1.0 },
            bullet = { 0.76, 0.88, 1.0, 1.0 },
            emphasis = { 0.98, 0.86, 1.0, 1.0 },
            warning = { 1.0, 0.58, 0.68, 1.0 },
        }
    },
    {
        name = 'Forest Mint',
        colors = {
            title = { 0.74, 1.0, 0.84, 1.0 },
            section = { 0.58, 0.90, 0.72, 1.0 },
            subsection = { 0.62, 0.96, 0.88, 1.0 },
            body = { 0.86, 0.98, 0.90, 1.0 },
            bullet = { 0.54, 0.94, 0.76, 1.0 },
            emphasis = { 0.80, 1.0, 0.86, 1.0 },
            warning = { 1.0, 0.62, 0.52, 1.0 },
        }
    },
    {
        name = 'Amber Night',
        colors = {
            title = { 1.0, 0.86, 0.44, 1.0 },
            section = { 0.96, 0.74, 0.42, 1.0 },
            subsection = { 1.0, 0.84, 0.58, 1.0 },
            body = { 0.98, 0.92, 0.80, 1.0 },
            bullet = { 1.0, 0.80, 0.48, 1.0 },
            emphasis = { 1.0, 0.92, 0.62, 1.0 },
            warning = { 1.0, 0.56, 0.46, 1.0 },
        }
    },
    {
        name = 'High Contrast',
        colors = {
            title = { 1.0, 1.0, 1.0, 1.0 },
            section = { 0.92, 0.92, 0.92, 1.0 },
            subsection = { 0.82, 0.82, 0.82, 1.0 },
            body = { 0.98, 0.98, 0.98, 1.0 },
            bullet = { 0.85, 0.95, 1.0, 1.0 },
            emphasis = { 1.0, 0.92, 0.52, 1.0 },
            warning = { 1.0, 0.45, 0.45, 1.0 },
        }
    },
    {
        name = 'Molten Orange',
        colors = {
            title = { 1.0, 0.74, 0.28, 1.0 },
            section = { 1.0, 0.62, 0.30, 1.0 },
            subsection = { 1.0, 0.78, 0.44, 1.0 },
            body = { 0.98, 0.90, 0.82, 1.0 },
            bullet = { 1.0, 0.72, 0.42, 1.0 },
            emphasis = { 1.0, 0.84, 0.56, 1.0 },
            warning = { 1.0, 0.45, 0.38, 1.0 },
        }
    },
    {
        name = 'Solar Gold',
        colors = {
            title = { 1.0, 0.90, 0.36, 1.0 },
            section = { 1.0, 0.84, 0.30, 1.0 },
            subsection = { 1.0, 0.92, 0.52, 1.0 },
            body = { 1.0, 0.97, 0.86, 1.0 },
            bullet = { 1.0, 0.88, 0.46, 1.0 },
            emphasis = { 1.0, 0.95, 0.62, 1.0 },
            warning = { 1.0, 0.56, 0.42, 1.0 },
        }
    },
    {
        name = 'Crimson Ember',
        colors = {
            title = { 1.0, 0.56, 0.50, 1.0 },
            section = { 0.98, 0.46, 0.44, 1.0 },
            subsection = { 1.0, 0.64, 0.56, 1.0 },
            body = { 0.98, 0.88, 0.88, 1.0 },
            bullet = { 1.0, 0.62, 0.58, 1.0 },
            emphasis = { 1.0, 0.78, 0.66, 1.0 },
            warning = { 1.0, 0.34, 0.34, 1.0 },
        }
    },
    {
        name = 'Copper Sand',
        colors = {
            title = { 0.96, 0.74, 0.52, 1.0 },
            section = { 0.90, 0.62, 0.42, 1.0 },
            subsection = { 0.98, 0.78, 0.58, 1.0 },
            body = { 0.95, 0.89, 0.82, 1.0 },
            bullet = { 0.94, 0.70, 0.52, 1.0 },
            emphasis = { 1.0, 0.84, 0.66, 1.0 },
            warning = { 0.96, 0.40, 0.34, 1.0 },
        }
    },
    {
        name = 'Lava Contrast',
        colors = {
            title = { 1.0, 0.62, 0.22, 1.0 },
            section = { 1.0, 0.50, 0.18, 1.0 },
            subsection = { 1.0, 0.72, 0.38, 1.0 },
            body = { 1.0, 0.92, 0.84, 1.0 },
            bullet = { 1.0, 0.66, 0.30, 1.0 },
            emphasis = { 1.0, 0.86, 0.50, 1.0 },
            warning = { 1.0, 0.30, 0.24, 1.0 },
        }
    },
    {
        name = 'Harvest Wheat',
        colors = {
            title = { 0.98, 0.82, 0.48, 1.0 },
            section = { 0.94, 0.72, 0.40, 1.0 },
            subsection = { 1.0, 0.86, 0.58, 1.0 },
            body = { 0.97, 0.93, 0.84, 1.0 },
            bullet = { 0.98, 0.80, 0.50, 1.0 },
            emphasis = { 1.0, 0.90, 0.66, 1.0 },
            warning = { 0.95, 0.50, 0.36, 1.0 },
        }
    },
}

local recommendedCombos = {
    {
        name = 'Readability Balanced',
        themeName = 'Slate Mono',
        textPresetName = 'Balanced',
        description = 'Neutral contrast and clean labels for long reading sessions.',
    },
    {
        name = 'Readability High Contrast',
        themeName = 'Ice Blue',
        textPresetName = 'High Contrast',
        description = 'Crisp separation for dense pages and faster scanning.',
    },
    {
        name = 'Night Mode Soft',
        themeName = 'Royal Indigo',
        textPresetName = 'Violet Mist',
        description = 'Lower glare and softer accents for dark rooms.',
    },
    {
        name = 'Night Mode Warm',
        themeName = 'Crimson Noir',
        textPresetName = 'Amber Night',
        description = 'Warm low-light palette that stays readable at night.',
    },
    {
        name = 'Colorblind Safe',
        themeName = 'Slate Mono',
        textPresetName = 'Monochrome',
        description = 'Reduced hue dependence with grayscale-forward text hierarchy.',
    },
}

local function copyColorTable(src)
    local out = {}
    for key, rgba in pairs(src or {}) do
        out[key] = { rgba[1], rgba[2], rgba[3], rgba[4] }
    end
    return out
end

local textColorsByTheme = {}
for i = 1, #themesModule.themes do
    textColorsByTheme[i] = copyColorTable(defaultTextColors)
end
local activeTextPresetName = 'Balanced'

local function findTextPresetByName(presetName)
    for _, preset in ipairs(textPresets) do
        if preset.name == presetName then
            return preset
        end
    end
    return nil
end

local function applyActiveTextPresetToTheme(themeIndex)
    local preset = findTextPresetByName(activeTextPresetName)
    if not preset then
        return
    end
    textColorsByTheme[themeIndex] = copyColorTable(preset.colors)
end

local function clampColorValue(v)
    local n = tonumber(v) or 0
    if n < 0 then return 0 end
    if n > 1 then return 1 end
    return n
end

local function normalizeColorSet(src)
    local out = copyColorTable(defaultTextColors)
    for key, rgba in pairs(src or {}) do
        if type(rgba) == 'table' and #rgba >= 4 then
            out[key] = {
                clampColorValue(rgba[1]),
                clampColorValue(rgba[2]),
                clampColorValue(rgba[3]),
                clampColorValue(rgba[4]),
            }
        end
    end
    return out
end

local function saveUiSettings()
    local handle = io.open(settingsFile, 'w')
    if not handle then
        return
    end

    handle:write('return {\n')
    handle:write(('  currentTheme = %d,\n'):format(currentTheme))
    handle:write(("  activeTextPresetName = '%s',\n"):format(activeTextPresetName:gsub("'", "\\'")))
    handle:write(('  autoTrackEnabled = %s,\n'):format(autoTrackEnabled and 'true' or 'false'))
    handle:write('  textColorsByTheme = {\n')
    for i = 1, #themesModule.themes do
        local set = textColorsByTheme[i] or defaultTextColors
        handle:write(('    [%d] = {\n'):format(i))
        for _, key in ipairs({ 'title', 'section', 'subsection', 'body', 'bullet', 'emphasis', 'warning' }) do
            local c = set[key] or defaultTextColors[key]
            handle:write(("      %s = { %.4f, %.4f, %.4f, %.4f },\n"):format(
                key, clampColorValue(c[1]), clampColorValue(c[2]), clampColorValue(c[3]), clampColorValue(c[4])
            ))
        end
        handle:write('    },\n')
    end
    handle:write('  },\n')
    handle:write('}\n')
    handle:close()
end

local function loadUiSettings()
    local ok, loaded = pcall(dofile, settingsFile)
    if not ok or type(loaded) ~= 'table' then
        return
    end

    if tonumber(loaded.currentTheme) and themesModule.themes[loaded.currentTheme] then
        currentTheme = loaded.currentTheme
    end
    if type(loaded.activeTextPresetName) == 'string' and findTextPresetByName(loaded.activeTextPresetName) then
        activeTextPresetName = loaded.activeTextPresetName
    end
    if type(loaded.autoTrackEnabled) == 'boolean' then
        autoTrackEnabled = loaded.autoTrackEnabled
    end

    if type(loaded.textColorsByTheme) == 'table' then
        for i = 1, #themesModule.themes do
            local colorSet = loaded.textColorsByTheme[i]
            if type(colorSet) == 'table' then
                textColorsByTheme[i] = normalizeColorSet(colorSet)
            end
        end
    end
end

loadUiSettings()

local function findThemeIndexByName(themeName)
    for i, theme in ipairs(themesModule.themes or {}) do
        if theme.name == themeName then
            return i
        end
    end
    return nil
end

local function applyThemeAndTextCombo(combo)
    if not combo then
        return
    end

    local themeIndex = findThemeIndexByName(combo.themeName)
    if themeIndex then
        currentTheme = themeIndex
    end

    if combo.textPresetName then
        activeTextPresetName = combo.textPresetName
        for _, preset in ipairs(textPresets) do
            if preset.name == combo.textPresetName then
                textColorsByTheme[currentTheme] = copyColorTable(preset.colors)
                break
            end
        end
    end

    saveUiSettings()
end

local helpThemeController = {
    getThemes = function()
        return themesModule.themes
    end,
    getCurrentTheme = function()
        return currentTheme
    end,
    setCurrentTheme = function(index)
        if themesModule.themes[index] then
            currentTheme = index
            applyActiveTextPresetToTheme(currentTheme)
            saveUiSettings()
        end
    end,
    getTextColors = function()
        return textColorsByTheme[currentTheme] or copyColorTable(defaultTextColors)
    end,
    getTextPresetNames = function()
        local names = {}
        for _, preset in ipairs(textPresets) do
            names[#names + 1] = preset.name
        end
        return names
    end,
    applyTextPreset = function(presetName)
        for _, preset in ipairs(textPresets) do
            if preset.name == presetName then
                activeTextPresetName = presetName
                textColorsByTheme[currentTheme] = copyColorTable(preset.colors)
                saveUiSettings()
                return
            end
        end
    end,
    resetTextColors = function()
        activeTextPresetName = 'Balanced'
        textColorsByTheme[currentTheme] = copyColorTable(defaultTextColors)
        saveUiSettings()
    end,
    getRecommendedCombos = function()
        return recommendedCombos
    end,
    applyRecommendedCombo = function(comboName)
        for _, combo in ipairs(recommendedCombos) do
            if combo.name == comboName then
                applyThemeAndTextCombo(combo)
                return
            end
        end
    end,
}

content.setThemeController(helpThemeController)

local function normalizeSearchText(text)
    local t = tostring(text or ''):lower()
    t = t:gsub('[%p]', ' ')
    t = t:gsub('%s+', ' ')
    return t:gsub('^%s+', ''):gsub('%s+$', '')
end

local function labelMatchesSearch(label)
    local needle = normalizeSearchText(sidebarSearchText)
    if needle == '' then
        return true
    end
    local hay = normalizeSearchText(label)
    return hay:find(needle, 1, true) ~= nil
end

local function drawList(items)
    local shown = 0
    for _, item in ipairs(items) do
        if labelMatchesSearch(item.label) then
            shown = shown + 1
            if imgui.Selectable(item.label, selectedCategory == item.id) then
                selectedCategory = item.id
            end
        end
    end
    return shown
end

local function drawHelpSystemsTab()
    imgui.BeginChild('Sidebar', 320, 0, true)
    local okSidebar, errSidebar = pcall(function()
        local newSearch, changed = imgui.InputText('Search##sidebar', sidebarSearchText, 128)
        if changed then
            sidebarSearchText = newSearch
        end
        if sidebarSearchText ~= '' then
            imgui.SameLine()
            if imgui.SmallButton('Clear##sidebar_search') then
                sidebarSearchText = ''
            end
        end
        imgui.Separator()

        imgui.TextColored(0.5, 0.5, 0.5, 1.0, '--- SERVER FUNDAMENTALS ---')
        drawList(progression.fundamentals)

        imgui.Spacing()
        imgui.TextColored(0.5, 0.5, 0.5, 1.0, '--- PROGRESSION & RAIDS ---')
        if imgui.CollapsingHeader('11.0 Progression Tiers', ImGuiTreeNodeFlags.DefaultOpen) then
            if labelMatchesSearch('11.0 Progress Tracker') and imgui.Selectable('  11.0 Progress Tracker', selectedCategory == '11.0') then
                selectedCategory = '11.0'
            end
            for _, tier in ipairs(progression.progression_tiers) do
                local displayLabel = '  ' .. tier.label
                if labelMatchesSearch(displayLabel) and imgui.Selectable(displayLabel, selectedCategory == tier.id) then
                    selectedCategory = tier.id
                end
            end
        end
        drawList(progression.optional_raids)

        imgui.Spacing()
        imgui.TextColored(0.5, 0.5, 0.5, 1.0, '--- CUSTOM SYSTEMS ---')
        drawList(progression.custom_systems)

        imgui.Spacing()
        imgui.Separator()
        if labelMatchesSearch('THEME SELECTOR') and imgui.Selectable('THEME SELECTOR', selectedCategory == 'THEMES') then
            selectedCategory = 'THEMES'
        end
    end)
    if not okSidebar then
        imgui.TextColored(1.0, 0.35, 0.35, 1.0, 'Sidebar render error:')
        imgui.TextWrapped(tostring(errSidebar))
    end

    imgui.EndChild()

    imgui.SameLine()

    imgui.BeginChild('MainViewport', 0, 0, false)
    local okMain, errMain = pcall(function()
        if content[selectedCategory] then
            local ok, err = pcall(content[selectedCategory])
            if not ok then
                imgui.TextColored(1.0, 0.35, 0.35, 1.0, 'Render error in content page:')
                imgui.TextWrapped(tostring(err))
            end
        else
            imgui.Text('Select a category to view content.')
        end
    end)
    if not okMain then
        imgui.TextColored(1.0, 0.35, 0.35, 1.0, 'Main viewport render error:')
        imgui.TextWrapped(tostring(errMain))
    end
    imgui.EndChild()
end

local function renderUltimateEqHelpMenu()
    if not openGUI then
        return
    end

    imgui.SetNextWindowSize(defaultWindowW, defaultWindowH, ImGuiCond.FirstUseEver)
    imgui.SetNextWindowSizeConstraints(minWindowW, minWindowH, maxWindowW, maxWindowH)

    themesModule.applyTheme(currentTheme)
    imgui.PushStyleVar(ImGuiStyleVar.FrameRounding, 8)
    imgui.PushStyleVar(ImGuiStyleVar.WindowRounding, 10)
    imgui.PushStyleVar(ImGuiStyleVar.ItemSpacing, 12, 10)
    local draw = false
    openGUI, draw = imgui.Begin('Ultimate EQ Help Menu', openGUI)

    if draw then
        local progress = content.getProgressStatus and content.getProgressStatus() or nil

        if progress then
            imgui.BeginChild('ProgressSummaryPanel', 0, 165, true)
            local totalTiers = progress.totalTiers or 0
            local completedTiers = progress.completedTiers or 0
            local overallPct = progress.overallPct or 0
            local summary = ('Progress: %d/%d tiers complete'):format(completedTiers, totalTiers)

            imgui.TextColored(0.95, 0.82, 0.32, 1.0, summary)
            imgui.SameLine()
            imgui.TextColored(0.72, 0.96, 0.78, 1.0, ('(%d%%)'):format(overallPct))

            local fraction = 0.0
            if totalTiers > 0 then
                fraction = completedTiers / totalTiers
            end
            if imgui.ProgressBar then
                imgui.ProgressBar(fraction, -1, 18, ('%d%% overall completion'):format(overallPct))
            else
                imgui.TextColored(0.72, 0.96, 0.78, 1.0, ('Overall Completion: %d%%'):format(overallPct))
            end

            imgui.Spacing()
            local autoLabel = (autoTrackEnabled and '[x] ' or '[ ] ') .. 'Auto-track from chat/log (Dev)'
            if imgui.Selectable(autoLabel, false) then
                autoTrackEnabled = not autoTrackEnabled
                saveUiSettings()
                autoTrackLastMsg = autoTrackEnabled and 'Auto-track enabled.' or 'Auto-track disabled.'
            end
            if autoTrackLastMsg ~= '' then
                imgui.TextColored(0.60, 0.88, 0.98, 1.0, autoTrackLastMsg)
            end
            imgui.Spacing()
            if progress.activeTierId and progress.nextStep and progress.nextStep ~= '' then
                local tierName = progress.activeTierId
                for _, tier in ipairs(progression.progression_tiers or {}) do
                    if tier.id == progress.activeTierId then
                        tierName = tier.label
                        break
                    end
                end
                imgui.TextColored(0.86, 0.62, 0.96, 1.0, 'Next Quest Step')
                imgui.Separator()
                imgui.TextWrapped('[' .. tierName .. '] ' .. progress.nextStep)
            else
                imgui.TextColored(0.72, 0.96, 0.78, 1.0, 'Next Quest Step')
                imgui.Separator()
                imgui.TextWrapped('All tracked tiers are complete.')
            end
            imgui.EndChild()
            imgui.Separator()
        end

        drawHelpSystemsTab()
    end

    imgui.End()
    imgui.PopStyleVar(3)
    imgui.PopStyleColor(12)
end

local function tryAutoTrack(action, targetText)
    if not autoTrackEnabled then
        return
    end
    if not content.autoTrackByAction then
        return
    end
    local ok, matched, tierId, stepText = pcall(content.autoTrackByAction, action, targetText)
    if ok and matched then
        autoTrackLastMsg = ('Auto-checked [%s]: %s'):format(tierId, stepText or '')
    end
end

local function detectTierIdFromText(text)
    local t = (text or ''):lower()
    local lookup = {
        ['vanilla progression'] = '11.1',
        ['kunark progression'] = '11.1',
        ['velious progression'] = '11.1',
        ['luclin progression'] = '11.1',
        ['pop progression'] = '11.1',
        ['crushbone'] = '11.2',
        ['sebilis'] = '11.3',
        ['temple of veeshan'] = '11.4',
        ['kael drakkel'] = '11.5',
        ['sleeper'] = '11.6',
        ['blackburrow'] = '11.7',
        ['mistmoore'] = '11.7',
        ['solusek a'] = '11.7',
        ['the hole'] = '11.8',
        ['frozen shadow'] = '11.9',
        ['veeshan peak'] = '11.10',
        ['ocean of tears'] = '11.11',
        ['unrest'] = '11.11',
        ['plane of fear'] = '11.12',
        ['velketor'] = '11.13',
        ['goblin vault'] = '11.14',
        ['elddar forest'] = '11.15',
        ['old kurn'] = '11.15',
        ['crystallos'] = '11.15',
        ['god tier'] = '11.15',
    }
    for key, tierId in pairs(lookup) do
        if t:find(key, 1, true) then
            return tierId
        end
    end
    return nil
end

local function tryAutoCompleteTierFromText(text)
    if not autoTrackEnabled then
        return
    end
    if not content.markTierComplete then
        return
    end
    local tierId = detectTierIdFromText(text)
    if not tierId then
        return
    end
    local ok, changed = pcall(content.markTierComplete, tierId)
    if ok and changed then
        autoTrackLastMsg = ('Auto-completed tier [%s] from completion message.'):format(tierId)
    end
end

mq.event('pro_autotrack_kill', '#*#You have slain #1#.#*#', function(_, mobName)
    tryAutoTrack('kill', mobName)
end)

mq.event('pro_autotrack_loot_a', '#*#You have looted a #1#.#*#', function(_, itemName)
    tryAutoTrack('loot', itemName)
end)

mq.event('pro_autotrack_loot_an', '#*#You have looted an #1#.#*#', function(_, itemName)
    tryAutoTrack('loot', itemName)
end)

mq.event('pro_autotrack_loot', '#*#You have looted #1#.#*#', function(_, itemName)
    tryAutoTrack('loot', itemName)
end)

mq.event('pro_autotrack_loot_from', '#*#You have looted #1# from #2#.#*#', function(_, itemName)
    tryAutoTrack('loot', itemName)
end)

mq.event('pro_autotrack_receive', '#*#You receive #1#.#*#', function(_, itemName)
    tryAutoTrack('loot', itemName)
end)

mq.event('pro_autotrack_complete_congrats', '#*#Congrats to #1# for completing #2# and receiving #3#.#*#', function(_, _, completedText)
    tryAutoCompleteTierFromText(completedText)
end)

mq.event('pro_autotrack_complete_generic', '#*#for completing #1# and receiving #2#.#*#', function(_, completedText)
    tryAutoCompleteTierFromText(completedText)
end)

mq.event('pro_autotrack_complete_generic_typo', '#*#for completing #1# and recieving #2#.#*#', function(_, completedText)
    tryAutoCompleteTierFromText(completedText)
end)

mq.event('pro_autotrack_complete_for_completing', '#*#for completing #1#.#*#', function(_, completedText)
    tryAutoCompleteTierFromText(completedText)
end)

mq.event('pro_autotrack_complete_for_completing_loose', '#*#for completing #1##*#', function(_, completedText)
    tryAutoCompleteTierFromText(completedText)
end)

mq.imgui.init('UltimateEqHelpMenu', renderUltimateEqHelpMenu)
while openGUI do
    mq.doevents()
    mq.delay(100)
end
