local mq = require('mq')
local imgui = require('ImGui')

local progression = require('data_progression')
local systems = require('data_systems')
local gettingStartedData = require('data_getting_started')
local macroquestData = require('data_macroquest')
local aaGuideData = require('data_aa_grinding')
local epicsData = require('data_epics')
local swordData = require('data_sword_experience')
local commandsData = require('data_server_commands')

local zoneNamesOk, zoneNamesData = pcall(require, 'data_zone_names')
if not zoneNamesOk or type(zoneNamesData) ~= 'table' then
    zoneNamesData = { lines = { 'Zone reference failed to load.', '', tostring(zoneNamesData) } }
end

local categoryRenderers = {}
local themeController = nil

local colors = {
    title = { 0.95, 0.82, 0.32, 1.0 },
    section = { 0.86, 0.62, 0.96, 1.0 },
    subsection = { 0.73, 0.80, 1.0, 1.0 },
    body = { 0.92, 0.92, 0.95, 1.0 },
    bullet = { 0.60, 0.88, 0.98, 1.0 },
    emphasis = { 1.0, 0.88, 0.45, 1.0 },
    warning = { 1.0, 0.52, 0.52, 1.0 },
}

local tierTrackerFile = 'tier_progress_tracker.lua'
do
    local mqRoot = mq.TLO and mq.TLO.MacroQuest and mq.TLO.MacroQuest.Path and mq.TLO.MacroQuest.Path()
    if mqRoot and mqRoot ~= '' then
        tierTrackerFile = mqRoot .. '\\lua\\pro\\tier_progress_tracker.lua'
    end
end

local trackedTierOrder = {
    '11.1', '11.2', '11.3', '11.4', '11.5', '11.6', '11.7', '11.8', '11.9', '11.10',
    '11.11', '11.12', '11.13', '11.14', '11.15',
}

