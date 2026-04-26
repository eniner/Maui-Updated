local mq = require('mq')
require('ImGui')
print('[MAUI] Loaded patched build 2026-03-10b')

-- Some client builds do not ship mq.PackageMan. Fall back to plain require('lfs').
do
    local okPackageMan, PackageMan = pcall(require, 'mq.PackageMan')
    if okPackageMan and PackageMan and PackageMan.Require then
        PackageMan.Require('luafilesystem', 'lfs', 'Failed to install or load lfs.dll. Check the FAQ at https://www.redguides.com/community/resources/maui-muleassist-ui.2207/field?field=faq')
    else
        local okLfs = pcall(require, 'lfs')
        if not okLfs then
            print('\at[\ax\ayMAUI\ax\at]\ax \arERROR: luafilesystem (lfs) is missing, and mq.PackageMan is unavailable on this MQ build.\ax')
            return
        end
    end
end

local LIP = require('lib.LIP')
local lfs = require('lfs')
local globals = require('globals')
local utils = require('maui.utils')
local filedialog = require('lib.imguifiledialog')
local cache = require('lib.cache')

globals.CurrentSchema = 'ma'
globals.Schema = require('schemas.'..globals.CurrentSchema)

-- Animations for drawing spell/item icons
local animSpellIcons = mq.FindTextureAnimation('A_SpellIcons')
local animItems = mq.FindTextureAnimation('A_DragItem')
-- Blue and yellow icon border textures
local animBlueWndPieces = mq.FindTextureAnimation('BlueIconBackground')
animBlueWndPieces:SetTextureCell(1)
local animYellowWndPieces = mq.FindTextureAnimation('YellowIconBackground')
animYellowWndPieces:SetTextureCell(1)
local animRedWndPieces = mq.FindTextureAnimation('RedIconBackground')
animRedWndPieces:SetTextureCell(1)

-- UI State
local open = true
local shouldDrawUI = true
local terminate = false
local initialRun = true
local leftPanelDefaultWidth = 150
local leftPanelWidth = 150
local ui_main_tab = 'UI'
local hide_ini_path = false

local selectedListItem = {nil, 0} -- {key, index}
local selectedUpgrade = nil
local selectedSection = 'General' -- Left hand menu selected item
local pendingConfigTab = nil
local pendingMainTab = nil
local bottomActionMsg = ''
local showAdvancedTabs = false
local autoMemAfterRetune = false
local isDirty = false
local lastSaveLabel = 'Never'
local lastSavedFingerprint = ''
local pendingUnsavedAction = nil
local pendingUnsavedFile = nil
local pendingStartWarnings = nil
local actionLastAt = {}
local integrationSourceRoot = 'C:/Users/E9ine/Downloads'
local integrationAutoSync = true
local actionCooldowns = {
    memspells = 1.0,
    savegems = 1.0,
    upgrades = 1.5,
    downgrades = 1.5,
    preflight = 0.8,
    start = 1.0,
    pause = 0.5,
    resume = 0.5,
    endmacro = 0.5,
    runtool = 0.8,
    stoptool = 0.8,
}

local tloCache = cache:new(300, 300)

globals.MyServer = mq.TLO.EverQuest.Server()
globals.MyName = mq.TLO.Me.CleanName()
globals.MyLevel = mq.TLO.Me.Level()
globals.MyClass = mq.TLO.Me.Class.ShortName():lower()

globals.MAUI_INI = ('%s/%s_%s.ini'):format(mq.configDir, globals.MyServer, globals.MyName)
local maui_ini_key = 'MAUI'
if utils.FileExists(globals.MAUI_INI) then
    globals.MAUI_Config = LIP.load(globals.MAUI_INI, false)
end
if not globals.MAUI_Config or not globals.MAUI_Config[maui_ini_key] or not globals.MAUI_Config[maui_ini_key]['StartCommand'] then
    globals.MAUI_Config = {[maui_ini_key] = {['StartCommand'] = globals.Schema['StartCommands'][1], ['Theme'] = 'template', ['AutoMemRetune'] = false,}}
end
if globals.MAUI_Config[maui_ini_key]['AutoMemRetune'] ~= nil then
    autoMemAfterRetune = utils.InitCheckBoxValue(globals.MAUI_Config[maui_ini_key]['AutoMemRetune'])
end

local selected_start_command = nil
for _,startcommand in ipairs(globals.Schema['StartCommands']) do
    if startcommand == globals.MAUI_Config[maui_ini_key]['StartCommand'] then
        selected_start_command = startcommand
    end
end
if not selected_start_command then
    if globals.MAUI_Config[maui_ini_key]['StartCommand'] then
        selected_start_command = 'custom'
    else
        selected_start_command = globals.Schema['StartCommands'][1]
    end
end

-- Storage for spell/AA/disc picker
local spells, altAbilities, discs = {categories={}},{types={}},{categories={}}
local aatypes = {'General','Archtype','Class','Special','Focus','Merc'}

local useRankNames = false
local typeWarningDebug = false
local uniformButtonWidth = 94
local activeThemeKey = 'template'

-- GMConsole-style theme palette, with current MAUI style preserved as template.
local uiThemes = {
    ['template'] = {
        windowBg = {0.03, 0.05, 0.10, 1.00},
        titleBg = {0.02, 0.03, 0.07, 1.00},
        titleBgActive = {0.03, 0.05, 0.12, 1.00},
        button = {0.10, 0.18, 0.31, 0.95},
        buttonHovered = {0.16, 0.27, 0.44, 1.00},
        buttonActive = {0.21, 0.33, 0.52, 1.00},
        frameBg = {0.09, 0.15, 0.26, 0.95},
        frameBgHovered = {0.14, 0.22, 0.36, 1.00},
        header = {0.10, 0.18, 0.31, 0.95},
        text = {1.00, 0.95, 0.20, 1.00},
        border = {0.74, 0.66, 0.34, 0.95},
        separator = {0.44, 0.52, 0.72, 0.90},
    },
    ['neon_purple'] = {
        windowBg = {0.05, 0.05, 0.05, 0.95},
        titleBg = {0.1, 0.05, 0.15, 1.0},
        titleBgActive = {0.3, 0.1, 0.4, 1.0},
        button = {0.5, 0.1, 0.7, 1.0},
        buttonHovered = {0.7, 0.2, 0.9, 1.0},
        buttonActive = {0.4, 0.05, 0.6, 1.0},
        frameBg = {0.15, 0.1, 0.2, 1.0},
        frameBgHovered = {0.25, 0.15, 0.3, 1.0},
        header = {0.4, 0.15, 0.55, 1.0},
        text = {0.95, 0.85, 1.0, 1.0},
        border = {0.6, 0.2, 0.8, 0.5},
        separator = {0.5, 0.2, 0.7, 0.8},
    },
    ['cyber_blue'] = {
        windowBg = {0.02, 0.02, 0.08, 0.95},
        titleBg = {0.05, 0.1, 0.2, 1.0},
        titleBgActive = {0.1, 0.3, 0.5, 1.0},
        button = {0.1, 0.4, 0.8, 1.0},
        buttonHovered = {0.2, 0.5, 0.95, 1.0},
        buttonActive = {0.05, 0.3, 0.6, 1.0},
        frameBg = {0.1, 0.15, 0.25, 1.0},
        frameBgHovered = {0.15, 0.25, 0.35, 1.0},
        header = {0.15, 0.4, 0.65, 1.0},
        text = {0.85, 0.95, 1.0, 1.0},
        border = {0.2, 0.6, 0.9, 0.5},
        separator = {0.2, 0.5, 0.8, 0.8},
    },
    ['toxic_green'] = {
        windowBg = {0.02, 0.05, 0.02, 0.95},
        titleBg = {0.05, 0.15, 0.05, 1.0},
        titleBgActive = {0.1, 0.4, 0.1, 1.0},
        button = {0.2, 0.7, 0.2, 1.0},
        buttonHovered = {0.3, 0.9, 0.3, 1.0},
        buttonActive = {0.15, 0.5, 0.15, 1.0},
        frameBg = {0.1, 0.2, 0.1, 1.0},
        frameBgHovered = {0.15, 0.3, 0.15, 1.0},
        header = {0.2, 0.6, 0.2, 1.0},
        text = {0.85, 1.0, 0.85, 1.0},
        border = {0.3, 0.8, 0.3, 0.5},
        separator = {0.25, 0.7, 0.25, 0.8},
    },
    ['hot_pink'] = {
        windowBg = {0.08, 0.02, 0.05, 0.95},
        titleBg = {0.2, 0.05, 0.1, 1.0},
        titleBgActive = {0.5, 0.1, 0.3, 1.0},
        button = {0.9, 0.2, 0.5, 1.0},
        buttonHovered = {1.0, 0.4, 0.7, 1.0},
        buttonActive = {0.7, 0.1, 0.4, 1.0},
        frameBg = {0.2, 0.1, 0.15, 1.0},
        frameBgHovered = {0.3, 0.15, 0.25, 1.0},
        header = {0.7, 0.15, 0.4, 1.0},
        text = {1.0, 0.85, 0.95, 1.0},
        border = {0.9, 0.3, 0.6, 0.5},
        separator = {0.8, 0.25, 0.5, 0.8},
    },
    ['orange_blaze'] = {
        windowBg = {0.05, 0.03, 0.0, 0.95},
        titleBg = {0.15, 0.08, 0.0, 1.0},
        titleBgActive = {0.4, 0.2, 0.0, 1.0},
        button = {0.9, 0.5, 0.1, 1.0},
        buttonHovered = {1.0, 0.6, 0.2, 1.0},
        buttonActive = {0.7, 0.4, 0.05, 1.0},
        frameBg = {0.2, 0.12, 0.05, 1.0},
        frameBgHovered = {0.3, 0.18, 0.08, 1.0},
        header = {0.7, 0.4, 0.1, 1.0},
        text = {1.0, 0.95, 0.85, 1.0},
        border = {0.9, 0.5, 0.2, 0.5},
        separator = {0.8, 0.45, 0.15, 0.8},
    },
    ['ice_blue'] = {
        windowBg = {0.02, 0.05, 0.08, 0.95},
        titleBg = {0.05, 0.12, 0.18, 1.0},
        titleBgActive = {0.1, 0.25, 0.4, 1.0},
        button = {0.2, 0.6, 0.8, 1.0},
        buttonHovered = {0.3, 0.75, 0.95, 1.0},
        buttonActive = {0.15, 0.5, 0.65, 1.0},
        frameBg = {0.1, 0.18, 0.25, 1.0},
        frameBgHovered = {0.15, 0.25, 0.35, 1.0},
        header = {0.2, 0.5, 0.7, 1.0},
        text = {0.9, 0.98, 1.0, 1.0},
        border = {0.3, 0.7, 0.9, 0.5},
        separator = {0.25, 0.65, 0.85, 0.8},
    },
    ['matrix_hack'] = {
        windowBg = {0.0, 0.0, 0.0, 0.98},
        titleBg = {0.0, 0.08, 0.0, 1.0},
        titleBgActive = {0.0, 0.25, 0.0, 1.0},
        button = {0.0, 0.5, 0.0, 1.0},
        buttonHovered = {0.0, 0.7, 0.0, 1.0},
        buttonActive = {0.0, 0.35, 0.0, 1.0},
        frameBg = {0.0, 0.12, 0.0, 1.0},
        frameBgHovered = {0.0, 0.2, 0.0, 1.0},
        header = {0.0, 0.4, 0.0, 1.0},
        text = {0.0, 1.0, 0.0, 1.0},
        border = {0.0, 0.6, 0.0, 0.7},
        separator = {0.0, 0.5, 0.0, 0.9},
    },
    ['term_hack'] = {
        windowBg = {0.0, 0.02, 0.0, 0.98},
        titleBg = {0.0, 0.1, 0.05, 1.0},
        titleBgActive = {0.0, 0.3, 0.15, 1.0},
        button = {0.0, 0.6, 0.3, 1.0},
        buttonHovered = {0.0, 0.8, 0.4, 1.0},
        buttonActive = {0.0, 0.45, 0.22, 1.0},
        frameBg = {0.0, 0.15, 0.08, 1.0},
        frameBgHovered = {0.0, 0.25, 0.12, 1.0},
        header = {0.0, 0.5, 0.25, 1.0},
        text = {0.2, 1.0, 0.6, 1.0},
        border = {0.0, 0.7, 0.35, 0.7},
        separator = {0.0, 0.6, 0.3, 0.9},
    },
}

local themeOrder = {
    'template',
    'neon_purple',
    'cyber_blue',
    'toxic_green',
    'hot_pink',
    'orange_blaze',
    'ice_blue',
    'matrix_hack',
    'term_hack',
}

local themeLabels = {
    template = 'Template',
    neon_purple = 'Neon Purple',
    cyber_blue = 'Cyber Blue',
    toxic_green = 'Toxic Green',
    hot_pink = 'Hot Pink',
    orange_blaze = 'Orange Blaze',
    ice_blue = 'Ice Blue',
    matrix_hack = 'Matrix Hack',
    term_hack = 'Term Hack',
}

local DrawPanelHeader
local ReloadINIFromDisk

local function NormalizeThemeKey(themeKey)
    local k = tostring(themeKey or ''):lower()
    if k == '' or k == 'default' then return 'template' end
    if k == 'red' then return 'cyber_blue' end
    if uiThemes[k] then return k end
    return 'template'
end

local currentThemeIndex = 1
activeThemeKey = NormalizeThemeKey(globals.MAUI_Config[maui_ini_key]['Theme'] or globals.Theme or 'template')
for i, key in ipairs(themeOrder) do
    if key == activeThemeKey then
        currentThemeIndex = i
        break
    end
end
globals.Theme = activeThemeKey

local TABLE_FLAGS = bit32.bor(ImGuiTableFlags.Hideable, ImGuiTableFlags.RowBg, ImGuiTableFlags.ScrollY, ImGuiTableFlags.BordersOuter)

--local customSections = require('ma.addons.'..globals.CurrentSchema)
local ok, customSections = pcall(require, 'addons.'..globals.CurrentSchema)
if not ok then customSections = nil end

local function SaveMAUIConfig()
    -- Reload the maui.ini before saving to try and prevent writing stale data
    local tmpStartCommand = globals.MAUI_Config[maui_ini_key]['StartCommand']
    local tmpTheme = NormalizeThemeKey(themeOrder[currentThemeIndex] or activeThemeKey)
    local tmpAutoMemRetune = autoMemAfterRetune
    if utils.FileExists(globals.MAUI_INI) then
        globals.MAUI_Config = LIP.load(globals.MAUI_INI, false)
    else
        globals.MAUI_Config = {}
    end
    globals.MAUI_Config[maui_ini_key] = {['StartCommand'] = tmpStartCommand, ['INIFile'] = globals.INIFile, ['Theme'] = tmpTheme, ['AutoMemRetune'] = tmpAutoMemRetune}
    LIP.save_simple(globals.MAUI_INI, globals.MAUI_Config)
end

local function SortedKeys(tbl)
    local keys = {}
    if type(tbl) ~= 'table' then return keys end
    for k,_ in pairs(tbl) do
        table.insert(keys, tostring(k))
    end
    table.sort(keys)
    return keys
end

local function ComputeConfigFingerprint()
    if type(globals.Config) ~= 'table' then return '' end
    local parts = {}
    for _, section in ipairs(SortedKeys(globals.Config)) do
        table.insert(parts, '['..section..']')
        local sectionData = globals.Config[section]
        if type(sectionData) == 'table' then
            for _, key in ipairs(SortedKeys(sectionData)) do
                local value = sectionData[key]
                table.insert(parts, key..'='..tostring(value))
            end
        else
            table.insert(parts, tostring(sectionData))
        end
    end
    return table.concat(parts, '\n')
end

local function FindExistingMAProfile()
    local cfgDir = mq.configDir
    local best = nil
    local bestTime = 0
    for file in lfs.dir(cfgDir) do
        if file:match('^MuleAssist_.*_80%.ini$') or file:match('^MuleAssist_.*_%d+%.ini$') then
            local full = cfgDir .. '/' .. file
            if utils.FileExists(full) then
                local attr = lfs.attributes(full)
                local mod = (attr and attr.modification) or 0
                if mod > bestTime then
                    best = file
                    bestTime = mod
                end
            end
        end
    end
    return best
end

local function MarkConfigClean()
    lastSavedFingerprint = ComputeConfigFingerprint()
    isDirty = false
    lastSaveLabel = os.date('%H:%M:%S')
end

local function RefreshDirtyState()
    local current = ComputeConfigFingerprint()
    if lastSavedFingerprint == '' then
        lastSavedFingerprint = current
        isDirty = false
        return
    end
    isDirty = (current ~= lastSavedFingerprint)
end

local function TryBeginAction(actionName)
    local now = os.clock()
    local cooldown = actionCooldowns[actionName] or 1.0
    local lastAt = actionLastAt[actionName] or -999
    if (now - lastAt) < cooldown then
        bottomActionMsg = string.format('%s: wait %.1fs', actionName, cooldown - (now - lastAt))
        return false
    end
    actionLastAt[actionName] = now
    return true
end

local function NormalizePath(path)
    return tostring(path or ''):gsub('\\', '/')
end

local function EnsureDirectory(path)
    local normalized = NormalizePath(path)
    if normalized == '' then return false end
    local current = ''
    local prefix = ''
    local drive = normalized:match('^([A-Za-z]:)')
    if drive then
        prefix = drive
        normalized = normalized:sub(3)
        current = prefix
    end
    for part in normalized:gmatch('[^/]+') do
        if current == '' then
            current = part
        else
            current = current .. '/' .. part
        end
        if not lfs.attributes(current, 'mode') then
            local ok, err = lfs.mkdir(current)
            if not ok then
                print(string.format('[MAUI] Failed to create directory %s (%s)', current, tostring(err)))
                return false
            end
        end
    end
    return true
end

local function CopyFile(sourcePath, targetPath)
    local src = io.open(sourcePath, 'rb')
    if not src then return false end
    local data = src:read('*a')
    src:close()
    local dst = io.open(targetPath, 'wb')
    if not dst then return false end
    dst:write(data or '')
    dst:close()
    return true
end

local function SyncDirectory(sourceDir, targetDir)
    local copied = 0
    local sourceMode = lfs.attributes(sourceDir, 'mode')
    if sourceMode ~= 'directory' then
        return false, copied
    end
    if not EnsureDirectory(targetDir) then
        return false, copied
    end
    for entry in lfs.dir(sourceDir) do
        if entry ~= '.' and entry ~= '..' then
            local srcPath = sourceDir .. '/' .. entry
            local dstPath = targetDir .. '/' .. entry
            local mode = lfs.attributes(srcPath, 'mode')
            if mode == 'directory' then
                local ok, subCount = SyncDirectory(srcPath, dstPath)
                if not ok then return false, copied end
                copied = copied + subCount
            elseif mode == 'file' then
                if not CopyFile(srcPath, dstPath) then
                    return false, copied
                end
                copied = copied + 1
            end
        end
    end
    return true, copied
end

local function GetLuaScriptStatus(scriptName)
    local ok, status = pcall(function() return mq.TLO.Lua.Script(scriptName).Status() end)
    if ok and status then
        return tostring(status)
    end
    return 'stopped'
end

local function RunToolCommand(scriptKey, command)
    if not TryBeginAction(scriptKey) then return end
    mq.cmd(command)
end

local function RequestUnsavedAction(actionName, fileName)
    RefreshDirtyState()
    if not isDirty then
        return false
    end
    pendingUnsavedAction = actionName
    pendingUnsavedFile = fileName
    ImGui.OpenPopup('Unsaved Changes##UEA')
    return true
end

local function HandleUnsavedActionConfirm()
    if pendingUnsavedAction == 'reload' then
        ReloadINIFromDisk()
    elseif pendingUnsavedAction == 'loadfile' and pendingUnsavedFile then
        globals.INIFile = pendingUnsavedFile
        ReloadINIFromDisk()
        filedialog:reset_filename()
    end
    pendingUnsavedAction = nil
    pendingUnsavedFile = nil
end

local function Save()
    -- Set "NULL" string values to nil so they aren't saved
    for sectionName,sectionProperties in pairs(globals.Config) do
        for key,value in pairs(sectionProperties) do
            if value == 'NULL' then
                -- Replace and XYZCond#=FALSE with nil as well if no corresponding XYZ# value
                local word = string.match(key, '[^%d]+')
                local number = string.match(key, '%d+')
                if number then
                    globals.Config[sectionName][word..'Cond'..number] = nil
                end
                globals.Config[sectionName][key] = nil
            end
        end
    end
    if globals.INIFile:sub(-string.len('.ini')) ~= '.ini' then
        globals.INIFile = globals.INIFile .. '.ini'
    end
    LIP.save(mq.configDir..'/'..globals.INIFile, globals.Config, globals.Schema)
    SaveMAUIConfig()
    MarkConfigClean()
end

-- Sort spells by level
local SpellSorter = function(a, b)
    -- spell level is in spell[1], name in spell[2]
    if a[1] < b[1] then
        return false
    elseif b[1] < a[1] then
        return true
    else
        return false
    end
end

local function AddSpellToMap(spell)
    local cat = spell.Category()
    local subcat = spell.Subcategory()
    if not spells[cat] then
        spells[cat] = {subcategories={}}
        table.insert(spells.categories, cat)
    end
    if not spells[cat][subcat] then
        spells[cat][subcat] = {}
        table.insert(spells[cat].subcategories, subcat)
    end
    --if spell.Level() >= globals.MyLevel-30 then
        local name = spell.Name():gsub(' Rk%..*', '')
        table.insert(spells[cat][subcat], {spell.Level(), name, spell.Name()})
    --end
end

local function SortMap(map)
    -- sort categories and subcategories alphabetically, spells by level
    table.sort(map.categories)
    for category,subcategories in pairs(map) do
        if category ~= 'categories' then
            table.sort(map[category].subcategories)
            for subcategory,subcatspells in pairs(subcategories) do
                if subcategory ~= 'subcategories' then
                    table.sort(subcatspells, SpellSorter)
                end
            end
        end
    end
end

-- Ability menu initializers
local function InitSpellTree()
    -- Build spell tree for picking spells
    for spellIter=1,1120 do
        local spell = mq.TLO.Me.Book(spellIter)
        if spell() then
            AddSpellToMap(spell)
        end
    end
    SortMap(spells)
end

local function AddAAToMap(aa)
    local type = aatypes[aa.Type()]
    if not altAbilities[type] then
        altAbilities[type] = {}
        table.insert(altAbilities.types, type)
    end
    table.insert(altAbilities[type], {aa.Name(),aa.Spell.Name()})
end

local function InitAATree()
    -- TODO: what's the right way to loop through activated abilities?
    for aaIter=1,10000 do
        local aa = mq.TLO.Me.AltAbility(aaIter)
        if aa.Spell() then
            AddAAToMap(aa)
        end
    end
    for _,type in ipairs(altAbilities.types) do
        if altAbilities[type] then
            table.sort(altAbilities[type], function(a,b) return a[1] < b[1] end)
        end
    end
end

