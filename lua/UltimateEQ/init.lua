--[[ ProEQ / ProFusion quest tracker (RmlUi) — /lua run UltimateEQ  or  /lua run proeq ]]

local mq = require('mq')
local rmlui = require('rmlui')

local SCRIPT_DIR = (debug.getinfo(1, 'S').source:gsub('^@', ''):match('^(.*[\\/])')) or ''
local DATA_DIR = _G.UEQ_DATA_DIR or SCRIPT_DIR

local function dataFile(name)
    return DATA_DIR .. name
end

local function dataLoad(name)
    local ok, result = pcall(dofile, dataFile(name))
    if ok and type(result) == 'table' then
        return result
    end
    error('[ProEQ] missing ' .. dataFile(name))
end

local ueqFloat = nil
pcall(function() ueqFloat = require('ueq_logo_float') end)
local Open, ShowUI = true, true

local WIN_NAME = 'ProEQHud'
local win = nil
local nextHudUpdate = 0
local questViewAlt = false
local huntRowSlots = -1
local stepRowSlots = -1
local altRowSlots = -1
local visibleStepsCache = {}

local function esc(s)
    s = tostring(s or '')
    s = s:gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;'):gsub('"', '&quot;')
    return s
end

-- forward declarations used by quest mini helpers
local oldZone, myZone, showOnlyMissing, minimize, showGrind, onlySpawned, spawnUp, totalDone
local showQuestMini, questOnlyMissing, questTierIndex
local questAutoTrack, questAutoLastMsg
--- Quest Mini: `questMiniHideNav` — hide tier tabs + search (progress/chain/list only). `questMiniClearBg` — see-through HUD window.
local questMiniClearBg
local questMiniHideNav
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
    { name = 'Timekeeper Credits',      variants = { 'Timekeeper Credits',      'Timekeeper Credit'      } },
    { name = 'Najena Kill Points',      variants = { 'Najena Kill Points',      'Najena Kill Point'      } },
    { name = 'Riftseekers Kill Points', variants = { 'Riftseekers Kill Points', 'Riftseekers Kill Point'  } },
    { name = 'ProFusion Credits',       variants = { 'ProFusion Credits',       'ProFusion Credit'       } },
    { name = 'Season Credits',          variants = { 'Season Credits',          'Season Credit', 'Season Points' } },
    { name = 'Contributor Credits',     variants = { 'Contributor Credits',     'Contributor Credit'     } },
    { name = 'AA Points',               variants = { 'AA Points',               'Alternate Advancement Points' } },
}

local function printf(...)
    print(string.format(...))
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
    f:write(('  questMiniClearBg = %s,\n'):format(questMiniClearBg and 'true' or 'false'))
    f:write(('  questMiniHideNav = %s,\n'):format(questMiniHideNav and 'true' or 'false'))
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
    if type(loaded.questMiniClearBg) == 'boolean' then
        questMiniClearBg = loaded.questMiniClearBg
    end
    if type(loaded.questMiniHideNav) == 'boolean' then
        questMiniHideNav = loaded.questMiniHideNav
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
        return stepNorm:match('^turn in ') or stepNorm:match('^deliver ') or stepNorm:match('^give ')
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
        ['temple of veeshan'] = '11.1',
        ['tov'] = '11.1',
        ['riftseekers'] = '11.2',
        ['najena'] = '11.3',
        ['hidden najena'] = '11.3',
        ['the hole'] = '11.4',
        ['muramite proving'] = '11.5',
        ['proving grounds'] = '11.5',
        ['kael'] = '11.6',
        ['anguish'] = '11.7',
        ['sleeper'] = '11.8',
        ['sleepers'] = '11.8',
        ['xorbb'] = '11.9',
        ['valley of king xorbb'] = '11.9',
        ['devastation'] = '11.10',
        ['plane of time'] = '11.11',
        ['shards landing'] = '11.12',
        ['beast domain'] = '11.13',
        ['plane of hate'] = '11.14',
        ['hate'] = '11.14',
        ['frozen shadow'] = '11.15',
        ['tower of frozen shadow'] = '11.15',
        ['tofs'] = '11.15',
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
questMiniClearBg = false
questMiniHideNav = false
toggleCommand = '/hhtoggle'
activeToggleCommand = nil

-- shortening the mq bind for achievements 
local myAch = mq.TLO.Achievement

