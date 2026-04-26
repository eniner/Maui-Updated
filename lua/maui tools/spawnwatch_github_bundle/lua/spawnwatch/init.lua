local mq = require('mq')
require('ImGui')
local Icons = require('mq/Icons')

local OpenEditor, OpenSpawnViewer = false, true
local npc_list = {}
local tracked_spawns = {}
local input_npc_name = ''
local file_path = mq.luaDir .. '/npc_watchlist_by_zone.json'
local lockWindow = false
local action_status = ''
local ICON_TARGET = Icons.FA_CROSSHAIRS or 'T'
local ICON_NAV = Icons.FA_LOCATION_ARROW or 'N'
local ICON_CHECK = Icons.FA_EYE or 'C'

local function push_maui_theme()
    local pushedVars, pushedColors = 0, 0
    ImGui.PushStyleVar(ImGuiStyleVar.WindowRounding, 0.0); pushedVars = pushedVars + 1
    ImGui.PushStyleVar(ImGuiStyleVar.FrameRounding, 6.0); pushedVars = pushedVars + 1
    ImGui.PushStyleVar(ImGuiStyleVar.FrameBorderSize, 1.0); pushedVars = pushedVars + 1
    ImGui.PushStyleVar(ImGuiStyleVar.WindowPadding, 6.0, 6.0); pushedVars = pushedVars + 1
    ImGui.PushStyleColor(ImGuiCol.WindowBg, 0.03, 0.02, 0.07, 0.94); pushedColors = pushedColors + 1
    ImGui.PushStyleColor(ImGuiCol.TitleBg, 0.16, 0.03, 0.20, 0.98); pushedColors = pushedColors + 1
    ImGui.PushStyleColor(ImGuiCol.TitleBgActive, 0.28, 0.04, 0.31, 1.00); pushedColors = pushedColors + 1
    ImGui.PushStyleColor(ImGuiCol.Button, 0.20, 0.07, 0.28, 0.98); pushedColors = pushedColors + 1
    ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 0.38, 0.10, 0.46, 1.00); pushedColors = pushedColors + 1
    ImGui.PushStyleColor(ImGuiCol.ButtonActive, 0.50, 0.12, 0.56, 1.00); pushedColors = pushedColors + 1
    ImGui.PushStyleColor(ImGuiCol.FrameBg, 0.11, 0.04, 0.16, 0.95); pushedColors = pushedColors + 1
    ImGui.PushStyleColor(ImGuiCol.Header, 0.23, 0.07, 0.29, 0.98); pushedColors = pushedColors + 1
    ImGui.PushStyleColor(ImGuiCol.Border, 1.00, 0.18, 0.72, 1.00); pushedColors = pushedColors + 1
    ImGui.PushStyleColor(ImGuiCol.Separator, 0.24, 1.00, 0.92, 0.85); pushedColors = pushedColors + 1
    ImGui.PushStyleColor(ImGuiCol.Text, 0.93, 0.98, 1.00, 1.00); pushedColors = pushedColors + 1
    return pushedVars, pushedColors
end

local function pop_maui_theme(pushedVars, pushedColors)
    if pushedColors and pushedColors > 0 then ImGui.PopStyleColor(pushedColors) end
    if pushedVars and pushedVars > 0 then ImGui.PopStyleVar(pushedVars) end
end

mq.bind('/sm_edit', function()
    OpenEditor = true
end)

mq.bind('/sm_lock', function()
    lockWindow = not lockWindow
end)

mq.bind('/showspawns', function()
    OpenSpawnViewer = true
end)

local function escape_json_string(s)
    s = tostring(s or '')
    s = s:gsub('\\', '\\\\')
    s = s:gsub('"', '\\"')
    return s
end