local function AddDiscToMap(disc)
    local cat = disc.Category()
    local subcat = disc.Subcategory()
    if not discs[cat] then
        discs[cat] = {subcategories={}}
        table.insert(discs.categories, cat)
    end
    if not discs[cat][subcat] then
        discs[cat][subcat] = {}
        table.insert(discs[cat].subcategories, subcat)
    end
    local name = disc.Name():gsub(' Rk%..*', '')
    table.insert(discs[cat][subcat], {disc.Level(), name, disc.Name()})
end

local function InitDiscTree()
    local discIter = 1
    repeat
        local disc = mq.TLO.Me.CombatAbility(discIter)
        if disc() then
            AddDiscToMap(disc)
        end
        discIter = discIter + 1
    until mq.TLO.Me.CombatAbility(discIter)() == nil
    SortMap(discs)
end

--Given some spell data input, determine whether a better spell with the same inputs exists
local function GetSpellUpgrade(targetType, subCat, numEffects, minLevel)
    local max = 0
    local max2 = 0
    local maxName = ''
    local maxLevel = 0
    for i=1,1120 do
        local valid = true
        local spell = mq.TLO.Me.Book(i)
        if not spell.ID() then
            valid = false
        elseif spell.Subcategory() ~= subCat then
            valid = false
        elseif spell.TargetType() ~= targetType then
            valid = false
        elseif spell.NumEffects() ~= numEffects then
            valid = false
        elseif spell.Level() <= minLevel then
            valid = false
        end
        if valid then
            -- TODO: several trigger spells i don't think this would handle properly...
            -- 470 == trigger best in spell group
            -- 374 == trigger spell
            -- 340 == chance spell
            if spell.HasSPA(470)() or spell.HasSPA(374)() or spell.HasSPA(340)() then
                for eIdx=1,spell.NumEffects() do
                    if spell.Trigger(eIdx)() then
                        for SPAIdx=1,spell.Trigger(eIdx).NumEffects() do
                            if spell.Trigger(eIdx).Base(SPAIdx)() < -1 then
                                if spell.Trigger(eIdx).Base(SPAIdx)() < max then
                                    max = spell.Trigger(eIdx).Base(SPAIdx)()
                                    maxName = spell.Name():gsub(' Rk%..*', '')
                                end
                            else
                                if spell.Trigger(eIdx).Base(SPAIdx)() > max then
                                    max = spell.Trigger(eIdx).Base(SPAIdx)()
                                    maxName = spell.Name():gsub(' Rk%..*', '')
                                end
                            end
                        end
                    end
                end
                -- TODO: this won't handle spells whos trigger SPA is just the illusion portion
            else
                for SPAIdx=1,spell.NumEffects() do
                    --print(string.format('[%s] .Base: %d, Base2: %d, Max: %d', spell.Name(), spell.Base(SPAIdx)(), spell.Base2(SPAIdx)(), spell.Max(SPAIdx)()))
                    if spell.Base(SPAIdx)() < -1 then
                        if spell.Base(SPAIdx)() < max then
                            max = spell.Base(SPAIdx)()
                            maxName = spell.Name():gsub(' Rk%..*', '')
                        elseif spell.Base2(SPAIdx)() ~= 0 and spell.Base2(SPAIdx)() > max2 then
                            max2 = spell.Base2(SPAIdx)()
                            maxName = spell.Name():gsub(' Rk%..*', '')
                        end
                    else
                        if spell.Base(SPAIdx)() > max then
                            max = spell.Base(SPAIdx)()
                            maxName = spell.Name():gsub(' Rk%..*', '')
                        elseif spell.Base2(SPAIdx)() ~= 0 and spell.Base2(SPAIdx)() > max2 then
                            max2 = spell.Base2(SPAIdx)()
                            maxName = spell.Name():gsub(' Rk%..*', '')
                        end
                    end
                end
            end
        end
    end
    return maxName
end

-- ImGui functions

-- Color spell names in spell picker similar to the spell bar context menus
local function SetSpellTextColor(spell)
    local target = tloCache:get(spell..'.targettype', function() return mq.TLO.Spell(spell).TargetType() end)
    if target == 'Single' or target == 'Line of Sight' or target == 'Undead' then
        ImGui.PushStyleColor(ImGuiCol.Text, 1, 0, 0, 1)
    elseif target == 'Self' then
        ImGui.PushStyleColor(ImGuiCol.Text, 1, 1, 0, 1)
    elseif target == 'Group v2' or target == 'Group v1' or target == 'AE PC v2' then
        ImGui.PushStyleColor(ImGuiCol.Text, 1, 0, 1, 1)
    elseif target == 'Beam' then
        ImGui.PushStyleColor(ImGuiCol.Text, 0, 1, 1, 1)
    elseif target == 'Targeted AE' then
        ImGui.PushStyleColor(ImGuiCol.Text, 1, 0.5, 0, 1)
    elseif target == 'PB AE' then
        ImGui.PushStyleColor(ImGuiCol.Text, 0, 0.5, 1, 1)
    elseif target == 'Pet' then
        ImGui.PushStyleColor(ImGuiCol.Text, 1, 0, 0, 1)
    elseif target == 'Pet2' then
        ImGui.PushStyleColor(ImGuiCol.Text, 1, 0, 0, 1)
    elseif target == 'Free Target' then
        ImGui.PushStyleColor(ImGuiCol.Text, 0, 1, 0, 1)
    else
        ImGui.PushStyleColor(ImGuiCol.Text, 1, 1, 1, 1)
    end
end

local memspell = nil
local memgem = 0
local memQueue = {}
-- Recreate the spell bar context menu
-- sectionName+key+index defines where to store the result
-- selectedIdx is used to clear spell upgrade input incase of updating over an existing entry
local function DrawSpellPicker(sectionName, key, index)
    if not globals.Config[sectionName][key..index] then
        globals.Config[sectionName][key..index] = ''
    end
    local valueParts = nil
    if type(globals.Config[sectionName][key..index]) == "string" then
        valueParts = utils.Split(globals.Config[sectionName][key..index],'|',1)
    elseif type(globals.Config[sectionName][key..index]) == "number" then
        valueParts = {tostring(globals.Config[sectionName][key..index])}
    end
    -- Right click context menu popup on list buttons
    if ImGui.BeginPopupContextItem('##rcmenu'..sectionName..key..index) then
        -- Top level 'Spells' menu item
        if #spells.categories > 0 then
            if ImGui.BeginMenu('Spells##rcmenu'..sectionName..key) then
                for _,category in ipairs(spells.categories) do
                    -- Spell Subcategories submenu
                    if ImGui.BeginMenu(category..'##rcmenu'..sectionName..key..category) then
                        for _,subcategory in ipairs(spells[category].subcategories) do
                            -- Subcategory Spell menu
                            local menuHeight = -1
                            if #spells[category][subcategory] > 25 then
                                menuHeight = ImGui.GetTextLineHeight()*25
                            end
                            ImGui.SetNextWindowSize(250, menuHeight)
                            if #spells[category][subcategory] > 0 and ImGui.BeginMenu(subcategory..'##'..sectionName..key..subcategory) then
                                for _,spell in ipairs(spells[category][subcategory]) do
                                    -- spell[1]=level, spell[2]=name
                                    SetSpellTextColor(spell[2])
                                    if ImGui.MenuItem(spell[1]..' - '..spell[2]..'##'..sectionName..key..subcategory) then
                                        if useRankNames then
                                            valueParts[1] = spell[3]
                                        else
                                            valueParts[1] = spell[2]
                                        end
                                        selectedUpgrade = nil
                                    end
                                    ImGui.PopStyleColor()
                                end
                                ImGui.EndMenu()
                            end
                        end
                        ImGui.EndMenu()
                    end
                end
                ImGui.EndMenu()
            end
        end
        -- Top level 'AAs' menu item
        if sectionName ~= 'MySpells' and #altAbilities.types > 0 then
            if ImGui.BeginMenu('Alt Abilities##rcmenu'..sectionName..key) then
                for _,type in ipairs(aatypes) do
                    if altAbilities[type] then
                        local menuHeight = -1
                        if #altAbilities[type] > 25 then
                            menuHeight = ImGui.GetTextLineHeight()*25
                        end
                        ImGui.SetNextWindowSize(250, menuHeight)
                        if ImGui.BeginMenu(type..'##aamenu'..sectionName..key..type) then
                            for _,altAbility in ipairs(altAbilities[type]) do
                                SetSpellTextColor(altAbility[2])
                                if ImGui.MenuItem(altAbility[1]..'##aa'..sectionName..key) then
                                    valueParts[1] = altAbility[1]
                                end
                                ImGui.PopStyleColor()
                            end
                            ImGui.EndMenu()
                        end
                    end
                end
                ImGui.EndMenu()
            end
        end
        -- Top level 'Discs' menu item
        if sectionName ~= 'MySpells' and #discs.categories > 0 then
            if ImGui.BeginMenu('Combat Abilities##rcmenu'..sectionName..key) then
                for _,category in ipairs(discs.categories) do
                    -- Spell Subcategories submenu
                    if ImGui.BeginMenu(category..'##rcmenu'..sectionName..key..category) then
                        for _,subcategory in ipairs(discs[category].subcategories) do
                            -- Subcategory Spell menu
                            local menuHeight = -1
                            if #discs[category][subcategory] > 25 then
                                menuHeight = ImGui.GetTextLineHeight()*25
                            end
                            ImGui.SetNextWindowSize(250, menuHeight)
                            if #discs[category][subcategory] > 0 and ImGui.BeginMenu(subcategory..'##'..sectionName..key..subcategory) then
                                for _,disc in ipairs(discs[category][subcategory]) do
                                    -- spell[1]=level, spell[2]=name
                                    SetSpellTextColor(disc[2])
                                    if ImGui.MenuItem(disc[1]..' - '..disc[2]..'##'..sectionName..key..subcategory) then
                                        valueParts[1] = disc[2]
                                        selectedUpgrade = nil
                                    end
                                    ImGui.PopStyleColor()
                                end
                                ImGui.EndMenu()
                            end
                        end
                        ImGui.EndMenu()
                    end
                end
                ImGui.EndMenu()
            end
        end
        if valueParts[1] then
            local rankname = tloCache:get(valueParts[1]..'.rankname', function() return mq.TLO.Spell(valueParts[1]).RankName() end)
            if rankname then
                local bookidx = tloCache:get('book.'..rankname, function() return mq.TLO.Me.Book(rankname)() end)
                if bookidx then
                    if ImGui.MenuItem('Memorize Spell') then
                        for i=1,13 do
                            if not mq.TLO.Me.Gem(i)() then
                                memspell = valueParts[1]
                                memgem = i
                                break
                            end
                        end
                    end
                end
            end
        end
        ImGui.EndPopup()
    end
    globals.Config[sectionName][key..index] = table.concat(valueParts, '|')
    if globals.Config[sectionName][key..index] == '|' then
        globals.Config[sectionName][key..index] = 'NULL'
    end
end

local function DrawSelectedSpellUpgradeButton(spell)
    local upgradeValue = nil
    -- Avoid finding the upgrade more than once
    if not selectedUpgrade then
        selectedUpgrade = GetSpellUpgrade(spell.TargetType(), spell.Subcategory(), spell.NumEffects(), spell.Level())
    end
    -- Upgrade found? display the upgrade button
    if selectedUpgrade ~= '' and selectedUpgrade ~= spell.Name() then
        if ImGui.Button('Upgrade Available - '..selectedUpgrade) then
            upgradeValue = selectedUpgrade
            selectedUpgrade = nil
        end
    end
    return upgradeValue
end

local function DrawSelectedSpellDowngradeButton(spell)
    local upgradeValue = nil
    -- Avoid finding the upgrade more than once
    if not selectedUpgrade then
        selectedUpgrade = GetSpellUpgrade(spell.TargetType(), spell.Subcategory(), spell.NumEffects(), 0)
    end
    -- Upgrade found? display the upgrade button
    if selectedUpgrade ~= '' and selectedUpgrade ~= spell.Name() then
        if ImGui.Button('Downgrade Available - '..selectedUpgrade) then
            upgradeValue = selectedUpgrade
            selectedUpgrade = nil
        end
    end
    return upgradeValue
end

local function CheckInputType(key, value, typestring, inputtype)
    if typeWarningDebug and type(value) ~= typestring then
        utils.printf('\arWARNING [%s]: %s value is not a %s: type=%s value=%s\a-x', key, inputtype, typestring, type(value), tostring(value))
    end
end

local function DrawKeyAndInputText(keyText, label, value, helpText)
    ImGui.PushStyleColor(ImGuiCol.Text, 1, 1, 0, 1)
    ImGui.Text(keyText)
    ImGui.PopStyleColor()
    ImGui.SameLine()
    utils.HelpMarker(helpText)
    ImGui.SameLine()
    ImGui.SetCursorPosX(175)
    -- the first part, spell/item/disc name, /command, etc
    CheckInputType(label, value, 'string', 'InputText')
    return ImGui.InputText(label, tostring(value))
end

-- Draw the value and condition of the selected list item
local function DrawSelectedListItem(sectionName, key, value)
    local valueKey = key..selectedListItem[2]
    -- make sure values not nil so imgui inputs don't barf
    if globals.Config[sectionName][valueKey] == nil then
        globals.Config[sectionName][valueKey] = 'NULL'
    end
    -- split the value so we can update spell name and stuff after the | individually
    local valueParts = utils.Split(globals.Config[sectionName][valueKey], '|', 1)
    -- the first part, spell/item/disc name, /command, etc
    if not valueParts[1] then valueParts[1] = '' end
    -- the rest of the stuff after the first |, classes, percents, oog, etc
    if not valueParts[2] then valueParts[2] = '' end

    ImGui.Separator()
    ImGui.PushStyleColor(ImGuiCol.Text, 0, 1, 1, 1)
    ImGui.Text(string.format('%s%d', key, selectedListItem[2]))
    ImGui.PopStyleColor()
    valueParts[1] = DrawKeyAndInputText('Name: ', '##'..sectionName..valueKey, valueParts[1], value['Tooltip'])
    -- prevent | in the ability name field, or else things get ugly in the options field
    if valueParts[1]:find('|') then valueParts[1] = valueParts[1]:match('[^|]+') end
    valueParts[2] = DrawKeyAndInputText('Options: ', '##'..sectionName..valueKey..'options', valueParts[2], value['OptionsTooltip'])
    if value['Conditions'] then
        local valueCondKey = key..'Cond'..selectedListItem[2]
        if globals.Config[sectionName][valueCondKey] == nil then
            globals.Config[sectionName][valueCondKey] = 'NULL'
        end
        globals.Config[sectionName][valueCondKey] = DrawKeyAndInputText('Conditions: ', '##cond'..sectionName..valueKey, globals.Config[sectionName][valueCondKey], value['CondTooltip'])
    end
    local spell = tloCache:get(valueParts[1], function() return mq.TLO.Spell(valueParts[1]) end)
    if mq.TLO.Me.Book(spell.RankName())() then
        local upgradeResult = DrawSelectedSpellUpgradeButton(spell)
        if upgradeResult then valueParts[1] = upgradeResult end
    elseif spell then
        local upgradeResult = DrawSelectedSpellDowngradeButton(spell)
        if upgradeResult then valueParts[1] = upgradeResult end
    end
    if valueParts[1] and string.len(valueParts[1]) > 0 then
        globals.Config[sectionName][valueKey] = valueParts[1]
        if valueParts[2] and string.len(valueParts[2]) > 0 then
            globals.Config[sectionName][valueKey] = globals.Config[sectionName][valueKey]..'|'..valueParts[2]:gsub('|$','')
        end
    else
        globals.Config[sectionName][valueKey] = ''
    end
    ImGui.Separator()
end

local function DrawPlainListButton(sectionName, key, listIdx, iconSize)
    -- INI value is set to non-spell/item
    if ImGui.Button(listIdx..'##'..sectionName..key, iconSize[1], iconSize[2]) then
        if type(listIdx) == 'number' then
            if mq.TLO.CursorAttachment.Type() == 'ITEM' then
                globals.Config[sectionName][key..listIdx] = mq.TLO.CursorAttachment.Item.Name()
            elseif mq.TLO.CursorAttachment.Type() == 'SPELL_GEM' then
                globals.Config[sectionName][key..listIdx] = mq.TLO.CursorAttachment.Spell.Name()
            else
                selectedListItem = {key, listIdx}
                selectedUpgrade = nil
            end
        else
            if mq.TLO.CursorAttachment.Type() == 'ITEM' then
                globals.Config[sectionName][key] = mq.TLO.CursorAttachment.Item.Name()
            elseif mq.TLO.CursorAttachment.Type() == 'SPELL_GEM' then
                globals.Config[sectionName][key] = mq.TLO.CursorAttachment.Spell.Name()
            end
        end
    elseif type(listIdx) == 'number' then
        if not mq.TLO.Cursor() and ImGui.BeginDragDropSource() then
            ImGui.SetDragDropPayload("ListBtn", listIdx)
            ImGui.Button(listIdx..'##'..sectionName..key, iconSize[1], iconSize[2])
            ImGui.EndDragDropSource()
        end
    end
end

local function DrawTooltip(text)
    if ImGui.IsItemHovered() and text and string.len(text) > 0 then
        ImGui.BeginTooltip()
        ImGui.PushTextWrapPos(ImGui.GetFontSize() * 35.0)
        ImGui.Text(text)
        ImGui.PopTextWrapPos()
        ImGui.EndTooltip()
    end
end

local function CharacterHasThing(iniValue)
    local valid = false
    if not iniValue then
        -- count unset INI entry as valid
        valid = true
    elseif tloCache:get('invalid.'..iniValue) then
        valid = false
    else
        local rankname = tloCache:get(iniValue..'.rankname', function() return mq.TLO.Spell(iniValue).RankName() end)
        if rankname then
            if tloCache:get('book.'..rankname, function() return mq.TLO.Me.Book(rankname)() end) then
                valid = true
            elseif tloCache:get('aa.'..iniValue, function() return mq.TLO.Me.AltAbility(iniValue)() end) then
                valid = true
            elseif tloCache:get('disc.'..rankname, function() return mq.TLO.Me.CombatAbility(rankname)() end) then
                valid = true
            end
        elseif tloCache:get('item.'..iniValue, function() return mq.TLO.FindItem(iniValue)() end) then
            valid = true
        elseif iniValue:find('command:') or iniValue:find('${') then
            valid = true
        elseif tloCache:get('ability.'..iniValue, function() return mq.TLO.Me.Ability(iniValue)() end) then
            valid = true
        else
            tloCache:get('invalid.'..iniValue, function() return 1 end)
            valid = false
        end
    end
    return valid
end

local function Trim(value)
    if type(value) ~= 'string' then return value end
    return value:match('^%s*(.-)%s*$')
end

local function ResolveBestAbilityName(rawName, mode)
    local name = Trim(rawName or '')
    if not name or name == '' or name:upper() == 'NULL' then return nil end
    if name:find('command:') or name:find('${') then return nil end

    -- Keep already-valid non-spell entries untouched.
    if mq.TLO.FindItem(name)() or mq.TLO.Me.AltAbility(name)() or mq.TLO.Me.Ability(name)() then
        return nil
    end
    if mq.TLO.Me.CombatAbility(name)() then
        return nil
    end

    local spell = mq.TLO.Spell(name)
    if spell() then
        local rankName = spell.RankName()
        if rankName and mq.TLO.Me.CombatAbility(rankName)() then
            return rankName
        end
        local knownSpell = rankName and mq.TLO.Me.Book(rankName)()
        local minLevel = 0
        if mode == 'upgrade' and knownSpell then
            minLevel = spell.Level()
        end
        local replacement = GetSpellUpgrade(spell.TargetType(), spell.Subcategory(), spell.NumEffects(), minLevel)
        if replacement and replacement ~= '' and replacement ~= name then
            return replacement
        end
    end

    -- Fallback: strip explicit rank suffixes and retry disc/AA/spell name.
    local baseName = name:gsub(' Rk%..*', '')
    if baseName ~= name then
        if mq.TLO.Me.CombatAbility(baseName)() or mq.TLO.Me.AltAbility(baseName)() or mq.TLO.Me.Ability(baseName)() then
            return baseName
        end
        local baseSpell = mq.TLO.Spell(baseName)
        if baseSpell() then
            local replacement = GetSpellUpgrade(baseSpell.TargetType(), baseSpell.Subcategory(), baseSpell.NumEffects(), 0)
            if replacement and replacement ~= '' and replacement ~= name then
                return replacement
            end
        end
    end

    return nil
end

local function RewriteConfigAbilityValue(sectionName, key, mode)
    if not globals.Config[sectionName] then return false end
    local current = globals.Config[sectionName][key]
    if type(current) ~= 'string' or current == '' or current == 'NULL' then return false end
    local parts = utils.Split(current, '|', 1)
    local oldName = Trim(parts[1] or '')
    if not oldName or oldName == '' then return false end
    local newName = ResolveBestAbilityName(oldName, mode)
    if newName and newName ~= oldName then
        parts[1] = newName
        globals.Config[sectionName][key] = table.concat(parts, '|')
        return true
    end
    return false
end

local function QueueMemSpell(gemIdx, spellName, queue)
    if type(gemIdx) ~= 'number' or gemIdx < 1 or gemIdx > 13 then return false end
    local spellBase = Trim(spellName or '')
    if not spellBase or spellBase == '' or spellBase:upper() == 'NULL' then return false end
    local spell = mq.TLO.Spell(spellBase)
    if not spell() then return false end
    local rankName = spell.RankName()
    if not rankName or not mq.TLO.Me.Book(rankName)() then return false end
    table.insert(queue, {gem = gemIdx, spell = rankName})
    return true
end

local function QueueRetunedGemsForMem(updatedGems, queue)
    local queued = 0
    for gem = 1, 13 do
        if updatedGems[gem] then
            local gemName = updatedGems[gem]
            if type(gemName) == 'string' then
                gemName = utils.Split(gemName, '|', 1)[1]
            end
            if QueueMemSpell(gem, gemName, queue) then
                queued = queued + 1
            end
        end
    end
    return queued
end

local function AutoRetuneAbilities(mode)
    local changed = 0
    local checked = 0
    local updatedGems = {}
    for sectionName, sectionSchema in pairs(globals.Schema) do
        if type(sectionSchema) == 'table' and sectionSchema.Properties and globals.Config[sectionName] then
            for key, prop in pairs(sectionSchema.Properties) do
                if prop.Type == 'SPELL' then
                    checked = checked + 1
                    if RewriteConfigAbilityValue(sectionName, key, mode) then
                        changed = changed + 1
                    end
                elseif prop.Type == 'LIST' then
                    local size = tonumber(globals.Config[sectionName][key..'Size']) or 0
                    for idx = 1, size do
                        checked = checked + 1
                        if RewriteConfigAbilityValue(sectionName, key..idx, mode) then
                            changed = changed + 1
                        end
                    end
                end
            end
        end
    end

    -- Also retune memorized spell set entries.
    if globals.Config.MySpells then
        for gem = 1, 13 do
            checked = checked + 1
            local before = globals.Config.MySpells['Gem'..gem]
            if RewriteConfigAbilityValue('MySpells', 'Gem'..gem, mode) then
                changed = changed + 1
                updatedGems[gem] = globals.Config.MySpells['Gem'..gem] or before
            end
        end
    end

    if changed > 0 then
        Save()
        globals.INIFileContents = utils.ReadRawINIFile()
    end
    return changed, checked, updatedGems
