local mq = require('mq')
local ImGui = require('ImGui') -- UPDATED: avoid leaking ImGui as an implicit global
local Icons = require('mq/Icons')
print('[MAUI] Loaded patched build 2026-05-04')
--[[
=======================================================================
  MAUI init.lua - FIXED BUILD (reviewed 2026-04-25)
  Applied fixes:
    FIX 1  - NewSpellMemmed: variable shadowing + wrong Book() argument types
    FIX 2  - InitAATree: missing nil guard on aa object before aa.Spell()
    FIX 3  - InitDiscTree: broken repeat/until termination (== nil is unreliable on TLO userdata)
    FIX 4  - DrawSelectedListItem: spell.RankName() called without existence guard on spell
    FIX 5  - SpellSorter: inverted/redundant comparator logic
    FIX 6  - LeftPaneWindow: pairs(customSections) crashes when customSections is nil
    FIX 7  - RightPaneWindow: customSections[selectedSection] crashes when customSections is nil
    FIX 8  - Main loop memspell: mq.delay(10) too short + missing mq.doevents() in wait loop
    FIX 9  - DrawSpells: mq.TLO.Me.Gem(i).Name() called without nil guard on empty slot
    FIX 10 - Validation: bare `general` local variable used outside its scope (ReturnToCamp fix button)
    FIX 11 - Validation: bare `general` local used for MedOn check outside its scope
    FIX 12 - BindMaui: {args} always produces length-1 table; #arglist > 1 could never be true
    FIX 13 - AddAAToMap: aa.Spell.Name() uses unevaluated TLO intermediate + no type guard
    FIX 15 - CheckGameState: nil GameState during zone transitions would prematurely exit script
    FIX 16 - DrawSpellPicker: INI values that are not string/number left valueParts nil → table.concat error
    FIX 17 - InitSpellTree/InitAATree/InitDiscTree: periodic mq.delay(0) to reduce long-startup hitching
=======================================================================
]]--

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
local miniSetupOpen = false
local miniValidationWarnings = {}
local miniValidationChecked = false
local leftPanelDefaultWidth = 150
local leftPanelWidth = 150
local ui_main_tab = 'UI'
local hide_ini_path = false

--- Floating Ultimate EQ logo (`lua/maui/ultimate-eq-photo.png`): toggles main MAUI window (EZInventory-style).
local MauiFloat = {
    showToggle = true,
    logoTex = nil,
    logoFailed = false,
    relPath = 'maui/ultimate-eq-photo.png',
    --- Logo PNG includes small “Ultimate EQ” text; keep max dimension ≥ ~80 for readability.
    floatSize = 88,
    miniSize = 56,
}

local selectedListItem = {nil, 0} -- {key, index}
local selectedUpgrade = nil
local selectedSection = 'General' -- Left hand menu selected item
local pendingConfigTab = nil
local pendingMainTab = nil
local bottomActionMsg = ''
local showAdvancedTabs = true
--- Redesigned nav: shared state (table lives in a global to reduce main-chunk local count; Lua 5.1 limit 200).
MauiRuntime = {
    nav = { id = 'setup', combatSub = 'Aggro', buffsSub = 'Buffs', healsSub = 'Heals' },
    quickProfile = 'Group',
    useGemRack = false,
}
--- Single visual system for Ultimate layout (widgets read this instead of one-off greens/reds).
UltimateAssistPalette = {
    textTitle = {0.82, 0.76, 1.00, 1.00},
    textMuted = {0.62, 0.58, 0.78, 1.00},
    textOk = {0.52, 0.82, 0.72, 1.00},
    textWarn = {0.94, 0.70, 0.42, 1.00},
    textDim = {0.52, 0.46, 0.62, 1.00},
    accentBorder = {0.72, 0.42, 0.92, 0.88},
    modeUnsel = {0.12, 0.09, 0.18, 1.00},
    modeUnselHov = {0.18, 0.13, 0.26, 1.00},
    modeUnselBorder = {0.42, 0.26, 0.58, 0.85},
    modeSel = {0.32, 0.14, 0.52, 1.00},
    modeSelHov = {0.40, 0.18, 0.64, 1.00},
    modeSelBorder = {0.76, 0.48, 0.94, 0.95},
    moduleOn = {0.26, 0.20, 0.42, 1.00},
    moduleOnHov = {0.32, 0.26, 0.50, 1.00},
    moduleOff = {0.16, 0.13, 0.22, 1.00},
    moduleOffHov = {0.22, 0.17, 0.30, 1.00},
    startPrimary = {0.36, 0.18, 0.62, 1.00},
    startPrimaryHov = {0.44, 0.24, 0.74, 1.00},
    startBusy = {0.52, 0.20, 0.48, 1.00},
    startBusyHov = {0.62, 0.26, 0.56, 1.00},
    navColumnBg = {0.07, 0.05, 0.13, 1.00},
}
local integrationToolLastRun = {}
local maui_restore_win = nil
local maui_window_persist_at = 0
local autoMemAfterRetune = false
local isDirty = false
local lastSaveLabel = 'Never'
local lastSavedFingerprint = ''
local pendingUnsavedAction = nil
local pendingUnsavedFile = nil
local pendingStartWarnings = nil
local actionLastAt = {}
local actionNowFn = function() return mq.gettime() / 1000 end
local readmeGlossaryFilter = ''
local readmeJumpToTab = nil
--- Portable default: MacroQuest install dir (folder above `lua`). Put optional bundles like `EZInventory/...` there.
local function DefaultIntegrationSourceRoot()
    local ld = tostring(mq.luaDir or ''):gsub('\\', '/'):gsub('/+$', '')
    local parent = ld:match('^(.*)/lua$')
    return parent or ''
end
local integrationSourceRoot = DefaultIntegrationSourceRoot()
local integrationAutoSync = true
local integrationStatusCache = {}
local integrationStatusNextRefresh = 0
local integrationStatusRefreshMs = 500
local pendingLuaConsoleRestartAt = nil
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

local SafeTLOCall
SafeTLOCall = function(fn, default)
    local ok, value = pcall(fn)
    if ok and value ~= nil then
        return value
    end
    return default
end

--- INI filenames may include spaces (e.g. server "Ultimate EQ"). DoCommand rejects `/memmyspells "..."`;
--- use ${Parse[0,...]} so the path is one literal token (see MacroQuest parser docs for ${Parse[]}).
local function CmdMemMySpells(iniFile)
    local s = tostring(iniFile or '')
    if s == '' then
        return
    end
    if not s:lower():match('%.ini$') then
        s = s .. '.ini'
    end
    s = s:gsub('\\', '/'):gsub('"', '')
    -- `]` would terminate ${Parse[0,...]} early; EQ paths normally omit it.
    local payload = s:gsub(']', '')
    mq.cmd('/memmyspells ${Parse[0,' .. payload .. ']}')
end

globals.MyServer = SafeTLOCall(function() return mq.TLO.EverQuest.Server() end, 'Unknown') -- UPDATED: nil-safe TLO read during transient load/zoning states
globals.MyName = SafeTLOCall(function() return mq.TLO.Me.CleanName() end, 'Unknown') -- UPDATED: nil-safe TLO read during transient load/zoning states
globals.MyLevel = tonumber(SafeTLOCall(function() return mq.TLO.Me.Level() end, 1) or 1) or 1 -- UPDATED: enforce numeric level with safe fallback
globals.MyClass = tostring(SafeTLOCall(function() return mq.TLO.Me.Class.ShortName() end, 'unk') or 'unk'):lower() -- UPDATED: nil-safe class short name normalization

--- Main window: comfortable panel on large monitors (saved sizes were uncapped and could fill the screen).
local MAUI_WIN_MIN_W, MAUI_WIN_MIN_H = 580, 400
local MAUI_WIN_MAX_W, MAUI_WIN_MAX_H = 1200, 820
local MAUI_WIN_DEFAULT_W, MAUI_WIN_DEFAULT_H = 760, 520

globals.MAUI_INI = ('%s/%s_%s.ini'):format(mq.configDir, globals.MyServer, globals.MyName)
local maui_ini_key = 'MAUI'
if utils.FileExists(globals.MAUI_INI) then
    globals.MAUI_Config = LIP.load(globals.MAUI_INI, false)
end
do
    local sec = globals.MAUI_Config and globals.MAUI_Config[maui_ini_key]
    if sec and sec.WinW and tonumber(sec.WinW) and tonumber(sec.WinW) > 80 then
        local rw = tonumber(sec.WinW) or MAUI_WIN_DEFAULT_W
        local rh = tonumber(sec.WinH) or MAUI_WIN_DEFAULT_H
        rw = math.max(MAUI_WIN_MIN_W, math.min(MAUI_WIN_MAX_W, rw))
        rh = math.max(MAUI_WIN_MIN_H, math.min(MAUI_WIN_MAX_H, rh))
        maui_restore_win = {
            x = tonumber(sec.WinX) or 80,
            y = tonumber(sec.WinY) or 80,
            w = rw,
            h = rh,
        }
    end
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

-- Forward declarations for helpers referenced by earlier-defined local functions.
local EnsureConfigSection
local IsNullOrEmpty
local ParseToggleValue
local IsSectionEnabled

