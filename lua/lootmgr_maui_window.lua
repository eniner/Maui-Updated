local mq = require('mq')
local ImGui = require('ImGui')

local scriptName = 'LootMgrMauiWindow'
local state = {
    open = true,
    running = true,
    selectedTab = 5, -- Stat DNA
    themeKey = 'template',
}

local tabs = {
    'Corpse',
    'Loot Config',
    'Personal Inv.',
    'All Inventories',
    'Stat DNA',
    'Settings',
    'About',
}

local rows = {
    { idx = 0, id = 44, los = 198, dist = 85, npc = 'Guardian_of_Order001', target = 'Tar', nav = 'Nav' },
}

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

local pushedVarCount = 0
local pushedColorCount = 0

local function normalizeThemeKey(themeKey)
    local key = tostring(themeKey or ''):lower()
    if key == '' or key == 'default' then return 'template' end
    if key == 'red' then return 'cyber_blue' end
    if uiThemes[key] then return key end
    return 'template'
end

local function parseIniSectionValue(path, section, key)
    local file = io.open(path, 'r')
    if not file then return nil end
    local currentSection = ''
    for line in file:lines() do
        local trimmed = line:match('^%s*(.-)%s*$')
        if trimmed ~= '' and not trimmed:match('^[;#]') then
            local sec = trimmed:match('^%[(.-)%]$')
            if sec then
                currentSection = sec
            elseif currentSection == section then
                local k, v = trimmed:match('^([^=]+)=(.+)$')
                if k and v and k:match('^%s*(.-)%s*$') == key then
                    file:close()
                    return v:match('^%s*(.-)%s*$')
                end
            end
        end
    end
    file:close()
    return nil
end

local function loadMauiThemeFromConfig()
    local server = mq.TLO.EverQuest.Server() or ''
    local charName = mq.TLO.Me.CleanName() or ''
    if server == '' or charName == '' then
        state.themeKey = 'template'
        return
    end
    local path = string.format('%s/%s_%s.ini', mq.configDir, server, charName)
    local configured = parseIniSectionValue(path, 'MAUI', 'Theme')
    state.themeKey = normalizeThemeKey(configured or 'template')
end