end

local function DrawSpellIconOrButton(sectionName, key, index)
    local iniValue = nil
    if globals.Config[sectionName][key..index] and globals.Config[sectionName][key..index] ~= 'NULL' then
        if type(globals.Config[sectionName][key..index]) == "string" then
            iniValue = utils.Split(globals.Config[sectionName][key..index],'|',1)[1]
        elseif type(globals.Config[sectionName][key..index]) == "number" then
            iniValue = tostring(globals.Config[sectionName][key..index])
        end
    end
    local charHasAbility = CharacterHasThing(iniValue)
    local iconSize = {30,30} -- default icon size
    if type(index) == 'number' then
        local x,y = ImGui.GetCursorPos()
        if not charHasAbility then
            ImGui.DrawTextureAnimation(animRedWndPieces, iconSize[1], iconSize[2])
            ImGui.SetCursorPosX(x+2)
            ImGui.SetCursorPosY(y+2)
            iconSize = {26,26}
        end
    end
    if iniValue then
        -- Use first part of INI value as spell or item name to lookup icon
        if tloCache:get('invalid.'..iniValue) then
            DrawPlainListButton(sectionName, key, index, iconSize)
        elseif tloCache:get(iniValue..'.name', function() return mq.TLO.Spell(iniValue)() end) then
            -- Need to create a group for drag/drop to work, doesn't seem to work with just the texture animation?
            ImGui.BeginGroup()
            local x,y = ImGui.GetCursorPos()
            ImGui.Button('##'..index..sectionName..key, iconSize[1], iconSize[2])
            ImGui.SetCursorPosX(x)
            ImGui.SetCursorPosY(y)
            local spellIcon = tloCache:get(iniValue..'.spellicon', function() return mq.TLO.Spell(iniValue).SpellIcon() end)
            animSpellIcons:SetTextureCell(spellIcon)
            ImGui.DrawTextureAnimation(animSpellIcons, iconSize[1], iconSize[2])
            ImGui.EndGroup()
        elseif tloCache:get('item.'..iniValue, function() return mq.TLO.FindItem(iniValue)() end) then
            -- Need to create a group for drag/drop to work, doesn't seem to work with just the texture animation?
            ImGui.BeginGroup()
            local x,y = ImGui.GetCursorPos()
            ImGui.Button('##'..index..sectionName..key, iconSize[1], iconSize[2])
            ImGui.SetCursorPosX(x)
            ImGui.SetCursorPosY(y)
            local itemIcon = tloCache:get('itemicon.'..iniValue, function() return mq.TLO.FindItem(iniValue).Icon() end)
            animItems:SetTextureCell(itemIcon-500)
            ImGui.DrawTextureAnimation(animItems, iconSize[1], iconSize[2])
            ImGui.EndGroup()
        else
            DrawPlainListButton(sectionName, key, index, iconSize)
        end
        DrawTooltip(iniValue)
        -- Handle clicks on spell icon animations that aren't buttons
        if ImGui.BeginDragDropTarget() then
            local payload = ImGui.AcceptDragDropPayload("ListBtn")
            if payload ~= nil then
                local num = payload.Data;
                -- swap the list entries
                globals.Config[sectionName][key..index], globals.Config[sectionName][key..num] = globals.Config[sectionName][key..num], globals.Config[sectionName][key..index]
                globals.Config[sectionName][key..'Cond'..index], globals.Config[sectionName][key..'Cond'..num] = globals.Config[sectionName][key..'Cond'..num], globals.Config[sectionName][key..'Cond'..index]
            end
            ImGui.EndDragDropTarget()
        elseif ImGui.IsItemHovered() and ImGui.IsMouseReleased(0) and type(index) == 'number' then
            if mq.TLO.CursorAttachment.Type() == 'ITEM' then
                globals.Config[sectionName][key..index] = mq.TLO.CursorAttachment.Item.Name()
            elseif mq.TLO.CursorAttachment.Type() == 'SPELL_GEM' then
                globals.Config[sectionName][key..index] = mq.TLO.CursorAttachment.Spell.Name()
            else
                selectedListItem = {key, index}
                selectedUpgrade = nil
            end
        elseif ImGui.IsItemHovered() and ImGui.IsMouseDown(ImGuiMouseButton.Left) and type(index) == 'number' then
            if not mq.TLO.Cursor() and ImGui.BeginDragDropSource() then
                ImGui.SetDragDropPayload("ListBtn", index)
                ImGui.Button(index..'##'..sectionName..key, iconSize[1], iconSize[2])
                ImGui.EndDragDropSource()
            end
        end
        -- Spell picker context menu on right click button
        DrawSpellPicker(sectionName, key, index)
    else
        -- No INI value assigned yet for this key
        DrawPlainListButton(sectionName, key, index, iconSize)
        DrawSpellPicker(sectionName, key, index)
        if ImGui.BeginDragDropTarget() then
            local payload = ImGui.AcceptDragDropPayload("ListBtn")
            if payload ~= nil then
                local num = payload.Data;
                -- swap the list entries
                globals.Config[sectionName][key..index], globals.Config[sectionName][key..num] = globals.Config[sectionName][key..num], globals.Config[sectionName][key..index]
                globals.Config[sectionName][key..'Cond'..index], globals.Config[sectionName][key..'Cond'..num] = globals.Config[sectionName][key..'Cond'..num], globals.Config[sectionName][key..'Cond'..index]
            end
            ImGui.EndDragDropTarget()
        end
    end
end

-- Draw 0..N buttons based on value of XYZSize input
local function DrawList(sectionName, key, value)
    ImGui.PushStyleColor(ImGuiCol.Text, 1, 1, 0, 1)
    ImGui.Text(key..'Size: ')
    ImGui.PopStyleColor()
    ImGui.SameLine()
    utils.HelpMarker(value['SizeTooltip'])
    ImGui.SameLine()
    ImGui.PushItemWidth(100)
    local size = globals.Config[sectionName][key..'Size']
    if size == nil or type(size) ~= 'number' then
        CheckInputType(key..'Size', size, 'number', 'InputInt')
        size = 0
    end
    ImGui.SetCursorPosX(175)
    -- Set size of list and check boundaries
    size = ImGui.InputInt('##sizeinput'..sectionName..key, size)
    if size < 0 then
        size = 0
    elseif size > value['Max'] then
        size = value['Max']
    end
    ImGui.PopItemWidth()
    local xOffset,yOffset = ImGui.GetCursorPos()
    local avail = ImGui.GetContentRegionAvail()
    local iconsPerRow = math.floor(avail/38)
    if iconsPerRow == 0 then iconsPerRow = 1 end
    for i=1,size do
        local offsetMod = math.floor((i-1)/iconsPerRow)
        ImGui.SetCursorPosY(yOffset+(36*offsetMod))
        DrawSpellIconOrButton(sectionName, key, i)
        if i%iconsPerRow ~= 0 and i < size then
            -- Some silliness instead of sameline due to the offset changes for red frames around missing abilities in list items
            -- Just let it be
            ImGui.SetCursorPosX(xOffset+(30*(i%iconsPerRow))+(6*(i%iconsPerRow)))
            ImGui.SetCursorPosY(yOffset)
        end
    end
    ImGui.SetCursorPosY(yOffset+38*(math.floor((size-1)/iconsPerRow)+1))
    globals.Config[sectionName][key..'Size'] = size
end

local function DrawMultiPartProperty(sectionName, key, value)
    -- TODO: what's a nice clean way to represent values which are multiple parts? 
    -- Currently just using this experimentally with RezAcceptOn
    local parts = utils.Split(globals.Config[sectionName][key], '|',1)
    for partIdx,part in ipairs(value['Parts']) do
        if part['Type'] == 'SWITCH' then
            ImGui.Text(part['Name']..': ')
            ImGui.SameLine()
            local value = utils.InitCheckBoxValue(tonumber(parts[partIdx]))
            CheckInputType(key, value, 'boolean', 'Checkbox')
            parts[partIdx] = ImGui.Checkbox('##'..key, value)
            if parts[partIdx] then parts[partIdx] = '1' else parts[partIdx] = '0' end
        elseif part['Type'] == 'NUMBER' then
            if not parts[partIdx] or parts[partIdx] == 'NULL' then parts[partIdx] = 0 end
            ImGui.Text(part['Name']..': ')
            ImGui.SameLine()
            ImGui.PushItemWidth(100)
            local value = tonumber(parts[partIdx])
            CheckInputType(key, value, 'number', 'InputInt')
            parts[partIdx] = ImGui.InputInt('##'..sectionName..key..partIdx, value)
            ImGui.PopItemWidth()
            if part['Min'] and parts[partIdx] < part['Min'] then
                parts[partIdx] = part['Min']
            elseif part['Max'] and parts[partIdx] > part['Max'] then
                parts[partIdx] = part['Max']
            end
            parts[partIdx] = tostring(parts[partIdx])
        end
        globals.Config[sectionName][key] = table.concat(parts, '|')
        if partIdx == 1 then
            ImGui.SameLine()
        end
    end
end

-- Draw a generic section key/value property
local function DrawProperty(sectionName, key, value)
    ImGui.PushStyleColor(ImGuiCol.Text, 1, 1, 0, 1)
    ImGui.Text(key..': ')
    ImGui.PopStyleColor()
    ImGui.SameLine()
    utils.HelpMarker(value['Tooltip'])
    ImGui.SameLine()
    if globals.Config[sectionName][key] == nil then
        globals.Config[sectionName][key] = 'NULL'
    end
    ImGui.SetCursorPosX(175)
    if value['Type'] == 'SWITCH' then
        local initialValue = utils.InitCheckBoxValue(globals.Config[sectionName][key])
        CheckInputType(key, initialValue, 'boolean', 'Checkbox')
        globals.Config[sectionName][key] = ImGui.Checkbox('##'..key, initialValue)
    elseif value['Type'] == 'SPELL' then
        DrawSpellIconOrButton(sectionName, key, '')
        ImGui.SameLine()
        ImGui.PushItemWidth(350)
        local initialValue = globals.Config[sectionName][key]
        CheckInputType(key, initialValue, 'string', 'InputText')
        globals.Config[sectionName][key] = ImGui.InputText('##textinput'..sectionName..key, tostring(initialValue))
        ImGui.PopItemWidth()
    elseif value['Type'] == 'NUMBER' then
        local initialValue = globals.Config[sectionName][key]
        if not initialValue or initialValue == 'NULL' or type(initialValue) ~= 'number' then
            CheckInputType(key, initialValue, 'number', 'InputInt')
            initialValue = 0
        end
        ImGui.PushItemWidth(350)
        globals.Config[sectionName][key] = ImGui.InputInt('##'..sectionName..key, initialValue)
        ImGui.PopItemWidth()
        if value['Min'] and globals.Config[sectionName][key] < value['Min'] then
            globals.Config[sectionName][key] = value['Min']
        elseif value['Max'] and globals.Config[sectionName][key] > value['Max'] then
            globals.Config[sectionName][key] = value['Max']
        end
    elseif value['Type'] == 'STRING' then
        ImGui.PushItemWidth(350)
        local initialValue = tostring(globals.Config[sectionName][key])
        CheckInputType(key, initialValue, 'string', 'InputText')
        globals.Config[sectionName][key] = ImGui.InputText('##'..sectionName..key, initialValue)
        ImGui.PopItemWidth()
    elseif value['Type'] == 'MULTIPART' then
        DrawMultiPartProperty(sectionName, key, value)
    end
end

-- Draw main On/Off switches for an INI section
local function DrawSectionControlSwitches(sectionName, sectionProperties)
    if sectionProperties['On'] then
        if sectionProperties['On']['Type'] == 'SWITCH' then
            local value = utils.InitCheckBoxValue(globals.Config[sectionName][sectionName..'On'])
            CheckInputType(sectionName..'On', value, 'boolean', 'Checkbox')
            globals.Config[sectionName][sectionName..'On'] = ImGui.Checkbox(sectionName..'On', value)
        elseif sectionProperties['On']['Type'] == 'NUMBER' then
            -- Type=NUMBER control switch mostly a special case for DPS section only
            if not globals.Config[sectionName][sectionName..'On'] then globals.Config[sectionName][sectionName..'On'] = 0 end
            ImGui.PushItemWidth(100)
            globals.Config[sectionName][sectionName..'On'] = ImGui.InputInt(sectionName..'On', globals.Config[sectionName][sectionName..'On'])
            ImGui.PopItemWidth()
            if sectionProperties['On']['Min'] and globals.Config[sectionName][sectionName..'On'] < sectionProperties['On']['Min'] then
                globals.Config[sectionName][sectionName..'On'] = sectionProperties['On']['Min']
            elseif sectionProperties['On']['Max'] and globals.Config[sectionName][sectionName..'On'] > sectionProperties['On']['Max'] then
                globals.Config[sectionName][sectionName..'On'] = sectionProperties['On']['Max']
            end
        end
        if sectionProperties['COn'] then ImGui.SameLine() end
    end
    if sectionProperties['COn'] then
        globals.Config[sectionName][sectionName..'COn'] = ImGui.Checkbox(sectionName..'COn', utils.InitCheckBoxValue(globals.Config[sectionName][sectionName..'COn']))
    end
    ImGui.Separator()
end

local function DrawSpellsGemList(spellSection)
    local _,yOffset = ImGui.GetCursorPos()
    local avail = ImGui.GetContentRegionAvail()
    local iconsPerRow = math.floor(avail/36)
    if iconsPerRow == 0 then iconsPerRow = 1 end
    for i=1,13 do
        local offsetMod = math.floor((i-1)/iconsPerRow)
        ImGui.SetCursorPosY(yOffset+(34*offsetMod))
        DrawSpellIconOrButton(spellSection, 'Gem', i)
        if i%iconsPerRow ~= 0 and i < 13 then
            ImGui.SameLine()
        end
    end
    -- in case a spell gem was left clicked, don't mark it as selected so we don't enter the selected item drill-down
    selectedListItem = {nil, 0}
    selectedUpgrade = nil
end

local function DrawSpells(spellSection)
    ImGui.TextColored(1, 1, 0, 1, spellSection)
    if globals.Config[spellSection] then
        DrawSpellsGemList(spellSection)
    end
    if ImGui.Button('Update from spell bar') then
        if not globals.Config[spellSection] then globals.Config[spellSection] = {} end
        for i=1,13 do
            globals.Config[spellSection]['Gem'..i] = mq.TLO.Me.Gem(i).Name()
        end
        Save()
        globals.INIFileContents = utils.ReadRawINIFile()
    end
    ImGui.SameLine()
    if ImGui.Button('Mem Spells') then
        mq.cmdf('/memmyspells %s', globals.INIFile)
    end
end

-- Draw an INI section tab
local function DrawSection(sectionName, sectionProperties)
    if sectionName == 'Buffs' then
        useRankNames = true
    end
    if not globals.Config[sectionName] then
        globals.Config[sectionName] = {}
    end
    -- Draw main section control switches first
    if sectionProperties['Controls'] then
        DrawSectionControlSwitches(sectionName, sectionProperties['Controls'])
    end
    if sectionName == 'SpellSet' then
        -- special case for SpellSet tab to draw save spell set button (MA)
        DrawSpells('MySpells')
    elseif sectionName == 'Spells' then
        -- special case for Spells tab (KA)
        DrawSpells('Spells')
        -- Generic properties last
        for key,value in pairs(sectionProperties['Properties']) do
            if value['Type'] ~= 'LIST' then
                DrawProperty(sectionName, key, value)
            end
        end
    end
    if selectedListItem[1] then
        if ImGui.Button('Back to List') then
            selectedListItem = {nil, 0}
            selectedUpgrade = nil
        else
            DrawSpellIconOrButton(sectionName, selectedListItem[1], selectedListItem[2])
            DrawSelectedListItem(sectionName, selectedListItem[1], sectionProperties['Properties'][selectedListItem[1]])
        end
    else
        -- Draw List properties before general properties
        for key,value in pairs(sectionProperties['Properties']) do
            if value['Type'] == 'LIST' then
                DrawList(sectionName, key, value)
            end
        end
        -- Generic properties last
        for key,value in pairs(sectionProperties['Properties']) do
            if value['Type'] ~= 'LIST' then
                DrawProperty(sectionName, key, value)
            end
        end
    end
    if sectionName == 'Buffs' then
        useRankNames = false
    end
end

local function DrawSplitter(thickness, size0, min_size0)
    local x,y = ImGui.GetCursorPos()
    local delta = 0
    ImGui.SetCursorPosX(x + size0)

    ImGui.PushStyleColor(ImGuiCol.Button, 0, 0, 0, 0)
    ImGui.PushStyleColor(ImGuiCol.ButtonActive, 0, 0, 0, 0)
    ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 0.6, 0.6, 0.6, 0.1)
    ImGui.Button('##splitter', thickness, -1)
    ImGui.PopStyleColor(3)

    ImGui.SetItemAllowOverlap()

    if ImGui.IsItemActive() then
        delta,_ = ImGui.GetMouseDragDelta()

        if delta < min_size0 - size0 then
            delta = min_size0 - size0
        end
        if delta > 200 - size0 then
            delta = 200 - size0
        end

        size0 = size0 + delta
        leftPanelWidth = size0
    else
        leftPanelDefaultWidth = leftPanelWidth
    end
    ImGui.SetCursorPosX(x)
    ImGui.SetCursorPosY(y)
end

local function LeftPaneWindow()
    local x,y = ImGui.GetContentRegionAvail()
    if ImGui.BeginChild("left", leftPanelWidth, y-1, ImGuiChildFlags.Border) then
        if ImGui.BeginTable('SelectSectionTable', 1, TABLE_FLAGS, 0, 0, 0.0) then
            ImGui.TableSetupColumn('Section Name',     0,   -1.0, 1)
            ImGui.TableSetupScrollFreeze(0, 1) -- Make row always visible
            ImGui.TableHeadersRow()

            for _,sectionName in ipairs(globals.Schema.Sections) do
                if globals.Schema[sectionName] and (not globals.Schema[sectionName].Classes or globals.Schema[sectionName].Classes[globals.MyClass]) then
                    ImGui.TableNextRow()
                    ImGui.TableNextColumn()
                    local popStyleColor = false
                    if globals.Schema[sectionName]['Controls'] and globals.Schema[sectionName]['Controls']['On'] then
                        if not globals.Config[sectionName] or not globals.Config[sectionName][sectionName..'On'] or globals.Config[sectionName][sectionName..'On'] == 0 then
                            ImGui.PushStyleColor(ImGuiCol.Text, 1, 0, 0, 1)
                        else
                            ImGui.PushStyleColor(ImGuiCol.Text, 0, 1, 0, 1)
                        end
                        popStyleColor = true
                    end
                    local sel = ImGui.Selectable(sectionName, selectedSection == sectionName)
                    if sel and selectedSection ~= sectionName then
                        selectedListItem = {nil,0}
                        selectedSection = sectionName
                    end
                    if popStyleColor then ImGui.PopStyleColor() end
                end
            end
            ImGui.Separator()
            ImGui.Separator()
            for section,_ in pairs(customSections) do
                ImGui.TableNextRow()
                ImGui.TableNextColumn()
                if ImGui.Selectable(section, selectedSection == section) then
                    selectedSection = section
                end
            end
            ImGui.EndTable()
        end
    end
    ImGui.EndChild()
end

local function RightPaneWindow()
    local x,y = ImGui.GetContentRegionAvail()
    if ImGui.BeginChild("right", x, y-1, ImGuiChildFlags.Border) then
        if customSections[selectedSection] then
            customSections[selectedSection]()
        else
            DrawSection(selectedSection, globals.Schema[selectedSection])
        end
    end
    ImGui.EndChild()
end

local function DrawWindowPanels()
    DrawSplitter(8, leftPanelDefaultWidth, 75)
    ImGui.PushStyleVar(ImGuiStyleVar.WindowPadding, 2, 2)
    LeftPaneWindow()
    ImGui.SameLine()
    RightPaneWindow()
    ImGui.PopStyleVar()
end

local top_sections = {
    {'AE', 'AE'},
    {'Aggro', 'Aggro'},
    {'Buffs', 'Buffs'},
    {'Burn', 'Burn'},
    {'Cures', 'Cures'},
    {'DPS', 'DPS'},
    {'GoM', 'GoM'},
    {'Heals', 'Heals'},
    {'Mez', 'Mez'},
    {'OhS...', 'OhShit'},
    {'Pet', 'Pet'},
}

ReloadINIFromDisk = function()
    if globals.INIFile:sub(-string.len('.ini')) ~= '.ini' then
        globals.INIFile = globals.INIFile .. '.ini'
    end
    if utils.FileExists(mq.configDir..'/'..globals.INIFile) then
        globals.Config = LIP.load(mq.configDir..'/'..globals.INIFile)
        globals.INIFileContents = utils.ReadRawINIFile()
        globals.INILoadError = ''
        MarkConfigClean()
    else
        globals.INILoadError = ('INI File %s/%s does not exist!'):format(mq.configDir, globals.INIFile)
    end
end

local function DrawUltimateTopBar()
    RefreshDirtyState()
    hide_ini_path = ImGui.Checkbox('Hide INI Path', hide_ini_path)

    if not hide_ini_path then
        ImGui.PushItemWidth(520)
        globals.INIFile,_ = ImGui.InputText('##UEA_INIPath', globals.INIFile or '')
        ImGui.PopItemWidth()
    end
    ImGui.SameLine()
    if ImGui.Button('Import') then
        filedialog.set_file_selector_open(true)
    end
    ImGui.SameLine()
    if ImGui.Button('ReLoad') then
        if not RequestUnsavedAction('reload') then
            ReloadINIFromDisk()
        end
    end
    ImGui.SameLine()
    ImGui.SetNextItemWidth(150)
    local themeChanged = false
    if ImGui.BeginCombo('##UEA_ThemeCombo', themeLabels[themeOrder[currentThemeIndex]] or 'Template') then
        for i, key in ipairs(themeOrder) do
            local selected = (i == currentThemeIndex)
            if ImGui.Selectable(themeLabels[key], selected) then
                currentThemeIndex = i
                activeThemeKey = key
                globals.Theme = key
                themeChanged = true
            end
        end
        ImGui.EndCombo()
    end
    if themeChanged then
        if not globals.MAUI_Config[maui_ini_key] then globals.MAUI_Config[maui_ini_key] = {} end
        globals.MAUI_Config[maui_ini_key]['Theme'] = activeThemeKey
        SaveMAUIConfig()
    end

    if filedialog.is_file_selector_open() then
        filedialog.draw_file_selector(mq.configDir, '.ini')
    end
    if not filedialog.is_file_selector_open() and filedialog.get_filename() ~= '' then
        local selectedFile = filedialog.get_filename()
        if not RequestUnsavedAction('loadfile', selectedFile) then
            globals.INIFile = selectedFile
            ReloadINIFromDisk()
            filedialog:reset_filename()
        end
    end

    ImGui.Separator()
    if isDirty then
        ImGui.TextColored(1.00, 0.65, 0.20, 1.0, 'Unsaved changes')
    else
        ImGui.TextColored(0.45, 0.90, 0.98, 1.0, string.format('Saved at %s', lastSaveLabel))
    end
    if ImGui.BeginPopupModal('Unsaved Changes##UEA', true, ImGuiWindowFlags.AlwaysAutoResize) then
        ImGui.TextWrapped('You have unsaved changes in this INI.')
        ImGui.TextWrapped('Discard changes and continue?')
        ImGui.Separator()
        if ImGui.Button('Discard & Continue', 160, 0) then
            HandleUnsavedActionConfirm()
            ImGui.CloseCurrentPopup()
        end
        ImGui.SameLine()
        if ImGui.Button('Cancel', 100, 0) then
            local cancelledAction = pendingUnsavedAction
            pendingUnsavedAction = nil
            pendingUnsavedFile = nil
            if cancelledAction == 'loadfile' then
                filedialog:reset_filename()
            end
            ImGui.CloseCurrentPopup()
        end
        ImGui.EndPopup()
    end
