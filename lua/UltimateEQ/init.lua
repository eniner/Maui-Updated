--Version 1.2.0
local mq = require 'mq'
require 'ImGui'
local themeBridge = require 'lib.maui_theme_bridge'
local Open,ShowUI = true,true

-- icons for the checkboxes
local done = mq.FindTextureAnimation('A_TransparentCheckBoxPressed')
local notDone = mq.FindTextureAnimation('A_TransparentCheckBoxNormal')

-- Some WindowFlags
local WindowFlags = bit32.bor(ImGuiWindowFlags.NoTitleBar, ImGuiWindowFlags.NoResize)

-- forward declarations used by quest mini helpers
local oldZone, myZone, showOnlyMissing, minimize, showGrind, onlySpawned, spawnUp, totalDone
local showQuestMini, questOnlyMissing, questTierIndex
local questAutoTrack, questAutoLastMsg
local questTrackerFile, questTierOrder, questData, questTracker
local questSearchText, questPage, questStepsPerPage
local toggleCommand, activeToggleCommand

-- Alt Currency state
local altCurrencyFile
local altCurrencyData = {}
local altCurrencySearch = ''
local altCurrencyLiveRead = true
local altCurrencyLastRefresh = 0

local altCurrencyList = {
    { name = 'Tier 1 Credits',  variants = { 'Tier 1 Credits',  'Tier 1 Credit'  } },
    { name = 'Tier 2 Credits',  variants = { 'Tier 2 Credits',  'Tier 2 Credit'  } },
    { name = 'Tier 3 Credits',  variants = { 'Tier 3 Credits',  'Tier 3 Credit'  } },
    { name = 'Tier 4 Credits',  variants = { 'Tier 4 Credits',  'Tier 4 Credit'  } },
    { name = 'Tier 5 Credits',  variants = { 'Tier 5 Credits',  'Tier 5 Credit'  } },
    { name = 'Tier 6 Credits',  variants = { 'Tier 6 Credits',  'Tier 6 Credit'  } },
    { name = 'Tier 7 Credits',  variants = { 'Tier 7 Credits',  'Tier 7 Credit'  } },
    { name = 'Tier 8 Credits',  variants = { 'Tier 8 Credits',  'Tier 8 Credit'  } },
    { name = 'Tier 9 Credits',  variants = { 'Tier 9 Credits',  'Tier 9 Credit'  } },
    { name = 'Tier 10 Credits', variants = { 'Tier 10 Credits', 'Tier 10 Credit' } },
}

-- print format function
local function printf(...)
    print(string.format(...))
end

local function push_spawnmaster_theme()
    local pv, pc = 0, 0
    local function sv(var, ...)
        ImGui.PushStyleVar(var, ...)
        pv = pv + 1
    end
    local function sc(col, ...)
        ImGui.PushStyleColor(col, ...)
        pc = pc + 1
    end

    sv(ImGuiStyleVar.WindowRounding, 4)
    sv(ImGuiStyleVar.FrameRounding, 5)
    sv(ImGuiStyleVar.FrameBorderSize, 1)
    sv(ImGuiStyleVar.WindowPadding, 8, 6)
    sv(ImGuiStyleVar.ItemSpacing, 6, 4)

    sc(ImGuiCol.WindowBg, 0.04, 0.02, 0.08, 0.95)
    sc(ImGuiCol.TitleBg, 0.14, 0.02, 0.22, 1.00)
    sc(ImGuiCol.TitleBgActive, 0.24, 0.04, 0.32, 1.00)
    sc(ImGuiCol.Button, 0.18, 0.06, 0.26, 1.00)
    sc(ImGuiCol.ButtonHovered, 0.36, 0.09, 0.44, 1.00)
    sc(ImGuiCol.ButtonActive, 0.50, 0.12, 0.58, 1.00)
    sc(ImGuiCol.FrameBg, 0.10, 0.04, 0.16, 1.00)
    sc(ImGuiCol.FrameBgHovered, 0.18, 0.07, 0.26, 1.00)
    sc(ImGuiCol.FrameBgActive, 0.26, 0.10, 0.36, 1.00)
    sc(ImGuiCol.Header, 0.22, 0.07, 0.30, 1.00)
    sc(ImGuiCol.HeaderHovered, 0.34, 0.10, 0.42, 1.00)
    sc(ImGuiCol.HeaderActive, 0.44, 0.13, 0.52, 1.00)
    sc(ImGuiCol.Border, 0.90, 0.16, 0.68, 0.70)
    sc(ImGuiCol.Separator, 0.22, 0.90, 0.84, 0.60)
    sc(ImGuiCol.Text, 0.92, 0.96, 1.00, 1.00)

    return pv, pc
end

local function pop_spawnmaster_theme(pv, pc)
    if pc and pc > 0 then ImGui.PopStyleColor(pc) end
    if pv and pv > 0 then ImGui.PopStyleVar(pv) end
end

local function saveQuestTracker()
    local f = io.open(questTrackerFile, 'w')
    if not f then return end
    f:write('return {\n')
    f:write(('  tierIndex = %d,\n'):format(questTierIndex))
    f:write(('  toggleCommand = %q,\n'):format(toggleCommand or '/hhtoggle'))
    f:write(('  showQuestMini = %s,\n'):format(showQuestMini and 'true' or 'false'))
    f:write(('  questOnlyMissing = %s,\n'):format(questOnlyMissing and 'true' or 'false'))
    f:write(('  questAutoTrack = %s,\n'):format(questAutoTrack and 'true' or 'false'))
    f:write('  tiers = {\n')
    for _, tierId in ipairs(questTierOrder) do
        local entries = questTracker.tiers[tierId] or {}
        f:write(("    ['%s'] = {\n"):format(tierId))
        for _, key in ipairs(entries) do
            f:write(("      '%s',\n"):format(key:gsub("'", "\\'")))
        end
        f:write('    },\n')
    end
    f:write('  },\n')
    f:write('}\n')
    f:close()
end

local function loadQuestTracker()
    local ok, loaded = pcall(dofile, questTrackerFile)
    if not ok or type(loaded) ~= 'table' then return end
    if type(loaded.tierIndex) == 'number' and loaded.tierIndex >= 1 and loaded.tierIndex <= #questTierOrder then
        questTierIndex = loaded.tierIndex
    end
    if type(loaded.toggleCommand) == 'string' and loaded.toggleCommand ~= '' then
        toggleCommand = loaded.toggleCommand
    end
    if type(loaded.showQuestMini) == 'boolean' then
        showQuestMini = loaded.showQuestMini
    end
    if type(loaded.questOnlyMissing) == 'boolean' then
        questOnlyMissing = loaded.questOnlyMissing
    end
    if type(loaded.questAutoTrack) == 'boolean' then
        questAutoTrack = loaded.questAutoTrack
    end
    if type(loaded.tiers) == 'table' then
        for _, tierId in ipairs(questTierOrder) do
            questTracker.tiers[tierId] = {}
            local src = loaded.tiers[tierId]
            if type(src) == 'table' then
                for _, key in ipairs(src) do
                    if type(key) == 'string' then
                        table.insert(questTracker.tiers[tierId], key)
                    end
                end
            end
        end
    end
    -- Keep manual override practical by default: show all steps unless user re-enables missing-only.
    questOnlyMissing = false
