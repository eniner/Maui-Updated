local mq = require('mq')
local ImGui = require('ImGui') -- UPDATED: avoid leaking ImGui as an implicit global

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

local tloCache = cache:new(300, 300)

globals.MyServer = mq.TLO.EverQuest.Server() or 'Unknown' -- UPDATED: nil-safe TLO read during transient load/zoning states
globals.MyName = mq.TLO.Me.CleanName() or 'Unknown' -- UPDATED: nil-safe TLO read during transient load/zoning states
globals.MyLevel = tonumber(mq.TLO.Me.Level() or 1) or 1 -- UPDATED: enforce numeric level with safe fallback
globals.MyClass = tostring(mq.TLO.Me.Class.ShortName() or 'unk'):lower() -- UPDATED: nil-safe class short name normalization

globals.MAUI_INI = ('%s/%s_%s.ini'):format(mq.configDir, globals.MyServer, globals.MyName)
local maui_ini_key = 'MAUI'
if utils.FileExists(globals.MAUI_INI) then
    globals.MAUI_Config = LIP.load(globals.MAUI_INI, false)
end
if not globals.MAUI_Config or not globals.MAUI_Config[maui_ini_key] or not globals.MAUI_Config[maui_ini_key]['StartCommand'] then
    globals.MAUI_Config = {[maui_ini_key] = {['StartCommand'] = globals.Schema['StartCommands'][1], ['Theme'] = 'template',}}
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
        separator = {0.22, 0.90, 0.84, 0.60},
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
    if utils.FileExists(globals.MAUI_INI) then
        globals.MAUI_Config = LIP.load(globals.MAUI_INI, false)
    else
        globals.MAUI_Config = {}
    end
    globals.MAUI_Config[maui_ini_key] = {['StartCommand'] = tmpStartCommand, ['INIFile'] = globals.INIFile, ['Theme'] = tmpTheme}
    LIP.save_simple(globals.MAUI_INI, globals.MAUI_Config)
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

local function ReloadINIFromDisk()
    if globals.INIFile:sub(-string.len('.ini')) ~= '.ini' then
        globals.INIFile = globals.INIFile .. '.ini'
    end
    if utils.FileExists(mq.configDir..'/'..globals.INIFile) then
        globals.Config = LIP.load(mq.configDir..'/'..globals.INIFile)
        globals.INIFileContents = utils.ReadRawINIFile()
        globals.INILoadError = ''
    else
        globals.INILoadError = ('INI File %s/%s does not exist!'):format(mq.configDir, globals.INIFile)
    end
end

local function DrawUltimateTopBar()
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
        ReloadINIFromDisk()
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
        globals.INIFile = filedialog.get_filename()
        ReloadINIFromDisk()
        filedialog:reset_filename()
    end

    ImGui.Separator()
end

local function DrawUltimateBottomBar()
    if ImGui.Button('MemSpells', uniformButtonWidth, 0) then
        mq.cmdf('/memmyspells %s', globals.INIFile)
    end
    ImGui.SameLine()
    if ImGui.Button('SaveGems', uniformButtonWidth, 0) then
        mq.cmd('/memspells save')
    end
    ImGui.SameLine()
    if ImGui.Button('Ini Manager', uniformButtonWidth, 0) then
        filedialog.set_file_selector_open(true)
    end
    ImGui.SameLine()
    if ImGui.Button('Remote', uniformButtonWidth, 0) then
        selectedSection = 'General'
    end
    ImGui.SameLine()
    if ImGui.Button('Upgrades?', uniformButtonWidth, 0) then
        selectedSection = 'Buffs'
    end
    ImGui.SameLine()
    if ImGui.Button('Downgrades?', uniformButtonWidth, 0) then
        selectedSection = 'Buffs'
    end
    ImGui.SameLine()
    if ImGui.Button('HotButtons', uniformButtonWidth, 0) then
        selectedSection = 'General'
    end
    ImGui.SameLine()
    if ImGui.Button('Gem Manager', uniformButtonWidth, 0) then
        selectedSection = 'MySpells'
    end

    ImGui.SameLine()
    local curX = ImGui.GetCursorPosX()
    local availX = ImGui.GetContentRegionAvail()
    local startWidth = 58
    local rightPad = 8
    if availX < (startWidth + rightPad) then
        ImGui.NewLine()
        curX = ImGui.GetCursorPosX()
        availX = ImGui.GetContentRegionAvail()
    end
    local targetX = curX + math.max(0, availX - startWidth - rightPad)
    ImGui.SetCursorPosX(targetX)
    if ImGui.Button('Start', startWidth, 0) then
        mq.cmd(globals.MAUI_Config[maui_ini_key]['StartCommand'])
        SaveMAUIConfig()
    end