end

local function DrawUltimateBottomBar()
    local function RunStartCommand()
        mq.cmd(globals.MAUI_Config[maui_ini_key]['StartCommand'])
        SaveMAUIConfig()
    end

    local function CollectStartWarnings()
        local warnings = {}
        EnsureConfigSection('General')
        EnsureConfigSection('DPS')
        EnsureConfigSection('Buffs')
        EnsureConfigSection('Heals')
        EnsureConfigSection('Cures')

        if ParseToggleValue(globals.Config.General.ChaseAssist) and ParseToggleValue(globals.Config.General.ReturnToCamp) then
            table.insert(warnings, 'Both ChaseAssist and ReturnToCamp are enabled.')
        end
        if ParseToggleValue(globals.Config.General.TwistOn) then
            local twistWhat = tostring(globals.Config.General.TwistWhat or '')
            if twistWhat == '' or twistWhat == '0' or twistWhat:upper() == 'NULL' then
                table.insert(warnings, 'TwistOn is enabled but TwistWhat is empty/zero.')
            end
        end
        if IsSectionEnabled('DPS') and (tonumber(globals.Config.DPS.DPSSize) or 0) == 0 then
            table.insert(warnings, 'DPS is enabled but DPSSize is 0.')
        end
        if IsSectionEnabled('Buffs') and (tonumber(globals.Config.Buffs.BuffsSize) or 0) == 0 then
            table.insert(warnings, 'Buffs are enabled but BuffsSize is 0.')
        end
        if IsSectionEnabled('Heals') and (tonumber(globals.Config.Heals.HealsSize) or 0) == 0 then
            table.insert(warnings, 'Heals are enabled but HealsSize is 0.')
        end
        if IsSectionEnabled('Cures') and (tonumber(globals.Config.Cures.CuresSize) or 0) == 0 then
            table.insert(warnings, 'Cures are enabled but CuresSize is 0.')
        end
        return warnings
    end

    local function RunPreflight(allowStart)
        local warnings = CollectStartWarnings()
        pendingStartWarnings = warnings
        if #warnings > 0 then
            ImGui.OpenPopup('Safe Start Check##UEA')
        else
            bottomActionMsg = 'Preflight: no risky settings found'
            if allowStart then
                RunStartCommand()
            end
        end
    end

    local function GetMacroStatus()
        if not mq.TLO.Macro() or mq.TLO.Macro.Name() ~= 'muleassist.mac' then
            return 'STOPPED', {1.00, 0.35, 0.35, 1.0}
        end
        if mq.TLO.Macro.Paused() then
            return 'PAUSED', {1.00, 0.85, 0.20, 1.0}
        end
        return 'RUNNING', {0.30, 1.00, 0.45, 1.0}
    end

    if ImGui.Button('MemSpells', uniformButtonWidth, 0) then
        if TryBeginAction('memspells') then
            mq.cmdf('/memmyspells %s', globals.INIFile)
        end
    end
    ImGui.SameLine()
    if ImGui.Button('SaveGems', uniformButtonWidth, 0) then
        if TryBeginAction('savegems') then
            mq.cmd('/memspells save')
        end
    end
    ImGui.SameLine()
    if ImGui.Button('Ini Manager', uniformButtonWidth, 0) then
        filedialog.set_file_selector_open(true)
    end
    ImGui.SameLine()
    if ImGui.Button('README', uniformButtonWidth, 0) then
        pendingMainTab = 'Readme'
        bottomActionMsg = 'README: opened documentation'
    end
    ImGui.SameLine()
    if ImGui.Button('Remote', uniformButtonWidth, 0) then
        selectedSection = 'General'
        showAdvancedTabs = true
        pendingConfigTab = 'Utility'
        bottomActionMsg = 'Remote: opened Utility tab'
    end
    ImGui.SameLine()
    if ImGui.Button('Upgrades?', uniformButtonWidth, 0) then
        if TryBeginAction('upgrades') then
            local changed, checked, updatedGems = AutoRetuneAbilities('upgrade')
            showAdvancedTabs = true
            pendingConfigTab = 'Buffs & Cures'
            local queued = 0
            if autoMemAfterRetune then
                queued = QueueRetunedGemsForMem(updatedGems, memQueue)
            end
            if autoMemAfterRetune and queued > 0 then
                bottomActionMsg = string.format('Upgrades: %d/%d updated, queued %d gems', changed, checked, queued)
            else
                bottomActionMsg = string.format('Upgrades: %d/%d entries updated', changed, checked)
            end
        end
    end
    ImGui.SameLine()
    if ImGui.Button('Downgrades?', uniformButtonWidth, 0) then
        if TryBeginAction('downgrades') then
            local changed, checked, updatedGems = AutoRetuneAbilities('downgrade')
            showAdvancedTabs = true
            pendingConfigTab = 'Buffs & Cures'
            local queued = 0
            if autoMemAfterRetune then
                queued = QueueRetunedGemsForMem(updatedGems, memQueue)
            end
            if autoMemAfterRetune and queued > 0 then
                bottomActionMsg = string.format('Downgrades: %d/%d updated, queued %d gems', changed, checked, queued)
            else
                bottomActionMsg = string.format('Downgrades: %d/%d entries updated', changed, checked)
            end
        end
    end
    ImGui.SameLine()
    local prevAutoMem = autoMemAfterRetune
    autoMemAfterRetune = ImGui.Checkbox('AutoMem##Retune', autoMemAfterRetune)
    if prevAutoMem ~= autoMemAfterRetune then
        SaveMAUIConfig()
    end
    ImGui.SameLine()
    if ImGui.Button('HotButtons', uniformButtonWidth, 0) then
        selectedSection = 'General'
        showAdvancedTabs = true
        pendingConfigTab = 'Utility'
        bottomActionMsg = 'HotButtons: opened Utility tab'
    end
    ImGui.SameLine()
    if ImGui.Button('Gem Manager', uniformButtonWidth, 0) then
        selectedSection = 'SpellSet'
        showAdvancedTabs = true
        pendingConfigTab = 'SpellSet / Gems'
        bottomActionMsg = 'Gem Manager: opened SpellSet / Gems'
    end

    ImGui.SameLine()
    local macroStatus, macroColor = GetMacroStatus()
    ImGui.TextColored(macroColor[1], macroColor[2], macroColor[3], macroColor[4], 'Macro: '..macroStatus)
    ImGui.SameLine()
    if macroStatus == 'RUNNING' then
        if ImGui.Button('Pause', 60, 0) and TryBeginAction('pause') then
            mq.cmd('/mqp on')
            bottomActionMsg = 'Macro paused'
        end
        ImGui.SameLine()
    elseif macroStatus == 'PAUSED' then
        if ImGui.Button('Resume', 64, 0) and TryBeginAction('resume') then
            mq.cmd('/mqp off')
            bottomActionMsg = 'Macro resumed'
        end
        ImGui.SameLine()
    end
    if macroStatus ~= 'STOPPED' then
        if ImGui.Button('End', 48, 0) and TryBeginAction('endmacro') then
            mq.cmd('/end')
            bottomActionMsg = 'Macro ended'
        end
        ImGui.SameLine()
    end

    ImGui.SameLine()
    local curX = ImGui.GetCursorPosX()
    local availX = ImGui.GetContentRegionAvail()
    local startWidth = 130
    local targetX = curX + math.max(0, availX - startWidth)
    if bottomActionMsg ~= '' then
        local textW = ImGui.CalcTextSize(bottomActionMsg)
        local msgX = math.max(curX, targetX - textW - 12)
        ImGui.SetCursorPosX(msgX)
        ImGui.TextColored(0.45, 0.90, 0.98, 1.0, bottomActionMsg)
        ImGui.SameLine()
    end
    ImGui.SetCursorPosX(targetX)
    if ImGui.Button('Preflight', 68, 0) then
        if TryBeginAction('preflight') then
            RunPreflight(false)
        end
    end
    ImGui.SameLine()
    if ImGui.Button('Start') then
        if TryBeginAction('start') then
            RunPreflight(true)
        end
    end
    if ImGui.BeginPopupModal('Safe Start Check##UEA', true, ImGuiWindowFlags.AlwaysAutoResize) then
        ImGui.TextWrapped('Preflight found risky settings:')
        ImGui.Separator()
        if pendingStartWarnings then
            for _, warning in ipairs(pendingStartWarnings) do
                ImGui.BulletText(warning)
            end
        end
        ImGui.Separator()
        if ImGui.Button('Start Anyway', 140, 0) then
            RunStartCommand()
            pendingStartWarnings = nil
            ImGui.CloseCurrentPopup()
        end
        ImGui.SameLine()
        if ImGui.Button('Fix Now', 100, 0) then
            pendingConfigTab = 'Setup'
            pendingStartWarnings = nil
            ImGui.CloseCurrentPopup()
        end
        ImGui.EndPopup()
    end
end

DrawPanelHeader = function(text)
    ImGui.TextColored(0.45, 0.90, 0.98, 1.0, text)
    ImGui.Separator()
end

local function DrawCodeSnippet(snippet)
    ImGui.PushStyleColor(ImGuiCol.Text, 0.72, 0.95, 1.00, 1.00)
    ImGui.TextWrapped(snippet)
    ImGui.PopStyleColor()
    ImGui.Separator()
end

local smartlootMockScreenNames = {
    '1. Loot Rules Editor',
    '2. Choose Action Popup',
    '3. Peer Rule Editor',
    '4. How It Works',
    '5. Peer Loot Order',
    '6. Settings',
    '7. Peer Commands',
    '8. Not Looting Checks',
    '9. AFK + Whitelist',
    '10. Validation',
}

local function DrawMockTitle(title)
    ImGui.TextColored(0.70, 0.88, 1.00, 1.00, title)
    ImGui.Separator()
end

local function DrawMockField(label, value, width)
    ImGui.Text(label)
    ImGui.SameLine(220)
    ImGui.Button(value, width or 220, 0)
end

local function DrawSmartLootMockScreen(screen, idSuffix)
    local childId = '##UEA_SmartLootMockCanvas' .. tostring(idSuffix or '')
    if not ImGui.BeginChild(childId, -1, 320, ImGuiChildFlags.Border) then
        ImGui.EndChild()
        return
    end

    if screen == 1 then
        DrawMockTitle('SmartLoot - Loot Rules Editor (Mock)')
        ImGui.Button('Loot Rules Editor', 130, 0); ImGui.SameLine()
        ImGui.Button('AFK Farm Rules', 110, 0); ImGui.SameLine()
        ImGui.Button('Settings', 80, 0); ImGui.SameLine()
        ImGui.Button('Loot History', 90, 0); ImGui.SameLine()
        ImGui.Button('Loot Statistics', 100, 0); ImGui.SameLine()
        ImGui.Button('Peer Loot Order', 100, 0)
        ImGui.Separator()
        DrawMockField('Search:', 'Dual-Blade', 180)
        DrawMockField('Character:', 'Linamas', 140)
        ImGui.Separator()
        if ImGui.BeginTable('##UEA_SLMockRulesTable', 5, ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg) then
            ImGui.TableSetupColumn('Item')
            ImGui.TableSetupColumn('Item ID')
            ImGui.TableSetupColumn('Rule')
            ImGui.TableSetupColumn('Peers')
            ImGui.TableSetupColumn('Action')
            ImGui.TableHeadersRow()
            local rows = {
                {'Dose Potion 100%', '119930', 'Ignore', 'Peers', 'Delete'},
                {'100k AA Crystal', '50390', 'Keep', 'Peers', 'Delete'},
                {'20k AA Crystal', '135455', 'KeepIfFewerThan 5', 'Peers', 'Delete'},
            }
            for _, row in ipairs(rows) do
                ImGui.TableNextRow()
                for col = 1, 5 do
                    ImGui.TableSetColumnIndex(col - 1)
                    ImGui.Text(row[col])
                end
            end
            ImGui.EndTable()
        end
    elseif screen == 2 then
        DrawMockTitle('SmartLoot - Choose Action (Mock)')
        ImGui.Text('Item requiring decision:')
        ImGui.Button('Dual-Blade of Reckoning', 340, 0)
        ImGui.Separator()
        DrawMockField('Select rule:', 'Keep', 160)
        ImGui.Spacing()
        ImGui.Button('Apply To All Connected Peers', 210, 0)
        ImGui.SameLine()
        ImGui.Button('Apply To Just Me & Process', 210, 0)
        ImGui.Spacing()
        ImGui.Button('Open Peer Rule Editor', 160, 0)
        ImGui.SameLine()
        ImGui.Button('Process as Ignored', 140, 0)
        ImGui.SameLine()
        ImGui.Button('Skip Item (Unset)', 130, 0)
    elseif screen == 3 then
        DrawMockTitle('Peer Rules for: Dual-Blade of Reckoning (Mock)')
        ImGui.Button('Set All to Keep', 120, 0); ImGui.SameLine()
        ImGui.Button('Set All to Ignore', 120, 0); ImGui.SameLine()
        ImGui.Button('Close', 80, 0)
        ImGui.Separator()
        if ImGui.BeginTable('##UEA_SLMockPeerRules', 3, ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg) then
            ImGui.TableSetupColumn('Peer')
            ImGui.TableSetupColumn('Rule')
            ImGui.TableSetupColumn('Action')
            ImGui.TableHeadersRow()
            local peerRows = {
                {'MainLooter', 'Ignore', 'Unset'},
                {'Cleric', 'Unset', 'Unset'},
                {'Dps', 'KeepIfFewerThan 15', 'Unset'},
                {'Bard', 'Unset', 'Unset'},
            }
            for _, row in ipairs(peerRows) do
                ImGui.TableNextRow()
                for col = 1, 3 do
                    ImGui.TableSetColumnIndex(col - 1)
                    ImGui.Text(row[col])
                end
            end
            ImGui.EndTable()
        end
    elseif screen == 4 then
        DrawMockTitle('SmartLoot - How It Works (Mock)')
        ImGui.Button('Main Looter: ON', 150, 0); ImGui.SameLine()
        ImGui.Button('Out of Combat', 120, 0); ImGui.SameLine()
        ImGui.Button('Pending Decisions: 0', 160, 0)
        ImGui.Separator()
        ImGui.Text('Waterfall Flow:')
        ImGui.Button('1) Process Corpse', 130, 0); ImGui.SameLine()
        ImGui.Text('->'); ImGui.SameLine()
        ImGui.Button('2) Evaluate Rules', 140, 0); ImGui.SameLine()
        ImGui.Text('->'); ImGui.SameLine()
        ImGui.Button('3) Trigger Peers', 120, 0); ImGui.SameLine()
        ImGui.Text('->'); ImGui.SameLine()
        ImGui.Button('4) Complete', 100, 0)
        ImGui.Spacing()
        if ImGui.BeginTable('##UEA_SLMockFlowTable', 3, ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg) then
            ImGui.TableSetupColumn('Stage')
            ImGui.TableSetupColumn('Condition')
            ImGui.TableSetupColumn('Result')
            ImGui.TableHeadersRow()
            local flowRows = {
                {'Main pass', 'Corpse in radius', 'Loot by main rules'},
                {'Ignore review', 'Ignored item found', 'Check peers by order'},
                {'Peer pass', 'Peer wants item', 'Send peer loot command'},
                {'End', 'No interested peers', 'Corpse marked complete'},
            }
            for _, row in ipairs(flowRows) do
                ImGui.TableNextRow()
                for col = 1, 3 do
                    ImGui.TableSetColumnIndex(col - 1)
                    ImGui.Text(row[col])
                end
            end
            ImGui.EndTable()
        end
    elseif screen == 5 then
        DrawMockTitle('Peer Loot Order (Mock)')
        if ImGui.BeginTable('##UEA_SLMockOrder', 2, ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg) then
            ImGui.TableSetupColumn('Position')
            ImGui.TableSetupColumn('Peer')
            ImGui.TableHeadersRow()
            local orderRows = {
                {'1', 'MainLooter'},
                {'2', 'Cleric'},
                {'3', 'Wizard'},
                {'4', 'Bard'},
            }
            for _, row in ipairs(orderRows) do
                ImGui.TableNextRow()
                ImGui.TableSetColumnIndex(0); ImGui.Text(row[1])
                ImGui.TableSetColumnIndex(1); ImGui.Text(row[2])
            end
            ImGui.EndTable()
        end
        ImGui.Spacing()
        ImGui.Button('Move Up', 90, 0); ImGui.SameLine()
        ImGui.Button('Move Down', 90, 0); ImGui.SameLine()
        ImGui.Button('Refresh Peers', 110, 0); ImGui.SameLine()
        ImGui.Button('Save Order', 120, 0)
    elseif screen == 6 then
        DrawMockTitle('Settings (Mock)')
        ImGui.Button('Pause', 90, 0)
        ImGui.Separator()
        ImGui.Text('Chat Output Settings')
        DrawMockField('Chat Output Mode', 'Raid Say (/rsay)', 220)
        ImGui.Text('Navigation Settings')
        DrawMockField('Navigation Command', '/nav', 220)
        DrawMockField('Fallback Command', '/moveto', 220)
        DrawMockField('Stop Command', '/nav stop', 220)
        ImGui.Text('Chase Integration Settings')
        DrawMockField('Enable Chase Commands', '[x] enabled', 220)
        DrawMockField('Chase Pause Command', '/luachase pause on', 220)
        DrawMockField('Chase Resume Command', '/luachase pause off', 220)
        ImGui.Spacing()
        ImGui.Button('/sl_save', 120, 0)
    elseif screen == 7 then
        DrawMockTitle('Peer Commands Window (Mock)')
        DrawMockField('Connected Peers', '24', 80)
        DrawMockField('Select Target Peer', 'Cleric', 150)
        ImGui.Spacing()
        ImGui.Button('Send Loot', 100, 0); ImGui.SameLine()
        ImGui.Button('Pause', 90, 0); ImGui.SameLine()
        ImGui.Button('Resume', 90, 0); ImGui.SameLine()
        ImGui.Button('Clear Cache', 100, 0)
        ImGui.Spacing()
        if ImGui.BeginTable('##UEA_SLMockPeerStatus', 3, ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg) then
            ImGui.TableSetupColumn('Peer')
            ImGui.TableSetupColumn('Mode')
            ImGui.TableSetupColumn('Looting')
            ImGui.TableHeadersRow()
            local peerStatusRows = {
                {'MainLooter', 'main', 'yes'},
                {'Cleric', 'background', 'no'},
                {'Wizard', 'background', 'no'},
            }
            for _, row in ipairs(peerStatusRows) do
                ImGui.TableNextRow()
                for col = 1, 3 do
                    ImGui.TableSetColumnIndex(col - 1)
                    ImGui.Text(row[col])
                end
            end
            ImGui.EndTable()
        end
    elseif screen == 8 then
        DrawMockTitle('Troubleshooting - Not Looting (Mock)')
        ImGui.Button('Check Mode', 120, 0); ImGui.SameLine()
        ImGui.Button('/sl_mode_status', 140, 0); ImGui.SameLine()
        ImGui.Button('Expected: main/once', 160, 0)
        ImGui.Button('Check State', 120, 0); ImGui.SameLine()
        ImGui.Button('/echo ${SmartLoot.State}', 190, 0); ImGui.SameLine()
        ImGui.Button('Expected: idle/finding', 170, 0)
        ImGui.Button('Reset Cache', 120, 0); ImGui.SameLine()
        ImGui.Button('/sl_clearcache', 120, 0); ImGui.SameLine()
        ImGui.Button('/sl_doloot', 100, 0)
        ImGui.Button('Peer Health', 120, 0); ImGui.SameLine()
        ImGui.Button('/sl_check_peers', 130, 0); ImGui.SameLine()
        ImGui.Button('/sl_engine_status', 140, 0)
        ImGui.Spacing()
        ImGui.Text('If still stuck: /sl_emergency_stop then /sl_resume')
    elseif screen == 9 then
        DrawMockTitle('AFK Temp Rules + Whitelist (Mock)')
        ImGui.Text('AFK Temp Rules')
        DrawMockField('Item Name', 'Short Sword', 200)
        DrawMockField('Rule', 'KeepIfFewerThan', 180)
        DrawMockField('Threshold', '5', 90)
        ImGui.Spacing()
        ImGui.Button('/sl_addtemp "Short Sword" KeepIfFewerThan 5', 320, 0)
        ImGui.Separator()
        ImGui.Text('Whitelist-Only (Per Character)')
        DrawMockField('Whitelist Only', '[x] enabled', 140)
        ImGui.Button('/sl_whitelistonly on', 170, 0); ImGui.SameLine()
        ImGui.Button('/sl_whitelist', 130, 0); ImGui.SameLine()
        ImGui.Button('/sl_whitelist off', 150, 0)
    elseif screen == 10 then
        DrawMockTitle('Validation Checklist (Mock)')
        if ImGui.BeginTable('##UEA_SLMockValidate', 3, ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg) then
            ImGui.TableSetupColumn('Check')
            ImGui.TableSetupColumn('Command')
            ImGui.TableSetupColumn('Pass Criteria')
            ImGui.TableHeadersRow()
            local checkRows = {
                {'Mode check', '/sl_mode_status', 'Main toon = main'},
                {'Engine state', '/sl_engine_status', 'No hard errors'},
                {'Waterfall', '/sl_waterfall_status', 'Peers trigger in order'},
                {'Corpse pass', '/sl_doloot', 'Nearby corpse processed'},
                {'Whitelist', '/sl_whitelistonly on', 'Only Keep items looted'},
            }
            for _, row in ipairs(checkRows) do
                ImGui.TableNextRow()
                for col = 1, 3 do
                    ImGui.TableSetColumnIndex(col - 1)
                    ImGui.Text(row[col])
                end
            end
            ImGui.EndTable()
        end
        ImGui.Spacing()
        ImGui.Button('/sl_mode_status', 140, 0); ImGui.SameLine()
        ImGui.Button('/sl_engine_status', 150, 0); ImGui.SameLine()
        ImGui.Button('/sl_waterfall_status', 160, 0); ImGui.SameLine()
        ImGui.Button('/sl_report all', 120, 0)
    end

    ImGui.EndChild()
end