local tierGuides = {
    ['11.1'] = {
        title = 'Pre-Ultimate Progression',
        lines = {
            'Complete these in order with Mel:',
            '- Vanilla -> Kunark -> Velious -> Luclin -> Planes of Power.',
            '- Each turn-in upgrades Ultimate Charm rank and grants AA rewards.',
        },
        steps = {
            'Collect Nagafen\'s Head and return it to Mel.',
            'Collect Innoruuk\'s Brain and return it to Mel.',
            'Collect Cazic Thule\'s Eye and return it to Mel.',
            'Turn in your Ultimate Charm with the Vanilla set to Mel.',
            'Collect Trakanon\'s Tail and return it to Mel.',
            'Collect Phara Dar\'s Tooth and return it to Mel.',
            'Collect Venril Sathir\'s Belt and return it to Mel.',
            'Turn in Ultimate Charm - Tier 1 with the Kunark set to Mel.',
            'Collect The Statue\'s Helmet and return it to Mel.',
            'Collect Tunare\'s Torn Dress and return it to Mel.',
            'Collect Vulak\'s Scale and return it to Mel.',
            'Turn in Ultimate Charm - Tier 2 with the Velious set to Mel.',
            'Collect Emperor Ssra\'s Idol and return it to Mel.',
            'Collect Aten\'s Ring and return it to Mel.',
            'Collect Grieg\'s Torn Parchment and return it to Mel.',
            'Turn in Ultimate Charm - Tier 3 with the Luclin set to Mel.',
            'Collect Rallos Zek\'s Axe and return it to Mel.',
            'Collect Solusek\'s Burning Staff and return it to Mel.',
            'Collect Fenin Ro\'s Burning Boots and return it to Mel.',
            'Turn in Ultimate Charm - Tier 4 with the PoP set to Mel.',
        },
    },
    ['11.2'] = {
        title = 'Ultimate Rank 1 Access',
        lines = {
            'Goal: unlock Ultimate Upper/Lower Guk access.',
            'Flow: complete Crushbone challenge and report completion chain.',
        },
        steps = {
            'Defeat Dvinn the Tormentor.',
            'Defeat Ser Darish the Black.',
            'Defeat Crush the Transformed and loot Heart of Crush the Transformed.',
            'Deliver Heart of Crush the Transformed to Forge.',
            'Hail Quake to claim Ultimate Rank 1 access.',
        },
    },
    ['11.3'] = {
        title = 'Ultimate Rank 2 Access',
        lines = {
            'Goal: unlock Ultimate Sebilis.',
            'All four heads are required in one Mel hand-in.',
        },
        steps = {
            'Collect Ghoul Lord\'s Head.',
            'Collect Froglok King\'s Head.',
            'Collect Shin Lord\'s Head.',
            'Collect Ancient Croc\'s Head.',
            'Turn in all four heads to Mel at once.',
            'Hail Quake to enter Sebilis.',
        },
    },
    ['11.4'] = {
        title = 'Ultimate Rank 3 Access',
        lines = {
            'Goal: unlock Temple of Veeshan.',
            'Requirement: craft your Ultimate Legendary weapon line via Forge.',
        },
        steps = {
            'Collect Legendary Mold in Ultimate zones.',
            'Collect Ultimate Token in Ultimate zones.',
            'Deliver Ultimate weapon recipe materials to Forge.',
            'Obtain your Ultimate Legendary weapon completion flag.',
            'Hail Quake to claim Temple of Veeshan access.',
        },
    },
    ['11.5'] = {
        title = 'Ultimate Rank 4 Access',
        lines = {
            'Goal: unlock Ultimate Kael Drakkel.',
            'Requirement: complete Temple of Veeshan with Mel hand-in.',
        },
        steps = {
            'Defeat Ultimate Vulak and collect Ultimate Vulak\'s Scale.',
            'Turn in Ultimate Vulak\'s Scale to Mel.',
            'Hail Quake to access Ultimate Kael Drakkel.',
        },
    },
    ['11.6'] = {
        title = 'Ultimate Rank 5 Access',
        lines = {
            'Goal: unlock Ultimate Sleeper\'s Tomb.',
            'Requirement: complete Kael Drakkel progression hand-in.',
        },
        steps = {
            'Collect Ultimate Kael Completion Pass.',
            'Turn in Ultimate Kael Completion Pass to Mel.',
            'Hail Quake to access Ultimate Sleeper\'s Tomb.',
        },
    },
    ['11.7'] = {
        title = 'Avatar Rank 1 Access',
        lines = {
            'Goal: unlock Blackburrow, Mistmoore, and Solusek A.',
            'Requirement: Sleeper\'s Tomb completion plus Rank 6 charm completion.',
        },
        steps = {
            'Collect Ultimate Kerafyrm\'s Scale from Sleeper path.',
            'Turn in Ultimate Kerafyrm\'s Scale to Mel.',
            'Collect Ultimate Charm Upgrade Token (Rank 6) from Uber Megalodon path.',
            'Deliver Rank 6 token to Arch Magus Phil.',
            'Hail Quake to unlock Avatar Rank 1 zones.',
        },
    },
    ['11.8'] = {
        title = 'Avatar Rank 2 Access',
        lines = {
            'Goal: unlock The Hole.',
            'Requirement: three heads in one Mel turn-in.',
        },
        steps = {
            'Collect Mayong\'s Head.',
            'Collect Fippy\'s Head.',
            'Collect Goblin King\'s Head.',
            'Turn in all three heads to Mel at once.',
            'Hail Quake to access The Hole.',
        },
    },
    ['11.9'] = {
        title = 'Avatar Rank 3 Access',
        lines = {
            'Goal: unlock Tower of Frozen Shadow.',
            'Requirement: complete The Hole and Rank 7 charm progression.',
        },
        steps = {
            'Collect An Earthen Soulstone.',
            'Turn in An Earthen Soulstone to Mel.',
            'Complete Rank 7 charm path with Measel in The Hole.',
            'Hail Quake to unlock Tower of Frozen Shadow.',
        },
    },
    ['11.10'] = {
        title = 'Avatar Rank 4 Access',
        lines = {
            'Goal: unlock Veeshan\'s Peak.',
            'Requirement: complete Tower of Frozen Shadow progression.',
        },
        steps = {
            'Collect Frozen Avatar Energy.',
            'Turn in Frozen Avatar Energy to Mel.',
            'Hail Quake to unlock Veeshan\'s Peak.',
        },
    },
    ['11.11'] = {
        title = 'Demigod Rank 1 Access',
        lines = {
            'Goal: unlock Ocean of Tears and Unrest.',
            'Requirement: Veeshan\'s Peak completion and Rank 8 charm completion.',
        },
        steps = {
            'Collect Heart of the Peak.',
            'Turn in Heart of the Peak to Mel.',
            'Complete Rank 8 charm path with Measel in Veeshan\'s Peak.',
            'Hail Seism to unlock Ocean of Tears.',
            'Hail Seism to unlock Unrest.',
        },
    },
    ['11.12'] = {
        title = 'Demigod Rank 2 Access',
        lines = {
            'Goal: unlock Plane of Fear.',
            'Requirements: Ocean completion, Unrest completion, Ultimate 2.0 completion, and Rank 9 charm completion.',
        },
        steps = {
            'Collect Coalesced Demigod Energy.',
            'Turn in Coalesced Demigod Energy to Mel.',
            'Collect Ultimate Unrest Commendation.',
            'Turn in Ultimate Unrest Commendation to Mel.',
            'Complete Ultimate 2.0 with Cloud in Ocean of Tears.',
            'Complete Rank 9 charm path with Arch Magus Phil in Ocean of Tears.',
            'Create Plane of Fear instance via Seism.',
        },
    },
    ['11.13'] = {
        title = 'Demigod Rank 3 Access',
        lines = {
            'Goal: unlock Velketor\'s Labyrinth.',
            'Requirement: complete Plane of Fear token turn-in.',
        },
        steps = {
            'Collect A Freshly Severed Head in Plane of Fear path.',
            'Turn in A Freshly Severed Head to Mel.',
            'Hail Seism to unlock Velketor\'s Labyrinth.',
        },
    },
    ['11.14'] = {
        title = 'Demigod Rank 4 Access',
        lines = {
            'Goal: unlock The Treasure Goblin Vault.',
            'Requirements: Velketor completion and Rank 10 charm completion.',
        },
        steps = {
            'Collect Velketorian Essence.',
            'Turn in Velketorian Essence to Mel.',
            'Complete Rank 10 charm path with Farnsworth in Velketor\'s Labyrinth.',
            'Create Treasure Goblin Vault instance with Seism.',
        },
    },
    ['11.15'] = {
        title = 'God Progression Access',
        lines = {
            'Goal: enter God tier, progress to level 75, and unlock God Tier 2.',
            'Core NPCs: Mel, Seism, Illuminous, Crumble.',
        },
        steps = {
            'Collect Realm of the Gods Commendation.',
            'Turn in Realm of the Gods Commendation to Mel.',
            'Hail Illuminous and complete all three confirmation prompts.',
            'Enter Elddar Forest or Old Kurn\'s Tower to obtain level 71.',
            'Spend 250 Tier 9 credits with Illuminous to obtain level 72.',
            'Collect 4x item 149854 and turn in to Illuminous for level 73.',
            'Collect 149855, 149856, 149857, and 149858 then turn in to Illuminous for level 74.',
            'Collect item 149859 and turn in to Illuminous for level 75.',
            'Hail Seism to enter Crystallos.',
            'Collect Abomination Head and turn in to Mel for God Tier 2 access.',
        },
    },
}