local function pushTheme()
    local theme = uiThemes[state.themeKey] or uiThemes.template
    pushedVarCount = 0
    pushedColorCount = 0

    ImGui.PushStyleVar(ImGuiStyleVar.WindowRounding, 0); pushedVarCount = pushedVarCount + 1
    ImGui.PushStyleVar(ImGuiStyleVar.FrameRounding, 6); pushedVarCount = pushedVarCount + 1
    ImGui.PushStyleVar(ImGuiStyleVar.ChildRounding, 0); pushedVarCount = pushedVarCount + 1
    ImGui.PushStyleVar(ImGuiStyleVar.PopupRounding, 8); pushedVarCount = pushedVarCount + 1
    ImGui.PushStyleVar(ImGuiStyleVar.GrabRounding, 6); pushedVarCount = pushedVarCount + 1
    ImGui.PushStyleVar(ImGuiStyleVar.TabRounding, 0); pushedVarCount = pushedVarCount + 1
    ImGui.PushStyleVar(ImGuiStyleVar.WindowBorderSize, 1); pushedVarCount = pushedVarCount + 1
    ImGui.PushStyleVar(ImGuiStyleVar.FrameBorderSize, 1); pushedVarCount = pushedVarCount + 1
    ImGui.PushStyleVar(ImGuiStyleVar.ChildBorderSize, 1); pushedVarCount = pushedVarCount + 1
    ImGui.PushStyleVar(ImGuiStyleVar.WindowPadding, 6, 6); pushedVarCount = pushedVarCount + 1
    ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, 4, 2); pushedVarCount = pushedVarCount + 1
    ImGui.PushStyleVar(ImGuiStyleVar.ItemSpacing, 8, 8); pushedVarCount = pushedVarCount + 1

    ImGui.PushStyleColor(ImGuiCol.WindowBg, theme.windowBg[1], theme.windowBg[2], theme.windowBg[3], theme.windowBg[4]); pushedColorCount = pushedColorCount + 1
    ImGui.PushStyleColor(ImGuiCol.ChildBg, 0.02, 0.03, 0.08, 1.00); pushedColorCount = pushedColorCount + 1
    ImGui.PushStyleColor(ImGuiCol.TitleBg, theme.titleBg[1], theme.titleBg[2], theme.titleBg[3], theme.titleBg[4]); pushedColorCount = pushedColorCount + 1
    ImGui.PushStyleColor(ImGuiCol.TitleBgActive, theme.titleBgActive[1], theme.titleBgActive[2], theme.titleBgActive[3], theme.titleBgActive[4]); pushedColorCount = pushedColorCount + 1
    ImGui.PushStyleColor(ImGuiCol.Button, theme.button[1], theme.button[2], theme.button[3], theme.button[4]); pushedColorCount = pushedColorCount + 1
    ImGui.PushStyleColor(ImGuiCol.ButtonHovered, theme.buttonHovered[1], theme.buttonHovered[2], theme.buttonHovered[3], theme.buttonHovered[4]); pushedColorCount = pushedColorCount + 1
    ImGui.PushStyleColor(ImGuiCol.ButtonActive, theme.buttonActive[1], theme.buttonActive[2], theme.buttonActive[3], theme.buttonActive[4]); pushedColorCount = pushedColorCount + 1
    ImGui.PushStyleColor(ImGuiCol.FrameBg, theme.frameBg[1], theme.frameBg[2], theme.frameBg[3], theme.frameBg[4]); pushedColorCount = pushedColorCount + 1
    ImGui.PushStyleColor(ImGuiCol.FrameBgHovered, theme.frameBgHovered[1], theme.frameBgHovered[2], theme.frameBgHovered[3], theme.frameBgHovered[4]); pushedColorCount = pushedColorCount + 1
    ImGui.PushStyleColor(ImGuiCol.FrameBgActive, theme.frameBgHovered[1], theme.frameBgHovered[2], theme.frameBgHovered[3], 1.00); pushedColorCount = pushedColorCount + 1
    ImGui.PushStyleColor(ImGuiCol.Header, theme.header[1], theme.header[2], theme.header[3], theme.header[4]); pushedColorCount = pushedColorCount + 1
    ImGui.PushStyleColor(ImGuiCol.HeaderHovered, theme.buttonHovered[1], theme.buttonHovered[2], theme.buttonHovered[3], 1.00); pushedColorCount = pushedColorCount + 1
    ImGui.PushStyleColor(ImGuiCol.HeaderActive, theme.buttonActive[1], theme.buttonActive[2], theme.buttonActive[3], 1.00); pushedColorCount = pushedColorCount + 1
    ImGui.PushStyleColor(ImGuiCol.Text, theme.text[1], theme.text[2], theme.text[3], theme.text[4]); pushedColorCount = pushedColorCount + 1
    ImGui.PushStyleColor(ImGuiCol.Border, theme.border[1], theme.border[2], theme.border[3], theme.border[4]); pushedColorCount = pushedColorCount + 1
    ImGui.PushStyleColor(ImGuiCol.Separator, theme.separator[1], theme.separator[2], theme.separator[3], theme.separator[4]); pushedColorCount = pushedColorCount + 1
    ImGui.PushStyleColor(ImGuiCol.TextDisabled, 0.72, 0.72, 0.72, 1.00); pushedColorCount = pushedColorCount + 1
    ImGui.PushStyleColor(ImGuiCol.CheckMark, 0.96, 0.86, 0.30, 1.00); pushedColorCount = pushedColorCount + 1
    ImGui.PushStyleColor(ImGuiCol.PopupBg, 0.02, 0.03, 0.08, 0.98); pushedColorCount = pushedColorCount + 1
    ImGui.PushStyleColor(ImGuiCol.Tab, theme.frameBg[1], theme.frameBg[2], theme.frameBg[3], 1.00); pushedColorCount = pushedColorCount + 1
    ImGui.PushStyleColor(ImGuiCol.TabHovered, theme.frameBgHovered[1], theme.frameBgHovered[2], theme.frameBgHovered[3], 1.00); pushedColorCount = pushedColorCount + 1
    ImGui.PushStyleColor(ImGuiCol.TabActive, theme.header[1], theme.header[2], theme.header[3], 1.00); pushedColorCount = pushedColorCount + 1
