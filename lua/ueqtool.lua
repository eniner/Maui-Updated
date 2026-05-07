--[[
  UEQ Launcher - stable fixed bar
  5 fixed icon slots, equal spacing, direct image-item click.

  Run:  /lua run ueqtool
  Stop: /lua stop ueqtool
--]]

local mq = require('mq')
local imgui = require('ImGui')

local SCRIPT_ID = 'ueq_launcher_stable'
local terminate = false
local startedAt = os.clock()
local CLICK_ARM_DELAY_SEC = 0.75

local ICON_SIZE = 56
local ICON_GAP = 4
local launchedByBar = {}
local CATEGORY_ORDER = {
    'Core Tools',
    'Travel and Navigation',
    'Combat and Profiles',
    'Inventory and Loot',
    'Quests and References',
}

-- Mirror UltimateEQ push_spawnmaster_theme() styling for launcher consistency.
local function pushUltimateEqTheme()
    local pv, pc = 0, 0
    local function sv(var, ...)
        imgui.PushStyleVar(var, ...)
        pv = pv + 1
    end
    local function sc(col, ...)
        imgui.PushStyleColor(col, ...)
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

local function popUltimateEqTheme(pv, pc)
    if pc and pc > 0 then imgui.PopStyleColor(pc) end
    if pv and pv > 0 then imgui.PopStyleVar(pv) end
end

local TOOLS = {
    { category = 'Core Tools', name = 'MAUI', module = 'maui', stopAliases = { 'maui', 'Maui' }, icon = 'ueqtool_icons/maui.png', tip = 'Toggle MAUI' },
    { category = 'Quests and References', name = 'UltimateEQ', module = 'UltimateEQ', stopAliases = { 'UltimateEQ', 'ultimateeq' }, icon = 'ueqtool_icons/ultimateeq.png', tip = 'Toggle UltimateEQ' },
    { category = 'Core Tools', name = 'Lua Console', module = 'luaconsole', stopAliases = { 'luaconsole', 'LuaConsole' }, icon = 'ueqtool_icons/luaconsole.png', tip = 'Toggle Lua Console' },
    { category = 'Travel and Navigation', name = 'Port', module = 'Port', stopAliases = { 'Port', 'port' }, icon = 'ueqtool_icons/port.png', tip = 'Toggle Port' },
    { category = 'Travel and Navigation', name = 'Spawn', module = 'spawn', stopAliases = { 'spawn', 'Spawn' }, icon = 'ueqtool_icons/spawn.png', tip = 'Toggle Spawn' },
    { category = 'Combat and Profiles', name = 'Condition Builder', module = 'condition_builder', stopAliases = { 'condition_builder', 'ConditionBuilder' }, icon = 'ueqtool_icons/conditionbuilder.png', tip = 'Toggle Condition Builder' },
    { category = 'Combat and Profiles', name = 'Grouper', module = 'grouper', stopAliases = { 'grouper', 'Grouper' }, icon = 'ueqtool_icons/grouper.png', tip = 'Toggle Grouper' },
    { category = 'Combat and Profiles', name = 'LEM', module = 'lem', stopAliases = { 'lem', 'LEM' }, icon = 'ueqtool_icons/lem.png', tip = 'Toggle LEM' },
    { category = 'Combat and Profiles', name = 'ButtonMaster', module = 'buttonmaster', stopAliases = { 'buttonmaster', 'ButtonMaster' }, icon = 'ueqtool_icons/buttonmaster.png', tip = 'Toggle ButtonMaster' },
    { category = 'Inventory and Loot', name = 'EZInventory', module = 'ezinventory', stopAliases = { 'ezinventory', 'EZInventory' }, icon = 'ueqtool_icons/ezinventory.png', tip = 'Toggle EZInventory' },
    { category = 'Inventory and Loot', name = 'SmartLoot', module = 'smartloot', stopAliases = { 'smartloot', 'SmartLoot' }, icon = 'ueqtool_icons/smartloot.png', tip = 'Toggle SmartLoot' },
    { category = 'Inventory and Loot', name = 'Transmute', module = 'Transmute', stopAliases = { 'Transmute', 'transmute' }, icon = 'ueqtool_icons/transmute.png', tip = 'Toggle Transmute' },
    { category = 'Inventory and Loot', name = 'AutoAug', module = 'autoaug', stopAliases = { 'autoaug', 'AutoAug' }, icon = 'ueqtool_icons/autoaug.png', tip = 'Toggle AutoAug' },
    { category = 'Quests and References', name = 'EZQuests', module = 'ezquests', stopAliases = { 'ezquests', 'EZQuests' }, icon = 'ueqtool_icons/ezquests.png', tip = 'Toggle EZQuests' },
    { category = 'Quests and References', name = 'Mini Wiki', module = 'ulti', stopAliases = { 'ulti' }, icon = 'ueqtool_icons/miniwiki.png', tip = 'Toggle Mini Wiki (ulti)' },
}

