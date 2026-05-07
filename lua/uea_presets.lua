-- UltimateEQ Assist preset loader: reads seeded profiles from
--   MacroQuest/config/UltimateEQAssist/Templates[/ImportedRG]/Level*/...
-- Same behavior as MQ Fresh MAUI UEA merge (solo/group/raid quick setup).

local function NormalizePath(path)
    return tostring(path or ''):gsub('\\', '/')
end

local function trimStr(s)
    if type(s) ~= 'string' then return '' end
    return (s:match('^%s*(.-)%s*$') or '')
end

local function cmdMemMySpells(iniFile)
    local s = tostring(iniFile or '')
    if s == '' then
        return
    end
    if not s:lower():match('%.ini$') then
        s = s .. '.ini'
    end
    s = s:gsub('\\', '/'):gsub('"', '')
    local payload = s:gsub(']', '')
    mq.cmd('/memmyspells ${Parse[0,' .. payload .. ']}')
end

--- First field of a MuleAssist pipe string (spell name before options).
local function firstPipeToken(raw, utils)
    if raw == nil or raw == 'NULL' then return nil end
    if type(raw) == 'number' then
        raw = tostring(raw)
    end
    if type(raw) ~= 'string' then
        return nil
    end
    local t = trimStr(utils.Split(raw, '|', 1)[1] or '')
    if t == '' or t:upper() == 'NULL' then
        return nil
    end
    if t:find('command:', 1, true) or t:find('${', 1, true) then
        return nil
    end
    return t
end

--- If the INI token names an EQ spell, use it for [MySpells]. Prefer RankName (what MuleAssist /memmyspells expects).
local function spellNameForMySpells(token, mq, SafeTLOCall)
    if not token or token == '' then
        return nil
    end
    local function try(t)
        if not t or t == '' then
            return nil
        end
        local sp = mq.TLO.Spell(t)
        if not sp() then
            return nil
        end
        local rank = SafeTLOCall(function()
            return sp.RankName()
        end, nil)
        if rank and rank ~= '' then
            return rank
        end
        return t
    end
    local name = try(token)
    if name then
        return name
    end
    -- INI may omit " Rk. II" etc.; strip and retry once.
    local stripped = token:gsub(' Rk%..*$', '')
    if stripped ~= token then
        return try(stripped)
    end
    return nil
end

--- Scan section keys (DPS1, Buffs3, …) when *Size is 0 or module is off but rows still exist in the INI.
local function inferListMaxIndexFromKeys(section, listKey, maxAllowed)
    if type(section) ~= 'table' then
        return 0
    end
    maxAllowed = maxAllowed or 99
    local maxIdx = 0
    local patt = '^' .. listKey .. '(%d+)$'
    for key, value in pairs(section) do
        local idx = tonumber(tostring(key):match(patt))
        if idx and idx >= 1 and idx <= maxAllowed then
            if type(value) == 'string' then
                local t = trimStr(value)
                if t ~= '' and t:upper() ~= 'NULL' and t ~= '0' then
                    maxIdx = math.max(maxIdx, idx)
                end
            elseif type(value) == 'number' and value ~= 0 then
                maxIdx = math.max(maxIdx, idx)
            end
        end
    end
    return maxIdx
end