local rulesLines = {
    'Server Rules (Practical)',
    '',
    '- Follow progression order; access checks are strict and intentional.',
    '- Do not exploit instance mechanics, duplicate turn-ins, or automation abuse.',
    '- Keep interactions respectful in public channels and shared zones.',
    '- If in doubt about a system, check Herald or ask staff before committing resources.',
}

local eqMacroLines = {
    'EQ Built-In Macro Basics',
    '',
    '- /pause, /doability, /cast, /target, /assist are the standard foundation.',
    '- Use simple one-purpose macros first, then layer behavior.',
    '- Keep emergency stop and defensive utility on dedicated hotkeys.',
}

local optionalContentLines = {
    'Optional and Expedition Content',
    '',
    '- Seism supports God expeditions (Caverns of Exile and Bloodmoon Keep).',
    '- You need expedition map credits from Aftershock to create those instances.',
    '- Plane of Fear and Treasure Goblin Vault are private instance style progression gates.',
    '- Extra content is valuable for loot and talent-cap progression, but not all of it is mandatory for first clear paths.',
}

local tierTracker = { tiers = {} }

local function syncThemeColors()
    if not themeController or not themeController.getTextColors then
        return
    end
    local set = themeController.getTextColors()
    if type(set) ~= 'table' then
        return
    end
    for k, v in pairs(set) do
        if type(v) == 'table' and #v >= 4 then
            colors[k] = { v[1], v[2], v[3], v[4] }
        end
    end
end

local function trimText(s)
    return ((s or ''):gsub('^%s+', ''):gsub('%s+$', ''))
end

