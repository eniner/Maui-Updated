local mq = require('mq')
local imgui = require('ImGui')

local terminate = false
local windowOpen = true
local selectedTab = 'Corpse'
local searchBuf = ''
local radarActive = true
local npcRange = 200
local corpseRange = 100
local selectedCorpseName = nil

local npcList = {
    { id = 44, los = 198, dist = 85, lvl = 85, name = 'Guardian_of_Order001' },
}
local corpseList = {}

local tabs = {
    'Corpse',
    'Loot Config',
    'Personal Inv.',
    'All Inventories',
    'Stat DNA',
    'Settings',
    'About',
}

local lastScanTime = 0
local scanIntervalSeconds = 1.0
local dot = string.char(226, 151, 143)

local function safeNum(v, fallback)
    local n = tonumber(v)
    if n == nil then return fallback or 0 end
    return n
end

local function valueFromSpawn(spawn, fnName, fallback)
    if not spawn then return fallback end
    local fn = spawn[fnName]
    if type(fn) ~= 'function' then return fallback end
    local ok, result = pcall(fn, spawn)
    if not ok or result == nil then return fallback end
    return result
end

local function normalizeSpawnRow(spawn)
    local row = {
        id = safeNum(valueFromSpawn(spawn, 'ID', 0), 0),
        los = valueFromSpawn(spawn, 'LineOfSight', false) and 1 or 0,
        dist = math.floor(safeNum(valueFromSpawn(spawn, 'Distance3D', 0), 0)),
        lvl = safeNum(valueFromSpawn(spawn, 'Level', 0), 0),
        name = tostring(valueFromSpawn(spawn, 'CleanName', '') or ''),
    }
    if row.name == '' then row.name = tostring(valueFromSpawn(spawn, 'Name', '') or '') end
    return row
end