--- Build gem order: [DPS] rows first (DPS1..), then every other section in schema order. Dedupe, cap 13.
local function collectSpellsForGems(cfg, schema, mq, utils, SafeTLOCall)
    local ordered = {}
    local seen = {}
    local skipSections = {MySpells = true, SpellSet = true, GMail = true, AFKTools = true}

    local function addRaw(raw)
        local first = firstPipeToken(raw, utils)
        if not first then
            return
        end
        local name = spellNameForMySpells(first, mq, SafeTLOCall)
        if not name then
            return
        end
        local key = name:lower()
        if seen[key] then
            return
        end
        seen[key] = true
        table.insert(ordered, name)
    end

    local function walkSectionProps(sectionName)
        if skipSections[sectionName] then
            return
        end
        local secSchema = schema[sectionName]
        local secCfg = cfg[sectionName]
        if type(secSchema) ~= 'table' or not secSchema.Properties or type(secCfg) ~= 'table' then
            return
        end
        for propKey, prop in pairs(secSchema.Properties) do
            if prop.Type == 'SPELL' then
                addRaw(secCfg[propKey])
            elseif prop.Type == 'LIST' then
                local maxSlots = tonumber(prop.Max) or 40
                local declared = tonumber(secCfg[propKey..'Size']) or 0
                local inferred = inferListMaxIndexFromKeys(secCfg, propKey, maxSlots)
                local size = math.min(maxSlots, math.max(declared, inferred))
                for idx = 1, size do
                    addRaw(secCfg[propKey..idx])
                end
            end
        end
    end

    -- DPS: always scan raw INI keys DPS1..DPSn (does not depend on schema; matches MuleAssist files).
    do
        local secCfg = cfg.DPS
        if type(secCfg) == 'table' then
            local maxSlots = 40
            local declared = tonumber(secCfg.DPSSize) or 0
            local inferred = inferListMaxIndexFromKeys(secCfg, 'DPS', maxSlots)
            local size = math.min(maxSlots, math.max(declared, inferred))
            for idx = 1, size do
                addRaw(secCfg['DPS' .. idx])
            end
        end
    end

    for _, sectionName in ipairs(schema.Sections or {}) do
        if sectionName ~= 'DPS' then
            walkSectionProps(sectionName)
        end
    end
    return ordered
end