local function normalizeStepText(line)
    local t = trimText(line or '')
    t = t:gsub('^%s*[-]+%s*', '')
    t = t:gsub('^%s*[%d]+[%.%)]%s*', '')
    t = t:lower()
    t = t:gsub('[%.!:%s]+$', '')
    t = t:gsub('%s+', ' ')
    return t
end

local function isTrackableStep(line)
    local t = normalizeStepText(line)
    if t == '' then
        return false
    end
    return t:match('^kill ')
        or t:match('^defeat ')
        or t:match('^loot ')
        or t:match('^collect ')
        or t:match('^combine ')
        or t:match('^turn in ')
        or t:match('^deliver ')
        or t:match('^hail ')
        or t:match('^hand ')
        or t:match('^give ')
        or t:match('^create ')
        or t:match('^obtain ')
        or t:match('^spend ')
        or t:match('^enter ')
end

local function nextStepKey(tierId, line, seen)
    local text = normalizeStepText(line)
    local count = (seen[text] or 0) + 1
    seen[text] = count
    return tierId .. '|' .. text .. '|' .. tostring(count)
end

local function saveTierTracker()
    local handle = io.open(tierTrackerFile, 'w')
    if not handle then
        return
    end

    handle:write('return {\n')
    handle:write('  tiers = {\n')
    for _, tierId in ipairs(trackedTierOrder) do
        local entries = (tierTracker.tiers and tierTracker.tiers[tierId]) or {}
        handle:write(("    ['%s'] = {\n"):format(tierId))
        for _, key in ipairs(entries) do
            handle:write(('      %q,\n'):format(key))
        end
        handle:write('    },\n')
    end
    handle:write('  },\n')
    handle:write('}\n')
    handle:close()
end

local function loadTierTracker()
    local ok, loaded = pcall(dofile, tierTrackerFile)
    if not ok or type(loaded) ~= 'table' or type(loaded.tiers) ~= 'table' then
        return
    end
    tierTracker.tiers = {}
    for _, tierId in ipairs(trackedTierOrder) do
        tierTracker.tiers[tierId] = {}
        local src = loaded.tiers[tierId]
        if type(src) == 'table' then
            for _, key in ipairs(src) do
                if type(key) == 'string' and key ~= '' then
                    table.insert(tierTracker.tiers[tierId], key)
                end
            end
        end
    end
end

local function isTrackedTier(tierId)
    for _, id in ipairs(trackedTierOrder) do
        if id == tierId then
            return true
        end
    end
    return false
end

local function isStepChecked(tierId, stepKey)
    local entries = (tierTracker.tiers and tierTracker.tiers[tierId]) or {}
    for _, key in ipairs(entries) do
        if key == stepKey then
            return true
        end
    end
    return false
end

local function setStepChecked(tierId, stepKey, checked)
    tierTracker.tiers[tierId] = tierTracker.tiers[tierId] or {}
    local entries = tierTracker.tiers[tierId]

    local existing = nil
    for i, key in ipairs(entries) do
        if key == stepKey then
            existing = i
            break
        end
    end

    if checked and not existing then
        table.insert(entries, stepKey)
    elseif (not checked) and existing then
        table.remove(entries, existing)
    end

    saveTierTracker()
end

local function getTrackedLinesForTier(tierId)
    local guide = tierGuides[tierId]
    return (guide and guide.steps) or {}
end

local function getTierProgressCounts(tierId)
    local lines = getTrackedLinesForTier(tierId)
    local seen = {}
    local checked, total = 0, 0

    for _, line in ipairs(lines) do
        if isTrackableStep(line) then
            total = total + 1
            local key = nextStepKey(tierId, line, seen)
            if isStepChecked(tierId, key) then
                checked = checked + 1
            end
        end
    end

    return checked, total
end

local function renderTierProgressLine(tierId)
    local checked, total = getTierProgressCounts(tierId)
    local pct = 0
    if total > 0 then
        pct = math.floor((checked / total) * 100 + 0.5)
    end

    imgui.PushStyleColor(ImGuiCol.Text, colors.emphasis[1], colors.emphasis[2], colors.emphasis[3], colors.emphasis[4])
    imgui.TextWrapped(('Progress Tracker: %d/%d steps complete (%d%%)'):format(checked, total, pct))
    imgui.PopStyleColor()
end

local function getNextUncheckedStep(tierId)
    local lines = getTrackedLinesForTier(tierId)
    local seen = {}
    for _, line in ipairs(lines) do
        if isTrackableStep(line) then
            local key = nextStepKey(tierId, line, seen)
            if not isStepChecked(tierId, key) then
                return line
            end
        end
    end
    return nil
