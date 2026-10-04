--[[
  UEQ Launcher — RmlUi

  Run:  /lua run ueqtool
  Stop: /lua stop ueqtool   or   /ueqlaunchquit
  Toggle panel: /ueqlauncher
--]]

local mq = require('mq')
local rmlui = require('rmlui')

local terminate = false
local startedAt = os.clock()
local CLICK_ARM_DELAY_SEC = 0.75
local launcherMainOpen = true
local launchedByBar = {}

local CATEGORY_ORDER = {
    'Core Tools',
    'Travel and Navigation',
    'Combat and Profiles',
    'Inventory and Loot',
    'Quests and References',
}

local CATEGORY_CLASS = {
    ['Core Tools'] = 'core',
    ['Travel and Navigation'] = 'travel',
    ['Combat and Profiles'] = 'combat',
    ['Inventory and Loot'] = 'loot',
    ['Quests and References'] = 'quests',
}

--- RmlUi targets for testing. Original ImGui spawn.lua is intentionally not on this bar.
local TOOLS = {
    { category = 'Core Tools', name = 'MAUI', module = 'maui', stopAliases = { 'maui', 'Maui' }, tip = 'Toggle MAUI' },
    { category = 'Quests and References', name = 'UltimateEQ', module = 'UltimateEQ', stopAliases = { 'UltimateEQ', 'ultimateeq', 'ProEQ', 'proeq' }, tip = 'Quest / hunter HUD (RmlUi)' },
    { category = 'Quests and References', name = 'God Tier', module = 'godtier', stopAliases = { 'godtier' }, tip = 'God Tier 71-75 + talents (RmlUi)' },
    { category = 'Core Tools', name = 'Teg HUD', module = 'teghud', stopAliases = { 'teghud', 'rmlhud' }, tip = 'Combat vitals HUD (RmlUi)' },
    { category = 'Core Tools', name = 'GM Console', module = 'gmconsole', stopAliases = { 'gmconsole' }, tip = 'GM command console (RmlUi)' },
    { category = 'Core Tools', name = 'EQUI', module = 'EQUI', stopAliases = { 'EQUI', 'equi' }, tip = 'Lua UI shell (ImGui — pending Rml port)' },
    { category = 'Core Tools', name = 'ZoneView', module = 'zoneview', stopAliases = { 'zoneview' }, tip = '3D zone explorer' },
    { category = 'Core Tools', name = 'Lua Console', module = 'luaconsole', stopAliases = { 'luaconsole', 'LuaConsole' }, tip = 'Toggle Lua Console' },
    { category = 'Travel and Navigation', name = 'Port', module = 'Port', stopAliases = { 'Port', 'port' }, tip = 'Toggle Port' },
    { category = 'Travel and Navigation', name = 'SpawnWatch', module = 'spawnrml', stopAliases = { 'spawnrml', 'spawn', 'Spawn' }, tip = 'SpawnWatch RmlUi (keep /lua run spawn for ImGui)' },
    { category = 'Combat and Profiles', name = 'Condition Builder', module = 'condition_builder', stopAliases = { 'condition_builder', 'ConditionBuilder' }, tip = 'Toggle Condition Builder' },
    { category = 'Combat and Profiles', name = 'Grouper', module = 'grouper', stopAliases = { 'grouper', 'Grouper' }, tip = 'Toggle Grouper' },
    { category = 'Combat and Profiles', name = 'LEM', module = 'lem', stopAliases = { 'lem', 'LEM' }, tip = 'Toggle LEM' },
    { category = 'Combat and Profiles', name = 'ButtonMaster', module = 'buttonmaster', stopAliases = { 'buttonmaster', 'ButtonMaster' }, tip = 'Toggle ButtonMaster' },
    { category = 'Inventory and Loot', name = 'EZInventory', module = 'ezinventory', stopAliases = { 'ezinventory', 'EZInventory' }, tip = 'Toggle EZInventory' },
    { category = 'Inventory and Loot', name = 'SmartLoot', module = 'smartloot', stopAliases = { 'smartloot', 'SmartLoot' }, tip = 'Toggle SmartLoot' },
    { category = 'Inventory and Loot', name = 'Transmute', module = 'Transmute', stopAliases = { 'Transmute', 'transmute' }, tip = 'Toggle Transmute' },
    { category = 'Inventory and Loot', name = 'Ultimate EQ Credit', module = 'ueqcredit', stopAliases = { 'ueqcredit' }, tip = 'Toggle Ultimate EQ Credit' },
    { category = 'Inventory and Loot', name = 'AutoAug', module = 'autoaug', stopAliases = { 'autoaug', 'AutoAug' }, tip = 'Toggle AutoAug' },
    { category = 'Inventory and Loot', name = 'GearScoreX', module = 'GearScoreX', stopAliases = { 'GearScoreX', 'gearscorex' }, tip = 'Toggle GearScoreX' },
    { category = 'Quests and References', name = 'EZQuests', module = 'ezquests', stopAliases = { 'ezquests', 'EZQuests' }, tip = 'Toggle EZQuests' },
    { category = 'Quests and References', name = 'Mini Wiki', module = 'ulti', stopAliases = { 'ulti' }, tip = 'Toggle Mini Wiki (ulti)' },
    { category = 'Core Tools', name = 'ulteqtool', module = 'ulteqtool', stopAliases = { 'ulteqtool' }, tip = 'Toggle ulteqtool' },
    { category = 'Core Tools', name = 'Expr Evaluator', module = 'expression_evaluator', stopAliases = { 'expression_evaluator', 'ExpressionEvaluator' }, tip = 'Toggle expression evaluator' },
}