local function DrawSmartLootGitHubOrderedGuide()
    ImGui.TextWrapped('Introducing SmartLoot! Your new, clean EverQuest Emulator Looting Partner!')
    ImGui.Spacing()
    ImGui.TextColored(0.85, 0.92, 1.0, 1.0, 'Screenshot 1 - Main SmartLoot Window')
    DrawSmartLootMockScreen(1, '_guide_1')

    ImGui.TextWrapped("Intended to be a smarter, easier, and efficient way of managing loot rules, SmartLoot was born out desperation - no more trying to remember who has how many of an item, or who's finished which quest. No more tabbing out of the game window to go change an .ini file to stop looting a certain item.")
    ImGui.Spacing()
    ImGui.TextWrapped("Within SmartLoot's interface, you can now add, change, remove, or update the rules for every character connected. It doesn't ship with a default database, since most emulators run their own custom content.")
    ImGui.Spacing()
    ImGui.TextWrapped('As you encounter new items, looting will pause and prompt you to make a decision.')
    ImGui.Spacing()
    ImGui.TextColored(0.85, 0.92, 1.0, 1.0, 'Screenshot 2 - Choose Action Popup')
    DrawSmartLootMockScreen(2, '_guide_2')

    ImGui.TextWrapped('From there, you can set it for everyone, just yourself, or open the peer rules editor and set it per user!')
    ImGui.Spacing()
    ImGui.TextColored(0.85, 0.92, 1.0, 1.0, 'Screenshot 3 - Peer Rules Editor')
    DrawSmartLootMockScreen(3, '_guide_3')

    ImGui.Spacing()
    ImGui.TextWrapped('But How Does It Work?!')
    ImGui.TextWrapped("Simple! Your Main Looter is responsible for processing all those pesky corpses laying around. That character will, when not in combat, begin cycling through nearby corpses and looting according to their rule set. When they've finished looted/processing the corpses, they'll go back through the list of items they ignored, and check to see if any of their buddies need or want that item based on their rules. If anyone has a rule of 'Keep' or 'KeepIfFewerThan', the main looter will send a command telling them to go loot! Then the process repeats on the triggered character, and down the line it goes until either all characters have processed the corpse, or there's no items left/no interested peers left.")
    ImGui.Spacing()

    ImGui.TextWrapped('Ok, but How Do I Get Started?!')
    ImGui.TextWrapped("Once you've got the script loaded, you can /sl_getstarted for an in game help, OR...")
    ImGui.Spacing()
    ImGui.TextWrapped("1) Go to the Peer Loot Order Tab and set your loot order! This is super important, since the whole system is based off of 'Who Loots First? What Loots Second?' The good news is, the order is saved globally so you don't need to set it on each character! It's stored in a local sqlite database, and you can change it 'on the fly'!")
    ImGui.TextColored(0.85, 0.92, 1.0, 1.0, 'Screenshot 4 - Peer Loot Order')
    DrawSmartLootMockScreen(5, '_guide_5')
    ImGui.Spacing()
    ImGui.TextWrapped("2) Once you've saved your Loot Order, embrace your inner Froglok, and hop on over to the Settings Tab. Here we'll need to tweak a couple things for your custom set up! Important Settings: a) Chat Output Settings - The System will announce various actions/activities. Choose your output channel, or Silent if you don't want to hear it! b) Navigation Commands - Choose the movement command SmartLoot should use to reach corpses (/nav, /moveto, /warp, etc.). You can also define a fallback if MQ2Nav isn't available and a stop command to send when looting finishes. c) Chase Commands - If you have any kind of auto chase set, set the pause/resume commands here. Otherwise if a corpse is further away than your leash, your toon will never get there!")
    ImGui.TextColored(0.85, 0.92, 1.0, 1.0, 'Screenshot 5 - Settings')
    DrawSmartLootMockScreen(6, '_guide_6')
    ImGui.Spacing()
    ImGui.TextWrapped("3) Give yourself a /sl_save to ensure that the config got saved, then restart the script! (Best to broadcast to all your peers to stop the script - /dgae, /e3bcaa, /bcaa, etc). Then, load 'er up on the main character!")
    ImGui.TextWrapped('/lua run smartloot')
    ImGui.Spacing()
    ImGui.TextWrapped("4) It's Smart so it'll auto detect who's in what mode based on their order in the Loot Order. Once she's running, go kill!")
    ImGui.Spacing()

    ImGui.TextWrapped('Helpful tips!')
    ImGui.TextWrapped('I tend to have the Peer Commands window open all the time.')
    ImGui.TextColored(0.85, 0.92, 1.0, 1.0, 'Screenshot 6 - Peer Commands Window')
    DrawSmartLootMockScreen(7, '_guide_7')
    ImGui.TextWrapped('This window lets you choose a targetted peer, and then send them individual commands.')
    ImGui.Spacing()
    ImGui.TextWrapped('DISCLAIMER')
    ImGui.TextWrapped("This is still a work in progress. I've done what I can to test, but MY use case may (hah, IS) different than YOUR use case. I look forward to ironing out the kinks!")
    ImGui.Spacing()

    ImGui.TextWrapped("Helpers and FAQ's")
    ImGui.TextWrapped('1) /sl_help will toggle a help window that shows you all the / commands for SmartLoot. I find these commands the most commonly used:')
    ImGui.BulletText('/sl_doloot - this triggers a "once" round of looting. If for some reason your character was out of the zone or missed the automatic trigger, you can issue a /sl_doloot command to them (this is also hard coded into the Peer Commands window).')
    ImGui.BulletText('/sl_peer_commands - I leave this window open all the time and dock it somewhere out of the way but accessible. The command toggles the visibility of the Peer Commands Window.')
    ImGui.BulletText("/sl_clearcache - This will clear the corpse cache. If for some reason you have a corpse at your feet and you're not looting, check if you're in Main Mode, or Once mode, then clear your corpse cache.")
    ImGui.BulletText('/sl_mode - This will output your current mode - helpful when checking the above! /sl_mode main/background - you can change modes with a command, or you can right click the floating button.')
    ImGui.BulletText('/sl_pause - Need to stop looting for some reason? /sl_pause will pause corpse processing until you toggle it back on. This is also hard coded into the Peer Commands window (it pauses looting on yourself, not the targetted peer).')
    ImGui.BulletText('/sl_stats - Toggle the Live Stats window.')
    ImGui.BulletText('/sl_chat - available options are raid, group, guild, custom (if you wanted a channel, for example) or silent.')
    ImGui.Spacing()
    ImGui.TextWrapped('2) Why am I not looting?!')
    ImGui.BulletText("Who knows?! Haha, not really. Check first: Are you in main looter mode? /sl_mode to check! If you are, and still aren't looting, are you in combat? You can check with: /echo ${SmartLoot.State}. Finally, did you already process this corpse? Try a /sl_clearcache and see if we start looting! Finally, if all else fails: /sl_doloot to kick yourself into a looting cycle.")
    ImGui.Spacing()
    ImGui.TextWrapped('3) The script needs to be running on all your characters simultaneously. To achieve this, we\'ll autobroadcast a start up message from our "Main" toon when it starts on that character. If you have the script set to run in a .cfg file or at start up on your character, the background guys might miss the command. Be sure it\'s running on everyone before you start hunting!')
    ImGui.Spacing()
    ImGui.TextWrapped("4) Item Stats - I'm not a mathematician, but I tried my best to keep the drop stats as accurate as possible. If you notice any oddities, please let me know.")
    ImGui.Spacing()
    ImGui.TextWrapped("5) The script does expose some TLO's if you wanted to integrate this into your own macro/bot system.")
    ImGui.BulletText('SmartLoot.State - this will return what State you\'re in. (Idle, Finding Corpse, Pending Decision, Combat Detected)')
    ImGui.BulletText('SmartLoot.Mode - this will return what Mode you\'re in. (Main, Background, Once, RGMain, RGOnce)')
    ImGui.BulletText('SmartLoot.CorpseCount - this will return how many corpses are in the configured loot radius')
    ImGui.BulletText("SmartLoot.SafeToLoot - a simple true/false to identify if we're in a mode and conditions are met for looting (e.g., out of combat, not casting, not moving)")
    ImGui.BulletText("SmartLoot.NeedsDecision - are we in a pending decision mode? This can be helpful if you're not paying attention to the chat spam. This'll return True for background peers if they're pending a decision.")
    ImGui.Spacing()

    ImGui.TextWrapped('AFK Temp Rules Mode')
    ImGui.TextWrapped("What's this AFK Rules tab?! Good question! The system is designed around saving loot rules based on itemID's. As such, since we don't have a precompiled database, in order to save a loot rule we need the item ID. AFK Farm Rules solves this temporarily. If you're going to let this run overnight (provided it's permitted on your server!), you can set temporary rules based on item names alone, and assign it to a peer. When it's encountered over night it'll apply the rule, and save the item to the database with all the pertinent information!")
    ImGui.Spacing()
    ImGui.TextColored(0.85, 0.92, 1.0, 1.0, 'Screenshot 8 - AFK + Whitelist')
    DrawSmartLootMockScreen(9, '_guide_9')

    ImGui.TextWrapped('Whitelist-Only Loot (per character)')
    ImGui.BulletText("Enable a character to only loot items you've explicitly set to Keep, and silently ignore everything else (no prompts).")
    ImGui.BulletText('Toggle it on the character you want: /sl_whitelistonly on to enable, /sl_whitelistonly off to disable.')
    ImGui.BulletText('Or enable it from Settings -> Character Settings -> "Whitelist-Only Loot (this character)".')
    ImGui.BulletText('Manage whitelist items: Settings -> Character Settings -> Manage Whitelist..., or command /sl_whitelist to open.')
    ImGui.Spacing()

    ImGui.TextWrapped('Bug fixes')
    ImGui.BulletText('Fixed a rule leakage bug where a resolved Keep rule could carry over to the next slot on the same corpse. The engine now clears the resolved item state after completing (or failing) a loot action so subsequent slots are evaluated independently.')
    ImGui.Spacing()

    ImGui.TextWrapped('How to validate')
    ImGui.BulletText('See tests/whitelist_leak_test.md for manual verification steps to run inside MacroQuest.')
    ImGui.BulletText('Optional: "Do not trigger peers" -> In Settings -> Character Settings, enable "Do not trigger peers while whitelist-only" if you do not want this toon to start waterfall triggers for others while running in whitelist-only mode.')
    ImGui.BulletText('How to "whitelist" items: add normal rules for those items (for example set Diamonds/Blue Diamonds to Keep for that toon). With whitelist-only enabled, only those Kept items will be looted; all other items are auto-ignored without asking.')
    ImGui.Spacing()
    ImGui.TextColored(0.85, 0.92, 1.0, 1.0, 'Screenshot 9 - Validation')
    DrawSmartLootMockScreen(10, '_guide_10')
end

local function DrawEZBotsMockScreen(screen, idSuffix)
    local childId = '##UEA_EZBotsMockCanvas' .. tostring(idSuffix or '')
    if not ImGui.BeginChild(childId, -1, 300, ImGuiChildFlags.Border) then
        ImGui.EndChild()
        return
    end

    if screen == 1 then
        DrawMockTitle('EZBots - Main Peer Monitor (Mock)')
        ImGui.Button('Options', 90, 0); ImGui.SameLine()
        ImGui.Button('Sort: Custom', 110, 0); ImGui.SameLine()
        ImGui.Button('Use Class Name', 120, 0)
        ImGui.Separator()
        if ImGui.BeginTable('##UEA_EZBotsMainTable', 8, ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg) then
            ImGui.TableSetupColumn('Peer')
            ImGui.TableSetupColumn('HP')
            ImGui.TableSetupColumn('End')
            ImGui.TableSetupColumn('Mana')
            ImGui.TableSetupColumn('Pet')
            ImGui.TableSetupColumn('Zone')
            ImGui.TableSetupColumn('Dist')
            ImGui.TableSetupColumn('Status')
            ImGui.TableHeadersRow()
            local rows = {
                {'MainTank', '100%', '91%', '62%', '-', 'same', '0', 'In Group'},
                {'Cleric', '98%', '45%', '89%', '-', 'same', '16', 'In Group'},
                {'Bard', '100%', '84%', '-', '-', 'other', '--', 'Raid Only'},
            }
            for _, row in ipairs(rows) do
                ImGui.TableNextRow()
                for c = 1, 8 do
                    ImGui.TableSetColumnIndex(c - 1)
                    ImGui.Text(row[c])
                end
            end
            ImGui.EndTable()
        end
        ImGui.Spacing()
        ImGui.Text('Left-click peer: switch to that character. Right-click peer: target that character.')
    elseif screen == 2 then
        DrawMockTitle('EZBots - Zone Color Behavior (Mock)')
        ImGui.TextColored(0.75, 1.0, 0.75, 1.0, 'Green names = same zone')
        ImGui.TextColored(1.0, 0.75, 0.75, 1.0, 'Red names = out of zone')
        ImGui.Separator()
        ImGui.Button('Name View', 100, 0); ImGui.SameLine()
        ImGui.Button('Class View', 100, 0)
        ImGui.Spacing()
        if ImGui.BeginTable('##UEA_EZBotsZoneTable', 2, ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg) then
            ImGui.TableSetupColumn('Display')
            ImGui.TableSetupColumn('Zone State')
            ImGui.TableHeadersRow()
            ImGui.TableNextRow(); ImGui.TableSetColumnIndex(0); ImGui.TextColored(0.75,1,0.75,1,'MainTank'); ImGui.TableSetColumnIndex(1); ImGui.Text('Same Zone')
            ImGui.TableNextRow(); ImGui.TableSetColumnIndex(0); ImGui.TextColored(1,0.75,0.75,1,'Bard'); ImGui.TableSetColumnIndex(1); ImGui.Text('Different Zone')
            ImGui.EndTable()
        end
    elseif screen == 3 then
        DrawMockTitle('EZBots - Custom Sort Editor (Mock)')
        ImGui.Button('Alphabetical', 110, 0); ImGui.SameLine()
        ImGui.Button('HP', 70, 0); ImGui.SameLine()
        ImGui.Button('Distance', 90, 0); ImGui.SameLine()
        ImGui.Button('Class', 80, 0); ImGui.SameLine()
        ImGui.Button('Group', 80, 0); ImGui.SameLine()
        ImGui.Button('Custom', 90, 0)
        ImGui.Separator()
        if ImGui.BeginTable('##UEA_EZBotsSortTable', 3, ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg) then
            ImGui.TableSetupColumn('Order')
            ImGui.TableSetupColumn('Entry')
            ImGui.TableSetupColumn('Action')
            ImGui.TableHeadersRow()
            local rows = {
                {'1', 'MainTank', 'Move / Remove'},
                {'2', '--- Healers ---', 'Move / Remove'},
                {'3', 'Cleric', 'Move / Remove'},
                {'4', 'Bard', 'Move / Remove'},
            }
            for _, row in ipairs(rows) do
                ImGui.TableNextRow()
                for c = 1, 3 do
                    ImGui.TableSetColumnIndex(c - 1)
                    ImGui.Text(row[c])
                end
            end
            ImGui.EndTable()
        end
        ImGui.Spacing()
        ImGui.Button('Add Filler Row', 120, 0); ImGui.SameLine()
        ImGui.Button('Save Layout', 110, 0)
    elseif screen == 4 then
        DrawMockTitle('EZBots - Peer Context Menu (Mock)')
        ImGui.Text('Right-click peer opens quick actions:')
        ImGui.Separator()
        ImGui.Button('Follow Me', 110, 0); ImGui.SameLine()
        ImGui.Button('Stop Follow', 110, 0); ImGui.SameLine()
        ImGui.Button('Nav To Peer', 110, 0); ImGui.SameLine()
        ImGui.Button('Nav Stop', 90, 0)
        ImGui.Button('Make Camp On', 110, 0); ImGui.SameLine()
        ImGui.Button('Make Camp Off', 120, 0); ImGui.SameLine()
        ImGui.Button('Pause MQ', 100, 0); ImGui.SameLine()
        ImGui.Button('Resume MQ', 100, 0)
        ImGui.Button('Target Peer', 110, 0); ImGui.SameLine()
        ImGui.Button('Invite', 90, 0); ImGui.SameLine()
        ImGui.Button('Raid Invite', 110, 0)
    elseif screen == 5 then
        DrawMockTitle('EZBots - Command Helpers (Mock)')
        if ImGui.BeginTable('##UEA_EZBotsCmdTable', 2, ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg) then
            ImGui.TableSetupColumn('Command')
            ImGui.TableSetupColumn('Use')
            ImGui.TableHeadersRow()
            local rows = {
                {'/aclist', 'list connected peers'},
                {'/actell <peer> <cmd>', 'send command to one peer'},
                {'/aca <cmd>', 'send command to all other peers'},
                {'/acaa <cmd>', 'send command to all peers including self'},
                {'/acalias <alias> <cmd>', 'send command to alias group'},
                {'/acreloadaliases', 'reload alias file'},
            }
            for _, row in ipairs(rows) do
                ImGui.TableNextRow()
                ImGui.TableSetColumnIndex(0); ImGui.Text(row[1])
                ImGui.TableSetColumnIndex(1); ImGui.Text(row[2])
            end
            ImGui.EndTable()
        end
    end

    ImGui.EndChild()
end

local function DrawEZBotsGitHubOrderedGuide()
    ImGui.TextWrapped('A lightweight resource to help monitor all your connected bots. Script must run on all characters, giving you a Heads Up on who is where, what, when and how.')
    ImGui.Spacing()
    ImGui.TextWrapped('DPS functions have been removed (matching current upstream note).')
    ImGui.Spacing()

    ImGui.TextColored(0.85, 0.92, 1.0, 1.0, 'Screenshot 1 - Main Monitor')
    DrawEZBotsMockScreen(1, '_guide_1')
    ImGui.Spacing()
    ImGui.TextWrapped('Left click a character to switch to their screen. Right click to target that character.')
    ImGui.TextWrapped('Characters in the same zone appear in green - out of zone appear in red. Toggle between Character names or Character Class.')
    ImGui.TextColored(0.85, 0.92, 1.0, 1.0, 'Screenshot 2 - Zone Colors / Name-Class Toggle')
    DrawEZBotsMockScreen(2, '_guide_2')
    ImGui.Spacing()

    ImGui.TextWrapped('Apply a custom sort order through a graphical, intuitive UI. You can add in custom filler rows to break up your army of toons.')
    ImGui.TextColored(0.85, 0.92, 1.0, 1.0, 'Screenshot 3 - Sort UI')
    DrawEZBotsMockScreen(3, '_guide_3')
    ImGui.Spacing()
    ImGui.TextWrapped('Persistent, but be sure to save your configuration through the right click menu option.')
    ImGui.Spacing()

    ImGui.TextWrapped('Context actions and group-control helpers from peer right-click menu:')
    DrawEZBotsMockScreen(4, '_guide_4')
    ImGui.Spacing()

    ImGui.TextWrapped('Command helpers (actor peer command system):')
    DrawEZBotsMockScreen(5, '_guide_5')
    ImGui.Spacing()

    ImGui.TextWrapped('Core files:')
    DrawCodeSnippet('Config/peer_ui_config.json\nConfig/peer_aliases.ini')
    ImGui.TextWrapped('Startup and save:')
    DrawCodeSnippet('/lua run ezbots\n/savepeerui')
end

local function DrawMauiMockMainUI(idSuffix)
    local childId = '##UEA_MAUI_MockMain' .. tostring(idSuffix or '')
    if not ImGui.BeginChild(childId, -1, 240, ImGuiChildFlags.Border) then
        ImGui.EndChild()
        return
    end
    DrawMockTitle('MAUI - Main UI (Mock)')
    ImGui.Button('UI', 40, 0); ImGui.SameLine()
    ImGui.Button('RAW', 50, 0)
    ImGui.Separator()
    ImGui.Button('General', 70, 0); ImGui.SameLine()
    ImGui.Button('Combat', 70, 0); ImGui.SameLine()
    ImGui.Button('Buffs & Cures', 100, 0); ImGui.SameLine()
    ImGui.Button('Healing & OhShit', 110, 0); ImGui.SameLine()
    ImGui.Button('SpellSet / Gems', 110, 0)
    ImGui.Separator()
    DrawMockField('INI File', 'MuleAssist_E9_80.ini', 240)
    DrawMockField('Section', 'DPS', 120)
    DrawMockField('Entry', 'DPS1', 120)
    ImGui.EndChild()
end

local function DrawMauiMockListEntryParts(idSuffix)
    local childId = '##UEA_MAUI_MockParts' .. tostring(idSuffix or '')
    if not ImGui.BeginChild(childId, -1, 220, ImGuiChildFlags.Border) then
        ImGui.EndChild()
        return
    end
    DrawMockTitle('MAUI - Editing List Entries (Mock)')
    DrawCodeSnippet('Buffs1=Wand of Frozen Modulation|Summon|Wand of Restless Modulation|1|ME\nBuffsCond1=TRUE')
    ImGui.Separator()
    DrawMockField('Name', 'Wand of Frozen Modulation', 300)
    DrawMockField('Options', 'Summon|Wand of Restless Modulation|1|ME', 300)
    DrawMockField('Conditions', 'TRUE', 120)
    ImGui.EndChild()
end

local function DrawMauiMockPickerMenu(idSuffix)
    local childId = '##UEA_MAUI_MockPicker' .. tostring(idSuffix or '')
    if not ImGui.BeginChild(childId, -1, 180, ImGuiChildFlags.Border) then
        ImGui.EndChild()
        return
    end
    DrawMockTitle('MAUI - Right Click Picker (Mock)')
    ImGui.Text('Right-click icon -> choose source:')
    ImGui.Button('Spells', 90, 0); ImGui.SameLine()
    ImGui.Button('AAs', 90, 0); ImGui.SameLine()
    ImGui.Button('Discs', 90, 0)
    ImGui.Separator()
    ImGui.Button('Arcane Hymn', 180, 0); ImGui.SameLine()
    ImGui.Button('Fierce Eye', 180, 0)
    ImGui.EndChild()
end

local function DrawMauiMockUpgrade(idSuffix)
    local childId = '##UEA_MAUI_MockUpgrade' .. tostring(idSuffix or '')
    if not ImGui.BeginChild(childId, -1, 150, ImGuiChildFlags.Border) then
        ImGui.EndChild()
        return
    end
    DrawMockTitle('MAUI - Upgrades / Downgrades (Mock)')
    DrawMockField('Current Spell', 'War March of Meldrath Rk. II', 260)
    ImGui.Button('Upgrades?', 110, 0); ImGui.SameLine()
    ImGui.Button('Downgrades?', 120, 0); ImGui.SameLine()
    ImGui.Button('AutoMem', 90, 0)
    ImGui.EndChild()
end

local function DrawMauiMockRaw(idSuffix)
    local childId = '##UEA_MAUI_MockRaw' .. tostring(idSuffix or '')
    if not ImGui.BeginChild(childId, -1, 170, ImGuiChildFlags.Border) then
        ImGui.EndChild()
        return
    end
    DrawMockTitle('MAUI - Raw INI Editor (Mock)')
    DrawCodeSnippet('[General]\nDanNetOn=1\nChaseDistance=25\n...\n[DPS]\nDPS1=Blade of Vesagran|99')
    ImGui.Button('Save Raw', 90, 0); ImGui.SameLine()
    ImGui.Button('Reload Raw', 95, 0)
    ImGui.EndChild()
