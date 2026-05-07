local mq = require('mq')
local ImGui = require('ImGui')

-- LFS must be downloaded from the luarocks server before anything can work
-- so do that first. This will open a dialog prompting to download lfs.dll
-- if not already present.
-- Include helper function so we can give user friendly messages
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

local lfs = require('lfs')

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

local selectedListItem = {nil, 0} -- {key, index}
local selectedUpgrade = nil
local selectedSection = 'General' -- Left hand menu selected item
local autoMemAfterRetune = false
local memQueue = {}
local miniSetupOpen = false
local bottomActionMsg = ''
local miniValidationWarnings = {}
local miniValidationChecked = false

local tloCache = cache:new(300, 300)

local function SafeTLOCall(fn, fallback)
    local ok, v = pcall(fn)
    if ok then return v end
    return fallback
end

--- INI paths may include spaces; DoCommand rejects `/memmyspells "..."` — use ${Parse[0,...]} (same as maui/init.lua).
local function CmdMemMySpells(iniFile)
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
    globals.MAUI_Config = {[maui_ini_key] = {['StartCommand'] = globals.Schema['StartCommands'][1], ['AutoMemRetune'] = false,}}
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

local TABLE_FLAGS = bit32.bor(ImGuiTableFlags.Hideable, ImGuiTableFlags.RowBg, ImGuiTableFlags.ScrollY, ImGuiTableFlags.BordersOuter)

--local customSections = require('ma.addons.'..globals.CurrentSchema)
local ok, customSections = pcall(require, 'addons.'..globals.CurrentSchema)
if not ok then customSections = nil end

local function SaveMAUIConfig()
    -- Reload the maui.ini before saving to try and prevent writing stale data
    local tmpStartCommand = globals.MAUI_Config[maui_ini_key]['StartCommand']
    if utils.FileExists(globals.MAUI_INI) then
        globals.MAUI_Config = LIP.load(globals.MAUI_INI, false)
    else
        globals.MAUI_Config = {}
    end
    local tmpAutoMemRetune = autoMemAfterRetune
    globals.MAUI_Config[maui_ini_key] = {['StartCommand'] = tmpStartCommand, ['INIFile'] = globals.INIFile, ['AutoMemRetune'] = tmpAutoMemRetune}
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

local uea_presets = require('uea_presets')
local function ApplySetupPreset(presetName)
    uea_presets.apply(presetName, {
        mq = mq,
        globals = globals,
        utils = utils,
        LIP = LIP,
        lfs = lfs,
        Save = Save,
        SafeTLOCall = SafeTLOCall,
        setBottomMsg = function(s)
            bottomActionMsg = s
        end,
    })
end

-- Sort spells by level
local SpellSorter = function(a, b)
    -- spell level is in spell[1], name in spell[2]
    return a[1] > b[1]
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
        if spellIter % 100 == 0 then
            mq.delay(0)
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
    local spellName = aa.Spell() and aa.Spell.Name() or aa.Name()
    table.insert(altAbilities[type], {aa.Name(), spellName})
end

local function InitAATree()
    -- TODO: what's the right way to loop through activated abilities?
    for aaIter=1,10000 do
        local aa = mq.TLO.Me.AltAbility(aaIter)
        if aa and aa() and aa.Spell() then
            AddAAToMap(aa)
        end
        if aaIter % 200 == 0 then
            mq.delay(0)
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
    for discIter = 1, 10000 do
        local disc = mq.TLO.Me.CombatAbility(discIter)
        if disc and disc() then
            AddDiscToMap(disc)
        else
            break
        end
        if discIter % 100 == 0 then
            mq.delay(0)
        end
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
    if typestring == 'number' and (value == nil or value == 'NULL' or value == '') then
        return
    end
    if type(value) ~= typestring then
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

    if SafeTLOCall(function() return mq.TLO.FindItem(name)() end, nil)
        or SafeTLOCall(function() return mq.TLO.Me.AltAbility(name)() end, nil)
        or SafeTLOCall(function() return mq.TLO.Me.Ability(name)() end, nil)
        or SafeTLOCall(function() return mq.TLO.Me.CombatAbility(name)() end, nil) then
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

--- MuleAssist /memmyspells requires [MySpells] Gem1..Gem13 (from MAUI or /writespells).
local function MySpellsHasAnyGem()
    local ms = globals.Config and globals.Config.MySpells
    if not ms or type(ms) ~= 'table' then
        return false
    end
    for i = 1, 13 do
        local v = ms['Gem' .. i]
        if type(v) == 'string' then
            local s = Trim(v)
            if s ~= '' and s:upper() ~= 'NULL' then
                return true
            end
        elseif type(v) == 'number' then
            return true
        end
    end
    return false
