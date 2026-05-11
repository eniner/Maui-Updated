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

local ICON_SIZE = 88
local LAUNCHER_TOGGLE_REL = 'ueqtool_icons/launcher_toggle.png'
--- Tall launcher art: scale by longest edge (not a square cell) so the FAB isn’t a tiny strip with empty padding.
local TOGGLE_FAB_MAX_EDGE = 132
local launcherMainOpen = true
local fabWindowOpen = true
local toggleTex = nil
local toggleLoadFailed = false
local toggleAspectW = ICON_SIZE
local toggleAspectH = ICON_SIZE
local ICON_GAP = 6
local CATEGORY_CHILD_PAD_X = 12
local CATEGORY_CHILD_PAD_Y = 12
--- Vertical space reserved per section for slim divider + accent bar + category title (visual layout).
local CATEGORY_LABEL_H = 40
local CATEGORY_HEADER_ROW_H = 20
local ROW_WRAP_MAX = 8192
local launchedByBar = {}
local CATEGORY_ORDER = {
    'Core Tools',
    'Travel and Navigation',
    'Combat and Profiles',
    'Inventory and Loot',
    'Quests and References',
}

--- Per-category accent (RGB 0–1) for headers, active indicator, and button hover/active tint.
local CATEGORY_ACCENTS = {
    ['Core Tools'] = { 79 / 255, 156 / 255, 249 / 255 },
    ['Travel and Navigation'] = { 52 / 255, 211 / 255, 153 / 255 },
    ['Combat and Profiles'] = { 248 / 255, 113 / 255, 113 / 255 },
    ['Inventory and Loot'] = { 251 / 255, 191 / 255, 36 / 255 },
    ['Quests and References'] = { 167 / 255, 139 / 255, 250 / 255 },
}

local function getCategoryAccent(cat)
    local t = CATEGORY_ACCENTS[cat]
    if t then
        return t[1], t[2], t[3]
    end
    return 0.55, 0.58, 0.62
end