end

local function getProgressStatus()
    local overallChecked, overallTotal = 0, 0
    local completedTiers = 0
    local activeTierId, nextStep = nil, nil

    for _, tierId in ipairs(trackedTierOrder) do
        local checked, total = getTierProgressCounts(tierId)
        overallChecked = overallChecked + checked
        overallTotal = overallTotal + total

        local done = total > 0 and checked == total
        if done then
            completedTiers = completedTiers + 1
        elseif not activeTierId then
            activeTierId = tierId
            nextStep = getNextUncheckedStep(tierId)
        end
    end

    local pct = 0
    if overallTotal > 0 then
        pct = math.floor((overallChecked / overallTotal) * 100 + 0.5)
    end

    return {
        overallChecked = overallChecked,
        overallTotal = overallTotal,
        overallPct = pct,
        completedTiers = completedTiers,
        totalTiers = #trackedTierOrder,
        activeTierId = activeTierId,
        nextStep = nextStep,
    }
end

local function normalizeMatchToken(text)
    local t = trimText(text or ''):lower()
    t = t:gsub('[%p]', ' ')
    t = t:gsub('%s+', ' ')
    return trimText(t)
end

local function actionMatchesStep(action, stepNorm, tokenNorm)
    if tokenNorm == '' then
        return false
    end
    if not stepNorm:find(tokenNorm, 1, true) then
        return false
    end

    if action == 'kill' then
        return stepNorm:match('^kill ') or stepNorm:match('^defeat ')
    end
    if action == 'loot' then
        return stepNorm:match('^loot ') or stepNorm:match('^collect ') or stepNorm:match('^obtain ')
    end
    if action == 'hail' then
        return stepNorm:match('^hail ')
    end
    if action == 'turnin' then
        return stepNorm:match('^turn in ') or stepNorm:match('^give ') or stepNorm:match('^deliver ')
    end

    return false
end