end

local function popTheme()
    if pushedColorCount > 0 then ImGui.PopStyleColor(pushedColorCount) end
    if pushedVarCount > 0 then ImGui.PopStyleVar(pushedVarCount) end
    pushedColorCount = 0
    pushedVarCount = 0
end

local function drawTopRow()
    ImGui.Button('...', 30, 22)
    ImGui.SameLine()
    ImGui.Button('1.00', 58, 22)
    ImGui.SameLine()
    ImGui.Button('v', 24, 22)
    ImGui.SameLine()
    ImGui.Button('v', 24, 22)

    local x = ImGui.GetCursorPosX()
    local avail = ImGui.GetContentRegionAvail()
    local rightStart = x + avail - 72
    if rightStart > x then
        ImGui.SameLine()
        ImGui.SetCursorPosX(rightStart)
    end

    ImGui.PushStyleColor(ImGuiCol.Button, 0.18, 0.90, 0.85, 1.0)
    ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 0.24, 0.98, 0.92, 1.0)
    ImGui.PushStyleColor(ImGuiCol.ButtonActive, 0.10, 0.72, 0.66, 1.0)
    ImGui.Button('o', 22, 22)
    ImGui.PopStyleColor(3)

    ImGui.SameLine()
    ImGui.PushStyleColor(ImGuiCol.Button, 0.30, 0.92, 0.26, 1.0)
    ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 0.42, 1.00, 0.38, 1.0)
    ImGui.PushStyleColor(ImGuiCol.ButtonActive, 0.22, 0.75, 0.20, 1.0)
    ImGui.Button('o', 22, 22)
    ImGui.PopStyleColor(3)
end

local function drawTabs(theme)
    for i, label in ipairs(tabs) do
        if i > 1 then ImGui.SameLine() end
        if i == state.selectedTab then
            ImGui.PushStyleColor(ImGuiCol.Button, theme.header[1], theme.header[2], theme.header[3], 1.00)
            ImGui.PushStyleColor(ImGuiCol.ButtonHovered, theme.buttonHovered[1], theme.buttonHovered[2], theme.buttonHovered[3], 1.00)
            ImGui.PushStyleColor(ImGuiCol.ButtonActive, theme.buttonActive[1], theme.buttonActive[2], theme.buttonActive[3], 1.00)
        end
        if ImGui.Button(label, 100, 0) then
            state.selectedTab = i
        end
        if i == state.selectedTab then
            ImGui.PopStyleColor(3)
        end
    end
end

local function drawScannerRow()
    ImGui.Button('Q', 52, 0)
    ImGui.SameLine()
    ImGui.TextColored(0.18, 0.98, 0.22, 1.0, 'o')
    ImGui.SameLine()
    ImGui.Text('Scanner Mode (Radar)')

    local x = ImGui.GetCursorPosX()
    local avail = ImGui.GetContentRegionAvail()
    local rightStart = x + avail - 114
    if rightStart > x then
        ImGui.SameLine()
        ImGui.SetCursorPosX(rightStart)
    end
    ImGui.Button('Grp', 54, 0)
    ImGui.SameLine()
    ImGui.Button('Bot', 54, 0)
end

local function drawActionRow()
    ImGui.Button('R', 52, 0)
    ImGui.SameLine()
    ImGui.TextDisabled('::')
    ImGui.SameLine()
    ImGui.TextDisabled('No corpse in history')

    local x = ImGui.GetCursorPosX()
    local avail = ImGui.GetContentRegionAvail()
    local rightStart = x + avail - 114
    if rightStart > x then
        ImGui.SameLine()
        ImGui.SetCursorPosX(rightStart)
    end
    ImGui.Button('Self', 112, 0)
end