--- Slate chrome (#0f1117). Child rows use their own ChildBg push (#13151f).
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

    sv(ImGuiStyleVar.WindowRounding, 8)
    sv(ImGuiStyleVar.FrameRounding, 8)
    sv(ImGuiStyleVar.FrameBorderSize, 1)
    sv(ImGuiStyleVar.WindowPadding, 10, 10)
    sv(ImGuiStyleVar.ItemSpacing, 8, 8)

    local slate = { 15 / 255, 17 / 255, 23 / 255, 1 }
    sc(ImGuiCol.WindowBg, slate[1], slate[2], slate[3], slate[4])
    sc(ImGuiCol.ChildBg, slate[1], slate[2], slate[3], slate[4])
    sc(ImGuiCol.PopupBg, slate[1], slate[2], slate[3], slate[4])
    sc(ImGuiCol.TitleBg, 18 / 255, 20 / 255, 26 / 255, 1)
    sc(ImGuiCol.TitleBgActive, 22 / 255, 24 / 255, 31 / 255, 1)
    sc(ImGuiCol.Border, 42 / 255, 45 / 255, 58 / 255, 1)
    sc(ImGuiCol.Separator, 38 / 255, 41 / 255, 52 / 255, 0.85)
    sc(ImGuiCol.Text, 0.78, 0.80, 0.84, 1.0)

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
    { category = 'Inventory and Loot', name = 'Ultimate EQ Credit', module = 'ueqcredit', stopAliases = { 'ueqcredit' }, icon = 'ueqtool_icons/ueqcredit.png', tip = 'Toggle Ultimate EQ Credit' },
    { category = 'Inventory and Loot', name = 'AutoAug', module = 'autoaug', stopAliases = { 'autoaug', 'AutoAug' }, icon = 'ueqtool_icons/autoaug.png', tip = 'Toggle AutoAug' },
    { category = 'Inventory and Loot', name = 'Ultimate EQ GearScore', module = 'GearScoreX', stopAliases = { 'GearScoreX', 'gearscorex' }, icon = 'ueqtool_icons/gearscorex.png', tip = 'Toggle GearScoreX' },
    { category = 'Quests and References', name = 'EZQuests', module = 'ezquests', stopAliases = { 'ezquests', 'EZQuests' }, icon = 'ueqtool_icons/ezquests.png', tip = 'Toggle EZQuests' },
    { category = 'Quests and References', name = 'Mini Wiki', module = 'ulti', stopAliases = { 'ulti' }, icon = 'ueqtool_icons/miniwiki.png', tip = 'Toggle Mini Wiki (ulti)' },
    { category = 'Core Tools', name = 'ulteqtool', module = 'ulteqtool', stopAliases = { 'ulteqtool' }, icon = 'ueqtool_icons/ulteqtool.png', tip = 'Toggle ulteqtool' },
    { category = 'Core Tools', name = 'Ultimate EQ Exprevaluator', module = 'expression_evaluator', stopAliases = { 'expression_evaluator', 'ExpressionEvaluator' }, icon = 'ueqtool_icons/expression_evaluator.png', tip = 'Toggle Ultimate EQ Exprevaluator' },
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

local function readPngDimensions(fullPath)
    local f = io.open(norm(fullPath), 'rb')
    if not f then
        return 0, 0
    end
    local sig = f:read(8)
    if not sig or #sig ~= 8 or sig ~= '\137PNG\r\n\26\n' then
        f:close()
        return 0, 0
    end
    while true do
        local lenB = f:read(4)
        if not lenB or #lenB ~= 4 then
            break
        end
        local chunkLen =
            (((lenB:byte(1) * 256 + lenB:byte(2)) * 256 + lenB:byte(3)) * 256 + lenB:byte(4))
        local ctype = f:read(4)
        if not ctype or #ctype ~= 4 then
            break
        end
        if ctype == 'IHDR' and chunkLen >= 13 then
            local d = f:read(13)
            f:close()
            if d and #d == 13 then
                local w = (((d:byte(1) * 256 + d:byte(2)) * 256 + d:byte(3)) * 256 + d:byte(4))
                local h = (((d:byte(5) * 256 + d:byte(6)) * 256 + d:byte(7)) * 256 + d:byte(8))
                return w, h
            end
            return 0, 0
        end
        if not pcall(function()
            f:seek('cur', chunkLen + 4)
        end) then
            break
        end
    end
    f:close()
    return 0, 0
end

local function resolveToolIconFullPath(rel)
    local cleanRel = norm(rel):gsub('^/+', '')
    if cleanRel == '' then
        return nil
    end
    local base = cleanRel:match('([^/]+)$') or cleanRel
    local luaPath = norm(mq.luaDir) .. '/' .. cleanRel
    local prof = norm(os.getenv('USERPROFILE') or '')
    local deskPath = (prof ~= '') and (prof .. '/Desktop/ulttool/' .. base) or ''
    if deskPath ~= '' and fileExists(deskPath) then
        return deskPath
    end
    if fileExists(luaPath) then
        return luaPath
    end
    return nil
end

--- Must appear before drawLauncherToggleFab / drawIcon (Lua 5.1 local forward refs are nil).
local function asVecXY(v1, v2)
    if type(v1) == 'number' then
        return v1, v2 or 0
    end
    if type(v1) == 'table' then
        return tonumber(v1.x or v1.X or v1[1]) or 0, tonumber(v1.y or v1.Y or v1[2]) or 0
    end
    return 0, 0
end

--- MQ ImGui may return width as a number or as an ImVec2-like table (see GearScoreX.lua).
local function contentRegionAvailW()
    local w, _h = imgui.GetContentRegionAvail()
    if type(w) == 'number' then
        return w
    end
    if type(w) == 'table' then
        return tonumber(w.x or w.X or w[1]) or 400
    end
    return 400
end

local function ensureLauncherToggleTexture()
    if toggleTex or toggleLoadFailed or not mq.CreateTexture then
        return
    end
    local full = resolveToolIconFullPath(LAUNCHER_TOGGLE_REL)
    if not full then
        toggleLoadFailed = true
        return
    end
    local pw, ph = readPngDimensions(full)
    if pw >= 1 and ph >= 1 then
        toggleAspectW = pw
        toggleAspectH = ph
    end
    local ok, tex = pcall(mq.CreateTexture, full)
    if ok and tex and type(tex.GetTextureID) == 'function' then
        local okId, tid = pcall(function() return tex:GetTextureID() end)
        if okId and tid ~= nil and not (type(tid) == 'number' and tid == 0) then
            toggleTex = tex
            return
        end
    end
    toggleLoadFailed = true
end

local function drawLauncherToggleFab()
    ensureLauncherToggleTexture()
    imgui.SetNextWindowBgAlpha(0.0)
    imgui.SetNextWindowPos(16, 120, ImGuiCond.FirstUseEver)
    local Wf = ImGuiWindowFlags
    local fabFlags = Wf.NoDecoration + Wf.AlwaysAutoResize + Wf.NoNav + Wf.NoFocusOnAppearing
    if Wf.NoBackground then
        fabFlags = fabFlags + Wf.NoBackground
    end
    local pvFab = 0
    local function svFab(var, ...)
        imgui.PushStyleVar(var, ...)
        pvFab = pvFab + 1
    end
    svFab(ImGuiStyleVar.WindowPadding, 0, 0)
    svFab(ImGuiStyleVar.WindowBorderSize, 0)
    svFab(ImGuiStyleVar.ItemSpacing, 0, 0)
    svFab(ImGuiStyleVar.FramePadding, 0, 0)
    local fabDraw
    fabWindowOpen, fabDraw = imgui.Begin('UEQ Launcher##fab_toggle', fabWindowOpen, fabFlags)
    if fabDraw then
        local texW = tonumber(toggleAspectW) or 100
        local texH = tonumber(toggleAspectH) or 100
        if texW < 1 or texH < 1 then
            texW, texH = 100, 100
        end
        local maxEdge = TOGGLE_FAB_MAX_EDGE
        local scale = maxEdge / math.max(texW, texH)
        local dw = math.max(1, math.floor(texW * scale + 0.5))
        local dh = math.max(1, math.floor(texH * scale + 0.5))

        imgui.InvisibleButton('##launcher_fab_hit', dw, dh)
        local clickedFab = imgui.IsItemClicked(0)
        local minX, minY = asVecXY(imgui.GetItemRectMin())
        local dlFab = imgui.GetWindowDrawList()
        if toggleTex then
            local okTid, tid = pcall(function() return toggleTex:GetTextureID() end)
            if okTid and tid ~= nil and dlFab and dlFab.AddImage then
                pcall(function()
                    dlFab:AddImage(tid, ImVec2(minX, minY), ImVec2(minX + dw, minY + dh), ImVec2(0, 0), ImVec2(1, 1))
                end)
            end
        elseif dlFab and dlFab.AddRectFilled then
            pcall(function()
                dlFab:AddRectFilled(
                    ImVec2(minX, minY),
                    ImVec2(minX + dw, minY + dh),
                    imgui.GetColorU32(0.22, 0.07, 0.32, 0.95)
                )
            end)
        end
        local armed = (os.clock() - startedAt) >= CLICK_ARM_DELAY_SEC
        if clickedFab and armed then
            launcherMainOpen = not launcherMainOpen
        end
        if imgui.IsItemHovered() then
            imgui.SetTooltip(launcherMainOpen and 'Hide Ultimate EQ launcher panel' or 'Show Ultimate EQ launcher panel')
        end
    end
    imgui.End()
    if pvFab > 0 then
        imgui.PopStyleVar(pvFab)
    end
end

local function loadTexture(rel)
    if not mq.CreateTexture then
        return nil, 'CreateTexture unavailable'
    end

    local cleanRel = norm(rel):gsub('^/+', '')
    if cleanRel == '' then
        return nil, 'empty icon path'
    end

    local base = cleanRel:match('([^/]+)$') or cleanRel
    local luaPath = norm(mq.luaDir) .. '/' .. cleanRel
    local prof = norm(os.getenv('USERPROFILE') or '')
    local deskPath = (prof ~= '') and (prof .. '/Desktop/ulttool/' .. base) or ''

    local full = nil
    if deskPath ~= '' and fileExists(deskPath) then
        full = deskPath
    elseif fileExists(luaPath) then
        full = luaPath
    else
        return nil, 'missing file (Desktop/ulttool/' .. base .. ' or ' .. luaPath .. ')'
    end

    local ok, tex = pcall(mq.CreateTexture, full)
    if not ok or not tex or type(tex.GetTextureID) ~= 'function' then
        return nil, 'CreateTexture failed: ' .. full
    end

    local okId, tid = pcall(function() return tex:GetTextureID() end)
    if not okId or tid == nil or (type(tid) == 'number' and tid == 0) then
        return nil, 'invalid texture id: ' .. full
    end

    return tex, nil, full
end

local function buildEntries()
    local out = {}
    local seen = {}

    local function texPixelSizeProbe(tex)
        local s = tex and tex.size
        if not s then
            return 0, 0
        end
        local w = tonumber(s.x or s.X or (type(s) == 'table' and s[1])) or 0
        local h = tonumber(s.y or s.Y or (type(s) == 'table' and s[2])) or 0
        return w, h
    end

    for _, t in ipairs(TOOLS) do
        local mkey = key(t.module)
        if mkey ~= '' and not seen[mkey] then
            seen[mkey] = true
            local tex, err, resolvedPath = loadTexture(t.icon)
            if tex then
                local pw, ph = readPngDimensions(resolvedPath or '')
                if pw < 1 or ph < 1 then
                    pw, ph = texPixelSizeProbe(tex)
                end
                if pw < 1 or ph < 1 then
                    pw, ph = ICON_SIZE, ICON_SIZE
                end
                out[#out + 1] = {
                    category = t.category or 'Misc',
                    name = t.name or t.module,
                    module = t.module,
                    stopAliases = t.stopAliases,
                    tip = t.tip,
                    tex = tex,
                    aspectW = pw,
                    aspectH = ph,
                    drawW = ICON_SIZE,
                    drawH = ICON_SIZE,
                }
            else
                mq.cmdf('/echo \ar[UEQ Launcher]\ax Skipping %s (%s)', tostring(t.name or t.module), tostring(err))
            end
        end
    end

    return out
end

local ENTRIES = buildEntries()

do
    local warned = {}
    local function luaScriptOnDisk(name)
        local n = tostring(name or '')
        if n == '' then
            return true
        end
        local root = norm(mq.luaDir) .. '/' .. n
        if fileExists(root .. '.lua') then
            return true
        end
        if fileExists(root .. '/init.lua') then
            return true
        end
        return false
    end
    for _, t in ipairs(TOOLS) do
        local m = t.module
        if m and not warned[m] then
            warned[m] = true
            if not luaScriptOnDisk(m) then
                mq.cmdf(
                    '/echo \ar[UEQ Launcher]\ax Missing Lua file for \ay%s\ax — copy \ay%s.lua\ax (or \ay%s/init.lua\ax) into \ay%s\ax then \ay/lua run %s\ax will work.',
                    tostring(m),
                    tostring(m),
                    tostring(m),
                    tostring(norm(mq.luaDir)),
                    tostring(m)
                )
            end
        end
    end
end

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

local function luaScriptStatusUpper(name)
    local m = tostring(name or '')
    if m == '' then
        return ''
    end
    local ok, st = pcall(function()
        local s = mq.TLO.Lua.Script(m)
        if not s or not s() then
            return ''
        end
        local v = s.Status()
        if v == nil then
            return ''
        end
        return tostring(v):upper():gsub('^%s+', ''):gsub('%s+$', '')
    end)
    if not ok or not st then
        return ''
    end
    return st
end

--- Only treat MQ as "running" for known active states. A loose "non-empty status" check
--- falsely marks scripts as running (launcher then only /lua stop — never /lua run).
local function scriptNameIsRunning(name)
    local st = luaScriptStatusUpper(name)
    if st == '' or st == 'NULL' then
        return false
    end
    if st == 'RUNNING' or st == 'PAUSED' then
        return true
    end
    return false
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

local function wrappedIconRows(rows, wrapW)
    if wrapW <= 0 then
        wrapW = 520
    end
    local lines = {}
    local line = {}
    local lineW, lineH = 0, 0
    for _, e in ipairs(rows) do
        local ew = tonumber(e.drawW) or ICON_SIZE
        local eh = tonumber(e.drawH) or ICON_SIZE
        local gap = #line > 0 and ICON_GAP or 0
        if #line > 0 and lineW + gap + ew > wrapW then
            lines[#lines + 1] = { entries = line, h = lineH }
            line = {}
            lineW, lineH = 0, 0
            gap = 0
        end
        table.insert(line, e)
        lineW = lineW + gap + ew
        if eh > lineH then
            lineH = eh
        end
    end
    if #line > 0 then
        lines[#lines + 1] = { entries = line, h = lineH }
    end
    if #lines == 0 then
        lines[1] = { entries = {}, h = ICON_SIZE }
    end
    return lines
end

local function linePixelWidth(entries)
    local w = 0
    for i, e in ipairs(entries) do
        w = w + (tonumber(e.drawW) or ICON_SIZE)
        if i < #entries then
            w = w + ICON_GAP
        end
    end
    return w
end

local function categoryKey(cat)
    return tostring(cat or ''):gsub('[^%w]+', '_')
end

local function texPixelSize(tex)
    local s = tex and tex.size
    if not s then
        return 0, 0
    end
    local w = tonumber(s.x or s.X or (type(s) == 'table' and s[1])) or 0
    local h = tonumber(s.y or s.Y or (type(s) == 'table' and s[2])) or 0
    return w, h
end

local function categoryBoxFromLines(lines)
    local maxInnerW = 0
    local sumH = 0
    for i, ln in ipairs(lines) do
        maxInnerW = math.max(maxInnerW, linePixelWidth(ln.entries))
        sumH = sumH + ln.h
        if i < #lines then
            sumH = sumH + ICON_GAP
        end
    end
    sumH = sumH + CATEGORY_CHILD_PAD_Y
    local boxW = maxInnerW + (CATEGORY_CHILD_PAD_X * 2)
    boxW = math.max(boxW, ICON_SIZE + CATEGORY_CHILD_PAD_X * 2)
    local boxH = math.max(sumH, ICON_SIZE + 8)
    return boxW, boxH
end

local function drawCategoryHeader(cat)
    local ar, ag, ab = getCategoryAccent(cat)
    imgui.Dummy(1, 6)
    local x0, y0 = asVecXY(imgui.GetCursorScreenPos())
    local wAvail = contentRegionAvailW()

    local dl = imgui.GetWindowDrawList()
    local rowH = CATEGORY_HEADER_ROW_H
    local sepY = y0 + rowH + 4
    local blockBottom = sepY + 9

    if dl and dl.AddRectFilled then
        local accentU32 = imgui.GetColorU32(ar, ag, ab, 1)
        dl:AddRectFilled(ImVec2(x0, y0), ImVec2(x0 + 3, y0 + rowH), accentU32)
        local sepU32 = imgui.GetColorU32(0.18, 0.19, 0.24, 1)
        dl:AddRectFilled(ImVec2(x0, sepY), ImVec2(x0 + wAvail, sepY + 1), sepU32)
    end

    imgui.SetCursorScreenPos(x0 + 10, y0 + 2)
    imgui.PushStyleColor(ImGuiCol.Text, 0.62, 0.66, 0.74, 1.0)
    imgui.Text(cat)
    imgui.PopStyleColor()

    imgui.SetCursorScreenPos(x0, blockBottom)
end

local function drawIcon(entry, catKey, catDisplayName, li, i)
    local ar, ag, ab = getCategoryAccent(catDisplayName)

    local okTid, tid = pcall(function() return entry.tex:GetTextureID() end)
    if not okTid or tid == nil then
        return
    end

    imgui.PushStyleVar(ImGuiStyleVar.FrameRounding, 8)
    imgui.PushStyleVar(ImGuiStyleVar.FrameBorderSize, 1)
    imgui.PushStyleColor(ImGuiCol.Button, 26 / 255, 29 / 255, 39 / 255, 1)
    imgui.PushStyleColor(ImGuiCol.ButtonHovered, ar, ag, ab, 0.30)
    imgui.PushStyleColor(ImGuiCol.ButtonActive, ar, ag, ab, 0.60)
    imgui.PushStyleColor(ImGuiCol.Border, 42 / 255, 45 / 255, 58 / 255, 1)

    local cell = ICON_SIZE
    local texW = tonumber(entry.aspectW) or 0
    local texH = tonumber(entry.aspectH) or 0
    if texW < 1 or texH < 1 then
        texW, texH = texPixelSize(entry.tex)
    end
    if texW < 1 or texH < 1 then
        texW, texH = cell, cell
    end

    local modKey = tostring(entry.module or 'x'):gsub('[^%w]', '_')
    local hitKey = string.format('##hit_%s_%d_%d_%s', catKey or 'c', tonumber(li) or 0, tonumber(i) or 0, modKey)
    local clicked = imgui.InvisibleButton(hitKey, cell, cell)

    local minX, minY = asVecXY(imgui.GetItemRectMin())
    local maxX, maxY = asVecXY(imgui.GetItemRectMax())
    local dl = imgui.GetWindowDrawList()
    if dl then
        local bgU32 = imgui.GetColorU32(26 / 255, 29 / 255, 39 / 255, 1)
        local hoverU32 = imgui.GetColorU32(ar, ag, ab, 0.30)
        local activeU32 = imgui.GetColorU32(ar, ag, ab, 0.60)
        pcall(function()
            if dl.AddRectFilled then
                dl:AddRectFilled(ImVec2(minX, minY), ImVec2(maxX, maxY), bgU32, 8)
                if imgui.IsItemActive() then
                    dl:AddRectFilled(ImVec2(minX, minY), ImVec2(maxX, maxY), activeU32, 8)
                elseif imgui.IsItemHovered() then
                    dl:AddRectFilled(ImVec2(minX, minY), ImVec2(maxX, maxY), hoverU32, 8)
                end
            end
        end)
    end

    local scale = math.min(cell / texW, cell / texH)
    local dw = math.floor(texW * scale + 0.5)
    local dh = math.floor(texH * scale + 0.5)
    if dw < 1 then
        dw = 1
    end
    if dh < 1 then
        dh = 1
    end

    local ox = minX + (cell - dw) * 0.5
    local oy = minY + (cell - dh) * 0.5

    if dl and dl.AddImage then
        pcall(function()
            dl:AddImage(tid, ImVec2(ox, oy), ImVec2(ox + dw, oy + dh), ImVec2(0, 0), ImVec2(1, 1))
        end)
    end

    if dl and dl.AddRect then
        local borderU32 = imgui.GetColorU32(42 / 255, 45 / 255, 58 / 255, 1)
        pcall(function()
            dl:AddRect(ImVec2(minX, minY), ImVec2(maxX, maxY), borderU32, 8, 0, 1)
        end)
    end

    if moduleIsRunning(entry) and dl then
        local au = imgui.GetColorU32(ar, ag, ab, 1)
        pcall(function()
            if dl.AddRect then
                dl:AddRect(ImVec2(minX, maxY - 3), ImVec2(maxX, maxY), au, 0, 0, 2)
            else
                dl:AddRectFilled(ImVec2(minX, maxY - 2), ImVec2(maxX, maxY), au)
            end
        end)
    end

    local clicksArmed = (os.clock() - startedAt) >= CLICK_ARM_DELAY_SEC
    if clicked and clicksArmed then
        toggleModule(entry)
    end
    if entry.tip and imgui.IsItemHovered() then
        local state = moduleIsRunning(entry) and 'running' or 'stopped'
        imgui.SetTooltip(string.format('%s (%s)', entry.tip, state))
    end

    imgui.PopStyleColor(4)
    imgui.PopStyleVar(2)
end

local function drawWindow()
    if launcherMainOpen then
        local layouts = {}
        local maxBoxW = 280
        local totalCategoryPixH = 0
        local sectionCount = 0
        for _, cat in ipairs(CATEGORY_ORDER) do
            local rows = ENTRIES_BY_CATEGORY[cat] or {}
            if #rows > 0 then
                sectionCount = sectionCount + 1
                local lines = wrappedIconRows(rows, ROW_WRAP_MAX)
                local boxW, boxH = categoryBoxFromLines(lines)
                layouts[cat] = { lines = lines, boxW = boxW, boxH = boxH }
                maxBoxW = math.max(maxBoxW, boxW)
                totalCategoryPixH = totalCategoryPixH + boxH + CATEGORY_LABEL_H
            end
        end

        local pv, pc = pushUltimateEqTheme()
        imgui.SetNextWindowBgAlpha(1.0)
        local winW = math.min(1600, math.max(360, maxBoxW + 72))
        local winH = math.max(220, 104 + totalCategoryPixH + sectionCount * 10)
        imgui.SetNextWindowSize(winW, winH, ImGuiCond.FirstUseEver)
        local winOpen, drawMain = imgui.Begin(
            'Ultimate EQ - launcher##UEQ_Launcher_Stable',
            launcherMainOpen,
            ImGuiWindowFlags.NoCollapse
        )
        if drawMain ~= nil then
            launcherMainOpen = winOpen
            if not drawMain then
                imgui.End()
                popUltimateEqTheme(pv, pc)
                drawLauncherToggleFab()
                return
            end
        else
            if not winOpen then
                imgui.End()
                popUltimateEqTheme(pv, pc)
                drawLauncherToggleFab()
                return
            end
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
                    drawCategoryHeader(cat)
                    local L = layouts[cat]
                    if L then
                        local lines = L.lines
                        local ck = categoryKey(cat)
                        imgui.PushStyleColor(ImGuiCol.ChildBg, 19 / 255, 21 / 255, 31 / 255, 1)
                        imgui.PushStyleVar(ImGuiStyleVar.ChildRounding, 10)
                        imgui.BeginChild('cat_' .. ck, L.boxW, L.boxH, true)
                        for li, ln in ipairs(lines) do
                            for i, entry in ipairs(ln.entries) do
                                if i > 1 then
                                    imgui.SameLine(0, ICON_GAP)
                                end
                                drawIcon(entry, ck, cat, li, i)
                            end
                            if li < #lines then
                                imgui.Dummy(1, ICON_GAP)
                            end
                        end
                        imgui.EndChild()
                        imgui.PopStyleVar()
                        imgui.PopStyleColor()
                    end
                end
            end
        end

        imgui.PushStyleColor(ImGuiCol.Button, 61 / 255, 26 / 255, 26 / 255, 1)
        imgui.PushStyleColor(ImGuiCol.ButtonHovered, 127 / 255, 29 / 255, 29 / 255, 1)
        if imgui.Button('Quit launcher##quit') then
            terminate = true
        end
        imgui.PopStyleColor(2)
        imgui.SameLine()
        imgui.TextColored(0.55, 0.58, 0.62, 1.0, '/lua stop ueqtool')

        imgui.End()
        popUltimateEqTheme(pv, pc)
    end

    drawLauncherToggleFab()
end

mq.bind('/ueqlaunchquit', function() terminate = true end)

mq.bind('/ueqlauncher', function()
    launcherMainOpen = not launcherMainOpen
end)

pcall(function() mq.imgui.destroy('ueq_launcher_stable') end)
pcall(function() mq.imgui.destroy('ueq_launcher_singleitem') end)
pcall(function() mq.imgui.destroy('ueq_launcher_clean') end)
pcall(function() mq.imgui.destroy('ueq_launcher_bar_v2') end)
pcall(function() mq.imgui.destroy('ueq_launcher_bar') end)
pcall(function() mq.imgui.destroy('ueqtool') end)
pcall(function() mq.imgui.destroy('UEQ_Launcher') end)
mq.imgui.init(SCRIPT_ID, drawWindow)
mq.cmd('/echo \ag[UEQ Launcher]\ax Stable launcher loaded. /ueqlauncher toggles panel. /ueqlaunchquit unloads.')

while not terminate do
    mq.delay(50)
end

pcall(function() mq.imgui.destroy(SCRIPT_ID) end)
pcall(function() mq.unbind('/ueqlaunchquit') end)
pcall(function() mq.unbind('/ueqlauncher') end)