local function autoTrackByAction(action, targetText, tierId)
    local tokenNorm = normalizeMatchToken(targetText)
    if tokenNorm == '' then
        return false
    end

    local order = {}
    if tierId and isTrackedTier(tierId) then
        order[#order + 1] = tierId
    else
        local status = getProgressStatus()
        if status.activeTierId then
            order[#order + 1] = status.activeTierId
        end
        for _, id in ipairs(trackedTierOrder) do
            local exists = false
            for _, x in ipairs(order) do
                if x == id then
                    exists = true
                    break
                end
            end
            if not exists then
                order[#order + 1] = id
            end
        end
    end

    for _, id in ipairs(order) do
        local lines = getTrackedLinesForTier(id)
        local seen = {}
        for _, line in ipairs(lines) do
            if isTrackableStep(line) then
                local stepKey = nextStepKey(id, line, seen)
                if not isStepChecked(id, stepKey) then
                    local stepNorm = normalizeMatchToken(normalizeStepText(line))
                    if actionMatchesStep(action, stepNorm, tokenNorm) then
                        setStepChecked(id, stepKey, true)
                        return true, id, line
                    end
                end
            end
        end
    end

    return false
end

local function markTierComplete(tierId)
    if not isTrackedTier(tierId) then
        return false
    end

    local changed = false
    local lines = getTrackedLinesForTier(tierId)
    local seen = {}

    for _, line in ipairs(lines) do
        if isTrackableStep(line) then
            local key = nextStepKey(tierId, line, seen)
            if not isStepChecked(tierId, key) then
                setStepChecked(tierId, key, true)
                changed = true
            end
        end
    end

    return changed
end

local function pushColor(rgba)
    imgui.PushStyleColor(ImGuiCol.Text, rgba[1], rgba[2], rgba[3], rgba[4])
end

local function drawLine(line)
    local t = tostring(line or '')
    if trimText(t) == '' then
        imgui.Spacing()
        return
    end

    if t:match('^WARNING') then
        pushColor(colors.warning)
        imgui.TextWrapped(t)
        imgui.PopStyleColor()
        return
    end

    if t:match('^%- ') then
        pushColor(colors.bullet)
        imgui.TextWrapped(t)
        imgui.PopStyleColor()
        return
    end

    if t:match(':$') then
        pushColor(colors.section)
        imgui.TextWrapped(t)
        imgui.PopStyleColor()
        return
    end

    pushColor(colors.body)
    imgui.TextWrapped(t)
    imgui.PopStyleColor()
end

local function renderLines(lines)
    for _, line in ipairs(lines or {}) do
        drawLine(line)
    end
end

local function renderTierHeader(tierId)
    local tier = progression.tiers[tierId]
    local label = tierId
    for _, p in ipairs(progression.progression_tiers or {}) do
        if p.id == tierId then
            label = p.label
            break
        end
    end

    pushColor(colors.title)
    imgui.TextWrapped(label)
    imgui.PopStyleColor()

    if tier then
        imgui.Separator()
        pushColor(colors.subsection)
        imgui.TextWrapped('Task: ' .. (tier.task or 'N/A'))
        imgui.TextWrapped('Guide NPC(s): ' .. (tier.giver or 'N/A'))
        imgui.TextWrapped('Access Command/Flow: ' .. (tier.cmd or 'N/A'))
        imgui.PopStyleColor()
    end

    imgui.Spacing()
    renderTierProgressLine(tierId)
    imgui.Separator()
end

local function renderTrackedSteps(tierId)
    local guide = tierGuides[tierId] or {}
    local steps = guide.steps or {}
    local seen = {}

    pushColor(colors.section)
    imgui.Text('Tracked Steps')
    imgui.PopStyleColor()

    for _, line in ipairs(steps) do
        if isTrackableStep(line) then
            local stepKey = nextStepKey(tierId, line, seen)
            local checked = isStepChecked(tierId, stepKey)
            local buttonLabel = checked and ('[x]##' .. stepKey) or ('[ ]##' .. stepKey)
            if imgui.SmallButton(buttonLabel) then
                setStepChecked(tierId, stepKey, not checked)
                checked = not checked
            end
            imgui.SameLine()
            if checked then
                pushColor(colors.emphasis)
            else
                pushColor(colors.body)
            end
            imgui.TextWrapped(line)
            imgui.PopStyleColor()
        end
    end
end

local function renderTierPage(tierId)
    syncThemeColors()
    renderTierHeader(tierId)

    local guide = tierGuides[tierId] or {}

    if guide.lines and #guide.lines > 0 then
        pushColor(colors.section)
        imgui.Text('Overview')
        imgui.PopStyleColor()
        renderLines(guide.lines)
        imgui.Spacing()
    end

    renderTrackedSteps(tierId)
end

local function renderSimplePage(title, lines)
    syncThemeColors()
    pushColor(colors.title)
    imgui.TextWrapped(title)
    imgui.PopStyleColor()
    imgui.Separator()
    renderLines(lines)
end

categoryRenderers['11.0'] = function()
    local function tierLabelById(tierId)
        for _, p in ipairs(progression.progression_tiers or {}) do
            if p.id == tierId then
                return p.label
            end
        end
        return tierId
    end

    local function renderMasterProgressTracker()
        local status = getProgressStatus()
        pushColor(colors.emphasis)
        imgui.TextWrapped(('Overall: %d/%d steps (%d%%)'):format(status.overallChecked, status.overallTotal, status.overallPct))
        imgui.TextWrapped(('Tiers Complete: %d/%d'):format(status.completedTiers, status.totalTiers))
        imgui.PopStyleColor()

        local frac = 0
        if status.overallTotal > 0 then
            frac = status.overallChecked / status.overallTotal
        end
        if imgui.ProgressBar then
            imgui.ProgressBar(frac, -1, 18, ('%d%% overall completion'):format(status.overallPct))
        end

        imgui.Spacing()
        imgui.Separator()
        pushColor(colors.section)
        imgui.Text('Current Focus')
        imgui.PopStyleColor()
        if status.activeTierId and status.nextStep and status.nextStep ~= '' then
            imgui.TextWrapped('[' .. tierLabelById(status.activeTierId) .. '] ' .. status.nextStep)
        else
            imgui.TextWrapped('All tracked tiers are complete.')
        end

        imgui.Spacing()
        imgui.Separator()
        pushColor(colors.section)
        imgui.Text('Remaining Tiers')
        imgui.PopStyleColor()

        local shown = 0
        for _, tierId in ipairs(trackedTierOrder) do
            local checked, total = getTierProgressCounts(tierId)
            if total > 0 and checked < total then
                shown = shown + 1
                local pct = math.floor((checked / total) * 100 + 0.5)
                imgui.TextWrapped(('%s: %d/%d (%d%%)'):format(tierLabelById(tierId), checked, total, pct))
            end
        end
        if shown == 0 then
            imgui.TextWrapped('No remaining tiers.')
        end
    end

    syncThemeColors()
    pushColor(colors.title)
    imgui.Text('UltimateEQ Master Progress Tracker')
    imgui.PopStyleColor()
    imgui.Separator()
    renderMasterProgressTracker()
end

for _, tierId in ipairs(trackedTierOrder) do
    categoryRenderers[tierId] = function()
        renderTierPage(tierId)
    end
end

categoryRenderers['1.0'] = function()
    renderSimplePage('Getting Started', gettingStartedData.lines)
end

categoryRenderers['2.0'] = function()
    renderSimplePage('Server Rules', rulesLines)
end

categoryRenderers['3.0'] = function()
    renderSimplePage('MacroQuest Setup', macroquestData.lines)
end

categoryRenderers['4.0'] = function()
    renderSimplePage('EQ Built-In Macros', eqMacroLines)
end

categoryRenderers['5.0'] = function()
    renderSimplePage('Credits, AA, and Power Growth', aaGuideData.lines)
end

categoryRenderers['7.0'] = function()
    renderSimplePage('Ultimate Charm Path', swordData.lines)
end

categoryRenderers['8.0'] = function()
    renderSimplePage('Server Commands', commandsData.lines)
end

categoryRenderers['9.0'] = function()
    renderSimplePage('Ultimate Weapons and Gambling', epicsData.lines)
end

categoryRenderers['10.0'] = function()
    renderSimplePage('God Tier Leveling (71-75)', systems.lines)
end

categoryRenderers['12.0'] = function()
    renderSimplePage('Optional and Expedition Content', optionalContentLines)
end

categoryRenderers['14.0'] = function()
    renderSimplePage('Zone Access and Instances', zoneNamesData.lines)
end

categoryRenderers['23.0'] = function()
    categoryRenderers['11.0']()
end

categoryRenderers['THEMES'] = function()
    syncThemeColors()

    pushColor(colors.title)
    imgui.Text('Theme Selector')
    imgui.PopStyleColor()

    if not themeController then
        imgui.TextWrapped('Theme controller unavailable.')
        return
    end

    imgui.Separator()

    local themes = themeController.getThemes and themeController.getThemes() or {}
    local current = themeController.getCurrentTheme and themeController.getCurrentTheme() or 1

    pushColor(colors.section)
    imgui.Text('UI Themes')
    imgui.PopStyleColor()

    for i, th in ipairs(themes) do
        local name = th.name or ('Theme ' .. tostring(i))
        if imgui.Selectable(name, i == current) and themeController.setCurrentTheme then
            themeController.setCurrentTheme(i)
            syncThemeColors()
        end
    end

    imgui.Spacing()
    pushColor(colors.section)
    imgui.Text('Text Presets')
    imgui.PopStyleColor()

    local presets = themeController.getTextPresetNames and themeController.getTextPresetNames() or {}
    for _, presetName in ipairs(presets) do
        if imgui.SmallButton('Apply##' .. presetName) and themeController.applyTextPreset then
            themeController.applyTextPreset(presetName)
            syncThemeColors()
        end
        imgui.SameLine()
        imgui.Text(presetName)
    end

    if themeController.resetTextColors and imgui.Button('Reset Text Colors') then
        themeController.resetTextColors()
        syncThemeColors()
    end
end

local function registerFallbackRenderers()
    local groups = {
        progression.fundamentals,
        progression.progression_tiers,
        progression.optional_raids,
        progression.custom_systems,
    }

    for _, group in ipairs(groups) do
        for _, item in ipairs(group or {}) do
            if not categoryRenderers[item.id] then
                categoryRenderers[item.id] = function()
                    renderSimplePage(item.label, {
                        'Page not configured yet.',
                        'Add content in pro/content.lua renderer map.',
                    })
                end
            end
        end
    end
end

loadTierTracker()
registerFallbackRenderers()

function categoryRenderers.setThemeController(controller)
    themeController = controller
end

function categoryRenderers.getProgressStatus()
    return getProgressStatus()
end

function categoryRenderers.autoTrackByAction(action, targetText, tierId)
    return autoTrackByAction(action, targetText, tierId)
end

function categoryRenderers.markTierComplete(tierId)
    return markTierComplete(tierId)
end

return categoryRenderers