end

local function DrawMauiMockImportKA(idSuffix)
    local childId = '##UEA_MAUI_MockImportKA' .. tostring(idSuffix or '')
    if not ImGui.BeginChild(childId, -1, 170, ImGuiChildFlags.Border) then
        ImGui.EndChild()
        return
    end
    DrawMockTitle('MAUI - Import KA INI (Mock)')
    DrawMockField('KA INI File', 'KissAssist_E9_70.ini', 220)
    ImGui.Button('Import', 90, 0); ImGui.SameLine()
    ImGui.Button('ReLoad', 90, 0)
    ImGui.Separator()
    ImGui.Text('Conversion maps shared keys and converts KConditions to MA *Cond entries.')
    ImGui.EndChild()
end

local function DrawMauiDocsOverviewGuide()
    ImGui.TextWrapped('MAUI')
    ImGui.TextWrapped('An INI Editor for the MuleAssist macro.')
    ImGui.Spacing()
    DrawMauiMockMainUI('_docs_1')
    ImGui.Spacing()

    ImGui.TextWrapped('Overview')
    ImGui.TextWrapped('MAUI is a replacement for the MQ2Mule plugin so that MuleAssist users can continue to have a UI to make INI updates.')
    ImGui.TextWrapped("It doesn't do everything which the old plugin did, but it should look pretty familiar.")
    ImGui.Spacing()

    ImGui.TextWrapped('Installation')
    ImGui.TextWrapped('Manual Install')
    ImGui.BulletText('Clone the repo or download the zip file linked above.')
    ImGui.BulletText('Move the maui folder into the MQ lua folder.')
    ImGui.BulletText('Start the script with /lua run maui and accept the prompt to install lfs.dll.')
    ImGui.Spacing()
    ImGui.TextWrapped('RedGuides Launcher')
    ImGui.BulletText('Navigate to the MAUI resource page and click Watch on the Overview tab.')
    ImGui.BulletText('Open the RedGuides Launcher and install MAUI from the Lua tab.')
    ImGui.BulletText('Start the script with /lua run maui and accept the prompt to install lfs.dll.')
    ImGui.Spacing()
    ImGui.TextWrapped('The resulting folder content should look like this:')
    DrawCodeSnippet('lua/\n├── maui/\n│   ├── addons/\n│   │   └── ma.lua\n│   ├── lib/\n│   │   └── Cache.lua\n│   │   └── ImGuiFileDialog.lua\n│   │   └── LIP.lua\n│   ├── schemas/\n│   │   └── ma.lua\n│   ├── globals.lua\n│   ├── init.lua\n│   └── utils.lua')
    ImGui.TextWrapped('lfs.dll is lua file system from the MQ LuaRocks Server.')
    ImGui.Spacing()

    ImGui.TextWrapped('Commands')
    DrawCodeSnippet('/lua run maui -- Start the script\n/lua stop maui -- End the script\n/maui stop -- Stop MAUI\n/maui -- MAUI Help\n/maui hide -- Hide MAUI\n/maui show -- Show MAUI\n/mqoverlay resume -- Recover ImGui windows in case of an error')
    ImGui.Spacing()

    ImGui.TextWrapped('Editing List Entries')
    ImGui.TextWrapped('List entries in the MA INI file, like DPS1 or Heals1, are made up of multiple parts, as well as an associated condition, like DPSCond1. For example:')
    DrawCodeSnippet('Buffs1=Wand of Frozen Modulation|Summon|Wand of Restless Modulation|1|ME\nBuffsCond1=TRUE')
    ImGui.TextWrapped('MAUI breaks this line up into 3 pieces of information:')
    ImGui.BulletText('Name -- Everything up to the first pipe (|), typically the spell or item name.')
    ImGui.BulletText('Options -- Everything after the first pipe (|).')
    ImGui.BulletText('Conditions -- The entire condition entry.')
    ImGui.Spacing()
    DrawMauiMockListEntryParts('_docs_2')
    ImGui.Spacing()
    ImGui.TextWrapped('In addition to typing in a value for the name, you can right click the icon in the list and navigate spells, discs and AAs from the context menu.')
    DrawMauiMockPickerMenu('_docs_3')
    ImGui.Spacing()

    ImGui.TextWrapped('Upgrading Spells')
    ImGui.TextWrapped('When viewing the details of a list entry, an upgrade button will be displayed if it is determined that you have a stronger version of the spell memorized. The logic for detecting stronger spells is far from perfect, so it might be wrong a lot of the time.')
    ImGui.TextWrapped("Similarly, downgrades will be suggested. This is in case you imported an INI which is above your level, and includes spells which you don't have memorized yet.")
    DrawMauiMockUpgrade('_docs_4')
    ImGui.Spacing()

    ImGui.TextWrapped('Raw INI Editor')
    ImGui.TextWrapped('The INI file can still be edited directly through the Raw INI tab.')
    DrawMauiMockRaw('_docs_5')
    ImGui.Spacing()

    ImGui.TextWrapped('Importing KissAssist INI Files')
    ImGui.TextWrapped('MAUI can import KA INI files and convert them to MA INI files. This has only been tested with a limited number of KA12 INI files, so YMMV. It works like so:')
    ImGui.BulletText('Place the KA INI you wish to import into your MQ config folder.')
    ImGui.BulletText('On the Import KA INI section, enter the file name (no file explorer, it must be typed manually/pasted in).')
    ImGui.BulletText('Click Import.')
    ImGui.TextWrapped('All keys common to both KA and MA are copied to the resulting MA INI. KA-only or MA-only keys are not set. Lines with KA conditions are converted to MA *Cond entries.')
    DrawMauiMockImportKA('_docs_6')
end

local function DrawReadmeTab()
    DrawPanelHeader('MQ2 Advanced Automation Suite - In-UI README')
    if ImGui.BeginTabBar('##UEA_ReadmeTabs') then
        if ImGui.BeginTabItem('Overview') then
            DrawMauiDocsOverviewGuide()
            ImGui.EndTabItem()
        end

        if ImGui.BeginTabItem('Setup') then
            ImGui.BulletText('Prereq: matched MQ2 build for your EQ client.')
            ImGui.BulletText('Load plugins in stable order: cast -> movement -> melee -> nav -> events -> netbots.')
            ImGui.BulletText('Place macro in Macros\\\\ and INIs in Config\\\\.')
            ImGui.BulletText('Use character profile first, then class/default fallback.')
            ImGui.BulletText('INI precedence: Character > Class > Default.')
            DrawCodeSnippet('/plugin mq2cast load\n/plugin mq2melee load\n/plugin mq2moveutils load\n/plugin mq2nav load')
            DrawCodeSnippet('/mac AdvancedSuite assist Tankname\n/mqp on\n/mqp off\n/end')
            ImGui.TextWrapped('Startup troubleshooting: if no actions occur, verify role, MainAssist, and that relevant section toggles are on (HealsOn/BuffsOn/DPSOn/etc).')
            ImGui.EndTabItem()
        end

        if ImGui.BeginTabItem('Commands') then
            ImGui.TextWrapped('Core macro command set:')
            ImGui.BulletText('/asuite help')
            ImGui.BulletText('/asuite on | /asuite off')
            ImGui.BulletText('/asuite reload')
            ImGui.BulletText('/asuite role <assist|tank|manual|puller>')
            ImGui.BulletText('/asuite ma <name>')
            ImGui.BulletText('/asuite camp set|clear')
            ImGui.BulletText('/asuite burn on|off|now')
            ImGui.BulletText('/asuite pause <module> | /asuite resume <module>')
            ImGui.BulletText('/asuite debug on|off')
            ImGui.Spacing()
            ImGui.TextWrapped('High-use MQ2 commands (enhanced/used heavily):')
            ImGui.BulletText('/cast, /memspell, /stick, /moveto, /nav, /melee, /target id, /ini, /if, /while, /for')
            ImGui.BulletText('/bca //cmd and /bct Toon //cmd for multibox coordination')
            DrawCodeSnippet('/bca //asuite burn on\n/bct Cleric //casting "Divine Arbitration"')
            ImGui.EndTabItem()
        end

        if ImGui.BeginTabItem('INI Guide') then
            ImGui.TextWrapped('Master INI grouping (from full README structure):')
            ImGui.BulletText('4.1 Global & General Settings')
            ImGui.BulletText('4.2 Combat & DPS')
            ImGui.BulletText('4.3 Healing, Curing & Prevention')
            ImGui.BulletText('4.4 Buffing & Maintenance')
            ImGui.BulletText('4.5 Pulling, Aggro & Targeting')
            ImGui.BulletText('4.6 Loot, Navigation & Movement')
            ImGui.BulletText('4.7 Plugin-Specific Sections')
            ImGui.BulletText('4.8 Custom/Advanced Sections')
            ImGui.Spacing()
            ImGui.TextWrapped('Key INI patterns:')
            DrawCodeSnippet('[General]\nRole=assist\nMainAssist=Tankname\nEnabled=1\nAssistRange=100\nCampRadius=40\nChaseAssist=0\nLoopDelayMS=50')
            DrawCodeSnippet('[DPS]\nDPSOn=1\nDPSSize=2\nDPS1=Riotous Servant|99|Cond:${Target.Named}\nDPS2=Chaotic Fire|40|Cond:${Me.PctMana}>45')
            DrawCodeSnippet('[Heals]\nHealsOn=1\nHealSize=3\nHeal1=Complete Heal|35|Cond:${Me.PctHPs}<35\nHeal2=Remedy|55|Cond:${Group.MainTank.PctHPs}<55')
            ImGui.TextWrapped('INI read/write examples:')
            DrawCodeSnippet('${Ini[Config\\\\AdvancedSuite_MyServer_MyChar.ini,General,AssistRange]}\n/ini \"Config\\\\AdvancedSuite_MyServer_MyChar.ini\" \"General\" \"AssistRange\" \"100\"')
            ImGui.EndTabItem()
        end

        if ImGui.BeginTabItem('Conditions') then
            ImGui.TextWrapped('Condition syntax primer: operators (==, !=, >, <, >=, <=), boolean (!, &&, ||), nesting with ${If[]} and ${Select[]}.')
            ImGui.BulletText('Combat: ${Target.ID} && ${Target.Distance}<30 && ${Target.Type.Equal[NPC]}')
            ImGui.BulletText('Buffing: !${Me.Buff[Shield of Destiny].ID} && ${Me.PctMana}>30')
            ImGui.BulletText('Healing: ${Me.PctHPs}<35 || ${Group.MainTank.PctHPs}<50')
            ImGui.BulletText('Adds: ${SpawnCount[npc radius 35 aggro]}>2')
            ImGui.BulletText('Group damage: ${Group.Injured[60]}>=3')
            ImGui.BulletText('Branching: ${If[${Me.PctMana}<20,LOW,OK]}')
            ImGui.Spacing()
            ImGui.TextWrapped('Bad vs Good:')
            ImGui.BulletText('Bad: ${SpawnCount[npc]}>0')
            ImGui.BulletText('Good: ${SpawnCount[npc radius 120 los noalert 1]}>0')
            ImGui.BulletText('Bad: !${Target.Buff[Debuff].ID}')
            ImGui.BulletText('Good: ${Target.ID} && !${Target.Buff[Debuff].ID}')
            ImGui.BulletText('Bad: expensive nested Spawn queries every pulse')
            ImGui.BulletText('Good: cache/reduce wide queries; cheap checks first for short-circuiting')
            ImGui.EndTabItem()
        end

        if ImGui.BeginTabItem('Features') then
            ImGui.BulletText('Auto-Assist & Combat Loop')
            ImGui.BulletText('Casting Engine (MQ2Cast integration)')
            ImGui.BulletText('Movement & Pathing (Stick/Nav)')
            ImGui.BulletText('Healing Priority & Emergency')
            ImGui.BulletText('Pulling System')
            ImGui.BulletText('Buff Maintenance (Downshit/Holyshit)')
            ImGui.BulletText('Event Handling')
            ImGui.BulletText('Multibox Broadcasting (/bca, /bct, netbots)')
            ImGui.Spacing()
            ImGui.TextWrapped('Flow overview:')
            DrawCodeSnippet('Med if low resource -> Buff maintenance -> Heal/Cure checks -> Combat routine -> Loot/nav return -> Idle/camp')
            ImGui.EndTabItem()
        end

        if ImGui.BeginTabItem('Examples') then
            DrawCodeSnippet('Sub CombatPulse\n  /if (${Target.ID} && ${Target.Distance}<100) /attack on\n  /if (${Me.PctHPs}<35) /casting "Complete Heal"\n  /if (${Target.Named} && ${Me.PctMana}>40) /alt activate 15073\n/return')
            DrawCodeSnippet('Sub HealPriority\n  /if (${Me.PctHPs}<35) /casting "Complete Heal"\n  /if (${Group.MainTank.PctHPs}<55) /casting "Remedy"\n  /if (${Group.Injured[60]}>=3) /casting "Word of Reformation"\n/return')
            DrawCodeSnippet('Sub BuffCheck\n  /if (!${Me.Buff[Shield of Destiny].ID}) /casting "Shield of Destiny"\n  /if (${Pet.ID} && !${Pet.Buff[Burnout].ID}) /casting "Burnout"\n/return')
            DrawCodeSnippet('Sub PullLogic\n  /if (${SpawnCount[npc radius 200 los]}>0) /target npc radius 200\n  /if (${Target.ID}) /casting "Snare of Stone"\n/return')
            DrawCodeSnippet('Sub Holyshit\n  /if (${Me.PctHPs}<30) /alt activate 15073\n  /if (${SpawnCount[npc radius 30 aggro]}>3) /bcaa //alt activate 202\n/return')
            ImGui.EndTabItem()
        end

        if ImGui.BeginTabItem('Advanced') then
            ImGui.BulletText('Use short, pulse-based subroutines (DoHeals, DoDPS, DoBuffs, DoPull).')
            ImGui.BulletText('Keep expensive Spawn queries bounded by radius, LOS, and noalert filters.')
            ImGui.BulletText('Tune LoopDelayMS and module toggles for low CPU overhead.')
            ImGui.BulletText('Debug with /echo, /mqlog, and explicit branch traces.')
            ImGui.BulletText('Use role-specific profile INIs (assist/tank/puller/manual).')
            ImGui.BulletText('Prefer plugin delegation: MQ2Cast for execution, MQ2Melee for melee micro.')
            ImGui.EndTabItem()
        end

        if ImGui.BeginTabItem('FAQ') then
            ImGui.BulletText('Stuck nav: /nav stop, /stick off, verify zone mesh.')
            ImGui.BulletText('No casting: verify gems, mana threshold, and condition guards.')
            ImGui.BulletText('INI ignored: verify active file path and /asuite reload.')
            ImGui.BulletText('Condition not firing: add target guards and echo intermediate values.')
            ImGui.BulletText('Low FPS: raise LoopDelayMS and reduce wide SpawnCount checks.')
            ImGui.BulletText('Dead buttons after UI refactor: map each button to explicit config tab/feature action.')
            ImGui.EndTabItem()
        end

        if ImGui.BeginTabItem('Tools Guides') then
            if ImGui.BeginTabBar('##UEA_ReadmeToolsTabs') then
        if ImGui.BeginTabItem('Start Here') then
            ImGui.TextWrapped('This is an add-on guide for the tools integrated into the MAUI Tools tab. Use this when you are new and just want the safest startup flow.')
            ImGui.Spacing()
            ImGui.BulletText('Step 1: open Tools tab in MAUI.')
            ImGui.BulletText('Step 2: click Sync for each external tool at least once after updates.')
            ImGui.BulletText('Step 3: click Run on the tool you want.')
            ImGui.BulletText('Step 4: click Open UI to show that tool window.')
            ImGui.BulletText('Step 5: use Save command inside each tool after config changes.')
            ImGui.Spacing()
            ImGui.TextWrapped('Recommended first-run order:')
            ImGui.BulletText('SmartLoot: set peer order and navigation settings first.')
            ImGui.BulletText('EZInventory: verify peers and open inventory data refresh.')
            ImGui.BulletText('EZBots: verify peers connect on all characters.')
            ImGui.BulletText('Utility windows (Grouper, HunterHud, LEM, LuaConsole, SpawnWatch): start as needed.')
            DrawCodeSnippet('/lua run maui\n-- Tools tab: Sync -> Run -> Open UI')
            ImGui.EndTabItem()
        end

        if ImGui.BeginTabItem('EZInventory') then
            ImGui.TextWrapped('Purpose: cross-character inventory management, assignment workflows, and upgrade checking.')
            ImGui.BulletText('Run: /lua run ezinventory')
            ImGui.BulletText('Open/Toggle UI: /ezinventory_ui')
            ImGui.BulletText('Help: /ezinventory_help')
            ImGui.Spacing()
            ImGui.TextWrapped('Noob workflow:')
            ImGui.BulletText('Open UI and confirm your peers are visible.')
            ImGui.BulletText('Start with launcher/equipped/bags tabs before advanced assignment tools.')
            ImGui.BulletText('Use assignment and autobank only after verifying actor/peer connectivity.')
            ImGui.Spacing()
            ImGui.TextWrapped('Main settings file:')
            DrawCodeSnippet('Config/EZInventory/<server>/<character>.lua')
            ImGui.TextWrapped('Useful commands:')
            DrawCodeSnippet('/ezinventory_stats_mode minimal|selective|full\n/ezinventory_toggle_basic\n/ezinventory_toggle_detailed\n/ezinvbank\n/ezinvassign show\n/ezinvassign execute')
            ImGui.EndTabItem()
        end

        if ImGui.BeginTabItem('SmartLoot') then
            DrawSmartLootGitHubOrderedGuide()
            ImGui.EndTabItem()
        end

        if ImGui.BeginTabItem('EZBots') then
            DrawEZBotsGitHubOrderedGuide()
            ImGui.EndTabItem()
        end

        if ImGui.BeginTabItem('SpawnWatch') then
            ImGui.TextWrapped('Purpose: zone-based spawn query watchlist + active spawn viewer.')
            ImGui.BulletText('Run: /lua run spawnwatch')
            ImGui.BulletText('Open viewer: /showspawns')
            ImGui.BulletText('Open editor: /sm_edit')
            ImGui.BulletText('Lock/Unlock viewer window: /sm_lock')
            ImGui.Spacing()
            ImGui.TextWrapped('Noob workflow:')
            ImGui.BulletText('Open editor and add one spawn query for current zone.')
            ImGui.BulletText('Return to viewer and verify matching mobs appear.')
            ImGui.BulletText('Use lock toggle to keep overlay anchored while moving.')
            ImGui.Spacing()
            ImGui.TextWrapped('Saved file:')
            DrawCodeSnippet('Lua/npc_watchlist_by_zone.json')
            ImGui.EndTabItem()
        end

        if ImGui.BeginTabItem('BuffBot') then
            ImGui.TextWrapped('Purpose: class-driven buff service bot with optional account/friend/guild controls.')
            ImGui.BulletText('Run: /lua run buffbot')
            ImGui.BulletText('Main command: /bb')
            ImGui.BulletText('UI toggle: /bb gui')
            ImGui.Spacing()
            ImGui.TextWrapped('Noob workflow:')
            ImGui.BulletText('Run on a supported class first (example: Shaman/Cleric/Enchanter/Magician).')
            ImGui.BulletText('Open UI and set mana thresholds + service options.')
            ImGui.BulletText('Test with one friend tell/say request before enabling account mode.')
            ImGui.Spacing()
            ImGui.TextWrapped('Settings files:')
            DrawCodeSnippet('Config/BuffBot/Settings/BuffBot_<character>.ini\nConfig/BuffBot/*.ini (friends/guild/accounts as created by tool)')
            ImGui.TextWrapped('Common commands:')
            DrawCodeSnippet('/bb gui\n/bb quit\n/bb buff <friendName>\n/bb balance add|del|get <friendName>\n/bb friend add|del|get <friendName>\n/bb guild add|del|get <guildName>')
            ImGui.EndTabItem()
        end

        if ImGui.BeginTabItem('Grouper') then
            ImGui.TextWrapped('Purpose: group control action pad for follow, camp, movement, visibility, and helper commands.')
            ImGui.BulletText('Run: /lua run grouper')
            ImGui.BulletText('Main command: /grouper')
            ImGui.Spacing()
            ImGui.TextWrapped('Noob workflow:')
            ImGui.BulletText('Start with Pause/Resume, Camp On/Off, and Follow On/Off only.')
            ImGui.BulletText('Avoid Setup button until you understand what defaults it changes.')
            ImGui.BulletText('Use hide behavior after confirming all buttons do expected actions.')
            ImGui.Spacing()
            ImGui.TextWrapped('Saved config:')
            DrawCodeSnippet('Config/Grouper_<character>_<server>.ini')
            ImGui.TextWrapped('Examples:')
            DrawCodeSnippet('/grouper pause\n/grouper resume\n/grouper campon\n/grouper campoff\n/grouper followon\n/grouper followoff\n/grouper invis')
            ImGui.EndTabItem()
        end

        if ImGui.BeginTabItem('HunterHud') then
            ImGui.TextWrapped('Purpose: hunter achievement tracker and spawn visibility helper for current zone.')
            ImGui.BulletText('Run: /lua run hunterhud')
            ImGui.BulletText('Toggle/Help: /hh')
            ImGui.BulletText('Stop: /hh stop')
            ImGui.Spacing()
            ImGui.TextWrapped('Noob workflow:')
            ImGui.BulletText('Run in a zone with hunter objectives.')
            ImGui.BulletText('Right-click title for menu options (minimize/hide/spawned-only).')
            ImGui.BulletText('Double-click a listed spawn to nav to it.')
            ImGui.EndTabItem()
        end

        if ImGui.BeginTabItem('LEM') then
            ImGui.TextWrapped('Purpose: Lua Event Manager for text/condition triggers and automated action scripts.')
            ImGui.BulletText('Run: /lua run lem')
            ImGui.BulletText('Main command: /lem')
            ImGui.BulletText('Alias command: /mlem')
            ImGui.Spacing()
            ImGui.TextWrapped('Noob workflow:')
            ImGui.BulletText('Open UI and leave safemode off only after testing one event.')
            ImGui.BulletText('Create one text event, verify trigger, then enable broadcast if needed.')
            ImGui.BulletText('Use lower frequency values only after stability testing.')
            ImGui.Spacing()
            ImGui.TextWrapped('Saved files:')
            DrawCodeSnippet('Lua/lem/settings.lua\nLua/lem/characters/<character>.lua')
            ImGui.TextWrapped('Common commands:')
            DrawCodeSnippet('/lem help\n/lem show\n/lem hide\n/lem reload\n/lem event <name> on|off\n/lem cond <name> on|off')
            ImGui.EndTabItem()
        end

        if ImGui.BeginTabItem('LuaConsole') then
            ImGui.TextWrapped('Purpose: in-game Lua editor/runner for quick tests and utility scripts.')
            ImGui.BulletText('Run: /lua run luaconsole')
            ImGui.BulletText('Toggle UI: /lc')
            ImGui.Spacing()
            ImGui.TextWrapped('Noob workflow:')
            ImGui.BulletText('Paste a tiny test snippet first.')
            ImGui.BulletText('Run with toolbar play button or Ctrl+Enter.')
            ImGui.BulletText('Use clear buttons to reset script/console while learning.')
            ImGui.Spacing()
            ImGui.TextWrapped('Saved editor state:')
            DrawCodeSnippet('Config/luaconsole_settings.lua')
            ImGui.EndTabItem()
        end

        if ImGui.BeginTabItem('Troubleshooting') then
            ImGui.TextWrapped('Quick checks when a tool fails to start or appears missing:')
            ImGui.BulletText('If Src:Missing in Tools tab, correct Source Root and click Sync.')
            ImGui.BulletText('If Status:EXITED, run the tool and watch MQ red error text for missing dependency/module.')
            ImGui.BulletText('Run tools one at a time first before Run All.')
            ImGui.BulletText('After updates, restart MAUI and the target tool.')
            ImGui.BulletText("If command seems dead, use that tool's help command first (/sl_help, /ezinventory_help, /lem help, /bb).")
            ImGui.Spacing()
            DrawCodeSnippet('/lua stop <tool>\n/lua run <tool>\n/lua stop maui\n/lua run maui')
            ImGui.EndTabItem()
        end
            ImGui.EndTabBar()
        end
            ImGui.EndTabItem()
        end
        ImGui.EndTabBar()
    end