-- Table that will store the spawnnames of the Hunter achievement
local myHunterSpawn = {}

-- Current Achievemment information
local curAch = {}

questTrackerFile = dataFile('proeq_hud_quest_tracker.lua')
altCurrencyFile  = dataFile('proeq_hud_altcurrency.lua')

questTierOrder = {
    '11.1', '11.2', '11.3', '11.4', '11.5',
    '11.6', '11.7', '11.8', '11.9', '11.10',
    '11.11', '11.12', '11.13', '11.14', '11.15',
}

questData = dataLoad('proeq_quest_data.lua')

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

local QUEST_GROUP_TABS = {
    { label = 'T1-2', ids = { '11.1', '11.2' } },
    { label = 'T3-6', ids = { '11.3', '11.4', '11.5', '11.6' } },
    { label = 'T7-10', ids = { '11.7', '11.8', '11.9', '11.10' } },
    { label = 'T11-13', ids = { '11.11', '11.12', '11.13' } },
    { label = 'T14-15', ids = { '11.14', '11.15' } },
}

local function setTierById(gid)
    for i, id in ipairs(questTierOrder) do
        if id == gid then
            questTierIndex = i
            questPage = 1
            questViewAlt = false
            saveQuestTracker()
            return true
        end
    end
    return false
end

local function groupIndexForTier(tierId)
    for gi, group in ipairs(QUEST_GROUP_TABS) do
        for _, gid in ipairs(group.ids) do
            if gid == tierId then return gi end
        end
    end
    return 1
end

