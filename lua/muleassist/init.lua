local mq = require('mq')

local SCRIPT_NAME = 'muleassist'
local TICK_MS = 75
local INFO_INI = 'KissAssist_Info.ini'

local state = {
    running = true,
    paused = false,
    role = 'assist',
    mainAssist = nil,
    iniFile = nil,
    config = {},
    lists = {},
    class = nil,
    classShort = nil,
    lastAssistAt = 0,
    lastDpsAt = 0,
    lastBuffAt = 0,
    lastHealAt = 0,
    lastBurnAt = 0,
    lastMezAt = 0,
    lastZoneID = 0,
    camp = {x = 0, y = 0, z = 0},
    navActive = false,
    debug = false,
    debugCast = false,
    buffMode = false,
    zombieMode = false,
    lastSpellCastAt = {},
    mapTheZone = false,
    lastMapPulseAt = 0,
    custom = { pending = false, name = nil, param = nil, lastAt = 0 },
    cast = {
        fizzled = false,
        interrupted = false,
        resisted = false,
    },
    pull = {
        lastAt = 0,
        lastID = 0,
        phase = 'IDLE',
        targetID = 0,
        pullWith = 'Melee',
        range = 12,
        startAt = 0,
        attempts = 0,
        startXT = 0,
        lastNavAt = 0,
        lastActionAt = 0,
        campX = 0,
        campY = 0,
        campZ = 0,
        lastTraceAt = 0,
        lastReason = 'init',
        chainPauseUntil = 0,
        chainNextPauseAt = 0,
    },
    pullRules = {
        all = true,
        allow = {},
        ignore = {},
        minLvl = 1,
        maxLvl = 200,
    },
    mezImmune = {},
}

local CLASS_CAPS = {
    WAR = {name='Warrior', healer=false, hybrid=false, rez=false, pet=false, canCast=false, burnAA={611, 912}},
    PAL = {name='Paladin', healer=true, hybrid=true, rez=true, pet=false, canCast=true, burnAA={520, 6001}},
    SHD = {name='Shadow Knight', healer=true, hybrid=true, rez=false, pet=true, canCast=true, burnAA={1267, 826}},
    MNK = {name='Monk', healer=false, hybrid=false, rez=false, pet=false, canCast=false, burnAA={1112, 1122}},
    ROG = {name='Rogue', healer=false, hybrid=false, rez=false, pet=false, canCast=false, burnAA={801, 1410}},
    RNG = {name='Ranger', healer=true, hybrid=true, rez=false, pet=false, canCast=true, burnAA={213, 864}},
    BER = {name='Berserker', healer=false, hybrid=false, rez=false, pet=false, canCast=false, burnAA={3000, 4000}},
    BRD = {name='Bard', healer=false, hybrid=true, rez=false, pet=false, canCast=true, burnAA={700, 701}},
    CLR = {name='Cleric', healer=true, hybrid=false, rez=true, pet=false, canCast=true, burnAA={215, 216}},
    DRU = {name='Druid', healer=true, hybrid=false, rez=true, pet=false, canCast=true, burnAA={740, 742}},
    SHM = {name='Shaman', healer=true, hybrid=false, rez=true, pet=true, canCast=true, burnAA={777, 778}},
    WIZ = {name='Wizard', healer=false, hybrid=false, rez=false, pet=false, canCast=true, burnAA={15073, 15074}},
    MAG = {name='Magician', healer=false, hybrid=false, rez=false, pet=true, canCast=true, burnAA={1215, 1216}},
    NEC = {name='Necromancer', healer=false, hybrid=false, rez=true, pet=true, canCast=true, burnAA={840, 843}},
    ENC = {name='Enchanter', healer=false, hybrid=false, rez=true, pet=true, canCast=true, burnAA={850, 851}},
    BST = {name='Beastlord', healer=true, hybrid=true, rez=false, pet=true, canCast=true, burnAA={1106, 1107}},
}

local CLASS_FALLBACK = {
    WAR = {burn={'Mighty Strike Discipline','Furious Discipline','Spire of the Warlord'}, dps={'Taunt','Kick','Bash'}},
    PAL = {burn={'Holyforge Discipline','Inquisitor\'s Judgment','Valorous Rage'}, dps={'Crush','Stun','Disruptive Persecution'}, heals={'Burst','Light','Remedy'}},
    SHD = {burn={'Leechcurse Discipline','Unholy Aura Discipline','Thought Leech'}, dps={'Spear','Touch','Terror'}, heals={'Touch','Leech'}},
    MNK = {burn={'Heel of Zagali','Speed Focus Discipline','Two-Finger Wasp Touch'}, dps={'Tiger Claw','Flying Kick','Dragon Punch'}},
    ROG = {burn={'Twisted Chance Discipline','Pinpoint Vulnerability','Rogue\'s Fury'}, dps={'Backstab','Knifeplay Discipline','Ligament Slice'}},
    RNG = {burn={'Auspice of the Hunter','Outrider\'s Accuracy','Guardian of the Forest'}, dps={'Summer','Winter','Focused Arrowrain'}, heals={'Salve','Mending','Sylvan'}},
    BER = {burn={'Mangling Discipline','Brutal Discipline','Juggernaut Surge'}, dps={'Frenzy','Disconcerting Discipline','Volley'}},
    BRD = {burn={'Quick Time','Fierce Eye','Funeral Dirge'}, dps={'Insult','Nuke','Chant'}},
    CLR = {burn={'Celestial Rapidity','Flurry of Life','Divine Avatar'}, dps={'Contravention','Smite'}, heals={'Remedy','Syllable','Elixir'}, buffs={'Symbol','Aegolism','Shining'}},
    DRU = {burn={'Spirit of the Wood','Spire of Nature','Nature\'s Boon'}, dps={'Remote','Sunflash','Nature\'s'}, heals={'Adrenaline','Survival','Luna'}, buffs={'Skin','Regen','Mask'}},
    SHM = {burn={'Ancestral Aid','Spire of Ancestors','Rabid Bear'}, dps={'Nectar','Bite','Chaotic Poison'}, heals={'Reckless','Mending','Renewal'}, buffs={'Talisman','Unity','Panther'}},
    WIZ = {burn={'Improved Twincast','Frenzied Devastation','Second Spire of Arcanum'}, dps={'Claw','Ethereal','Cloudburst'}},
    MAG = {burn={'Host of the Elements','Servant of Ro','Heart of Flames'}, dps={'Spear','Bolt','Shock'}, buffs={'Aegis','Burnout','Velocity'}},
    NEC = {burn={'Heretic\'s Twincast','Funeral Pyre','Wake the Dead'}, dps={'Pyre','Hemorrhagic','Ignite'}, buffs={'Lich','Shielding','Deadskin'}},
    ENC = {burn={'Calculated Insanity','Illusions of Grandeur','Third Spire of Enchantment'}, dps={'Mindslash','Chromatic','Strangulate'}, buffs={'Haste','Clarity','Rune'}},
    BST = {burn={'Bestial Alignment','Ruaabri\'s Fury','Savage Rage'}, dps={'Maul','Bite','Nuke'}, heals={'Salve','Mending','Rejuvenation'}, buffs={'Ferocity','Paragon','Spiritual'}},
}

local SECTION_KEYS = {
    General = {'Role','CampRadius','CampRadiusExceed','ReturnToCamp','ReturnToCampAccuracy','ChaseAssist','ChaseDistance','BuffWhileChasing','MedOn','MedStart','SitToMed','LootOn','RezAcceptOn','AcceptInvitesOn','GroupWatchOn','CastingInterruptOn','DanNetOn','DanNetDelay','MiscGem','MiscGemLW','MiscGemRemem','HoTTOn','CampfireOn','GroupEscapeOn','DPSMeter','Scatter','MoveCloserIfNoLOS','CheerPeople','CastRetries','TravelOnHorse'},
    DPS = {'DPSOn','DPSCOn','DPSSize','DPSSkip','DPSInterval','DebuffAllOn'},
    Buffs = {'BuffsOn','BuffsCOn','BuffsSize','RebuffOn','CheckBuffsTimer'},
    Heals = {'HealsOn','HealsCOn','HealsSize','InterruptHeals','AutoRezOn','AutoRezWith','HealGroupPetsOn','XTarHeal'},
    Cures = {'CuresOn','CuresSize'},
    Mez = {'MezOn','MezRadius','MezMinLevel','MezMaxLevel','MezStopHPs','MezSpell','MezAESpell'},
    Burn = {'BurnOn','BurnCOn','BurnSize','BurnText','BurnAllNamed','UseTribute'},
    Aggro = {'AggroOn','AggroCOn','AggroSize'},
    OhShit = {'OhShitOn','OhShitCOn','OhShitSize'},
    AE = {'AEOn','AESize','AERadius'},
    Pull = {'PullRoleToggle','PullWith','PullMeleeStick','MaxRadius','MaxZRange','CheckForMemblurredMobsInCamp','PullWait','ChainPull','ChainPullHP','ChainPullPause','PullLevel','PullArcWidth','PullNamedsFirst','ActNatural','UseCalm','CalmWith','GrabDeadGroupMembers','PullPath','PullTwistOn'},
    Pet = {'PetOn','PetSpell','PetBuffsOn','PetBuffsSize','PetCombatOn','PetAssistAt','PetToysOn','PetToysSize'},
    GoM = {'GoMOn','GoMCOn','GoMSize'},
    Melee = {'MeleeOn','AssistAt','MeleeDistance','FaceMobOn','StickHow','UseMQ2Melee','AutoFireOn','MeleeTwistOn','MeleeTwistWhat'},
}

local LIST_DEFS = {
    DPS = {section='DPS', prefix='DPS', size='DPSSize', cond='DPSCond'},
    Buffs = {section='Buffs', prefix='Buffs', size='BuffsSize', cond='BuffsCond'},
    Heals = {section='Heals', prefix='Heals', size='HealsSize', cond='HealsCond'},
    Cures = {section='Cures', prefix='Cures', size='CuresSize'},
    Burn = {section='Burn', prefix='Burn', size='BurnSize', cond='BurnCond'},
    Aggro = {section='Aggro', prefix='Aggro', size='AggroSize', cond='AggroCond'},
    OhShit = {section='OhShit', prefix='OhShit', size='OhShitSize', cond='OhShitCond'},
    AE = {section='AE', prefix='AE', size='AESize'},
    GoM = {section='GoM', prefix='GoM', size='GoMSize', cond='GoMCond'},
    PetBuffs = {section='Pet', prefix='PetBuffs', size='PetBuffsSize'},
    PetToys = {section='Pet', prefix='PetToys', size='PetToysSize'},
}

local function nowMs()
    return mq.gettime()
end

local function log(fmt, ...)
    print(string.format('[MuleAssistLua] '..fmt, ...))
end

local function tloSafe(fn, default)
    local ok, result = pcall(fn)
    if ok and result ~= nil then return result end
    return default
end

local function boolish(v)
    if v == nil then return false end
    local s = tostring(v):lower()
    return s == 'true' or s == '1' or s == 'on' or s == 'yes'
end