end

local function saveAltCurrency()
    local f = io.open(altCurrencyFile, 'w')
    if not f then return end
    f:write('return {\n')
    for _, cur in ipairs(altCurrencyList) do
        local val = altCurrencyData[cur.name] or 0
        f:write(string.format("  [%q] = %d,\n", cur.name, val))
    end
    f:write('}\n')
    f:close()
end

local function loadAltCurrency()
    local ok, loaded = pcall(dofile, altCurrencyFile)
    if not ok or type(loaded) ~= 'table' then return end
    for _, cur in ipairs(altCurrencyList) do
        if type(loaded[cur.name]) == 'number' then
            altCurrencyData[cur.name] = loaded[cur.name]
        end
    end
end

local function readOneCurrency(cur)
    for _, v in ipairs(cur.variants) do
        local ok, val = pcall(function() return mq.TLO.Me.AltCurrency(v)() end)
        if ok and type(val) == 'number' and val >= 0 then return val end
    end
    for _, v in ipairs(cur.variants) do
        local ok, result = pcall(function()
            return mq.parse('${Me.AltCurrency[' .. v .. ']}')
        end)
        if ok and result and result ~= 'NULL' and result ~= '' then
            local n = tonumber(result)
            if n and n >= 0 then return n end
        end
    end
    return nil
end

local function refreshAltCurrencyFromGame()
    for _, cur in ipairs(altCurrencyList) do
        local val = readOneCurrency(cur)
        if val ~= nil then
            altCurrencyData[cur.name] = val
        end
    end
    saveAltCurrency()
end

local function renderAltCurrency()
    -- Throttled live read once per second
    if altCurrencyLiveRead then
        local now = os.time()
        if now ~= altCurrencyLastRefresh then
            altCurrencyLastRefresh = now
            refreshAltCurrencyFromGame()
        end
    end

    ImGui.Separator()
    ImGui.TextColored(0.973, 0.741, 0.129, 1, 'Alt Currency Tracker')
    ImGui.Spacing()

    -- Search bar
    local newSearch, changed = ImGui.InputText('Search##altcur_search', altCurrencySearch, 128)
    if changed then altCurrencySearch = newSearch end

    ImGui.Spacing()

    -- Controls row
    if ImGui.SmallButton('Refresh##altcur_refresh') then
        refreshAltCurrencyFromGame()
    end
    ImGui.SameLine()
    local liveLabel = altCurrencyLiveRead and 'Live: ON##altcur_live' or 'Live: OFF##altcur_live'
    if ImGui.SmallButton(liveLabel) then
        altCurrencyLiveRead = not altCurrencyLiveRead
    end

    ImGui.Separator()

    -- Header row
    local totalW = ImGui.GetContentRegionAvail()
    ImGui.PushStyleColor(ImGuiCol.Text, 0.22, 0.90, 0.84, 1.00)
    ImGui.Text('Currency')
    ImGui.SameLine(totalW - 90)
    ImGui.Text('Balance')
    ImGui.PopStyleColor()
    ImGui.Separator()

    -- Scrollable list
    local _, availY = ImGui.GetContentRegionAvail()
    ImGui.BeginChild('##altcur_child', totalW, availY, true)

    local childW = ImGui.GetContentRegionAvail()
    local searchNorm = (altCurrencySearch or ''):lower()
    local rowIndex = 0

    for _, cur in ipairs(altCurrencyList) do
        if searchNorm == '' or cur.name:lower():find(searchNorm, 1, true) then
            rowIndex = rowIndex + 1
            local val = altCurrencyData[cur.name] or 0
            local valStr = tostring(val)

            -- Alternating name color
            if rowIndex % 2 == 0 then
                ImGui.TextColored(0.92, 0.96, 1.00, 1.00, cur.name)
            else
                ImGui.TextColored(0.690, 0.553, 0.259, 1.00, cur.name)
            end

            -- Right-align the balance value
            local valW = ImGui.CalcTextSize(valStr)
            ImGui.SameLine(childW - valW - 6)
            ImGui.TextColored(0.22, 0.90, 0.84, 1.00, valStr)
        end
    end

    ImGui.EndChild()
end

local function questStepKey(tierId, idx)
    return string.format('%s|%d', tierId, idx)
end

local function isQuestStepDone(tierId, key)
    local entries = questTracker.tiers[tierId] or {}
    for _, v in ipairs(entries) do
        if v == key then return true end
    end
    return false
end

local function setQuestStepDone(tierId, key, doneState)
    questTracker.tiers[tierId] = questTracker.tiers[tierId] or {}
    local entries = questTracker.tiers[tierId]
    local found = nil
    for i, v in ipairs(entries) do
        if v == key then
            found = i
            break
        end
    end
    if doneState and not found then
        table.insert(entries, key)
    elseif (not doneState) and found then
        table.remove(entries, found)
    end
    saveQuestTracker()
end

local function getQuestCounts(tierId)
    local data = questData[tierId] or { steps = {} }
    local doneCount = 0
    local totalCount = #data.steps
    for idx = 1, totalCount do
        if isQuestStepDone(tierId, questStepKey(tierId, idx)) then
            doneCount = doneCount + 1
        end
    end
    return doneCount, totalCount
end

local function getOverallQuestCounts()
    local doneCount, totalCount = 0, 0
    for _, tierId in ipairs(questTierOrder) do
        local d, t = getQuestCounts(tierId)
        doneCount = doneCount + d
        totalCount = totalCount + t
    end
    return doneCount, totalCount
end

local function normalizeQuestText(text)
    local t = (text or ''):lower()
    t = t:gsub('[%p]', ' ')
    t = t:gsub('%s+', ' ')
    return t:gsub('^%s+', ''):gsub('%s+$', '')
end

local function actionMatchesQuestStep(action, stepNorm, tokenNorm)
    if tokenNorm == '' then return false end
    if not stepNorm:find(tokenNorm, 1, true) then return false end
    if action == 'kill' then
        return stepNorm:match('^defeat ') or stepNorm:match('^kill ')
    end
    if action == 'loot' then
        return stepNorm:match('^collect ') or stepNorm:match('^loot ') or stepNorm:match('^obtain ')
    end
    if action == 'turnin' then
        return stepNorm:match('^turn in ') or stepNorm:match('^deliver ')
    end
    if action == 'hail' then
        return stepNorm:match('^hail ')
    end
    return false