local function fillMySpellsGems(cfg, names)
    cfg.MySpells = cfg.MySpells or {}
    local ms = cfg.MySpells
    for i = 1, 13 do
        ms['Gem'..i] = nil
    end
    local n = math.min(13, #names)
    for i = 1, n do
        ms['Gem'..i] = names[i]
    end
    return n
end

local function apply(presetName, ctx)
    local mq = ctx.mq
    local globals = ctx.globals
    local utils = ctx.utils
    local LIP = ctx.LIP
    local lfs = ctx.lfs
    local Save = ctx.Save
    local SafeTLOCall = ctx.SafeTLOCall
    local setBottomMsg = ctx.setBottomMsg or function() end

    local existingConfig = globals.Config

    local function MergeMissingConfig(targetCfg, sourceCfg)
        if type(targetCfg) ~= 'table' or type(sourceCfg) ~= 'table' then
            return
        end
        for sectionName, sectionData in pairs(sourceCfg) do
            if type(sectionData) == 'table' then
                if type(targetCfg[sectionName]) ~= 'table' then
                    targetCfg[sectionName] = {}
                end
                for key, value in pairs(sectionData) do
                    if targetCfg[sectionName][key] == nil then
                        targetCfg[sectionName][key] = value
                    end
                end
            elseif targetCfg[sectionName] == nil then
                targetCfg[sectionName] = sectionData
            end
        end
    end

    local function MergeMissingConfigFromExisting(cfg)
        if type(existingConfig) ~= 'table' or type(cfg) ~= 'table' then
            return
        end
        MergeMissingConfig(cfg, existingConfig)
    end

    local function EnsureActiveINIForCurrentCharacter()
        local levelName = globals.Schema['INI_PATTERNS']['level']:format(globals.MyServer, globals.MyName, globals.MyLevel)
        local noLevelName = globals.Schema['INI_PATTERNS']['nolevel']:format(globals.MyServer, globals.MyName)
        local expectedPrefix = ('MuleAssist_%s_%s'):format(globals.MyServer, globals.MyName)
        local active = tostring(globals.INIFile or '')
        if active == '' or not active:find(expectedPrefix, 1, true) then
            if utils.FileExists(mq.configDir..'/'..noLevelName) then
                globals.INIFile = noLevelName
            else
                globals.INIFile = levelName
            end
            return true
        end
        return false
    end

    local function GetOrderedLevelBuckets(levelNow, roots)
        local bucketSet = {}
        for _, root in ipairs(roots) do
            if lfs.attributes(root, 'mode') == 'directory' then
                for entry in lfs.dir(root) do
                    local lvl = tonumber(tostring(entry):match('^Level(%d+)$'))
                    if lvl then
                        bucketSet[lvl] = true
                    end
                end
            end
        end

        local buckets = {}
        for lvl in pairs(bucketSet) do
            table.insert(buckets, lvl)
        end
        table.sort(buckets)
        if #buckets == 0 then
            return buckets
        end

        local ordered = {}
        for i = #buckets, 1, -1 do
            if buckets[i] <= levelNow then
                table.insert(ordered, buckets[i])
            end
        end
        for i = 1, #buckets do
            if buckets[i] > levelNow then
                table.insert(ordered, buckets[i])
            end
        end
        return ordered
    end

    local function FindPresetTemplateFile(levelNow, classShort, presetUpper)
        local templatesRoot = NormalizePath(mq.configDir .. '/UltimateEQAssist/Templates')
        local importedRoot = NormalizePath(templatesRoot .. '/ImportedRG')
        local roots = {}
        if lfs.attributes(importedRoot, 'mode') == 'directory' then
            table.insert(roots, importedRoot)
        end
        if lfs.attributes(templatesRoot, 'mode') == 'directory' then
            table.insert(roots, templatesRoot)
        end
        if #roots == 0 then
            return nil
        end

        local orderedBuckets = GetOrderedLevelBuckets(levelNow, roots)
        for _, bucket in ipairs(orderedBuckets) do
            local prefix = string.format('UltimateEQAssist_L%d_%s_%s', bucket, classShort, presetUpper)
            local candidates = {
                string.format('%s/Level%d/KAHybrid/%s_KAHYBRID.ini', importedRoot, bucket, prefix),
                string.format('%s/Level%d/Presets/%s.ini', importedRoot, bucket, prefix),
                string.format('%s/Level%d/UltimateEQAssist_L%d_%s.ini', importedRoot, bucket, bucket, classShort),
                string.format('%s/Level%d/KAHybrid/%s_KAHYBRID.ini', templatesRoot, bucket, prefix),
                string.format('%s/Level%d/Presets/%s.ini', templatesRoot, bucket, prefix),
                string.format('%s/Level%d/UltimateEQAssist_L%d_%s.ini', templatesRoot, bucket, bucket, classShort),
                string.format('%s/UltimateEQAssist_%s.ini', templatesRoot, classShort),
            }
            for _, p in ipairs(candidates) do
                if utils.FileExists(p) then
                    return p, bucket
                end
            end
        end
        return nil
    end

    local function CountConfigSections(cfg)
        if type(cfg) ~= 'table' then
            return 0
        end
        local count = 0
        for _, sectionData in pairs(cfg) do
            if type(sectionData) == 'table' and next(sectionData) ~= nil then
                count = count + 1
            end
        end
        return count
    end

    local function FindRichClassTemplateFile(levelNow, classShort, presetUpper)
        local templatesRoot = NormalizePath(mq.configDir .. '/UltimateEQAssist/Templates')
        local importedRoot = NormalizePath(templatesRoot .. '/ImportedRG')
        local roots = {}
        if lfs.attributes(importedRoot, 'mode') == 'directory' then
            table.insert(roots, importedRoot)
        end
        if lfs.attributes(templatesRoot, 'mode') == 'directory' then
            table.insert(roots, templatesRoot)
        end
        if #roots == 0 then
            return nil, nil, 0
        end

        local bestPath, bestBucket, bestScore = nil, nil, 0
        local orderedBuckets = GetOrderedLevelBuckets(levelNow, roots)
        for _, bucket in ipairs(orderedBuckets) do
            local prefix = string.format('UltimateEQAssist_L%d_%s_%s', bucket, classShort, presetUpper)
            local candidates = {
                string.format('%s/Level%d/KAHybrid/%s_KAHYBRID.ini', importedRoot, bucket, prefix),
                string.format('%s/Level%d/Presets/%s.ini', importedRoot, bucket, prefix),
                string.format('%s/Level%d/UltimateEQAssist_L%d_%s.ini', importedRoot, bucket, bucket, classShort),
                string.format('%s/Level%d/KAHybrid/%s_KAHYBRID.ini', templatesRoot, bucket, prefix),
                string.format('%s/Level%d/Presets/%s.ini', templatesRoot, bucket, prefix),
                string.format('%s/Level%d/UltimateEQAssist_L%d_%s.ini', templatesRoot, bucket, bucket, classShort),
                string.format('%s/UltimateEQAssist_%s.ini', templatesRoot, classShort),
            }
            for _, p in ipairs(candidates) do
                if utils.FileExists(p) then
                    local cfg = LIP.load(p, false)
                    local score = CountConfigSections(cfg)
                    if not bestPath or score > bestScore or (score == bestScore and (not bestBucket or bucket > bestBucket)) then
                        bestPath, bestBucket, bestScore = p, bucket, score
                    end
                end
            end
        end
        return bestPath, bestBucket, bestScore
    end

    local function BuildFallbackCleanConfig()
        local cfg = {}
        for _, sectionName in ipairs(globals.Schema.Sections or {}) do cfg[sectionName] = {} end
        cfg.General = cfg.General or {}
        cfg.DPS = cfg.DPS or {}
        cfg.Buffs = cfg.Buffs or {}
        cfg.Heals = cfg.Heals or {}
        cfg.Cures = cfg.Cures or {}
        cfg.Pet = cfg.Pet or {}
        cfg.General.CharInfo = string.format('%s|%d|GOLD', tostring(SafeTLOCall(function() return mq.TLO.Me.Class.Name() end, 'Unknown')), tonumber(SafeTLOCall(function() return mq.TLO.Me.Level() end, globals.MyLevel) or globals.MyLevel) or 0)
        cfg.General.Role = 'Assist'
        cfg.General.MedOn, cfg.General.MedStart, cfg.General.SitToMed = 1, 20, 0
        cfg.General.AcceptInvitesOn, cfg.General.CastRetries, cfg.General.BuffWhileChasing = 1, 3, 1
        cfg.General.GroupWatchOn, cfg.General.EQBCOn, cfg.General.DanNetOn, cfg.General.DanNetDelay = 0, 0, 1, 20
        cfg.General.CampRadiusExceed, cfg.General.TwistOn, cfg.General.TwistWhat, cfg.General.TwistMed = 500, 0, '0', 0
        cfg.General.MeleeTwistOn, cfg.General.MeleeTwistWhat = 0, '0'
        cfg.General.LootOn, cfg.General.RezAcceptOn, cfg.General.CampfireOn, cfg.General.GroupEscapeOn, cfg.General.TravelOnHorse, cfg.General.CheerPeople = 0, '0|90', 0, 0, 0, 0
        cfg.DPS.DPSOn, cfg.DPS.DPSCOn, cfg.DPS.DPSSize, cfg.DPS.DPSInterval, cfg.DPS.DPSSkip = 1, 0, 0, 0, 1
        cfg.Heals.HealsOn, cfg.Heals.HealsCOn, cfg.Heals.HealsSize = 1, 0, 0
        cfg.Buffs.BuffsOn, cfg.Buffs.BuffsCOn, cfg.Buffs.BuffsSize = 1, 0, 0
        cfg.Cures.CuresOn, cfg.Cures.CuresCOn, cfg.Cures.CuresSize = 1, 0, 0
        cfg.Pet.PetOn, cfg.Pet.PetCombatOn, cfg.Pet.PetBuffsOn, cfg.Pet.PetToysOn = 0, 0, 0, 0
        return cfg
    end

    local function NormalizeLoadedTemplateIdentity(cfg)
        cfg.General = cfg.General or {}
        local className = tostring(SafeTLOCall(function() return mq.TLO.Me.Class.Name() end, globals.MyClass or 'Unknown') or 'Unknown')
        className = className:gsub('^%l', string.upper)
        local levelNow = tonumber(SafeTLOCall(function() return mq.TLO.Me.Level() end, globals.MyLevel) or globals.MyLevel) or (globals.MyLevel or 0)
        local currentCharInfo = tostring(cfg.General.CharInfo or '')
        local tier = currentCharInfo:match('^[^|]*|%d+|([^|]+)$') or 'GOLD'
        cfg.General.CharInfo = string.format('%s|%d|%s', className, levelNow, tier)
        cfg.General.Role = cfg.General.Role or 'Assist'
        if tostring(globals.MyClass or ''):lower() ~= 'brd' then
            cfg.General.TwistOn = 0
        end
    end

    local function ParseToggleValue(value)
        if type(value) == 'boolean' then return value end
        if type(value) == 'number' then return value ~= 0 end
        if type(value) == 'string' then
            local firstPart = utils.Split(value, '|', 1)[1] or value
            local numeric = tonumber(firstPart)
            if numeric ~= nil then
                return numeric ~= 0
            end
            local upper = firstPart:upper()
            return upper == 'TRUE' or upper == 'ON'
        end
        return false
    end

    local function ApplyModeDeltas(cfg)
        cfg.General = cfg.General or {}
        if presetName == 'Solo' then
            cfg.General.ChaseAssist = 0
            cfg.General.ReturnToCamp = 1
            cfg.General.CampRadius = cfg.General.CampRadius or 35
            cfg.General.ReturnToCampAccuracy = cfg.General.ReturnToCampAccuracy or 10
            cfg.General.ChaseDistance = cfg.General.ChaseDistance or 25
        elseif presetName == 'Raid' then
            cfg.General.ChaseAssist = 1
            cfg.General.ReturnToCamp = 0
            cfg.General.CampRadius = cfg.General.CampRadius or 30
            cfg.General.ChaseDistance = cfg.General.ChaseDistance or 35
            cfg.General.ReturnToCampAccuracy = cfg.General.ReturnToCampAccuracy or 10
        else
            cfg.General.ChaseAssist = 1
            cfg.General.ReturnToCamp = 0
            cfg.General.CampRadius = cfg.General.CampRadius or 30
            cfg.General.ChaseDistance = cfg.General.ChaseDistance or 25
            cfg.General.ReturnToCampAccuracy = cfg.General.ReturnToCampAccuracy or 10
        end
    end

    local function InferListSize(section, entryPrefix)
        local maxIndex = 0
        if type(section) ~= 'table' then return 0 end
        for key, value in pairs(section) do
            local idx = tonumber(tostring(key):match('^' .. entryPrefix .. '(%d+)$'))
            if idx and idx > 0 then
                local text = tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')
                if text ~= '' and text:upper() ~= 'NULL' and text ~= '0' then
                    if idx > maxIndex then
                        maxIndex = idx
                    end
                end
            end
        end
        return maxIndex
    end

    local function NormalizeEnabledModuleSizes(cfg)
        -- INI keys are DPS1, Buffs1, Heals1, Cures1 (same stem as LIST property name — not "Buff1"/"Heal1").
        local rules = {
            {section = 'DPS', onKey = 'DPSOn', cOnKey = 'DPSCOn', sizeKey = 'DPSSize', entryPrefix = 'DPS'},
            {section = 'Buffs', onKey = 'BuffsOn', cOnKey = 'BuffsCOn', sizeKey = 'BuffsSize', entryPrefix = 'Buffs'},
            {section = 'Heals', onKey = 'HealsOn', cOnKey = 'HealsCOn', sizeKey = 'HealsSize', entryPrefix = 'Heals'},
            {section = 'Cures', onKey = 'CuresOn', cOnKey = 'CuresCOn', sizeKey = 'CuresSize', entryPrefix = 'Cures'},
        }

        local inferredCount = 0
        local disabledCount = 0
        for _, rule in ipairs(rules) do
            cfg[rule.section] = cfg[rule.section] or {}
            local section = cfg[rule.section]
            if ParseToggleValue(section[rule.onKey]) then
                local currentSize = tonumber(section[rule.sizeKey]) or 0
                if currentSize <= 0 then
                    local inferredSize = InferListSize(section, rule.entryPrefix)
                    if inferredSize > 0 then
                        section[rule.sizeKey] = inferredSize
                        inferredCount = inferredCount + 1
                    else
                        section[rule.onKey] = 0
                        if section[rule.cOnKey] ~= nil then
                            section[rule.cOnKey] = 0
                        end
                        disabledCount = disabledCount + 1
                    end
                end
            end
        end
        return inferredCount, disabledCount
    end

    local switchedToCharINI = EnsureActiveINIForCurrentCharacter()
    local levelNow = tonumber(SafeTLOCall(function() return mq.TLO.Me.Level() end, globals.MyLevel) or globals.MyLevel) or (globals.MyLevel or 0)
    local classShort = tostring(globals.MyClass or ''):upper()
    local presetUpper = tostring(presetName or 'GROUP'):upper()
    local templatePath, bucket = FindPresetTemplateFile(levelNow, classShort, presetUpper)

    if templatePath then
        globals.Config = LIP.load(templatePath, false) or BuildFallbackCleanConfig()
        NormalizeLoadedTemplateIdentity(globals.Config)
    else
        globals.Config = BuildFallbackCleanConfig()
    end
    local richTemplatePath, _, richScore = FindRichClassTemplateFile(levelNow, classShort, presetUpper)
    if richTemplatePath and utils.FileExists(richTemplatePath) then
        local currentScore = CountConfigSections(globals.Config)
        if richScore > currentScore then
            local richCfg = LIP.load(richTemplatePath, false)
            MergeMissingConfig(globals.Config, richCfg)
        end
    end
    MergeMissingConfigFromExisting(globals.Config)
    ApplyModeDeltas(globals.Config)
    local inferredSizes, autoDisabled = NormalizeEnabledModuleSizes(globals.Config)

    -- Mini preset: always rebuild [MySpells] from spell tokens in DPS/Buffs/Heals/etc. (overwrite).
    -- Do not skip when old gems exist — merged INIs often leave junk and blocked fills before.
    local mySpellsGemCount = 0
    local mySpellsNote = ''
    local names = collectSpellsForGems(globals.Config, globals.Schema, mq, utils, SafeTLOCall)
    if #names > 0 then
        mySpellsGemCount = fillMySpellsGems(globals.Config, names)
        mySpellsNote = string.format(' [MySpells: filled %d gem(s) from INI spell refs; /memmyspells sent]', mySpellsGemCount)
    else
        mySpellsNote = ' [MySpells: no Spell() matches in DPS/etc. (discs/items use other slots)]'
    end

    Save()
    if globals.INIFile and globals.INIFile ~= '' then
        globals.INIFileContents = utils.ReadRawINIFile()
    end

    if mySpellsGemCount > 0 then
        local ini = tostring(globals.INIFile or '')
        if ini ~= '' and ini:sub(-string.len('.ini')) ~= '.ini' then
            ini = ini .. '.ini'
        end
        if ini ~= '' then
            -- Do not mq.delay here: apply() runs from ImGui (non-yieldable thread).
            cmdMemMySpells(ini)
        end
    end

    local normalizeNote = ''
    if inferredSizes > 0 or autoDisabled > 0 then
        normalizeNote = string.format(' [normalized sizes: +%d inferred, %d auto-disabled]', inferredSizes, autoDisabled)
    end

    if templatePath then
        local sourceKind = templatePath:find('/KAHybrid/', 1, true) and 'KAHybrid' or (templatePath:find('/Presets/', 1, true) and 'Preset' or 'Class')
        local fromLabel = string.format('L%d %s %s', tonumber(bucket or levelNow) or levelNow, classShort, sourceKind)
        if switchedToCharINI then
            setBottomMsg(string.format('Preset applied: %s from %s (switched to %s)%s%s', presetName, fromLabel, tostring(globals.INIFile), normalizeNote, mySpellsNote))
        else
            setBottomMsg(string.format('Preset applied: %s from %s%s%s', presetName, fromLabel, normalizeNote, mySpellsNote))
        end
    else
        setBottomMsg(string.format('Preset applied: %s (fallback baseline; no template under UltimateEQAssist/Templates)%s%s', presetName, normalizeNote, mySpellsNote))
    end
end

--- Called from init.lua ApplySetupPreset after template merge: fill Gem1.. from DPS/Buffs/Heals spell lines.
--- ctx: { globals = globals, mq = mq, utils = utils, SafeTLOCall = SafeTLOCall }
local function rebuildMySpellsGems(ctx)
    local g = ctx and ctx.globals
    if not g or type(g.Config) ~= 'table' or type(g.Schema) ~= 'table' then
        return 0
    end
    local names = collectSpellsForGems(g.Config, g.Schema, ctx.mq, ctx.utils, ctx.SafeTLOCall)
    if #names == 0 then
        return 0
    end
    return fillMySpellsGems(g.Config, names)
end

return { apply = apply, rebuildMySpellsGems = rebuildMySpellsGems }