local function split(input, sep)
    local out = {}
    if not input then return out end
    sep = sep or '|'
    local pattern = string.format('([^%s]+)', sep:gsub('%%', '%%%%'))
    for part in tostring(input):gmatch(pattern) do
        out[#out+1] = part:gsub('^%s+', ''):gsub('%s+$', '')
    end
    return out
end

local function parseNumber(v, default)
    local n = tonumber(v)
    if n == nil then return default end
    return n
end

local function sanitizeIniPath(path)
    local p = tostring(path or '')
    if p:match('%.ini$') then return p end
    return p .. '.ini'
end

local function getIni(section, key, default)
    local val = tloSafe(function() return mq.TLO.Ini(state.iniFile, section, key)() end, nil)
    if val == nil or val == '' or tostring(val) == 'NULL' then return default end
    return val
end

local function writeIni(section, key, value)
    local ok = pcall(function()
        mq.cmdf('/ini "%s" "%s" "%s" "%s"', state.iniFile, section, key, tostring(value))
    end)
    return ok
end

local function iniGet(pathOrName, section, key, default)
    local iniPath = tostring(pathOrName or '')
    if iniPath == '' then iniPath = state.iniFile end
    if not iniPath:find('[\\/]') then
        iniPath = string.format('%s/%s', mq.configDir, iniPath)
    end
    if not iniPath:match('%.ini$') then iniPath = iniPath .. '.ini' end
    local val = tloSafe(function() return mq.TLO.Ini(iniPath, section, key)() end, nil)
    if val == nil or val == '' or tostring(val) == 'NULL' then return default end
    return val
end

local function findIniFile()
    local server = tloSafe(function() return mq.TLO.EverQuest.Server() end, '')
    local name = tloSafe(function() return mq.TLO.Me.CleanName() end, '')
    local level = tloSafe(function() return mq.TLO.Me.Level() end, 1)
    local a = string.format('MuleAssist_%s_%s.ini', server, name)
    local b = string.format('MuleAssist_%s_%s_%d.ini', server, name, level)
    local pathA = string.format('%s/%s', mq.configDir, a)
    local pathB = string.format('%s/%s', mq.configDir, b)
    if tloSafe(function() return mq.TLO.Ini(pathA, 'General', 'Role')() ~= nil end, false) then return pathA end
    if tloSafe(function() return mq.TLO.Ini(pathB, 'General', 'Role')() ~= nil end, false) then return pathB end
    return pathB
end

local function evalCond(expr)
    if not expr or expr == '' or expr == 'TRUE' then return true end
    local ok, out = pcall(mq.parse, expr)
    if not ok then return false end
    local s = tostring(out):lower()
    return s ~= 'false' and s ~= '0' and s ~= '' and s ~= 'nil'
end

local function parseListValue(raw)
    local parts = split(raw, '|')
    return {
        raw = raw,
        ability = parts[1],
        options = parts,
    }
end

local function loadConfig()
    state.config = {}
    state.lists = {}

    -- Load full INI content first so legacy MuleAssist keys not listed in SECTION_KEYS are still available.
    local iniPath = tostring(state.iniFile or '')
    if iniPath ~= '' then
        local f = io.open(iniPath, 'r')
        if f then
            local curSection = nil
            for line in f:lines() do
                local s = tostring(line or ''):gsub('^%s+', ''):gsub('%s+$', '')
                if s ~= '' and not s:match('^;') then
                    local sec = s:match('^%[(.+)%]$')
                    if sec then
                        curSection = sec
                        if not state.config[curSection] then state.config[curSection] = {} end
                    elseif curSection then
                        local k, v = s:match('^([^=]+)=(.*)$')
                        if k and v then
                            k = tostring(k):gsub('^%s+', ''):gsub('%s+$', '')
                            v = tostring(v):gsub('^%s+', ''):gsub('%s+$', '')
                            state.config[curSection][k] = v
                        end
                    end
                end
            end
            f:close()
        end
    end

    for section, keys in pairs(SECTION_KEYS) do
        if not state.config[section] then state.config[section] = {} end
        for _, key in ipairs(keys) do
            local val = getIni(section, key, nil)
            if val ~= nil then state.config[section][key] = val end
        end
    end

    for listName, def in pairs(LIST_DEFS) do
        local arr = {}
        local size = parseNumber(getIni(def.section, def.size, '0'), 0)
        for i = 1, size do
            local key = string.format('%s%d', def.prefix, i)
            local raw = getIni(def.section, key, nil)
            if raw and raw ~= 'NULL' and raw ~= '' then
                local cond = def.cond and getIni(def.section, string.format('%s%d', def.cond, i), 'TRUE') or 'TRUE'
                arr[#arr+1] = {
                    index = i,
                    value = parseListValue(raw),
                    cond = cond,
                }
            end
        end
        state.lists[listName] = arr
    end

    local iniRole = tostring(state.config.General.Role or state.role or 'assist'):lower()
    state.role = iniRole

    local function csvSet(v)
        local set = {}
        for _, part in ipairs(split(v or '', ',')) do
            local key = tostring(part or ''):gsub('^%s+', ''):gsub('%s+$', ''):lower()
            if key ~= '' then set[key] = true end
        end
        return set
    end
    local zoneKey = tloSafe(function() return mq.TLO.Zone.ShortName() end, 'UnknownZone')
    local infoPath = string.format('%s/%s', mq.configDir, INFO_INI)
    local allowRaw = tostring(iniGet(infoPath, zoneKey, 'MobsToPull', 'ALL') or 'ALL')
    local ignoreRaw = tostring(iniGet(infoPath, zoneKey, 'MobsToIgnore', 'NULL') or 'NULL')
    local mezImmuneRaw = tostring(iniGet(infoPath, zoneKey, 'MezImmune', 'NULL') or 'NULL')
    local pullLevelRaw = tostring((state.config.Pull and state.config.Pull.PullLevel) or '0|0')
    local allowLower = allowRaw:lower()
    state.pullRules.all = (allowLower == 'all' or allowLower == 'all for all mobs' or allowLower == 'null' or allowLower == '')
    state.pullRules.allow = state.pullRules.all and {} or csvSet(allowRaw)
    state.pullRules.ignore = csvSet(ignoreRaw)
    state.mezImmune = csvSet(mezImmuneRaw)
    local pl = pullLevelRaw:lower()
    if pl == 'auto' then
        local lvl = parseNumber(tloSafe(function() return mq.TLO.Me.Level() end, 1), 1)
        state.pullRules.minLvl = math.max(1, lvl - 5)
        state.pullRules.maxLvl = math.max(state.pullRules.minLvl, lvl + 2)
    elseif pl:find('|', 1, true) then
        local a = split(pl, '|')
        local minV = parseNumber(a[1], 0) or 0
        local maxV = parseNumber(a[2], 0) or 0
        if minV <= 0 and maxV <= 0 then
            -- Macro semantics: 0|0 means no pull-level restriction.
            state.pullRules.minLvl = 1
            state.pullRules.maxLvl = 200
        else
            if minV <= 0 then minV = 1 end
            if maxV <= 0 then maxV = 200 end
            if maxV < minV then maxV = minV end
            state.pullRules.minLvl = minV
            state.pullRules.maxLvl = maxV
        end
    elseif (parseNumber(pl, 0) or 0) <= 0 then
        state.pullRules.minLvl = 1
        state.pullRules.maxLvl = 200
    else
        state.pullRules.minLvl = 1
        state.pullRules.maxLvl = 200
    end
end

local function findSectionForKey(keyName)
    for section, keys in pairs(SECTION_KEYS) do
        for _, key in ipairs(keys) do
            if tostring(key):lower() == tostring(keyName):lower() then
                return section, key
            end
        end
    end
    for section, kv in pairs(state.config or {}) do
        if type(kv) == 'table' then
            for k, _ in pairs(kv) do
                if tostring(k):lower() == tostring(keyName):lower() then
                    return section, k
                end
            end
        end
    end
    return nil, nil
end

local function setConfigValue(section, key, value)
    section = tostring(section or '')
    key = tostring(key or '')
    if section == '' or key == '' then return false end
    if not state.config[section] then state.config[section] = {} end
    state.config[section][key] = value
    writeIni(section, key, value)
    return true
end

local function toggleConfigKey(keyName, explicit)
    local section, key = findSectionForKey(keyName)
    if not section then return false end
    local cur = boolish(state.config[section][key])
    local nv = explicit
    if nv == nil then nv = not cur end
    setConfigValue(section, key, nv and 1 or 0)
    return true
end

local function distance3d(x1, y1, z1, x2, y2, z2)
    local dx, dy, dz = (x1 - x2), (y1 - y2), (z1 - z2)
    return math.sqrt((dx * dx) + (dy * dy) + (dz * dz))
end

local function setCampHere()
    state.camp.x = parseNumber(tloSafe(function() return mq.TLO.Me.X() end, 0), 0)
    state.camp.y = parseNumber(tloSafe(function() return mq.TLO.Me.Y() end, 0), 0)
    state.camp.z = parseNumber(tloSafe(function() return mq.TLO.Me.Z() end, 0), 0)
end

local function writeCurrentGemsToIni(pathOrName)
    local iniPath = tostring(pathOrName or state.iniFile or '')
    if iniPath == '' then return false end
    if not iniPath:find('[\\/]') then
        iniPath = string.format('%s/%s', mq.configDir, iniPath)
    end
    if not iniPath:match('%.ini$') then iniPath = iniPath .. '.ini' end
    for i = 1, 13 do
        local gemName = tloSafe(function() return mq.TLO.Me.Gem(i).Name() end, nil)
        if gemName and gemName ~= '' then
            pcall(function()
                mq.cmdf('/ini "%s" "MySpells" "Gem%d" "%s"', iniPath, i, gemName)
            end)
        else
            pcall(function()
                mq.cmdf('/ini "%s" "MySpells" "Gem%d" "NULL"', iniPath, i)
            end)
        end
    end
    return true
end

local function memMySpells(pathOrName)
    local iniPath = tostring(pathOrName or state.iniFile or '')
    if iniPath == '' then return false end
    if not iniPath:find('[\\/]') then
        iniPath = string.format('%s/%s', mq.configDir, iniPath)
    end
    if not iniPath:match('%.ini$') then iniPath = iniPath .. '.ini' end
    local memmed = 0
    for i = 1, 13 do
        local spellName = iniGet(iniPath, 'MySpells', string.format('Gem%d', i), nil)
        if spellName and spellName ~= '' and spellName ~= 'NULL' and spellName ~= '0' then
            local rankName = tloSafe(function() return mq.TLO.Spell(spellName).RankName() end, nil) or spellName
            local ok = pcall(function()
                mq.cmdf('/memspell %d "%s"', i, rankName)
            end)
            if ok then
                memmed = memmed + 1
                mq.delay(1200, function()
                    local g = mq.TLO.Me.Gem(i).Name()
                    return g and tostring(g):lower() == tostring(rankName):lower()
                end)
            end
        end
    end
    pcall(function() mq.TLO.Window('SpellBookWnd').DoClose() end)
    log('MemMySpells loaded %d gems from %s', memmed, iniPath)
    return memmed > 0
end

local function resetCastFlags()
    state.cast.fizzled = false
    state.cast.interrupted = false
    state.cast.resisted = false
    state.cast.failed = false
    state.cast.success = false
end

mq.event('MA_Fizzle', '#*#Your #1# spell fizzles#*#', function() state.cast.fizzled = true end)
mq.event('MA_Fizzle2', '#*#Your spell fizzles#*#', function() state.cast.fizzled = true end)
mq.event('MA_Interrupt', '#*#Your spell is interrupted.#*#', function() state.cast.interrupted = true end)
mq.event('MA_Interrupt2', '#*#Your casting has been interrupted#*#', function() state.cast.interrupted = true end)
mq.event('MA_Interrupt3', '#*#Your #1# spell is interrupted#*#', function() state.cast.interrupted = true end)
mq.event('MA_Resist', '#*#resisted the #1# spell#*#', function() state.cast.resisted = true end)
mq.event('MA_Resist2', '#*#Your target resisted the #1# spell#*#', function() state.cast.resisted = true end)
mq.event('MA_CantSee', '#*#You cannot see your target#*#', function() state.cast.interrupted = true end)
mq.event('MA_TooFar', '#*#Your target is too far away#*#', function() state.cast.interrupted = true end)
mq.event('MA_CastFail', '#*#spell did not take hold#*#', function() state.cast.failed = true end)
mq.event('MA_CastSuccess', '#*#Your #1# spell#*#', function() state.cast.success = true end)
local function bindSafe(cmd, fn)
    local ok, err = pcall(function() mq.bind(cmd, fn) end)
    if ok then return true end
    local msg = tostring(err or '')
    if msg:lower():find('already bound', 1, true) then
        -- Another script/plugin owns this bind. Skip silently to avoid startup spam.
        return false
    end
    log('Bind failed %s: %s', tostring(cmd), msg)
    return false
end

local function unbindSafe(cmd)
    pcall(function() mq.unbind(cmd) end)
end

local function findGemBySpellName(spellName)
    if not spellName then return nil end
    local target = tostring(spellName):lower()
    for i = 1, 13 do
        local gem = tloSafe(function() return mq.TLO.Me.Gem(i)() end, nil)
        if gem and gem ~= '' then
            local g = tostring(gem):lower()
            if g == target or g:find(target, 1, true) then
                return i
            end
        end
    end
    return nil
end

local function targetByID(id)
    if not id then return false end
    local ok = pcall(function() mq.cmdf('/squelch /tar id %d', id) end)
    if not ok then return false end
    mq.delay(300, function() return mq.TLO.Target.ID() == id end)
    return mq.TLO.Target.ID() == id
end

local function spellByName(spellName)
    local s = tloSafe(function() return mq.TLO.Spell(spellName) end, nil)
    if not s or not s() then return nil end
    return s
end

local function spellInBook(spellName)
    return tloSafe(function() return (mq.TLO.Me.Book(spellName)() or 0) > 0 end, false)
end

local function spellCastCheck(spellName, allowMove)
    local spell = spellByName(spellName)
    if not spell then return false end
    local me = mq.TLO.Me
    local castWindowClosed = not (me.Casting() or mq.TLO.Window('CastingWindow').Open())
    local movingCheck = allowMove or not (me.Moving() and (spell.MyCastTime() or 0) > 0)
    local manaCheck = (spell.Mana() or 0) == 0 or (me.CurrentMana() or 0) >= (spell.Mana() or 0)
    local endCheck = (spell.EnduranceCost() or 0) == 0 or (me.CurrentEndurance() or 0) >= (spell.EnduranceCost() or 0)
    local controlCheck = not (me.Stunned() or me.Feared() or me.Charmed() or me.Mezzed())
    return castWindowClosed and movingCheck and manaCheck and endCheck and controlCheck
end

local function memorizeSpell(gem, spellName, waitReady, maxWaitMs)
    if not gem or gem < 1 then return false end
    if not spellName or spellName == '' then return false end
    maxWaitMs = maxWaitMs or 25000
    local rankName = tloSafe(function() return mq.TLO.Spell(spellName).RankName() end, nil) or spellName
    local castWindowOpen = tloSafe(function() return mq.TLO.Window('CastingWindow').Open() end, false)
    if castWindowOpen or mq.TLO.Me.Casting() then return false end
    local ok = pcall(function() mq.cmdf('/memspell %d "%s"', gem, rankName) end)
    if not ok then return false end
    local start = nowMs()
    while nowMs() - start < maxWaitMs do
        local loaded = tloSafe(function() return mq.TLO.Me.Gem(gem).Name() end, nil)
        local matches = loaded and tostring(loaded):lower() == tostring(rankName):lower()
        if matches then
            if not waitReady then
                pcall(function() mq.TLO.Window('SpellBookWnd').DoClose() end)
                return true
            end
            if tloSafe(function() return mq.TLO.Me.SpellReady(gem)() end, false) then
                pcall(function() mq.TLO.Window('SpellBookWnd').DoClose() end)
                return true
            end
        end
        if getHostileNearby(60) > 0 then return false end
        mq.doevents()
        mq.delay(20)
    end
    pcall(function() mq.TLO.Window('SpellBookWnd').DoClose() end)
    return false
end

local function waitCastReadyGem(gem, maxWaitMs)
    maxWaitMs = maxWaitMs or 5000
    local start = nowMs()
    while nowMs() - start < maxWaitMs do
        if tloSafe(function() return mq.TLO.Me.SpellReady(gem)() end, false) then
            mq.delay(math.max(20, parseNumber(tloSafe(function() return mq.TLO.EverQuest.Ping() end, 100), 100)))
            return true
        end
        if getHostileNearby(60) > 0 then return false end
        mq.doevents()
        mq.delay(10)
    end
    return false
end

local function waitCastFinish(targetID, spellRange, allowDead)
    local maxWaitOrig = parseNumber(tloSafe(function() return mq.TLO.Me.Casting.MyCastTime() end, 0), 0) + ((parseNumber(tloSafe(function() return mq.TLO.EverQuest.Ping() end, 100), 100) * 20) + 1000)
    if maxWaitOrig < 1500 then maxWaitOrig = 1500 end
    local start = nowMs()
    while mq.TLO.Me.Casting() do
        mq.delay(20)
        mq.doevents()
        if targetID and targetID > 0 then
            local t = mq.TLO.Spawn(targetID)
            if (not allowDead) and (not t() or t.Dead()) then
                pcall(function() mq.TLO.Me.StopCast() end)
                return false, 'target_dead'
            end
            local curTarget = parseNumber(tloSafe(function() return mq.TLO.Target.ID() end, 0), 0)
            if curTarget > 0 and curTarget ~= targetID then
                pcall(function() mq.TLO.Me.StopCast() end)
                return false, 'target_changed'
            end
            if spellRange and spellRange > 0 then
                local d = parseNumber(tloSafe(function() return t.Distance3D() end, 0), 0)
                if d > (spellRange * 1.10) then
                    pcall(function() mq.TLO.Me.StopCast() end)
                    return false, 'out_of_range'
                end
            end
        end
        if nowMs() - start > maxWaitOrig then
            pcall(function() mq.TLO.Me.StopCast() end)
            return false, 'timeout'
        end
    end
    return true, 'done'
end

local function castGem(gem, targetID, retries)
    retries = retries or parseNumber(state.config.General.CastRetries, 3)
    local spellName = tloSafe(function() return mq.TLO.Me.Gem(gem).Name() end, nil)
    local spell = spellName and spellByName(spellName) or nil
    local spellRange = spell and parseNumber(spell.MyRange(), 0) or 0
    if spellRange <= 0 and spell then spellRange = parseNumber(spell.AERange(), 0) end
    if spellRange <= 0 then spellRange = 250 end
    for _ = 1, retries do
        resetCastFlags()
        local skipAttempt = false
        if not waitCastReadyGem(gem, 6000) then
            mq.delay(50)
            skipAttempt = true
        end
        if (not skipAttempt) and targetID and targetID > 0 and mq.TLO.Target.ID() ~= targetID then
            if not targetByID(targetID) then
                skipAttempt = true
            end
        end
        if (not skipAttempt) and spellName and not spellCastCheck(spellName, false) then
            skipAttempt = true
        end
        if not skipAttempt then
            local ok = pcall(function() mq.cmdf('/cast %d', gem) end)
            if not ok then
                mq.delay(100)
            else
                mq.delay(1200, function() return mq.TLO.Me.Casting() or (mq.TLO.Me.CastTimeLeft() or 0) > 0 or state.cast.fizzled or state.cast.interrupted or state.cast.resisted or state.cast.failed end)
                local _, finishReason = waitCastFinish(targetID, spellRange, false)
                if state.cast.resisted then return false, 'resisted' end
                if state.cast.fizzled or state.cast.interrupted then
                    mq.delay(200)
                elseif state.cast.failed then
                    mq.delay(150)
                elseif finishReason ~= 'done' then
                    mq.delay(100)
                else
                    return true, 'ok'
                end
            end
        end
    end
    return false, 'failed'
end

local function canUseAA(aaid)
    if not aaid then return false end
    return tloSafe(function() return mq.TLO.Me.AltAbilityReady(aaid)() end, false)
end

local function castAbility(abilityName, targetID, critical)
    if not abilityName or abilityName == '' or abilityName == 'NULL' then return false end
    local ability = tostring(abilityName)
    local lockKey = string.format('%s:%s', ability:lower(), tostring(targetID or 0))
    local lastCast = state.lastSpellCastAt[lockKey] or 0
    if nowMs() - lastCast < 400 then return false end
    local pctMana = tloSafe(function() return mq.TLO.Me.PctMana() end, 100)
    local medStart = parseNumber(state.config.General.MedStart, 20)
    if not critical and pctMana < medStart then return false end

    if ability:sub(1, 1) == '/' then
        local ok = pcall(function() mq.cmd(ability) end)
        if ok then state.lastSpellCastAt[lockKey] = nowMs() end
        return ok
    end

    local discReady = tloSafe(function() return mq.TLO.Me.CombatAbilityReady(ability)() end, false)
    if discReady then
        if mq.TLO.Me.Casting() or mq.TLO.Window('CastingWindow').Open() then return false end
        local ok = pcall(function() mq.cmdf('/disc %s', ability) end)
        if ok then
            state.lastSpellCastAt[lockKey] = nowMs()
            mq.delay(150)
            return true
        end
    end

    local aaid = tonumber(ability)
    local aaReadyByName = tloSafe(function() return mq.TLO.Me.AltAbilityReady(ability)() end, false)
    if not aaid then
        aaid = tloSafe(function() return mq.TLO.Me.AltAbility(ability).ID() end, nil)
    end
    if (aaid and canUseAA(aaid)) or aaReadyByName then
        if mq.TLO.Me.Casting() or mq.TLO.Window('CastingWindow').Open() then return false end
        local ok
        if aaid then
            ok = pcall(function() mq.cmdf('/alt activate %d', aaid) end)
        else
            ok = pcall(function() mq.cmdf('/alt activate "%s"', ability) end)
        end
        if ok then
            state.lastSpellCastAt[lockKey] = nowMs()
            mq.delay(150)
            return true
        end
    end

    local gem = findGemBySpellName(ability)
    local memorizedHere = false
    local prevGemSpell = nil
    if not gem and spellInBook(ability) then
        local inCombat = boolish(tloSafe(function() return mq.TLO.Me.InCombat() end, false))
        if (not inCombat) or critical then
            local miscGem = parseNumber(state.config.General.MiscGem, 8)
            if miscGem < 1 then miscGem = 8 end
            prevGemSpell = tloSafe(function() return mq.TLO.Me.Gem(miscGem).Name() end, nil)
            if memorizeSpell(miscGem, ability, true, 25000) then
                gem = miscGem
                memorizedHere = true
            end
        end
    end
    if gem then
        local ok = castGem(gem, targetID, parseNumber(state.config.General.CastRetries, 3))
        if ok then state.lastSpellCastAt[lockKey] = nowMs() end
        if memorizedHere and boolish(state.config.General.MiscGemRemem) and prevGemSpell and prevGemSpell ~= '' and prevGemSpell ~= ability then
            memorizeSpell(gem, prevGemSpell, false, 18000)
        end
        return ok
    end

    return false
end

local function targetIsUsable()
    return mq.TLO.Target.ID() and mq.TLO.Target.ID() > 0 and not mq.TLO.Target.Dead()
end

local function assistMAIfNeeded()
    local now = nowMs()
    if now - state.lastAssistAt < 800 then return end
    if state.role == 'tank' or state.role == 'puller' or state.role == 'pullertank' then return end
    local ma = state.mainAssist or tloSafe(function() return mq.TLO.Group.MainAssist.Name() end, nil)
    if not ma or ma == '' then return end
    if targetIsUsable() then return end
    state.lastAssistAt = now
    pcall(function() mq.cmdf('/assist %s', ma) end)
end

local function navigateToSpawn(spawnID)
    if not spawnID or spawnID < 1 then return false end
    local ok = pcall(function() mq.cmdf('/squelch /nav id %d', spawnID) end)
    if ok then state.navActive = true end
    return ok
end

local function navigateToCamp()
    local ok = pcall(function()
        mq.cmdf('/squelch /nav locyxz %.2f %.2f %.2f', state.camp.y, state.camp.x, state.camp.z)
    end)
    if ok then state.navActive = true end
    return ok
end

local function stopNavigation()
    if state.navActive then
        pcall(function() mq.cmd('/squelch /nav stop') end)
        state.navActive = false
    end
end

local function waitNavStart(maxWaitMs)
    maxWaitMs = maxWaitMs or 5000
    local start = nowMs()
    while nowMs() - start < maxWaitMs do
        if boolish(tloSafe(function() return mq.TLO.Navigation.Active() end, false)) then
            state.navActive = true
            return true
        end
        mq.doevents()
        mq.delay(20)
    end
    return false
end

local function waitNavStop(maxWaitMs)
    maxWaitMs = maxWaitMs or 40000
    local start = nowMs()
    while nowMs() - start < maxWaitMs do
        if not boolish(tloSafe(function() return mq.TLO.Navigation.Active() end, false)) then
            state.navActive = false
            return true
        end
        mq.doevents()
        mq.delay(20)
    end
    return false
end

local function getHostileNearby(radius)
    local count = tloSafe(function() return mq.TLO.SpawnCount(string.format('npc radius %d zradius 50', radius or 50))() end, 0)
    return count or 0
end

local function getXTHaterCount()
    local cnt = 0
    local n = parseNumber(tloSafe(function() return mq.TLO.Me.XTarget() end, 0), 0)
    for i = 1, n do
        local xt = mq.TLO.Me.XTarget(i)
        if xt() and tostring(xt.Type() or ''):lower() == 'npc' and not boolish(xt.Dead()) then
            cnt = cnt + 1
        end
    end
    return cnt
end

local function getFirstXTargetNPCID()
    local n = parseNumber(tloSafe(function() return mq.TLO.Me.XTarget() end, 0), 0)
    for i = 1, n do
        local xt = mq.TLO.Me.XTarget(i)
        if xt() and tostring(xt.Type() or ''):lower() == 'npc' and not boolish(xt.Dead()) then
            local sid = parseNumber(tloSafe(function() return xt.ID() end, 0), 0)
            if sid > 0 then return sid end
        end
    end
    return 0
end

local function getBestXTargetNPCID(preferLoS)
    local bestID = 0
    local bestDist = 999999
    local n = parseNumber(tloSafe(function() return mq.TLO.Me.XTarget() end, 0), 0)
    for i = 1, n do
        local xt = mq.TLO.Me.XTarget(i)
        if xt() and tostring(xt.Type() or ''):lower() == 'npc' and not boolish(xt.Dead()) then
            local sid = parseNumber(tloSafe(function() return xt.ID() end, 0), 0)
            local dist = parseNumber(tloSafe(function() return xt.Distance3D() end, 999999), 999999)
            if sid > 0 then
                if dist < bestDist then
                    bestDist = dist
                    bestID = sid
                end
            end
        end
    end
    return bestID
end

local function acquireCombatTargetFromXT(forceSwitch)
    local curUsable = targetIsUsable()
    local curLOS = boolish(tloSafe(function() return mq.TLO.Target.LineOfSight() end, true))
    if curUsable and not forceSwitch and curLOS then return true end

    local sid = getBestXTargetNPCID(true)
    if sid < 1 then sid = getBestXTargetNPCID(false) end
    if sid < 1 then sid = getFirstXTargetNPCID() end
    if sid > 0 then
        local curID = parseNumber(tloSafe(function() return mq.TLO.Target.ID() end, 0), 0)
        if forceSwitch or curID ~= sid or not curLOS then
            return targetByID(sid)
        end
        return true
    end
    return false
end

local function pullAbilityRange(pullWith)
    local pw = tostring(pullWith or 'Melee'):lower()
    if pw == 'melee' or pw == 'autoattack' then return 12 end
    if pw == 'ranged' then
        local r = parseNumber(tloSafe(function() return mq.TLO.Me.Inventory('ranged').Range() end, 0), 0)
        local rt = tostring(tloSafe(function() return mq.TLO.Me.Inventory('ranged').Type() end, '') or ''):lower()
        if rt == 'archery' or rt == 'bow' then
            r = r + parseNumber(tloSafe(function() return mq.TLO.Me.Inventory('ammo').Range() end, 0), 0)
        end
        if r > 0 then return r end
        return 80
    end
    local s = spellByName(pullWith)
    if s then
        local r = parseNumber(s.MyRange(), 0)
        if r <= 0 then r = parseNumber(s.AERange(), 0) end
        if r > 0 then return r end
    end
    return 80
end

local function performPullAction(pullWith, sid)
    local pw = tostring(pullWith or 'Melee'):lower()
    if pw == 'melee' or pw == 'autoattack' then
        pcall(function() mq.cmdf('/face fast id %d', sid) end)
        pcall(function() mq.cmdf('/stick 10 id %d moveback uw', sid) end)
        pcall(function() mq.cmd('/attack on') end)
        return true
    end
    if pw == 'ranged' then
        pcall(function() mq.cmdf('/face fast id %d', sid) end)
        pcall(function() mq.cmdf('/ranged %d', sid) end)
        return true
    end
    return castAbility(pullWith, sid, true)
end

local function pullAttemptSucceeded(startXT, pullID)
    local xt = getXTHaterCount()
    if xt > startXT then return true end
    if boolish(tloSafe(function() return mq.TLO.Me.InCombat() end, false)) then return true end
    if pullID and pullID > 0 then
        local hp = parseNumber(tloSafe(function() return mq.TLO.Spawn(pullID).PctHPs() end, 100), 100)
        if hp < 100 then return true end
    end
    return false
end

local function angleDelta(a, b)
    local d = math.abs((a - b) % 360)
    if d > 180 then d = 360 - d end
    return d
end

local function inPullArc(sid)
    local arcWidth = parseNumber(state.config.Pull.PullArcWidth, 0) or 0
    if arcWidth <= 0 then return true end
    local meHeading = parseNumber(tloSafe(function() return mq.TLO.Me.Heading.Degrees() end, 0), 0)
    local toHeading = parseNumber(tloSafe(function() return mq.TLO.Spawn(sid).HeadingTo() end, -1), -1)
    if toHeading < 0 then
        local meX = parseNumber(tloSafe(function() return mq.TLO.Me.X() end, 0), 0)
        local meY = parseNumber(tloSafe(function() return mq.TLO.Me.Y() end, 0), 0)
        local sx = parseNumber(tloSafe(function() return mq.TLO.Spawn(sid).X() end, meX), meX)
        local sy = parseNumber(tloSafe(function() return mq.TLO.Spawn(sid).Y() end, meY), meY)
        local dy = sy - meY
        local dx = sx - meX
        local ang = math.deg(math.atan2(dx, dy))
        if ang < 0 then ang = ang + 360 end
        toHeading = ang
    end
    return angleDelta(meHeading, toHeading) <= (arcWidth / 2)
end

local function findPullCandidate(maxRadius, maxZRange)
    maxRadius = tonumber(maxRadius or 200) or 200
    maxZRange = tonumber(maxZRange or state.config.Pull.MaxZRange or 60) or 60
    local queries = {
        string.format('targetable npc radius %d zradius %d', maxRadius, maxZRange),
        string.format('npc targetable radius %d zradius %d', maxRadius, maxZRange),
        string.format('npc radius %d zradius %d', maxRadius, maxZRange),
    }
    local sid = 0
    local namedFirst = boolish(state.config.Pull.PullNamedsFirst)
    local namedSid = 0
    for _, query in ipairs(queries) do
        for i = 1, 50 do
            local cand = parseNumber(tloSafe(function() return mq.TLO.NearestSpawn(i, query).ID() end, 0), 0)
            if cand > 0 then
                local nm = tostring(tloSafe(function() return mq.TLO.Spawn(cand).CleanName() end, '') or ''):lower()
                local lvl = parseNumber(tloSafe(function() return mq.TLO.Spawn(cand).Level() end, 0), 0)
                local ignored = state.pullRules.ignore[nm] == true
                local allowed = state.pullRules.all or state.pullRules.allow[nm] == true
                local levelOk = lvl >= (state.pullRules.minLvl or 1) and lvl <= (state.pullRules.maxLvl or 200)
                local inArc = inPullArc(cand)
                if not ignored and allowed and levelOk and inArc then
                    if namedFirst and boolish(tloSafe(function() return mq.TLO.Spawn(cand).Named() end, false)) then
                        namedSid = cand
                        break
                    end
                    sid = cand
                    break
                end
            end
        end
        if namedSid > 0 or sid > 0 then break end
    end
    if namedSid > 0 then sid = namedSid end
    if sid < 1 then return 0 end
    if sid == state.pull.lastID and (nowMs() - state.pull.lastAt) < 3000 then
        return 0
    end
    return sid
end

local function setPullPhase(phase, reason)
    if state.pull.phase ~= phase and state.debug then
        log('PullPhase %s -> %s (%s)', tostring(state.pull.phase), tostring(phase), tostring(reason or ''))
    end
    state.pull.phase = phase
end

local function resetPullState(cooldownMs)
    stopNavigation()
    state.pull.targetID = 0
    state.pull.attempts = 0
    state.pull.startXT = 0
    state.pull.startAt = 0
    state.pull.lastNavAt = 0
    state.pull.lastActionAt = 0
    state.pull.pullWith = tostring(state.config.Pull.PullWith or 'Melee')
    state.pull.range = pullAbilityRange(state.pull.pullWith)
    if cooldownMs and cooldownMs > 0 then
        state.pull.lastAt = nowMs() - (math.max(0, parseNumber(state.config.Pull.PullWait, 1)) * 1000) + cooldownMs
    else
        state.pull.lastAt = nowMs()
    end
    setPullPhase('IDLE', 'reset')
end

local function startPullCycle(sid)
    state.pull.targetID = sid
    state.pull.lastID = sid
    state.pull.pullWith = tostring(state.config.Pull.PullWith or 'Melee')
    state.pull.range = pullAbilityRange(state.pull.pullWith)
    state.pull.startXT = getXTHaterCount()
    state.pull.attempts = 0
    state.pull.startAt = nowMs()
    state.pull.lastNavAt = 0
    state.pull.lastActionAt = 0
    state.pull.campX = state.camp.x
    state.pull.campY = state.camp.y
    state.pull.campZ = state.camp.z
    targetByID(sid)
    setPullPhase('NAV_TO_TARGET', 'new_target')
end

local function doPullNavStep()
    local sid = state.pull.targetID
    if sid < 1 then return end
    local range = math.max(6, math.floor(state.pull.range * 0.9))
    local now = nowMs()
    if now - state.pull.lastNavAt < 800 then return end
    state.pull.lastNavAt = now
    targetByID(sid)
    local hasNavMesh = boolish(tloSafe(function() return mq.TLO.Navigation.MeshLoaded() end, false))
    if hasNavMesh and boolish(tloSafe(function() return mq.TLO.Navigation.PathExists(string.format('id %d distance %d', sid, range))() end, false)) then
        pcall(function() mq.cmdf('/squelch /nav id %d distance=%d lineofsight=off log=off', sid, range) end)
    else
        pcall(function() mq.cmd('/squelch /nav target') end)
        mq.delay(150)
        if not boolish(tloSafe(function() return mq.TLO.Navigation.Active() end, false)) then
            pcall(function() mq.cmdf('/moveto id %d mdist %d', sid, range) end)
            mq.delay(150)
        end
        if not boolish(tloSafe(function() return mq.TLO.Navigation.Active() end, false))
            and not boolish(tloSafe(function() return mq.TLO.MoveTo.Moving() end, false)) then
            pcall(function() mq.cmdf('/stick %d id %d moveback uw', range, sid) end)
            mq.delay(150)
        end
        if not boolish(tloSafe(function() return mq.TLO.Navigation.Active() end, false))
            and not boolish(tloSafe(function() return mq.TLO.MoveTo.Moving() end, false))
            and not boolish(tloSafe(function() return mq.TLO.Stick.Active() end, false)) then
            pcall(function() mq.cmdf('/face fast id %d', sid) end)
            pcall(function() mq.cmd('/keypress forward hold') end)
            mq.delay(350)
            pcall(function() mq.cmd('/keypress forward') end)
        end
    end
end

local function parseChainPauseMinutes()
    local raw = tostring((state.config.Pull and state.config.Pull.ChainPullPause) or '')
    if raw == '' or raw:upper() == 'NULL' or raw == '0' then return 0, 0 end
    local p = split(raw, '|')
    local active = math.max(0, parseNumber(p[1], 0))
    local pause = math.max(0, parseNumber(p[2], 0))
    return active, pause
end

local function chainPauseBlocked(chainEnabled)
    if not chainEnabled then return false end
    local activeMins, pauseMins = parseChainPauseMinutes()
    if activeMins <= 0 or pauseMins <= 0 then return false end
    local now = nowMs()
    if state.pull.chainNextPauseAt <= 0 then
        state.pull.chainNextPauseAt = now + (activeMins * 60 * 1000)
    end
    if state.pull.chainPauseUntil > now then
        return true
    end
    if now >= state.pull.chainNextPauseAt then
        state.pull.chainPauseUntil = now + (pauseMins * 60 * 1000)
        state.pull.chainNextPauseAt = state.pull.chainPauseUntil + (activeMins * 60 * 1000)
        log('Pausing Pulls for %d minute(s).', pauseMins)
        return true
    end
    return false
end

local function useCalmOnTargetIfConfigured(sid)
    if not boolish(state.config.Pull.UseCalm) then return false end
    local calmWith = tostring(state.config.Pull.CalmWith or '')
    if calmWith == '' or calmWith:upper() == 'NULL' then return false end
    local dist = parseNumber(tloSafe(function() return mq.TLO.Spawn(sid).Distance3D() end, 9999), 9999)
    local spell = spellByName(calmWith)
    local range = spell and parseNumber(spell.MyRange(), 0) or 0
    if range <= 0 then range = 100 end
    if dist > (range + 3) then return false end
    local already = boolish(tloSafe(function() return mq.TLO.Spawn(sid).Buff(calmWith)() ~= nil end, false))
    if already then return false end
    return castAbility(calmWith, sid, true)
end

local function runPullerRole()
    local function trace(reason)
        state.pull.lastReason = tostring(reason or '')
        if not state.debug then return end
        if nowMs() - (state.pull.lastTraceAt or 0) < 900 then return end
        state.pull.lastTraceAt = nowMs()
        log('PullTrace phase=%s reason=%s', tostring(state.pull.phase), tostring(reason))
    end

    local role = tostring(state.role or ''):lower()
    if role ~= 'puller' and role ~= 'pullertank' and role ~= 'pullerpettank' and role ~= 'hunter' and role ~= 'hunterpettank' then
        trace('role_not_puller')
        if state.pull.phase ~= 'IDLE' then resetPullState(0) end
        return false
    end

    if state.pull.phase == 'IDLE' then
        if boolish(tloSafe(function() return mq.TLO.Me.InCombat() end, false)) then trace('blocked_in_combat') return false end
        local xtCount = getXTHaterCount()
        local chainRaw = state.config.Pull.ChainPull
        local chainNum = parseNumber(chainRaw, 0)
        local chainEnabled = boolish(chainRaw) or chainNum > 0
        local chainLimit = chainEnabled and math.max(1, chainNum > 0 and chainNum or 1) or 0
        if chainPauseBlocked(chainEnabled) then
            trace('blocked_chain_pause')
            return false
        end
        if (not chainEnabled and xtCount > 0) then
            trace(string.format('blocked_xtarget_nonzero(%d)', xtCount))
            return false
        end
        if chainEnabled then
            local chainHP = parseNumber(state.config.Pull.ChainPullHP, 90)
            local tHP = parseNumber(tloSafe(function() return mq.TLO.Target.PctHPs() end, 100), 100)
            if targetIsUsable() and tHP > chainHP then
                trace(string.format('blocked_chain_hp target=%d hp=%d', chainHP, tHP))
                return false
            end
        end
        if (chainEnabled and xtCount >= chainLimit) then
            trace(string.format('blocked_chain_limit xt=%d limit=%d', xtCount, chainLimit))
            return false
        end
        local waitMs = math.max(1, parseNumber(state.config.Pull.PullWait, 1)) * 1000
        if nowMs() - state.pull.lastAt < waitMs then trace('blocked_pull_wait') return false end
        local sid = findPullCandidate(parseNumber(state.config.Pull.MaxRadius, 200), state.config.Pull.MaxZRange)
        if sid < 1 then trace('no_candidate_found') return false end
        startPullCycle(sid)
    end

    local sid = state.pull.targetID
    if sid < 1 then
        resetPullState(250)
        return false
    end
    local sp = mq.TLO.Spawn(sid)
    if not sp() or boolish(sp.Dead()) then
        resetPullState(500)
        return true
    end

    if pullAttemptSucceeded(state.pull.startXT, sid) and state.pull.phase ~= 'RETURN_TO_CAMP' then
        setPullPhase('RETURN_TO_CAMP', 'tagged')
    end

    if state.pull.phase == 'NAV_TO_TARGET' then
        local dist = parseNumber(tloSafe(function() return mq.TLO.Spawn(sid).Distance3D() end, 9999), 9999)
        if dist <= (state.pull.range + 3) then
            stopNavigation()
            setPullPhase('EXECUTE_PULL', 'in_range')
        else
            doPullNavStep()
        end
        if nowMs() - state.pull.startAt > 20000 then
            resetPullState(1200)
        end
        return true
    end

    if state.pull.phase == 'EXECUTE_PULL' then
        local dist = parseNumber(tloSafe(function() return mq.TLO.Spawn(sid).Distance3D() end, 9999), 9999)
        local inRange = dist <= (state.pull.range + 2)
        if not inRange then
            doPullNavStep()
            return true
        end
        useCalmOnTargetIfConfigured(sid)
        if nowMs() - state.pull.lastActionAt > 600 then
            targetByID(sid)
            state.pull.lastActionAt = nowMs()
            state.pull.attempts = state.pull.attempts + 1
            performPullAction(state.pull.pullWith, sid)
        end
        if pullAttemptSucceeded(state.pull.startXT, sid) then
            setPullPhase('RETURN_TO_CAMP', 'success')
        elseif state.pull.attempts >= 14 or (nowMs() - state.pull.startAt) > 22000 then
            resetPullState(1400)
        end
        return true
    end

    if state.pull.phase == 'RETURN_TO_CAMP' then
        if not boolish(state.config.General.ReturnToCamp) then
            resetPullState(500)
            return true
        end
        local rtcAcc = parseNumber(state.config.General.ReturnToCampAccuracy, 10)
        local meX = parseNumber(tloSafe(function() return mq.TLO.Me.X() end, 0), 0)
        local meY = parseNumber(tloSafe(function() return mq.TLO.Me.Y() end, 0), 0)
        local meZ = parseNumber(tloSafe(function() return mq.TLO.Me.Z() end, 0), 0)
        local dist = distance3d(meX, meY, meZ, state.pull.campX, state.pull.campY, state.pull.campZ)
        if dist <= rtcAcc or boolish(tloSafe(function() return mq.TLO.Me.InCombat() end, false)) then
            resetPullState(250)
            return true
        end
        if nowMs() - state.pull.lastNavAt > 900 then
            state.pull.lastNavAt = nowMs()
            pcall(function() mq.cmdf('/squelch /nav locyxz %.2f %.2f %.2f', state.pull.campY, state.pull.campX, state.pull.campZ) end)
        end
        if nowMs() - state.pull.startAt > 35000 then
            resetPullState(800)
        end
        return true
    end

    resetPullState(0)
    return false
end

local function iterateList(listName, fn)
    local entries = state.lists[listName] or {}
    for _, entry in ipairs(entries) do
        if evalCond(entry.cond) then
            local stop = fn(entry)
            if stop then return true end
        end
    end
    return false
end

local function runOhShit()
    if not boolish(state.config.OhShit.OhShitOn) then return false end
    local selfHP = tloSafe(function() return mq.TLO.Me.PctHPs() end, 100)
    if selfHP > 70 then return false end
    return iterateList('OhShit', function(entry)
        return castAbility(entry.value.ability, mq.TLO.Me.ID(), true)
    end)
end

local function runAggroTools()
    if not boolish(state.config.Aggro.AggroOn) then return false end
    return iterateList('Aggro', function(entry)
        local threshold = parseNumber(entry.value.options[2], 90)
        local aggroPct = tloSafe(function() return mq.TLO.Me.PctAggro() end, 0)
        if aggroPct >= threshold then
            return castAbility(entry.value.ability, mq.TLO.Target.ID(), true)
        end
        return false
    end)
end

local function runBurns()
    if not boolish(state.config.Burn.BurnOn) then return false end
    local now = nowMs()
    if now - state.lastBurnAt < 900 then return false end
    state.lastBurnAt = now
    local fired = iterateList('Burn', function(entry)
        return castAbility(entry.value.ability, mq.TLO.Target.ID(), true)
    end)
    if fired then return true end

    local caps = CLASS_CAPS[state.classShort]
    if not caps then return false end
    local fb = CLASS_FALLBACK[state.classShort]
    for _, n in ipairs((fb and fb.burn) or {}) do
        if castAbility(n, mq.TLO.Target.ID(), true) then return true end
    end
    for _, aa in ipairs(caps.burnAA or {}) do
        if canUseAA(aa) then
            local ok = pcall(function() mq.cmdf('/alt activate %d', aa) end)
            if ok then return true end
        end
    end
    return false
end

local function runAETools()
    if not boolish(state.config.AE.AEOn) then return false end
    local radius = parseNumber(state.config.AE.AERadius, 50)
    local mobs = getHostileNearby(radius)
    return iterateList('AE', function(entry)
        local needed = parseNumber(entry.value.options[2], 2)
        if mobs >= needed then
            return castAbility(entry.value.ability, mq.TLO.Target.ID(), false)
        end
        return false
    end)
end

local function runMez()
    if not boolish(state.config.Mez and state.config.Mez.MezOn) then return false end
    local cls = tostring(state.classShort or '')
    if cls ~= 'ENC' and cls ~= 'BRD' and cls ~= 'CLR' then return false end
    if nowMs() - state.lastMezAt < 600 then return false end
    local mezSpell = tostring((state.config.Mez and state.config.Mez.MezSpell) or '')
    if mezSpell == '' or mezSpell == 'Your Mez Spell' or mezSpell == 'NULL' then return false end
    local mezRadius = parseNumber(state.config.Mez.MezRadius, 50)
    local minLvl = parseNumber(state.config.Mez.MezMinLevel, 1)
    local maxLvl = parseNumber(state.config.Mez.MezMaxLevel, 999)
    local stopHP = parseNumber(state.config.Mez.MezStopHPs, 80)
    local curTarget = parseNumber(tloSafe(function() return mq.TLO.Target.ID() end, 0), 0)

    local xtMax = parseNumber(tloSafe(function() return mq.TLO.Me.XTarget() end, 0), 0)
    for i = 1, xtMax do
        local xt = mq.TLO.Me.XTarget(i)
        if xt() and tostring(xt.Type() or ''):lower() == 'npc' and not boolish(xt.Dead()) then
            local sid = parseNumber(tloSafe(function() return xt.ID() end, 0), 0)
            local dist = parseNumber(tloSafe(function() return xt.Distance3D() end, 9999), 9999)
            local lvl = parseNumber(tloSafe(function() return xt.Level() end, 0), 0)
            local hp = parseNumber(tloSafe(function() return xt.PctHPs() end, 100), 100)
            local name = tostring(tloSafe(function() return xt.CleanName() end, '') or ''):lower()
            if sid > 0 and sid ~= curTarget and dist <= mezRadius and lvl >= minLvl and lvl <= maxLvl and hp >= stopHP and not state.mezImmune[name] then
                if targetByID(sid) then
                    local ok = castAbility(mezSpell, sid, true)
                    if ok then
                        state.lastMezAt = nowMs()
                        return true
                    end
                end
            end
        end
    end
    return false
end

local function runDps()
    if not boolish(state.config.DPS.DPSOn) then return false end
    local interval = math.max(1, parseNumber(state.config.DPS.DPSInterval, 2)) * 1000
    if nowMs() - state.lastDpsAt < interval then return false end
    state.lastDpsAt = nowMs()
    local usedIni = iterateList('DPS', function(entry)
        local pct = parseNumber(entry.value.options[2], 100)
        local targetPct = tloSafe(function() return mq.TLO.Target.PctHPs() end, 100)
        if targetPct <= pct then
            return castAbility(entry.value.ability, mq.TLO.Target.ID(), false)
        end
        return false
    end)
    if usedIni then return true end
    local fb = CLASS_FALLBACK[state.classShort]
    for _, n in ipairs((fb and fb.dps) or {}) do
        if castAbility(n, mq.TLO.Target.ID(), false) then return true end
    end
    return false
end

local function gatherGroup()
    local members = {}
    members[#members+1] = {
        id = tloSafe(function() return mq.TLO.Me.ID() end, 0),
        name = tloSafe(function() return mq.TLO.Me.CleanName() end, ''),
        hp = tloSafe(function() return mq.TLO.Me.PctHPs() end, 100),
        dead = tloSafe(function() return mq.TLO.Me.Dead() end, false),
        self = true,
    }
    local count = parseNumber(tloSafe(function() return mq.TLO.Group.Members() end, 0), 0)
    for i = 1, count do
        local name = tloSafe(function() return mq.TLO.Group.Member(i).Name() end, nil)
        if name and name ~= '' then
            members[#members+1] = {
                id = tloSafe(function() return mq.TLO.Spawn(name).ID() end, 0),
                name = name,
                hp = parseNumber(tloSafe(function() return mq.TLO.Group.Member(i).PctHPs() end, 100), 100),
                dead = boolish(tloSafe(function() return mq.TLO.Group.Member(i).Dead() end, false)),
                self = false,
                index = i,
            }
        end
    end
    table.sort(members, function(a, b) return a.hp < b.hp end)
    return members
end

local function hasBuffOnMe(buffName)
    return tloSafe(function() return mq.TLO.Me.Buff(buffName)() ~= nil or mq.TLO.Me.Song(buffName)() ~= nil end, false)
end

local function hasBuffOnMember(memberIndex, buffName)
    return tloSafe(function() return mq.TLO.Group.Member(memberIndex).Buff(buffName)() ~= nil end, false)
end

local function buffNeedsRefreshOnMe(buffName, minTicks)
    minTicks = minTicks or 18
    local buffObj = tloSafe(function() return mq.TLO.Me.Buff(buffName) end, nil)
    if buffObj and buffObj() then
        local d = parseNumber(tloSafe(function() return buffObj.Duration() end, 9999), 9999)
        return d <= minTicks
    end
    local songObj = tloSafe(function() return mq.TLO.Me.Song(buffName) end, nil)
    if songObj and songObj() then
        local d = parseNumber(tloSafe(function() return songObj.Duration() end, 9999), 9999)
        return d <= minTicks
    end
    return true
end

local function buffNeedsRefreshOnMember(memberIndex, buffName, minTicks)
    minTicks = minTicks or 18
    local b = tloSafe(function() return mq.TLO.Group.Member(memberIndex).Buff(buffName) end, nil)
    if b and b() then
        local d = parseNumber(tloSafe(function() return b.Duration() end, 9999), 9999)
        return d <= minTicks
    end
    return true
end

local function isValidHealTarget(targetID, spellName)
    if not targetID or targetID < 1 then return false end
    local t = mq.TLO.Spawn(targetID)
    if not t() or t.Dead() then return false end
    if spellName and spellName ~= '' then
        local s = spellByName(spellName)
        if s then
            local r = parseNumber(tloSafe(function() return s.MyRange() end, 0), 0)
            if r <= 0 then r = 200 end
            local d = parseNumber(tloSafe(function() return t.Distance3D() end, 9999), 9999)
            if d > r * 1.1 then return false end
        end
    end
    return true
end

local function runHeals()
    local caps = CLASS_CAPS[state.classShort]
    local healOn = boolish(state.config.Heals.HealsOn)
    if not healOn and not (caps and caps.healer) then return false end
    if nowMs() - state.lastHealAt < 350 then return false end
    state.lastHealAt = nowMs()

    local group = gatherGroup()
    for _, member in ipairs(group) do
        if member.dead and (caps and caps.rez) and boolish(state.config.Heals.AutoRezOn) then
            local rezWith = state.config.Heals.AutoRezWith
            if rezWith and rezWith ~= '' and rezWith ~= 'Your Rez Item/AA/Spell' then
                if castAbility(rezWith, member.id, true) then return true end
            end
        end
    end

    if #group == 0 then return false end
    local didIni = iterateList('Heals', function(entry)
        local threshold = parseNumber(entry.value.options[2], 60)
        local groupHeal = tostring(entry.value.options[3] or ''):lower():find('group', 1, true) ~= nil
        if groupHeal then
            local lowCount = 0
            for _, m in ipairs(group) do
                if not m.dead and m.hp <= threshold then lowCount = lowCount + 1 end
            end
            if lowCount >= 3 then
                return castAbility(entry.value.ability, mq.TLO.Me.ID(), true)
            end
        else
            for _, m in ipairs(group) do
                if not m.dead and m.hp <= threshold then
                    if isValidHealTarget(m.id, entry.value.ability) then
                        return castAbility(entry.value.ability, m.id, true)
                    end
                end
            end
        end
        return false
    end)
    if didIni then return true end
    local fb = CLASS_FALLBACK[state.classShort]
    for _, h in ipairs((fb and fb.heals) or {}) do
        for _, m in ipairs(group) do
            if not m.dead and m.hp <= 70 and isValidHealTarget(m.id, h) then
                if castAbility(h, m.id, true) then return true end
            end
        end
    end
    return false
end

local function runBuffs()
    if not boolish(state.config.Buffs.BuffsOn) then return false end
    local now = nowMs()
    local checkEvery = math.max(2, parseNumber(state.config.Buffs.CheckBuffsTimer, 10)) * 1000
    if now - state.lastBuffAt < checkEvery then return false end
    state.lastBuffAt = now

    local inCombat = boolish(tloSafe(function() return mq.TLO.Me.InCombat() end, false))
    local casted = false

    local usedIni = iterateList('Buffs', function(entry)
        local ability = entry.value.ability
        local mode = tostring(entry.value.options[2] or 'me'):lower()
        local critical = mode:find('critical', 1, true) ~= nil
        local inCombatAllowed = critical or mode:find('combat', 1, true) ~= nil
        if inCombat and not inCombatAllowed then return false end

        if mode:find('group', 1, true) then
            local count = parseNumber(tloSafe(function() return mq.TLO.Group.Members() end, 0), 0)
            for i = 1, count do
                local name = tloSafe(function() return mq.TLO.Group.Member(i).Name() end, nil)
                if name and name ~= '' and (not hasBuffOnMember(i, ability) or buffNeedsRefreshOnMember(i, ability, 24)) then
                    local id = tloSafe(function() return mq.TLO.Spawn(name).ID() end, 0)
                    if id > 0 and castAbility(ability, id, critical) then
                        casted = true
                        return true
                    end
                end
            end
        else
            if (not hasBuffOnMe(ability) or buffNeedsRefreshOnMe(ability, 24)) and castAbility(ability, mq.TLO.Me.ID(), critical) then
                casted = true
                return true
            end
        end
        return false
    end)
    if usedIni then return true end
    local fb = CLASS_FALLBACK[state.classShort]
    for _, b in ipairs((fb and fb.buffs) or {}) do
        if (not hasBuffOnMe(b) or buffNeedsRefreshOnMe(b, 24)) then
            if castAbility(b, mq.TLO.Me.ID(), false) then return true end
        end
    end

    return casted
end

local function runPetLogic()
    local caps = CLASS_CAPS[state.classShort]
    if not (caps and caps.pet and boolish(state.config.Pet.PetOn)) then return false end
    local havePet = tloSafe(function() return mq.TLO.Me.Pet.ID() and mq.TLO.Me.Pet.ID() > 0 end, false)
    if not havePet then
        local petSpell = state.config.Pet.PetSpell
        if petSpell and petSpell ~= '' and petSpell ~= 'YourPetSpell' then
            return castAbility(petSpell, mq.TLO.Me.ID(), true)
        end
        return false
    end
    if boolish(state.config.Pet.PetCombatOn) and targetIsUsable() then
        pcall(function() mq.cmd('/pet attack') end)
    end
    if boolish(state.config.Pet.PetBuffsOn) then
        return iterateList('PetBuffs', function(entry)
            return castAbility(entry.value.ability, tloSafe(function() return mq.TLO.Me.Pet.ID() end, 0), false)
        end)
    end
    return false
end

local function handleMeleeEngage()
    local role = tostring(state.role or ''):lower()
    local combatRole = (role == 'tank' or role == 'puller' or role == 'pullertank' or role == 'pullerpettank' or role == 'hunter' or role == 'hunterpettank' or role == 'pettank')
    if combatRole then
        if targetIsUsable() then
            local tid = parseNumber(tloSafe(function() return mq.TLO.Target.ID() end, 0), 0)
            pcall(function() mq.cmd('/attack on') end)
            if tid > 0 then
                pcall(function() mq.cmdf('/face fast id %d', tid) end)
                pcall(function() mq.cmdf('/stick 12 id %d moveback uw', tid) end)
            elseif boolish(state.config.Melee.FaceMobOn) then
                pcall(function() mq.cmd('/face fast') end)
            end
        else
            pcall(function() mq.cmd('/attack off') end)
        end
        return
    end
    local assistAt = parseNumber(state.config.Melee.AssistAt, 95)
    local tHP = parseNumber(tloSafe(function() return mq.TLO.Target.PctHPs() end, 100), 100)
    local meleeOn = boolish(state.config.Melee.MeleeOn)
    if tHP <= assistAt then
        local tid = parseNumber(tloSafe(function() return mq.TLO.Target.ID() end, 0), 0)
        pcall(function() mq.cmd('/attack on') end)
        if tid > 0 then
            pcall(function() mq.cmdf('/face fast id %d', tid) end)
            if meleeOn then
                pcall(function() mq.cmdf('/stick 12 id %d moveback uw', tid) end)
            end
        elseif meleeOn and boolish(state.config.Melee.FaceMobOn) then
            pcall(function() mq.cmd('/face fast') end)
        end
    else
        pcall(function() mq.cmd('/attack off') end)
    end
end

local function classCombatPulse()
    if not targetIsUsable() then return end
    local targetID = parseNumber(tloSafe(function() return mq.TLO.Target.ID() end, 0), 0)
    local targetLOS = boolish(tloSafe(function() return mq.TLO.Target.LineOfSight() end, true))
    if targetID > 0 and not targetLOS then
        navigateToSpawn(targetID)
        pcall(function() mq.cmd('/attack on') end)
        return
    end
    runMez()
    runOhShit()
    runAggroTools()
    runBurns()
    runAETools()
    runDps()
    runPetLogic()
    handleMeleeEngage()
end

local function canAct()
    if state.paused then return false end
    if boolish(tloSafe(function() return mq.TLO.Me.Dead() end, false)) then return false end
    if boolish(tloSafe(function() return mq.TLO.Me.Hovering() end, false)) then return false end
    if boolish(tloSafe(function() return mq.TLO.Me.Feigning() end, false)) then return false end
    if boolish(tloSafe(function() return mq.TLO.Me.Charmed() end, false)) then return false end
    if boolish(tloSafe(function() return mq.TLO.Me.Mezzed() end, false)) then return false end
    if tloSafe(function() return mq.TLO.Zone.ID() end, 0) ~= state.lastZoneID then
        state.lastZoneID = tloSafe(function() return mq.TLO.Zone.ID() end, 0)
        mq.delay(1000)
        return false
    end
    return true
end

local runMapTheZone = function() end
local performCustomCall = function() end

local function pulse()
    performCustomCall()
    if state.mapTheZone then
        runMapTheZone()
    end

    local inCombat = boolish(tloSafe(function() return mq.TLO.Me.InCombat() end, false))
    local xtCountNow = getXTHaterCount()
    local combatPressure = inCombat or xtCountNow > 0
    local chaseAssist = boolish(state.config.General.ChaseAssist)
    local returnToCamp = boolish(state.config.General.ReturnToCamp)
    local chaseDistance = parseNumber(state.config.General.ChaseDistance, 25)
    local rtcAcc = parseNumber(state.config.General.ReturnToCampAccuracy, 10)
    local role = tostring(state.role or ''):lower()
    local isPullRole = (role == 'puller' or role == 'pullertank' or role == 'pullerpettank' or role == 'hunter' or role == 'hunterpettank')
    local meX = parseNumber(tloSafe(function() return mq.TLO.Me.X() end, 0), 0)
    local meY = parseNumber(tloSafe(function() return mq.TLO.Me.Y() end, 0), 0)
    local meZ = parseNumber(tloSafe(function() return mq.TLO.Me.Z() end, 0), 0)

    if combatPressure and state.pull.phase ~= 'IDLE' then
        resetPullState(250)
        state.pull.lastReason = 'combat_pressure_reset'
    end

    if combatPressure and (not targetIsUsable() or not boolish(tloSafe(function() return mq.TLO.Target.LineOfSight() end, true))) then
        acquireCombatTargetFromXT(true)
    end

    if not combatPressure then
        if isPullRole and runPullerRole() then
            return
        end
        if chaseAssist then
            local ma = state.mainAssist or tloSafe(function() return mq.TLO.Group.MainAssist.Name() end, nil)
            if ma and ma ~= '' then
                local maID = parseNumber(tloSafe(function() return mq.TLO.Spawn(ma).ID() end, 0), 0)
                local maDist = parseNumber(tloSafe(function() return mq.TLO.Spawn(maID).Distance3D() end, 0), 0)
                if maID > 0 and maDist > chaseDistance then
                    navigateToSpawn(maID)
                elseif maDist <= chaseDistance then
                    stopNavigation()
                end
            end
        elseif returnToCamp and not isPullRole then
            local dist = distance3d(meX, meY, meZ, state.camp.x, state.camp.y, state.camp.z)
            if dist > rtcAcc then
                navigateToCamp()
            else
                stopNavigation()
            end
        elseif not isPullRole then
            stopNavigation()
        end
    else
        stopNavigation()
    end

    assistMAIfNeeded()
    runHeals()
    if not state.navActive or boolish(state.config.General.BuffWhileChasing) then
        runBuffs()
    end
    if targetIsUsable() then
        classCombatPulse()
    else
        handleMeleeEngage()
    end
end

local function printGroupCheck()
    local members = gatherGroup()
    log('GroupCheck: %d entries', #members)
    for _, m in ipairs(members) do
        log(' - %s HP:%s Dead:%s ID:%s', tostring(m.name), tostring(m.hp), tostring(m.dead), tostring(m.id))
    end
end

local function currentZoneKey()
    return tloSafe(function() return mq.TLO.Zone.ShortName() end, 'UnknownZone')
end

local function resolveSpawnNameFromArg(arg, wantType)
    local sid = tonumber(arg or '')
    local s
    if sid and sid > 0 then
        s = mq.TLO.Spawn(sid)
    elseif arg and arg ~= '' then
        s = mq.TLO.Spawn(arg)
    else
        s = mq.TLO.Target
    end
    if not s or not s() then return nil end
    local sType = tostring(tloSafe(function() return s.Type() end, '')):lower()
    if wantType == 'npc' and sType ~= 'npc' then return nil end
    if wantType == 'pc' and sType ~= 'pc' then return nil end
    local name = tloSafe(function() return s.CleanName() end, nil)
    if not name or name == '' then return nil end
    name = tostring(name):gsub('%s+[Cc][Oo][Rr][Pp][Ss][Ee]$', '')
    return name
end

local function appendZoneList(key, spawnName)
    if not spawnName or spawnName == '' then return false, 'no_name' end
    local zoneKey = currentZoneKey()
    local iniPath = string.format('%s/%s', mq.configDir, INFO_INI)
    local cur = iniGet(iniPath, zoneKey, key, 'NULL')
    local lowerCur = tostring(cur):lower()
    if lowerCur:find(spawnName:lower(), 1, true) then
        return false, 'duplicate'
    end
    local nextValue
    if lowerCur == 'null' or lowerCur == 'all' or lowerCur == 'all for all mobs' then
        nextValue = spawnName
    else
        nextValue = string.format('%s,%s', cur, spawnName)
    end
    pcall(function() mq.cmdf('/ini "%s" "%s" "%s" "%s"', iniPath, zoneKey, key, nextValue) end)
    return true, nextValue
end

local function bindScribeStuff()
    pcall(function() mq.cmd('/autoinv') end)
    pcall(function() mq.cmd('/keypress OPEN_INV_BAGS') end)
    local didAny = 0
    local cls = tostring(tloSafe(function() return mq.TLO.Me.Class.ShortName() end, ''))
    local isPureCaster = (cls == 'CLR' or cls == 'DRU' or cls == 'SHM' or cls == 'ENC' or cls == 'WIZ' or cls == 'MAG' or cls == 'NEC')
    local isMeleeOnly = (cls == 'WAR' or cls == 'BER' or cls == 'MNK' or cls == 'ROG')
    local function shouldScribe(itemType)
        local lt = tostring(itemType or ''):lower()
        local isSpell = lt:find('spell', 1, true) ~= nil
        local isTome = lt:find('tome', 1, true) ~= nil
        if isMeleeOnly then return isTome end
        if isPureCaster then return isSpell end
        return isSpell or isTome
    end
    for bag = 1, 10 do
        local slotName = string.format('pack%d', bag)
        local containerSlots = parseNumber(tloSafe(function() return mq.TLO.InvSlot(slotName).Item.Container() end, 0), 0)
        if containerSlots > 0 then
            pcall(function() mq.cmdf('/itemnotify %s rightmouseup', slotName) end)
            mq.delay(150)
            for slot = 1, containerSlots do
                local iType = tostring(tloSafe(function() return mq.TLO.InvSlot(slotName).Item.Item(slot).ItemType() end, ''))
                local iName = tostring(tloSafe(function() return mq.TLO.InvSlot(slotName).Item.Item(slot).Name() end, ''))
                if iName ~= '' and shouldScribe(iType) then
                    local beforeId = parseNumber(tloSafe(function() return mq.TLO.InvSlot(slotName).Item.Item(slot).ID() end, 0), 0)
                    pcall(function() mq.cmdf('/itemnotify in %s %d rightmouseup', slotName, slot) end)
                    mq.delay(350)
                    if mq.TLO.Window('ConfirmationDialogBox').Open() then
                        pcall(function() mq.cmd('/notify ConfirmationDialogBox Yes_Button leftmouseup') end)
                    end
                    mq.delay(350)
                    mq.delay(2500, function()
                        local afterId = parseNumber(tloSafe(function() return mq.TLO.InvSlot(slotName).Item.Item(slot).ID() end, 0), 0)
                        return afterId == 0 or afterId ~= beforeId
                    end)
                    if mq.TLO.Cursor.ID() then pcall(function() mq.cmd('/autoinv') end) end
                    didAny = didAny + 1
                end
            end
        else
            local iType = tostring(tloSafe(function() return mq.TLO.InvSlot(slotName).Item.ItemType() end, ''))
            local iName = tostring(tloSafe(function() return mq.TLO.InvSlot(slotName).Item.Name() end, ''))
            if iName ~= '' and shouldScribe(iType) then
                local beforeId = parseNumber(tloSafe(function() return mq.TLO.InvSlot(slotName).Item.ID() end, 0), 0)
                pcall(function() mq.cmdf('/itemnotify %s rightmouseup', slotName) end)
                mq.delay(350)
                if mq.TLO.Window('ConfirmationDialogBox').Open() then
                    pcall(function() mq.cmd('/notify ConfirmationDialogBox Yes_Button leftmouseup') end)
                end
                mq.delay(350)
                mq.delay(2500, function()
                    local afterId = parseNumber(tloSafe(function() return mq.TLO.InvSlot(slotName).Item.ID() end, 0), 0)
                    return afterId == 0 or afterId ~= beforeId
                end)
                if mq.TLO.Cursor.ID() then pcall(function() mq.cmd('/autoinv') end) end
                didAny = didAny + 1
            end
        end
    end
    if mq.TLO.Window('InventoryWindow').Open() then pcall(function() mq.cmd('/keypress inventory') end) end
    pcall(function() mq.cmd('/keypress CLOSE_INV_BAGS') end)
    log('ScribeStuff finished. Attempted to scribe %d items.', didAny)
end

local function autoGroupCandidates()
    return {
        string.format('%s/../MQ2AutoGroup.ini', mq.configDir),
        string.format('%s/MQ2AutoGroup.ini', mq.configDir),
        'MQ2AutoGroup.ini',
        '../MQ2AutoGroup.ini',
    }
end

local function loadAutoGroups()
    local path
    for _, p in ipairs(autoGroupCandidates()) do
        local f = io.open(p, 'r')
        if f then
            f:close()
            path = p
            break
        end
    end
    if not path then return {} end
    local groups = {}
    local cur = nil
    local f = io.open(path, 'r')
    if not f then return {} end
    for line in f:lines() do
        local s = tostring(line):gsub('^%s+', ''):gsub('%s+$', '')
        if s ~= '' and not s:match('^;') then
            local sec = s:match('^%[(.+)%]$')
            if sec then
                cur = { name = sec }
                groups[#groups+1] = cur
            elseif cur then
                local k, v = s:match('^([^=]+)=(.*)$')
                if k and v then
                    k = k:gsub('^%s+', ''):gsub('%s+$', '')
                    v = v:gsub('^%s+', ''):gsub('%s+$', '')
                    cur[k] = v
                end
            end
        end
    end
    f:close()
    return groups
end

local function doMuleraid()
    local groups = loadAutoGroups()
    local invites = 0
    for _, g in ipairs(groups) do
        local member1 = tostring(g.Member1 or '')
        if member1 ~= '' then
            pcall(function() mq.cmdf('/raidinvite %s', member1) end)
            invites = invites + 1
            mq.delay(100)
        end
    end
    log('muleraid issued %d raid invites', invites)
end

local function doMulegroup()
    local groups = loadAutoGroups()
    local meName = tostring(tloSafe(function() return mq.TLO.Me.CleanName() end, '')):lower()
    local invites = 0
    for _, g in ipairs(groups) do
        local member1 = tostring(g.Member1 or ''):lower()
        if member1 == meName then
            for i = 2, 6 do
                local key = string.format('Member%d', i)
                local who = tostring(g[key] or '')
                if who ~= '' then
                    local inGroup = tloSafe(function() return mq.TLO.Group.Member(who).ID() ~= nil end, false)
                    if not inGroup then
                        pcall(function() mq.cmdf('/invite %s', who) end)
                        invites = invites + 1
                        mq.delay(80)
                    end
                end
            end
        end
    end
    log('mulegroup issued %d group invites', invites)
end

runMapTheZone = function()
    if nowMs() - (state.lastMapPulseAt or 0) < 3000 then return end
    state.lastMapPulseAt = nowMs()
    pcall(function() mq.cmd('/mapfilter all on') end)
    pcall(function() mq.cmd('/mapshow npc') end)
    pcall(function() mq.cmd('/mapfilter radius 400') end)
end

performCustomCall = function()
    if not state.custom.pending then return end
    if nowMs() - (state.custom.lastAt or 0) < 500 then return end
    state.custom.lastAt = nowMs()
    local name = tostring(state.custom.name or ''):lower()
    local param = tostring(state.custom.param or '')
    state.custom.pending = false
    if name == '' then return end

    if name == 'tbltrial' then
        local p = tonumber(param or '')
        local jumpSpots = {
            [1] = {y=556,x=293,z=-75,heading=33},
            [2] = {y=636,x=302,z=-75,heading=32},
            [3] = {y=681,x=345,z=-75,heading=28},
            [4] = {y=600,x=258,z=-75,heading=35},
            [5] = {y=528,x=339,z=-75,heading=25},
        }
        local spot = jumpSpots[p or -1]
        if spot then
            pcall(function() mq.cmdf('/nav locyxz %.2f %.2f %.2f', spot.y, spot.x, spot.z) end)
            waitNavStart(1000)
            waitNavStop(6000)
            pcall(function() mq.cmdf('/face fast heading %.2f', spot.heading) end)
            pcall(function() mq.cmd('/look 128') end)
            mq.delay(200)
            pcall(function() mq.cmd('/useitem rocketeer') end)
            mq.delay(5000, function() return mq.TLO.Me.Casting() ~= nil end)
            mq.delay(7000, function() return mq.TLO.Me.Casting() == nil end)
            pcall(function() mq.cmd('/keypress forward hold') end)
            mq.delay(1000)
            pcall(function() mq.cmd('/keypress forward') end)
            pcall(function() mq.cmd('/look 0') end)
            return
        end
    end

    local composed = '/' .. name .. (param ~= '' and (' ' .. param) or '')
    pcall(function() mq.cmd(composed) end)
end

local function doHalfMoon(radius)
    radius = radius or 40
    local meX = parseNumber(tloSafe(function() return mq.TLO.Me.X() end, 0), 0)
    local meY = parseNumber(tloSafe(function() return mq.TLO.Me.Y() end, 0), 0)
    local r = tonumber(radius) or 40
    local points = {
        {x = meX + r, y = meY},
        {x = meX, y = meY + r},
        {x = meX - r, y = meY},
    }
    for _, p in ipairs(points) do
        pcall(function() mq.cmdf('/nav locyx %.2f %.2f', p.y, p.x) end)
        mq.delay(1000)
    end
end

local function doFullMoon(radius)
    radius = radius or 40
    local meX = parseNumber(tloSafe(function() return mq.TLO.Me.X() end, 0), 0)
    local meY = parseNumber(tloSafe(function() return mq.TLO.Me.Y() end, 0), 0)
    local r = tonumber(radius) or 40
    local points = {
        {x = meX + r, y = meY},
        {x = meX, y = meY + r},
        {x = meX - r, y = meY},
        {x = meX, y = meY - r},
        {x = meX + r, y = meY},
    }
    for _, p in ipairs(points) do
        pcall(function() mq.cmdf('/nav locyx %.2f %.2f', p.y, p.x) end)
        mq.delay(1000)
    end
end

local function bindCommand(line)
    local args = split(line or '', ' ')
    local cmd = tostring(args[1] or ''):lower()
    local alias = {
        addafriend = 'addfriend',
        addtoignore = 'addignore',
        addtopull = 'addpull',
        addmezimmune = 'addimmune',
        assignmainassist = 'changema',
        dofullcircle = 'fullmoon',
        dohalfcircle = 'halfmoon',
        mapthezone = 'lemonmap',
        mulee = 'status',
        muledebug = 'status',
        lemondebug = 'status',
        castdebug = 'debugcast',
    }
    cmd = alias[cmd] or cmd
    if cmd == '' or cmd == 'help' then
        log('Usage: /muleassist [start|stop|pause|resume|reload|status|assist <name>|role <role>|groupcheck|buffmode <on|off>|zombie <on|off>|debug <on|off>]')
        return
    end
    if cmd == 'start' then
        state.paused = false
        return
    end
    if cmd == 'stop' then
        state.running = false
        return
    end
    if cmd == 'pause' then
        state.paused = true
        return
    end
    if cmd == 'resume' then
        state.paused = false
        return
    end
    if cmd == 'reload' then
        loadConfig()
        return
    end
    if cmd == 'status' then
        log('Role:%s MA:%s Paused:%s INI:%s Camp:(%.1f,%.1f,%.1f)', state.role, tostring(state.mainAssist), tostring(state.paused), tostring(state.iniFile), state.camp.x, state.camp.y, state.camp.z)
        log('Pull phase:%s target:%s attempts:%s pullWith:%s range:%s', tostring(state.pull.phase), tostring(state.pull.targetID), tostring(state.pull.attempts), tostring(state.pull.pullWith), tostring(state.pull.range))
        log('Pull reason:%s inCombat:%s XT:%d', tostring(state.pull.lastReason or ''), tostring(boolish(tloSafe(function() return mq.TLO.Me.InCombat() end, false))), getXTHaterCount())
        return
    end
    if cmd == 'assist' and args[2] then
        state.mainAssist = args[2]
        setConfigValue('General', 'MainAssist', args[2])
        return
    end
    if cmd == 'changema' and args[2] then
        state.mainAssist = args[2]
        setConfigValue('General', 'MainAssist', args[2])
        log('MainAssist set to %s', state.mainAssist)
        return
    end
    if cmd == 'role' and args[2] then
        state.role = tostring(args[2]):lower()
        return
    end
    if cmd == 'groupcheck' then
        printGroupCheck()
        return
    end
    if cmd == 'mulecheck' or cmd == 'muleedit' or cmd == 'mulee' then
        bindCommand('status')
        return
    end
    if cmd == 'camp' then
        setCampHere()
        log('Camp set to %.1f %.1f %.1f', state.camp.x, state.camp.y, state.camp.z)
        return
    end
    if cmd == 'buffmode' and args[2] then
        state.buffMode = boolish(args[2])
        return
    end
    if cmd == 'zombie' and args[2] then
        state.zombieMode = boolish(args[2])
        return
    end
    if cmd == 'debug' then
        local explicit = args[2]
        if explicit ~= nil and explicit ~= '' then
            state.debug = boolish(explicit)
        else
            state.debug = not state.debug
        end
        state.debugCast = state.debug
        log('Debug %s', state.debug and 'ON' or 'OFF')
        return
    end
    if cmd == 'changevarint' then
        local section, key, value = args[2], args[3], args[4]
        if section and key and value then
            setConfigValue(section, key, value)
            loadConfig()
        end
        return
    end
    if cmd == 'debugall' then
        state.debug = true
        state.debugCast = true
        bindCommand('togglevariable Debug on')
        bindCommand('togglevariable DebugBuffs on')
        bindCommand('togglevariable DebugDPS on')
        bindCommand('togglevariable DebugCombat on')
        bindCommand('togglevariable DebugHeal on')
        bindCommand('togglevariable DebugMez on')
        bindCommand('togglevariable DebugMove on')
        bindCommand('togglevariable DebugPull on')
        bindCommand('togglevariable DebugPet on')
        return
    end
    if cmd == 'backoff' then
        pcall(function() mq.cmd('/attack off') end)
        pcall(function() mq.cmd('/pet back off') end)
        return
    end
    if cmd == 'burn' then
        runBurns()
        return
    end
    if cmd == 'shakeloose' then
        state.config.General.ReturnToCamp = 0
        state.config.General.ChaseAssist = 0
        stopNavigation()
        pcall(function() mq.cmd('/stick off') end)
        return
    end
    if cmd == 'parse' then
        loadConfig()
        return
    end
    if cmd == 'togglevariable' then
        local key = args[2]
        local mode = args[3] and tostring(args[3]):lower() or nil
        local explicit = nil
        if mode == 'on' then explicit = true elseif mode == 'off' then explicit = false end
        if key then
            toggleConfigKey(key, explicit)
            loadConfig()
        end
        return
    end
    if cmd == 'iniwrite' then
        local section = args[2]
        local key = args[3]
        local value = table.concat(args, ' ', 4)
        if section and key and value and value ~= '' then
            setConfigValue(section, key, value)
            loadConfig()
        end
        return
    end
    if cmd == 'evac' then
        if state.classShort == 'WIZ' then
            castAbility('Exodus', mq.TLO.Me.ID(), true)
        elseif state.classShort == 'DRU' then
            castAbility('Succor', mq.TLO.Me.ID(), true)
        end
        return
    end
    if cmd == 'memmyspells' then
        memMySpells(args[2] or state.iniFile)
        return
    end
    if cmd == 'writemyspells' then
        writeCurrentGemsToIni(args[2] or state.iniFile)
        return
    end
    if cmd == 'memspells' then
        local sub = tostring(args[2] or ''):lower()
        if sub == 'save' then
            writeCurrentGemsToIni(args[3] or state.iniFile)
        end
        return
    end
    if cmd == 'switch' then
        local targetArg = args[2]
        if not targetArg or targetArg == '' then return end
        local id = tonumber(targetArg)
        if id then
            targetByID(id)
        else
            pcall(function() mq.cmdf('/target %s', targetArg) end)
        end
        return
    end
    if cmd == 'switchnow' then
        local rest = table.concat(args, ' ', 2)
        bindCommand('switch '..rest)
        return
    end
    if cmd == 'pull' then
        local targetArg = args[2]
        if targetArg and targetArg ~= '' then
            local id = tonumber(targetArg)
            if id then
                targetByID(id)
            else
                pcall(function() mq.cmdf('/target %s', targetArg) end)
            end
        end
        if targetIsUsable() then
            pcall(function() mq.cmd('/attack on') end)
        end
        return
    end
    if cmd == 'gobacktocamp' then
        navigateToCamp()
        return
    end
    if cmd == 'goback' then
        navigateToCamp()
        return
    end
    if cmd == 'zoneinfo' then
        local zn = tloSafe(function() return mq.TLO.Zone.ShortName() end, 'unknown')
        local id = tloSafe(function() return mq.TLO.Zone.ID() end, 0)
        log('ZoneInfo: %s (%s)', tostring(zn), tostring(id))
        return
    end
    if cmd == 'lemonmap' or cmd == 'mapthezone' then
        state.mapTheZone = not state.mapTheZone
        log('MapTheZone is %s', tostring(state.mapTheZone and 1 or 0))
        return
    end
    if cmd == 'trackmedown' then
        local who = args[2] or state.mainAssist or tloSafe(function() return mq.TLO.Group.MainAssist.Name() end, nil)
        if who and who ~= '' then
            local sid = parseNumber(tloSafe(function() return mq.TLO.Spawn(who).ID() end, 0), 0)
            if sid > 0 then navigateToSpawn(sid) end
        end
        return
    end
    if cmd == 'lockill' then
        local x = tonumber(args[3] or '')
        local y = tonumber(args[4] or '')
        if x and y then
            pcall(function() mq.cmdf('/nav locyx %.2f %.2f', y, x) end)
        end
        return
    end
    if cmd == 'setpullarc' then
        if args[2] then
            setConfigValue('Pull', 'PullArcWidth', args[2])
            loadConfig()
        end
        return
    end
    if cmd == 'halfmoon' then
        doHalfMoon(tonumber(args[2] or '40') or 40)
        return
    end
    if cmd == 'fullmoon' then
        doFullMoon(tonumber(args[2] or '40') or 40)
        return
    end
    if cmd == 'sheepmove' then
        local sid = tonumber(args[2] or '')
        if sid and sid > 0 then
            local sx = parseNumber(tloSafe(function() return mq.TLO.Spawn(sid).X() end, 0), 0)
            local sy = parseNumber(tloSafe(function() return mq.TLO.Spawn(sid).Y() end, 0), 0)
            pcall(function() mq.cmdf('/nav locyx %.2f %.2f', sy, sx) end)
        end
        return
    end
    if cmd == 'shareini' then
        local name = tloSafe(function() return mq.TLO.Me.CleanName() end, '')
        log('ShareIni requested for %s (%s)', tostring(name), tostring(state.iniFile))
        return
    end
    if cmd == 'foreground' or cmd == 'showwindow' then
        local who = args[2]
        if who and who ~= '' then
            pcall(function() mq.cmdf('/foreground %s', who) end)
        else
            local t = tloSafe(function() return mq.TLO.Target.CleanName() end, nil)
            if t then pcall(function() mq.cmdf('/foreground %s', t) end) end
        end
        return
    end
    if cmd == 'groupinvites' then
        doMulegroup()
        return
    end
    if cmd == 'raidinvites' then
        doMuleraid()
        return
    end
    if cmd == 'mulegroup' or cmd == 'muleraid' then
        if cmd == 'mulegroup' then
            doMulegroup()
        else
            doMuleraid()
        end
        return
    end
    if cmd == 'writedebug' then
        local category = args[2] or 'all'
        local seconds = tonumber(args[3] or '60') or 60
        pcall(function() mq.cmdf('/writedebug %s %d', category, seconds) end)
        return
    end
    if cmd == 'cleardebug' then
        local what = args[2] or 'all'
        pcall(function() mq.cmdf('/cleardebug %s', what) end)
        return
    end
    if cmd == 'doevac' then
        bindCommand('evac')
        return
    end
    if cmd == 'rgrez' then
        pcall(function() mq.cmd('/rez') end)
        return
    end
    if cmd == 'ivu' then
        local id = tonumber(args[2] or '')
        if id then targetByID(id) end
        if state.classShort == 'BRD' then
            castAbility('Selo', mq.TLO.Me.ID(), true)
        end
        return
    end
    if cmd == 'rootall' then
        local spell = table.concat(args, ' ', 2)
        if spell == '' then spell = 'Root' end
        local radius = parseNumber(state.config.AE.AERadius, 50)
        local count = parseNumber(tloSafe(function() return mq.TLO.SpawnCount(string.format('npc radius %d zradius 50', radius))() end, 0), 0)
        for i = 1, count do
            local sid = parseNumber(tloSafe(function() return mq.TLO.NearestSpawn(i, string.format('npc radius %d zradius 50', radius)).ID() end, 0), 0)
            if sid > 0 then
                castAbility(spell, sid, true)
            end
        end
        return
    end
    if cmd == 'masspull' then
        local pullSpell = args[2] or 'Melee'
        local n = tonumber(args[3] or '1') or 1
        local minLvl = tonumber(args[4] or '1') or 1
        local maxLvl = tonumber(args[5] or '999') or 999
        local maxDist = tonumber(args[6] or state.config.Pull.MaxRadius or '200') or 200
        local pulledIDs = {}
        for i = 1, n do
            local query = string.format('range %d %d radius %d targetable npc', minLvl, maxLvl, maxDist)
            local sid = parseNumber(tloSafe(function() return mq.TLO.NearestSpawn(i, query).ID() end, 0), 0)
            if sid > 0 then
                pcall(function() mq.cmdf('/nav spawn id %d dist=40', sid) end)
                waitNavStart(5000)
                waitNavStop(40000)
                bindCommand('pull '..tostring(sid))
                if pullSpell:lower() ~= 'melee' then castAbility(pullSpell, sid, true) end
                pulledIDs[#pulledIDs+1] = sid
                mq.delay(400)
            end
        end
        navigateToCamp()
        waitNavStart(2000)
        while boolish(tloSafe(function() return mq.TLO.Navigation.Active() end, false)) do
            local shouldPause = false
            for i = 1, parseNumber(tloSafe(function() return mq.TLO.Me.XTarget() end, 0), 0) do
                local xt = mq.TLO.Me.XTarget(i)
                if xt() and tostring(xt.Type() or ''):lower() == 'npc' then
                    local d = parseNumber(tloSafe(function() return xt.Distance3D() end, 0), 0)
                    if d > 180 then
                        shouldPause = true
                        local xtid = parseNumber(tloSafe(function() return xt.ID() end, 0), 0)
                        if xtid > 0 then
                            targetByID(xtid)
                            mq.delay(1000, function() return mq.TLO.Target.ID() == xtid end)
                            mq.delay(1000, function() return boolish(tloSafe(function() return mq.TLO.Target.BuffsPopulated() end, false)) end)
                            local rooted = boolish(tloSafe(function() return mq.TLO.Target.Rooted() end, false))
                            if not rooted then
                                stopNavigation()
                                mq.delay(5000, function()
                                    local xtd = parseNumber(tloSafe(function() return mq.TLO.Spawn(xtid).Distance3D() end, 999), 999)
                                    return xtd < 100
                                end)
                                navigateToCamp()
                                waitNavStart(1200)
                            end
                        end
                    end
                end
            end
            if not shouldPause then break end
            mq.delay(100)
        end
        return
    end
    if cmd == 'sow' then
        local sid = tonumber(args[2] or '') or mq.TLO.Me.ID()
        castAbility('Spirit of Wolf', sid, true)
        return
    end
    if cmd == 'bardinvis' then
        if state.classShort == 'BRD' then
            iterateList('Buffs', function(entry)
                if tostring(entry.value.ability):lower():find('invis', 1, true) then
                    return castAbility(entry.value.ability, mq.TLO.Me.ID(), true)
                end
                return false
            end)
        end
        return
    end
    if cmd == 'scribestuff' then
        bindScribeStuff()
        return
    end
    if cmd == 'customcall' then
        local callName = args[2]
        local rest = table.concat(args, ' ', 3)
        if callName and callName ~= '' then
            state.custom.name = callName
            state.custom.param = rest
            state.custom.pending = true
        end
        return
    end
    if cmd == 'mulehide' then
        pcall(function() mq.cmd('/hidecorpse all') end)
        return
    end
    if cmd == 'charmthis' then
        local sid = tonumber(args[2] or '')
        if sid and sid > 0 then targetByID(sid) end
        castAbility('Charm', mq.TLO.Target.ID(), true)
        return
    end
    if cmd == 'buffgroup' then
        runBuffs()
        return
    end
    if cmd == 'campfire' then
        if tloSafe(function() return mq.TLO.Zone.ID() end, 0) == 33506 then return end
        pcall(function() mq.cmd('/windowstate FellowshipWnd open') end)
        mq.delay(200)
        pcall(function() mq.cmd('/nomodkey /notify FellowshipWnd FP_Subwindows tabselect 2') end)
        mq.delay(200)
        local campZone = parseNumber(tloSafe(function() return mq.TLO.Me.Fellowship.CampfireZone.ID() end, 0), 0)
        local curZone = parseNumber(tloSafe(function() return mq.TLO.Zone.ID() end, 0), 0)
        if campZone ~= 0 and campZone ~= curZone then
            pcall(function() mq.cmd('/nomodkey /notify FellowshipWnd FP_DestroyCampsite leftmouseup') end)
            mq.delay(5000, function() return mq.TLO.Window('ConfirmationDialogBox').Open() end)
            if mq.TLO.Window('ConfirmationDialogBox').Open() then
                pcall(function() mq.cmd('/nomodkey /notify ConfirmationDialogBox Yes_Button leftmouseup') end)
            end
            mq.delay(1500)
        end
        pcall(function() mq.cmd('/nomodkey /notify FellowshipWnd FP_RefreshList leftmouseup') end)
        mq.delay(200)
        pcall(function() mq.cmd('/nomodkey /notify FellowshipWnd FP_CampsiteKitList listselect 1') end)
        mq.delay(200)
        pcall(function() mq.cmd('/nomodkey /notify FellowshipWnd FP_CreateCampsite leftmouseup') end)
        mq.delay(5000)
        pcall(function() mq.cmd('/windowstate FellowshipWnd close') end)
        return
    end
    if cmd == 'writespells' then
        bindCommand('writemyspells '..tostring(args[2] or state.iniFile))
        return
    end
    if cmd == 'zombiemode' then
        bindCommand('zombie '..tostring(args[2] or 'on'))
        return
    end
    if cmd == 'debugcast' then
        bindCommand('debug '..tostring(args[2] or 'on'))
        state.debugCast = true
        return
    end
    if cmd == 'addfriend' or cmd == 'addpull' or cmd == 'addignore' or cmd == 'addimmune' then
        local val = table.concat(args, ' ', 2)
        if cmd == 'addfriend' then
            local friendName = resolveSpawnNameFromArg(val ~= '' and val or nil, 'pc')
            if friendName and friendName:lower() ~= tostring(mq.TLO.Me.CleanName() or ''):lower() then
                pcall(function() mq.cmdf('/posse add %s', friendName) end)
                pcall(function() mq.cmd('/posse save') end)
                pcall(function() mq.cmd('/posse load') end)
                log('Added friend to posse: %s', friendName)
            else
                log('AddFriend failed: target a PC.')
            end
            return
        end
        local mobName = resolveSpawnNameFromArg(val ~= '' and val or nil, 'npc')
        if not mobName then
            log('%s failed: target/provide a valid NPC.', cmd)
            return
        end
        local key = (cmd == 'addpull' and 'MobsToPull') or (cmd == 'addignore' and 'MobsToIgnore') or 'MezImmune'
        local ok, info = appendZoneList(key, mobName)
        if ok then
            log('%s added %s to %s (%s)', cmd, mobName, key, currentZoneKey())
        elseif info == 'duplicate' then
            log('%s skipped duplicate %s in %s', cmd, mobName, key)
        else
            log('%s failed for %s', cmd, mobName)
        end
        return
    end
    if cmd == 'giveitem' then
        local item = args[2]
        local givee = args[3]
        local qty = tonumber(args[4] or '1') or 1
        if item and givee then
            pcall(function() mq.cmdf('/nomodkey /multiline ; /target %s ; /itemnotify "%s" leftmouseup ; /notify GiveWnd GVW_Give_Button leftmouseup', givee, item) end)
            log('GiveItem requested: %s x%d -> %s', item, qty, givee)
        end
        return
    end
    if cmd == 'collectibles' then
        pcall(function() mq.cmd('/invoke ${FindItem[=Collection].ID}') end)
        log('Collectibles command sent')
        return
    end
end

bindSafe('/muleassist', bindCommand)
bindSafe('/mqp', function(line)
    local mode = tostring(split(line or '', ' ')[1] or ''):lower()
    if mode == 'on' or mode == '1' or mode == 'pause' then
        state.paused = true
    elseif mode == 'off' or mode == '0' or mode == 'resume' then
        state.paused = false
    end
end)
bindSafe('/groupcheck', function() printGroupCheck() end)
bindSafe('/buffmode', function(line) state.buffMode = boolish(split(line or '', ' ')[1] or 'off') end)
bindSafe('/zombie', function(line) state.zombieMode = boolish(split(line or '', ' ')[1] or 'off') end)
bindSafe('/muledebug', function(line)
    local tok = tostring(split(line or '', ' ')[1] or '')
    if tok == '' then
        state.debug = not state.debug
    else
        state.debug = boolish(tok)
    end
    log('Debug %s', state.debug and 'ON' or 'OFF')
end)
bindSafe('/castdebug', function(line)
    local tok = tostring(split(line or '', ' ')[1] or '')
    if tok == '' then
        state.debugCast = not state.debugCast
    else
        state.debugCast = boolish(tok)
    end
    log('CastDebug %s', state.debugCast and 'ON' or 'OFF')
end)
bindSafe('/lemondebug', function()
    log('Debug Role:%s MA:%s Class:%s BuffMode:%s Zombie:%s', state.role, tostring(state.mainAssist), tostring(state.classShort), tostring(state.buffMode), tostring(state.zombieMode))
end)
bindSafe('/evac', function() bindCommand('evac') end)
bindSafe('/changevarint', function(line) bindCommand('changevarint '..(line or '')) end)
bindSafe('/togglevariable', function(line) bindCommand('togglevariable '..(line or '')) end)
bindSafe('/iniwrite', function(line) bindCommand('iniwrite '..(line or '')) end)
bindSafe('/chase', function() toggleConfigKey('ChaseAssist') loadConfig() end)
bindSafe('/chaseon', function() toggleConfigKey('ChaseAssist', true) loadConfig() end)
bindSafe('/chaseoff', function() toggleConfigKey('ChaseAssist', false) loadConfig() end)
bindSafe('/returntocamp', function() toggleConfigKey('ReturnToCamp') loadConfig() end)
bindSafe('/camphere', function(line)
    local a = split(line or '', ' ')
    local explicit = nil
    if a[1] then
        local s = tostring(a[1]):lower()
        if s == 'on' or s == '1' then explicit = true end
        if s == 'off' or s == '0' then explicit = false end
    end
    toggleConfigKey('ReturnToCamp', explicit)
    if explicit ~= false then setCampHere() end
    loadConfig()
end)
bindSafe('/buffson', function() toggleConfigKey('BuffsOn') loadConfig() end)
bindSafe('/healson', function() toggleConfigKey('HealsOn') loadConfig() end)
bindSafe('/dpson', function(line)
    local a = split(line or '', ' ')
    if a[1] then setConfigValue('DPS', 'DPSOn', tonumber(a[1]) or a[1]) else toggleConfigKey('DPSOn') end
    loadConfig()
end)
bindSafe('/meleeon', function() toggleConfigKey('MeleeOn') loadConfig() end)
bindSafe('/peton', function() toggleConfigKey('PetOn') loadConfig() end)
bindSafe('/autorezon', function() toggleConfigKey('AutoRezOn') loadConfig() end)
bindSafe('/rebuffon', function() toggleConfigKey('RebuffOn') loadConfig() end)
bindSafe('/mezon', function(line)
    local a = split(line or '', ' ')
    if a[1] then setConfigValue('Mez', 'MezOn', tonumber(a[1]) or a[1]) end
    loadConfig()
end)
bindSafe('/campradius', function(line)
    local v = tonumber(split(line or '', ' ')[1] or '')
    if v then setConfigValue('General', 'CampRadius', v) loadConfig() end
end)
bindSafe('/chasedistance', function(line)
    local v = tonumber(split(line or '', ' ')[1] or '')
    if v then setConfigValue('General', 'ChaseDistance', v) loadConfig() end
end)
bindSafe('/assistat', function(line)
    local v = tonumber(split(line or '', ' ')[1] or '')
    if v then setConfigValue('Melee', 'AssistAt', v) loadConfig() end
end)
bindSafe('/medstart', function(line)
    local v = tonumber(split(line or '', ' ')[1] or '')
    if v then setConfigValue('General', 'MedStart', v) loadConfig() end
end)
bindSafe('/meleedistance', function(line)
    local v = tonumber(split(line or '', ' ')[1] or '')
    if v then setConfigValue('Melee', 'MeleeDistance', v) loadConfig() end
end)
bindSafe('/maxradius', function(line)
    local v = tonumber(split(line or '', ' ')[1] or '')
    if v then setConfigValue('Pull', 'MaxRadius', v) loadConfig() end
end)
bindSafe('/mulecheck', function() bindCommand('status') end)
bindSafe('/mulee', function() bindCommand('status') end)
bindSafe('/burn', function() runBurns() end)
bindSafe('/backoff', function() pcall(function() mq.cmd('/attack off') end) end)
bindSafe('/memmyspells', function(line) bindCommand('memmyspells '..(line or '')) end)
bindSafe('/memspells', function(line) bindCommand('memspells '..(line or '')) end)
bindSafe('/writemyspells', function(line) bindCommand('writemyspells '..(line or '')) end)
bindSafe('/switch', function(line) bindCommand('switch '..(line or '')) end)
bindSafe('/pull', function(line) bindCommand('pull '..(line or '')) end)
bindSafe('/gobacktocamp', function() bindCommand('gobacktocamp') end)
bindSafe('/zoneinfo', function() bindCommand('zoneinfo') end)
bindSafe('/trackmedown', function(line) bindCommand('trackmedown '..(line or '')) end)
bindSafe('/lockill', function(line) bindCommand('lockill '..(line or '')) end)
bindSafe('/shareini', function() bindCommand('shareini') end)
bindSafe('/showwindow', function(line) bindCommand('showwindow '..(line or '')) end)
bindSafe('/groupinvites', function() bindCommand('groupinvites') end)
bindSafe('/raidinvites', function() bindCommand('raidinvites') end)
bindSafe('/doevac', function() bindCommand('doevac') end)
bindSafe('/writedebug', function(line) bindCommand('writedebug '..(line or '')) end)
bindSafe('/cleardebug', function(line) bindCommand('cleardebug '..(line or '')) end)
bindSafe('/ivu', function(line) bindCommand('ivu '..(line or '')) end)
bindSafe('/rootall', function(line) bindCommand('rootall '..(line or '')) end)
bindSafe('/sow', function(line) bindCommand('sow '..(line or '')) end)
bindSafe('/bardinvis', function() bindCommand('bardinvis') end)
bindSafe('/giveitem', function(line) bindCommand('giveitem '..(line or '')) end)
bindSafe('/setae', function(line) bindCommand('iniwrite AE '..(line or '')) end)
bindSafe('/setaggro', function(line) bindCommand('iniwrite Aggro '..(line or '')) end)
bindSafe('/setbuffs', function(line) bindCommand('iniwrite Buffs '..(line or '')) end)
bindSafe('/setburn', function(line) bindCommand('iniwrite Burn '..(line or '')) end)
bindSafe('/setcure', function(line) bindCommand('iniwrite Cures '..(line or '')) end)
bindSafe('/setdps', function(line) bindCommand('iniwrite DPS '..(line or '')) end)
bindSafe('/setheals', function(line) bindCommand('iniwrite Heals '..(line or '')) end)
bindSafe('/afktoolson', function(line) bindCommand('changevarint AFKTools AFKToolsOn '..(line or '1')) end)
bindSafe('/autofireon', function() bindCommand('togglevariable AutoFireOn') end)
bindSafe('/buffwhilechase', function() bindCommand('togglevariable BuffWhileChasing') end)
bindSafe('/conditions', function(line) bindCommand('togglevariable Conditions '..(line or '')) end)
bindSafe('/conditionson', function() bindCommand('togglevariable Conditions on') end)
bindSafe('/conditionsoff', function() bindCommand('togglevariable Conditions off') end)
bindSafe('/debug', function() bindCommand('togglevariable Debug') end)
bindSafe('/debugbuffs', function() bindCommand('togglevariable DebugBuffs') end)
bindSafe('/debugbuff', function() bindCommand('togglevariable DebugBuffs') end)
bindSafe('/debugcombat', function() bindCommand('togglevariable DebugCombat') end)
bindSafe('/debugdps', function() bindCommand('togglevariable DebugDPS') end)
bindSafe('/debugheal', function() bindCommand('togglevariable DebugHeal') end)
bindSafe('/debugmez', function() bindCommand('togglevariable DebugMez') end)
bindSafe('/debugmove', function() bindCommand('togglevariable DebugMove') end)
bindSafe('/debugpull', function() bindCommand('togglevariable DebugPull') end)
bindSafe('/debugrk', function() bindCommand('togglevariable DebugRK') end)
bindSafe('/debugpet', function() bindCommand('togglevariable DebugPet') end)
bindSafe('/dpsinterval', function(line) bindCommand('changevarint DPS DPSInterval '..(line or '2')) end)
bindSafe('/dpsmeter', function() bindCommand('togglevariable DPSMeter') end)
bindSafe('/dpsskip', function(line) bindCommand('changevarint DPS DPSSkip '..(line or '1')) end)
bindSafe('/dpsspam', function() bindCommand('togglevariable DPSSpam') end)
bindSafe('/dpswrite', function() bindCommand('togglevariable DPSWriteOn') end)
bindSafe('/interrupton', function() bindCommand('togglevariable CastingInterruptOn') end)
bindSafe('/looton', function(line) bindCommand('changevarint General LootOn '..(line or '1')) end)
bindSafe('/maxzrange', function(line) bindCommand('changevarint Pull MaxZRange '..(line or '50')) end)
bindSafe('/mercassistat', function(line) bindCommand('changevarint Merc MercAssistAt '..(line or '92')) end)
bindSafe('/movewhenhit', function() bindCommand('togglevariable MoveWhenHit') end)
bindSafe('/pethold', function() bindCommand('togglevariable PetHoldOn') end)
bindSafe('/pettoyson', function() bindCommand('togglevariable PetToysOn') end)
bindSafe('/pettoysplz', function() pcall(function() mq.cmd('/pet toys') end) end)
bindSafe('/scatteron', function() bindCommand('togglevariable Scatter') end)
bindSafe('/ktdismount', function() pcall(function() mq.cmd('/dismount') end) end)
bindSafe('/ktdoor', function(line) pcall(function() mq.cmd('/doortarget') mq.cmd('/click left door') end) end)
bindSafe('/kthail', function(line) pcall(function() mq.cmd('/keypress HAIL') end) end)
bindSafe('/ktinvite', function(line) if line and line ~= '' then pcall(function() mq.cmdf('/invite %s', line) end) end end)
bindSafe('/ktsay', function(line) if line and line ~= '' then pcall(function() mq.cmdf('/say %s', line) end) end end)
bindSafe('/kttarget', function(line) if line and line ~= '' then pcall(function() mq.cmdf('/target %s', line) end) end end)
bindSafe('/mulecollect', function() bindCommand('collectibles') end)
bindSafe('/mulecolelct', function() bindCommand('collectibles') end)
bindSafe('/collectibles', function()
    pcall(function() mq.cmd('/invoke ${FindItem[=Collection].ID}') end)
    log('Collectibles command sent')
end)
bindSafe('/addfriend', function(line) bindCommand('addfriend '..(line or '')) end)
bindSafe('/addpull', function(line) bindCommand('addpull '..(line or '')) end)
bindSafe('/addignore', function(line) bindCommand('addignore '..(line or '')) end)
bindSafe('/addimmune', function(line) bindCommand('addimmune '..(line or '')) end)
bindSafe('/buffgroup', function() bindCommand('buffgroup') end)
bindSafe('/campfire', function() bindCommand('campfire') end)
bindSafe('/debugall', function() bindCommand('debugall') end)
bindSafe('/masspull', function(line) bindCommand('masspull '..(line or '')) end)
bindSafe('/muleedit', function() bindCommand('muleedit') end)
bindSafe('/parse', function(line) bindCommand('parse '..(line or '')) end)
bindSafe('/switchnow', function(line) bindCommand('switchnow '..(line or '')) end)
bindSafe('/writespells', function(line) bindCommand('writespells '..(line or '')) end)
bindSafe('/halfmoon', function(line) bindCommand('halfmoon '..(line or '')) end)
bindSafe('/fullmoon', function(line) bindCommand('fullmoon '..(line or '')) end)
bindSafe('/sheepmove', function(line) bindCommand('sheepmove '..(line or '')) end)
bindSafe('/changema', function(line) bindCommand('changema '..(line or '')) end)
bindSafe('/goback', function() bindCommand('goback') end)
bindSafe('/customcall', function(line) bindCommand('customcall '..(line or '')) end)
bindSafe('/mulehide', function(line) bindCommand('mulehide '..(line or '')) end)
bindSafe('/charmthis', function(line) bindCommand('charmthis '..(line or '')) end)
bindSafe('/rgrez', function() bindCommand('rgrez') end)
bindSafe('/zombiemode', function(line) bindCommand('zombiemode '..(line or '')) end)
bindSafe('/debugcast', function(line) bindCommand('debugcast '..(line or '')) end)
bindSafe('/muleraid', function() bindCommand('muleraid') end)
bindSafe('/mulegroup', function() bindCommand('mulegroup') end)
bindSafe('/lemonmap', function(line) bindCommand('lemonmap '..(line or '')) end)
bindSafe('/scribestuff', function() bindCommand('scribestuff') end)

local function initialize(scriptArgs)
    state.classShort = tloSafe(function() return mq.TLO.Me.Class.ShortName() end, 'WAR')
    state.class = CLASS_CAPS[state.classShort] or CLASS_CAPS.WAR
    state.iniFile = sanitizeIniPath(findIniFile())
    state.lastZoneID = tloSafe(function() return mq.TLO.Zone.ID() end, 0)

    local argv = split(scriptArgs or '', ' ')
    local idx = 1
    if argv[idx] and argv[idx] ~= '' then
        local roleArg = tostring(argv[idx]):lower()
        if roleArg == 'assist' or roleArg == 'tank' or roleArg == 'puller' or roleArg == 'pullertank' or roleArg == 'pullerpettank' or roleArg == 'hunter' or roleArg == 'hunterpettank' then
            state.role = roleArg
        end
    end
    if argv[idx + 1] and argv[idx + 1] ~= '' then
        state.mainAssist = argv[idx + 1]
    end

    loadConfig()
    setCampHere()
    log('Loaded %s as %s (%s)', state.iniFile, state.role, state.class.name)
end

local function shutdown()
    unbindSafe('/muleassist')
    unbindSafe('/mqp')
    unbindSafe('/groupcheck')
    unbindSafe('/buffmode')
    unbindSafe('/zombie')
    unbindSafe('/muledebug')
    unbindSafe('/castdebug')
    unbindSafe('/lemondebug')
    unbindSafe('/evac')
    unbindSafe('/changevarint')
    unbindSafe('/togglevariable')
    unbindSafe('/iniwrite')
    unbindSafe('/chase')
    unbindSafe('/chaseon')
    unbindSafe('/chaseoff')
    unbindSafe('/returntocamp')
    unbindSafe('/camphere')
    unbindSafe('/buffson')
    unbindSafe('/healson')
    unbindSafe('/dpson')
    unbindSafe('/meleeon')
    unbindSafe('/peton')
    unbindSafe('/autorezon')
    unbindSafe('/rebuffon')
    unbindSafe('/mezon')
    unbindSafe('/campradius')
    unbindSafe('/chasedistance')
    unbindSafe('/assistat')
    unbindSafe('/medstart')
    unbindSafe('/meleedistance')
    unbindSafe('/maxradius')
    unbindSafe('/mulecheck')
    unbindSafe('/mulee')
    unbindSafe('/burn')
    unbindSafe('/backoff')
    unbindSafe('/memmyspells')
    unbindSafe('/memspells')
    unbindSafe('/writemyspells')
    unbindSafe('/switch')
    unbindSafe('/pull')
    unbindSafe('/gobacktocamp')
    unbindSafe('/zoneinfo')
    unbindSafe('/trackmedown')
    unbindSafe('/lockill')
    unbindSafe('/shareini')
    unbindSafe('/showwindow')
    unbindSafe('/groupinvites')
    unbindSafe('/raidinvites')
    unbindSafe('/doevac')
    unbindSafe('/writedebug')
    unbindSafe('/cleardebug')
    unbindSafe('/ivu')
    unbindSafe('/rootall')
    unbindSafe('/sow')
    unbindSafe('/bardinvis')
    unbindSafe('/giveitem')
    unbindSafe('/setae')
    unbindSafe('/setaggro')
    unbindSafe('/setbuffs')
    unbindSafe('/setburn')
    unbindSafe('/setcure')
    unbindSafe('/setdps')
    unbindSafe('/setheals')
    unbindSafe('/afktoolson')
    unbindSafe('/autofireon')
    unbindSafe('/buffwhilechase')
    unbindSafe('/conditions')
    unbindSafe('/conditionson')
    unbindSafe('/conditionsoff')
    unbindSafe('/debug')
    unbindSafe('/debugbuffs')
    unbindSafe('/debugbuff')
    unbindSafe('/debugcombat')
    unbindSafe('/debugdps')
    unbindSafe('/debugheal')
    unbindSafe('/debugmez')
    unbindSafe('/debugmove')
    unbindSafe('/debugpull')
    unbindSafe('/debugrk')
    unbindSafe('/debugpet')
    unbindSafe('/dpsinterval')
    unbindSafe('/dpsmeter')
    unbindSafe('/dpsskip')
    unbindSafe('/dpsspam')
    unbindSafe('/dpswrite')
    unbindSafe('/interrupton')
    unbindSafe('/looton')
    unbindSafe('/maxzrange')
    unbindSafe('/mercassistat')
    unbindSafe('/movewhenhit')
    unbindSafe('/pethold')
    unbindSafe('/pettoyson')
    unbindSafe('/pettoysplz')
    unbindSafe('/scatteron')
    unbindSafe('/ktdismount')
    unbindSafe('/ktdoor')
    unbindSafe('/kthail')
    unbindSafe('/ktinvite')
    unbindSafe('/ktsay')
    unbindSafe('/kttarget')
    unbindSafe('/mulecollect')
    unbindSafe('/mulecolelct')
    unbindSafe('/collectibles')
    unbindSafe('/addfriend')
    unbindSafe('/addpull')
    unbindSafe('/addignore')
    unbindSafe('/addimmune')
    unbindSafe('/buffgroup')
    unbindSafe('/campfire')
    unbindSafe('/debugall')
    unbindSafe('/masspull')
    unbindSafe('/muleedit')
    unbindSafe('/parse')
    unbindSafe('/switchnow')
    unbindSafe('/writespells')
    unbindSafe('/halfmoon')
    unbindSafe('/fullmoon')
    unbindSafe('/sheepmove')
    unbindSafe('/changema')
    unbindSafe('/goback')
    unbindSafe('/customcall')
    unbindSafe('/mulehide')
    unbindSafe('/charmthis')
    unbindSafe('/rgrez')
    unbindSafe('/zombiemode')
    unbindSafe('/debugcast')
    unbindSafe('/muleraid')
    unbindSafe('/mulegroup')
    unbindSafe('/lemonmap')
    unbindSafe('/scribestuff')
    log('Stopped')
end

initialize(...)

while state.running do
    mq.doevents()
    if canAct() then
        local ok, err = pcall(pulse)
        if not ok then
            log('Pulse error: %s', tostring(err))
            mq.delay(250)
        end
    end
    mq.delay(TICK_MS)
end

shutdown()