local function table_to_json(tbl)
    local zones = {}
    for zone in pairs(tbl) do
        table.insert(zones, zone)
    end
    table.sort(zones)

    local lines = {'{'}
    for zi, zone in ipairs(zones) do
        local queries = tbl[zone] or {}
        local encoded = {}
        for i = 1, #queries do
            encoded[#encoded + 1] = '"' .. escape_json_string(queries[i]) .. '"'
        end
        local suffix = (zi < #zones) and ',' or ''
        lines[#lines + 1] = string.format('    "%s": [%s]%s', escape_json_string(zone), table.concat(encoded, ', '), suffix)
    end
    lines[#lines + 1] = '}'
    return table.concat(lines, '\n')
end

local function json_to_table(json)
    local tbl = {}
    for zone, query_list_str in json:gmatch('"([^"]+)":%s*%[(.-)%]') do
        local queries = {}
        for query in query_list_str:gmatch('"([^"]+)"') do
            table.insert(queries, query)
        end
        tbl[zone] = queries
    end
    return tbl
end

local function save_npc_list()
    local file = io.open(file_path, 'w')
    if file then
        file:write(table_to_json(npc_list))
        file:close()
    end
end

local function load_npc_list()
    local file = io.open(file_path, 'r')
    if file then
        local content = file:read('*a')
        file:close()
        npc_list = json_to_table(content) or {}
    end
end

local function nav_loaded()
    return mq.TLO.Plugin('mq2nav') and mq.TLO.Plugin('mq2nav').IsLoaded() == true
end

local function get_spawn_by_id(id)
    if not id or id <= 0 then
        return nil
    end

    local spawn = mq.TLO.Spawn(('id %d'):format(id))
    if spawn and spawn.ID() and spawn.ID() > 0 then
        return spawn
    end

    return nil
end

local function target_spawn(id, name)
    local spawn = get_spawn_by_id(id)
    if not spawn then
        action_status = ('Unable to target %s. Spawn is no longer available.'):format(name or 'spawn')
        return
    end

    mq.cmdf('/squelch /target id %d', id)
    action_status = ('Targeted %s.'):format(spawn.CleanName() or spawn.Name() or name or ('ID %d'):format(id))
end

local function nav_to_spawn(id, name)
    if not nav_loaded() then
        action_status = 'MQ2Nav is not loaded.'
        return
    end

    local spawn = get_spawn_by_id(id)
    if not spawn then
        action_status = ('Unable to navigate to %s. Spawn is no longer available.'):format(name or 'spawn')
        return
    end

    mq.cmdf('/squelch /nav id %d', id)
    action_status = ('Navigating to %s.'):format(spawn.CleanName() or spawn.Name() or name or ('ID %d'):format(id))
end

local function check_spawn(id, name)
    local spawn = get_spawn_by_id(id)
    if not spawn then
        action_status = ('%s is no longer up.'):format(name or 'Spawn')
        return
    end

    action_status = ('%s is up at (%.0f, %.0f, %.0f), %.1f away.'):format(
        spawn.CleanName() or spawn.Name() or name or ('ID %d'):format(id),
        spawn.X() or 0,
        spawn.Y() or 0,
        spawn.Z() or 0,
        spawn.Distance() or 0
    )
end

local function update_tracked_spawns()
    tracked_spawns = {}
    local current_zone = mq.TLO.Zone.ShortName() or 'Unknown'

    if npc_list[current_zone] then
        tracked_spawns[current_zone] = {}
        for _, query in ipairs(npc_list[current_zone]) do
            local spawn_count = mq.TLO.SpawnCount(query)()
            if spawn_count and spawn_count > 0 then
                for i = 1, spawn_count do
                    local spawn = mq.TLO.NearestSpawn(i, query)
                    local spawn_id = spawn and spawn.ID() or 0
                    local spawn_name = spawn and (spawn.CleanName() or spawn.Name()) or 'Unknown'
                    local spawn_loc = string.format('%d, %d, %d',
                        spawn and math.floor(spawn.X() or 0) or 0,
                        spawn and math.floor(spawn.Y() or 0) or 0,
                        spawn and math.floor(spawn.Z() or 0) or 0)
                    local spawn_distance = spawn and (spawn.Distance() or 0) or 0
                    table.insert(tracked_spawns[current_zone], {
                        id = spawn_id,
                        name = spawn_name,
                        location = spawn_loc,
                        distance = spawn_distance,
                    })
                end
            end
        end
        table.sort(tracked_spawns[current_zone], function(a, b)
            return (a.name or '') < (b.name or '')
        end)
    end
end

local function draw_editor()
    if not OpenEditor then
        return
    end

    local pushedVars, pushedColors = push_maui_theme()
    ImGui.SetNextWindowSize(400, 500, ImGuiCond.FirstUseEver)
    ImGui.SetNextWindowBgAlpha(0.6)
    OpenEditor = ImGui.Begin('Spawn Query Watchlist Editor', OpenEditor)

    local current_zone = mq.TLO.Zone.ShortName() or 'Unknown'
    ImGui.Text('Add spawn query in ' .. current_zone)
    ImGui.SetNextItemWidth(250)
    input_npc_name = ImGui.InputText('##spawnQuery', input_npc_name, 64)
    ImGui.SameLine()
    if ImGui.Button('Add') and input_npc_name ~= '' then
        if not npc_list[current_zone] then
            npc_list[current_zone] = {}
        end
        table.insert(npc_list[current_zone], input_npc_name)
        save_npc_list()
        input_npc_name = ''
    end

    for zone, queries in pairs(npc_list) do
        if ImGui.CollapsingHeader(zone) then
            if ImGui.BeginTable('WatchlistTable_' .. zone, 2, ImGuiTableFlags.Borders) then
                ImGui.TableSetupColumn('Spawn Query', ImGuiTableColumnFlags.WidthStretch)
                ImGui.TableSetupColumn('Remove', ImGuiTableColumnFlags.WidthFixed, 80)
                ImGui.TableHeadersRow()

                for i, query in ipairs(queries) do
                    ImGui.TableNextRow()
                    ImGui.TableSetColumnIndex(0)
                    ImGui.Text(query)
                    ImGui.TableSetColumnIndex(1)
                    if ImGui.Button('Remove##' .. zone .. i) then
                        table.remove(npc_list[zone], i)
                        if #npc_list[zone] == 0 then
                            npc_list[zone] = nil
                        end
                        save_npc_list()
                    end
                end
                ImGui.EndTable()
            end
        end
    end

    ImGui.End()
    pop_maui_theme(pushedVars, pushedColors)
end

local function draw_spawn_viewer()
    if not OpenSpawnViewer then
        return
    end

    local pushedVars, pushedColors = push_maui_theme()
    ImGui.SetNextWindowSize(640, 340, ImGuiCond.FirstUseEver)
    ImGui.SetNextWindowBgAlpha(0.0)

    local window_flags = ImGuiWindowFlags.NoTitleBar
    if lockWindow then
        window_flags = window_flags + ImGuiWindowFlags.NoMove
    end

    OpenSpawnViewer = ImGui.Begin('Active Spawn Viewer', OpenSpawnViewer, window_flags)

    if ImGui.Button('Open Spawn Query Editor') then
        OpenEditor = true
    end
    ImGui.SameLine()
    if ImGui.Button(lockWindow and 'Unlock Window' or 'Lock Window') then
        lockWindow = not lockWindow
    end

    local current_zone = mq.TLO.Zone.ShortName() or 'Unknown'
    ImGui.Separator()
    ImGui.TextColored(0.90, 0.90, 0.65, 1.00, 'Zone: ' .. current_zone)
    if action_status ~= '' then
        ImGui.TextWrapped(action_status)
    end
    ImGui.Separator()

    if tracked_spawns[current_zone] and #tracked_spawns[current_zone] > 0 then
        if ImGui.BeginTable('TrackedSpawnsTable', 5, ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg + ImGuiTableFlags.ScrollX + ImGuiTableFlags.SizingStretchSame) then
            ImGui.TableSetupColumn('Spawn', ImGuiTableColumnFlags.WidthStretch, 1.0)
            ImGui.TableSetupColumn('Loc', ImGuiTableColumnFlags.WidthStretch, 1.1)
            ImGui.TableSetupColumn('Target', ImGuiTableColumnFlags.WidthStretch, 0.7)
            ImGui.TableSetupColumn('Nav', ImGuiTableColumnFlags.WidthStretch, 0.55)
            ImGui.TableSetupColumn('Check', ImGuiTableColumnFlags.WidthStretch, 0.7)
            ImGui.TableHeadersRow()

            for _, spawn in ipairs(tracked_spawns[current_zone]) do
                ImGui.TableNextRow()

                ImGui.TableSetColumnIndex(0)
                ImGui.TextColored(1.00, 0.20, 0.75, 1.00, spawn.name or 'Unknown')

                ImGui.TableSetColumnIndex(1)
                ImGui.Text(spawn.location or '')

                ImGui.TableSetColumnIndex(2)
                if ImGui.Button(ICON_TARGET .. '##target_' .. tostring(spawn.id), -1, 0) then
                    target_spawn(spawn.id, spawn.name)
                end
                if ImGui.IsItemHovered() then
                    ImGui.SetTooltip('Target')
                end

                ImGui.TableSetColumnIndex(3)
                if ImGui.Button(ICON_NAV .. '##nav_' .. tostring(spawn.id), -1, 0) then
                    nav_to_spawn(spawn.id, spawn.name)
                end
                if ImGui.IsItemHovered() then
                    ImGui.SetTooltip('Navigate')
                end

                ImGui.TableSetColumnIndex(4)
                if ImGui.Button(ICON_CHECK .. '##check_' .. tostring(spawn.id), -1, 0) then
                    check_spawn(spawn.id, spawn.name)
                end
                if ImGui.IsItemHovered() then
                    ImGui.SetTooltip('Check')
                end
            end

            ImGui.EndTable()
        end
    else
        ImGui.TextColored(1, 0, 0, 1, "Nothing's Up.")
    end

    ImGui.End()
    pop_maui_theme(pushedVars, pushedColors)
end

mq.imgui.init('SpawnQueryEditor', draw_editor)
mq.imgui.init('SpawnViewer', draw_spawn_viewer)

local function main()
    load_npc_list()
    while true do
        mq.doevents()
        update_tracked_spawns()
        mq.delay(5000)
    end
end

main()