local function norm(p)
    return tostring(p or ''):gsub('\\', '/')
end

local function key(s)
    return tostring(s or ''):lower():gsub('^%s+', ''):gsub('%s+$', '')
end

local function fileExists(path)
    local f = io.open(path, 'rb')
    if not f then return false end
    f:close()
    return true
end

local function loadTexture(rel)
    if not mq.CreateTexture then
        return nil, 'CreateTexture unavailable'
    end

    local cleanRel = norm(rel):gsub('^/+', '')
    if cleanRel == '' then
        return nil, 'empty icon path'
    end

    local full = norm(mq.luaDir) .. '/' .. cleanRel
    if not fileExists(full) then
        return nil, 'missing file: ' .. full
    end

    local ok, tex = pcall(mq.CreateTexture, full)
    if not ok or not tex or type(tex.GetTextureID) ~= 'function' then
        return nil, 'CreateTexture failed: ' .. full
    end

    local okId, tid = pcall(function() return tex:GetTextureID() end)
    if not okId or tid == nil or (type(tid) == 'number' and tid == 0) then
        return nil, 'invalid texture id: ' .. full
    end

    return tex
end

local function buildEntries()
    local out = {}
    local seen = {}

    for _, t in ipairs(TOOLS) do
        local mkey = key(t.module)
        if mkey ~= '' and not seen[mkey] then
            seen[mkey] = true
            local tex, err = loadTexture(t.icon)
            if tex then
                local texSize = tex.size
                local w = tonumber(texSize and texSize.x) or ICON_SIZE
                local h = tonumber(texSize and texSize.y) or ICON_SIZE
                if w <= 0 then w = ICON_SIZE end
                if h <= 0 then h = ICON_SIZE end
                local scale = ICON_SIZE / math.max(w, h)
                out[#out + 1] = {
                    category = t.category or 'Misc',
                    name = t.name or t.module,
                    module = t.module,
                    stopAliases = t.stopAliases,
                    tip = t.tip,
                    tex = tex,
                    drawW = math.floor(w * scale + 0.5),
                    drawH = math.floor(h * scale + 0.5),
                }
            else
                mq.cmdf('/echo \ar[UEQ Launcher]\ax Skipping %s (%s)', tostring(t.name or t.module), tostring(err))
            end
        end
    end

    return out
end

local ENTRIES = buildEntries()
local ENTRIES_BY_CATEGORY = {}
for _, c in ipairs(CATEGORY_ORDER) do
    ENTRIES_BY_CATEGORY[c] = {}
end
for _, e in ipairs(ENTRIES) do
    local c = e.category or 'Misc'
    if not ENTRIES_BY_CATEGORY[c] then
        ENTRIES_BY_CATEGORY[c] = {}
    end
    table.insert(ENTRIES_BY_CATEGORY[c], e)
end

local function scriptNameIsRunning(name)
    local m = tostring(name or '')
    if m == '' then return false end
    local ok, running = pcall(function()
        local s = mq.TLO.Lua.Script(m)
        if not s or not s() then
            return false
        end
        local st = s.Status()
        if not st then
            return false
        end
        st = tostring(st)
        return st ~= '' and st ~= 'NULL'
    end)
    if not ok then
        return false
    end
    return running == true
end

local function moduleIsRunning(entry)
    if scriptNameIsRunning(entry.module) then
        return true
    end
    for _, alias in ipairs(entry.stopAliases or {}) do
        if scriptNameIsRunning(alias) then
            return true
        end
    end
    return false
end

local function stopModule(entry, force)
    local stopped = false
    local tried = {}
    local function stopName(n)
        n = tostring(n or '')
        if n == '' or tried[n] then return end
        tried[n] = true
        if force or scriptNameIsRunning(n) then
            mq.cmdf('/lua stop %s', n)
            stopped = true
        end
    end
    stopName(entry.module)
    for _, alias in ipairs(entry.stopAliases or {}) do
        stopName(alias)
    end
    return stopped
end

local function toggleModule(entry)
    if entry and entry.module and entry.module ~= '' then
        local k = key(entry.module)
        local runningNow = moduleIsRunning(entry)
        if runningNow or launchedByBar[k] then
            -- Force-stop primary name on second click if we launched it,
            -- even when script status detection is unreliable on some MQ builds.
            stopModule(entry, launchedByBar[k] == true)
            launchedByBar[k] = false
        else
            mq.cmdf('/lua run %s', entry.module)
            launchedByBar[k] = true
        end
    end
end