end

local function markQuestTierComplete(tierId)
    local data = questData[tierId]
    if not data then return false end
    local changed = false
    for idx = 1, #data.steps do
        local key = questStepKey(tierId, idx)
        if not isQuestStepDone(tierId, key) then
            setQuestStepDone(tierId, key, true)
            changed = true
        end
    end
    return changed
end

local function autoTrackQuestStep(action, targetText)
    if not questAutoTrack then return false end
    local tokenNorm = normalizeQuestText(targetText)
    if tokenNorm == '' then return false end

    local order = {}
    local curTierId = questTierOrder[questTierIndex]
    if curTierId then table.insert(order, curTierId) end
    for _, tierId in ipairs(questTierOrder) do
        if tierId ~= curTierId then table.insert(order, tierId) end
    end

    for _, tierId in ipairs(order) do
        local data = questData[tierId]
        if data then
            for idx, step in ipairs(data.steps or {}) do
                local key = questStepKey(tierId, idx)
                if not isQuestStepDone(tierId, key) then
                    local stepNorm = normalizeQuestText(step)
                    if actionMatchesQuestStep(action, stepNorm, tokenNorm) then
                        setQuestStepDone(tierId, key, true)
                        questAutoLastMsg = string.format('Auto-checked [%s] %s', tierId, step)
                        return true
                    end
                end
            end
        end
    end
    return false
end