-- GMConsole-style theme palette, with current MAUI style preserved as template.
local uiThemes = {
    ['template'] = {
        windowBg = {0.04, 0.02, 0.08, 0.95},
        titleBg = {0.14, 0.02, 0.22, 1.00},
        titleBgActive = {0.24, 0.04, 0.32, 1.00},
        button = {0.18, 0.06, 0.26, 1.00},
        buttonHovered = {0.36, 0.09, 0.44, 1.00},
        buttonActive = {0.50, 0.12, 0.58, 1.00},
        frameBg = {0.10, 0.04, 0.16, 1.00},
        frameBgHovered = {0.18, 0.07, 0.26, 1.00},
        header = {0.22, 0.07, 0.30, 1.00},
        text = {0.92, 0.96, 1.00, 1.00},
        border = {0.90, 0.16, 0.68, 0.70},
        separator = {0.52, 0.28, 0.72, 0.45},
        menuBarBg = {0.08, 0.03, 0.14, 1.00},
        tableRowBg = {0.00, 0.00, 0.00, 0.00},
        tableRowBgAlt = {0.08, 0.03, 0.14, 0.60},
        tableBorderLight = {0.30, 0.10, 0.40, 0.60},
        tableBorderStrong = {0.60, 0.18, 0.80, 0.80},
        scrollbarBg = {0.02, 0.01, 0.06, 0.80},
        scrollbarGrab = {0.30, 0.08, 0.40, 0.80},
        scrollbarGrabHovered = {0.50, 0.14, 0.60, 0.90},
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
    local mem = globals.MAUI_Config[maui_ini_key] or {}
    local tmpStartCommand = mem['StartCommand'] or (globals.Schema and globals.Schema.StartCommands and globals.Schema.StartCommands[1]) or '/mac muleassist'
    local tmpTheme = NormalizeThemeKey(themeOrder[currentThemeIndex] or activeThemeKey)
    local tmpAutoMemRetune = autoMemAfterRetune
    local wx, wy, ww, wh = mem.WinX, mem.WinY, mem.WinW, mem.WinH
    if utils.FileExists(globals.MAUI_INI) then
        globals.MAUI_Config = LIP.load(globals.MAUI_INI, false)
    else
        globals.MAUI_Config = {}
    end
    globals.MAUI_Config[maui_ini_key] = {['StartCommand'] = tmpStartCommand, ['INIFile'] = globals.INIFile, ['Theme'] = tmpTheme, ['AutoMemRetune'] = tmpAutoMemRetune}
    if wx then globals.MAUI_Config[maui_ini_key].WinX = wx end
    if wy then globals.MAUI_Config[maui_ini_key].WinY = wy end
    if ww then globals.MAUI_Config[maui_ini_key].WinW = ww end
    if wh then globals.MAUI_Config[maui_ini_key].WinH = wh end
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
    local now = actionNowFn()
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

local function GetMauiLogoTexturePath()
    return NormalizePath(mq.luaDir) .. '/' .. MauiFloat.relPath
end

local function EnsureMauiLogoTexture()
    if MauiFloat.logoTex or MauiFloat.logoFailed then
        return
    end
    if not mq.CreateTexture then
        MauiFloat.logoFailed = true
        return
    end
    local path = GetMauiLogoTexturePath()
    if not utils.FileExists(path) then
        MauiFloat.logoFailed = true
        return
    end
    local ok, tex = pcall(mq.CreateTexture, path)
    if ok and tex and type(tex.GetTextureID) == 'function' then
        MauiFloat.logoTex = tex
    else
        MauiFloat.logoFailed = true
    end
end

--- @param tooltip string shown on hover (describe what THIS control does — main vs mini are separate).
--- @return boolean clicked
--- Use ImGui.Image (not ImageButton) so ImGui does not draw button frame/border (avoids blue/hover outline on MQ themes).
local function DrawMauiLogoButton(idSuffix, sizePx, tooltip)
    EnsureMauiLogoTexture()
    local maxPx = sizePx or MauiFloat.floatSize
    local clicked = false
    if MauiFloat.logoTex then
        local t = MauiFloat.logoTex
        local tw, th = maxPx, maxPx
        if t.size then
            local s = t.size
            local w0 = tonumber(s.x or s.X or (type(s) == 'table' and s[1])) or 0
            local h0 = tonumber(s.y or s.Y or (type(s) == 'table' and s[2])) or 0
            if w0 > 0 and h0 > 0 then
                local sc = math.min(maxPx / w0, maxPx / h0)
                tw, th = w0 * sc, h0 * sc
            end
        end
        ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, 0, 0)
        ImGui.Image(t:GetTextureID(), ImVec2(tw, th), ImVec2(0, 0), ImVec2(1, 1))
        ImGui.PopStyleVar()
        clicked = ImGui.IsItemClicked(0)
    else
        clicked = ImGui.Button('UE##mauiUELogoFb' .. tostring(idSuffix), maxPx, maxPx)
    end
    if tooltip and tooltip ~= '' and ImGui.IsItemHovered() then
        ImGui.SetTooltip(tooltip)
    end
    return clicked
end

local mauiFloatWinFlags = bit32.bor(
    ImGuiWindowFlags.NoTitleBar,
    ImGuiWindowFlags.NoResize,
    ImGuiWindowFlags.NoScrollbar,
    ImGuiWindowFlags.NoFocusOnAppearing,
    ImGuiWindowFlags.AlwaysAutoResize,
    ImGuiWindowFlags.NoBackground
)

--- Mini Setup (`Mini Setup` button) sets main hidden and only mini open. The logo must dismiss *both* when any UI is up, and restore the main window when both are closed (same as float + header logo).
local function ToggleMauiFromLogoButton()
    if open or miniSetupOpen then
        open = false
        miniSetupOpen = false
    else
        open = true
    end
end

local function DrawMauiFloatingToggleWindow()
    if not MauiFloat.showToggle then
        return
    end
    ImGui.PushStyleVar(ImGuiStyleVar.WindowBorderSize, 0)
    ImGui.PushStyleVar(ImGuiStyleVar.WindowPadding, 0, 0)
    ImGui.PushStyleColor(ImGuiCol.Border, 0, 0, 0, 0)
    ImGui.PushStyleColor(ImGuiCol.WindowBg, 0, 0, 0, 0)
    ImGui.Begin('UEA###MAUIFloatToggle', nil, mauiFloatWinFlags)
    local tipFloat = (open or miniSetupOpen)
        and 'Hide all MAUI UI (main window + Mini Setup)'
        or 'Show main MAUI window'
    if DrawMauiLogoButton('float', MauiFloat.floatSize, tipFloat) then
        ToggleMauiFromLogoButton()
    end
    ImGui.End()
    ImGui.PopStyleColor(2)
    ImGui.PopStyleVar(2)
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
    if type(globals.Config) ~= 'table' then
        globals.Config = {}
    end
    -- Set "NULL" string values to nil so they aren't saved
    for sectionName,sectionProperties in pairs(globals.Config) do
        if type(sectionProperties) == 'table' then
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
    end
    if globals.INIFile:sub(-string.len('.ini')) ~= '.ini' then
        globals.INIFile = globals.INIFile .. '.ini'
    end
    LIP.save(mq.configDir..'/'..globals.INIFile, globals.Config, globals.Schema)
    SaveMAUIConfig()
    MarkConfigClean()
end

-- FIX 5: SpellSorter logic was inverted and redundant.
-- Original returned false for a<b AND false for a==b, which sorts descending but
-- with a redundant branch. Simplified to a clean descending-level comparator.
local SpellSorter = function(a, b)
    -- spell level is in spell[1], name in spell[2]
    -- Sort descending by level (highest level spells first)
    return a[1] > b[1]
end

local function AddSpellToMap(spell)
    if not spell or not spell() then return end
    local cat = SafeTLOCall(function() return spell.Category() end, 'Unknown')
    local subcat = SafeTLOCall(function() return spell.Subcategory() end, 'General')
    local spellName = SafeTLOCall(function() return spell.Name() end, '')
    if spellName == '' then return end
    if not spells[cat] then
        spells[cat] = {subcategories={}}
        table.insert(spells.categories, cat)
    end
    if not spells[cat][subcat] then
        spells[cat][subcat] = {}
        table.insert(spells[cat].subcategories, subcat)
    end
    --if spell.Level() >= globals.MyLevel-30 then
        local name = spellName:gsub(' Rk%..*', '')
        table.insert(spells[cat][subcat], {SafeTLOCall(function() return spell.Level() end, 0), name, spellName})
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
        if spellIter % 200 == 0 then
            mq.delay(0)
        end
        local spell = mq.TLO.Me.Book(spellIter)
        if spell() then
            AddSpellToMap(spell)
        end
    end
    SortMap(spells)
end

local function AddAAToMap(aa)
    if not aa or not aa() then return end
    local aaType = aatypes[SafeTLOCall(function() return aa.Type() end, nil)]
    if not aaType then return end  -- FIX 13a: guard against unknown AA type index
    if not altAbilities[aaType] then
        altAbilities[aaType] = {}
        table.insert(altAbilities.types, aaType)
    end
    -- FIX 13b: aa.Spell.Name() chains through an unevaluated TLO intermediate.
    -- Must evaluate aa.Spell() first, then get Name() from the spell object.
    local spellObj = aa.Spell
    local spellName = (spellObj and spellObj() and SafeTLOCall(function() return spellObj.Name() end, '')) or ''
    local aaName = SafeTLOCall(function() return aa.Name() end, '')
    if aaName == '' then return end
    table.insert(altAbilities[aaType], {aaName, spellName})
end

local function InitAATree()
    -- FIX 2: Guard aa existence before accessing aa.Spell().
    -- Previously, if mq.TLO.Me.AltAbility(aaIter) returned a nil/empty object,
    -- calling aa.Spell() on it would crash or silently fail.
    for aaIter=1,10000 do
        if aaIter % 2000 == 0 then
            mq.delay(0)
        end
        local aa = mq.TLO.Me.AltAbility(aaIter)
        if aa and aa() then
            if aa.Spell and aa.Spell() then
                AddAAToMap(aa)
            end
        end
    end
    for _,type in ipairs(altAbilities.types) do
        if altAbilities[type] then
            table.sort(altAbilities[type], function(a,b) return a[1] < b[1] end)
        end
    end
end

local function AddDiscToMap(disc)
    if not disc or not disc() then return end
    local cat = SafeTLOCall(function() return disc.Category() end, 'Unknown')
    local subcat = SafeTLOCall(function() return disc.Subcategory() end, 'General')
    local discName = SafeTLOCall(function() return disc.Name() end, '')
    if discName == '' then return end
    if not discs[cat] then
        discs[cat] = {subcategories={}}
        table.insert(discs.categories, cat)
    end
    if not discs[cat][subcat] then
        discs[cat][subcat] = {}
        table.insert(discs[cat].subcategories, subcat)
    end
    local name = discName:gsub(' Rk%..*', '')
    table.insert(discs[cat][subcat], {SafeTLOCall(function() return disc.Level() end, 0), name, discName})
end

local function InitDiscTree()
    -- FIX 3: The original repeat/until condition was wrong.
    -- mq.TLO.Me.CombatAbility(N)() returns nil (falsy) when the slot is empty,
    -- NOT the lua nil literal, so == nil comparisons are unreliable here.
    -- Use `not disc()` as the stop condition, and check inside the loop body.
    local discIter = 1
    while true do
        if discIter % 100 == 0 then
            mq.delay(0)
        end
        local disc = mq.TLO.Me.CombatAbility(discIter)
        if not disc or not disc() then break end
        AddDiscToMap(disc)
        discIter = discIter + 1
    end
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
        if not spell or not spell() then
            valid = false
        elseif not SafeTLOCall(function() return spell.ID() end, nil) then
            valid = false
        elseif SafeTLOCall(function() return spell.Subcategory() end, nil) ~= subCat then
            valid = false
        elseif SafeTLOCall(function() return spell.TargetType() end, nil) ~= targetType then
            valid = false
        elseif SafeTLOCall(function() return spell.NumEffects() end, nil) ~= numEffects then
            valid = false
        elseif (SafeTLOCall(function() return spell.Level() end, 0) or 0) <= minLevel then
            valid = false
        end
        if valid then
            local okUpgrade = pcall(function()
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
            end)
            if not okUpgrade then
                maxName = maxName or ''
            end
        end
    end
    return maxName
end

-- ImGui functions

-- Color spell names in spell picker similar to the spell bar context menus
local function SetSpellTextColor(spell)
    local target = tloCache:get(spell..'.targettype', function() return SafeTLOCall(function() return mq.TLO.Spell(spell).TargetType() end, nil) end)
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

local function CursorAttachmentType()
    return SafeTLOCall(function() return mq.TLO.CursorAttachment.Type() end, '')
end

local function CursorAttachmentName(kind)
    if kind == 'ITEM' then
        return SafeTLOCall(function() return mq.TLO.CursorAttachment.Item.Name() end, nil)
    elseif kind == 'SPELL_GEM' then
        return SafeTLOCall(function() return mq.TLO.CursorAttachment.Spell.Name() end, nil)
    end
end

local function BuildClickyItemLists()
    local equipped = {}
    local bags = {}
    local seen = {}

    local function addClicky(list, item, source)
        if not item or not item() then return end
        local itemName = SafeTLOCall(function() return item.Name() end, '')
        if itemName == '' then return end
        local clickSpell = SafeTLOCall(function() return item.Clicky.Spell() end, '')
        if not clickSpell or clickSpell == '' then return end
        local dedupeKey = itemName:lower()
        if seen[dedupeKey] then return end
        seen[dedupeKey] = true
        table.insert(list, {
            name = itemName,
            spell = tostring(clickSpell),
            source = source or '',
            sort = itemName:lower(),
        })
    end

    for slot = 0, 22 do
        local item = mq.TLO.Me.Inventory(slot)
        addClicky(equipped, item, 'equipped')
    end

    for invSlot = 23, 34 do
        local pack = mq.TLO.Me.Inventory(invSlot)
        addClicky(bags, pack, string.format('bag %d', invSlot - 22))
        if pack() and (pack.Container() or 0) > 0 then
            for bagSlot = 1, pack.Container() do
                addClicky(bags, pack.Item(bagSlot), string.format('bag %d.%d', invSlot - 22, bagSlot))
            end
        end
    end

    table.sort(equipped, function(a, b) return a.sort < b.sort end)
    table.sort(bags, function(a, b) return a.sort < b.sort end)
    return equipped, bags
end

local function DrawClickyMenuList(entries, idPrefix, sectionName, key, valueParts)
    if #entries == 0 then
        ImGui.TextDisabled('No clickies found')
        return
    end
    local menuHeight = -1
    if #entries > 25 then
        menuHeight = ImGui.GetTextLineHeight() * 25
    end
    ImGui.SetNextWindowSize(420, menuHeight)
    for idx, entry in ipairs(entries) do
        local label = string.format('%s -> %s##%s%s%s%d', entry.name, entry.spell, idPrefix, sectionName, key, idx)
        if ImGui.MenuItem(label) then
            valueParts[1] = entry.name
            selectedUpgrade = nil
        end
    end
end

local function GetClickyEffectBucket(spellName)
    if not spellName or spellName == '' then return 'Utility' end
    local spell = mq.TLO.Spell(spellName)
    if not spell() then return 'Utility' end

    local spellType = tostring(SafeTLOCall(function() return spell.SpellType() end, '')):lower()
    if spellType:find('beneficial', 1, true) or spellType == '0' then
        return 'Beneficial'
    end
    if spellType:find('detrimental', 1, true) or spellType == '1' then
        return 'Detrimental'
    end

    local cat = tostring(SafeTLOCall(function() return spell.Category() end, '')):lower()
    if cat:find('detrimental', 1, true) then return 'Detrimental' end
    if cat:find('buff', 1, true) or cat:find('heal', 1, true) or cat:find('aura', 1, true) then
        return 'Beneficial'
    end
    return 'Utility'
end

local function BuildClickyCategoryTree(equippedClickies, bagClickies)
    local tree = {
        Beneficial = {categories = {}, count = 0},
        Detrimental = {categories = {}, count = 0},
        Utility = {categories = {}, count = 0},
    }

    local function addToTree(entry)
        local spellName = tostring(entry.spell or '')
        local spell = mq.TLO.Spell(spellName)
        local category = 'Misc'
        local subcategory = 'General'
        if spell() then
            category = tostring(SafeTLOCall(function() return spell.Category() end, 'Misc'))
            subcategory = tostring(SafeTLOCall(function() return spell.Subcategory() end, 'General'))
            if category == '' then category = 'Misc' end
            if subcategory == '' then subcategory = 'General' end
        end
        local bucket = GetClickyEffectBucket(spellName)
        local b = tree[bucket]
        if not b[category] then
            b[category] = {subcategories = {}}
            table.insert(b.categories, category)
        end
        if not b[category][subcategory] then
            b[category][subcategory] = {}
            table.insert(b[category].subcategories, subcategory)
        end
        table.insert(b[category][subcategory], entry)
        b.count = b.count + 1
    end

    for _, e in ipairs(equippedClickies) do addToTree(e) end
    for _, e in ipairs(bagClickies) do addToTree(e) end

    for _, bucket in ipairs({'Beneficial', 'Detrimental', 'Utility'}) do
        local b = tree[bucket]
        table.sort(b.categories)
        for _, cat in ipairs(b.categories) do
            table.sort(b[cat].subcategories)
            for _, sub in ipairs(b[cat].subcategories) do
                table.sort(b[cat][sub], function(a, c) return (a.sort or a.name or '') < (c.sort or c.name or '') end)
            end
        end
    end
    return tree
end

local function DrawClickyCategoryTreeMenu(tree, sectionName, key, valueParts)
    if not ImGui.BeginMenu('By Effect / Category##rcmenu'..sectionName..key) then
        return
    end
    for _, bucket in ipairs({'Beneficial', 'Detrimental', 'Utility'}) do
        local b = tree[bucket]
        if ImGui.BeginMenu(string.format('%s (%d)##rcmenu%s%s%s', bucket, b.count or 0, bucket, sectionName, key)) then
            if (b.count or 0) == 0 then
                ImGui.TextDisabled('No clickies found')
            else
                for _, category in ipairs(b.categories or {}) do
                    if ImGui.BeginMenu(category..'##rcmenu'..bucket..sectionName..key..category) then
                        for _, subcategory in ipairs(b[category].subcategories or {}) do
                            if ImGui.BeginMenu(subcategory..'##rcmenu'..bucket..sectionName..key..subcategory) then
                                DrawClickyMenuList(b[category][subcategory], 'clickcat'..bucket..category..subcategory, sectionName, key, valueParts)
                                ImGui.EndMenu()
                            end
                        end
                        ImGui.EndMenu()
                    end
                end
            end
            ImGui.EndMenu()
        end
    end
    ImGui.EndMenu()
end

-- Recreate the spell bar context menu
-- sectionName+key+index defines where to store the result
-- selectedIdx is used to clear spell upgrade input incase of updating over an existing entry
local function DrawSpellPicker(sectionName, key, index)
    if not globals.Config[sectionName][key..index] then
        globals.Config[sectionName][key..index] = ''
    end
    local valueParts
    local cfgVal = globals.Config[sectionName][key..index]
    if type(cfgVal) == "string" then
        valueParts = utils.Split(cfgVal, '|', 1)
    elseif type(cfgVal) == "number" then
        valueParts = { tostring(cfgVal) }
    else
        -- FIX 16: booleans, corrupted INI, etc. — must never leave valueParts nil for concat below
        valueParts = { cfgVal ~= nil and tostring(cfgVal) or '' }
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
        if sectionName ~= 'MySpells' then
            local equippedClickies, bagClickies = BuildClickyItemLists()
            local clickyTree = BuildClickyCategoryTree(equippedClickies, bagClickies)
            if ImGui.BeginMenu('Items (Clickies)##rcmenu'..sectionName..key) then
                DrawClickyCategoryTreeMenu(clickyTree, sectionName, key, valueParts)
                if ImGui.BeginMenu(string.format('Equipped (%d)##rcmenu%s%s', #equippedClickies, sectionName, key)) then
                    DrawClickyMenuList(equippedClickies, 'eqclick', sectionName, key, valueParts)
                    ImGui.EndMenu()
                end
                if ImGui.BeginMenu(string.format('Bags (%d)##rcmenu%s%s', #bagClickies, sectionName, key)) then
                    DrawClickyMenuList(bagClickies, 'bagclick', sectionName, key, valueParts)
                    ImGui.EndMenu()
                end
                ImGui.EndMenu()
            end
        end
        if valueParts[1] then
            local rankname = tloCache:get(valueParts[1]..'.rankname', function() return SafeTLOCall(function() return mq.TLO.Spell(valueParts[1]).RankName() end, nil) end)
            if rankname then
                local bookidx = tloCache:get('book.'..rankname, function() return SafeTLOCall(function() return mq.TLO.Me.Book(rankname)() end, nil) end)
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
        selectedUpgrade = GetSpellUpgrade(
            SafeTLOCall(function() return spell.TargetType() end, nil),
            SafeTLOCall(function() return spell.Subcategory() end, nil),
            SafeTLOCall(function() return spell.NumEffects() end, nil),
            SafeTLOCall(function() return spell.Level() end, 0)
        )
    end
    -- Upgrade found? display the upgrade button
    if selectedUpgrade ~= '' and selectedUpgrade ~= SafeTLOCall(function() return spell.Name() end, '') then
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
        selectedUpgrade = GetSpellUpgrade(
            SafeTLOCall(function() return spell.TargetType() end, nil),
            SafeTLOCall(function() return spell.Subcategory() end, nil),
            SafeTLOCall(function() return spell.NumEffects() end, nil),
            0
        )
    end
    -- Upgrade found? display the upgrade button
    if selectedUpgrade ~= '' and selectedUpgrade ~= SafeTLOCall(function() return spell.Name() end, '') then
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
    -- FIX 4: Guard spell existence before accessing spell.RankName().
    -- Previously, if valueParts[1] was empty or invalid, spell could be a non-nil
    -- userdata with no valid data, causing spell.RankName() to error or return garbage.
    if spell and spell() then
        local rankName = SafeTLOCall(function() return spell.RankName() end, nil)
        if rankName and SafeTLOCall(function() return mq.TLO.Me.Book(rankName)() end, nil) then
            local upgradeResult = DrawSelectedSpellUpgradeButton(spell)
            if upgradeResult then valueParts[1] = upgradeResult end
        else
            local upgradeResult = DrawSelectedSpellDowngradeButton(spell)
            if upgradeResult then valueParts[1] = upgradeResult end
        end
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
            local cursorType = CursorAttachmentType()
            local cursorName = CursorAttachmentName(cursorType)
            if cursorName and (cursorType == 'ITEM' or cursorType == 'SPELL_GEM') then
                globals.Config[sectionName][key..listIdx] = cursorName
            else
                selectedListItem = {key, listIdx}
                selectedUpgrade = nil
            end
        else
            local cursorType = CursorAttachmentType()
            local cursorName = CursorAttachmentName(cursorType)
            if cursorName and (cursorType == 'ITEM' or cursorType == 'SPELL_GEM') then
                globals.Config[sectionName][key] = cursorName
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
        local rankname = tloCache:get(iniValue..'.rankname', function() return SafeTLOCall(function() return mq.TLO.Spell(iniValue).RankName() end, nil) end)
        if rankname then
            if tloCache:get('book.'..rankname, function() return SafeTLOCall(function() return mq.TLO.Me.Book(rankname)() end, nil) end) then
                valid = true
            elseif tloCache:get('aa.'..iniValue, function() return SafeTLOCall(function() return mq.TLO.Me.AltAbility(iniValue)() end, nil) end) then
                valid = true
            elseif tloCache:get('disc.'..rankname, function() return SafeTLOCall(function() return mq.TLO.Me.CombatAbility(rankname)() end, nil) end) then
                valid = true
            end
        elseif tloCache:get('item.'..iniValue, function() return SafeTLOCall(function() return mq.TLO.FindItem(iniValue)() end, nil) end) then
            valid = true
        elseif iniValue:find('command:') or iniValue:find('${') then
            valid = true
        elseif tloCache:get('ability.'..iniValue, function() return SafeTLOCall(function() return mq.TLO.Me.Ability(iniValue)() end, nil) end) then
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
    if SafeTLOCall(function() return mq.TLO.FindItem(name)() end, nil)
        or SafeTLOCall(function() return mq.TLO.Me.AltAbility(name)() end, nil)
        or SafeTLOCall(function() return mq.TLO.Me.Ability(name)() end, nil) then
        return nil
    end
    if SafeTLOCall(function() return mq.TLO.Me.CombatAbility(name)() end, nil) then
        return nil
    end

    local spell = mq.TLO.Spell(name)
    if spell() then
        local rankName = SafeTLOCall(function() return spell.RankName() end, nil)
        if rankName and SafeTLOCall(function() return mq.TLO.Me.CombatAbility(rankName)() end, nil) then
            return rankName
        end
        local knownSpell = rankName and SafeTLOCall(function() return mq.TLO.Me.Book(rankName)() end, nil)
        local minLevel = 0
        if mode == 'upgrade' and knownSpell then
            minLevel = SafeTLOCall(function() return spell.Level() end, 0)
        end
        local replacement = GetSpellUpgrade(
            SafeTLOCall(function() return spell.TargetType() end, nil),
            SafeTLOCall(function() return spell.Subcategory() end, nil),
            SafeTLOCall(function() return spell.NumEffects() end, nil),
            minLevel
        )
        if replacement and replacement ~= '' and replacement ~= name then
            return replacement
        end
    end

    -- Fallback: strip explicit rank suffixes and retry disc/AA/spell name.
    local baseName = name:gsub(' Rk%..*', '')
    if baseName ~= name then
        if SafeTLOCall(function() return mq.TLO.Me.CombatAbility(baseName)() end, nil)
            or SafeTLOCall(function() return mq.TLO.Me.AltAbility(baseName)() end, nil)
            or SafeTLOCall(function() return mq.TLO.Me.Ability(baseName)() end, nil) then
            return baseName
        end
        local baseSpell = mq.TLO.Spell(baseName)
        if baseSpell() then
            local replacement = GetSpellUpgrade(
                SafeTLOCall(function() return baseSpell.TargetType() end, nil),
                SafeTLOCall(function() return baseSpell.Subcategory() end, nil),
                SafeTLOCall(function() return baseSpell.NumEffects() end, nil),
                0
            )
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
    local rankName = SafeTLOCall(function() return spell.RankName() end, nil)
    if not rankName or not SafeTLOCall(function() return mq.TLO.Me.Book(rankName)() end, nil) then return false end
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
        elseif tloCache:get(iniValue..'.name', function() return SafeTLOCall(function() return mq.TLO.Spell(iniValue)() end, nil) end) then
            -- Need to create a group for drag/drop to work, doesn't seem to work with just the texture animation?
            ImGui.BeginGroup()
            local x,y = ImGui.GetCursorPos()
            ImGui.Button('##'..index..sectionName..key, iconSize[1], iconSize[2])
            ImGui.SetCursorPosX(x)
            ImGui.SetCursorPosY(y)
            local spellIcon = tloCache:get(iniValue..'.spellicon', function() return SafeTLOCall(function() return mq.TLO.Spell(iniValue).SpellIcon() end, nil) end)
            animSpellIcons:SetTextureCell(spellIcon)
            ImGui.DrawTextureAnimation(animSpellIcons, iconSize[1], iconSize[2])
            ImGui.EndGroup()
        elseif tloCache:get('item.'..iniValue, function() return SafeTLOCall(function() return mq.TLO.FindItem(iniValue)() end, nil) end) then
            -- Need to create a group for drag/drop to work, doesn't seem to work with just the texture animation?
            ImGui.BeginGroup()
            local x,y = ImGui.GetCursorPos()
            ImGui.Button('##'..index..sectionName..key, iconSize[1], iconSize[2])
            ImGui.SetCursorPosX(x)
            ImGui.SetCursorPosY(y)
            local itemIcon = tloCache:get('itemicon.'..iniValue, function() return SafeTLOCall(function() return mq.TLO.FindItem(iniValue).Icon() end, nil) end)
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
            local cursorType = CursorAttachmentType()
            local cursorName = CursorAttachmentName(cursorType)
            if cursorName and (cursorType == 'ITEM' or cursorType == 'SPELL_GEM') then
                globals.Config[sectionName][key..index] = cursorName
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
    local size = globals.Config[sectionName][key..'Size']
    if size == nil or type(size) ~= 'number' then
        CheckInputType(key..'Size', size, 'number', 'InputInt')
        size = 0
    end
    ImGui.SetCursorPosX(175)
    --- InputInt includes value + steppers; 100px clips digits. Fit row with right margin.
    local sizeInputW = math.max(160, ImGui.GetContentRegionAvail() - 14)
    ImGui.PushItemWidth(sizeInputW)
    -- Set size of list and check boundaries
    size = ImGui.InputInt('##sizeinput'..sectionName..key, size)
    if size < 0 then
        size = 0
    elseif size > value['Max'] then
        size = value['Max']
    end
    ImGui.PopItemWidth()
    local xOffset,yOffset = ImGui.GetCursorPos()
    --- Leave inset so spell icons are not flush against the child border.
    local iconRowPad = 14
    local avail = math.max(38, ImGui.GetContentRegionAvail() - iconRowPad)
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
    -- MQ ImGui: manual SetCursorPos grid must submit an item so parent/child bounds stay consistent.
    ImGui.Dummy(1, 1)
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
            ImGui.PushItemWidth(math.max(160, ImGui.GetContentRegionAvail() - 14))
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
    local fieldW = math.max(160, ImGui.GetContentRegionAvail() - 14)
    if value['Type'] == 'SWITCH' then
        local initialValue = utils.InitCheckBoxValue(globals.Config[sectionName][key])
        CheckInputType(key, initialValue, 'boolean', 'Checkbox')
        globals.Config[sectionName][key] = ImGui.Checkbox('##'..key, initialValue)
    elseif value['Type'] == 'SPELL' then
        DrawSpellIconOrButton(sectionName, key, '')
        ImGui.SameLine()
        ImGui.PushItemWidth(fieldW)
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
        ImGui.PushItemWidth(fieldW)
        globals.Config[sectionName][key] = ImGui.InputInt('##'..sectionName..key, initialValue)
        ImGui.PopItemWidth()
        if value['Min'] and globals.Config[sectionName][key] < value['Min'] then
            globals.Config[sectionName][key] = value['Min']
        elseif value['Max'] and globals.Config[sectionName][key] > value['Max'] then
            globals.Config[sectionName][key] = value['Max']
        end
    elseif value['Type'] == 'STRING' then
        ImGui.PushItemWidth(fieldW)
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
            ImGui.PushItemWidth(math.max(160, ImGui.GetContentRegionAvail() - 14))
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
    local avail = math.max(36, ImGui.GetContentRegionAvail() - 14)
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
    ImGui.Dummy(1, 1)
    -- in case a spell gem was left clicked, don't mark it as selected so we don't enter the selected item drill-down
    selectedListItem = {nil, 0}
    selectedUpgrade = nil
end

--- Two-column gem rack with live bar readout (SpellSet / Gems nav).
local function DrawGemRackMySpells()
    if not globals.Config.MySpells then globals.Config.MySpells = {} end
    ImGui.TextWrapped('Gem bar (live) vs [MySpells] INI. Clear removes the line; use icon row below for drag/pick.')
    if ImGui.BeginTable('##GemRack13', 5, ImGuiTableFlags.BordersOuter + ImGuiTableFlags.RowBg + ImGuiTableFlags.ScrollY, -1, 280) then
        ImGui.TableSetupColumn('Gem')
        ImGui.TableSetupColumn('On bar')
        ImGui.TableSetupColumn('INI value')
        ImGui.TableSetupColumn('Clr')
        ImGui.TableSetupColumn('Assign')
        ImGui.TableHeadersRow()
        for i = 1, 13 do
            ImGui.TableNextRow()
            local gemSlot = mq.TLO.Me.Gem(i)
            local live = ''
            if gemSlot and gemSlot() then
                live = tostring(SafeTLOCall(function() return gemSlot.Name() end, '') or '')
            end
            ImGui.TableSetColumnIndex(0)
            ImGui.TextColored(0.85, 0.78, 1, 1, tostring(i))
            ImGui.TableSetColumnIndex(1)
            ImGui.TextWrapped(live ~= '' and live or '—')
            ImGui.TableSetColumnIndex(2)
            local iniKey = 'Gem' .. i
            local cur = globals.Config.MySpells[iniKey]
            if cur == nil or cur == 'NULL' then
                cur = ''
            else
                cur = tostring(cur)
            end
            ImGui.PushItemWidth(-1)
            local newv = ImGui.InputText('##gemit_' .. i, cur)
            ImGui.PopItemWidth()
            if newv ~= cur then
                globals.Config.MySpells[iniKey] = (newv == '' or newv == 'NULL') and 'NULL' or newv
            end
            ImGui.TableSetColumnIndex(3)
            if ImGui.SmallButton('X##gemclr' .. i) then
                globals.Config.MySpells[iniKey] = 'NULL'
            end
            ImGui.TableSetColumnIndex(4)
            if ImGui.SmallButton('Use bar##gemuse' .. i) then
                if live ~= '' then
                    globals.Config.MySpells[iniKey] = live
                end
            end
        end
        ImGui.EndTable()
    end
end

local function DrawSpells(spellSection)
    ImGui.TextColored(1, 1, 0, 1, spellSection)
    if globals.Config[spellSection] then
        if MauiRuntime.useGemRack then
            DrawGemRackMySpells()
        else
            DrawSpellsGemList(spellSection)
        end
    end
    if ImGui.Button('Update from spell bar') then
        if not globals.Config[spellSection] then globals.Config[spellSection] = {} end
        for i=1,13 do
            -- FIX 9: Guard Gem TLO existence before calling .Name().
            -- An empty gem slot returns a falsy userdata, not lua nil.
            local gemSlot = mq.TLO.Me.Gem(i)
            if gemSlot and gemSlot() then
                globals.Config[spellSection]['Gem'..i] = gemSlot.Name()
            else
                globals.Config[spellSection]['Gem'..i] = 'NULL'
            end
        end
        Save()
        globals.INIFileContents = utils.ReadRawINIFile()
    end
    ImGui.SameLine()
    if ImGui.Button('Mem Spells') then
        CmdMemMySpells(globals.INIFile)
    end
end

-- Draw an INI section tab
local function DrawSection(sectionName, sectionProperties)
    if type(globals.Config) ~= 'table' then
        globals.Config = {}
    end
    if type(sectionProperties) ~= 'table' then
        ImGui.TextColored(1, 0.35, 0.35, 1, string.format('Missing schema section: %s', tostring(sectionName)))
        return
    end
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
            -- FIX 6: customSections can be nil when the addon require fails.
            -- pairs(nil) crashes. Guard with nil check.
            if customSections then
                ImGui.Separator()
                ImGui.Separator()
                for section,_ in pairs(customSections) do
                    ImGui.TableNextRow()
                    ImGui.TableNextColumn()
                    if ImGui.Selectable(section, selectedSection == section) then
                        selectedSection = section
                    end
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
        -- FIX 7: customSections can be nil when addon require fails.
        -- Indexing nil crashes. Guard with nil check.
        if customSections and customSections[selectedSection] then
            customSections[selectedSection]()
        else
            DrawSection(selectedSection, globals.Schema[selectedSection])
        end
    end
    ImGui.EndChild()
end

local function DrawWindowPanels()
    DrawSplitter(8, leftPanelDefaultWidth, 75)
    -- MQ ImGui: DrawSplitter uses SetCursorPos; extend parent bounds so following BeginChild stacks cleanly.
    ImGui.Dummy(1, 1)
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

--- Hero: centered UltimateEQAssist title (mockup), then identity + Solo/Group/Raid on row 2.
local function DrawUltimateModeBanner()
    local title = 'UltimateEQAssist'
    local tw = ImGui.CalcTextSize(title)
    ImGui.SetCursorPosX((ImGui.GetWindowWidth() - tw) * 0.5)
    ImGui.TextColored(0.96, 0.90, 1.0, 1, title)
    ImGui.Spacing()

    local cls = tostring(globals.MyClass or '?'):upper()
    local cname = tostring(globals.MyName or '?')
    local clvl = tostring(globals.MyLevel or '?')
    ImGui.TextColored(0.82, 0.76, 1.0, 1, (Icons.FA_USER or '') .. '  ')
    ImGui.SameLine()
    ImGui.TextColored(0.82, 0.76, 1.0, 1, string.format('%s · %s · Lv%s', cls, cname, clvl))

    ImGui.SameLine(ImGui.GetWindowWidth() - 360)
    ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, 10, 6)
    local modes = {'Solo', 'Group', 'Raid'}
    local P = UltimateAssistPalette
    for _, m in ipairs(modes) do
        local sel = (tostring(MauiRuntime.quickProfile):upper() == m:upper())
        if sel then
            ImGui.PushStyleColor(ImGuiCol.Button, P.modeSel[1], P.modeSel[2], P.modeSel[3], P.modeSel[4])
            ImGui.PushStyleColor(ImGuiCol.ButtonHovered, P.modeSelHov[1], P.modeSelHov[2], P.modeSelHov[3], P.modeSelHov[4])
            ImGui.PushStyleColor(ImGuiCol.ButtonActive, P.modeSel[1] * 0.85, P.modeSel[2] * 0.85, P.modeSel[3] * 0.85, 1)
            ImGui.PushStyleColor(ImGuiCol.Border, P.modeSelBorder[1], P.modeSelBorder[2], P.modeSelBorder[3], P.modeSelBorder[4])
            ImGui.PushStyleVar(ImGuiStyleVar.FrameBorderSize, 2)
            ImGui.PushStyleVar(ImGuiStyleVar.FrameRounding, 10)
        else
            ImGui.PushStyleColor(ImGuiCol.Button, P.modeUnsel[1], P.modeUnsel[2], P.modeUnsel[3], P.modeUnsel[4])
            ImGui.PushStyleColor(ImGuiCol.ButtonHovered, P.modeUnselHov[1], P.modeUnselHov[2], P.modeUnselHov[3], P.modeUnselHov[4])
            ImGui.PushStyleColor(ImGuiCol.ButtonActive, P.modeUnsel[1], P.modeUnsel[2], P.modeUnsel[3], 1)
            ImGui.PushStyleColor(ImGuiCol.Border, P.modeUnselBorder[1], P.modeUnselBorder[2], P.modeUnselBorder[3], P.modeUnselBorder[4])
            ImGui.PushStyleVar(ImGuiStyleVar.FrameBorderSize, 1)
            ImGui.PushStyleVar(ImGuiStyleVar.FrameRounding, 10)
        end
        if ImGui.Button(m .. '##qsmode_' .. m, 84, 30) then
            ApplySetupPreset(m)
        end
        ImGui.PopStyleVar(2)
        ImGui.PopStyleColor(4)
        ImGui.SameLine()
    end
    ImGui.PopStyleVar(1)
end

local function DrawUltimateIniSettingsRow()
    RefreshDirtyState()
    hide_ini_path = ImGui.Checkbox('Hide INI Path', hide_ini_path)

    if not hide_ini_path then
        ImGui.PushItemWidth(360)
        globals.INIFile,_ = ImGui.InputText('##UEA_INIPath', globals.INIFile or '')
        ImGui.PopItemWidth()
    end
    ImGui.SameLine()
    if ImGui.Button('Import') then
        filedialog.set_file_selector_open(true)
    end
    ImGui.SameLine()
    if ImGui.Button('Reload') then
        if not RequestUnsavedAction('reload') then
            ReloadINIFromDisk()
        end
    end
    ImGui.SameLine()
    ImGui.TextColored(0.72, 0.70, 0.88, 1.0, 'Template')
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

    ImGui.SameLine()
    local Pi = UltimateAssistPalette
    if isDirty then
        ImGui.TextColored(Pi.textWarn[1], Pi.textWarn[2], Pi.textWarn[3], Pi.textWarn[4], 'Unsaved INI')
    else
        ImGui.TextColored(Pi.textOk[1], Pi.textOk[2], Pi.textOk[3], Pi.textOk[4], string.format('Saved %s', lastSaveLabel))
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

local function DrawUltimateTopBar()
    DrawUltimateModeBanner()
    ImGui.Separator()
    DrawUltimateIniSettingsRow()
end

local function DrawUltimateBottomBar()
    --- Shrink toolbar buttons when the window is narrow so rows do not clip.
    local toolbarAvail = ImGui.GetContentRegionAvail()
    local uw = uniformButtonWidth
    if toolbarAvail < 920 then uw = 82 end
    if toolbarAvail < 760 then uw = 72 end
    if toolbarAvail < 620 then uw = 64 end

    local function toolbarBreakIfTight(minNeeded)
        if ImGui.GetContentRegionAvail() < minNeeded then
            ImGui.NewLine()
        end
    end

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
        local macro = mq.TLO.Macro
        local Pu = UltimateAssistPalette
        local macroName = SafeTLOCall(function() return macro.Name() end, nil)
        if macroName ~= 'muleassist.mac' then
            return 'STOPPED', {Pu.textDim[1], Pu.textDim[2], Pu.textDim[3], Pu.textDim[4]}
        end
        if SafeTLOCall(function() return macro.Paused() end, false) then
            return 'PAUSED', {0.95, 0.72, 0.35, 1.0}
        end
        return 'RUNNING', {Pu.textOk[1], Pu.textOk[2], Pu.textOk[3], Pu.textOk[4]}
    end

    local Pb = UltimateAssistPalette
    ImGui.TextColored(Pb.textMuted[1], Pb.textMuted[2], Pb.textMuted[3], Pb.textMuted[4], '[Spells]')
    ImGui.SameLine()
    if ImGui.Button((Icons.FA_UPLOAD or '') .. ' MemSpells', uw, 0) then
        if TryBeginAction('memspells') then
            CmdMemMySpells(globals.INIFile)
        end
    end
    ImGui.SameLine()
    if ImGui.Button((Icons.FA_FLOPPY_O or '') .. ' SaveGems', uw, 0) then
        if TryBeginAction('savegems') then
            mq.cmd('/memspells save')
        end
    end
    ImGui.SameLine()
    ImGui.Text('   ')
    ImGui.SameLine()
    toolbarBreakIfTight(340)
    ImGui.TextColored(Pb.textMuted[1], Pb.textMuted[2], Pb.textMuted[3], Pb.textMuted[4], '[Config]')
    ImGui.SameLine()
    if ImGui.Button((Icons.FA_FOLDER_OPEN_O or Icons.FA_FOLDER_OPEN or '') .. ' IniMgr', uw, 0) then
        filedialog.set_file_selector_open(true)
    end
    ImGui.SameLine()
    if ImGui.Button((Icons.FA_USERS or '') .. ' Remote', uw, 0) then
        selectedSection = 'General'
        MauiRuntime.nav.id = 'utility'
        bottomActionMsg = 'Remote: Utility panel'
    end
    ImGui.SameLine()
    local prevAutoMem = autoMemAfterRetune
    autoMemAfterRetune = ImGui.Checkbox('AutoMem##toolbar', autoMemAfterRetune)
    if prevAutoMem ~= autoMemAfterRetune then
        SaveMAUIConfig()
    end
    ImGui.SameLine()
    ImGui.Text('   ')
    ImGui.SameLine()
    toolbarBreakIfTight(360)
    ImGui.TextColored(Pb.textMuted[1], Pb.textMuted[2], Pb.textMuted[3], Pb.textMuted[4], '[Adjust]')
    ImGui.SameLine()
    if ImGui.Button((Icons.FA_ARROW_CIRCLE_O_UP or Icons.FA_ARROW_UP or '') .. ' Retune ↑', uw, 0) then
        if TryBeginAction('upgrades') then
            local changed, checked, updatedGems = AutoRetuneAbilities('upgrade')
            MauiRuntime.nav.id = 'buffs'
            local queued = 0
            if autoMemAfterRetune then
                queued = QueueRetunedGemsForMem(updatedGems, memQueue)
            end
            if autoMemAfterRetune and queued > 0 then
                bottomActionMsg = string.format('Retune Up (best rank): %d/%d updated, queued %d gem mems', changed, checked, queued)
            else
                bottomActionMsg = string.format('Retune Up (best rank): %d/%d entries updated', changed, checked)
            end
        end
    end
    ImGui.SameLine()
    if ImGui.Button((Icons.FA_ARROW_CIRCLE_O_DOWN or Icons.FA_ARROW_DOWN or '') .. ' Retune ↓', uw, 0) then
        if TryBeginAction('downgrades') then
            local changed, checked, updatedGems = AutoRetuneAbilities('downgrade')
            MauiRuntime.nav.id = 'buffs'
            local queued = 0
            if autoMemAfterRetune then
                queued = QueueRetunedGemsForMem(updatedGems, memQueue)
            end
            if autoMemAfterRetune and queued > 0 then
                bottomActionMsg = string.format('Retune Down (lower rank): %d/%d updated, queued %d gem mems', changed, checked, queued)
            else
                bottomActionMsg = string.format('Retune Down (lower rank): %d/%d entries updated', changed, checked)
            end
        end
    end
    ImGui.SameLine()
    if ImGui.Button((Icons.FA_TH or '') .. ' HotBtns', uw, 0) then
        selectedSection = 'General'
        MauiRuntime.nav.id = 'utility'
        bottomActionMsg = 'HotButtons: Utility panel'
    end
    ImGui.SameLine()
    ImGui.Dummy(12, 1)

    --- Second toolbar row (mockup): macro / run controls read cleaner below spell & adjust rows.
    ImGui.NewLine()

    local macroStatus, macroColor = GetMacroStatus()
    ImGui.TextColored(macroColor[1], macroColor[2], macroColor[3], macroColor[4], 'Macro: '..macroStatus)
    ImGui.SameLine()
    if macroStatus == 'RUNNING' then
        if ImGui.Button((Icons.FA_PAUSE or '') .. ' Pause', 84, 0) and TryBeginAction('pause') then
            mq.cmd('/mqp on')
            bottomActionMsg = 'Macro paused'
        end
        ImGui.SameLine()
    elseif macroStatus == 'PAUSED' then
        if ImGui.Button((Icons.FA_PLAY or '') .. ' Resume', 92, 0) and TryBeginAction('resume') then
            mq.cmd('/mqp off')
            bottomActionMsg = 'Macro resumed'
        end
        ImGui.SameLine()
    end
    if macroStatus ~= 'STOPPED' then
        if ImGui.Button((Icons.FA_STOP or '') .. ' End', 76, 0) and TryBeginAction('endmacro') then
            mq.cmd('/end')
            bottomActionMsg = 'Macro ended'
        end
        ImGui.SameLine()
    end

    ImGui.SameLine()
    local preflightWidth = 108
    local startWidth = 120
    local runLabel = '[Run] '
    local runW = ImGui.CalcTextSize(runLabel)
    local sp = 6
    --- Visible gap between START and the window/content edge (previous math omitted [Run] width, pushing the cluster into the border).
    local rightMargin = 32
    local groupW = runW + sp + preflightWidth + sp + startWidth
    local curX = ImGui.GetCursorPosX()
    local availX = ImGui.GetContentRegionAvail()
    if availX < groupW + rightMargin + 24 then
        ImGui.NewLine()
        curX = ImGui.GetCursorPosX()
        availX = ImGui.GetContentRegionAvail()
    end
    if availX < groupW + rightMargin then
        local inner = availX - rightMargin - runW - 2 * sp
        preflightWidth = math.max(84, math.floor(inner * 0.48))
        startWidth = math.max(84, inner - preflightWidth)
        groupW = runW + sp + preflightWidth + sp + startWidth
    end
    local targetX = curX + math.max(0, availX - groupW - rightMargin)
    if bottomActionMsg ~= '' then
        local textW = ImGui.CalcTextSize(bottomActionMsg)
        local msgX = math.max(curX, targetX - textW - 12)
        ImGui.SetCursorPosX(msgX)
        ImGui.TextColored(Pb.textMuted[1], Pb.textMuted[2], Pb.textMuted[3], Pb.textMuted[4], bottomActionMsg)
        ImGui.SameLine()
    end
    ImGui.SetCursorPosX(targetX)
    ImGui.TextColored(Pb.textMuted[1], Pb.textMuted[2], Pb.textMuted[3], Pb.textMuted[4], runLabel)
    ImGui.SameLine()
    if ImGui.Button((Icons.FA_SHIELD or '') .. ' Preflight', preflightWidth, 34) then
        if TryBeginAction('preflight') then
            RunPreflight(false)
        end
    end
    ImGui.SameLine()
    do
        local ms = macroStatus
        local P = UltimateAssistPalette
        if ms == 'RUNNING' then
            ImGui.PushStyleColor(ImGuiCol.Button, P.startBusy[1], P.startBusy[2], P.startBusy[3], P.startBusy[4])
            ImGui.PushStyleColor(ImGuiCol.ButtonHovered, P.startBusyHov[1], P.startBusyHov[2], P.startBusyHov[3], P.startBusyHov[4])
        else
            ImGui.PushStyleColor(ImGuiCol.Button, P.startPrimary[1], P.startPrimary[2], P.startPrimary[3], P.startPrimary[4])
            ImGui.PushStyleColor(ImGuiCol.ButtonHovered, P.startPrimaryHov[1], P.startPrimaryHov[2], P.startPrimaryHov[3], P.startPrimaryHov[4])
        end
        if ImGui.Button((Icons.FA_PLAY_CIRCLE or Icons.FA_PLAY or '') .. ' START', startWidth, 34) then
            if TryBeginAction('start') then
                RunPreflight(true)
            end
        end
        ImGui.PopStyleColor(2)
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
        if ImGui.Button((Icons.FA_ROCKET or Icons.FA_PLAY or '') .. ' Start Anyway', 170, 0) then
            RunStartCommand()
            pendingStartWarnings = nil
            ImGui.CloseCurrentPopup()
        end
        ImGui.SameLine()
        if ImGui.Button((Icons.FA_WRENCH or '') .. ' Fix Now', 130, 0) then
            MauiRuntime.nav.id = 'setup'
            pendingStartWarnings = nil
            ImGui.CloseCurrentPopup()
        end
        ImGui.EndPopup()
    end
end

DrawPanelHeader = function(text)
    local Pu = UltimateAssistPalette
    ImGui.TextColored(Pu.textTitle[1], Pu.textTitle[2], Pu.textTitle[3], Pu.textTitle[4], text)
    ImGui.Separator()
end

--- Readme + mock UIs: wrapped in an IIFE so inner locals do not count against Lua 5.1 main-chunk 200 limit.
local ReadmeUI = (function()

local function DrawCodeSnippet(snippet)
    ImGui.PushStyleColor(ImGuiCol.Text, 0.72, 0.95, 1.00, 1.00)
    ImGui.TextWrapped(snippet)
    ImGui.PopStyleColor()
    ImGui.Separator()
end

local function DrawQuickCopyCommands(idSuffix, title, snippet)
    ImGui.TextColored(0.45, 0.95, 0.55, 1.0, title or 'Quick Copy')
    if ImGui.SmallButton('Copy##' .. tostring(idSuffix or 'cmd')) then
        ImGui.SetClipboardText(snippet or '')
        bottomActionMsg = 'Copied command block to clipboard'
    end
    ImGui.Separator()
    ImGui.PushStyleColor(ImGuiCol.Text, 0.72, 0.95, 1.00, 1.00)
    ImGui.TextWrapped(snippet or '')
    ImGui.PopStyleColor()
    ImGui.Separator()
end

local function ReadmeTextMatches(filterText, candidate)
    local f = tostring(filterText or ''):lower()
    if f == '' then return true end
    return tostring(candidate or ''):lower():find(f, 1, true) ~= nil
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
    ImGui.Button('Retune Up (Best Rank)', 170, 0); ImGui.SameLine()
    ImGui.Button('Retune Down (Lower Rank)', 185, 0); ImGui.SameLine()
    ImGui.Button('AutoMem After Retune', 170, 0)
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
    ImGui.TextColored(0.45, 0.90, 0.98, 1.0, 'New here? Open Start Here first, then run Preflight before Start.')
    ImGui.Text('Jump to:')
    local function JumpButton(label)
        if ImGui.Button(label, 96, 0) then
            readmeJumpToTab = label
        end
    end
    JumpButton('Start Here')
    ImGui.SameLine(); JumpButton('Setup')
    ImGui.SameLine(); JumpButton('Commands')
    ImGui.SameLine(); JumpButton('Glossary')
    ImGui.SameLine(); JumpButton('FAQ')
    ImGui.SameLine(); JumpButton('Tools Guides')
    ImGui.Separator()
    if ImGui.BeginTabBar('##UEA_ReadmeTabs') then
        if ImGui.BeginTabItem('Start Here', nil, readmeJumpToTab == 'Start Here' and ImGuiTabItemFlags.SetSelected or 0) then
            if readmeJumpToTab == 'Start Here' then readmeJumpToTab = nil end
            ImGui.TextWrapped('5-minute safe startup for new users (level 80 baseline):')
            ImGui.Spacing()
            ImGui.BulletText('1) In UI tab, click Quick Setup: Solo, Group, or Raid.')
            ImGui.BulletText('2) In Step 1, enable Combat + Buffs + Heals. Enable Pet only if your class uses pet.')
            ImGui.BulletText('3) In Step 2/3, keep recommended values: ChaseDistance 20-35, MedStart 20-35, CastRetries 2-4.')
            ImGui.BulletText('4) Click Save Config, then click Preflight.')
            ImGui.BulletText('5) Fix any FAIL/WARN items, then click Start.')
            ImGui.Spacing()
            ImGui.TextColored(0.45, 0.95, 0.55, 1.0, 'Safe defaults for most groups:')
            DrawCodeSnippet('Modules: Combat=On, Buffs=On, Heals=On, Cures=On, Pet=Off (unless pet class)\nChaseAssist=On (Group/Raid) or ReturnToCamp=On (Solo)\nMedOn=On, MedStart=30, SitToMed=0\nCastRetries=3')
            ImGui.TextColored(1.0, 0.65, 0.2, 1.0, 'Common mistakes to avoid:')
            ImGui.BulletText('Enabling both ChaseAssist and ReturnToCamp at the same time.')
            ImGui.BulletText('Setting MedStart too low and starving mana/endurance.')
            ImGui.BulletText('Leaving modules enabled with size=0 (DPSSize, BuffsSize, HealsSize).')
            ImGui.BulletText('Starting without syncing/updating spells (MemSpells, SaveGems, Upgrades/Downgrades).')
            ImGui.Spacing()
            ImGui.TextWrapped('Quick commands:')
            DrawCodeSnippet('/lua run maui\n/lua stop maui\n/mqoverlay resume')
            ImGui.EndTabItem()
        end

        if ImGui.BeginTabItem('Overview', nil, readmeJumpToTab == 'Overview' and ImGuiTabItemFlags.SetSelected or 0) then
            if readmeJumpToTab == 'Overview' then readmeJumpToTab = nil end
            DrawMauiDocsOverviewGuide()
            ImGui.EndTabItem()
        end

        if ImGui.BeginTabItem('Setup', nil, readmeJumpToTab == 'Setup' and ImGuiTabItemFlags.SetSelected or 0) then
            if readmeJumpToTab == 'Setup' then readmeJumpToTab = nil end
            ImGui.TextColored(0.45, 0.95, 0.55, 1.0, 'Quick install checklist')
            if ImGui.BeginTable('##UEA_SetupChecklist', 3, ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg + ImGuiTableFlags.SizingStretchProp) then
                ImGui.TableSetupColumn('Step')
                ImGui.TableSetupColumn('Action')
                ImGui.TableSetupColumn('Why It Matters')
                ImGui.TableHeadersRow()
                local rows = {
                    {'1', 'Use matched MQ build + plugins', 'Prevents command/runtime mismatch.'},
                    {'2', 'Put macro in Macros\\\\ and INIs in Config\\\\', 'Ensures files load in expected paths.'},
                    {'3', 'Start with character profile', 'Avoids class/default overwriting character tuning.'},
                    {'4', 'Use INI precedence: Character > Class > Default', 'Explains which value wins when duplicated.'},
                }
                for _, row in ipairs(rows) do
                    ImGui.TableNextRow()
                    ImGui.TableSetColumnIndex(0); ImGui.Text(row[1])
                    ImGui.TableSetColumnIndex(1); ImGui.TextWrapped(row[2])
                    ImGui.TableSetColumnIndex(2); ImGui.TextWrapped(row[3])
                end
                ImGui.EndTable()
            end
            ImGui.TextColored(1.0, 0.65, 0.2, 1.0, 'Warning: if nothing fires, check Role/MainAssist and module toggles first (HealsOn/BuffsOn/DPSOn).')
            ImGui.Separator()
            DrawCodeSnippet('/plugin mq2cast load\n/plugin mq2melee load\n/plugin mq2moveutils load\n/plugin mq2nav load')
            DrawCodeSnippet('/mac AdvancedSuite assist Tankname\n/mqp on\n/mqp off\n/end')
            ImGui.EndTabItem()
        end

        if ImGui.BeginTabItem('Commands', nil, readmeJumpToTab == 'Commands' and ImGuiTabItemFlags.SetSelected or 0) then
            if readmeJumpToTab == 'Commands' then readmeJumpToTab = nil end
            ImGui.TextColored(0.45, 0.95, 0.55, 1.0, 'High-use command reference')
            if ImGui.BeginTable('##UEA_CommandsTable', 2, ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg + ImGuiTableFlags.SizingStretchProp) then
                ImGui.TableSetupColumn('Command')
                ImGui.TableSetupColumn('Use')
                ImGui.TableHeadersRow()
                local rows = {
                    {'/asuite help', 'Show macro command help.'},
                    {'/asuite on | /asuite off', 'Master enable/disable.'},
                    {'/asuite reload', 'Reload macro settings/INI state.'},
                    {'/asuite role <assist|tank|manual|puller>', 'Change macro role behavior.'},
                    {'/asuite ma <name>', 'Set/update main assist target.'},
                    {'/asuite burn on|off|now', 'Burn control for planned DPS windows.'},
                    {'/asuite pause <module> | /asuite resume <module>', 'Pause/resume modules without full stop.'},
                    {'/bca //cmd  /bct Toon //cmd', 'Broadcast commands for multibox sync.'},
                }
                for _, row in ipairs(rows) do
                    ImGui.TableNextRow()
                    ImGui.TableSetColumnIndex(0); ImGui.Text(row[1])
                    ImGui.TableSetColumnIndex(1); ImGui.TextWrapped(row[2])
                end
                ImGui.EndTable()
            end
            ImGui.TextColored(0.72, 0.95, 1.00, 1.00, 'Related MQ2 commands: /cast, /memspell, /stick, /moveto, /nav, /melee, /target id, /ini')
            ImGui.Separator()
            DrawCodeSnippet('/bca //asuite burn on\n/bct Cleric //casting "Divine Arbitration"')
            ImGui.EndTabItem()
        end

        if ImGui.BeginTabItem('INI Guide', nil, readmeJumpToTab == 'INI Guide' and ImGuiTabItemFlags.SetSelected or 0) then
            if readmeJumpToTab == 'INI Guide' then readmeJumpToTab = nil end
            ImGui.TextColored(0.45, 0.95, 0.55, 1.0, 'INI map by section')
            if ImGui.BeginTable('##UEA_IniMapTable', 2, ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg + ImGuiTableFlags.SizingStretchProp) then
                ImGui.TableSetupColumn('Section')
                ImGui.TableSetupColumn('Primary Purpose')
                ImGui.TableHeadersRow()
                local rows = {
                    {'General', 'Core behavior, movement, role, and recovery settings.'},
                    {'DPS', 'Offensive abilities and cast priority.'},
                    {'Heals / Cures', 'Survival, triage, and cure logic.'},
                    {'Buffs', 'Self/group maintenance and long-duration spells.'},
                    {'Pet', 'Pet spell/combat behavior for pet classes.'},
                    {'Utility', 'Loot/rez/group helpers and non-combat flow.'},
                }
                for _, row in ipairs(rows) do
                    ImGui.TableNextRow()
                    ImGui.TableSetColumnIndex(0); ImGui.Text(row[1])
                    ImGui.TableSetColumnIndex(1); ImGui.TextWrapped(row[2])
                end
                ImGui.EndTable()
            end
            ImGui.TextColored(0.72, 0.95, 1.00, 1.00, 'Key INI patterns:')
            DrawCodeSnippet('[General]\nRole=assist\nMainAssist=Tankname\nEnabled=1\nAssistRange=100\nCampRadius=40\nChaseAssist=0\nLoopDelayMS=50')
            DrawCodeSnippet('[DPS]\nDPSOn=1\nDPSSize=2\nDPS1=Riotous Servant|99|Cond:${Target.Named}\nDPS2=Chaotic Fire|40|Cond:${Me.PctMana}>45')
            DrawCodeSnippet('[Heals]\nHealsOn=1\nHealSize=3\nHeal1=Complete Heal|35|Cond:${Me.PctHPs}<35\nHeal2=Remedy|55|Cond:${Group.MainTank.PctHPs}<55')
            ImGui.TextColored(0.72, 0.95, 1.00, 1.00, 'INI read/write examples:')
            DrawCodeSnippet('${Ini[Config\\\\AdvancedSuite_MyServer_MyChar.ini,General,AssistRange]}\n/ini \"Config\\\\AdvancedSuite_MyServer_MyChar.ini\" \"General\" \"AssistRange\" \"100\"')
            ImGui.EndTabItem()
        end

        if ImGui.BeginTabItem('Glossary', nil, readmeJumpToTab == 'Glossary' and ImGuiTabItemFlags.SetSelected or 0) then
            if readmeJumpToTab == 'Glossary' then readmeJumpToTab = nil end
            ImGui.TextWrapped('Search confusing settings, safe ranges, and common risk notes.')
            readmeGlossaryFilter, _ = ImGui.InputText('Search##UEA_ReadmeGlossary', readmeGlossaryFilter)
            if ImGui.BeginTable('##UEA_GlossaryTable', 5, ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg + ImGuiTableFlags.SizingStretchProp) then
                ImGui.TableSetupColumn('Setting')
                ImGui.TableSetupColumn('Safe Range')
                ImGui.TableSetupColumn('What It Does')
                ImGui.TableSetupColumn('Risk If Wrong')
                ImGui.TableSetupColumn('Level')
                ImGui.TableHeadersRow()
                local rows = {
                    {'ChaseDistance', '20-35', 'Distance from assist target while chasing.', 'Too high can overpull/position badly.', 'SAFE'},
                    {'MedStart', '20-35', 'When to begin medding at low mana/end.', 'Too low can cause starvation/deaths.', 'SAFE'},
                    {'CastRetries', '2-4', 'Retry failed casts this many times.', 'Too high can create cast loops.', 'SAFE'},
                    {'GroupWatchOn', '0 unless needed', 'Advanced group monitoring logic.', 'Unexpected behavior if enabled blindly.', 'ADVANCED'},
                    {'CampRadius', '25-40', 'How far from camp MA can drift.', 'Too large can break camp discipline.', 'ADVANCED'},
                    {'CampRadiusExceed', '300-600', 'Distance threshold before emergency return behavior.', 'Too small causes constant corrections.', 'ADVANCED'},
                    {'BuffWhileChasing', '1 for most', 'Allows buffing while moving/chasing.', 'Off can delay maintenance buffs.', 'SAFE'},
                    {'DanNetDelay', '10-30', 'Delay between DanNet checks/actions.', 'Too low can spam network updates.', 'RISKY'},
                }
                for _, row in ipairs(rows) do
                    local haystack = table.concat(row, ' ')
                    if ReadmeTextMatches(readmeGlossaryFilter, haystack) then
                        ImGui.TableNextRow()
                        ImGui.TableSetColumnIndex(0); ImGui.Text(row[1])
                        ImGui.TableSetColumnIndex(1); ImGui.Text(row[2])
                        ImGui.TableSetColumnIndex(2); ImGui.TextWrapped(row[3])
                        ImGui.TableSetColumnIndex(3); ImGui.TextWrapped(row[4])
                        ImGui.TableSetColumnIndex(4)
                        if row[5] == 'SAFE' then
                            ImGui.TextColored(0.45, 0.95, 0.55, 1.0, 'SAFE')
                        elseif row[5] == 'ADVANCED' then
                            ImGui.TextColored(0.98, 0.85, 0.35, 1.0, 'ADVANCED')
                        else
                            ImGui.TextColored(1.0, 0.45, 0.25, 1.0, 'RISKY')
                        end
                    end
                end
                ImGui.EndTable()
            end
            ImGui.EndTabItem()
        end

        if ImGui.BeginTabItem('Conditions', nil, readmeJumpToTab == 'Conditions' and ImGuiTabItemFlags.SetSelected or 0) then
            if readmeJumpToTab == 'Conditions' then readmeJumpToTab = nil end
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

        if ImGui.BeginTabItem('Features', nil, readmeJumpToTab == 'Features' and ImGuiTabItemFlags.SetSelected or 0) then
            if readmeJumpToTab == 'Features' then readmeJumpToTab = nil end
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

        if ImGui.BeginTabItem('Examples', nil, readmeJumpToTab == 'Examples' and ImGuiTabItemFlags.SetSelected or 0) then
            if readmeJumpToTab == 'Examples' then readmeJumpToTab = nil end
            DrawCodeSnippet('Sub CombatPulse\n  /if (${Target.ID} && ${Target.Distance}<100) /attack on\n  /if (${Me.PctHPs}<35) /casting "Complete Heal"\n  /if (${Target.Named} && ${Me.PctMana}>40) /alt activate 15073\n/return')
            DrawCodeSnippet('Sub HealPriority\n  /if (${Me.PctHPs}<35) /casting "Complete Heal"\n  /if (${Group.MainTank.PctHPs}<55) /casting "Remedy"\n  /if (${Group.Injured[60]}>=3) /casting "Word of Reformation"\n/return')
            DrawCodeSnippet('Sub BuffCheck\n  /if (!${Me.Buff[Shield of Destiny].ID}) /casting "Shield of Destiny"\n  /if (${Pet.ID} && !${Pet.Buff[Burnout].ID}) /casting "Burnout"\n/return')
            DrawCodeSnippet('Sub PullLogic\n  /if (${SpawnCount[npc radius 200 los]}>0) /target npc radius 200\n  /if (${Target.ID}) /casting "Snare of Stone"\n/return')
            DrawCodeSnippet('Sub Holyshit\n  /if (${Me.PctHPs}<30) /alt activate 15073\n  /if (${SpawnCount[npc radius 30 aggro]}>3) /bcaa //alt activate 202\n/return')
            ImGui.EndTabItem()
        end

        if ImGui.BeginTabItem('Advanced', nil, readmeJumpToTab == 'Advanced' and ImGuiTabItemFlags.SetSelected or 0) then
            if readmeJumpToTab == 'Advanced' then readmeJumpToTab = nil end
            ImGui.BulletText('Use short, pulse-based subroutines (DoHeals, DoDPS, DoBuffs, DoPull).')
            ImGui.BulletText('Keep expensive Spawn queries bounded by radius, LOS, and noalert filters.')
            ImGui.BulletText('Tune LoopDelayMS and module toggles for low CPU overhead.')
            ImGui.BulletText('Debug with /echo, /mqlog, and explicit branch traces.')
            ImGui.BulletText('Use role-specific profile INIs (assist/tank/puller/manual).')
            ImGui.BulletText('Prefer plugin delegation: MQ2Cast for execution, MQ2Melee for melee micro.')
            ImGui.EndTabItem()
        end

        if ImGui.BeginTabItem('FAQ', nil, readmeJumpToTab == 'FAQ' and ImGuiTabItemFlags.SetSelected or 0) then
            if readmeJumpToTab == 'FAQ' then readmeJumpToTab = nil end
            if ImGui.CollapsingHeader('Why am I not casting?', ImGuiTreeNodeFlags.DefaultOpen) then
                ImGui.BulletText('Verify gems are memmed and spell names match current client rank.')
                ImGui.BulletText('Check mana threshold and condition guards.')
                ImGui.BulletText('Use Upgrades?/Downgrades? + AutoMem when needed.')
            end
            if ImGui.CollapsingHeader('Why is movement weird?', ImGuiTreeNodeFlags.DefaultOpen) then
                ImGui.BulletText('Stuck nav: /nav stop, /stick off, verify mesh.')
                ImGui.BulletText('Do not run ChaseAssist and ReturnToCamp together unless intentional.')
                ImGui.BulletText('Keep ChaseDistance in safe range (20-35).')
            end
            if ImGui.CollapsingHeader('Why are settings ignored?', ImGuiTreeNodeFlags.DefaultOpen) then
                ImGui.BulletText('Confirm active INI path and click Reload.')
                ImGui.BulletText('Run /asuite reload after direct INI edits.')
                ImGui.BulletText('Remember precedence: Character > Class > Default.')
            end
            if ImGui.CollapsingHeader('Performance / FPS issues', ImGuiTreeNodeFlags.DefaultOpen) then
                ImGui.BulletText('Raise LoopDelayMS and reduce wide SpawnCount queries.')
                ImGui.BulletText('Disable unused modules in Setup.')
            end
            ImGui.EndTabItem()
        end

        if ImGui.BeginTabItem('Tools Guides', nil, readmeJumpToTab == 'Tools Guides' and ImGuiTabItemFlags.SetSelected or 0) then
            if readmeJumpToTab == 'Tools Guides' then readmeJumpToTab = nil end
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
            ImGui.TextColored(0.45, 0.95, 0.55, 1.0, 'What it does')
            ImGui.TextWrapped('Cross-character inventory visibility + assignment execution + banking helpers. Best used after peers are connected.')
            ImGui.Separator()
            ImGui.TextColored(0.72, 0.95, 1.00, 1.00, 'First run (safe noob flow)')
            ImGui.BulletText('1) /lua run ezinventory')
            ImGui.BulletText('2) /ezinventory_ui to open window.')
            ImGui.BulletText('3) Pick server and peer from top selectors.')
            ImGui.BulletText('4) Verify your own inventory loads first, then peers.')
            ImGui.BulletText('5) Start in Equipped/Bags tabs before Assignment/Banking.')
            ImGui.BulletText('6) Run /ezinvassign show before /ezinvassign execute.')
            ImGui.Separator()
            ImGui.TextColored(1.0, 0.65, 0.2, 1.0, 'Safety notes')
            ImGui.BulletText('Do not run execute/auto-bank blind. Confirm selected server + peer first.')
            ImGui.BulletText('If data feels heavy or slow, switch stats mode to minimal/selective.')
            ImGui.BulletText('Use execute only after reviewing assignment list output.')
            ImGui.Separator()
            ImGui.TextColored(0.72, 0.95, 1.00, 1.00, 'Commands')
            DrawQuickCopyCommands('ezinventory_cmds', 'Quick Copy Commands', '/ezinventory_help\n/ezinventory_ui\n/ezinventory_stats_mode minimal|selective|full\n/ezinventory_toggle_basic\n/ezinventory_toggle_detailed\n/ezinvbank\n/ezinvassign show\n/ezinvassign execute\n/ezinventory_cmd <peer> <command> [args]')
            ImGui.TextColored(0.72, 0.95, 1.00, 1.00, 'Config / data files')
            DrawCodeSnippet('Config/EZInventory/<server>/<character>.lua')
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
            ImGui.TextColored(0.45, 0.95, 0.55, 1.0, 'What it does')
            ImGui.TextWrapped('Tracks named spawn queries per zone and shows active matches with coordinates in a lightweight overlay.')
            ImGui.Separator()
            ImGui.TextColored(0.72, 0.95, 1.00, 1.00, 'First run (safe noob flow)')
            ImGui.BulletText('1) /lua run spawnwatch')
            ImGui.BulletText('2) /sm_edit and add a single query for your current zone.')
            ImGui.BulletText('3) /showspawns to open viewer and validate results.')
            ImGui.BulletText('4) /sm_lock if you want a fixed-position overlay.')
            ImGui.BulletText('5) Add more queries only after the first one works.')
            ImGui.Separator()
            ImGui.TextColored(1.0, 0.65, 0.2, 1.0, 'Safety notes')
            ImGui.BulletText('Broad queries can spam the list. Start specific (named/rare).')
            ImGui.BulletText('It only tracks the current zone list for display, so zone changes require matching entries.')
            ImGui.Separator()
            ImGui.TextColored(0.72, 0.95, 1.00, 1.00, 'Commands')
            DrawQuickCopyCommands('spawnwatch_cmds', 'Quick Copy Commands', '/showspawns\n/sm_edit\n/sm_lock')
            ImGui.TextColored(0.72, 0.95, 1.00, 1.00, 'Data file')
            DrawCodeSnippet('Lua/npc_watchlist_by_zone.json')
            ImGui.EndTabItem()
        end

        if ImGui.BeginTabItem('BuffBot') then
            ImGui.TextColored(0.45, 0.95, 0.55, 1.0, 'What it does')
            ImGui.TextWrapped('Runs a buff service character with tell/say triggers, optional paid account balances, friend/guild filtering, rez/summon/port support by class.')
            ImGui.Separator()
            ImGui.TextColored(0.72, 0.95, 1.00, 1.00, 'Supported classes')
            ImGui.TextWrapped('Enchanter, Magician, Ranger, Shaman, Beastlord, Cleric, Druid, Paladin, Necromancer, Shadow Knight, Wizard.')
            ImGui.Separator()
            ImGui.TextColored(0.72, 0.95, 1.00, 1.00, 'First run (safe noob flow)')
            ImGui.BulletText('1) /lua run buffbot')
            ImGui.BulletText('2) /bb gui and verify class loaded correctly.')
            ImGui.BulletText('3) Set med thresholds first, leave Account/Friend/Guild modes off initially.')
            ImGui.BulletText('4) Test one command request (hail/buff/ports/rez/summon depending on class).')
            ImGui.BulletText('5) Enable advertise only after validation.')
            ImGui.Separator()
            ImGui.TextColored(1.0, 0.65, 0.2, 1.0, 'Safety notes')
            ImGui.BulletText('AccountMode/FriendMode/GuildMode change who can trigger service. Enable one at a time.')
            ImGui.BulletText('Setup button options that overwrite files should be used carefully.')
            ImGui.BulletText('If behavior is weird after update, rebuild the character settings file from GUI.')
            ImGui.Separator()
            ImGui.TextColored(0.72, 0.95, 1.00, 1.00, 'Commands')
            DrawQuickCopyCommands('buffbot_cmds', 'Quick Copy Commands', '/bb\n/bb gui\n/bb quit\n/bb buff <friendName>\n/bb balance add|del|get <friendName>\n/bb friend add|del|get <friendName>\n/bb guild add|del|get <guildName>')
            ImGui.TextColored(0.72, 0.95, 1.00, 1.00, 'Config / data files')
            DrawCodeSnippet('Config/BuffBot/Settings/BuffBot_<character>.ini\nConfig/BuffBot/Accounts.ini\nConfig/BuffBot/Friends.ini\nConfig/BuffBot/Guilds.ini')
            ImGui.EndTabItem()
        end

        if ImGui.BeginTabItem('Grouper') then
            ImGui.TextColored(0.45, 0.95, 0.55, 1.0, 'What it does')
            ImGui.TextWrapped('Broadcast control pad for your team: camp/chase/follow, movement formations, pause/resume, burn toggles, and utility actions.')
            ImGui.Separator()
            ImGui.TextColored(0.72, 0.95, 1.00, 1.00, 'First run (safe noob flow)')
            ImGui.BulletText('1) /lua run grouper')
            ImGui.BulletText('2) Test only pause/resume first.')
            ImGui.BulletText('3) Test followon/followoff.')
            ImGui.BulletText('4) Test campon/campoff.')
            ImGui.BulletText('5) Add invis/chase after base movement is stable.')
            ImGui.Separator()
            ImGui.TextColored(1.0, 0.45, 0.25, 1.0, 'Risk warning')
            ImGui.BulletText('Setup button is explicitly marked CAUTION and can change multiple settings/plugins.')
            ImGui.BulletText('Use it only if you understand the side effects on your team environment.')
            ImGui.Separator()
            ImGui.TextColored(0.72, 0.95, 1.00, 1.00, 'High-use commands')
            DrawQuickCopyCommands('grouper_cmds', 'Quick Copy Commands', '/grouper pause\n/grouper resume\n/grouper followon\n/grouper followoff\n/grouper campon\n/grouper campoff\n/grouper chaseon\n/grouper invis\n/grouper hide\n/grouper show\n/grouper quit')
            ImGui.TextColored(0.72, 0.95, 1.00, 1.00, 'Config file')
            DrawCodeSnippet('Config/Grouper_<character>_<server>.ini')
            ImGui.EndTabItem()
        end

        if ImGui.BeginTabItem('HunterHud') then
            ImGui.TextColored(0.45, 0.95, 0.55, 1.0, 'What it does')
            ImGui.TextWrapped('Tracks Hunter achievement mobs for current zone and helps navigate to known spawn targets.')
            ImGui.Separator()
            ImGui.TextColored(0.72, 0.95, 1.00, 1.00, 'First run (safe noob flow)')
            ImGui.BulletText('1) /lua run hunterhud in a hunter-supported zone.')
            ImGui.BulletText('2) Use /hh to show/hide quickly while fighting.')
            ImGui.BulletText('3) Right-click the window for menu options: Minimize, Spawned Only, Missing Hunts.')
            ImGui.BulletText('4) Use listed targets to navigate and clear missing entries.')
            ImGui.Separator()
            ImGui.TextColored(0.72, 0.95, 1.00, 1.00, 'Commands')
            DrawQuickCopyCommands('hunterhud_cmds', 'Quick Copy Commands', '/hh\n/hh stop')
            ImGui.TextColored(1.0, 0.65, 0.2, 1.0, 'If zone changed and data looks stale, give it a moment to auto-refresh.')
            ImGui.EndTabItem()
        end

        if ImGui.BeginTabItem('LEM') then
            ImGui.TextColored(0.45, 0.95, 0.55, 1.0, 'What it does')
            ImGui.TextWrapped('Lua Event Manager: create text-trigger and condition-trigger scripts, enable/disable per character, and broadcast toggles.')
            ImGui.Separator()
            ImGui.TextColored(0.72, 0.95, 1.00, 1.00, 'First run (safe noob flow)')
            ImGui.BulletText('1) /lua run lem safemode (recommended first launch).')
            ImGui.BulletText('2) /lem show and inspect existing events/conditions.')
            ImGui.BulletText('3) Add one simple event and keep it disabled until reviewed.')
            ImGui.BulletText('4) Enable that single event only, test, then expand.')
            ImGui.BulletText('5) Tune frequency after stability (default is safe).')
            ImGui.Separator()
            ImGui.TextColored(1.0, 0.65, 0.2, 1.0, 'Safety notes')
            ImGui.BulletText('Bad event code can break startup loops. Safemode prevents auto-enable at launch.')
            ImGui.BulletText('Reload currently restarts LEM; save first.')
            ImGui.BulletText('Use per-character enable states to stage rollout.')
            ImGui.Separator()
            ImGui.TextColored(0.72, 0.95, 1.00, 1.00, 'Commands')
            DrawQuickCopyCommands('lem_cmds', 'Quick Copy Commands', '/lem help\n/lem show\n/lem hide\n/lem reload\n/lem event <name> on|off\n/lem cond <name> on|off\n/mlem <same as /lem>')
            ImGui.TextColored(0.72, 0.95, 1.00, 1.00, 'Config / data files')
            DrawCodeSnippet('Lua/lem/settings.lua\nLua/lem/characters/<character>.lua\nLua/lem/events/*.lua\nLua/lem/conditions/*.lua')
            ImGui.EndTabItem()
        end

        if ImGui.BeginTabItem('LuaConsole') then
            ImGui.TextColored(0.45, 0.95, 0.55, 1.0, 'What it does')
            ImGui.TextWrapped('In-game Lua scratchpad: edit, run, and inspect output quickly without leaving EQ.')
            ImGui.Separator()
            ImGui.TextColored(0.72, 0.95, 1.00, 1.00, 'First run (safe noob flow)')
            ImGui.BulletText('1) /lua run luaconsole')
            ImGui.BulletText('2) Enter a tiny test script: print(\"hello\")')
            ImGui.BulletText('3) Click Play or press Ctrl+Enter.')
            ImGui.BulletText('4) Use Clear Script / Clear Console while iterating.')
            ImGui.BulletText('5) Toggle timestamps if you need timing context.')
            ImGui.Separator()
            ImGui.TextColored(1.0, 0.65, 0.2, 1.0, 'Safety notes')
            ImGui.BulletText('Scripts run immediately in-process. Avoid risky loops while multiboxing.')
            ImGui.BulletText('Use small snippets first, then scale up.')
            ImGui.Separator()
            ImGui.TextColored(0.72, 0.95, 1.00, 1.00, 'Commands / controls')
            DrawQuickCopyCommands('luaconsole_cmds', 'Quick Copy Commands', '/lc\n/lua run luaconsole')
            DrawCodeSnippet('Play button or Ctrl+Enter = execute\nStop button = stop coroutine')
            ImGui.TextColored(0.72, 0.95, 1.00, 1.00, 'Saved editor state')
            DrawCodeSnippet('Config/luaconsole_settings.lua')
            ImGui.EndTabItem()
        end

        if ImGui.BeginTabItem('ConditionBuilder') then
            ImGui.TextColored(0.45, 0.95, 0.55, 1.0, 'What it does')
            ImGui.TextWrapped('Builds MuleAssist condition strings with a guided UI, tests result live, and optionally writes directly to your INI condition key.')
            ImGui.Separator()
            ImGui.TextColored(0.72, 0.95, 1.00, 1.00, 'First run (safe noob flow)')
            ImGui.BulletText('1) /lua run condition_builder')
            ImGui.BulletText('2) Pick a base TLO + operator + value.')
            ImGui.BulletText('3) Click Add to Condition.')
            ImGui.BulletText('4) Click Test Condition to validate true/false.')
            ImGui.BulletText('5) Copy to clipboard or Apply to MAUI INI slot.')
            ImGui.Separator()
            ImGui.TextColored(1.0, 0.65, 0.2, 1.0, 'Safety notes')
            ImGui.BulletText('Always test before applying to a live Cond key.')
            ImGui.BulletText('If string-based comparisons fail, use .Equal[] or .Find[] operators.')
            ImGui.BulletText('Use Raw Macro value type for ${...} expressions to avoid quotes.')
            ImGui.Separator()
            DrawQuickCopyCommands('condition_builder_cmds', 'Quick Copy Commands', '/lua run condition_builder\n/cb show\n/cb hide\n/cb clear\n/cb quit')
            ImGui.EndTabItem()
        end

        if ImGui.BeginTabItem('ExprEvaluator') then
            ImGui.TextColored(0.45, 0.95, 0.55, 1.0, 'What it does')
            ImGui.TextWrapped('Evaluates Lua and MQ TLO expressions safely before you use them in conditions, aliases, or helper scripts. Shows value, Lua type, MQ userdata type, and keeps recent history.')
            ImGui.Separator()
            ImGui.TextColored(0.72, 0.95, 1.00, 1.00, 'First run (safe noob flow)')
            ImGui.BulletText('1) /lua run expression_evaluator')
            ImGui.BulletText('2) Keep mode on Expression (auto return).')
            ImGui.BulletText('3) Try preset: My Name or HP %.')
            ImGui.BulletText('4) Click Evaluate and verify Value + Type.')
            ImGui.BulletText('5) Copy Expr or Copy Result into your notes/INI editing workflow.')
            ImGui.Separator()
            ImGui.TextColored(1.0, 0.65, 0.2, 1.0, 'Safety notes')
            ImGui.BulletText('Use this to validate pieces first, then move confirmed logic into Condition Builder.')
            ImGui.BulletText('mq.TLO is case-sensitive. mq.tlo will fail.')
            ImGui.BulletText('Chunk mode is advanced: include return statements when you want output values.')
            ImGui.Separator()
            DrawQuickCopyCommands('expr_eval_cmds', 'Quick Copy Commands', '/lua run expression_evaluator\n/ee show\n/ee hide\n/ee eval mq.TLO.Me.CleanName()\n/ee clear\n/ee quit')
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

return { DrawReadmeTab = DrawReadmeTab }
end)()

local function DrawField(sectionName, key)
    if type(globals.Config) ~= 'table' then
        globals.Config = {}
    end
    local schemaSection = globals.Schema[sectionName]
    if not schemaSection or not schemaSection.Properties or not schemaSection.Properties[key] then
        return
    end
    if not globals.Config[sectionName] then
        globals.Config[sectionName] = {}
    end
    DrawProperty(sectionName, key, schemaSection.Properties[key])
end

--- Slider + compact input for General numeric keys, with recommended range hint (Setup steps 2–3).
local function DrawFieldSliderGeneral(key, vmin, vmax, recLo, recHi)
    local prop = globals.Schema.General and globals.Schema.General.Properties and globals.Schema.General.Properties[key]
    if not prop or prop.Type ~= 'NUMBER' then
        DrawField('General', key)
        return
    end
    EnsureConfigSection('General')
    local v = tonumber(globals.Config.General[key]) or 0
    ImGui.TextColored(1, 1, 0.35, 1, key .. ': ')
    ImGui.SameLine()
    utils.HelpMarker(prop.Tooltip or '')
    ImGui.SameLine()
    -- Size slider from remaining line width (do not use GetWindowWidth — Ultimate page column is a child).
    local inputW = 76
    local gap = 8
    local avail = ImGui.GetContentRegionAvail()
    local sliderW = math.max(48, avail - inputW - gap)
    ImGui.PushItemWidth(sliderW)
    local vf = v * 1.0
    vf = ImGui.SliderFloat('##g_sl_' .. key, vf, vmin * 1.0, vmax * 1.0, '%.0f')
    ImGui.PopItemWidth()
    local nv = math.floor(vf + 0.5)
    if nv < vmin then nv = vmin end
    if nv > vmax then nv = vmax end
    ImGui.SameLine(0, gap)
    ImGui.SetNextItemWidth(inputW)
    nv = ImGui.InputInt('##g_in_' .. key, nv)
    if nv < vmin then nv = vmin end
    if nv > vmax then nv = vmax end
    globals.Config.General[key] = nv
    ImGui.NewLine()
    ImGui.TextColored(0.55, 0.58, 0.72, 1, string.format('rec %d–%d · full range %d–%d', recLo, recHi, vmin, vmax))
end

EnsureConfigSection = function(sectionName)
    if type(globals.Config) ~= 'table' then
        globals.Config = {}
    end
    if not globals.Config[sectionName] then
        globals.Config[sectionName] = {}
    end
    return globals.Config[sectionName]
end

IsNullOrEmpty = function(value)
    if value == nil then return true end
    if type(value) == 'string' then
        local trimmed = value:gsub('^%s+', ''):gsub('%s+$', '')
        return trimmed == '' or trimmed:upper() == 'NULL'
    end
    return false
end

ParseToggleValue = function(value)
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

IsSectionEnabled = function(sectionName)
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
        -- INI keys are Buffs1, Heals1, Cures1 (must match LIST property name — not Buff1/Heal1).
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
    -- Some level templates are intentionally minimal. Backfill from the richest available class template.
    local richTemplatePath, _, richScore = FindRichClassTemplateFile(levelNow, classShort, presetUpper)
    if richTemplatePath and utils.FileExists(richTemplatePath) then
        local currentScore = CountConfigSections(globals.Config)
        if richScore > currentScore then
            local richCfg = LIP.load(richTemplatePath, false)
            MergeMissingConfig(globals.Config, richCfg)
        end
    end
    -- Preserve existing sections/keys not present in the selected template.
    MergeMissingConfigFromExisting(globals.Config)
    ApplyModeDeltas(globals.Config)
    local inferredSizes, autoDisabled = NormalizeEnabledModuleSizes(globals.Config)

    -- Build [MySpells] Gem1.. from DPS/Buffs/Heals/etc. (lua/maui/uea_presets.lua).
    local mySpellsGemCount = 0
    local mySpellsNote = ''
    do
        local okPack, uea = pcall(require, 'maui.uea_presets')
        if okPack and type(uea) == 'table' and uea.rebuildMySpellsGems then
            mySpellsGemCount = uea.rebuildMySpellsGems({
                globals = globals,
                mq = mq,
                utils = utils,
                SafeTLOCall = SafeTLOCall,
            }) or 0
            if mySpellsGemCount > 0 then
                mySpellsNote = string.format(' [MySpells: %d gem(s) from spell lines]', mySpellsGemCount)
            else
                mySpellsNote = ' [MySpells: 0 spells — lines may be discs/items or not Spell()]'
            end
        elseif not okPack then
            print(('\at[MAUI]\ax \armaui.uea_presets load failed:\ax %s'):format(tostring(uea)))
        end
    end

    Save()
    globals.INIFileContents = utils.ReadRawINIFile()
    if mySpellsGemCount > 0 then
        CmdMemMySpells(globals.INIFile)
    end
    if templatePath then
        local sourceKind = templatePath:find('/KAHybrid/', 1, true) and 'KAHybrid' or (templatePath:find('/Presets/', 1, true) and 'Preset' or 'Class')
        local fromLabel = string.format('L%d %s %s', tonumber(bucket or levelNow) or levelNow, classShort, sourceKind)
        local normalizeNote = ''
        if inferredSizes > 0 or autoDisabled > 0 then
            normalizeNote = string.format(' [normalized sizes: +%d inferred, %d auto-disabled]', inferredSizes, autoDisabled)
        end
        if switchedToCharINI then
            bottomActionMsg = string.format('Preset applied: %s from %s (switched to %s)%s%s', presetName, fromLabel, tostring(globals.INIFile), normalizeNote, mySpellsNote)
        else
            bottomActionMsg = string.format('Preset applied: %s from %s%s%s', presetName, fromLabel, normalizeNote, mySpellsNote)
        end
    else
        bottomActionMsg = string.format('Preset applied: %s (fallback baseline; no template found)%s%s', presetName, ((inferredSizes > 0 or autoDisabled > 0) and string.format(' [normalized sizes: +%d inferred, %d auto-disabled]', inferredSizes, autoDisabled) or ''), mySpellsNote)
    end
    MauiRuntime.quickProfile = tostring(presetName or 'Group')
end

local function DrawSetupModuleToggle(label, sectionName, openTabName)
    local enabled = IsSectionEnabled(sectionName)
    ImGui.PushStyleVar(ImGuiStyleVar.FrameRounding, 16)
    ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, 10, 5)
    local P = UltimateAssistPalette
    if enabled then
        ImGui.PushStyleColor(ImGuiCol.Button, P.moduleOn[1], P.moduleOn[2], P.moduleOn[3], P.moduleOn[4])
        ImGui.PushStyleColor(ImGuiCol.ButtonHovered, P.moduleOnHov[1], P.moduleOnHov[2], P.moduleOnHov[3], P.moduleOnHov[4])
        ImGui.PushStyleColor(ImGuiCol.Border, P.accentBorder[1], P.accentBorder[2], P.accentBorder[3], P.accentBorder[4])
        ImGui.PushStyleVar(ImGuiStyleVar.FrameBorderSize, 1)
    else
        ImGui.PushStyleColor(ImGuiCol.Button, P.moduleOff[1], P.moduleOff[2], P.moduleOff[3], P.moduleOff[4])
        ImGui.PushStyleColor(ImGuiCol.ButtonHovered, P.moduleOffHov[1], P.moduleOffHov[2], P.moduleOffHov[3], P.moduleOffHov[4])
        ImGui.PushStyleColor(ImGuiCol.Border, P.modeUnselBorder[1], P.modeUnselBorder[2], P.modeUnselBorder[3], 0.5)
        ImGui.PushStyleVar(ImGuiStyleVar.FrameBorderSize, 1)
    end
    if ImGui.Button((enabled and 'ON' or 'OFF') .. '##pill_' .. sectionName, 56, 26) then
        SetSectionEnabled(sectionName, not enabled)
    end
    ImGui.PopStyleVar(1)
    ImGui.PopStyleColor(3)
    ImGui.PopStyleVar(2)
    ImGui.SameLine()
    ImGui.Text(label)
    ImGui.SameLine()
    if enabled then
        ImGui.TextColored(P.textOk[1], P.textOk[2], P.textOk[3], P.textOk[4], 'ACTIVE ')
    else
        ImGui.TextColored(P.textDim[1], P.textDim[2], P.textDim[3], P.textDim[4], 'DISABLED')
    end
    ImGui.SameLine()
    if ImGui.SmallButton('Open##' .. sectionName) then
        local map = {Combat = 'combat', ['Buffs & Cures'] = 'buffs', ['Healing & OhShit'] = 'heals', Pet = 'pet'}
        MauiRuntime.nav.id = map[openTabName] or 'setup'
        if openTabName == 'Combat' then
            MauiRuntime.nav.combatSub = 'DPS'
        end
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
    local general = EnsureConfigSection('General')
    local classShort = tostring(globals.MyClass or ''):upper()
    local profileMode = ParseToggleValue(general.ChaseAssist) and 'Group/Raid' or 'Solo/Camp'
    local Ps = UltimateAssistPalette

    ImGui.TextColored(Ps.textTitle[1], Ps.textTitle[2], Ps.textTitle[3], Ps.textTitle[4], 'Quick Setup')
    ImGui.Spacing()
    ImGui.TextColored(Ps.textMuted[1], Ps.textMuted[2], Ps.textMuted[3], Ps.textMuted[4], 'Import a profile from Solo / Group / Raid above, tune modules, then confirm the validation strip before Start.')
    ImGui.Spacing()
    ImGui.TextColored(Ps.textTitle[1], Ps.textTitle[2], Ps.textTitle[3], Ps.textTitle[4], string.format('%s  ·  %s  ·  %s', classShort, profileMode, tostring(globals.INIFile or 'Unknown')))
    ImGui.TextColored(Ps.textOk[1], Ps.textOk[2], Ps.textOk[3], Ps.textOk[4], 'Recommended ranges — ChaseDistance 20–35 · MedStart 20–35 · CastRetries 2–4')
    ImGui.Spacing()

    if ImGui.Button('Safe Defaults') then
        ApplySetupPreset('Group')
        bottomActionMsg = 'Safe defaults applied (Group baseline)'
    end
    ImGui.SameLine()
    if ImGui.Button('Mini Setup') then
        miniSetupOpen = true
        open = false
        bottomActionMsg = 'Mini Setup opened'
    end
    ImGui.SameLine()
    if ImGui.Button('Save Config') then
        Save()
        globals.INIFileContents = utils.ReadRawINIFile()
        bottomActionMsg = 'Config saved to INI'
    end
    ImGui.SameLine()
    showAdvancedTabs = ImGui.Checkbox('Show Advanced Tabs##SetupTop', showAdvancedTabs)

    ImGui.Spacing()
    local enabledCountPre = 0
    for _, mod in ipairs(modules) do
        if IsSectionEnabled(mod.section) then enabledCountPre = enabledCountPre + 1 end
    end
    if ImGui.CollapsingHeader(string.format('STEP 1 — MODULES (%d / %d enabled)', enabledCountPre, #modules), ImGuiTreeNodeFlags.DefaultOpen) then
        ImGui.TextColored(Ps.textMuted[1], Ps.textMuted[2], Ps.textMuted[3], Ps.textMuted[4], 'Toggle combat/support lines; Open jumps to the matching Ultimate section.')
        ImGui.TextColored(Ps.textWarn[1], Ps.textWarn[2], Ps.textWarn[3], Ps.textWarn[4], 'Tip: start with Combat + Buffs + Heals; add Pet only on pet classes.')
        for _, mod in ipairs(modules) do
            DrawSetupModuleToggle(mod.label, mod.section, mod.tab)
        end
    end

    if ImGui.CollapsingHeader('STEP 2 — MOVEMENT', ImGuiTreeNodeFlags.DefaultOpen) then
        DrawField('General', 'ChaseAssist')
        local chaseOn = ParseToggleValue(EnsureConfigSection('General').ChaseAssist)
        if chaseOn then
            DrawFieldSliderGeneral('ChaseDistance', 0, 100, 20, 35)
            DrawField('General', 'BuffWhileChasing')
            ImGui.TextColored(Ps.textWarn[1], Ps.textWarn[2], Ps.textWarn[3], Ps.textWarn[4], 'Recommended: ChaseDistance 20-35 for safer follow behavior.')
        else
            DrawField('General', 'ReturnToCamp')
            if ParseToggleValue(EnsureConfigSection('General').ReturnToCamp) then
                DrawField('General', 'CampRadius')
                DrawField('General', 'ReturnToCampAccuracy')
            end
        end
        DrawFieldSliderGeneral('CampRadiusExceed', 0, 2000, 250, 500)
    end

    if ImGui.CollapsingHeader('STEP 3 — SURVIVAL & CORE', ImGuiTreeNodeFlags.DefaultOpen) then
        DrawField('General', 'MedOn')
        if ParseToggleValue(EnsureConfigSection('General').MedOn) then
            DrawFieldSliderGeneral('MedStart', 0, 100, 20, 35)
            DrawField('General', 'SitToMed')
            ImGui.TextColored(Ps.textWarn[1], Ps.textWarn[2], Ps.textWarn[3], Ps.textWarn[4], 'Recommended: MedStart 20-35. Low values can cause risky mana starvation.')
        end
        DrawField('General', 'AcceptInvitesOn')
        DrawField('General', 'GroupWatchOn')
        ImGui.TextColored(Ps.textWarn[1], Ps.textWarn[2], Ps.textWarn[3], Ps.textWarn[4], 'GroupWatchOn is advanced. Leave disabled unless you intentionally monitor group state logic.')
        DrawFieldSliderGeneral('CastRetries', 0, 12, 2, 4)
        ImGui.TextColored(Ps.textWarn[1], Ps.textWarn[2], Ps.textWarn[3], Ps.textWarn[4], 'Recommended: CastRetries 2-4. Higher values can cause cast loops.')
    end

    if ImGui.CollapsingHeader('STEP 4 — CONNECTIVITY', ImGuiTreeNodeFlags.DefaultOpen) then
        DrawField('General', 'EQBCOn')
        DrawField('General', 'DanNetOn')
        DrawField('General', 'DanNetDelay')
    end

    if ImGui.CollapsingHeader('VALIDATION', ImGuiTreeNodeFlags.DefaultOpen) then
        local dpsEnabled = IsSectionEnabled('DPS')
        local buffsEnabled = IsSectionEnabled('Buffs')
        local healsEnabled = IsSectionEnabled('Heals')
        local petEnabled = IsSectionEnabled('Pet')
        local warnings = 0
        local fails = 0

        if dpsEnabled and GetNumericValue('DPS', 'DPSSize', 0) == 0 then
            ImGui.TextColored(1.0, 0.65, 0.2, 1.0, 'DPS is enabled but DPSSize is 0.')
            warnings = warnings + 1
        end
        if buffsEnabled and GetNumericValue('Buffs', 'BuffsSize', 0) == 0 then
            ImGui.TextColored(1.0, 0.65, 0.2, 1.0, 'Buffs are enabled but BuffsSize is 0.')
            warnings = warnings + 1
        end
        if healsEnabled and GetNumericValue('Heals', 'HealsSize', 0) == 0 then
            ImGui.TextColored(1.0, 0.65, 0.2, 1.0, 'Heals are enabled but HealsSize is 0.')
            warnings = warnings + 1
        end
        if petEnabled and IsNullOrEmpty(EnsureConfigSection('Pet').PetSpell) then
            ImGui.TextColored(1.0, 0.65, 0.2, 1.0, 'Pet is enabled but PetSpell is not set.')
            warnings = warnings + 1
            ImGui.SameLine()
            if ImGui.SmallButton('Disable Pet##validation_fix') then
                SetSectionEnabled('Pet', false)
                bottomActionMsg = 'Validation fix applied: Pet module disabled'
            end
        end
        if ParseToggleValue(EnsureConfigSection('General').ChaseAssist) and ParseToggleValue(EnsureConfigSection('General').ReturnToCamp) then
            ImGui.TextColored(1.0, 0.45, 0.25, 1.0, 'Both ChaseAssist and ReturnToCamp are enabled. Usually choose one.')
            fails = fails + 1
            ImGui.SameLine()
            if ImGui.SmallButton('Use Chase Only##validation_fix_chase') then
                -- FIX 10: `general` was a local from outer scope that may not be in scope
                -- here (CollapsingHeader is a new block). Use EnsureConfigSection directly.
                EnsureConfigSection('General').ReturnToCamp = 0
                bottomActionMsg = 'Validation fix applied: ReturnToCamp set to 0'
            end
        end
        if not dpsEnabled and not buffsEnabled and not healsEnabled and not petEnabled then
            ImGui.TextColored(0.85, 0.85, 0.85, 1.0, 'No major modules are enabled yet.')
            warnings = warnings + 1
        end
        if ParseToggleValue(EnsureConfigSection('General').MedOn) and (GetNumericValue('General', 'MedStart', 20) < 15 or GetNumericValue('General', 'MedStart', 20) > 50) then
            ImGui.TextColored(1.0, 0.65, 0.2, 1.0, 'MedStart is outside typical safe range (20-35).')
            warnings = warnings + 1
        end
        if warnings == 0 and fails == 0 then
            ImGui.TextColored(0.45, 0.95, 0.55, 1.0, 'Validation PASS: setup looks safe to run.')
        else
            ImGui.TextColored(1.0, 0.75, 0.25, 1.0, string.format('Validation: %d fail(s), %d warning(s). Run Preflight before Start.', fails, warnings))
        end
    end

    ImGui.Spacing()
end

local function DrawMiniSetupWindow()
    if not miniSetupOpen then return end

    local function CollectMiniWarnings()
        local warnings = {}
        EnsureConfigSection('General')
        EnsureConfigSection('DPS')
        EnsureConfigSection('Buffs')
        EnsureConfigSection('Heals')
        EnsureConfigSection('Cures')

        if ParseToggleValue(globals.Config.General.ChaseAssist) and ParseToggleValue(globals.Config.General.ReturnToCamp) then
            table.insert(warnings, {
                text = 'Both ChaseAssist and ReturnToCamp are enabled.',
                tab = 'Movement & Camping',
                section = 'General',
                hint = 'Disable one movement mode.',
            })
        end
        if IsSectionEnabled('DPS') and (tonumber(globals.Config.DPS.DPSSize) or 0) == 0 then
            table.insert(warnings, {
                text = 'DPS is enabled but DPSSize is 0.',
                tab = 'Combat',
                section = 'DPS',
                hint = 'Set DPSSize and populate DPS entries.',
            })
        end
        if IsSectionEnabled('Buffs') and (tonumber(globals.Config.Buffs.BuffsSize) or 0) == 0 then
            table.insert(warnings, {
                text = 'Buffs are enabled but BuffsSize is 0.',
                tab = 'Buffs & Cures',
                section = 'Buffs',
                hint = 'Set BuffsSize and add buff lines.',
            })
        end
        if IsSectionEnabled('Heals') and (tonumber(globals.Config.Heals.HealsSize) or 0) == 0 then
            table.insert(warnings, {
                text = 'Heals are enabled but HealsSize is 0.',
                tab = 'Healing & OhShit',
                section = 'Heals',
                hint = 'Set HealsSize and add heal lines.',
            })
        end
        if IsSectionEnabled('Cures') and (tonumber(globals.Config.Cures.CuresSize) or 0) == 0 then
            table.insert(warnings, {
                text = 'Cures are enabled but CuresSize is 0.',
                tab = 'Buffs & Cures',
                section = 'Cures',
                hint = 'Set CuresSize and add cure lines.',
            })
        end
        if ParseToggleValue(globals.Config.General.TwistOn) then
            local twistWhat = tostring(globals.Config.General.TwistWhat or '')
            if twistWhat == '' or twistWhat == '0' or twistWhat:upper() == 'NULL' then
                table.insert(warnings, {
                    text = 'TwistOn is enabled but TwistWhat is empty/zero.',
                    tab = 'Movement & Camping',
                    section = 'General',
                    hint = 'Set TwistWhat or disable TwistOn.',
                })
            end
        end
        return warnings
    end

    local function GetMacroStatusMini()
        local macro = mq.TLO.Macro
        local Pu = UltimateAssistPalette
        local macroName = SafeTLOCall(function() return macro.Name() end, nil)
        if macroName ~= 'muleassist.mac' then
            return 'STOPPED', {Pu.textDim[1], Pu.textDim[2], Pu.textDim[3], Pu.textDim[4]}
        end
        if SafeTLOCall(function() return macro.Paused() end, false) then
            return 'PAUSED', {0.95, 0.72, 0.35, 1.0}
        end
        return 'RUNNING', {Pu.textOk[1], Pu.textOk[2], Pu.textOk[3], Pu.textOk[4]}
    end

    local function RunStartMini()
        local cmd = globals.MAUI_Config
            and globals.MAUI_Config[maui_ini_key]
            and globals.MAUI_Config[maui_ini_key]['StartCommand']
        if not cmd or tostring(cmd) == '' then
            cmd = '/mac muleassist'
        end
        mq.cmd(cmd)
        bottomActionMsg = 'Mini Setup: start command sent'
    end

    ImGui.SetNextWindowSize(560, 230, ImGuiCond.FirstUseEver)
    miniSetupOpen, _ = ImGui.Begin('UEA Mini Setup###UEA_MiniSetup', miniSetupOpen, ImGuiWindowFlags.NoCollapse)

    ImGui.BeginGroup()
    local tipMini = (open or miniSetupOpen)
        and 'Hide all MAUI UI (main window + Mini Setup)'
        or 'Show main MAUI window'
    if DrawMauiLogoButton('miniHeader', MauiFloat.miniSize, tipMini) then
        ToggleMauiFromLogoButton()
    end
    ImGui.SameLine(0, 8)
    ImGui.TextColored(0.45, 0.90, 0.98, 1.0, 'Quick Setup Launcher')
    ImGui.EndGroup()
    ImGui.Separator()
    ImGui.TextWrapped(string.format('Class: %s   INI: %s', tostring(globals.MyClass or 'UNK'):upper(), tostring(globals.INIFile or 'Unknown')))
    ImGui.TextColored(0.45, 0.95, 0.55, 1.0, 'Safe ranges: ChaseDistance 20-35, MedStart 20-35, CastRetries 2-4')
    ImGui.Spacing()

    if ImGui.Button('Solo', 84, 0) then ApplySetupPreset('Solo') end
    ImGui.SameLine()
    if ImGui.Button('Group', 84, 0) then ApplySetupPreset('Group') end
    ImGui.SameLine()
    if ImGui.Button('Raid', 84, 0) then ApplySetupPreset('Raid') end
    ImGui.SameLine()
    if ImGui.Button('Safe Defaults', 110, 0) then ApplySetupPreset('Group') end
    ImGui.SameLine()
    if ImGui.Button('Save', 70, 0) then
        Save()
        globals.INIFileContents = utils.ReadRawINIFile()
        bottomActionMsg = 'Mini Setup: config saved'
    end

    ImGui.Spacing()
    if ImGui.Button('Preflight', 96, 0) then
        miniValidationWarnings = CollectMiniWarnings()
        miniValidationChecked = true
        if #miniValidationWarnings == 0 then
            bottomActionMsg = 'Mini Setup validation: SAFE'
        else
            bottomActionMsg = string.format('Mini Setup validation: NOT SAFE (%d warning(s))', #miniValidationWarnings)
        end
    end
    ImGui.SameLine()
    if ImGui.Button('Start', 80, 0) then
        local startWarnings = CollectMiniWarnings()
        miniValidationWarnings = startWarnings
        miniValidationChecked = true
        if #startWarnings == 0 then
            RunStartMini()
        else
            bottomActionMsg = string.format('Start blocked: fix %d validation warning(s) first', #startWarnings)
        end
    end
    ImGui.SameLine()
    if ImGui.Button('Stop', 80, 0) then
        mq.cmd('/end')
        bottomActionMsg = 'Mini Setup: macro end command sent'
    end
    ImGui.SameLine()
    if ImGui.Button('Restore Main', 120, 0) then
        miniSetupOpen = false
        open = true
        bottomActionMsg = 'Main window restored'
    end

    ImGui.Spacing()
    if ImGui.Button('Retune Up (Best Rank)', 170, 0) then
        local changed, checked, updatedGems = AutoRetuneAbilities('upgrade')
        local queued = 0
        if autoMemAfterRetune then
            queued = QueueRetunedGemsForMem(updatedGems, memQueue)
        end
        if autoMemAfterRetune and queued > 0 then
            bottomActionMsg = string.format('Retune Up complete: %d/%d updated, queued %d gem mems', changed, checked, queued)
        else
            bottomActionMsg = string.format('Retune Up complete: %d/%d entries updated', changed, checked)
        end
    end
    ImGui.SameLine()
    if ImGui.Button('Retune Down (Lower Rank)', 185, 0) then
        local changed, checked, updatedGems = AutoRetuneAbilities('downgrade')
        local queued = 0
        if autoMemAfterRetune then
            queued = QueueRetunedGemsForMem(updatedGems, memQueue)
        end
        if autoMemAfterRetune and queued > 0 then
            bottomActionMsg = string.format('Retune Down complete: %d/%d updated, queued %d gem mems', changed, checked, queued)
        else
            bottomActionMsg = string.format('Retune Down complete: %d/%d entries updated', changed, checked)
        end
    end
    ImGui.SameLine()
    autoMemAfterRetune = ImGui.Checkbox('AutoMem After Retune##Mini', autoMemAfterRetune)

    local macroStatus, macroColor = GetMacroStatusMini()
    ImGui.Spacing()
    ImGui.TextColored(macroColor[1], macroColor[2], macroColor[3], macroColor[4], 'Macro: '..macroStatus)
    ImGui.SameLine()
    local liveWarnings = CollectMiniWarnings()
    if #liveWarnings == 0 then
        ImGui.TextColored(0.45, 0.95, 0.55, 1.0, 'Validation: SAFE')
    else
        ImGui.TextColored(1.0, 0.65, 0.2, 1.0, string.format('Validation: NOT SAFE (%d)', #liveWarnings))
    end
    if #liveWarnings > 0 then
        ImGui.TextColored(1.0, 0.45, 0.25, 1.0, 'Not safe to start. Fix these first:')
        if ImGui.CollapsingHeader('Validation Warnings##Mini', ImGuiTreeNodeFlags.DefaultOpen) then
            for i, warning in ipairs(liveWarnings) do
                ImGui.BulletText(warning.text or tostring(warning))
                ImGui.SameLine()
                if ImGui.SmallButton('Fix##MiniWarnFix' .. tostring(i)) then
                    miniSetupOpen = false
                    open = true
                    showAdvancedTabs = true
                    local mapNav = {
                        ['Combat'] = 'combat',
                        ['Buffs & Cures'] = 'buffs',
                        ['Healing & OhShit'] = 'heals',
                        ['Movement & Camping'] = 'movement',
                        ['Utility'] = 'utility',
                    }
                    MauiRuntime.nav.id = mapNav[warning.tab] or 'setup'
                    if warning.section and globals.Schema[warning.section] then
                        selectedSection = warning.section
                    end
                    bottomActionMsg = string.format('Opened %s to fix: %s', tostring(warning.tab or 'Setup'), tostring(warning.hint or warning.text or 'validation item'))
                end
                if warning.tab then
                    ImGui.SameLine()
                    ImGui.TextColored(0.72, 0.95, 1.00, 1.00, string.format('[%s]', tostring(warning.tab)))
                end
            end
        end
    elseif miniValidationChecked and #miniValidationWarnings == 0 then
        ImGui.TextColored(0.45, 0.95, 0.55, 1.0, 'All validation checks passed. Safe to start.')
    end
    if bottomActionMsg ~= '' then
        ImGui.SameLine()
        local Pm = UltimateAssistPalette
        ImGui.TextColored(Pm.textMuted[1], Pm.textMuted[2], Pm.textMuted[3], Pm.textMuted[4], bottomActionMsg)
    end

    ImGui.End()

    if not miniSetupOpen then
        open = true
    end
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
            name = 'UltimateEQ',
            targetFolder = 'UltimateEQ',
            runCmd = '/lua run UltimateEQ',
            stopCmd = '/lua stop UltimateEQ',
            openCmd = '/ueq',
            script = 'UltimateEQ',
            localOnly = true,
        },
        {
            name = 'ulti',
            targetFolder = 'ulti',
            runCmd = '/lua run ulti',
            stopCmd = '/lua stop ulti',
            openCmd = '/lua run ulti',
            script = 'ulti',
            localOnly = true,
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
            openCmd = '/lua run luaconsole', -- UPDATED: use non-toggle open command compatible with RedGuides LuaConsole
            script = 'luaconsole',
        },
        {
            name = 'ButtonMaster',
            sourceFolder = 'buttonmaster-main/buttonmaster-main',
            targetFolder = 'buttonmaster',
            runCmd = '/lua run buttonmaster',
            stopCmd = '/lua stop buttonmaster',
            openCmd = '/btn 1',
            script = 'buttonmaster',
        },
        {
            name = 'EZQuests',
            targetFolder = 'EZQuests-main',
            runCmd = '/lua run ezquests',
            stopCmd = '/lua stop ezquests',
            openCmd = '/ezq show',
            script = 'ezquests',
            localOnly = true,
        },
        {
            name = 'ConditionBuilder',
            targetFolder = '.',
            runCmd = '/lua run condition_builder',
            stopCmd = '/lua stop condition_builder',
            openCmd = '/cb show',
            script = 'condition_builder',
            localOnly = true,
        },
        {
            name = 'ExprEvaluator',
            targetFolder = '.',
            runCmd = '/lua run expression_evaluator',
            stopCmd = '/lua stop expression_evaluator',
            openCmd = '/ee show',
            script = 'expression_evaluator',
            localOnly = true,
        },
    }
end

local function DrawIntegrationsTab()
    local tools = GetIntegrationTools()
    local nowMs = mq.gettime()
    if nowMs >= integrationStatusNextRefresh then
        integrationStatusNextRefresh = nowMs + integrationStatusRefreshMs
        integrationStatusCache = {}
        for _, tool in ipairs(tools) do
            local src = NormalizePath(integrationSourceRoot) .. '/' .. (tool.sourceFolder or tool.folder or '')
            local dst = NormalizePath(mq.luaDir) .. '/' .. (tool.targetFolder or tool.folder or '')
            integrationStatusCache[tool.name] = {
                srcOk = tool.localOnly or (lfs.attributes(src, 'mode') == 'directory'),
                dstOk = (lfs.attributes(dst, 'mode') == 'directory'),
                status = GetLuaScriptStatus(tool.script),
            }
        end
    end

    DrawPanelHeader('External Tool Integrations')
    ImGui.TextWrapped('Sync external lua tools into your MQ lua folder, then run/stop/open them from this window.')
    ImGui.TextColored(0.70, 0.86, 0.98, 1.0, 'Theme Note: this Tools panel uses your active MAUI theme; external tool windows keep their own theme unless that tool exposes theme commands.')
    ImGui.PushItemWidth(520)
    integrationSourceRoot, _ = ImGui.InputText('Source Root##Integrations', integrationSourceRoot)
    ImGui.PopItemWidth()
    ImGui.TextWrapped('Default is your MacroQuest folder (parent of lua). Optional tool trees live under that root, e.g. EZInventory/grouper — same layout for every install.')
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
    local availW = ImGui.GetContentRegionAvail()
    local columns = 1
    if availW > 1300 then
        columns = 3
    elseif availW > 820 then
        columns = 2
    end

    if ImGui.BeginTable('##UEA_IntegrationGrid', columns, ImGuiTableFlags.SizingStretchSame) then
        for _, tool in ipairs(tools) do
            local src = NormalizePath(integrationSourceRoot) .. '/' .. (tool.sourceFolder or tool.folder or '')
            local dst = NormalizePath(mq.luaDir) .. '/' .. (tool.targetFolder or tool.folder or '')
            local statusRow = integrationStatusCache[tool.name] or {}
            local srcOk = statusRow.srcOk
            local dstOk = statusRow.dstOk
            local status = statusRow.status or 'stopped'
            local srcLabel = tool.localOnly and 'N/A (Local)' or (srcOk and 'OK' or 'Missing')

            ImGui.TableNextColumn()
            ImGui.PushID('ToolCard##' .. tool.name)
            if ImGui.BeginChild('##CardBody', -1, 132, ImGuiChildFlags.Border) then
                local dr, dg, db = 0.48, 0.48, 0.52
                if status == 'running' then
                    local pulse = (math.sin(nowMs / 280) + 1) * 0.5
                    dr, dg, db = 0.15 + pulse * 0.25, 0.82, 0.32
                elseif status == 'paused' then
                    dr, dg, db = 0.95, 0.75, 0.22
                end
                ImGui.TextColored(dr, dg, db, 1.0, '●')
                ImGui.SameLine()
                ImGui.TextColored(0.45, 0.90, 0.98, 1.0, tool.name)
                ImGui.Text(string.format('Src:%s  Dst:%s', srcLabel, dstOk and 'OK' or 'Missing'))
                if status == 'running' then
                    ImGui.TextColored(0.45, 0.95, 0.55, 1.0, 'RUNNING')
                elseif status == 'paused' then
                    ImGui.TextColored(0.98, 0.85, 0.35, 1.0, 'PAUSED')
                elseif status == 'stopped' then
                    ImGui.TextColored(0.62, 0.62, 0.68, 1.0, 'Stopped')
                else
                    ImGui.Text(string.format('Status: %s', status))
                end
                local lr = integrationToolLastRun[tool.name]
                if lr then
                    ImGui.TextColored(0.55, 0.58, 0.72, 1, string.format('Last launch cmd: %.1fs ago', (nowMs - lr) / 1000))
                end
                ImGui.Separator()

                local bw = math.floor((ImGui.GetContentRegionAvail() - 18) / 4)
                if bw < 52 then bw = 52 end
                if bw > 84 then bw = 84 end

                if tool.localOnly then
                    ImGui.BeginDisabled()
                    ImGui.Button('Sync', bw, 0)
                    ImGui.EndDisabled()
                else
                    if ImGui.Button('Sync', bw, 0) then
                        local ok, copied = SyncDirectory(src, dst)
                        bottomActionMsg = ok and string.format('%s: synced %d files', tool.name, copied) or (tool.name..': sync failed')
                    end
                end
                ImGui.SameLine()
                if status == 'running' then
                    if ImGui.Button((Icons.FA_STOP or '') .. ' Stop', bw + 8, 26) then
                        RunToolCommand('stoptool', tool.stopCmd)
                        bottomActionMsg = tool.name..': stop command sent'
                    end
                else
                    if ImGui.Button((Icons.FA_PLAY or '') .. ' Run', bw + 8, 26) then
                        if integrationAutoSync and not tool.localOnly then
                            SyncDirectory(src, dst)
                        end
                        RunToolCommand('runtool', tool.runCmd)
                        integrationToolLastRun[tool.name] = nowMs
                        bottomActionMsg = tool.name..': launch command sent'
                    end
                end
                ImGui.SameLine()
                if ImGui.Button('Open', bw, 26) then
                    if tool.script == 'luaconsole' then
                        mq.cmd('/lua stop luaconsole')
                        pendingLuaConsoleRestartAt = mq.gettime() + 50
                        bottomActionMsg = tool.name..': restart queued'
                    else
                        mq.cmd(tool.openCmd)
                        bottomActionMsg = tool.name..': open/toggle command sent'
                    end
                end
            end
            ImGui.EndChild()
            ImGui.PopID()
        end
        ImGui.EndTable()
    end
end

local function SetSchemaVars(selectedSchema)
    local ok, schemaMod = pcall(require, 'schemas.'..selectedSchema)
    if not ok then print('Error loading schema for: '..selectedSchema) return false end
    local okAddons, addonMod = pcall(require, 'addons.'..selectedSchema) -- UPDATED: keep addon module binding local (prevent global leak)
    if not okAddons then print('Error loading schema for: '..selectedSchema) return false end -- UPDATED: validate addon require result from local status var

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
    ImGui.PopItemWidth()
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
    ImGui.PopItemWidth()
    ImGui.SameLine()
    ImGui.PushItemWidth(300)
    if selected_start_command == 'custom' then
        globals.MAUI_Config[maui_ini_key]['StartCommand'],_ = ImGui.InputText('##StartCommand', globals.MAUI_Config[maui_ini_key]['StartCommand'])
    else
        globals.MAUI_Config[maui_ini_key]['StartCommand'],_ = ImGui.InputText('##StartCommand', selected_start_command)
    end
    ImGui.PopItemWidth()
    --ImGui.SameLine()
    ImGui.Text('Status: ')
    ImGui.SameLine()
    ImGui.SetCursorPosX(120)
    local macro = mq.TLO.Macro
    local macroName = SafeTLOCall(function() return macro.Name() end, nil)
    if macroName ~= 'muleassist.mac' then
        ImGui.TextColored(1, 0, 0, 1, 'STOPPED')
        ImGui.SameLine()
        if ImGui.Button('Start Macro') then
            mq.cmd(globals.MAUI_Config[maui_ini_key]['StartCommand'])
            SaveMAUIConfig()
        end
    else
        if SafeTLOCall(function() return macro.Paused() end, false) then
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
        ImGui.Text(string.format('Role: %s', tostring(SafeTLOCall(function() return macro.Variable('Role')() end, 'Unknown'))))
    end
    if globals.Config.error then
        ImGui.SameLine()
        ImGui.TextColored(1,0,0,1,globals.Config.error)
    end
    ImGui.Separator()
end

local function push_styles()
    -- SpawnMaster-inspired spacing/rounding behavior
    ImGui.PushStyleVar(ImGuiStyleVar.WindowRounding, 4)
    ImGui.PushStyleVar(ImGuiStyleVar.FrameRounding, 5)
    ImGui.PushStyleVar(ImGuiStyleVar.ChildRounding, 0)
    ImGui.PushStyleVar(ImGuiStyleVar.PopupRounding, 8)
    ImGui.PushStyleVar(ImGuiStyleVar.GrabRounding, 6)
    ImGui.PushStyleVar(ImGuiStyleVar.TabRounding, 0)
    ImGui.PushStyleVar(ImGuiStyleVar.WindowBorderSize, 1)
    ImGui.PushStyleVar(ImGuiStyleVar.FrameBorderSize, 1)
    ImGui.PushStyleVar(ImGuiStyleVar.ChildBorderSize, 1)
    ImGui.PushStyleVar(ImGuiStyleVar.WindowPadding, 8, 6)
    ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, 4, 2)
    ImGui.PushStyleVar(ImGuiStyleVar.ItemSpacing, 6, 4)
    ImGui.PushStyleVar(ImGuiStyleVar.CellPadding, 4, 3)

    local themeKey = NormalizeThemeKey(themeOrder[currentThemeIndex] or 'template')
    activeThemeKey = themeKey
    local theme = uiThemes[themeKey] or uiThemes['template']
    local menuBarBg = theme.menuBarBg or theme.frameBg
    local tableRowBg = theme.tableRowBg or {0.00, 0.00, 0.00, 0.00}
    local tableRowBgAlt = theme.tableRowBgAlt or theme.frameBgHovered
    local tableBorderLight = theme.tableBorderLight or theme.border
    local tableBorderStrong = theme.tableBorderStrong or theme.border
    local scrollbarBg = theme.scrollbarBg or theme.windowBg
    local scrollbarGrab = theme.scrollbarGrab or theme.frameBg
    local scrollbarGrabHovered = theme.scrollbarGrabHovered or theme.frameBgHovered

    ImGui.PushStyleColor(ImGuiCol.WindowBg, theme.windowBg[1], theme.windowBg[2], theme.windowBg[3], theme.windowBg[4])
    ImGui.PushStyleColor(ImGuiCol.ChildBg, 0.02, 0.03, 0.08, 1.00)
    ImGui.PushStyleColor(ImGuiCol.MenuBarBg, menuBarBg[1], menuBarBg[2], menuBarBg[3], menuBarBg[4])
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
    ImGui.PushStyleColor(ImGuiCol.TableRowBg, tableRowBg[1], tableRowBg[2], tableRowBg[3], tableRowBg[4])
    ImGui.PushStyleColor(ImGuiCol.TableRowBgAlt, tableRowBgAlt[1], tableRowBgAlt[2], tableRowBgAlt[3], tableRowBgAlt[4])
    ImGui.PushStyleColor(ImGuiCol.TableBorderLight, tableBorderLight[1], tableBorderLight[2], tableBorderLight[3], tableBorderLight[4])
    ImGui.PushStyleColor(ImGuiCol.TableBorderStrong, tableBorderStrong[1], tableBorderStrong[2], tableBorderStrong[3], tableBorderStrong[4])
    ImGui.PushStyleColor(ImGuiCol.Text, theme.text[1], theme.text[2], theme.text[3], theme.text[4])
    ImGui.PushStyleColor(ImGuiCol.Border, theme.border[1], theme.border[2], theme.border[3], theme.border[4])
    ImGui.PushStyleColor(ImGuiCol.Separator, theme.separator[1], theme.separator[2], theme.separator[3], theme.separator[4])
    ImGui.PushStyleColor(ImGuiCol.ScrollbarBg, scrollbarBg[1], scrollbarBg[2], scrollbarBg[3], scrollbarBg[4])
    ImGui.PushStyleColor(ImGuiCol.ScrollbarGrab, scrollbarGrab[1], scrollbarGrab[2], scrollbarGrab[3], scrollbarGrab[4])
    ImGui.PushStyleColor(ImGuiCol.ScrollbarGrabHovered, scrollbarGrabHovered[1], scrollbarGrabHovered[2], scrollbarGrabHovered[3], scrollbarGrabHovered[4])
    ImGui.PushStyleColor(ImGuiCol.TextDisabled, 0.72, 0.72, 0.72, 1.00)
    ImGui.PushStyleColor(ImGuiCol.CheckMark, 0.88, 0.52, 0.98, 1.00)
    --- Neon cyan slider grabs (UltimateEQAssist cyber accent).
    ImGui.PushStyleColor(ImGuiCol.SliderGrab, 0.35, 0.82, 1.00, 1.00)
    ImGui.PushStyleColor(ImGuiCol.SliderGrabActive, 0.55, 0.92, 1.00, 1.00)
    ImGui.PushStyleColor(ImGuiCol.PopupBg, 0.02, 0.03, 0.08, 0.98)
    ImGui.PushStyleColor(ImGuiCol.Tab, theme.frameBg[1], theme.frameBg[2], theme.frameBg[3], 1.00)
    ImGui.PushStyleColor(ImGuiCol.TabHovered, theme.frameBgHovered[1], theme.frameBgHovered[2], theme.frameBgHovered[3], 1.00)
    ImGui.PushStyleColor(ImGuiCol.TabActive, theme.header[1], theme.header[2], theme.header[3], 1.00)
end

local function pop_styles()
    ImGui.PopStyleColor(32)
    ImGui.PopStyleVar(13)
end

local maui_last_persist_rect = {}

local MAUI = function()
    if not open and not miniSetupOpen and not MauiFloat.showToggle then return end
    DrawMauiFloatingToggleWindow()
    push_styles()
    if open then
        if maui_restore_win then
            ImGui.SetNextWindowPos(maui_restore_win.x, maui_restore_win.y, ImGuiCond.FirstUseEver)
            ImGui.SetNextWindowSize(maui_restore_win.w, maui_restore_win.h, ImGuiCond.FirstUseEver)
            maui_restore_win = nil
        end
        ImGui.SetNextWindowSizeConstraints(MAUI_WIN_MIN_W, MAUI_WIN_MIN_H, MAUI_WIN_MAX_W, MAUI_WIN_MAX_H)
        open, shouldDrawUI = ImGui.Begin('UltimateEQAssist###MuleAssist', open, ImGuiWindowFlags.NoCollapse)
        if shouldDrawUI then
            if initialRun then
                if ImGui.GetWindowHeight() == 38 and ImGui.GetWindowWidth() == 32 then
                    ImGui.SetWindowSize(MAUI_WIN_DEFAULT_W, MAUI_WIN_DEFAULT_H)
                elseif ImGui.GetWindowHeight() == 500 and ImGui.GetWindowWidth() == 500 then
                    ImGui.SetWindowSize(MAUI_WIN_DEFAULT_W, MAUI_WIN_DEFAULT_H)
                end
                initialRun = false
            end
            DrawUltimateLayout()
            local nowt = mq.gettime()
            if nowt >= maui_window_persist_at then
                maui_window_persist_at = nowt + 3000
                local px, py = ImGui.GetWindowPos()
                local pw, ph = ImGui.GetWindowSize()
                if not maui_last_persist_rect.x
                    or math.abs(maui_last_persist_rect.x - px) > 2
                    or math.abs(maui_last_persist_rect.y - py) > 2
                    or math.abs(maui_last_persist_rect.w - pw) > 2
                    or math.abs(maui_last_persist_rect.h - ph) > 2 then
                    maui_last_persist_rect.x = px
                    maui_last_persist_rect.y = py
                    maui_last_persist_rect.w = pw
                    maui_last_persist_rect.h = ph
                    if not globals.MAUI_Config[maui_ini_key] then
                        globals.MAUI_Config[maui_ini_key] = {}
                    end
                    globals.MAUI_Config[maui_ini_key].WinX = px
                    globals.MAUI_Config[maui_ini_key].WinY = py
                    globals.MAUI_Config[maui_ini_key].WinW = pw
                    globals.MAUI_Config[maui_ini_key].WinH = ph
                    SaveMAUIConfig()
                end
            end
        end
        ImGui.End()
    end
    DrawMiniSetupWindow()
    pop_styles()
end

local function CheckGameState()
    -- FIX 15: Guard GameState() for nil during transient load/zone-in states.
    -- Previously, if EverQuest.GameState() returned nil, ~= 'INGAME' would be
    -- true and the script would exit prematurely during zone transitions.
    local gameState = mq.TLO.EverQuest.GameState()
    if gameState ~= nil and gameState ~= 'INGAME' then
        print('\arNot in game, stopping MAUI.\ax')
        open = false
        shouldDrawUI = false
        mq.imgui.destroy('MuleAssist')
        mq.exit()
    end
end

local function ShowHelp()
    print('\a-t[\ax\ayMAUI\ax\a-t]\ax Usage: /maui [show|hide|stop]  (hide/stop close main + Mini Setup)')
end

local function BindMaui(args)
    -- FIX 12: {args} always creates a 1-element table regardless of content.
    -- #arglist > 1 could never be true. Split the arg string on spaces for proper parsing.
    if not args or args == '' then
        ShowHelp()
        return
    end
    local cmd = args:match('^%s*(%S+)')
    if cmd == 'show' then
        open = true
    elseif cmd == 'hide' then
        open = false
        miniSetupOpen = false
    elseif cmd == 'stop' then
        open = false
        miniSetupOpen = false
        terminate = true
    else
        ShowHelp()
    end
end

local function NewSpellMemmed(line, spellName)
    print(string.format('\a-t[\ax\ayMAUI\ax\a-t]\ax New spell memorized, updating spell list. \a-t(\ax\ay%s\ax\a-t)\ax', spellName))
    -- FIX 1: variable 'spell' was shadowing the parameter of the same name, and
    -- mq.TLO.Me.Book(spell) was being called twice with the wrong argument types.
    -- First call: look up the book index (number) for the spell name.
    -- Second call: use that index to get the actual spell TLO object.
    local spellNum = mq.TLO.Me.Book(spellName)
    if not spellNum or not spellNum() then return end
    local spellObj = mq.TLO.Me.Book(spellNum())
    if spellObj and spellObj() then
        AddSpellToMap(spellObj)
    end
    SortMap(spells)
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

MauiUltimateAPI = {
    RefreshDirtyState = RefreshDirtyState,
    IsSectionEnabled = IsSectionEnabled,
    GetNumericValue = GetNumericValue,
    EnsureConfigSection = EnsureConfigSection,
    ParseToggleValue = ParseToggleValue,
    IsNullOrEmpty = IsNullOrEmpty,
    Save = Save,
    getIsDirty = function() return isDirty end,
    setBottomActionMsg = function(msg) bottomActionMsg = msg end,
    DrawSetupTab = DrawSetupTab,
    DrawGeneralTab = DrawGeneralTab,
    DrawSectionTab = DrawSectionTab,
    DrawMovementCampingTab = DrawMovementCampingTab,
    DrawUtilityTab = DrawUtilityTab,
    DrawIntegrationsTab = DrawIntegrationsTab,
    DrawReadmeTab = ReadmeUI.DrawReadmeTab,
    DrawWindowPanels = DrawWindowPanels,
    DrawUltimateBottomBar = DrawUltimateBottomBar,
}
UltimateUIMod = require('maui.ultimate_ui')

function DrawUltimateLayout()
    ui_main_tab = 'UI'
    local n = MauiRuntime.nav
    if pendingMainTab == 'Readme' then
        n.id = 'readme'
    elseif pendingMainTab == 'RAW' then
        n.id = 'raw'
    elseif pendingMainTab == 'Tools' then
        n.id = 'tools'
    end
    pendingMainTab = nil

    if pendingConfigTab == 'Combat' then
        n.id, n.combatSub = 'combat', 'Aggro'
    elseif pendingConfigTab == 'Buffs & Cures' then
        n.id = 'buffs'
    elseif pendingConfigTab == 'Healing & OhShit' then
        n.id = 'heals'
    elseif pendingConfigTab == 'Pet' then
        n.id = 'pet'
    elseif pendingConfigTab == 'Movement & Camping' then
        n.id = 'movement'
    elseif pendingConfigTab == 'Utility' then
        n.id = 'utility'
    elseif pendingConfigTab == 'SpellSet / Gems' then
        n.id = 'spellset'
    elseif pendingConfigTab == 'General' then
        n.id = 'general'
    elseif pendingConfigTab == 'All Sections' then
        n.id = 'allsections'
    elseif pendingConfigTab == 'Setup' then
        n.id = 'setup'
    end
    pendingConfigTab = nil

    DrawUltimateModeBanner()
    ImGui.Separator()
    DrawUltimateIniSettingsRow()
    ImGui.Separator()
    UltimateUIMod.drawUltimateBody(MauiRuntime, MauiUltimateAPI)
end

mq.imgui.init('MuleAssist', MAUI)

--- Lua 5.1 / MQ: main chunk may only register ~200 locals; keep the hot loop in its own function.
local function RunMauiMainLoop()
    local init_done = false
    local nextCachePruneAt = 0
    local cachePruneIntervalMs = 1000
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
            local rankname = SafeTLOCall(function() return mq.TLO.Spell(memspell).RankName() end, nil)
            if rankname then
                mq.cmdf('/memspell %s "%s"', memgem, rankname)
                local waitUntil = mq.gettime() + 3000
                while mq.gettime() < waitUntil do
                    mq.doevents()
                    local gem = mq.TLO.Me.Gem(memgem)
                    if gem and gem() and gem.Name() == rankname then break end
                    mq.delay(50)
                end
                local spellBookWnd = mq.TLO.Window('SpellBookWnd')
                if spellBookWnd and spellBookWnd() then spellBookWnd.DoClose() end
            end
            memspell = nil
            memgem = 0
        end
        if pendingLuaConsoleRestartAt and mq.gettime() >= pendingLuaConsoleRestartAt then
            mq.cmd('/lua run luaconsole')
            pendingLuaConsoleRestartAt = nil
            bottomActionMsg = 'LuaConsole: restarted and opened'
        end
        local nowMs = mq.gettime()
        if nowMs >= nextCachePruneAt then
            tloCache:clean()
            nextCachePruneAt = nowMs + cachePruneIntervalMs
        end
        mq.delay(20)
    end
end

RunMauiMainLoop()

mq.unevent('NewSpellMemmed') -- UPDATED: unregister event handler on script shutdown
mq.unbind('/maui') -- UPDATED: remove slash-command binding on script shutdown
pcall(function() mq.imgui.destroy('MuleAssist') end) -- UPDATED: ensure ImGui callback is detached during normal termination