local function key(s)
    return tostring(s or ''):lower():gsub('^%s+', ''):gsub('%s+$', '')
end

local function norm(p)
    return tostring(p or ''):gsub('\\', '/')
end

local function fileExists(path)
    local f = io.open(path, 'rb')
    if not f then return false end
    f:close()
    return true
end

local function luaScriptStatusUpper(name)
    local ok, st = pcall(function()
        local s = mq.TLO.Lua.Script(name)
        if not s or not s() then return '' end
        local v = s.Status()
        if v == nil then return '' end
        return tostring(v):upper():gsub('^%s+', ''):gsub('%s+$', '')
    end)
    if not ok or not st then return '' end
    return st
end

local function scriptNameIsRunning(name)
    local st = luaScriptStatusUpper(name)
    if st == '' or st == 'NULL' then return false end
    return st == 'RUNNING' or st == 'PAUSED'
end

local function moduleIsRunning(entry)
    if scriptNameIsRunning(entry.module) then return true end
    for _, alias in ipairs(entry.stopAliases or {}) do
        if scriptNameIsRunning(alias) then return true end
    end
    return false
end

local function stopModule(entry, force)
    local tried = {}
    local function stopName(n)
        n = tostring(n or '')
        if n == '' or tried[n] then return end
        tried[n] = true
        if force or scriptNameIsRunning(n) then
            mq.cmdf('/lua stop %s', n)
        end
    end
    stopName(entry.module)
    for _, alias in ipairs(entry.stopAliases or {}) do
        stopName(alias)
    end
end

local function toggleModule(entry)
    if not entry or not entry.module or entry.module == '' then return end
    local k = key(entry.module)
    local runningNow = moduleIsRunning(entry)
    if runningNow or launchedByBar[k] then
        stopModule(entry, launchedByBar[k] == true)
        launchedByBar[k] = false
    else
        mq.cmdf('/lua run %s', entry.module)
        launchedByBar[k] = true
    end
end

local ENTRIES = {}
local ENTRIES_BY_CATEGORY = {}
local ENTRY_BY_MODULE = {}