local function detectQuestTierFromCompletion(text)
    local t = (text or ''):lower()
    local map = {
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
    for key, tierId in pairs(map) do
        if t:find(key, 1, true) then
            return tierId
        end
    end
    return nil
end

local function autoTrackQuestCompletion(text)
    if not questAutoTrack then return false end
    local tierId = detectQuestTierFromCompletion(text)
    if not tierId then return false end
    if markQuestTierComplete(tierId) then
        questAutoLastMsg = string.format('Auto-completed tier [%s] from completion text.', tierId)
        return true
    end
    return false
end

local function renderQuestMini()
    if not showQuestMini then return end
    local tierId = questTierOrder[questTierIndex]
    local data = questData[tierId]
    if not data then return end

    ImGui.Separator()
    ImGui.SetCursorPosX((ImGui.GetWindowWidth() - ImGui.CalcTextSize('Quest Mini')) * 0.5)
    ImGui.TextColored(0.973, 0.741, 0.129, 1, 'Quest Mini')
    local groupTabs = {
        { label = 'Pre', ids = { '11.1' } },
        { label = 'Ultimate', ids = { '11.2', '11.3', '11.4', '11.5', '11.6' } },
        { label = 'Avatar', ids = { '11.7', '11.8', '11.9', '11.10' } },
        { label = 'Demigod', ids = { '11.11', '11.12', '11.13', '11.14' } },
        { label = 'God', ids = { '11.15' } },
    }

    local function setTierById(gid)
        for i, id in ipairs(questTierOrder) do
            if id == gid then
                questTierIndex = i
                tierId = gid
                data = questData[tierId]
                questPage = 1
                saveQuestTracker()
                return
            end
        end
    end

    local function currentTierInGroup(group)
        for _, gid in ipairs(group.ids) do
            if gid == tierId then return true end
        end
        return false
    end

    if ImGui.BeginTabBar('##quest_group_tabs') then
        for _, group in ipairs(groupTabs) do
            if ImGui.BeginTabItem(group.label) then
                if not currentTierInGroup(group) then
                    setTierById(group.ids[1])
                end
                if ImGui.BeginTabBar('##quest_tier_tabs_' .. group.label) then
                    for _, gid in ipairs(group.ids) do
                        local label = questData[gid] and questData[gid].label or gid
                        local openTier = (gid == tierId)
                        if ImGui.BeginTabItem(label .. '##tier_tab_' .. gid) then
                            if not openTier then setTierById(gid) end
                            ImGui.EndTabItem()
                        end
                    end
                    ImGui.EndTabBar()
                end
                ImGui.EndTabItem()
            end
        end

        -- Alt Currency tab
        if ImGui.BeginTabItem('Alt Cur##altcur_tab') then
            ImGui.EndTabItem()
            ImGui.EndTabBar()
            renderAltCurrency()
            return
        end

        ImGui.EndTabBar()
    end

    ImGui.TextColored(0.690, 0.553, 0.259, 1, data.label)
    local newSearch, changed = ImGui.InputText('Search##quest_search', questSearchText, 128)
    if changed then
        questSearchText = newSearch
        questPage = 1
    end

    local doneCount, totalCount = getQuestCounts(tierId)
    local pct = 0
    if totalCount > 0 then pct = doneCount / totalCount end
    local availW = ImGui.GetContentRegionAvail()
    local barW = availW - 2
    if barW < 120 then barW = 120 end
    ImGui.TextColored(0.92, 0.96, 1.00, 1.00, string.format('Tier Progress: %d/%d Steps', doneCount, totalCount))
    ImGui.PushStyleColor(ImGuiCol.PlotHistogram, 0.690, 0.553, 0.259, 0.5)
    ImGui.PushStyleColor(ImGuiCol.FrameBg, 0.33, 0.33, 0.33, 0.5)
    ImGui.ProgressBar(pct, barW, 18, '')
    ImGui.PopStyleColor(2)

    local overallDone, overallTotal = getOverallQuestCounts()
    local overallPct = 0
    if overallTotal > 0 then overallPct = overallDone / overallTotal end
    ImGui.TextColored(0.22, 0.90, 0.84, 1.00, string.format('Overall Chain: %d/%d', overallDone, overallTotal))
    ImGui.PushStyleColor(ImGuiCol.PlotHistogram, 0.22, 0.90, 0.84, 0.70)
    ImGui.PushStyleColor(ImGuiCol.FrameBg, 0.20, 0.08, 0.28, 0.65)
    ImGui.ProgressBar(overallPct, barW, 14, '')
    ImGui.PopStyleColor(2)

    local visible = {}
    local searchNorm = normalizeQuestText(questSearchText or '')
    for idx, step in ipairs(data.steps) do
        local key = questStepKey(tierId, idx)
        local checked = isQuestStepDone(tierId, key)
        local includeMissing = (not questOnlyMissing) or (not checked)
        local includeSearch = (searchNorm == '') or (normalizeQuestText(step):find(searchNorm, 1, true) ~= nil)
        if includeMissing and includeSearch then
            table.insert(visible, { idx = idx, key = key, step = step, checked = checked })
        end
    end

    local totalPages = math.max(1, math.ceil(#visible / questStepsPerPage))
    if questPage > totalPages then questPage = totalPages end
    if questPage < 1 then questPage = 1 end

    if ImGui.SmallButton('<<##qfirst') then questPage = 1 end
    ImGui.SameLine()
    if ImGui.SmallButton('<##qprevpage') then questPage = math.max(1, questPage - 1) end
    ImGui.SameLine()
    ImGui.TextColored(0.65, 0.65, 0.65, 1, string.format('Page %d / %d', questPage, totalPages))
    ImGui.SameLine()
    if ImGui.SmallButton('>##qnextpage') then questPage = math.min(totalPages, questPage + 1) end
    ImGui.SameLine()
    if ImGui.SmallButton('>>##qlast') then questPage = totalPages end

    if questAutoLastMsg ~= '' then
        ImGui.TextColored(0.65, 0.65, 0.65, 1, questAutoLastMsg)
    end
    ImGui.TextColored(0.60, 0.90, 0.90, 1, 'Manual override: click any step to check/uncheck.')

    if minimize then return end
    local startIdx = ((questPage - 1) * questStepsPerPage) + 1
    local endIdx = math.min(#visible, startIdx + questStepsPerPage - 1)

    local availX, availY = ImGui.GetContentRegionAvail()
    ImGui.BeginChild('##quest_step_child', availX, availY, true)
    for i = startIdx, endIdx do
        local row = visible[i]
        if row then
            local boxLabel = (row.checked and '[x]' or '[ ]') .. '##questbox' .. row.key
            if ImGui.SmallButton(boxLabel) then
                setQuestStepDone(tierId, row.key, not row.checked)
                row.checked = not row.checked
            end
            ImGui.SameLine()
            local clicked = ImGui.Selectable(row.step .. '##quest' .. row.key, false)
            if clicked then
                setQuestStepDone(tierId, row.key, not row.checked)
                row.checked = not row.checked
            end
        end
    end
    ImGui.EndChild()
end

oldZone = 0
myZone = mq.TLO.Zone.ID
showOnlyMissing = false
minimize = false
showGrind = false
onlySpawned = false
spawnUp = 0
totalDone = ''
showQuestMini = true
questOnlyMissing = false
questTierIndex = 1
questAutoTrack = true
questAutoLastMsg = ''
questSearchText = ''
questPage = 1
questStepsPerPage = 8
toggleCommand = '/hhtoggle'
activeToggleCommand = nil

-- shortening the mq bind for achievements 
local myAch = mq.TLO.Achievement

-- Table that will store the spawnnames of the Hunter achievement
local myHunterSpawn = {}

-- Current Achievemment information
local curAch = {}

questTrackerFile = 'ultimateeq_hud_quest_tracker.lua'
altCurrencyFile  = 'ultimateeq_hud_altcurrency.lua'
do
    local mqRoot = mq.TLO and mq.TLO.MacroQuest and mq.TLO.MacroQuest.Path and mq.TLO.MacroQuest.Path()
    if mqRoot and mqRoot ~= '' then
        questTrackerFile = mqRoot .. '\\lua\\UltimateEQ Hud\\ultimateeq_hud_quest_tracker.lua'
        altCurrencyFile  = mqRoot .. '\\lua\\UltimateEQ Hud\\ultimateeq_hud_altcurrency.lua'
    end
end

questTierOrder = {
    '11.1', '11.2', '11.3', '11.4', '11.5',
    '11.6', '11.7', '11.8', '11.9', '11.10',
    '11.11', '11.12', '11.13', '11.14', '11.15',
}

questData = {
    ['11.1'] = {
        label = '11.1 Pre-Ultimate',
        steps = {
            'Collect Nagafen\'s Head.',
            'Collect Innoruuk\'s Brain.',
            'Collect Cazic Thule\'s Eye.',
            'Turn in those items plus Ultimate Charm to Mel.',
            'Collect Trakanon\'s Tail.',
            'Collect Phara Dar\'s Tooth.',
            'Collect Venril Sathir\'s Belt.',
            'Turn in those items plus Ultimate Charm - Tier 1 to Mel.',
            'Collect The Statue\'s Helmet.',
            'Collect Tunare\'s Torn Dress.',
            'Collect Vulak\'s Scale.',
            'Turn in those items plus Ultimate Charm - Tier 2 to Mel.',
            'Collect Emperor Ssra\'s Idol.',
            'Collect Aten\'s Ring.',
            'Collect Grieg\'s Torn Parchment.',
            'Turn in those items plus Ultimate Charm - Tier 3 to Mel.',
            'Collect Rallos Zek\'s Axe.',
            'Collect Solusek\'s Burning Staff.',
            'Collect Fenin Ro\'s Burning Boots.',
            'Turn in those items plus Ultimate Charm - Tier 4 to Mel.',
        },
    },
    ['11.2'] = {
        label = '11.2 Ultimate Rank 1',
        steps = {
            'Defeat Dvinn the Tormentor.',
            'Defeat Ser Darish the Black.',
            'Defeat Crush the Transformed and loot Heart of Crush the Transformed.',
            'Deliver Heart of Crush the Transformed to Forge.',
            'Hail Quake for Ultimate Rank 1 access.',
        },
    },
    ['11.3'] = {
        label = '11.3 Ultimate Rank 2',
        steps = {
            'Collect Ghoul Lord\'s Head.',
            'Collect Froglok King\'s Head.',
            'Collect Shin Lord\'s Head.',
            'Collect Ancient Croc\'s Head.',
            'Turn in all four heads to Mel at once.',
        },
    },
    ['11.4'] = {
        label = '11.4 Ultimate Rank 3',
        steps = {
            'Collect Ultimate weapon materials.',
            'Craft your Ultimate Legendary weapon with Forge.',
            'Hail Quake to access Temple of Veeshan.',
        },
    },
    ['11.5'] = {
        label = '11.5 Ultimate Rank 4',
        steps = {
            'Collect Ultimate Vulak\'s Scale.',
            'Turn in Ultimate Vulak\'s Scale to Mel.',
            'Hail Quake for Kael Drakkel access.',
        },
    },
    ['11.6'] = {
        label = '11.6 Ultimate Rank 5',
        steps = {
            'Collect Ultimate Kael Completion Pass.',
            'Turn in Ultimate Kael Completion Pass to Mel.',
            'Hail Quake for Sleeper\'s Tomb access.',
        },
    },
    ['11.7'] = {
        label = '11.7 Avatar Rank 1',
        steps = {
            'Collect Ultimate Kerafyrm\'s Scale.',
            'Turn in Ultimate Kerafyrm\'s Scale to Mel.',
            'Collect Ultimate Charm Upgrade Token (Rank 6).',
            'Turn in Rank 6 token to Arch Magus Phil.',
            'Hail Quake for Blackburrow, Mistmoore, and Solusek A.',
        },
    },
    ['11.8'] = {
        label = '11.8 Avatar Rank 2',
        steps = {
            'Collect Mayong\'s Head.',
            'Collect Fippy\'s Head.',
            'Collect Goblin King\'s Head.',
            'Turn in all three heads to Mel.',
        },
    },
    ['11.9'] = {
        label = '11.9 Avatar Rank 3',
        steps = {
            'Collect An Earthen Soulstone.',
            'Turn in An Earthen Soulstone to Mel.',
            'Complete Rank 7 charm path with Measel.',
            'Hail Quake for Tower of Frozen Shadow access.',
        },
    },
    ['11.10'] = {
        label = '11.10 Avatar Rank 4',
        steps = {
            'Collect Frozen Avatar Energy.',
            'Turn in Frozen Avatar Energy to Mel.',
            'Hail Quake for Veeshan\'s Peak access.',
        },
    },
    ['11.11'] = {
        label = '11.11 Demigod Rank 1',
        steps = {
            'Collect Heart of the Peak.',
            'Turn in Heart of the Peak to Mel.',
            'Complete Rank 8 charm path with Measel.',
            'Hail Seism for Ocean of Tears and Unrest access.',
        },
    },
    ['11.12'] = {
        label = '11.12 Demigod Rank 2',
        steps = {
            'Collect Coalesced Demigod Energy.',
            'Turn in Coalesced Demigod Energy to Mel.',
            'Collect Ultimate Unrest Commendation.',
            'Turn in Ultimate Unrest Commendation to Mel.',
            'Complete Ultimate 2.0 with Cloud.',
            'Complete Rank 9 charm path with Arch Magus Phil.',
            'Create Plane of Fear instance with Seism.',
        },
    },
    ['11.13'] = {
        label = '11.13 Demigod Rank 3',
        steps = {
            'Collect A Freshly Severed Head.',
            'Turn in A Freshly Severed Head to Mel.',
            'Hail Seism for Velketor\'s Labyrinth access.',
        },
    },
    ['11.14'] = {
        label = '11.14 Demigod Rank 4',
        steps = {
            'Collect Velketorian Essence.',
            'Turn in Velketorian Essence to Mel.',
            'Complete Rank 10 charm path with Farnsworth.',
            'Create Treasure Goblin Vault instance with Seism.',
        },
    },
    ['11.15'] = {
        label = '11.15 God Progression',
        steps = {
            'Collect Realm of the Gods Commendation.',
            'Turn in Realm of the Gods Commendation to Mel.',
            'Complete Illuminous confirmations.',
            'Enter Elddar Forest or Old Kurn\'s Tower for level 71.',
            'Spend 250 Tier 9 credits for level 72.',
            'Turn in 4x item 149854 for level 73.',
            'Turn in items 149855, 149856, 149857, 149858 for level 74.',
            'Turn in item 149859 for level 75.',
            'Hail Seism and access Crystallos.',
            'Turn in Abomination Head to Mel for God Tier 2.',
        },
    },
}

questTracker = { tiers = {} }

-- nameMap that maps wrong achievement objective names to the ingame name.
local nameMap = {
    ["Pli Xin Liako"]           = "Pli Xin Laiko",
    ["Xetheg, Luclin's Warder"] = "Xetheg, Luclin`s Warder",
    ["Itzal, Luclin's Hunter"]  = "Itzal, Luclin`s Hunter",
    ["Ol' Grinnin' Finley"]     = "Ol` Grinnin` Finley"
}

-- Zonemap that maps zoneID's to Achievement Indexes, for zones that are speshul!
local zoneMap = {
    [58]  = 105880,  --Hunter of Crushbone                  Clan Crusbone=crushbone

    [66]  = 106680,  --Hunter of The Ruins of Old Guk       The Reinforced Ruins of Old Guk=gukbottom
    [73]  = 107380,  --Hunter of the Permafrost Caverns     Permafrost Keep=permafrost
    [81]  = 258180,  --Hunter of The Temple of Droga        The Temple of Droga=droga
    [87]  = 208780,  --Hunter of The Burning Wood           The Burning Woods=burningwood
    [89]  = 208980,  --Hunter of The Ruins of Old Sebilis   The Reinforced Ruins of Old Sebilis=sebilis
    [108] = 250880,  --Hunter of Veeshan's Peak             Veeshan's Peak=veeshan

    [207] = 520780,  --Hunter of Torment, the Plane of Pain Plane of Torment=potorment
    [455] = 1645560, --Hunter of Kurn's Tower               Kurn's Tower=oldkurn
    [318] = 908300,  --Hunter of Dranik's Hollows           Dranik's Hollows (A)=dranikhollowsa
    [319] = 908300,  --Hunter of Dranik's Hollows           Dranik's Hollows (B)=dranikhollowsb
    [320] = 908300,  --Hunter of Dranik's Hollows           Dranik's Hollows (C)=dranikhollowsc
    [328] = 908600,  --Hunter of Catacombs of Dranik        Catacombs of Dranik (A)=dranikcatacombsa
    [329] = 908600,  --Hunter of Catacombs of Dranik        Catacombs of Dranik (B)=dranikcatacombsb
    [330] = 908600,  --Hunter of Catacombs of Dranik        Catacombs of Dranik (C)=dranikcatacombsc
    [331] = 908700,  --Hunter of Sewers of Dranik           Sewers of Dranik (A)=draniksewersa
    [332] = 908700,  --Hunter of Sewers of Dranik           Sewers of Dranik (B)=draniksewersb
    [333] = 908700,  --Hunter of Sewers of Dranik           Sewers of Dranik (C)=draniksewersc
    
    [700] = 1870060, --Hunter of The Feerrott               The Feerrott=Feerrott2
    [772] = 2177270, --Hunter of West Karana (Ethernere)    Ethernere Tainted West Karana=ethernere
    [76]  = 2320180, --Hunter of the Plane of Hate: Broken Mirror  Plane of hate Revisited=hateplane
    [788] = 2478880, --Hunter of The Temple of Droga        Temple of Droga=drogab
    [791] = 2479180, --Hunter of Frontier Mountains         Frontier Mountains=frontiermtnsb
    [800] = 2480080, --Hunter of Chardok                    Chardok=chardoktwo

    [813] = 2581380, --Hunter of The Howling Stones         Howling Stones=charasistwo
    [814] = 2581480, --Hunter of The Skyfire Mountains      Skyfire Mountains=skyfiretwo
    [815] = 2581580, --Hunter of The Overthere              The Overthere=overtheretwo
    [816] = 2581680, --Hunter of Veeshan's Peak             Veeshan's Peak=veeshantwo

    [824] = 2782480, --Hunter of The Eastern Wastes         The Eastern Wastes=eastwastestwo
    [825] = 2782580, --Hunter of The Tower of Frozen Shadow The Tower of Frozen Shadow=frozenshadowtwo
    [826] = 2782680, --Hunter of The Ry`Gorr Mines          The Ry`Gorr Mines=crystaltwoa
    [827] = 2782780, --Hunter of The Great Divide           The Great Divide=greatdividetwo
    [828] = 2782880, --Hunter of Velketor's Labyrinth       Velketor's Labyrinth=velketortwo
    [829] = 2782980, --Hunter of Kael Drakkel               Kael Drakkel=kaeltwo
    [830] = 2783080, --Hunter of Crystal Caverns            Crystal Caverns=crystaltwob

    [831] = 2807601, --Hunter of The Sleeper's Tomb         The Sleeper's Tomb=sleepertwo
    [832] = 2807401, --Hunter of Dragon Necropolis          Dragon Necropolis=necropolistwo
    [833] = 2807101, --Hunter of Cobalt Scar                Cobalt Scar=cobaltscartwo
    [834] = 2807201, --Hunter of The Western Wastes         The Western Wastes=westwastestwo
    [835] = 2807501, --Hunter of Skyshrine                  Skyshrine=skyshrinetwo
    [836] = 2807301, --Hunter of The Temple of Veeshan      The Temple of Veeshan=templeveeshantwo

    [843] = 2908100, --Hunter of Maiden's Eye               Maiden's Eye=maidentwo
    [844] = 2908200, --Hunter of Umbral Plains              Umbral Plains=umbraltwo
    [846] = 2908400, --Hunter of Vex Thal                   Vex Thal=vexthaltwo
    [847] = 2908500, --Hunter of Shadow Valley              zone name has an extra space
}

local function AchID()
    if zoneMap[mq.TLO.Zone.ID()] or myAch('Hunter of the '..mq.TLO.Zone.Name()).ID() then
        return zoneMap[mq.TLO.Zone.ID()] or myAch('Hunter of the '..mq.TLO.Zone.Name()).ID()
    else
        return myAch('Hunter of '..mq.TLO.Zone.Name()).ID()
    end
end

local function findspawn(spawn)
if nameMap[spawn] then spawn = nameMap[spawn] end
    local mySpawn = mq.TLO.Spawn(string.format('npc "%s"', spawn))
    if mySpawn.CleanName() == spawn then
        return mySpawn.ID()
    end
    return 0
end

local function getPctCompleted()
    local tmp = 0
    for index, hunterSpawn in ipairs(myHunterSpawn) do
        if myAch(curAch.ID).Objective(hunterSpawn).Completed() then
            tmp = tmp + 1
        end
    end
    totalDone = string.format('%d/%d',tmp, curAch.Count)
    if tmp == curAch.Count then totalDone = 'Completed!' end
    return tmp / curAch.Count
end

local function drawCheckBox(spawn)
    if myAch(curAch.ID).Objective(spawn).Completed() then
        ImGui.DrawTextureAnimation(done, 15, 15)
        ImGui.SameLine()
    else
        ImGui.DrawTextureAnimation(notDone, 15, 15)
        ImGui.SameLine()
    end
end

local function textEnabled(spawn)
    ImGui.PushStyleColor(ImGuiCol.Text, 0.690, 0.553, 0.259, 1)
    ImGui.PushStyleColor(ImGuiCol.HeaderHovered, 0.33, 0.33, 0.33, 0.5)
    ImGui.PushStyleColor(ImGuiCol.HeaderActive, 0.0, 0.66, 0.33, 0.5)
    local selSpawn = ImGui.Selectable(spawn, false, ImGuiSelectableFlags.AllowDoubleClick)
    ImGui.PopStyleColor(3)
    if selSpawn and ImGui.IsMouseDoubleClicked(0) then
        mq.cmdf('/nav id %d log=error' , findspawn(spawn))
        printf('\ayMoving to \ag%s',spawn)
    end
end

local function hunterProgress()
    local x, y = ImGui.GetContentRegionAvail()
    ImGui.PushStyleColor(ImGuiCol.PlotHistogram, 0.690, 0.553, 0.259, 0.5)
    ImGui.PushStyleColor(ImGuiCol.FrameBg, 0.33, 0.33, 0.33, 0.5)
    ImGui.SetWindowFontScale(0.85)
    ImGui.Indent(2)
    ImGui.ProgressBar(getPctCompleted(), x-4, 14, totalDone)
    ImGui.PopStyleColor(2)
    ImGui.SetWindowFontScale(1)

end

local function createLines(spawn)
    if findspawn(spawn) ~= 0 then
        drawCheckBox(spawn)
        textEnabled(spawn)
    elseif not onlySpawned then
        drawCheckBox(spawn)
        ImGui.TextDisabled(spawn)
    end
end

local function popupmenu()
    ImGui.SetCursorPosX((ImGui.GetWindowWidth() - ImGui.CalcTextSize('UltimateEQ Hud')) * 0.5)
    ImGui.TextColored(0.973, 0.741, 0.129, 1, 'UltimateEQ Hud')
    ImGui.Separator()
    ImGui.PushStyleColor(ImGuiCol.Text, 0.690, 0.553, 0.259, 1)
    ImGui.PushStyleColor(ImGuiCol.HeaderHovered, 0.33, 0.33, 0.33, 0.5)
    ImGui.PushStyleColor(ImGuiCol.HeaderActive, 0.0, 0.66, 0.33, 0.5)

    minimize = ImGui.MenuItem('Minimize', '', minimize)
    if ImGui.Selectable('Hide') then 
        printf('\a#f8bd21Hiding UltimateEQ Hud(\a#b08d42\'/ueq\' to show\ax)') 
        ShowUI = not ShowUI 
    end
    onlySpawned = ImGui.MenuItem('Toggle Spawned Only', '', onlySpawned)
    showOnlyMissing = ImGui.MenuItem('Toggle Missing Hunts', '', showOnlyMissing)
    showQuestMini = ImGui.MenuItem('Toggle Quest Mini', '', showQuestMini)
    questOnlyMissing = ImGui.MenuItem('Show Missing-Only Steps', '', questOnlyMissing)
    questAutoTrack = ImGui.MenuItem('Toggle Quest Auto-Track', '', questAutoTrack)
    if ImGui.Selectable('Reset Current Quest Tier') then
        local tierId = questTierOrder[questTierIndex]
        questTracker.tiers[tierId] = {}
        saveQuestTracker()
    end
    ImGui.Separator()
    ImGui.PushStyleColor(ImGuiCol.Text, 0.973, 0.741, 0.129, 1)
    if ImGui.Selectable('Stop UltimateEQ Hud') then Open = false end
    saveQuestTracker()
    ImGui.PopStyleColor(4)
    ImGui.EndPopup()
end

local function PCList()
    ImGui.SetCursorPosX((ImGui.GetWindowWidth() - ImGui.CalcTextSize('Players in Zone')) * 0.5)
    ImGui.TextColored(0.973, 0.741, 0.129, 1, 'Players in Zone')
    ImGui.Separator()
    ImGui.PushStyleColor(ImGuiCol.Text, 0.690, 0.553, 0.259, 1)
    --ImGui.PushStyleColor(ImGuiCol.HeaderHovered, 0.33, 0.33, 0.33, 0.5)
    --ImGui.PushStyleColor(ImGuiCol.HeaderActive, 0.0, 0.66, 0.33, 0.5)

    for i = 1, mq.TLO.SpawnCount('pc')() do
        local player = mq.TLO.NearestSpawn(i,'pc')
        ImGui.Text(string.format('%s [%d - %s] - %s', player.Name(), player.Level(), player.Class(), player.Guild() or 'No Guild'))
    end
    ImGui.Separator()
    ImGui.PushStyleColor(ImGuiCol.Text, 0.973, 0.741, 0.129, 1)
    --bottom line
    ImGui.PopStyleColor(2)
    ImGui.EndPopup()
end

local function RenderHunter()
    hunterProgress()
    if not minimize then ImGui.Separator() end
    for index, hunterSpawn in ipairs(myHunterSpawn) do

        if not minimize then
            if showOnlyMissing then
                if not myAch(curAch.ID).Objective(hunterSpawn).Completed() then
                    createLines(hunterSpawn)
                end
            else
                createLines(hunterSpawn)
            end
        end
    end
end 

local function InfoLine()
    ImGui.Separator()
    ImGui.TextColored(0.690, 0.553, 0.259, 1,'\xee\x9f\xbc')
    --[[if ImGui.BeginPopupContextItem('pcpopup') then
        PCList()
    end]]--
    ImGui.SameLine()
    local pcs = mq.TLO.SpawnCount('pc')() - mq.TLO.SpawnCount('group pc')()
    
    if pcs > 50 then 
        ImGui.TextColored(0.95, 0.05, 0.05, 1, tostring(pcs))
    elseif pcs > 25 then 
        ImGui.TextColored(0.95, 0.95, 0.05, 1, tostring(pcs))
    elseif pcs > 0 then 
        ImGui.TextColored(0.05, 0.95, 0.05, 1, tostring(pcs))
    else
        ImGui.TextDisabled(tostring(pcs))
    end

    ImGui.SameLine() ImGui.TextDisabled('|')
    if mq.TLO.Group() ~= nil then
        for i = 0, mq.TLO.Group.Members() do
            local member = mq.TLO.Group.Member(i)
            if member.Present() and not member.Mercenary() then
                ImGui.SameLine()
                if not member.Invis() then 
                    ImGui.TextColored(0.0, 0.95, 0.0, 1, 'F'..i+1)
                elseif member.Invis('NORMAL')() and not member.Invis('IVU')() then 
                    ImGui.TextDisabled('F'..i+1) 
                end
            end
        
        end
    else
        if not mq.TLO.Me.Invis() then 
            ImGui.SameLine()
            ImGui.TextColored(0.0, 0.95, 0.0, 1, 'F1')
        end
    end
    ImGui.SameLine() ImGui.TextDisabled('|')
    ImGui.SameLine()
    spawnUp = 0
    if spawnUp == 0 then ImGui.TextDisabled('\xee\x9f\xb5')  end
    if spawnUp == 1 then ImGui.TextColored(0.973, 0.741, 0.129, 1, '\xee\x9f\xb5') end
    if spawnUp == 2 then ImGui.TextColored(0.0129, 0.973, 0.129, 1, '\xee\x9f\xb5') end

end

local function RenderTitle()
    ImGui.SetWindowFontScale(1.15)
    local title = 0
    if curAch.ID then 
        title = curAch.Name
    else
        title = mq.TLO.Zone.Name()
    end
    ImGui.SetCursorPosX((ImGui.GetWindowWidth() - ImGui.CalcTextSize(title)) * 0.5)
    ImGui.TextColored(0.973, 0.741, 0.129, 1, title)
    ImGui.SetWindowFontScale(1)
    if ImGui.BeginPopupContextItem('titlepopup') then
        popupmenu()
    end
end

local function UltimateEQHud()
    if ShowUI then
        local themeToken = themeBridge.push()
        local pv, pc = push_spawnmaster_theme()
        ImGui.SetNextWindowSize(520, 600, ImGuiCond.FirstUseEver)
        Open, _ = ImGui.Begin('UltimateEQ Hud', Open, WindowFlags)
        RenderTitle()
        if curAch.ID then 
            RenderHunter() 
        end
        renderQuestMini()
        InfoLine()
        ImGui.End()
        pop_spawnmaster_theme(pv, pc)
        themeBridge.pop(themeToken)
    end
end

local function updateTables()
    myHunterSpawn = {}
    curAch = {}

    if AchID() ~= nil then
        curAch = {
            ID = AchID(),
            Name = myAch(AchID()).Name(),
            Count = myAch(AchID()).ObjectiveCount()
        }
        printf('\a#f8bd21Updating UltimateEQ Hud(\a#b08d42%s\a#f8bd21)', curAch.Name)
        local i = 0
        repeat
            if myAch(AchID()).ObjectiveByIndex(i)() ~= nil then
                table.insert(myHunterSpawn,myAch(AchID()).ObjectiveByIndex(i)())
            end
            i = i + 1
        until #myHunterSpawn == curAch.Count 
        printf('\a#f8bd21Updating Done(\a#b08d42%s\a#f8bd21)', curAch.Name)
    else 
        print('\a#f8bd21No Hunts found in \a#b08d42'..mq.TLO.Zone())
    end
end

local function normalizeSlashCommand(cmd)
    local c = tostring(cmd or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if c == '' then return '/hhtoggle' end
    if c:sub(1, 1) ~= '/' then c = '/' .. c end
    return c
end

local function toggleUltimateEQHud()
    local VividOrange = '\a#f8bd21'
    if ShowUI then
        printf('%sHiding UltimateEQ Hud', VividOrange)
        ShowUI = false
    else
        printf('%sShowing UltimateEQ Hud', VividOrange)
        ShowUI = true
    end
end

local function bindToggleCommand(cmd)
    local desired = normalizeSlashCommand(cmd)
    if activeToggleCommand and activeToggleCommand ~= '' and activeToggleCommand ~= desired then
        pcall(mq.unbind, activeToggleCommand)
    end
    if activeToggleCommand ~= desired then
        mq.bind(desired, toggleUltimateEQHud)
        activeToggleCommand = desired
    end
    toggleCommand = desired
end

local function bind_ueq(cmd)
    local VividOrange = '\a#f8bd21'
    local DarkOrange  = '\a#b08d42'
    local raw = tostring(cmd or ''):gsub('^%s+', ''):gsub('%s+$', '')
    local lower = raw:lower()

    if raw == '' then
        toggleUltimateEQHud()
    elseif lower == 'stop' then
        printf('%sUltimateEQ Hud Ended', VividOrange)
        Open = false
    elseif lower == 'quest' then
        showQuestMini = not showQuestMini
        saveQuestTracker()
        if showQuestMini then
            printf('%sShowing Quest Mini', VividOrange)
        else
            printf('%sHiding Quest Mini', VividOrange)
        end
    elseif lower == 'questauto' then
        questAutoTrack = not questAutoTrack
        saveQuestTracker()
        if questAutoTrack then
            printf('%sQuest auto-track enabled', VividOrange)
        else
            printf('%sQuest auto-track disabled', VividOrange)
        end
    elseif lower:match('^bind%s+') then
        local newCmd = raw:match('^bind%s+(.+)$')
        bindToggleCommand(newCmd)
        saveQuestTracker()
        printf('%sUltimateEQ Hud toggle command set to %s%s', VividOrange, DarkOrange, toggleCommand)
    else
        printf('%sUltimateEQ Hud usage:', VividOrange)
        printf('%s/ueq %sToggles showing and hiding UltimateEQ Hud', VividOrange, DarkOrange)
        printf('%s/ueq quest %sToggles the UltimateEQ Quest Mini', VividOrange, DarkOrange)
        printf('%s/ueq questauto %sToggles quest auto-track from chat events', VividOrange, DarkOrange)
        printf('%s/ueq bind /mytoggle %sSets custom slash command to toggle window', VividOrange, DarkOrange)
        printf('%sCurrent toggle bind: %s%s', VividOrange, DarkOrange, toggleCommand)
        printf('%s/ueq stop %sStop UltimateEQ Hud', VividOrange, DarkOrange)
    end

    return
end

mq.event('hh_quest_autotrack_kill', '#*#You have slain #1#.#*#', function(_, mobName)
    autoTrackQuestStep('kill', mobName)
end)

mq.event('hh_quest_autotrack_loot_a', '#*#You have looted a #1#.#*#', function(_, itemName)
    autoTrackQuestStep('loot', itemName)
end)

mq.event('hh_quest_autotrack_loot_an', '#*#You have looted an #1#.#*#', function(_, itemName)
    autoTrackQuestStep('loot', itemName)
end)

mq.event('hh_quest_autotrack_loot', '#*#You have looted #1#.#*#', function(_, itemName)
    autoTrackQuestStep('loot', itemName)
end)

mq.event('hh_quest_autotrack_receive', '#*#You receive #1#.#*#', function(_, itemName)
    autoTrackQuestStep('loot', itemName)
end)

mq.event('hh_quest_autotrack_turnin', '#*#You have given #1# to #2#.#*#', function(_, itemName)
    autoTrackQuestStep('turnin', itemName)
end)

mq.event('hh_quest_autotrack_complete_1', '#*#for completing #1# and receiving #2#.#*#', function(_, completedText)
    autoTrackQuestCompletion(completedText)
end)

mq.event('hh_quest_autotrack_complete_2', '#*# has completed #1#.#*#', function(_, completedText)
    autoTrackQuestCompletion(completedText)
end)

mq.event('hh_quest_autotrack_complete_3', '#*#has finished the quest: #1#!#*#', function(_, completedText)
    autoTrackQuestCompletion(completedText)
end)

mq.imgui.init('ultimateeq_hud', UltimateEQHud)
mq.bind('/ueq', bind_ueq)
loadQuestTracker()
loadAltCurrency()
bindToggleCommand(toggleCommand)

while Open do
    if oldZone ~= myZone() then
        updateTables()
        oldZone = myZone()
    end
    mq.delay(250)
end



--[[

Version 1.2.1
* Progrssbar will now show Completed! if the achievement is done.
* Findspawn function was optimized, cause i done dumb the first time.
* Fixed achievements:
    - Hunter of The Ruins of Old Guk       The Reinforced Ruins of Old Guk=gukbottom
    - Hunter of the Permafrost Caverns     Permafrost Keep=permafrost
    - Hunter of The Temple of Droga        The Temple of Droga=droga
    - Hunter of The Burning Wood           The Burning Woods=burningwood
    - Hunter of The Ruins of Old Sebilis   The Reinforced Ruins of Old Sebilis=sebilis
* Some rogue integer vars fixed to proper string vars where used
* Fancy icon for people in zone, still need to fix it proper counting when you not in group.

**Version 1.2.0
* Fixed achievements:
    - Hunter of The Feerrott               The Feerrott=Feerrott2
    - Hunter of West Karana (Ethernere)    Ethernere Tainted West Karana=ethernere
    - Hunter of the Plane of Hate: Broken Mirror  Plane of hate Revisited=hateplane
    - Hunter of Frontier Mountains         Frontier Mountains=frontiermtnsb
    - Hunter of Kurn's Tower               Kurn's Tower=oldkurn

* In world mob name to achievement objective name mapping, as some names dont match properly, please report names if you find any, i need a screenshot of the mobs ingame name, and the achievement name

* Removed some commnad line options as i didnt like them, now that we got the right click menu.

* Removed the check that made the achievment name grey when you didnt have any spawns up

* Added infoline (its a work in progrss!)
    - shows numbers of players in zone
    - Working on an invis indicator for group
    - Working on indicator for showing if spawns are up
        - indicator will show if you need the spawn or if its just or if something is just up.

* cleaned up some code and restructured some code to make it more modular and fanzys.



local function findspawnold(spawn)
    if nameMap[spawn] then spawn = nameMap[spawn] end
    local spawnCount = mq.TLO.SpawnCount(string.format('npc "%s"', spawn))()
    for i = 1, spawnCount do
        local mySpawn = mq.TLO.NearestSpawn(string.format('%d,npc "%s"',i , spawn))
        if mySpawn.CleanName() == spawn then
            return mySpawn.ID()
        end
    end
    return 0
end

]]--