local function drawIcon(entry)
    local okTid, tid = pcall(function() return entry.tex:GetTextureID() end)
    if not okTid or tid == nil then return end

    imgui.PushStyleVar(ImGuiStyleVar.FramePadding, 0, 0)
    imgui.PushStyleColor(ImGuiCol.Button, 0.18, 0.06, 0.26, 1.00)
    imgui.PushStyleColor(ImGuiCol.ButtonHovered, 0.36, 0.09, 0.44, 1.00)
    imgui.PushStyleColor(ImGuiCol.ButtonActive, 0.50, 0.12, 0.58, 1.00)

    local clicked = imgui.ImageButton(
        '##iconbtn',
        tid,
        ImVec2(entry.drawW or ICON_SIZE, entry.drawH or ICON_SIZE),
        ImVec2(0, 0),
        ImVec2(1, 1),
        ImVec4(0.10, 0.04, 0.16, 1.00),
        ImVec4(1, 1, 1, 1)
    )

    imgui.PopStyleColor(3)
    imgui.PopStyleVar()

    local clicksArmed = (os.clock() - startedAt) >= CLICK_ARM_DELAY_SEC
    if clicked and clicksArmed then
        toggleModule(entry)
    end
    if entry.tip and imgui.IsItemHovered() then
        local state = (moduleIsRunning(entry) or launchedByBar[key(entry.module)] == true) and 'running' or 'stopped'
        imgui.SetTooltip(string.format('%s (%s)', entry.tip, state))
    end
end

local function drawWindow()
    local maxRowW = 280
    local sectionCount = 0
    for _, cat in ipairs(CATEGORY_ORDER) do
        local rows = ENTRIES_BY_CATEGORY[cat] or {}
        if #rows > 0 then
            sectionCount = sectionCount + 1
            local rowW = math.max(0, #rows - 1) * ICON_GAP
            for _, e in ipairs(rows) do
                rowW = rowW + (tonumber(e.drawW) or ICON_SIZE)
            end
            if rowW > maxRowW then
                maxRowW = rowW
            end
        end
    end

    local pv, pc = pushUltimateEqTheme()
    imgui.SetNextWindowBgAlpha(0.95)
    local winW = math.min(1280, math.max(420, maxRowW + 180))
    local winH = math.max(210, 105 + sectionCount * 96)
    imgui.SetNextWindowSize(winW, winH, ImGuiCond.FirstUseEver)
    local visible = imgui.Begin('Ultimate EQ - launcher##UEQ_Launcher_Stable', true, ImGuiWindowFlags.NoCollapse)
    if not visible then
        imgui.End()
        popUltimateEqTheme(pv, pc)
        return
    end

    imgui.TextWrapped('Click an icon to toggle that module on/off.')
    local remain = CLICK_ARM_DELAY_SEC - (os.clock() - startedAt)
    if remain > 0 then
        imgui.TextColored(0.90, 0.75, 0.35, 1.0, string.format('Launcher arming... %.1fs', remain))
    end
    imgui.Separator()

    if #ENTRIES == 0 then
        imgui.TextColored(1.0, 0.55, 0.45, 1.0, 'No valid launcher icons loaded.')
    else
        for _, cat in ipairs(CATEGORY_ORDER) do
            local rows = ENTRIES_BY_CATEGORY[cat] or {}
            if #rows > 0 then
                imgui.PushStyleColor(ImGuiCol.Text, 0.22, 0.90, 0.84, 1.0)
                imgui.Text(cat)
                imgui.PopStyleColor()
                imgui.BeginChild('cat_' .. cat, 0, ICON_SIZE + 12, true)
                for i, entry in ipairs(rows) do
                    imgui.PushID(cat .. '_icon_' .. i)
                    drawIcon(entry)
                    imgui.PopID()
                    if i < #rows then imgui.SameLine(0, ICON_GAP) end
                end
                imgui.EndChild()
            end
        end
    end

    if imgui.Button('Quit launcher##quit') then
        terminate = true
    end
    imgui.SameLine()
    imgui.TextColored(0.55, 0.58, 0.62, 1.0, '/lua stop ueqtool')

    imgui.End()
    popUltimateEqTheme(pv, pc)
end

mq.bind('/ueqlaunchquit', function() terminate = true end)

pcall(function() mq.imgui.destroy('ueq_launcher_stable') end)
pcall(function() mq.imgui.destroy('ueq_launcher_singleitem') end)
pcall(function() mq.imgui.destroy('ueq_launcher_clean') end)
pcall(function() mq.imgui.destroy('ueq_launcher_bar_v2') end)
pcall(function() mq.imgui.destroy('ueq_launcher_bar') end)
pcall(function() mq.imgui.destroy('ueqtool') end)
pcall(function() mq.imgui.destroy('UEQ_Launcher') end)
pcall(function() mq.cmd('/lua stop ueq_launcher_bar') end)
pcall(function() mq.cmd('/lua stop ueq_launcher_bar_v2') end)

mq.imgui.init(SCRIPT_ID, drawWindow)
mq.cmd('/echo \ag[UEQ Launcher]\ax Stable launcher loaded. /ueqlaunchquit to unload.')

while not terminate do
    mq.delay(50)
end

pcall(function() mq.imgui.destroy(SCRIPT_ID) end)
pcall(function() mq.unbind('/ueqlaunchquit') end)