end

local function DrawPanelHeader(text)
    ImGui.TextColored(0.45, 0.90, 0.98, 1.0, text)
    ImGui.Separator()
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

local function DrawUltimateLayout()
    if ImGui.BeginTabBar('##UEA_Tabs') then
        if ImGui.BeginTabItem('UI') then
            ui_main_tab = 'UI'
            DrawUltimateTopBar()
            ImGui.BeginChild('##UEA_UIBody', -1, -72, ImGuiChildFlags.Border)
            if ImGui.BeginTabBar('##UEA_ConfigTabs') then
                if ImGui.BeginTabItem('General') then
                    DrawGeneralTab()
                    ImGui.EndTabItem()
                end
                if ImGui.BeginTabItem('Combat') then
                    if ImGui.BeginTabBar('##UEA_CombatSubtabs') then
                        if ImGui.BeginTabItem('Aggro') then DrawSectionTab('Aggro'); ImGui.EndTabItem() end
                        if ImGui.BeginTabItem('DPS') then DrawSectionTab('DPS'); ImGui.EndTabItem() end
                        if ImGui.BeginTabItem('Burn') then DrawSectionTab('Burn'); ImGui.EndTabItem() end
                        if ImGui.BeginTabItem('GoM') then DrawSectionTab('GoM'); ImGui.EndTabItem() end
                        ImGui.EndTabBar()
                    end
                    ImGui.EndTabItem()
                end
                if ImGui.BeginTabItem('Buffs & Cures') then
                    if ImGui.BeginTabBar('##UEA_BuffsSubtabs') then
                        if ImGui.BeginTabItem('Buffs') then DrawSectionTab('Buffs'); ImGui.EndTabItem() end
                        if ImGui.BeginTabItem('Cures') then DrawSectionTab('Cures'); ImGui.EndTabItem() end
                        if ImGui.BeginTabItem('AE') then DrawSectionTab('AE'); ImGui.EndTabItem() end
                        ImGui.EndTabBar()
                    end
                    ImGui.EndTabItem()
                end
                if ImGui.BeginTabItem('Healing & OhShit') then
                    if ImGui.BeginTabBar('##UEA_HealSubtabs') then
                        if ImGui.BeginTabItem('Heals') then DrawSectionTab('Heals'); ImGui.EndTabItem() end
                        if ImGui.BeginTabItem('OhShit') then DrawSectionTab('OhShit'); ImGui.EndTabItem() end
                        if ImGui.BeginTabItem('Mez') then DrawSectionTab('Mez'); ImGui.EndTabItem() end
                        ImGui.EndTabBar()
                    end
                    ImGui.EndTabItem()
                end
                if ImGui.BeginTabItem('Pet') then
                    DrawSectionTab('Pet')
                    ImGui.EndTabItem()
                end
                if ImGui.BeginTabItem('Movement & Camping') then
                    DrawMovementCampingTab()
                    ImGui.EndTabItem()
                end
                if ImGui.BeginTabItem('Utility') then
                    DrawUtilityTab()
                    ImGui.EndTabItem()
                end
                ImGui.EndTabBar()
            end
            ImGui.Dummy(1, 1)
            ImGui.EndChild()
            DrawUltimateBottomBar()
            ImGui.EndTabItem()
        end
        if ImGui.BeginTabItem('RAW') then
            ui_main_tab = 'RAW'
            if not globals.INIFileContents then
                globals.INIFileContents = utils.ReadRawINIFile()
            end
            globals.INIFileContents,_ = ImGui.InputTextMultiline('##UEA_RAW_INI', globals.INIFileContents or '', -1, -42)
            if ImGui.Button('Save Raw') then
                local path = mq.configDir..'/'..globals.INIFile
                local f = io.open(path, 'w')
                if f then
                    f:write(globals.INIFileContents or '')
                    f:close()
                    ReloadINIFromDisk()
                end
            end
            ImGui.SameLine()
            if ImGui.Button('Reload Raw') then
                globals.INIFileContents = utils.ReadRawINIFile()
            end
            ImGui.EndTabItem()
        end
        ImGui.EndTabBar()
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
    else
        globals.INIFile = ''
        globals.Config = {}
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
    local macro = mq.TLO.Macro() -- UPDATED: cache TLO handle once for nil-safe access
    if not macro or macro.Name() ~= 'muleassist.mac' then -- UPDATED: nil-safe macro existence/name check
        ImGui.TextColored(1, 0, 0, 1, 'STOPPED')
        ImGui.SameLine()
        if ImGui.Button('Start Macro') then
            mq.cmd(globals.MAUI_Config[maui_ini_key]['StartCommand'])
            SaveMAUIConfig()
        end
    elseif macro.Name() == 'muleassist.mac' then -- UPDATED: reuse cached macro handle for branch checks
        if macro.Paused() then -- UPDATED: reuse cached macro handle for paused-state check
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
        ImGui.Text(string.format('Role: %s', tostring(macro.Variable('Role')() or 'Unknown'))) -- UPDATED: nil-safe macro variable rendering
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
    ImGui.PushStyleColor(ImGuiCol.CheckMark, 0.96, 0.86, 0.30, 1.00)
    ImGui.PushStyleColor(ImGuiCol.PopupBg, 0.02, 0.03, 0.08, 0.98)
    ImGui.PushStyleColor(ImGuiCol.Tab, theme.frameBg[1], theme.frameBg[2], theme.frameBg[3], 1.00)
    ImGui.PushStyleColor(ImGuiCol.TabHovered, theme.frameBgHovered[1], theme.frameBgHovered[2], theme.frameBgHovered[3], 1.00)
    ImGui.PushStyleColor(ImGuiCol.TabActive, theme.header[1], theme.header[2], theme.header[3], 1.00)