end

local function DrawField(sectionName, key)
    local schemaSection = globals.Schema[sectionName]
    if not schemaSection or not schemaSection.Properties or not schemaSection.Properties[key] then
        return
    end
    if not globals.Config[sectionName] then
        globals.Config[sectionName] = {}
    end
    DrawProperty(sectionName, key, schemaSection.Properties[key])
end

local function EnsureConfigSection(sectionName)
    if not globals.Config[sectionName] then
        globals.Config[sectionName] = {}
    end
    return globals.Config[sectionName]
end

local function IsNullOrEmpty(value)
    if value == nil then return true end
    if type(value) == 'string' then
        local trimmed = value:gsub('^%s+', ''):gsub('%s+$', '')
        return trimmed == '' or trimmed:upper() == 'NULL'
    end
    return false
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

local function GetNumericValue(sectionName, key, defaultValue)
    local section = globals.Config[sectionName]
    if not section then return defaultValue end
    local value = section[key]
    if type(value) == 'number' then return value end
    if type(value) == 'string' then
        local n = tonumber(value)
        if n ~= nil then return n end
    end
    return defaultValue
end

local function IsSectionEnabled(sectionName)
    local schemaSection = globals.Schema[sectionName]
    if not schemaSection or not schemaSection.Controls or not schemaSection.Controls.On then
        return false
    end
    local section = EnsureConfigSection(sectionName)
    return ParseToggleValue(section[sectionName..'On'])
end

local function SetSectionEnabled(sectionName, enabled)
    local schemaSection = globals.Schema[sectionName]
    if not schemaSection or not schemaSection.Controls or not schemaSection.Controls.On then
        return
    end
    local section = EnsureConfigSection(sectionName)
    local onKey = sectionName..'On'
    local onType = schemaSection.Controls.On.Type
    if onType == 'NUMBER' then
        if enabled then
            local current = tonumber(section[onKey]) or 0
            section[onKey] = (current > 0) and current or 1
        else
            section[onKey] = 0
        end
    else
        section[onKey] = enabled
    end
    if schemaSection.Controls.COn and not enabled then
        section[sectionName..'COn'] = false
    end
end