do
    local seen = {}
    for _, t in ipairs(TOOLS) do
        local mkey = key(t.module)
        if mkey ~= '' and not seen[mkey] then
            seen[mkey] = true
            local entry = {
                category = t.category or 'Misc',
                name = t.name or t.module,
                module = t.module,
                stopAliases = t.stopAliases,
                tip = t.tip,
            }
            ENTRIES[#ENTRIES + 1] = entry
            ENTRY_BY_MODULE[mkey] = entry
            local cat = entry.category
            ENTRIES_BY_CATEGORY[cat] = ENTRIES_BY_CATEGORY[cat] or {}
            ENTRIES_BY_CATEGORY[cat][#ENTRIES_BY_CATEGORY[cat] + 1] = entry
        end
    end

    local function luaScriptOnDisk(name)
        local n = tostring(name or '')
        if n == '' then return true end
        local root = norm(mq.luaDir) .. '/' .. n
        return fileExists(root .. '.lua') or fileExists(root .. '/init.lua')
    end
    for _, t in ipairs(TOOLS) do
        if t.module and not luaScriptOnDisk(t.module) then
            mq.cmdf(
                '/echo \ar[UEQ Launcher]\ax Missing Lua file for \ay%s\ax — copy into \ay%s\ax',
                tostring(t.module),
                tostring(norm(mq.luaDir))
            )
        end
    end
end

local UI = { win = nil, slots_sig = '', next_update = 0 }

local function esc(s)
    return tostring(s or ''):gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;'):gsub('"', '&quot;')
end

local function build_cats_rml()
    local parts = {}
    for _, cat in ipairs(CATEGORY_ORDER) do
        local rows = ENTRIES_BY_CATEGORY[cat]
        if rows and #rows > 0 then
            local cls = CATEGORY_CLASS[cat] or 'core'
            parts[#parts + 1] = '<div class="cat ' .. cls .. '">'
            parts[#parts + 1] = '<div class="cat-head"><div class="cat-accent"></div>'
            parts[#parts + 1] = '<div class="cat-title">' .. esc(cat) .. '</div><div class="cat-line"></div></div>'
            parts[#parts + 1] = '<div class="grid">'
            for _, e in ipairs(rows) do
                local mid = esc(e.module)
                parts[#parts + 1] = string.format(
                    '<div id="tool_%s" class="tool" action="run:%s" title="%s"><div class="tool-name">%s</div><div id="st_%s" class="tool-state">stopped</div></div>',
                    mid, mid, esc(e.tip or e.name), esc(e.name), mid
                )
            end
            parts[#parts + 1] = '</div></div>'
        end
    end
    return table.concat(parts)
end

local function update_ui()
    local win = UI.win
    if not win then return end

    local remain = CLICK_ARM_DELAY_SEC - (os.clock() - startedAt)
    local arming = remain > 0
    win:class('arm_banner', 'show', arming)
    if arming then
        win:text('arm_txt', string.format('Launcher arming… %.1fs', remain))
    end

    local running = 0
    for _, e in ipairs(ENTRIES) do
        local on = moduleIsRunning(e)
        if on then running = running + 1 end
        local mid = e.module
        win:class('tool_' .. mid, 'on', on)
        win:text('st_' .. mid, on and 'running' or 'stopped')
    end
    win:text('st_run', running)
    win:text('st_tools', #ENTRIES)
    win:text('hero_sub', arming and 'Clicks armed after delay' or 'Click a tool to toggle it on or off')
end

local function handle(ev)
    if ev.type ~= 'click' then return end
    local a = ev.action or ''
    if a == 'window:close' then
        launcherMainOpen = false
        return
    end
    if a == 'quit' then
        terminate = true
        return
    end
    local mod = a:match('^run:(.+)$')
    if mod then
        if (os.clock() - startedAt) < CLICK_ARM_DELAY_SEC then return end
        local entry = ENTRY_BY_MODULE[key(mod)]
        if entry then toggleModule(entry) end
        UI.next_update = 0
    end
end

local function tick()
    if not UI.win then
        local win, err = rmlui.open('UEQLauncher', 'ueqtool/ui/launcher.rml', {
            width = 720, height = 780, autoclose = true,
        })
        if not win then
            print('[UEQ Launcher] RmlUi failed: ' .. tostring(err))
            terminate = true
            return
        end
        UI.win = win
        win:rml('cats', build_cats_rml())
        UI.slots_sig = 'built'
    end

    local win = UI.win
    if not win:is_open() then
        launcherMainOpen = false
    end
    win:show(launcherMainOpen)

    for ev in win:events() do
        local ok, herr = pcall(handle, ev)
        if not ok then print('[UEQ Launcher] event error: ' .. tostring(herr)) end
    end

    local now = mq.gettime and mq.gettime() or (os.clock() * 1000)
    if launcherMainOpen and now >= UI.next_update then
        UI.next_update = now + 250
        local oku, uerr = pcall(update_ui)
        if not oku then
            print('[UEQ Launcher] update error: ' .. tostring(uerr))
            UI.next_update = now + 1000
        end
    end
end

mq.bind('/ueqlaunchquit', function() terminate = true end)
mq.bind('/ueqlauncher', function()
    launcherMainOpen = not launcherMainOpen
    if UI.win then UI.win:show(launcherMainOpen) end
end)

-- Tear down any leftover ImGui launcher IDs from older builds.
pcall(function() mq.imgui.destroy('ueq_launcher_stable') end)
pcall(function() mq.imgui.destroy('ueq_launcher_singleitem') end)
pcall(function() mq.imgui.destroy('ueq_launcher_clean') end)
pcall(function() mq.imgui.destroy('ueq_launcher_bar_v2') end)
pcall(function() mq.imgui.destroy('ueq_launcher_bar') end)
pcall(function() mq.imgui.destroy('ueqtool') end)
pcall(function() mq.imgui.destroy('UEQ_Launcher') end)

print('[UEQ Launcher] RmlUi launcher loaded. /ueqlauncher toggles panel. /ueqlaunchquit unloads.')
print('[UEQ Launcher] Rml tools: UltimateEQ, godtier, teghud/rmlhud, gmconsole, spawnrml. ImGui spawn.lua kept as /lua run spawn.')

local function cleanup()
    pcall(function() rmlui.close_all() end)
    pcall(function() mq.unbind('/ueqlaunchquit') end)
    pcall(function() mq.unbind('/ueqlauncher') end)
    print('[UEQ Launcher] Exited.')
end

local ok, err = pcall(function()
    while not terminate do
        local tok, terr = pcall(tick)
        if not tok then
            print('[UEQ Launcher] tick error: ' .. tostring(terr))
            mq.delay(500)
        else
            mq.delay(50)
        end
    end
end)
if not ok and err then print('[UEQ Launcher] stop: ' .. tostring(err)) end
cleanup()