local function fetchSpawnList(filter)
    local rows = {}

    if type(mq.getFilteredSpawns) == 'function' then
        local ok, filtered = pcall(mq.getFilteredSpawns, filter)
        if ok and type(filtered) == 'table' then
            for _, spawn in ipairs(filtered) do
                local row = normalizeSpawnRow(spawn)
                if row.name ~= '' then rows[#rows + 1] = row end
            end
            return rows
        end
    end

    local count = safeNum(mq.TLO.SpawnCount(filter)(), 0)
    for i = 1, count do
        local spawn = mq.TLO.NearestSpawn(i, filter)
        if spawn and spawn() then
            local row = normalizeSpawnRow(spawn)
            if row.name ~= '' then rows[#rows + 1] = row end
        end
    end

    return rows
end

local function applySearchFilter(rows)
    if searchBuf == '' then return rows end
    local needle = string.lower(searchBuf)
    local out = {}
    for _, row in ipairs(rows) do
        if string.find(string.lower(row.name), needle, 1, true) then
            out[#out + 1] = row
        end
    end
    return out
end

local function scanForNPCs()
    if not radarActive then return end
    npcList = fetchSpawnList(string.format('npc radius %d', npcRange))
end

local function scanForCorpses()
    if not radarActive then return end
    corpseList = fetchSpawnList(string.format('corpse radius %d', corpseRange))
end

local function lootAll()
    for _, corpse in ipairs(corpseList) do
        if corpse.name and corpse.name ~= '' then
            mq.cmdf('/target %s', corpse.name)
            mq.delay(100)
            mq.cmdf('/nav spawn %s', corpse.name)
            mq.delay(170)
            mq.cmd('/open')
            mq.delay(90)
        end
    end
end

local function updateInputText(label, current, maxLen)
    local a, b = imgui.InputText(label, current, maxLen)
    if type(a) == 'string' and b == nil then return a end
    if a and type(b) == 'string' then return b end
    return current
end

local function updateSliderInt(label, current, min, max)
    local a, b = imgui.SliderInt(label, current, min, max)
    if type(a) == 'number' and b == nil then return a end
    if a and type(b) == 'number' then return b end
    return current
end

local function pushTheme()
    imgui.PushStyleColor(ImGuiCol.WindowBg, 0.10, 0.06, 0.19, 1.0)
    imgui.PushStyleColor(ImGuiCol.Border, 0.30, 0.24, 0.52, 1.0)
    imgui.PushStyleColor(ImGuiCol.Separator, 0.28, 0.23, 0.48, 1.0)
    imgui.PushStyleColor(ImGuiCol.Button, 0.13, 0.10, 0.24, 1.0)
    imgui.PushStyleColor(ImGuiCol.ButtonHovered, 0.19, 0.15, 0.33, 1.0)
    imgui.PushStyleColor(ImGuiCol.ButtonActive, 0.15, 0.12, 0.28, 1.0)
    imgui.PushStyleColor(ImGuiCol.FrameBg, 0.09, 0.05, 0.16, 1.0)
    imgui.PushStyleColor(ImGuiCol.FrameBgHovered, 0.12, 0.08, 0.20, 1.0)
    imgui.PushStyleColor(ImGuiCol.FrameBgActive, 0.12, 0.08, 0.20, 1.0)
    imgui.PushStyleColor(ImGuiCol.TextDisabled, 0.57, 0.54, 0.76, 1.0)
    imgui.PushStyleColor(ImGuiCol.TableHeaderBg, 0.22, 0.22, 0.24, 1.0)
    imgui.PushStyleColor(ImGuiCol.TableBorderStrong, 0.28, 0.24, 0.45, 1.0)
    imgui.PushStyleColor(ImGuiCol.TableBorderLight, 0.23, 0.20, 0.37, 1.0)

    imgui.PushStyleVar(ImGuiStyleVar.WindowRounding, 10)
    imgui.PushStyleVar(ImGuiStyleVar.FrameRounding, 10)
    imgui.PushStyleVar(ImGuiStyleVar.ChildRounding, 8)
    imgui.PushStyleVar(ImGuiStyleVar.FrameBorderSize, 1)
    imgui.PushStyleVar(ImGuiStyleVar.WindowBorderSize, 1)
    imgui.PushStyleVar(ImGuiStyleVar.ItemSpacing, 6, 5)
    imgui.PushStyleVar(ImGuiStyleVar.WindowPadding, 8, 6)
    imgui.PushStyleVar(ImGuiStyleVar.FramePadding, 8, 6)
end

local function popTheme()
    imgui.PopStyleVar(8)
    imgui.PopStyleColor(13)
end

local function pill(text, r, g, b)
    imgui.PushStyleColor(ImGuiCol.Button, r, g, b, 1.0)
    imgui.PushStyleColor(ImGuiCol.ButtonHovered, r, g, b, 1.0)
    imgui.PushStyleColor(ImGuiCol.ButtonActive, r, g, b, 1.0)
    imgui.Button(text)
    imgui.PopStyleColor(3)
end

local function drawHeaderRow()
    imgui.BeginChild('HeaderRow', -1, 24, false)

    imgui.PushStyleColor(ImGuiCol.Text, 1.0, 0.42, 0.35, 1.0)
    imgui.Text(dot)
    imgui.PopStyleColor(1)
    imgui.SameLine()
    imgui.PushStyleColor(ImGuiCol.Text, 0.99, 0.78, 0.23, 1.0)
    imgui.Text(dot)
    imgui.PopStyleColor(1)
    imgui.SameLine()
    imgui.PushStyleColor(ImGuiCol.Text, 0.22, 0.86, 0.45, 1.0)
    imgui.Text(dot)
    imgui.PopStyleColor(1)

    local title = 'LootMgr 1.23.0 - ALPHA'
    local cx = imgui.GetCursorPosX() + (imgui.GetContentRegionAvail() - imgui.CalcTextSize(title)) * 0.5
    if cx > imgui.GetCursorPosX() then imgui.SameLine(); imgui.SetCursorPosX(cx) end
    imgui.PushStyleColor(ImGuiCol.Text, 0.77, 0.72, 0.98, 1.0)
    imgui.Text(title)
    imgui.PopStyleColor(1)

    local rx = imgui.GetCursorPosX() + imgui.GetContentRegionAvail() - 20
    if rx > imgui.GetCursorPosX() then imgui.SameLine(); imgui.SetCursorPosX(rx) end
    if imgui.SmallButton('X') then terminate = true; windowOpen = false end

    imgui.EndChild()
end

local function drawToolbarRow()
    imgui.BeginChild('ToolbarRow', -1, 42, false)

    pill('v0.66', 0.22, 0.18, 0.43)
    imgui.SameLine()
    imgui.Button('Config', 102, 32)
    imgui.SameLine()
    imgui.Button('Log', 86, 32)

    local lightsX = imgui.GetCursorPosX() + imgui.GetContentRegionAvail() - 214
    if lightsX > imgui.GetCursorPosX() then imgui.SameLine(); imgui.SetCursorPosX(lightsX) end

    imgui.TextDisabled('|')
    imgui.SameLine()
    imgui.PushStyleColor(ImGuiCol.Text, 0.10, 1.0, 0.45, 1.0)
    imgui.Text(dot)
    imgui.PopStyleColor(1)
    imgui.SameLine()
    imgui.PushStyleColor(ImGuiCol.Text, 1.0, 0.80, 0.20, 1.0)
    imgui.Text(dot)
    imgui.PopStyleColor(1)
    imgui.SameLine()
    imgui.PushStyleColor(ImGuiCol.Text, 0.98, 0.37, 0.31, 1.0)
    imgui.Text(dot)
    imgui.PopStyleColor(1)
    imgui.SameLine()
    imgui.TextDisabled('|')

    imgui.SameLine()
    if imgui.Button('O', 48, 32) then end
    imgui.SameLine()
    if imgui.Button('U', 48, 32) then end

    imgui.EndChild()
end

local function drawTabsRow()
    imgui.BeginChild('TabsRow', -1, 27, false)
    for i, tab in ipairs(tabs) do
        if i > 1 then imgui.SameLine() end

        imgui.PushStyleColor(ImGuiCol.Button, 0.10, 0.06, 0.19, 1.0)
        imgui.PushStyleColor(ImGuiCol.ButtonHovered, 0.14, 0.10, 0.25, 1.0)
        imgui.PushStyleColor(ImGuiCol.ButtonActive, 0.12, 0.08, 0.21, 1.0)

        if tab == selectedTab then
            imgui.PushStyleColor(ImGuiCol.Text, 0.95, 0.95, 0.99, 1.0)
        else
            imgui.PushStyleColor(ImGuiCol.Text, 0.72, 0.70, 0.92, 1.0)
        end

        if imgui.Button(tab, 0, 21) then selectedTab = tab end
        imgui.PopStyleColor(4)
    end
    imgui.EndChild()

    imgui.BeginChild('ScrubRow', -1, 10, true)
    imgui.Text('<')
    imgui.SameLine()
    imgui.SetCursorPosX(16)
    imgui.PushStyleColor(ImGuiCol.Button, 0.63, 0.63, 0.67, 0.34)
    imgui.PushStyleColor(ImGuiCol.ButtonHovered, 0.63, 0.63, 0.67, 0.34)
    imgui.PushStyleColor(ImGuiCol.ButtonActive, 0.63, 0.63, 0.67, 0.34)
    imgui.Button('##scrubtrack', -24, 5)
    imgui.PopStyleColor(3)
    imgui.SameLine()
    imgui.Text('>')
    imgui.EndChild()
end

local function drawSearchCard()
    imgui.BeginChild('SearchCard', -1, 54, true)

    imgui.SetNextItemWidth(imgui.GetContentRegionAvail() - 216)
    searchBuf = updateInputText('##search', searchBuf, 128)
    if searchBuf == '' then
        imgui.SameLine()
        imgui.SetCursorPosX(16)
        imgui.TextDisabled('Search corpses or targets...')
    end

    imgui.SameLine()
    imgui.PushStyleColor(ImGuiCol.Text, radarActive and 0.0 or 0.95, radarActive and 1.0 or 0.30, radarActive and 0.42 or 0.30, 1.0)
    if imgui.Button(dot .. ' Radar', 68, 0) then radarActive = not radarActive end
    imgui.PopStyleColor(1)

    imgui.SameLine()
    imgui.PushStyleColor(ImGuiCol.Button, 0.12, 0.10, 0.23, 1.0)
    imgui.PushStyleColor(ImGuiCol.ButtonHovered, 0.19, 0.15, 0.33, 1.0)
    imgui.PushStyleColor(ImGuiCol.ButtonActive, 0.15, 0.12, 0.27, 1.0)
    if imgui.Button('Scan Now', 104, 0) then
        mq.cmd('/target')
        scanForNPCs()
        scanForCorpses()
    end
    imgui.PopStyleColor(3)

    imgui.EndChild()
end

local function drawRangeRow(label, id, value, min, max)
    imgui.Text(label)
    imgui.SameLine()
    imgui.SetNextItemWidth(-58)
    local v = updateSliderInt(id, value, min, max)
    imgui.SameLine()
    imgui.Text(tostring(v) .. 'm')
    return v
end

local function drawSectionHeader(text, count, withAuto)
    imgui.PushStyleColor(ImGuiCol.Text, 0.55, 0.52, 0.77, 1.0)
    imgui.Text(text)
    imgui.PopStyleColor(1)

    local badge = tostring(count) .. ' FOUND'
    local reserve = imgui.CalcTextSize(badge) + 35
    if withAuto then reserve = reserve + 104 end

    local x = imgui.GetCursorPosX() + imgui.GetContentRegionAvail() - reserve
    if x > imgui.GetCursorPosX() then imgui.SameLine(); imgui.SetCursorPosX(x) end

    pill(badge, 0.32, 0.28, 0.52)
    if withAuto then imgui.SameLine(); imgui.Button('Auto-check all') end
end

local function drawSpawnTable(tableId, rows, tableHeight, actionLabel)
    local flags = ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg + ImGuiTableFlags.SizingFixedFit
    if imgui.BeginTable(tableId, 8, flags, -1, tableHeight) then
        imgui.TableSetupColumn('#')
        imgui.TableSetupColumn('ID')
        imgui.TableSetupColumn('LOS')
        imgui.TableSetupColumn('DIST')
        imgui.TableSetupColumn('LVL')
        imgui.TableSetupColumn('NAME', ImGuiTableColumnFlags.WidthStretch)
        imgui.TableSetupColumn('ACTION')
        imgui.TableSetupColumn('NAV')
        imgui.TableHeadersRow()

        for i, row in ipairs(rows) do
            imgui.TableNextRow()
            imgui.TableSetColumnIndex(0); imgui.Text(tostring(i - 1))
            imgui.TableSetColumnIndex(1); imgui.Text(tostring(row.id))
            imgui.TableSetColumnIndex(2); imgui.Text(tostring(row.los))
            imgui.TableSetColumnIndex(3); imgui.Text(tostring(row.dist))
            imgui.TableSetColumnIndex(4)
            imgui.PushStyleColor(ImGuiCol.Text, 1.0, 0.79, 0.16, 1.0)
            imgui.Text(tostring(row.lvl))
            imgui.PopStyleColor(1)
            imgui.TableSetColumnIndex(5)
            imgui.PushStyleColor(ImGuiCol.Text, 0.88, 0.85, 1.0, 1.0)
            imgui.Text(row.name)
            imgui.PopStyleColor(1)

            imgui.TableSetColumnIndex(6)
            imgui.PushID(tableId .. '_act_' .. tostring(i))
            if imgui.Button(actionLabel) then
                mq.cmdf('/target %s', row.name)
                if actionLabel == 'Open' then
                    selectedCorpseName = row.name
                    mq.delay(75)
                    mq.cmd('/open')
                end
            end
            imgui.PopID()

            imgui.TableSetColumnIndex(7)
            imgui.PushStyleColor(ImGuiCol.Button, 0.10, 0.55, 0.22, 1.0)
            imgui.PushStyleColor(ImGuiCol.ButtonHovered, 0.14, 0.67, 0.28, 1.0)
            imgui.PushStyleColor(ImGuiCol.ButtonActive, 0.09, 0.45, 0.20, 1.0)
            imgui.PushID(tableId .. '_nav_' .. tostring(i))
            if imgui.Button('Nav ->') then mq.cmdf('/nav spawn %s', row.name) end
            imgui.PopID()
            imgui.PopStyleColor(3)
        end

        imgui.EndTable()
    end
end

local function drawCorpseTab()
    drawSearchCard()

    npcRange = drawRangeRow('NPC range', '##npcRange', npcRange, 50, 500)
    corpseRange = drawRangeRow('Corpse range', '##corpseRange', corpseRange, 25, 300)

    imgui.Separator()

    local npcs = applySearchFilter(npcList)
    drawSectionHeader(string.format('NPCS IN RANGE - %dm', npcRange), #npcs, true)
    imgui.BeginChild('NpcCard', -1, 92, true)
    drawSpawnTable('npcTable', npcs, 58, 'Target')
    imgui.EndChild()

    local corpses = applySearchFilter(corpseList)
    drawSectionHeader(string.format('CORPSES IN RANGE - %dm', corpseRange), #corpses, false)
    imgui.BeginChild('CorpseCard', -1, 86, true)
    drawSpawnTable('corpseTable', corpses, 54, 'Open')
    if #corpses == 0 then
        local msg = 'No corpses detected in range - open manually or wait for scan'
        local x = imgui.GetCursorPosX() + (imgui.GetContentRegionAvail() - imgui.CalcTextSize(msg)) * 0.5
        if x > imgui.GetCursorPosX() then imgui.SetCursorPosX(x) end
        imgui.TextDisabled(msg)
    end
    imgui.EndChild()

    imgui.Separator()

    local w = 122
    local total = w * 3 + 16
    local sx = imgui.GetCursorPosX() + imgui.GetContentRegionAvail() - total
    if sx > imgui.GetCursorPosX() then imgui.SetCursorPosX(sx) end

    if imgui.Button('Clear History', w, 0) then
        corpseList = {}
        selectedCorpseName = nil
    end
    imgui.SameLine()
    if imgui.Button('Open Selected', w, 0) then
        if selectedCorpseName and selectedCorpseName ~= '' then
            mq.cmdf('/target %s', selectedCorpseName)
            mq.delay(75)
            mq.cmd('/open')
        end
    end
    imgui.SameLine()
    if imgui.Button('Loot All', w, 0) then lootAll() end
end

local function renderUI()
    if not windowOpen then return end

    imgui.SetNextWindowSize(560, 520, ImGuiCond.FirstUseEver)
    pushTheme()

    local flags = ImGuiWindowFlags.NoCollapse + ImGuiWindowFlags.NoTitleBar + ImGuiWindowFlags.NoScrollbar
    local visible = false
    windowOpen, visible = imgui.Begin('LootMgr', windowOpen, flags)
    if visible then
        drawHeaderRow()
        drawToolbarRow()
        drawTabsRow()

        if selectedTab == 'Corpse' then
            drawCorpseTab()
        else
            imgui.Text('Coming soon')
        end
    end

    imgui.End()
    popTheme()
end

mq.imgui.init('LootMgr', renderUI)

while not terminate do
    local now = os.clock()
    if now - lastScanTime >= scanIntervalSeconds then
        scanForNPCs()
        scanForCorpses()
        lastScanTime = now
    end

    mq.doevents()
    mq.delay(50)
    mq.delay(0, function() return terminate end)
end