local function ApplySetupPreset(presetName)
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

    local function FindBestLevelBucket(levelNow, templatesRoot)
        local best = nil
        local minBucket = nil
        for entry in lfs.dir(templatesRoot) do
            local lvl = tonumber(tostring(entry):match('^Level(%d+)$'))
            if lvl then
                if not minBucket or lvl < minBucket then minBucket = lvl end
                if lvl <= levelNow and (not best or lvl > best) then
                    best = lvl
                end
            end
        end
        return best or minBucket
    end

    local function FindPresetTemplateFile(levelNow, classShort, presetUpper)
        local templatesRoot = NormalizePath(mq.configDir .. '/UltimateEQAssist/Templates')
        if lfs.attributes(templatesRoot, 'mode') ~= 'directory' then
            return nil
        end
        local bucket = FindBestLevelBucket(levelNow, templatesRoot)
        if not bucket then return nil end

        local prefix = string.format('UltimateEQAssist_L%d_%s_%s', bucket, classShort, presetUpper)
        local candidates = {
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
        return nil
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
        cfg.General.CharInfo = string.format('%s|%d|GOLD', tostring(mq.TLO.Me.Class.Name() or 'Unknown'), tonumber(mq.TLO.Me.Level() or globals.MyLevel) or 0)
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
        local className = tostring(mq.TLO.Me.Class.Name() or globals.MyClass or 'Unknown')
        className = className:gsub('^%l', string.upper)
        local levelNow = tonumber(mq.TLO.Me.Level() or globals.MyLevel) or (globals.MyLevel or 0)
        local currentCharInfo = tostring(cfg.General.CharInfo or '')
        local tier = currentCharInfo:match('^[^|]*|%d+|([^|]+)$') or 'GOLD'
        cfg.General.CharInfo = string.format('%s|%d|%s', className, levelNow, tier)
        cfg.General.Role = cfg.General.Role or 'Assist'
        if tostring(globals.MyClass or ''):lower() ~= 'brd' then
            cfg.General.TwistOn = 0
        end
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

    local switchedToCharINI = EnsureActiveINIForCurrentCharacter()
    local levelNow = tonumber(mq.TLO.Me.Level() or globals.MyLevel) or (globals.MyLevel or 0)
    local classShort = tostring(globals.MyClass or ''):upper()
    local presetUpper = tostring(presetName or 'GROUP'):upper()
    local templatePath, bucket = FindPresetTemplateFile(levelNow, classShort, presetUpper)

    if templatePath then
        globals.Config = LIP.load(templatePath, false) or BuildFallbackCleanConfig()
        NormalizeLoadedTemplateIdentity(globals.Config)
    else
        globals.Config = BuildFallbackCleanConfig()
    end
    ApplyModeDeltas(globals.Config)

    -- Full replace + immediate RAW refresh
    Save()
    globals.INIFileContents = utils.ReadRawINIFile()
    if templatePath then
        local sourceKind = templatePath:find('/KAHybrid/', 1, true) and 'KAHybrid' or (templatePath:find('/Presets/', 1, true) and 'Preset' or 'Class')
        local fromLabel = string.format('L%d %s %s', tonumber(bucket or levelNow) or levelNow, classShort, sourceKind)
        if switchedToCharINI then
            bottomActionMsg = string.format('Preset applied: %s from %s (switched to %s)', presetName, fromLabel, tostring(globals.INIFile))
        else
            bottomActionMsg = string.format('Preset applied: %s from %s', presetName, fromLabel)
        end
    else
        bottomActionMsg = string.format('Preset applied: %s (fallback baseline; no template found)', presetName)
    end
end

local function DrawSetupModuleToggle(label, sectionName, openTabName)
    local enabled = IsSectionEnabled(sectionName)
    local newValue = ImGui.Checkbox('##setup_'..sectionName, enabled)
    if newValue ~= enabled then
        SetSectionEnabled(sectionName, newValue)
    end
    ImGui.SameLine()
    ImGui.Text(label)
    ImGui.SameLine()
    if ImGui.Button('Open##'..sectionName, 64, 0) then
        showAdvancedTabs = true
        pendingConfigTab = openTabName
    end
end

local function DrawSetupTab()
    local modules = {
        {label='Combat (DPS)', section='DPS', tab='Combat'},
        {label='Buffs', section='Buffs', tab='Buffs & Cures'},
        {label='Cures', section='Cures', tab='Buffs & Cures'},
        {label='Heals', section='Heals', tab='Healing & OhShit'},
        {label='Pet', section='Pet', tab='Pet'},
    }

    DrawPanelHeader('Quick Setup')
    ImGui.TextWrapped('Use this page to turn features on and fill only the important fields. Keep Advanced tabs hidden until you need deep tuning.')
    ImGui.Spacing()

    if ImGui.Button('Apply Solo Preset') then
        ApplySetupPreset('Solo')
    end
    ImGui.SameLine()
    if ImGui.Button('Apply Group Preset') then
        ApplySetupPreset('Group')
    end
    ImGui.SameLine()
    if ImGui.Button('Apply Raid Preset') then
        ApplySetupPreset('Raid')
    end
    ImGui.SameLine()
    if ImGui.Button('Save Setup') then
        Save()
        globals.INIFileContents = utils.ReadRawINIFile()
        bottomActionMsg = 'Setup saved to INI'
    end
    ImGui.SameLine()
    showAdvancedTabs = ImGui.Checkbox('Show Advanced Tabs##SetupTop', showAdvancedTabs)

    ImGui.Spacing()
    if ImGui.CollapsingHeader('Step 1 - Enable Modules', ImGuiTreeNodeFlags.DefaultOpen) then
        local enabledCount = 0
        for _, mod in ipairs(modules) do
            if IsSectionEnabled(mod.section) then
                enabledCount = enabledCount + 1
            end
        end
        ImGui.TextColored(0.45, 0.90, 0.98, 1.0, string.format('Enabled modules: %d/%d', enabledCount, #modules))
        for _, mod in ipairs(modules) do
            DrawSetupModuleToggle(mod.label, mod.section, mod.tab)
        end
    end

    if ImGui.CollapsingHeader('Step 2 - Movement Rules', ImGuiTreeNodeFlags.DefaultOpen) then
        DrawField('General', 'ChaseAssist')
        local chaseOn = ParseToggleValue(EnsureConfigSection('General').ChaseAssist)
        if chaseOn then
            DrawField('General', 'ChaseDistance')
            DrawField('General', 'BuffWhileChasing')
        else
            DrawField('General', 'ReturnToCamp')
            if ParseToggleValue(EnsureConfigSection('General').ReturnToCamp) then
                DrawField('General', 'CampRadius')
                DrawField('General', 'ReturnToCampAccuracy')
            end
        end
        DrawField('General', 'CampRadiusExceed')
    end

    if ImGui.CollapsingHeader('Step 3 - Survival & Core', ImGuiTreeNodeFlags.DefaultOpen) then
        DrawField('General', 'MedOn')
        if ParseToggleValue(EnsureConfigSection('General').MedOn) then
            DrawField('General', 'MedStart')
            DrawField('General', 'SitToMed')
        end
        DrawField('General', 'AcceptInvitesOn')
        DrawField('General', 'GroupWatchOn')
        DrawField('General', 'CastRetries')
    end

    if ImGui.CollapsingHeader('Step 4 - Connectivity', ImGuiTreeNodeFlags.DefaultOpen) then
        DrawField('General', 'EQBCOn')
        DrawField('General', 'DanNetOn')
        DrawField('General', 'DanNetDelay')
    end

    if ImGui.CollapsingHeader('Validation', ImGuiTreeNodeFlags.DefaultOpen) then
        local dpsEnabled = IsSectionEnabled('DPS')
        local buffsEnabled = IsSectionEnabled('Buffs')
        local healsEnabled = IsSectionEnabled('Heals')
        local petEnabled = IsSectionEnabled('Pet')

        if dpsEnabled and GetNumericValue('DPS', 'DPSSize', 0) == 0 then
            ImGui.TextColored(1.0, 0.65, 0.2, 1.0, 'DPS is enabled but DPSSize is 0.')
        end
        if buffsEnabled and GetNumericValue('Buffs', 'BuffsSize', 0) == 0 then
            ImGui.TextColored(1.0, 0.65, 0.2, 1.0, 'Buffs are enabled but BuffsSize is 0.')
        end
        if healsEnabled and GetNumericValue('Heals', 'HealsSize', 0) == 0 then
            ImGui.TextColored(1.0, 0.65, 0.2, 1.0, 'Heals are enabled but HealsSize is 0.')
        end
        if petEnabled and IsNullOrEmpty(EnsureConfigSection('Pet').PetSpell) then
            ImGui.TextColored(1.0, 0.65, 0.2, 1.0, 'Pet is enabled but PetSpell is not set.')
        end
        if ParseToggleValue(EnsureConfigSection('General').ChaseAssist) and ParseToggleValue(EnsureConfigSection('General').ReturnToCamp) then
            ImGui.TextColored(1.0, 0.45, 0.25, 1.0, 'Both ChaseAssist and ReturnToCamp are enabled. Usually choose one.')
        end
        if not dpsEnabled and not buffsEnabled and not healsEnabled and not petEnabled then
            ImGui.TextColored(0.85, 0.85, 0.85, 1.0, 'No major modules are enabled yet.')
        end
    end

    ImGui.Spacing()
end

local function DrawGeneralTab()
    if ImGui.CollapsingHeader('Core', ImGuiTreeNodeFlags.DefaultOpen) then
        DrawPanelHeader('Connectivity / Macro Core')
        DrawField('General', 'EQBCOn')
        DrawField('General', 'DanNetOn')
        DrawField('General', 'DanNetDelay')
        DrawField('General', 'CastRetries')
        DrawField('General', 'AcceptInvitesOn')
    end

    if ImGui.CollapsingHeader('Meditation', ImGuiTreeNodeFlags.DefaultOpen) then
        DrawPanelHeader('Mana / Endurance')
        DrawField('General', 'MedOn')
        DrawField('General', 'MedStart')
        DrawField('General', 'SitToMed')
        DrawField('General', 'CheerPeople')
    end

    if ImGui.CollapsingHeader('Misc', ImGuiTreeNodeFlags.DefaultOpen) then
        DrawPanelHeader('Misc Behavior')
        DrawField('General', 'MiscGemLW')
        DrawField('General', 'MiscGemRemem')
        DrawField('General', 'GroupWatchOn')
        DrawField('General', 'BuffWhileChasing')
    end
end

local function DrawMovementCampingTab()
    if ImGui.CollapsingHeader('Camping Rules', ImGuiTreeNodeFlags.DefaultOpen) then
        DrawPanelHeader('Camp Radius / Return')
        DrawField('General', 'CampRadius')
        DrawField('General', 'CampRadiusExceed')
        DrawField('General', 'ReturnToCamp')
        DrawField('General', 'ReturnToCampAccuracy')
        DrawField('General', 'CampfireOn')
    end

    if ImGui.CollapsingHeader('Chasing', ImGuiTreeNodeFlags.DefaultOpen) then
        DrawPanelHeader('Follow Main Assist')
        DrawField('General', 'ChaseAssist')
        DrawField('General', 'ChaseDistance')
        DrawField('General', 'SwitchWithMA')
    end

    if ImGui.CollapsingHeader('Twist / Movement Extras', ImGuiTreeNodeFlags.DefaultOpen) then
        DrawPanelHeader('Twist')
        DrawField('General', 'TwistOn')
        DrawField('General', 'TwistMed')
        DrawField('General', 'TwistWhat')
        DrawField('General', 'GroupEscapeOn')
        DrawField('General', 'TravelOnHorse')
    end
end

local function DrawSectionTab(sectionName)
    if globals.Schema[sectionName] then
        selectedListItem = {nil, 0}
        selectedUpgrade = nil
        DrawSection(sectionName, globals.Schema[sectionName])
    else
        ImGui.TextColored(1, 0.2, 0.2, 1, 'Missing schema section: '..tostring(sectionName))
    end
end

local function DrawUtilityTab()
    if ImGui.CollapsingHeader('Loot / Rez / Group', ImGuiTreeNodeFlags.DefaultOpen) then
        DrawPanelHeader('Utility')
        DrawField('General', 'LootOn')
        DrawField('General', 'RezAcceptOn')
        DrawField('General', 'AcceptInvitesOn')
        DrawField('General', 'GroupWatchOn')
    end
    if ImGui.CollapsingHeader('Other', ImGuiTreeNodeFlags.DefaultOpen) then
        DrawPanelHeader('Additional')
        DrawField('General', 'DPSMeter')
        DrawField('General', 'CheerPeople')
        DrawField('General', 'DanNetOn')
        DrawField('General', 'DanNetDelay')
    end
end

local function GetIntegrationTools()
    return {
        {
            name = 'EZInventory',
            sourceFolder = 'EZInventory/EZInventory',
            targetFolder = 'EZInventory',
            runCmd = '/lua run ezinventory',
            stopCmd = '/lua stop ezinventory',
            openCmd = '/ezinventory_ui',
            script = 'ezinventory',
        },
        {
            name = 'SmartLoot',
            sourceFolder = 'smartloot-main/smartloot-main',
            targetFolder = 'smartloot',
            runCmd = '/lua run smartloot',
            stopCmd = '/lua stop smartloot',
            openCmd = '/sl_help',
            script = 'smartloot',
        },
        {
            name = 'EZBots',
            sourceFolder = 'EZInventory/EZBots-main',
            targetFolder = 'ezbots',
            runCmd = '/lua run ezbots',
            stopCmd = '/lua stop ezbots',
            -- EZBots does not expose a dedicated UI toggle bind by default.
            openCmd = '/lua run ezbots',
            script = 'ezbots',
        },
        {
            name = 'SpawnWatch',
            targetFolder = 'spawnwatch',
            runCmd = '/lua run spawnwatch',
            stopCmd = '/lua stop spawnwatch',
            openCmd = '/showspawns',
            script = 'spawnwatch',
            localOnly = true,
        },
        {
            name = 'BuffBot',
            sourceFolder = 'EZInventory/Buffbot',
            targetFolder = 'buffbot',
            runCmd = '/lua run buffbot',
            stopCmd = '/lua stop buffbot',
            openCmd = '/bb gui',
            script = 'buffbot',
        },
        {
            name = 'Grouper',
            sourceFolder = 'EZInventory/grouper',
            targetFolder = 'grouper',
            runCmd = '/lua run grouper',
            stopCmd = '/lua stop grouper',
            openCmd = '/grouper',
            script = 'grouper',
        },
        {
            name = 'HunterHud',
            sourceFolder = 'EZInventory/Hunterhud',
            targetFolder = 'hunterhud',
            runCmd = '/lua run hunterhud',
            stopCmd = '/lua stop hunterhud',
            openCmd = '/hh',
            script = 'hunterhud',
        },
        {
            name = 'LEM',
            sourceFolder = 'EZInventory/lem',
            targetFolder = 'lem',
            runCmd = '/lua run lem',
            stopCmd = '/lua stop lem',
            openCmd = '/lem',
            script = 'lem',
        },
        {
            name = 'LuaConsole',
            sourceFolder = 'EZInventory/luaconsole',
            targetFolder = 'luaconsole',
            runCmd = '/lua run luaconsole',
            stopCmd = '/lua stop luaconsole',
            openCmd = '/lc',
            script = 'luaconsole',
        },
    }
end

local function DrawIntegrationsTab()
    local tools = GetIntegrationTools()

    DrawPanelHeader('External Tool Integrations')
    ImGui.TextWrapped('Sync external lua tools into your MQ lua folder, then run/stop/open them from this window.')
    ImGui.TextColored(0.70, 0.86, 0.98, 1.0, 'Theme Note: this Tools panel uses your active MAUI theme; external tool windows keep their own theme unless that tool exposes theme commands.')
    ImGui.PushItemWidth(520)
    integrationSourceRoot, _ = ImGui.InputText('Source Root##Integrations', integrationSourceRoot)
    ImGui.PopItemWidth()
    integrationAutoSync = ImGui.Checkbox('Auto Sync Before Run##Integrations', integrationAutoSync)

    if ImGui.Button('Sync All Tools', 130, 0) then
        local totalCopied = 0
        local allOk = true
        for _, tool in ipairs(tools) do
            if not tool.localOnly then
                local src = NormalizePath(integrationSourceRoot) .. '/' .. (tool.sourceFolder or tool.folder or '')
                local dst = NormalizePath(mq.luaDir) .. '/' .. (tool.targetFolder or tool.folder or '')
                local ok, copied = SyncDirectory(src, dst)
                if ok then
                    totalCopied = totalCopied + copied
                else
                    allOk = false
                end
            end
        end
        if allOk then
            bottomActionMsg = string.format('Integrations: synced %d files', totalCopied)
        else
            bottomActionMsg = 'Integrations: sync failed for one or more tools'
        end
    end
    ImGui.SameLine()
    if ImGui.Button('Run All Tools', 120, 0) then
        for _, tool in ipairs(tools) do
            if integrationAutoSync and not tool.localOnly then
                local src = NormalizePath(integrationSourceRoot) .. '/' .. (tool.sourceFolder or tool.folder or '')
                local dst = NormalizePath(mq.luaDir) .. '/' .. (tool.targetFolder or tool.folder or '')
                SyncDirectory(src, dst)
            end
            mq.cmd(tool.runCmd)
        end
        bottomActionMsg = string.format('Integrations: launched %d tools', #tools)
    end

    ImGui.Separator()
    for _, tool in ipairs(tools) do
        local src = NormalizePath(integrationSourceRoot) .. '/' .. (tool.sourceFolder or tool.folder or '')
        local dst = NormalizePath(mq.luaDir) .. '/' .. (tool.targetFolder or tool.folder or '')
        local srcOk = tool.localOnly or (lfs.attributes(src, 'mode') == 'directory')
        local dstOk = (lfs.attributes(dst, 'mode') == 'directory')
        local status = GetLuaScriptStatus(tool.script)
        local srcLabel = tool.localOnly and 'N/A (Local)' or (srcOk and 'OK' or 'Missing')

        ImGui.TextColored(0.45, 0.90, 0.98, 1.0, tool.name)
        ImGui.SameLine()
        ImGui.Text(string.format('Src:%s  Dst:%s  Status:%s', srcLabel, dstOk and 'OK' or 'Missing', status))

        if tool.localOnly then
            ImGui.BeginDisabled()
            ImGui.Button('Sync##'..tool.name, 70, 0)
            ImGui.EndDisabled()
        else
            if ImGui.Button('Sync##'..tool.name, 70, 0) then
                local ok, copied = SyncDirectory(src, dst)
                bottomActionMsg = ok and string.format('%s: synced %d files', tool.name, copied) or (tool.name..': sync failed')
            end
        end
        ImGui.SameLine()
        if ImGui.Button('Run##'..tool.name, 60, 0) then
            if integrationAutoSync and not tool.localOnly then
                SyncDirectory(src, dst)
            end
            RunToolCommand('runtool', tool.runCmd)
            bottomActionMsg = tool.name..': launch command sent'
        end
        ImGui.SameLine()
        if ImGui.Button('Stop##'..tool.name, 60, 0) then
            RunToolCommand('stoptool', tool.stopCmd)
            bottomActionMsg = tool.name..': stop command sent'
        end
        ImGui.SameLine()
        if ImGui.Button('Open UI##'..tool.name, 80, 0) then
            mq.cmd(tool.openCmd)
            bottomActionMsg = tool.name..': open/toggle command sent'
        end
        ImGui.Separator()
    end
end

local function DrawToolsLayout()
    DrawUltimateTopBar()
    ImGui.BeginChild('##UEA_ToolsBody', -1, -72, ImGuiChildFlags.Border)
    DrawIntegrationsTab()
    ImGui.Dummy(1, 1)
    ImGui.EndChild()
    DrawUltimateBottomBar()
end

local function SafeDrawSection(label, fn)
    local ok, err = pcall(fn)
    if not ok then
        print(string.format('[MAUI] UI section error [%s]: %s', tostring(label), tostring(err)))
        bottomActionMsg = string.format('UI error in %s (see chat)', tostring(label))
        ImGui.TextColored(1.0, 0.35, 0.35, 1.0, string.format('UI section failed: %s', tostring(label)))
    end
end

local function DrawUltimateLayout()
    if ImGui.BeginTabBar('##UEA_Tabs') then
        local mainFlags = (pendingMainTab == 'UI') and ImGuiTabItemFlags.SetSelected or ImGuiTabItemFlags.None
        if ImGui.BeginTabItem('UI', nil, mainFlags) then
            ui_main_tab = 'UI'
            SafeDrawSection('TopBar', DrawUltimateTopBar)
            ImGui.BeginChild('##UEA_UIBody', -1, -72, ImGuiChildFlags.Border)
            if pendingConfigTab and pendingConfigTab ~= 'Setup' then
                showAdvancedTabs = true
            end
            if ImGui.BeginTabBar('##UEA_ConfigTabs') then
                local flags = (pendingConfigTab == 'Setup') and ImGuiTabItemFlags.SetSelected or ImGuiTabItemFlags.None
                if ImGui.BeginTabItem('Setup', nil, flags) then
                    SafeDrawSection('Setup', DrawSetupTab)
                    ImGui.EndTabItem()
                end
                if showAdvancedTabs then
                    flags = (pendingConfigTab == 'General') and ImGuiTabItemFlags.SetSelected or ImGuiTabItemFlags.None
                    if ImGui.BeginTabItem('General', nil, flags) then
                        SafeDrawSection('General', DrawGeneralTab)
                        ImGui.EndTabItem()
                    end
                    flags = (pendingConfigTab == 'Combat') and ImGuiTabItemFlags.SetSelected or ImGuiTabItemFlags.None
                    if ImGui.BeginTabItem('Combat', nil, flags) then
                        if ImGui.BeginTabBar('##UEA_CombatSubtabs') then
                            if ImGui.BeginTabItem('Aggro') then SafeDrawSection('Combat/Aggro', function() DrawSectionTab('Aggro') end); ImGui.EndTabItem() end
                            if ImGui.BeginTabItem('DPS') then SafeDrawSection('Combat/DPS', function() DrawSectionTab('DPS') end); ImGui.EndTabItem() end
                            if ImGui.BeginTabItem('Burn') then SafeDrawSection('Combat/Burn', function() DrawSectionTab('Burn') end); ImGui.EndTabItem() end
                            if ImGui.BeginTabItem('GoM') then SafeDrawSection('Combat/GoM', function() DrawSectionTab('GoM') end); ImGui.EndTabItem() end
                            ImGui.EndTabBar()
                        end
                        ImGui.EndTabItem()
                    end
                    flags = (pendingConfigTab == 'Buffs & Cures') and ImGuiTabItemFlags.SetSelected or ImGuiTabItemFlags.None
                    if ImGui.BeginTabItem('Buffs & Cures', nil, flags) then
                        if ImGui.BeginTabBar('##UEA_BuffsSubtabs') then
                            if ImGui.BeginTabItem('Buffs') then SafeDrawSection('Buffs/Buffs', function() DrawSectionTab('Buffs') end); ImGui.EndTabItem() end
                            if ImGui.BeginTabItem('Cures') then SafeDrawSection('Buffs/Cures', function() DrawSectionTab('Cures') end); ImGui.EndTabItem() end
                            if ImGui.BeginTabItem('AE') then SafeDrawSection('Buffs/AE', function() DrawSectionTab('AE') end); ImGui.EndTabItem() end
                            ImGui.EndTabBar()
                        end
                        ImGui.EndTabItem()
                    end
                    flags = (pendingConfigTab == 'Healing & OhShit') and ImGuiTabItemFlags.SetSelected or ImGuiTabItemFlags.None
                    if ImGui.BeginTabItem('Healing & OhShit', nil, flags) then
                        if ImGui.BeginTabBar('##UEA_HealSubtabs') then
                            if ImGui.BeginTabItem('Heals') then SafeDrawSection('Heals/Heals', function() DrawSectionTab('Heals') end); ImGui.EndTabItem() end
                            if ImGui.BeginTabItem('OhShit') then SafeDrawSection('Heals/OhShit', function() DrawSectionTab('OhShit') end); ImGui.EndTabItem() end
                            if ImGui.BeginTabItem('Mez') then SafeDrawSection('Heals/Mez', function() DrawSectionTab('Mez') end); ImGui.EndTabItem() end
                            ImGui.EndTabBar()
                        end
                        ImGui.EndTabItem()
                    end
                    flags = (pendingConfigTab == 'Pet') and ImGuiTabItemFlags.SetSelected or ImGuiTabItemFlags.None
                    if ImGui.BeginTabItem('Pet', nil, flags) then
                        SafeDrawSection('Pet', function() DrawSectionTab('Pet') end)
                        ImGui.EndTabItem()
                    end
                    flags = (pendingConfigTab == 'Movement & Camping') and ImGuiTabItemFlags.SetSelected or ImGuiTabItemFlags.None
                    if ImGui.BeginTabItem('Movement & Camping', nil, flags) then
                        SafeDrawSection('Movement & Camping', DrawMovementCampingTab)
                        ImGui.EndTabItem()
                    end
                    flags = (pendingConfigTab == 'Utility') and ImGuiTabItemFlags.SetSelected or ImGuiTabItemFlags.None
                    if ImGui.BeginTabItem('Utility', nil, flags) then
                        SafeDrawSection('Utility', DrawUtilityTab)
                        ImGui.EndTabItem()
                    end
                    flags = (pendingConfigTab == 'SpellSet / Gems') and ImGuiTabItemFlags.SetSelected or ImGuiTabItemFlags.None
                    if ImGui.BeginTabItem('SpellSet / Gems', nil, flags) then
                        SafeDrawSection('SpellSet / Gems', function() DrawSectionTab('SpellSet') end)
                        ImGui.EndTabItem()
                    end
                end
                ImGui.EndTabBar()
                pendingConfigTab = nil
            end
            ImGui.Dummy(1, 1)
            ImGui.EndChild()
            SafeDrawSection('BottomBar', DrawUltimateBottomBar)
            ImGui.EndTabItem()
        end
        mainFlags = (pendingMainTab == 'RAW') and ImGuiTabItemFlags.SetSelected or ImGuiTabItemFlags.None
        if ImGui.BeginTabItem('RAW', nil, mainFlags) then
            ui_main_tab = 'RAW'
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
                        ReloadINIFromDisk()
                    end
                end
            end
            ImGui.SameLine()
            if ImGui.Button('Reload Raw') then
                globals.INIFileContents = utils.ReadRawINIFile()
            end
            ImGui.EndTabItem()
        end
        mainFlags = (pendingMainTab == 'Tools') and ImGuiTabItemFlags.SetSelected or ImGuiTabItemFlags.None
        if ImGui.BeginTabItem('Tools', nil, mainFlags) then
            ui_main_tab = 'Tools'
            SafeDrawSection('Tools', DrawToolsLayout)
            ImGui.EndTabItem()
        end
        mainFlags = (pendingMainTab == 'Readme') and ImGuiTabItemFlags.SetSelected or ImGuiTabItemFlags.None
        if ImGui.BeginTabItem('Readme', nil, mainFlags) then
            ui_main_tab = 'Readme'
            SafeDrawSection('TopBar', DrawUltimateTopBar)
            ImGui.BeginChild('##UEA_ReadmeBody', -1, -72, ImGuiChildFlags.Border)
            SafeDrawSection('README', DrawReadmeTab)
            ImGui.Dummy(1, 1)
            ImGui.EndChild()
            SafeDrawSection('BottomBar', DrawUltimateBottomBar)
            ImGui.EndTabItem()
        end
        pendingMainTab = nil
        ImGui.EndTabBar()
    end
end

local function SetSchemaVars(selectedSchema)
    local ok, schemaMod = pcall(require, 'schemas.'..selectedSchema)
    if not ok then print('Error loading schema for: '..selectedSchema) return false end
    ok, addonMod = pcall(require, 'addons.'..selectedSchema)
    if not ok then print('Error loading schema for: '..selectedSchema) return false end

    customSections = addonMod
    globals.Schema = schemaMod
    globals.CurrentSchema = selectedSchema
    globals.INIFile = utils.FindINIFile()
    selectedSection = 'General'
    if globals.INIFile and utils.FileExists(mq.configDir..'/'..globals.INIFile) then
        globals.Config = LIP.load(mq.configDir..'/'..globals.INIFile)
        globals.INIFileContents = utils.ReadRawINIFile()
        globals.INILoadError = ''
        MarkConfigClean()
    else
        globals.INIFile = ''
        globals.Config = {}
        MarkConfigClean()
    end
    return true
end

local function DrawComboBox(label, resultvar, options)
    if ImGui.BeginCombo(label, resultvar) then
        for i,j in pairs(options) do
            if ImGui.Selectable(j, j == resultvar) then
                resultvar = j
            end
        end
        ImGui.EndCombo()
    end
    return resultvar
end

local radioValue = 1
local function DrawWindowHeaderSettings()
    if #globals.Schemas > 1 then
        for idx, schema_kind in ipairs(globals.Schemas) do
            radioValue,_ = ImGui.RadioButton(schema_kind, radioValue, idx)
            ImGui.SameLine()
        end
        if globals.CurrentSchema ~= globals.Schemas[radioValue] then
            if not SetSchemaVars(globals.Schemas[radioValue]) then
                radioValue = 1
            end
        end
        ImGui.NewLine()
        ImGui.Separator()
    end

    ImGui.Text('INI File: ')
    ImGui.SameLine()
    ImGui.SetCursorPosX(120)
    ImGui.PushItemWidth(350)
    globals.INIFile,_ = ImGui.InputText('##INIInput', globals.INIFile)
    ImGui.SameLine()
    if ImGui.Button('Choose...') then
        filedialog.set_file_selector_open(true)
    end
    ImGui.SameLine()
    if ImGui.Button('Save INI') then
        Save()
        globals.INIFileContents = utils.ReadRawINIFile()
    end
    ImGui.SameLine()
    if ImGui.Button('Reload INI') then
        if globals.INIFile:sub(-string.len('.ini')) ~= '.ini' then
            globals.INIFile = globals.INIFile .. '.ini'
        end
        if utils.FileExists(mq.configDir..'/'..globals.INIFile) then
            globals.Config = LIP.load(mq.configDir..'/'..globals.INIFile)
            globals.INILoadError = ''
            MarkConfigClean()
        else
            globals.INILoadError = ('INI File %s/%s does not exist!'):format(mq.configDir, globals.INIFile)
        end
    end

    if filedialog.is_file_selector_open() then
        filedialog.draw_file_selector(mq.configDir, '.ini')
    end
    if not filedialog.is_file_selector_open() and filedialog.get_filename() ~= '' then
        globals.INIFile = filedialog.get_filename()
        globals.Config = LIP.load(mq.configDir..'/'..globals.INIFile)
        globals.INILoadError = ''
        MarkConfigClean()
        filedialog:reset_filename()
    end

    if globals.INILoadError ~= '' then
        ImGui.TextColored(1,0,0,1,globals.INILoadError)
    end

    local match_found = false
    for _,startcommand in ipairs(globals.Schema['StartCommands']) do
        if startcommand == globals.MAUI_Config[maui_ini_key]['StartCommand'] then
            selected_start_command = startcommand
            match_found = true
            break
        end
    end
    if not match_found then
        if globals.MAUI_Config[maui_ini_key]['StartCommand'] then
            selected_start_command = 'custom'
        else
            selected_start_command = globals.Schema['StartCommands'][1]
        end
    end

    ImGui.Separator()
    ImGui.Text('Start Command: ')
    ImGui.SameLine()
    ImGui.SetCursorPosX(120)
    ImGui.PushItemWidth(190)
    selected_start_command = DrawComboBox('##StartCommands', selected_start_command, globals.Schema['StartCommands'])
    ImGui.SameLine()
    ImGui.PushItemWidth(300)
    if selected_start_command == 'custom' then
        globals.MAUI_Config[maui_ini_key]['StartCommand'],_ = ImGui.InputText('##StartCommand', globals.MAUI_Config[maui_ini_key]['StartCommand'])
    else
        globals.MAUI_Config[maui_ini_key]['StartCommand'],_ = ImGui.InputText('##StartCommand', selected_start_command)
    end
    --ImGui.SameLine()
    ImGui.Text('Status: ')
    ImGui.SameLine()
    ImGui.SetCursorPosX(120)
    if not mq.TLO.Macro() or mq.TLO.Macro.Name() ~= 'muleassist.mac' then
        ImGui.TextColored(1, 0, 0, 1, 'STOPPED')
        ImGui.SameLine()
        if ImGui.Button('Start Macro') then
            mq.cmd(globals.MAUI_Config[maui_ini_key]['StartCommand'])
            SaveMAUIConfig()
        end
    elseif mq.TLO.Macro.Name() == 'muleassist.mac' then
        if mq.TLO.Macro.Paused() then
            ImGui.TextColored(1, 1, 0, 1, 'PAUSED')
            ImGui.SameLine()
            if ImGui.Button('End') then
                mq.cmd('/end')
            end
            ImGui.SameLine()
            if ImGui.Button('Resume') then
                mq.cmd('/mqp off')
            end
        else
            ImGui.TextColored(0, 1, 0, 1, 'RUNNING')
            ImGui.SameLine()
            if ImGui.Button('End') then
                mq.cmd('/end')
            end
            ImGui.SameLine()
            if ImGui.Button('Pause') then
                mq.cmd('/mqp on')
            end
        end
        ImGui.SameLine()
        ImGui.Text(string.format('Role: %s', mq.TLO.Macro.Variable('Role')()))
    end
    if globals.Config.error then
        ImGui.SameLine()
        ImGui.TextColored(1,0,0,1,globals.Config.error)
    end
    ImGui.Separator()
end

local function push_styles()
    -- GMConsole-like spacing/rounding behavior
    ImGui.PushStyleVar(ImGuiStyleVar.WindowRounding, 0)
    ImGui.PushStyleVar(ImGuiStyleVar.FrameRounding, 6)
    ImGui.PushStyleVar(ImGuiStyleVar.ChildRounding, 0)
    ImGui.PushStyleVar(ImGuiStyleVar.PopupRounding, 8)
    ImGui.PushStyleVar(ImGuiStyleVar.GrabRounding, 6)
    ImGui.PushStyleVar(ImGuiStyleVar.TabRounding, 0)
    ImGui.PushStyleVar(ImGuiStyleVar.WindowBorderSize, 1)
    ImGui.PushStyleVar(ImGuiStyleVar.FrameBorderSize, 1)
    ImGui.PushStyleVar(ImGuiStyleVar.ChildBorderSize, 1)
    ImGui.PushStyleVar(ImGuiStyleVar.WindowPadding, 6, 6)
    ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, 4, 2)
    ImGui.PushStyleVar(ImGuiStyleVar.ItemSpacing, 8, 8)

    local themeKey = NormalizeThemeKey(themeOrder[currentThemeIndex] or 'template')
    activeThemeKey = themeKey
    local theme = uiThemes[themeKey] or uiThemes['template']

    ImGui.PushStyleColor(ImGuiCol.WindowBg, theme.windowBg[1], theme.windowBg[2], theme.windowBg[3], theme.windowBg[4])
    ImGui.PushStyleColor(ImGuiCol.ChildBg, 0.02, 0.03, 0.08, 1.00)
    ImGui.PushStyleColor(ImGuiCol.TitleBg, theme.titleBg[1], theme.titleBg[2], theme.titleBg[3], theme.titleBg[4])
    ImGui.PushStyleColor(ImGuiCol.TitleBgActive, theme.titleBgActive[1], theme.titleBgActive[2], theme.titleBgActive[3], theme.titleBgActive[4])
    ImGui.PushStyleColor(ImGuiCol.Button, theme.button[1], theme.button[2], theme.button[3], theme.button[4])
    ImGui.PushStyleColor(ImGuiCol.ButtonHovered, theme.buttonHovered[1], theme.buttonHovered[2], theme.buttonHovered[3], theme.buttonHovered[4])
    ImGui.PushStyleColor(ImGuiCol.ButtonActive, theme.buttonActive[1], theme.buttonActive[2], theme.buttonActive[3], theme.buttonActive[4])
    ImGui.PushStyleColor(ImGuiCol.FrameBg, theme.frameBg[1], theme.frameBg[2], theme.frameBg[3], theme.frameBg[4])
    ImGui.PushStyleColor(ImGuiCol.FrameBgHovered, theme.frameBgHovered[1], theme.frameBgHovered[2], theme.frameBgHovered[3], theme.frameBgHovered[4])
    ImGui.PushStyleColor(ImGuiCol.FrameBgActive, theme.frameBgHovered[1], theme.frameBgHovered[2], theme.frameBgHovered[3], 1.00)
    ImGui.PushStyleColor(ImGuiCol.Header, theme.header[1], theme.header[2], theme.header[3], theme.header[4])
    ImGui.PushStyleColor(ImGuiCol.HeaderHovered, theme.buttonHovered[1], theme.buttonHovered[2], theme.buttonHovered[3], 1.00)
    ImGui.PushStyleColor(ImGuiCol.HeaderActive, theme.buttonActive[1], theme.buttonActive[2], theme.buttonActive[3], 1.00)
    ImGui.PushStyleColor(ImGuiCol.Text, theme.text[1], theme.text[2], theme.text[3], theme.text[4])
    ImGui.PushStyleColor(ImGuiCol.Border, theme.border[1], theme.border[2], theme.border[3], theme.border[4])
    ImGui.PushStyleColor(ImGuiCol.Separator, theme.separator[1], theme.separator[2], theme.separator[3], theme.separator[4])
    ImGui.PushStyleColor(ImGuiCol.TextDisabled, 0.72, 0.72, 0.72, 1.00)
    ImGui.PushStyleColor(ImGuiCol.CheckMark, 0.96, 0.86, 0.30, 1.00)
    ImGui.PushStyleColor(ImGuiCol.PopupBg, 0.02, 0.03, 0.08, 0.98)
    ImGui.PushStyleColor(ImGuiCol.Tab, theme.frameBg[1], theme.frameBg[2], theme.frameBg[3], 1.00)
    ImGui.PushStyleColor(ImGuiCol.TabHovered, theme.frameBgHovered[1], theme.frameBgHovered[2], theme.frameBgHovered[3], 1.00)
    ImGui.PushStyleColor(ImGuiCol.TabActive, theme.header[1], theme.header[2], theme.header[3], 1.00)
end

local function pop_styles()
    ImGui.PopStyleColor(22)
    ImGui.PopStyleVar(12)
end

local MAUI = function()
    if not open then return end
    push_styles()
    open, shouldDrawUI = ImGui.Begin('UltimateEQAssist###MuleAssist', open, ImGuiWindowFlags.NoCollapse)
    if shouldDrawUI then
        -- these appear to be the numbers for the window on first use... probably shouldn't rely on them.
        if initialRun then
            if ImGui.GetWindowHeight() == 38 and ImGui.GetWindowWidth() == 32 then
                ImGui.SetWindowSize(727,487)
            elseif ImGui.GetWindowHeight() == 500 and ImGui.GetWindowWidth() == 500 then
                ImGui.SetWindowSize(727,487)
            end
            initialRun = false
        end
        DrawUltimateLayout()
    end
    ImGui.End()
    pop_styles()
end

local function CheckGameState()
    if mq.TLO.MacroQuest.GameState() ~= 'INGAME' then
        print('\arNot in game, stopping MAUI.\ax')
        open = false
        shouldDrawUI = false
        mq.imgui.destroy('MuleAssist')
        mq.exit()
    end
end

local function ShowHelp()
    print('\a-t[\ax\ayMAUI\ax\a-t]\ax Usage: /maui [show|hide|stop]')
end

local function BindMaui(args)
    if not args then
        ShowHelp()
    end
    local arglist = {args}
    if #arglist > 1 then
        ShowHelp()
    elseif arglist[1] == 'show' then
        open = true
    elseif arglist[1] == 'hide' then
        open = false
    elseif arglist[1] == 'stop' then
        open = false
        terminate = true
    end
end

local function NewSpellMemmed(line, spell)
    print(string.format('\a-t[\ax\ayMAUI\ax\a-t]\ax New spell memorized, updating spell list. \a-t(\ax\ay%s\ax\a-t)\ax', spell))
    -- Build spell tree for picking spells
    local spellNum = mq.TLO.Me.Book(spell)
    local spell = mq.TLO.Me.Book(spellNum)
    if spell() then
        AddSpellToMap(spell)
    end

    SortSpellMap()
end

-- Load INI into table as well as raw content
globals.INIFile = (globals.MAUI_Config[maui_ini_key] and globals.MAUI_Config[maui_ini_key]['INIFile']) or utils.FindINIFile()
if (not globals.INIFile or globals.INIFile == '' or not utils.FileExists(mq.configDir..'/'..globals.INIFile)) then
    local discovered = utils.FindINIFile()
    if discovered and discovered ~= '' and utils.FileExists(mq.configDir..'/'..discovered) then
        globals.INIFile = discovered
    else
        local fallback = FindExistingMAProfile()
        if fallback then
            globals.INIFile = fallback
        end
    end
end
if globals.INIFile and globals.INIFile ~= '' and utils.FileExists(mq.configDir..'/'..globals.INIFile) then
    globals.Config = LIP.load(mq.configDir..'/'..globals.INIFile)
    globals.INIFileContents = utils.ReadRawINIFile()
    globals.INILoadError = ''
    MarkConfigClean()
else
    globals.INIFile = globals.Schema['INI_PATTERNS']['level']:format(globals.MyServer, globals.MyName, globals.MyLevel)
    globals.Config = {}
    MarkConfigClean()
end

mq.bind('/maui', BindMaui)

mq.event('NewSpellMemmed', '#*#You have finished scribing #1#.', NewSpellMemmed)

mq.imgui.init('MuleAssist', MAUI)

local init_done = false
while not terminate do
    CheckGameState()
    mq.doevents()
    if not init_done then
        InitSpellTree()
        InitAATree()
        InitDiscTree()
        init_done = true
    end
    if not memspell and #memQueue > 0 then
        local nextMem = table.remove(memQueue, 1)
        memspell = nextMem.spell
        memgem = nextMem.gem
    end
    if memspell then
        local rankname = mq.TLO.Spell(memspell).RankName()
        if rankname then
            mq.cmdf('/memspell %s "%s"', memgem, rankname)
            mq.delay('3s', function() return mq.TLO.Me.Gem(memgem)() and mq.TLO.Me.Gem(memgem).Name() == rankname end)
            mq.TLO.Window('SpellBookWnd').DoClose()
        end
        memspell = nil
        memgem = 0
    end
    tloCache:clean()
    mq.delay(20)
end