end

--- After retune: gem queue only fills when [MySpells] Gem lines changed. If retune
--- touched DPS/Heals/etc. only, fall back to /memmyspells (same as Mem Spells button).
local function ApplyAutoMemAfterRetune(changed, updatedGems)
    if not autoMemAfterRetune or type(changed) ~= 'number' or changed <= 0 then
        return
    end
    local queued = QueueRetunedGemsForMem(updatedGems or {}, memQueue)
    if queued > 0 then
        utils.printf('[MAUI] AutoMem: queued %d gem slot(s) for /memspell', queued)
        return
    end
    if not MySpellsHasAnyGem() then
        utils.printf('[MAUI] AutoMem skipped: [MySpells] has no gems — set bar in MAUI SpellSet "Update from spell bar" + Save INI, or MuleAssist /writespells.')
        return
    end
    local ini = globals.INIFile
    if ini and ini ~= '' then
        if ini:sub(-string.len('.ini')) ~= '.ini' then
            ini = ini .. '.ini'
        end
        CmdMemMySpells(ini)
        utils.printf('[MAUI] AutoMem: ran /memmyspells for %s (retune did not change MySpells gems)', ini)
    else
        utils.printf('[MAUI] AutoMem: no INI path set — cannot mem bar')
    end
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

local function EnsureConfigSection(sectionName)
    if type(globals.Config) ~= 'table' then
        globals.Config = {}
    end
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
    ImGui.Dummy(1, 1)
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
        if MySpellsHasAnyGem() then
            CmdMemMySpells(globals.INIFile)
        else
            utils.printf('[MAUI] [MySpells] empty — use "Update from spell bar" here, Save INI, then try again (or /writespells in MuleAssist).')
        end
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
    if ImGui.BeginChild('SectionProperties') then
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
    end
    if sectionName == 'Buffs' then
        useRankNames = false
    end
    ImGui.EndChild()
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

    if ImGui.Button('UEA Mini Setup') then
        miniSetupOpen = true
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
    if ImGui.Button('Retune Up (Best Rank)', 170, 0) then
        local changed, checked, updatedGems = AutoRetuneAbilities('upgrade')
        ApplyAutoMemAfterRetune(changed, updatedGems)
        utils.printf('[MAUI] Retune Up: %d/%d entries updated', changed, checked)
    end
    ImGui.SameLine()
    if ImGui.Button('Retune Down (Lower Rank)', 185, 0) then
        local changed, checked, updatedGems = AutoRetuneAbilities('downgrade')
        ApplyAutoMemAfterRetune(changed, updatedGems)
        utils.printf('[MAUI] Retune Down: %d/%d entries updated', changed, checked)
    end
    ImGui.SameLine()
    local prevAutoMem = autoMemAfterRetune
    autoMemAfterRetune = ImGui.Checkbox('AutoMem After Retune##Header', autoMemAfterRetune)
    if prevAutoMem ~= autoMemAfterRetune then
        SaveMAUIConfig()
    end
    ImGui.Separator()
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
        local macroName = SafeTLOCall(function() return macro.Name() end, nil)
        if macroName ~= 'muleassist.mac' then
            return 'STOPPED', {1.00, 0.35, 0.35, 1.0}
        end
        if SafeTLOCall(function() return macro.Paused() end, false) then
            return 'PAUSED', {1.00, 0.85, 0.20, 1.0}
        end
        return 'RUNNING', {0.30, 1.00, 0.45, 1.0}
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
    ImGui.TextColored(0.45, 0.90, 0.98, 1.0, 'UE')
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
        ApplyAutoMemAfterRetune(changed, updatedGems)
        utils.printf('[MAUI] Retune Up: %d/%d entries updated', changed, checked)
        bottomActionMsg = string.format('Retune Up: %d/%d updated%s', changed, checked, autoMemAfterRetune and ' (AutoMem)' or '')
    end
    ImGui.SameLine()
    if ImGui.Button('Retune Down (Lower Rank)', 185, 0) then
        local changed, checked, updatedGems = AutoRetuneAbilities('downgrade')
        ApplyAutoMemAfterRetune(changed, updatedGems)
        utils.printf('[MAUI] Retune Down: %d/%d entries updated', changed, checked)
        bottomActionMsg = string.format('Retune Down: %d/%d updated%s', changed, checked, autoMemAfterRetune and ' (AutoMem)' or '')
    end
    ImGui.SameLine()
    local prevAutoMemMini = autoMemAfterRetune
    autoMemAfterRetune = ImGui.Checkbox('AutoMem After Retune##Mini', autoMemAfterRetune)
    if prevAutoMemMini ~= autoMemAfterRetune then
        SaveMAUIConfig()
    end

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
                    if warning.section and globals.Schema[warning.section] then
                        selectedSection = warning.section
                    end
                    bottomActionMsg = string.format('Opened MAUI to fix: %s', tostring(warning.hint or warning.text or 'validation item'))
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
        ImGui.TextColored(0.45, 0.90, 0.98, 1.0, bottomActionMsg)
    end

    ImGui.End()

    if not miniSetupOpen then
        open = true
    end