local function buildVisibleQuestSteps(tierId)
    local data = questData[tierId]
    local visible = {}
    if not data then return visible end
    local searchNorm = normalizeQuestText(questSearchText or '')
    for idx, step in ipairs(data.steps or {}) do
        local key = questStepKey(tierId, idx)
        local checked = isQuestStepDone(tierId, key)
        local includeMissing = (not questOnlyMissing) or (not checked)
        local includeSearch = (searchNorm == '') or (normalizeQuestText(step):find(searchNorm, 1, true) ~= nil)
        if includeMissing and includeSearch then
            visible[#visible + 1] = { idx = idx, key = key, step = step, checked = checked }
        end
    end
    return visible
end

local function ensureHudWindow()
    if win then return win end
    local w, err = rmlui.open(WIN_NAME, 'UltimateEQ/ui/hud.rml', {
        width = 520, height = 640, autoclose = true,
    })
    if not w then
        error('[ProEQ] RmlUi open failed: ' .. tostring(err))
    end
    w:theme('ember')
    win = w
    w:set_value('search', questSearchText or '')
    w:set_value('altsearch', altCurrencySearch or '')
    huntRowSlots, stepRowSlots, altRowSlots = -1, -1, -1
    return win
end

local function updateHudRml()
    local w = ensureHudWindow()
    if not w then return end

    w:class('body', 'see-through', questMiniClearBg)

    w:class('tg_min', 'on', minimize)
    w:class('tg_spawned', 'on', onlySpawned)
    w:class('tg_missing', 'on', showOnlyMissing)
    w:class('tg_quest', 'on', showQuestMini)
    w:class('tg_auto', 'on', questAutoTrack)
    w:class('tg_see', 'on', questMiniClearBg)
    w:class('tg_qmiss', 'on', questOnlyMissing)
    w:class('tg_nav', 'on', questMiniHideNav)
    w:text('tg_nav', questMiniHideNav and 'Show tabs' or 'Hide tabs')
    w:class('alt_live', 'on', altCurrencyLiveRead)
    w:text('alt_live', altCurrencyLiveRead and 'Live: ON' or 'Live: OFF')

    w:class('quest_panel', 'hidden', not showQuestMini)

    local zoneName = mq.TLO.Zone.Name() or 'Unknown zone'
    w:text('zone_name', zoneName)

    local huntDone, huntTotal = 0, 0
    local huntPct = 0
    local heroTitle = zoneName
    local heroProg = '--'
    if curAch.ID then
        heroTitle = curAch.Name or heroTitle
        if curAch.Count and curAch.Count > 0 then
            huntPct = getPctCompleted()
        end
        heroProg = totalDone ~= '' and totalDone or '--'
    else
        heroTitle = 'No hunt in zone'
        heroProg = '--'
    end
    w:text('hero_title', heroTitle)
    w:text('hero_prog', heroProg)
    w:text('st_hunt', heroProg)
    w:style('hunt_fill', 'width', string.format('%.1f%%', huntPct * 100))
    w:text('hunt_txt', heroProg)

    local chainDone, chainTotal = getOverallQuestCounts()
    w:text('st_chain', string.format('%d/%d', chainDone, chainTotal))

    w:class('nav', 'collapsed', questMiniHideNav)
    w:class('search_box', 'filled', (questSearchText or '') ~= '')
    w:class('alt_search_box', 'filled', (altCurrencySearch or '') ~= '')

    local tierId = questTierOrder[questTierIndex]
    local gi = groupIndexForTier(tierId)
    for i = 1, 5 do
        w:class('gt' .. i, 'on', (not questViewAlt) and i == gi)
    end
    w:class('gt_alt', 'on', questViewAlt)

    local group = QUEST_GROUP_TABS[gi]
    if group then
        for ti = 1, 4 do
            local gid = group.ids[ti]
            local tabId = 'tt' .. ti
            if gid then
                local label = questData[gid] and questData[gid].label or gid
                w:text(tabId, label)
                w:class(tabId, 'on', (not questViewAlt) and gid == tierId)
            else
                w:text(tabId, '-')
                w:class(tabId, 'on', false)
            end
        end
    end

    w:class('quest_body', 'hidden', questViewAlt)
    w:class('alt_body', 'hidden', not questViewAlt)

    if questViewAlt then
        if altCurrencyLiveRead then
            local now = os.time()
            if now ~= altCurrencyLastRefresh then
                altCurrencyLastRefresh = now
                refreshAltCurrencyFromGame()
            end
        end
        local searchNorm = (altCurrencySearch or ''):lower()
        local rows = {}
        for _, cur in ipairs(altCurrencyList) do
            if searchNorm == '' or cur.name:lower():find(searchNorm, 1, true) then
                rows[#rows + 1] = cur
            end
        end
        if altRowSlots ~= #rows then
            local parts = {}
            for i = 1, #rows do
                parts[i] = string.format(
                    '<div id="ar%d" class="alt-row"><span id="ar%dn" class="alt-name"></span><span id="ar%dv" class="alt-val"></span></div>',
                    i, i, i)
            end
            w.cache = {}
            w:rml('alt_list', table.concat(parts))
            altRowSlots = #rows
        end
        for i, cur in ipairs(rows) do
            w:text('ar' .. i .. 'n', cur.name)
            w:text('ar' .. i .. 'v', tostring(altCurrencyData[cur.name] or 0))
        end
    elseif showQuestMini and not minimize then
        local data = questData[tierId]
        if data then
            w:text('q_label', data.label or tierId)
            local doneCount, totalCount = getQuestCounts(tierId)
            local pct = totalCount > 0 and (doneCount / totalCount) or 0
            w:text('q_prog', string.format('Tier Progress: %d/%d Steps', doneCount, totalCount))
            w:style('q_fill', 'width', string.format('%.1f%%', pct * 100))
            local overallDone, overallTotal = getOverallQuestCounts()
            local overallPct = overallTotal > 0 and (overallDone / overallTotal) or 0
            w:text('q_chain', string.format('Overall Chain: %d/%d', overallDone, overallTotal))
            w:style('c_fill', 'width', string.format('%.1f%%', overallPct * 100))

            visibleStepsCache = buildVisibleQuestSteps(tierId)
            local totalPages = math.max(1, math.ceil(#visibleStepsCache / questStepsPerPage))
            if questPage > totalPages then questPage = totalPages end
            if questPage < 1 then questPage = 1 end
            w:text('q_page', string.format('Page %d / %d', questPage, totalPages))
            w:text('q_auto', questAutoLastMsg or '')

            local startIdx = ((questPage - 1) * questStepsPerPage) + 1
            local endIdx = math.min(#visibleStepsCache, startIdx + questStepsPerPage - 1)
            local pageCount = math.max(0, endIdx - startIdx + 1)

            if stepRowSlots ~= pageCount then
                local parts = {}
                for i = 1, pageCount do
                    parts[i] = string.format(
                        '<div id="qs%d" class="step-row" action="step:%d"><span id="qs%db" class="step-box">&#xE739;</span><span id="qs%dt" class="step-txt"></span></div>',
                        i, i, i, i)
                end
                w.cache = {}
                w:rml('steps', table.concat(parts))
                stepRowSlots = pageCount
            end
            for i = 1, pageCount do
                local row = visibleStepsCache[startIdx + i - 1]
                if row then
                    w:text('qs' .. i .. 't', row.step)
                    w:class('qs' .. i, 'on', row.checked)
                    w:text('qs' .. i .. 'b', row.checked and '&#xE73E;' or '&#xE739;')
                end
            end
        end
    end

    if curAch.ID then
        if minimize then
            if huntRowSlots ~= 0 then
                w:rml('hunt_list', '')
                huntRowSlots = 0
            end
        else
        local rows = {}
        for _, spawn in ipairs(myHunterSpawn) do
            local completed = myAch(curAch.ID).Objective(spawn).Completed()
            if showOnlyMissing and completed then
                -- skip
            else
                local sid = findspawn(spawn)
                if (not onlySpawned) or sid ~= 0 then
                    rows[#rows + 1] = { spawn = spawn, completed = completed, sid = sid }
                end
            end
        end
        if huntRowSlots ~= #rows then
            local parts = {}
            for i = 1, #rows do
                parts[i] = string.format(
                    '<div id="h%d" class="hunt-row" action="hunt:%d"><span id="h%dc" class="hunt-chk">&#xE739;</span><span id="h%dn" class="hunt-name"></span></div>',
                    i, i, i, i)
            end
            w.cache = {}
            w:rml('hunt_list', table.concat(parts))
            huntRowSlots = #rows
        end
        for i, row in ipairs(rows) do
            w:text('h' .. i .. 'n', row.spawn)
            w:class('h' .. i, 'done', row.completed)
            w:class('h' .. i, 'spawned', row.sid ~= 0)
            w:text('h' .. i .. 'c', row.completed and '&#xE73E;' or '&#xE739;')
        end
        end
    elseif huntRowSlots ~= 0 then
        w:rml('hunt_list', '')
        huntRowSlots = 0
    end

    local pcs = mq.TLO.SpawnCount('pc')() - mq.TLO.SpawnCount('group pc')()
    w:text('if_pcs', tostring(pcs))
    w:class('if_pcs', 'zero', pcs == 0)
    w:class('if_pcs', 'ok', pcs > 0 and pcs <= 25)
    w:class('if_pcs', 'warn', pcs > 25 and pcs <= 50)
    w:class('if_pcs', 'danger', pcs > 50)

    for i = 1, 6 do
        w:class('fk' .. i, 'hidden', true)
    end
    if mq.TLO.Group() ~= nil then
        for i = 0, mq.TLO.Group.Members() do
            local member = mq.TLO.Group.Member(i)
            if member.Present() and not member.Mercenary() and i < 6 then
                w:class('fk' .. (i + 1), 'hidden', false)
                if not member.Invis() then
                    w:text('fk' .. (i + 1), 'F' .. (i + 1))
                elseif member.Invis('NORMAL')() and not member.Invis('IVU')() then
                    w:text('fk' .. (i + 1), 'F' .. (i + 1))
                end
            end
        end
    elseif not mq.TLO.Me.Invis() then
        w:class('fk1', 'hidden', false)
        w:text('fk1', 'F1')
    end

    w:class('if_spawn', 'up', spawnUp == 1)
    w:class('if_spawn', 'hot', spawnUp == 2)
    w:text('if_spawn_txt', spawnUp == 0 and 'No spawns' or 'Spawns up')
end

local function handleHudEvent(ev)
    local a = ev.action or ''
    if ev.type == 'change' then
        if ev.id == 'search' then
            questSearchText = ev.value or ''
            questPage = 1
            stepRowSlots = -1
            return
        end
        if ev.id == 'altsearch' then
            altCurrencySearch = ev.value or ''
            altRowSlots = -1
            return
        end
        return
    end
    if ev.type ~= 'click' and ev.type ~= 'dblclick' then return end

    if a == 'window:close' then
        ShowUI = false
        printf('\a#f8bd21Hiding ProEQ Hud(\a#b08d42\'/proeq\' to show\ax)')
        return
    end
    if a == 'stop' then
        Open = false
        return
    end

    if a == 'tog:min' then minimize = not minimize; huntRowSlots = -1; return end
    if a == 'tog:spawned' then onlySpawned = not onlySpawned; huntRowSlots = -1; return end
    if a == 'tog:missing' then showOnlyMissing = not showOnlyMissing; huntRowSlots = -1; return end
    if a == 'tog:quest' then showQuestMini = not showQuestMini; saveQuestTracker(); return end
    if a == 'tog:auto' then questAutoTrack = not questAutoTrack; saveQuestTracker(); return end
    if a == 'tog:see' then questMiniClearBg = not questMiniClearBg; saveQuestTracker(); return end
    if a == 'tog:nav' then questMiniHideNav = not questMiniHideNav; saveQuestTracker(); return end
    if a == 'tog:qmiss' then questOnlyMissing = not questOnlyMissing; stepRowSlots = -1; saveQuestTracker(); return end
    if a == 'reset:tier' then
        local tierId = questTierOrder[questTierIndex]
        questTracker.tiers[tierId] = {}
        saveQuestTracker()
        stepRowSlots = -1
        return
    end
    if a == 'alt:refresh' then refreshAltCurrencyFromGame(); altRowSlots = -1; return end
    if a == 'alt:live' then altCurrencyLiveRead = not altCurrencyLiveRead; return end

    if a == 'grp:alt' then
        questViewAlt = true
        altRowSlots = -1
        return
    end
    local grp = tonumber(a:match('^grp:(%d+)$'))
    if grp and QUEST_GROUP_TABS[grp] then
        questViewAlt = false
        setTierById(QUEST_GROUP_TABS[grp].ids[1])
        stepRowSlots, altRowSlots = -1, -1
        return
    end

    local tierPick = tonumber(a:match('^tier:(%d+)$'))
    if tierPick then
        local gi = groupIndexForTier(questTierOrder[questTierIndex])
        local gid = QUEST_GROUP_TABS[gi] and QUEST_GROUP_TABS[gi].ids[tierPick]
        if gid then setTierById(gid) end
        questViewAlt = false
        stepRowSlots = -1
        return
    end

    if a == 'pg:first' then questPage = 1; stepRowSlots = -1; return end
    if a == 'pg:prev' then questPage = math.max(1, questPage - 1); stepRowSlots = -1; return end
    if a == 'pg:next' then questPage = questPage + 1; stepRowSlots = -1; return end
    if a == 'pg:last' then
        local vis = buildVisibleQuestSteps(questTierOrder[questTierIndex])
        questPage = math.max(1, math.ceil(#vis / questStepsPerPage))
        stepRowSlots = -1
        return
    end

    local stepIdx = tonumber(a:match('^step:(%d+)$'))
    if stepIdx and ev.type == 'click' then
        local row = visibleStepsCache[((questPage - 1) * questStepsPerPage) + stepIdx]
        if row then
            setQuestStepDone(questTierOrder[questTierIndex], row.key, not row.checked)
            stepRowSlots = -1
        end
        return
    end

    local huntIdx = tonumber(a:match('^hunt:(%d+)$'))
    if huntIdx and ev.type == 'dblclick' then
        local spawn = nil
        local n = 0
        for _, s in ipairs(myHunterSpawn) do
            local completed = myAch(curAch.ID).Objective(s).Completed()
            if not (showOnlyMissing and completed) then
                local sid = findspawn(s)
                if (not onlySpawned) or sid ~= 0 then
                    n = n + 1
                    if n == huntIdx then
                        spawn = s
                        if sid ~= 0 then
                            mq.cmdf('/nav id %d log=error', sid)
                            printf('\ayMoving to \ag%s', s)
                        end
                        break
                    end
                end
            end
        end
    end
end

local function drawLogoFloat()
    if not ueqFloat or not ueqFloat.drawFloating then return end
    ueqFloat.drawFloating({
        id = 'ProEQHud',
        resourceName = 'ProEQ Hud',
        windowTitle = 'Hide / show — ProEQ',
        imageRelPath = 'ProEQ/proeq-helper.png',
        placement = 'top_left',
        sizePx = 100,
        fallbackLabel = 'PEQ',
        isAnyOpen = function() return ShowUI == true end,
        onClick = function()
            ShowUI = not ShowUI
            if ShowUI then
                printf('\a#f8bd21Showing ProEQ Hud')
            else
                printf('\a#f8bd21Hiding ProEQ Hud')
            end
        end,
        tooltipHide = 'Hide tracker window (click again to show)',
        tooltipShow = 'Show tracker window',
    })
end

local function hudTick()
    if not Open then return end
    local w = ensureHudWindow()
    if not w then return end
    -- Always drain events while the script runs so autoclose can detect /lua stop,
    -- and so hide/toggle does not orphan the window after 5s.
    for ev in w:events() do
        local ok, err = pcall(handleHudEvent, ev)
        if not ok then printf('[ProEQ] event error: %s', tostring(err)) end
    end
    if not ShowUI then
        w:show(false)
        return
    end
    if not w:is_open() then
        Open = false
        return
    end
    w:show(true)
    local t = mq.gettime and mq.gettime() or (os.time() * 1000)
    if t >= nextHudUpdate then
        nextHudUpdate = t + 200
        local ok, err = pcall(updateHudRml)
        if not ok then
            printf('[ProEQ] UI update error: %s', tostring(err))
            nextHudUpdate = t + 1000
        end
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
        printf('\a#f8bd21Updating ProEQ Hud(\a#b08d42%s\a#f8bd21)', curAch.Name)
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

local function toggleProEQHud()
    local VividOrange = '\a#f8bd21'
    if ShowUI then
        printf('%sHiding ProEQ Hud', VividOrange)
        ShowUI = false
    else
        printf('%sShowing ProEQ Hud', VividOrange)
        ShowUI = true
        nextHudUpdate = 0
    end
end

local function bindToggleCommand(cmd)
    local desired = normalizeSlashCommand(cmd)
    if activeToggleCommand and activeToggleCommand ~= '' and activeToggleCommand ~= desired then
        pcall(mq.unbind, activeToggleCommand)
    end
    if activeToggleCommand ~= desired then
        mq.bind(desired, toggleProEQHud)
        activeToggleCommand = desired
        toggleCommand = desired
    end
end

local function bind_proeq(cmd)
    local VividOrange = '\a#f8bd21'
    local DarkOrange  = '\a#b08d42'
    local raw = tostring(cmd or ''):gsub('^%s+', ''):gsub('%s+$', '')
    local lower = raw:lower()

    if raw == '' then
        toggleProEQHud()
    elseif lower == 'stop' then
        printf('%sProEQ Hud Ended', VividOrange)
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
        printf('%sProEQ Hud toggle command set to %s%s', VividOrange, DarkOrange, toggleCommand)
    else
        printf('%sProEQ Hud usage:', VividOrange)
        printf('%s/proeq %sToggles showing and hiding ProEQ Hud', VividOrange, DarkOrange)
        printf('%s/proeq quest %sToggles the ProEQ Quest Mini', VividOrange, DarkOrange)
        printf('%s/proeq questauto %sToggles quest auto-track from chat events', VividOrange, DarkOrange)
        printf('%s/proeq bind /mytoggle %sSets custom slash command to toggle window', VividOrange, DarkOrange)
        printf('%sCurrent toggle bind: %s%s', VividOrange, DarkOrange, toggleCommand)
        printf('%s/proeq stop %sStop ProEQ Hud', VividOrange, DarkOrange)
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

pcall(function() mq.imgui.init('proeq_hud_float', drawLogoFloat) end)
mq.bind('/proeq', bind_proeq)
mq.bind('/ueq', bind_proeq)
loadQuestTracker()
loadAltCurrency()
bindToggleCommand(toggleCommand)
updateTables()
mq.cmd('/echo [ProEQ] RmlUi HUD loaded. /proeq  /ueq  — /proeq stop to end')

local function cleanup()
    pcall(function() rmlui.close_all() end)
    pcall(function() mq.unbind('/proeq') end)
    pcall(function() mq.unbind('/ueq') end)
    if activeToggleCommand then pcall(mq.unbind, activeToggleCommand) end
end

local ok, err = pcall(function()
    while Open do
        mq.doevents()
        hudTick()
        if oldZone ~= myZone() then
            updateTables()
            huntRowSlots = -1
            nextHudUpdate = 0
            oldZone = myZone()
        end
        mq.delay(50)
    end
end)
if not ok and err then printf('[ProEQ] stop: %s', tostring(err)) end
cleanup()



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