end

local function pop_styles()
    ImGui.PopStyleColor(30)
    ImGui.PopStyleVar(13)
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
    if mq.TLO.EverQuest.GameState() ~= 'INGAME' then -- UPDATED: use current EverQuest TLO for game state checks
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
if globals.INIFile and utils.FileExists(mq.configDir..'/'..globals.INIFile) then
    globals.Config = LIP.load(mq.configDir..'/'..globals.INIFile)
    globals.INIFileContents = utils.ReadRawINIFile()
    globals.INILoadError = ''
else
    globals.INIFile = globals.Schema['INI_PATTERNS']['level']:format(globals.MyServer, globals.MyName, globals.MyLevel)
    globals.Config = {}
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
    if memspell then
        local rankname = mq.TLO.Spell(memspell).RankName()
        mq.cmdf('/memspell %s "%s"', memgem, rankname)
        local waitUntil = mq.gettime() + 3000 -- UPDATED: coroutine-safe timed wait instead of a blocking string delay helper
        while mq.gettime() < waitUntil do -- UPDATED: yield in short slices while waiting for gem mem completion
            local gem = mq.TLO.Me.Gem(memgem) -- UPDATED: cache gem TLO for safe repeated checks
            if gem() and gem.Name() == rankname then break end -- UPDATED: explicit completion predicate with nil-safe checks
            mq.delay(10) -- UPDATED: cooperative yield while polling mem result
        end
        local spellBookWnd = mq.TLO.Window('SpellBookWnd') -- UPDATED: cache window TLO before issuing close
        if spellBookWnd() then spellBookWnd.DoClose() end -- UPDATED: nil-check window existence before close action
        memspell = nil
        memgem = 0
    end
    tloCache:clean()
    mq.delay(20)
end

mq.unevent('NewSpellMemmed') -- UPDATED: unregister event handler on script shutdown
mq.unbind('/maui') -- UPDATED: remove slash-command binding on script shutdown
pcall(function() mq.imgui.destroy('MuleAssist') end) -- UPDATED: ensure ImGui callback is detached during normal termination