local function drawCorpsesTable()
    local tableFlags = ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg + ImGuiTableFlags.ScrollY + ImGuiTableFlags.SizingStretchProp
    if ImGui.BeginTable('LootMgrCorpsesTable', 8, tableFlags, 0, 200) then
        ImGui.TableSetupColumn('Index', ImGuiTableColumnFlags.WidthFixed, 46)
        ImGui.TableSetupColumn('ID', ImGuiTableColumnFlags.WidthFixed, 54)
        ImGui.TableSetupColumn('Los', ImGuiTableColumnFlags.WidthFixed, 46)
        ImGui.TableSetupColumn('Dist', ImGuiTableColumnFlags.WidthFixed, 46)
        ImGui.TableSetupColumn('Lvl', ImGuiTableColumnFlags.WidthFixed, 42)
        ImGui.TableSetupColumn('Npc Name (range 200)')
        ImGui.TableSetupColumn('Target', ImGuiTableColumnFlags.WidthFixed, 74)
        ImGui.TableSetupColumn('Navigate', ImGuiTableColumnFlags.WidthFixed, 80)
        ImGui.TableHeadersRow()

        for _, row in ipairs(rows) do
            ImGui.TableNextRow()
            ImGui.TableSetColumnIndex(0); ImGui.Text(tostring(row.idx))
            ImGui.TableSetColumnIndex(1); ImGui.Text(tostring(row.id))
            ImGui.TableSetColumnIndex(2); ImGui.Text(tostring(row.los))
            ImGui.TableSetColumnIndex(3); ImGui.Text(tostring(row.dist))
            ImGui.TableSetColumnIndex(4); ImGui.Text(tostring(row.lvl or ''))
            ImGui.TableSetColumnIndex(5); ImGui.Text(row.npc)

            ImGui.TableSetColumnIndex(6)
            ImGui.PushID('tar' .. tostring(row.id))
            ImGui.Button(row.target, 60, 0)
            ImGui.PopID()

            ImGui.TableSetColumnIndex(7)
            ImGui.PushID('nav' .. tostring(row.id))
            ImGui.Button(row.nav, 64, 0)
            ImGui.PopID()
        end

        ImGui.EndTable()
    end

    if ImGui.BeginTable('LootMgrSecondHeader', 5, ImGuiTableFlags.Borders + ImGuiTableFlags.SizingStretchProp) then
        ImGui.TableSetupColumn('Index', ImGuiTableColumnFlags.WidthFixed, 46)
        ImGui.TableSetupColumn('ID', ImGuiTableColumnFlags.WidthFixed, 54)
        ImGui.TableSetupColumn('Los', ImGuiTableColumnFlags.WidthFixed, 46)
        ImGui.TableSetupColumn('Corpse Name (range 100)')
        ImGui.TableSetupColumn('Target', ImGuiTableColumnFlags.WidthFixed, 74)
        ImGui.TableHeadersRow()
        ImGui.EndTable()
    end
end

local function render()
    if not state.open then return end
    local theme = uiThemes[state.themeKey] or uiThemes.template
    ImGui.SetNextWindowSize(760, 560, ImGuiCond.FirstUseEver)
    pushTheme()

    local draw = false
    state.open, draw = ImGui.Begin('LootMgr 1.22.0.0 [ALPHA]###LootMgrMauiWindow', state.open, ImGuiWindowFlags.NoCollapse)
    if draw then
        drawTopRow()
        drawTabs(theme)
        ImGui.Separator()
        drawScannerRow()
        drawActionRow()
        ImGui.Separator()
        ImGui.SetCursorPosX(math.max(6, (ImGui.GetWindowWidth() * 0.5) - 145))
        ImGui.Text('-- Auto-check corpses or open them manually --')
        ImGui.Separator()
        drawCorpsesTable()
    end
    ImGui.End()
    popTheme()
end

local function commandHandler(arg)
    local cmd = string.lower(tostring(arg or ''))
    if cmd == 'show' then
        state.open = true
    elseif cmd == 'hide' then
        state.open = false
    elseif cmd == 'theme' then
        loadMauiThemeFromConfig()
        print(string.format('[%s] Theme reloaded: %s', scriptName, state.themeKey))
    elseif cmd == 'stop' or cmd == 'exit' then
        state.running = false
    else
        print(string.format('[%s] Commands: /lootmaui show | hide | theme | stop', scriptName))
    end
end

loadMauiThemeFromConfig()
mq.bind('/lootmaui', commandHandler)
mq.imgui.init(scriptName, render)

while state.running do
    mq.delay(100)
end

mq.unbind('/lootmaui')