end

local function push_styles()
    ImGui.PushStyleColor(ImGuiCol.WindowBg, 0, 0, 0, .9)
    ImGui.PushStyleColor(ImGuiCol.TitleBg, .3, 0, 0, 1)
    ImGui.PushStyleColor(ImGuiCol.TitleBgActive, .5, 0, 0, 1)
    ImGui.PushStyleColor(ImGuiCol.FrameBg, .2, .2, .2, 1)
    ImGui.PushStyleColor(ImGuiCol.FrameBgHovered, .3, 0, 0, 1)
    ImGui.PushStyleColor(ImGuiCol.FrameBgActive, .3, 0, 0, 1)
    ImGui.PushStyleColor(ImGuiCol.Button, .5, 0, 0,1)
    ImGui.PushStyleColor(ImGuiCol.ButtonHovered, .6, 0, 0,1)
    ImGui.PushStyleColor(ImGuiCol.ButtonActive, .5, 0, 0,1)
    ImGui.PushStyleColor(ImGuiCol.PopupBg, .1,.1,.1,1)
    ImGui.PushStyleColor(ImGuiCol.TextDisabled, 1, 1, 1, 1)
    ImGui.PushStyleColor(ImGuiCol.CheckMark, .5, 0, 0, 1)
    ImGui.PushStyleColor(ImGuiCol.Separator, .4, 0, 0, 1)
end

local function pop_styles()
    ImGui.PopStyleColor(13)
end

local MAUI = function()
    if not open and not miniSetupOpen then return end
    local used_theme = false
    if globals.Theme == 'red' then
        push_styles()
        used_theme = true
    end
    if open then
        open, shouldDrawUI = ImGui.Begin('MAUI (v'..globals.Version..')###MuleAssist', open)
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
            DrawWindowHeaderSettings()
            DrawWindowPanels()
        end
        ImGui.End()
    end
    DrawMiniSetupWindow()
    if used_theme then pop_styles() end
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
    local arg = tostring(args or ''):lower()
    if arg == 'show' then
        open = true
    elseif arg == 'hide' then
        open = false
        miniSetupOpen = false
    elseif arg == 'stop' then
        open = false
        terminate = true
    else
        ShowHelp()
    end
end

local function NewSpellMemmed(line, spell)
    print(string.format('\a-t[\ax\ayMAUI\ax\a-t]\ax New spell memorized, updating spell list. \a-t(\ax\ay%s\ax\a-t)\ax', spell))
    -- Build spell tree for picking spells
    local spellNum = mq.TLO.Me.Book(spell)()
    local bookSpell = spellNum and mq.TLO.Me.Book(spellNum) or nil
    if bookSpell and bookSpell() then
        AddSpellToMap(bookSpell)
    end

    SortMap(spells)
end

-- Load INI into table as well as raw content
globals.INIFile = globals.MAUI_Config['INIFile'] or utils.FindINIFile()
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
        local memName = (rankname and rankname ~= '' and rankname) or memspell
        mq.cmdf('/memspell %s "%s"', memgem, memName)
        local waitUntil = mq.gettime() + 8000
        while mq.gettime() < waitUntil do
            mq.doevents()
            local gem = mq.TLO.Me.Gem(memgem)
            if gem and gem() then
                local gname = SafeTLOCall(function() return gem.Name() end, '')
                if gname ~= '' and (gname == memName or gname == rankname) then break end
            end
            mq.delay(50)
        end
        local spellBookWnd = mq.TLO.Window('SpellBookWnd')
        if spellBookWnd and spellBookWnd() then spellBookWnd.DoClose() end
        memspell = nil
        memgem = 0
    end
    if mq.gettime() >= nextCachePruneAt then
        tloCache:clean()
        nextCachePruneAt = mq.gettime() + cachePruneIntervalMs
    end
    mq.delay(20)
end
