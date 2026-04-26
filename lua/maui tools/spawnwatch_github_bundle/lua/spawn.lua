--[[
============================================================
  SpawnWatch v3.0  —  MacroQuest Next / MQ2 Lua
============================================================
  /lua run spawnwatch

  Commands:
    /sw_toggle        show/hide main window
    /sw_edit          open watchlist editor
    /sw_lock          toggle window lock / resize
    /sw_sort <col>    dist | name | hp | level | timer
    /sw_alert         toggle popup/text alerts on/off
    /sw_beep          toggle beep sound for alerts
    /sw_auto [on|off] toggle periodic scanning
    /sw_radius <n>    set camp radius filter (0 = off)
    /sw_import [path] import old spawnwatch folder or npc_watchlist_by_zone.json
    /sw_addtarget     add current target to watchlist (current zone)
    /sw_addnamed      scan current zone named and add to watchlist

  Legacy (from v1):
    /showspawns  /sm_edit  /sm_lock
============================================================
]]

local mq    = require('mq')
require('ImGui')
local Icons = require('mq/Icons')

local function icon_or(value, fallback)
    if type(value) ~= 'string' or value == '' then return fallback end
    return value
end

-- ── dkjson is bundled with MQ Lua ────────────────────────
local ok, json = pcall(require, 'dkjson')
if not ok then json = nil end   -- fallback to hand-rolled below

-----------------------------------------------------------------------
-- Version & file paths
-----------------------------------------------------------------------
local VERSION      = '3.0'
local DIR          = mq.luaDir .. '/spawnwatch/'
local FILE_LIST    = DIR .. 'watchlist.json'
local FILE_CFG     = DIR .. 'config.json'
local FILE_TIMERS  = DIR .. 'timers.json'
local FILE_NOTES   = DIR .. 'notes.json'
local FILE_IGNORED = DIR .. 'ignored_named.json'
local LEGACY_V1_FILE = mq.luaDir .. '/npc_watchlist_by_zone.json'

-----------------------------------------------------------------------
-- Icons  (FontAwesome via mq/Icons, text fallback)
-----------------------------------------------------------------------
local I = {
    target  = icon_or(Icons.FA_CROSSHAIRS,        '[T]'),
    nav     = icon_or(Icons.FA_LOCATION_ARROW,    '[N]'),
    eye     = icon_or(Icons.FA_EYE,               '[C]'),
    lock    = icon_or(Icons.FA_LOCK,              '[L]'),
    unlock  = icon_or(Icons.FA_UNLOCK,            '[U]'),
    edit    = icon_or(Icons.FA_PENCIL,            '[E]'),
    trash   = icon_or(Icons.FA_TRASH,             '[X]'),
    plus    = icon_or(Icons.FA_PLUS,              '[+]'),
    refresh = icon_or(Icons.FA_REFRESH,           '[R]'),
    bell    = icon_or(Icons.FA_BELL,              '[!]'),
    bell_o  = icon_or(Icons.FA_BELL_O,            '[-]'),
    clock   = icon_or(Icons.FA_CLOCK_O,           '[~]'),
    map     = icon_or(Icons.FA_MAP_MARKER,        '[M]'),
    note    = icon_or(Icons.FA_STICKY_NOTE_O,     '[n]'),
    skull   = icon_or(Icons.FA_SKULL,             '[D]'),
    star    = icon_or(Icons.FA_STAR,              '[*]'),
    filter  = icon_or(Icons.FA_FILTER,            '[f]'),
}

-----------------------------------------------------------------------
-- Persistent state containers
-----------------------------------------------------------------------
--  npc_list[zone]   = { query, ... }
--  spawn_notes[key] = "string"           key = zone..':'..name
--  timer_cfg[key]   = { min=N, max=N }   respawn window in seconds
--  death_log[key]   = { died_at=N, respawn_min=N, respawn_max=N, zone=z, name=n }
--  event_log        = { {time, msg, r,g,b}, ... }   capped at LOG_MAX

local npc_list   = {}
local spawn_notes= {}
local timer_cfg  = {}
local death_log  = {}
local ignored_named = {}   -- key(zone:name) -> true
local event_log  = {}
local LOG_MAX    = 200

-----------------------------------------------------------------------
-- Runtime state
-----------------------------------------------------------------------
local open_viewer    = true
local open_hud       = true
local open_editor    = false
local open_log       = false
local open_minimap   = false
local open_log       = false
local lock_window    = false
local alerts_on      = true
local alerts_beep    = false
local auto_scan      = false
local show_all_zones = false
local camp_radius    = 0          -- 0 = disabled
local filter_text    = ''
local sort_col       = 'dist'
local sort_dir       = 1
local selected_id    = 0
local status_msg     = ''
local status_color   = {0.10, 0.95, 0.50, 1.0}
local last_poll_ms   = 0
local scan_requested = false
local POLL_MS        = 5000
local LOOP_DELAY_MS  = 16
local SCAN_QUERY_BUDGET = 2
local tracked_spawns = {}         -- zone -> { entry, ... }
local prev_ids       = {}         -- zone -> { id -> true }  last poll
local total_named    = 0
local total_spawns   = 0
local scan_state     = nil
local display_cache  = {}
local display_dirty  = true
local display_cache_second = -1
local has_completed_scan = false
local last_alert_ms = {}             -- key(zone:name) -> ms
local ALERT_COOLDOWN_MS = 12000
local hud_rows = 8

-- Editor sub-state
local input_query     = ''
local input_note_key  = ''
local input_note_val  = ''
local input_timer_key = ''
local input_timer_min = 0
local input_timer_max = 0
local editor_tab      = 0   -- 0=Watchlist 1=Notes 2=Timers 3=Cleanup
local import_path     = LEGACY_V1_FILE
local bulk_timer_sel  = {}  -- key(zone:name) -> bool
local bulk_ignore_sel = {}  -- key(zone:name) -> bool

-- Note editor popup
local note_popup_key  = ''
local note_popup_val  = ''
local note_popup_open = false

-----------------------------------------------------------------------
-- ── JSON helpers ────────────────────────────────────────────────────
-- Use dkjson when available; otherwise minimal hand-rolled encode/decode
-----------------------------------------------------------------------
local function json_encode(t)
    if json then return json.encode(t, {indent=true}) end
    -- minimal fallback (handles flat string arrays & string→array maps)
    local function val(v)
        if type(v) == 'string' then
            v = v:gsub('\\','\\\\'):gsub('"','\\"'):gsub('\n','\\n')
            return '"'..v..'"'
        elseif type(v) == 'number' then return tostring(v)
        elseif type(v) == 'boolean' then return tostring(v)
        elseif type(v) == 'table' then
            -- array?
            if #v > 0 then
                local parts = {}
                for _,item in ipairs(v) do parts[#parts+1] = val(item) end
                return '['..table.concat(parts,',')..']'
            else
                local parts = {}
                local keys={}; for k in pairs(v) do keys[#keys+1]=k end; table.sort(keys)
                for _,k in ipairs(keys) do
                    parts[#parts+1] = '"'..k..'":'..val(v[k])
                end
                return '{'..table.concat(parts,',')..'}'
            end
        end
        return 'null'
    end
    return val(t)
end

local function json_decode(s)
    if json then
        local t, _, err = json.decode(s)
        if err then return nil, err end
        return t
    end
    -- minimal fallback: only handles the flat structures we actually write
    local t = {}
    -- string->string pairs
    for k,v in s:gmatch('"([^"]+)"%s*:%s*"([^"]*)"') do t[k]=v end
    -- string->number pairs
    for k,v in s:gmatch('"([^"]+)"%s*:%s*(%d+%.?%d*)') do
        if t[k]==nil then t[k]=tonumber(v) end
    end
    -- string->array-of-strings
    for k, arr in s:gmatch('"([^"]+)"%s*:%s*(%b[])') do
        if not t[k] then
            local items={}
            for item in arr:gmatch('"([^"]+)"') do items[#items+1]=item end
            t[k]=items
        end
    end
    return t
end

-----------------------------------------------------------------------
-- ── File I/O ─────────────────────────────────────────────────────────
-----------------------------------------------------------------------
local function ensure_dir()
    -- mq.luaDir already exists; just try to create our subdir
    os.execute('mkdir "' .. DIR:gsub('/','\\'):gsub('\\$','') .. '" 2>nul')
    -- Linux/Wine fallback
    os.execute('mkdir -p "' .. DIR .. '" 2>/dev/null')
end

local function read_file(path)
    local f = io.open(path,'r')
    if not f then return nil end
    local s = f:read('*a'); f:close(); return s
end

local function write_file(path, content)
    local f = io.open(path,'w')
    if f then f:write(content); f:close() end
end

local function file_exists(path)
    local f = io.open(path, 'r')
    if f then f:close(); return true end
    return false
end

local function save_all()
    write_file(FILE_LIST,   json_encode(npc_list))
    write_file(FILE_NOTES,  json_encode(spawn_notes))
    write_file(FILE_TIMERS, json_encode(timer_cfg))
    write_file(FILE_IGNORED, json_encode(ignored_named))
    -- config
    local cfg = {
        lock_window    = lock_window,
        alerts_on      = alerts_on,
        alerts_beep    = alerts_beep,
        auto_scan      = auto_scan,
        open_hud       = open_hud,
        hud_rows       = hud_rows,
        show_all_zones = show_all_zones,
        camp_radius    = camp_radius,
        sort_col       = sort_col,
        sort_dir       = sort_dir,
    }
    write_file(FILE_CFG, json_encode(cfg))
end

local function load_all()
    ensure_dir()
    local s

    s = read_file(FILE_LIST)
    if s then npc_list = json_decode(s) or {} end

    s = read_file(FILE_NOTES)
    if s then spawn_notes = json_decode(s) or {} end

    s = read_file(FILE_TIMERS)
    if s then
        local raw = json_decode(s) or {}
        -- timer_cfg[key] = {min=N, max=N}
        -- stored as key -> {min=N,max=N} object
        for k,v in pairs(raw) do
            if type(v) == 'table' then
                timer_cfg[k] = { min = tonumber(v.min) or 300, max = tonumber(v.max) or 300 }
            end
        end
    end

    s = read_file(FILE_CFG)
    if s then
        local cfg = json_decode(s) or {}
        if cfg.lock_window    ~= nil then lock_window    = cfg.lock_window    end
        if cfg.alerts_on      ~= nil then alerts_on      = cfg.alerts_on      end
        if cfg.alerts_beep    ~= nil then alerts_beep    = cfg.alerts_beep    end
        if cfg.auto_scan      ~= nil then auto_scan      = cfg.auto_scan      end
        if cfg.open_hud       ~= nil then open_hud       = cfg.open_hud       end
        if cfg.hud_rows       ~= nil then hud_rows       = math.max(3, math.min(20, tonumber(cfg.hud_rows) or 8)) end
        if cfg.show_all_zones ~= nil then show_all_zones = cfg.show_all_zones end
        if cfg.camp_radius    ~= nil then camp_radius    = tonumber(cfg.camp_radius) or 0 end
        if cfg.sort_col       ~= nil then sort_col       = cfg.sort_col       end
        if cfg.sort_dir       ~= nil then sort_dir       = tonumber(cfg.sort_dir) or 1 end
    end
end

-----------------------------------------------------------------------
-- ── Helpers ──────────────────────────────────────────────────────────
-----------------------------------------------------------------------
local function now_ms()
    return mq.gettime and mq.gettime() or (os.time() * 1000)
end

local function now_str()
    return os.date('%H:%M:%S')
end

local parse_query_exact_name

local function mark_display_dirty()
    display_dirty = true
end

local function request_scan()
    scan_requested = true
    mark_display_dirty()
end

local function activate_mini_mode()
    open_hud = true
    open_viewer = false
    open_editor = false
    open_log = false
    open_minimap = false
    save_all()
end

local function activate_advanced_mode()
    open_viewer = true
    open_hud = false
    save_all()
end

local function nav_loaded()
    local p = mq.TLO.Plugin('mq2nav')
    return p and p.IsLoaded() == true
end

local function trim(s)
    s = tostring(s or '')
    return (s:gsub('^%s+', ''):gsub('%s+$', ''))
end

local function normalize_path(path)
    path = trim(path):gsub('\\', '/')
    path = path:gsub('/+$', '')
    return path
end

local function path_join(base, name)
    base = normalize_path(base)
    if base == '' then return name end
    return base .. '/' .. name
end

local function merge_watchlist_rows(src)
    local imported, skipped = 0, 0
    if type(src) ~= 'table' then return imported, skipped end

    for zone, queries in pairs(src) do
        if type(zone) == 'string' and type(queries) == 'table' then
            npc_list[zone] = npc_list[zone] or {}
            local existing = {}
            for _, query in ipairs(npc_list[zone]) do
                existing[tostring(query)] = true
            end
            for _, query in ipairs(queries) do
                query = trim(query)
                if query ~= '' then
                    if not existing[query] then
                        npc_list[zone][#npc_list[zone] + 1] = query
                        existing[query] = true
                        imported = imported + 1
                    else
                        skipped = skipped + 1
                    end
                end
            end
        end
    end

    return imported, skipped
end

local function merge_notes_rows(src)
    local imported = 0
    if type(src) ~= 'table' then return imported end
    for k, v in pairs(src) do
        if type(k) == 'string' and type(v) == 'string' and v ~= '' then
            spawn_notes[k] = v
            imported = imported + 1
        end
    end
    return imported
end

local function merge_timer_rows(src)
    local imported = 0
    if type(src) ~= 'table' then return imported end
    for k, v in pairs(src) do
        if type(k) == 'string' and type(v) == 'table' then
            timer_cfg[k] = {
                min = tonumber(v.min) or 300,
                max = tonumber(v.max) or tonumber(v.min) or 300,
            }
            imported = imported + 1
        end
    end
    return imported
end

local function apply_import_config(cfg)
    if type(cfg) ~= 'table' then return 0 end
    local changed = 0
    if cfg.lock_window ~= nil then lock_window = cfg.lock_window == true; changed = changed + 1 end
    if cfg.alerts_on ~= nil then alerts_on = cfg.alerts_on == true; changed = changed + 1 end
    if cfg.alerts_beep ~= nil then alerts_beep = cfg.alerts_beep == true; changed = changed + 1 end
    if cfg.show_all_zones ~= nil then show_all_zones = cfg.show_all_zones == true; changed = changed + 1 end
    if cfg.camp_radius ~= nil then camp_radius = tonumber(cfg.camp_radius) or 0; changed = changed + 1 end
    if cfg.sort_col ~= nil then sort_col = tostring(cfg.sort_col); changed = changed + 1 end
    if cfg.sort_dir ~= nil then sort_dir = tonumber(cfg.sort_dir) or 1; changed = changed + 1 end
    return changed
end

local function import_legacy_data(path)
    path = normalize_path(path)
    if path == '' or path == 'auto' then
        path = LEGACY_V1_FILE
    end

    local imported_queries, skipped_queries = 0, 0
    local imported_notes, imported_timers, imported_cfg = 0, 0, 0
    local imported_any = false

    local function import_watch_file(file_path)
        local s = read_file(file_path)
        if not s then return false end
        local rows = json_decode(s)
        if type(rows) ~= 'table' then return false end
        local added, skipped = merge_watchlist_rows(rows)
        imported_queries = imported_queries + added
        skipped_queries = skipped_queries + skipped
        return true
    end

    local function import_notes_file(file_path)
        local s = read_file(file_path)
        if not s then return false end
        local rows = json_decode(s)
        if type(rows) ~= 'table' then return false end
        imported_notes = imported_notes + merge_notes_rows(rows)
        return true
    end

    local function import_timers_file(file_path)
        local s = read_file(file_path)
        if not s then return false end
        local rows = json_decode(s)
        if type(rows) ~= 'table' then return false end
        imported_timers = imported_timers + merge_timer_rows(rows)
        return true
    end

    local function import_config_file(file_path)
        local s = read_file(file_path)
        if not s then return false end
        local rows = json_decode(s)
        if type(rows) ~= 'table' then return false end
        imported_cfg = imported_cfg + apply_import_config(rows)
        return true
    end

    if path:lower():match('%.json$') then
        local lower = path:lower()
        if lower:match('npc_watchlist_by_zone%.json$') or lower:match('watchlist%.json$') then
            imported_any = import_watch_file(path) or imported_any
        elseif lower:match('notes%.json$') then
            imported_any = import_notes_file(path) or imported_any
        elseif lower:match('timers%.json$') then
            imported_any = import_timers_file(path) or imported_any
        elseif lower:match('config%.json$') then
            imported_any = import_config_file(path) or imported_any
        end
    else
        imported_any = import_watch_file(path_join(path, 'watchlist.json')) or imported_any
        imported_any = import_notes_file(path_join(path, 'notes.json')) or imported_any
        imported_any = import_timers_file(path_join(path, 'timers.json')) or imported_any
        imported_any = import_config_file(path_join(path, 'config.json')) or imported_any

        -- Really old single-file watchlist format.
        if not imported_any then
            imported_any = import_watch_file(path_join(path, 'npc_watchlist_by_zone.json')) or imported_any
        end
    end

    -- Auto-fallback to the very old root file if requested/defaulted.
    if not imported_any and path == normalize_path(LEGACY_V1_FILE) and file_exists(LEGACY_V1_FILE) then
        imported_any = import_watch_file(LEGACY_V1_FILE) or imported_any
    end

    if not imported_any then
        return false, 'No importable legacy spawn data found at: ' .. path
    end

    save_all()
    scan_requested = true
    return true, string.format(
        'Imported legacy data from %s  Queries:+%d  Dups:%d  Notes:%d  Timers:%d  Config:%d',
        path, imported_queries, skipped_queries, imported_notes, imported_timers, imported_cfg
    )
end

local function safe_spawn(id)
    if not id or id <= 0 then return nil end
    local s = mq.TLO.Spawn(('id %d'):format(id))
    if s and s.ID and s.ID() and s.ID() > 0 then return s end
    return nil
end

local function spawn_key(zone, name)
    return (zone or 'unknown') .. ':' .. (name or 'unknown')
end

-- Use spawn.Named() TLO if available, else heuristic
local function is_named(s)
    local stype = (s.Type and s.Type()) or ''
    if stype:lower() ~= 'npc' then return false end

    -- Use raw Name first for heuristics; CleanName can strip article prefixes.
    local raw_name = (s.Name and s.Name()) or ''
    local clean_name = (s.CleanName and s.CleanName()) or ''
    local low = (raw_name ~= '' and raw_name or clean_name):lower()

    -- Generic trash names often end with numeric suffixes (e.g. Guard001).
    if low:match('%d%d%d+$') then return false end

    -- Heuristic: NPC with no generic article prefix.
    if low:sub(1,2) == 'a ' then return false end
    if low:sub(1,3) == 'an ' then return false end
    if low:sub(1,4) == 'the ' then return false end

    -- Try Named() as a hint after rejecting obvious trash patterns.
    if s.Named then
        local v = s.Named()
        if type(v) == 'boolean' then return v end
    end

    s = read_file(FILE_IGNORED)
    if s then
        local raw = json_decode(s) or {}
        if type(raw) == 'table' then
            ignored_named = {}
            for k, v in pairs(raw) do
                if type(k) == 'string' and v == true then
                    ignored_named[k] = true
                end
            end
        end
    end

    return true
end

local function add_zone_query(zone, query)
    zone = trim(zone or '')
    query = trim(query or '')
    if zone == '' or query == '' then return false, 'Invalid zone/query.' end

    npc_list[zone] = npc_list[zone] or {}
    local ql = query:lower()
    for _, existing in ipairs(npc_list[zone]) do
        if tostring(existing):lower() == ql then
            return false, 'Query already tracked.'
        end
    end
    table.insert(npc_list[zone], query)
    local exact_name = parse_query_exact_name(query)
    if exact_name and exact_name ~= '' then
        ignored_named[spawn_key(zone, exact_name)] = nil
    end
    return true, 'Query added.'
end

local function make_named_query(name)
    return 'npc = ' .. trim(name or '')
end

parse_query_exact_name = function(query)
    query = trim(query or '')
    if query == '' then return nil end

    local rhs = query:match('^%s*[Nn][Pp][Cc]%s*=%s*(.+)$')
    if rhs then
        rhs = trim(rhs)
        return rhs ~= '' and rhs or nil
    end

    rhs = query:match('^%s*[Nn][Aa][Mm][Ee]%s*=%s*(.+)$')
    if rhs then
        rhs = trim(rhs)
        return rhs ~= '' and rhs or nil
    end

    if query:find('=', 1, true) then
        rhs = query:match('=%s*(.+)$')
        if rhs then
            rhs = trim(rhs)
            local lhs = (query:match('^(.-)=') or ''):lower()
            if lhs:find('name', 1, true) or lhs:find('npc', 1, true) then
                return rhs ~= '' and rhs or nil
            end
        end
        return nil
    end

    local lq = query:lower()
    if lq:find('npc', 1, true)
        or lq:find('named', 1, true)
        or lq:find('radius', 1, true)
        or lq:find('id ', 1, true)
        or lq:find('level', 1, true)
        or lq:find('class', 1, true)
        or lq:find('race', 1, true)
        or lq:find('corpse', 1, true)
        or lq:find('pet', 1, true) then
        return nil
    end

    return query
end

local function clear_query_timer_state(zone, query)
    local name = parse_query_exact_name(query)
    if not name then return 0 end
    local key = spawn_key(zone, name)
    local removed = 0
    if death_log[key] then
        death_log[key] = nil
        removed = removed + 1
    end
    if bulk_timer_sel[key] ~= nil then
        bulk_timer_sel[key] = nil
    end
    if removed > 0 then
        mark_display_dirty()
    end
    return removed
end

local function set_ignored_named(zone, name, ignored)
    local key = spawn_key(zone, name)
    if ignored then
        ignored_named[key] = true
    else
        ignored_named[key] = nil
        bulk_ignore_sel[key] = nil
    end
end

local function is_ignored_named(zone, name)
    return ignored_named[spawn_key(zone, name)] == true
end

local function prune_orphan_timers_in_zone(zone)
    local tracked_exact = {}
    for _, q in ipairs(npc_list[zone] or {}) do
        local n = parse_query_exact_name(q)
        if n and n ~= '' then tracked_exact[n:lower()] = true end
    end

    local removed = 0
    for key, dl in pairs(death_log) do
        if dl and dl.zone == zone then
            local keep = tracked_exact[(dl.name or ''):lower()] == true
            if not keep then
                death_log[key] = nil
                bulk_timer_sel[key] = nil
                removed = removed + 1
            end
        end
    end
    if removed > 0 then mark_display_dirty() end
    return removed
end

local function add_target_to_watchlist()
    local cur_zone = mq.TLO.Zone.ShortName() or 'unknown'
    local t = mq.TLO.Target
    if not t or not t() then
        return false, 'No target selected.'
    end
    local ttype = (t.Type and t.Type()) or ''
    if ttype:lower() ~= 'npc' then
        return false, 'Target is not an NPC.'
    end
    local name = (t.CleanName and t.CleanName()) or (t.Name and t.Name()) or ''
    name = trim(name)
    if name == '' then
        return false, 'Target has no valid name.'
    end

    local ok_add, msg = add_zone_query(cur_zone, make_named_query(name))
    if ok_add then
        save_all()
        request_scan()
        return true, ('Added target: %s'):format(name)
    end
    return false, ('%s (%s)'):format(msg, name)
end

local function add_named_in_zone()
    local cur_zone = mq.TLO.Zone.ShortName() or 'unknown'
    local count = mq.TLO.SpawnCount('npc named')() or 0
    if count <= 0 then
        return false, ('No named found in %s.'):format(cur_zone)
    end

    local added, dup, ignored = 0, 0, 0
    local seen_names = {}
    for i = 1, count do
        local s = mq.TLO.NearestSpawn(i, 'npc named')
        if s and s.ID and s.ID() and s.ID() > 0 then
            local name = (s.CleanName and s.CleanName()) or (s.Name and s.Name()) or ''
            name = trim(name)
            if name ~= '' then
                local nl = name:lower()
                if not seen_names[nl] then
                    seen_names[nl] = true
                    if is_ignored_named(cur_zone, name) then
                        ignored = ignored + 1
                    else
                        local ok_add = add_zone_query(cur_zone, make_named_query(name))
                        if ok_add then added = added + 1 else dup = dup + 1 end
                    end
                end
            end
        end
    end

    if added > 0 then
        save_all()
        request_scan()
        return true, ('Added %d named queries in %s (dups:%d ignored:%d).'):format(added, cur_zone, dup, ignored)
    end
    return false, ('No new named queries added in %s (dups:%d ignored:%d).'):format(cur_zone, dup, ignored)
end

local function color_for_hp(p)
    if not p then return 0.5,0.5,0.5,1 end
    if p > 75 then return 0.10,0.90,0.30,1 end
    if p > 40 then return 0.95,0.80,0.10,1 end
    if p > 15 then return 0.95,0.40,0.05,1 end
    return 0.95,0.10,0.10,1
end

local function color_for_dist(d)
    if not d then return 0.5,0.5,0.5,1 end
    if d < 100  then return 0.10,0.95,0.50,1 end
    if d < 400  then return 0.95,0.85,0.10,1 end
    return 0.95,0.30,0.30,1
end

local function fmt_seconds(s)
    if s < 0 then return '00:00' end
    return string.format('%02d:%02d', math.floor(s/60), math.floor(s%60))
end

-----------------------------------------------------------------------
-- ── Event log ────────────────────────────────────────────────────────
-----------------------------------------------------------------------
local function log_event(msg, r, g, b)
    r,g,b = r or 0.10, g or 0.95, b or 0.50
    table.insert(event_log, { t=now_str(), msg=msg, r=r, g=g, b=b })
    if #event_log > LOG_MAX then table.remove(event_log, 1) end
end

local function set_status(msg, r, g, b)
    status_msg   = msg
    status_color = { r or 0.10, g or 0.95, b or 0.50, 1.0 }
    log_event(msg, r, g, b)
end

-----------------------------------------------------------------------
-- ── Alert (beep) ─────────────────────────────────────────────────────
-----------------------------------------------------------------------
local function alert(name, zone)
    if not alerts_on then return end
    if alerts_beep then
        pcall(mq.cmd, '/beep')
    end
    -- Flash window title — change the status bar message too
    set_status(('!! ALERT: %s popped in %s !!'):format(name, zone), 1.00, 0.90, 0.10)
    print(string.format('[SpawnWatch] ALERT: %s is up in %s', name, zone))
end

-----------------------------------------------------------------------
-- ── Timer management ─────────────────────────────────────────────────
-----------------------------------------------------------------------
local function get_timer_cfg(zone, name)
    local key = spawn_key(zone, name)
    return timer_cfg[key] or { min=300, max=300 }  -- default 5 min
end


local function record_death(zone, name)
    local key  = spawn_key(zone, name)
    local tcfg = get_timer_cfg(zone, name)
    death_log[key] = {
        died_at      = now_ms(),
        respawn_min  = tcfg.min,
        respawn_max  = tcfg.max,
        zone         = zone,
        name         = name,
    }
    mark_display_dirty()
    log_event(('Timer started: %s (%.0f–%.0fs)'):format(name, tcfg.min, tcfg.max),
        0.90, 0.60, 0.10)
end

-- Returns seconds until earliest possible respawn, seconds until latest,
-- and a 0-1 progress fraction.  All nil if no timer running.
local function get_timer_info(zone, name)
    local key  = spawn_key(zone, name)
    local dl   = death_log[key]
    if not dl then return nil, nil, nil end
    local elapsed = (now_ms() - dl.died_at) / 1000
    local until_min = dl.respawn_min - elapsed
    local until_max = dl.respawn_max - elapsed
    -- fraction through the window: 0 at died_at, 1 at respawn_max
    local frac = math.min(1.0, elapsed / math.max(1, dl.respawn_max))
    return until_min, until_max, frac
end

local function clear_timer(zone, name)
    local key = spawn_key(zone, name)
    death_log[key] = nil
    mark_display_dirty()
end

-----------------------------------------------------------------------
-- ── Spawn polling ────────────────────────────────────────────────────
-----------------------------------------------------------------------

local function process_spawn_query(scan, entry, query)
    local count = mq.TLO.SpawnCount(query)()
    if not count or count <= 0 then return end

    for i = 1, count do
        local s = mq.TLO.NearestSpawn(i, query)
        if s and s.ID and s.ID() and s.ID() > 0 then
            local sid = s.ID()
            if not entry.seen_ids[sid] then
                entry.seen_ids[sid] = true
                local named = is_named(s)
                local name  = (s.CleanName and s.CleanName())
                           or (s.Name and s.Name()) or 'Unknown'
                local dist  = (s.Distance and s.Distance()) or 0

                if camp_radius <= 0 or dist <= camp_radius then
                    local row = {
                        id       = sid,
                        name     = name,
                        level    = (s.Level and s.Level()) or 0,
                        hp       = (s.PctHPs and s.PctHPs()) or 100,
                        dist     = dist,
                        loc      = string.format('%d, %d, %d',
                            math.floor((s.X and s.X()) or 0),
                            math.floor((s.Y and s.Y()) or 0),
                            math.floor((s.Z and s.Z()) or 0)),
                        x        = (s.X and s.X()) or 0,
                        y        = (s.Y and s.Y()) or 0,
                        zone     = entry.zone,
                        is_named = named,
                        note     = spawn_notes[spawn_key(entry.zone, name)] or '',
                    }
                    table.insert(entry.zone_spawns, row)
                    scan.new_total_s = scan.new_total_s + 1
                    if named then scan.new_total_n = scan.new_total_n + 1 end

                    local prev = prev_ids[entry.zone] or {}
                    local akey = spawn_key(entry.zone, name)
                    local recently_alerted = ((now_ms() - (last_alert_ms[akey] or 0)) < ALERT_COOLDOWN_MS)
                    if has_completed_scan and named and not prev[sid] and not recently_alerted then
                        last_alert_ms[akey] = now_ms()
                        alert(name, entry.zone)
                        clear_timer(entry.zone, name)
                    end
                end
            end
        end
    end
end

local function finalize_scan_zone(entry)
    local prev = prev_ids[entry.zone] or {}
    for old_id, _ in pairs(prev) do
        if not entry.seen_ids[old_id] then
            local old_tracked = tracked_spawns[entry.zone] or {}
            for _, old_sp in ipairs(old_tracked) do
                if old_sp.id == old_id then
                    record_death(entry.zone, old_sp.name)
                    break
                end
            end
        end
    end

    scan_state.new_tracked[entry.zone] = entry.zone_spawns
    prev_ids[entry.zone] = entry.seen_ids
end

local function begin_scan()
    local cur_zone = mq.TLO.Zone.ShortName() or 'unknown'
    local entries = {}
    for zone, queries in pairs(npc_list) do
        if zone == cur_zone or show_all_zones then
            entries[#entries+1] = {
                zone = zone,
                queries = queries,
                query_index = 1,
                zone_spawns = {},
                seen_ids = {},
            }
        end
    end

    scan_state = {
        entries = entries,
        entry_index = 1,
        new_tracked = {},
        new_total_n = 0,
        new_total_s = 0,
    }

    if #entries == 0 then
        tracked_spawns = {}
        total_named = 0
        total_spawns = 0
        scan_state = nil
        mark_display_dirty()
    end
end

local function finalize_scan()
    tracked_spawns = scan_state.new_tracked
    total_named = scan_state.new_total_n
    total_spawns = scan_state.new_total_s
    scan_state = nil
    has_completed_scan = true
    mark_display_dirty()
end

local function update_spawns_step()
    if not scan_state then
        begin_scan()
        if not scan_state then return true end
    end

    local budget = SCAN_QUERY_BUDGET
    while scan_state and budget > 0 do
        local entry = scan_state.entries[scan_state.entry_index]
        if not entry then
            finalize_scan()
            break
        end

        local query = entry.queries[entry.query_index]
        if query then
            process_spawn_query(scan_state, entry, query)
            entry.query_index = entry.query_index + 1
            budget = budget - 1
        else
            finalize_scan_zone(entry)
            scan_state.entry_index = scan_state.entry_index + 1
        end
    end

    return scan_state == nil
end

-----------------------------------------------------------------------
-- ── Sort / filter ────────────────────────────────────────────────────
-----------------------------------------------------------------------

local function get_display_spawns()
    local cache_second = math.floor(now_ms() / 1000)
    if not display_dirty and display_cache_second == cache_second then
        return display_cache
    end

    local cur_zone = mq.TLO.Zone.ShortName() or 'unknown'
    local all = {}
    for zone, spawns in pairs(tracked_spawns) do
        if zone == cur_zone or show_all_zones then
            for _, s in ipairs(spawns) do
                local until_min, until_max, frac = get_timer_info(s.zone, s.name)
                local row = {}
                for k, v in pairs(s) do row[k] = v end
                row.note = spawn_notes[spawn_key(s.zone, s.name)] or ''
                row.timer_until_min = until_min
                row.timer_until_max = until_max
                row.timer_frac = frac
                all[#all+1] = row
            end
        end
    end

    local shown_keys = {}
    for _, s in ipairs(all) do shown_keys[spawn_key(s.zone, s.name)] = true end

    for key, dl in pairs(death_log) do
        if not shown_keys[key] and (dl.zone == cur_zone or show_all_zones) then
            local until_min, until_max, frac = get_timer_info(dl.zone, dl.name)
            if until_max and until_max > -60 then
                all[#all+1] = {
                    id = 0,
                    name = dl.name,
                    level = 0,
                    hp = 0,
                    dist = 0,
                    loc = '---',
                    x = 0,
                    y = 0,
                    zone = dl.zone,
                    is_named = false,
                    note = spawn_notes[key] or '',
                    is_dead = true,
                    timer_until_min = until_min,
                    timer_until_max = until_max,
                    timer_frac = frac,
                }
            end
        end
    end

    local lf = filter_text:lower()
    if lf ~= '' then
        local out = {}
        for _, s in ipairs(all) do
            if s.name:lower():find(lf, 1, true)
            or tostring(s.id):find(lf, 1, true)
            or s.loc:lower():find(lf, 1, true) then
                out[#out+1] = s
            end
        end
        all = out
    end

    local function cmp(a, b)
        if (a.is_dead or false) ~= (b.is_dead or false) then
            return not (a.is_dead or false)
        end

        local asc = (sort_dir == 1)
        if sort_col == 'name' then
            local av = tostring(a.name or '')
            local bv = tostring(b.name or '')
            if av == bv then return false end
            if asc then return av < bv else return av > bv end
        elseif sort_col == 'hp' then
            local av = tonumber(a.hp) or 0
            local bv = tonumber(b.hp) or 0
            if av == bv then return false end
            if asc then return av < bv else return av > bv end
        elseif sort_col == 'level' then
            local av = tonumber(a.level) or 0
            local bv = tonumber(b.level) or 0
            if av == bv then return false end
            if asc then return av < bv else return av > bv end
        elseif sort_col == 'timer' then
            local av = tonumber(a.timer_until_max) or 99999
            local bv = tonumber(b.timer_until_max) or 99999
            if av ~= av then av = 99999 end
            if bv ~= bv then bv = 99999 end
            if av == bv then return false end
            if asc then return av < bv else return av > bv end
        else
            local av = tonumber(a.dist) or 0
            local bv = tonumber(b.dist) or 0
            if av == bv then return false end
            if asc then return av < bv else return av > bv end
        end
    end

    table.sort(all, cmp)
    display_cache = all
    display_cache_second = cache_second
    display_dirty = false
    return display_cache
end

local function toggle_sort(col)
    if sort_col == col then sort_dir = -sort_dir
    else sort_col = col; sort_dir = 1 end
    mark_display_dirty()
end

-----------------------------------------------------------------------
-- ── Actions ──────────────────────────────────────────────────────────
-----------------------------------------------------------------------
local function action_target(id, name)
    if not safe_spawn(id) then
        set_status(('%s no longer available.'):format(name), 0.95,0.30,0.30)
        return
    end
    mq.cmdf('/squelch /target id %d', id)
    selected_id = id
    set_status(('Targeted: %s'):format(name), 0.10,0.80,1.00)
end

local function action_nav(id, name)
    if not nav_loaded() then
        set_status('MQ2Nav not loaded.', 0.95,0.60,0.10)
        return
    end
    if not safe_spawn(id) then
        set_status(('%s no longer available.'):format(name), 0.95,0.30,0.30)
        return
    end
    mq.cmdf('/squelch /nav id %d', id)
    set_status(('Navigating to: %s'):format(name), 0.10,0.95,0.80)
end

local function action_check(id, name)
    local s = safe_spawn(id)
    if not s then
        set_status(('%s is NOT up.'):format(name), 0.95,0.30,0.30)
        return
    end
    local dist = s.Distance and s.Distance() or 0
    local hp   = s.PctHPs and s.PctHPs() or '?'
    set_status(('%s UP  Dist:%.0f  HP:%s%%  Loc:%s'):format(
        (s.CleanName and s.CleanName()) or name,
        dist, tostring(hp),
        string.format('%d,%d,%d',
            math.floor((s.X and s.X()) or 0),
            math.floor((s.Y and s.Y()) or 0),
            math.floor((s.Z and s.Z()) or 0))
    ), 0.10,0.95,0.50)
end

-----------------------------------------------------------------------
-- ── Draw helpers — using only ImGui.ProgressBar (confirmed MQ call) ──
-----------------------------------------------------------------------
local function draw_hp_bar(pct, w)
    pct = pct or 0
    w   = w   or 55
    local r,g,b = color_for_hp(pct)
    -- Push the bar fill color, draw, pop
    ImGui.PushStyleColor(ImGuiCol.PlotHistogram, r, g, b, 1.0)
    ImGui.ProgressBar(pct / 100.0, w, 10, '')
    ImGui.PopStyleColor()
end

local function draw_timer_bar(frac, until_min, until_max, w)
    frac = math.max(0, math.min(1, frac or 0))
    w    = w or 70
    local r = 0.90 * (1 - frac)
    local g = 0.30 + 0.65 * frac
    local in_window = (until_min and until_min <= 0) and (until_max and until_max > 0)
    -- Pulse color when pop is imminent
    if in_window then
        ImGui.PushStyleColor(ImGuiCol.PlotHistogram, 0.10, 0.95, 0.90, 1.0)
    else
        ImGui.PushStyleColor(ImGuiCol.PlotHistogram, r, g, 0.10, 1.0)
    end
    ImGui.ProgressBar(frac, w, 10, '')
    ImGui.PopStyleColor()
end

local function sort_btn(label, col)
    local active = (sort_col == col)
    if active then
        ImGui.PushStyleColor(ImGuiCol.Button, 0.38,0.10,0.56,1)
        ImGui.PushStyleColor(ImGuiCol.Text,   1.00,1.00,1.00,1)
    end
    local arrow = active and (sort_dir==1 and ' v' or ' ^') or ''
    if ImGui.SmallButton(label..arrow..'##s'..col) then toggle_sort(col) end
    if active then ImGui.PopStyleColor(2) end
    ImGui.SameLine()
end

-----------------------------------------------------------------------
-- ── Theme ────────────────────────────────────────────────────────────
-----------------------------------------------------------------------
local function push_theme()
    local pv,pc = 0,0
    local function sv(var,...) ImGui.PushStyleVar(var,...);   pv=pv+1 end
    local function sc(col,...) ImGui.PushStyleColor(col,...); pc=pc+1 end

    sv(ImGuiStyleVar.WindowRounding,  4)
    sv(ImGuiStyleVar.FrameRounding,   5)
    sv(ImGuiStyleVar.FrameBorderSize, 1)
    sv(ImGuiStyleVar.WindowPadding,   8,6)
    sv(ImGuiStyleVar.ItemSpacing,     6,4)
    sv(ImGuiStyleVar.CellPadding,     4,3)

    sc(ImGuiCol.WindowBg,           0.04,0.02,0.08,0.95)
    sc(ImGuiCol.TitleBg,            0.14,0.02,0.22,1.00)
    sc(ImGuiCol.TitleBgActive,      0.24,0.04,0.32,1.00)
    sc(ImGuiCol.MenuBarBg,          0.08,0.03,0.14,1.00)
    sc(ImGuiCol.Button,             0.18,0.06,0.26,1.00)
    sc(ImGuiCol.ButtonHovered,      0.36,0.09,0.44,1.00)
    sc(ImGuiCol.ButtonActive,       0.50,0.12,0.58,1.00)
    sc(ImGuiCol.FrameBg,            0.10,0.04,0.16,1.00)
    sc(ImGuiCol.FrameBgHovered,     0.18,0.07,0.26,1.00)
    sc(ImGuiCol.FrameBgActive,      0.26,0.10,0.36,1.00)
    sc(ImGuiCol.Header,             0.22,0.07,0.30,1.00)
    sc(ImGuiCol.HeaderHovered,      0.34,0.10,0.42,1.00)
    sc(ImGuiCol.HeaderActive,       0.44,0.13,0.52,1.00)
    sc(ImGuiCol.TableRowBg,         0.00,0.00,0.00,0.00)
    sc(ImGuiCol.TableRowBgAlt,      0.08,0.03,0.14,0.60)
    sc(ImGuiCol.TableBorderLight,   0.30,0.10,0.40,0.60)
    sc(ImGuiCol.TableBorderStrong,  0.60,0.18,0.80,0.80)
    sc(ImGuiCol.Border,             0.90,0.16,0.68,0.70)
    sc(ImGuiCol.Separator,          0.22,0.90,0.84,0.60)
    sc(ImGuiCol.ScrollbarBg,        0.02,0.01,0.06,0.80)
    sc(ImGuiCol.ScrollbarGrab,      0.30,0.08,0.40,0.80)
    sc(ImGuiCol.ScrollbarGrabHovered,0.50,0.14,0.60,0.90)
    sc(ImGuiCol.Text,               0.92,0.96,1.00,1.00)

    return pv,pc
end

local function pop_theme(pv,pc)
    if pc and pc>0 then ImGui.PopStyleColor(pc) end
    if pv and pv>0 then ImGui.PopStyleVar(pv) end
end

-----------------------------------------------------------------------
-- ── Nearby Spawns window (replaces minimap — no DrawList needed) ─────
-- Shows tracked spawns sorted by distance with bearing direction.
-- Uses only confirmed MQ ImGui calls: Text, TextColored, BeginTable etc.
-----------------------------------------------------------------------
local function draw_nearby()
    if not open_minimap then return end

    local pv,pc = push_theme()
    ImGui.SetNextWindowSize(300, 280, ImGuiCond.FirstUseEver)
    local is_open, show = ImGui.Begin('SpawnWatch — Nearby###SWNearby', open_minimap)
    open_minimap = is_open
    if not show then
        ImGui.End()
        pop_theme(pv,pc)
        return
    end

    local cur_zone = mq.TLO.Zone.ShortName() or 'unknown'
    local my_x = mq.TLO.Me.X() or 0
    local my_y = mq.TLO.Me.Y() or 0
    local my_h = mq.TLO.Me.Heading() or 0

    -- Collect live spawns for this zone sorted by distance
    local nearby = {}
    for zone, spawns in pairs(tracked_spawns) do
        if zone == cur_zone or show_all_zones then
            for _, sp in ipairs(spawns) do
                table.insert(nearby, sp)
            end
        end
    end
    table.sort(nearby, function(a,b) return (a.dist or 0) < (b.dist or 0) end)

    -- Simple bearing: 8-direction compass from player to spawn
    local function bearing(sp)
        local dx = (sp.x or 0) - my_x
        local dy = (sp.y or 0) - my_y
        if math.abs(dx) < 1 and math.abs(dy) < 1 then return 'HERE' end
        -- EQ: +Y = North, +X = East
        local angle = math.deg(math.atan2(dx, dy))
        if angle < 0 then angle = angle + 360 end
        local dirs = {'N','NE','E','SE','S','SW','W','NW','N'}
        return dirs[math.floor((angle + 22.5) / 45) + 1] or '?'
    end

    ImGui.TextDisabled(string.format('Zone: %s   You: %.0f, %.0f', cur_zone, my_x, my_y))
    ImGui.Separator()

    if #nearby == 0 then
        ImGui.TextColored(0.95,0.30,0.30,1, 'No tracked spawns up.')
    else
        local tflags = ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg + ImGuiTableFlags.ScrollY
        local _, avail_h = ImGui.GetContentRegionAvail()
        avail_h = avail_h or 200

        if ImGui.BeginTable('##nearby_tbl', 4, tflags, 0, avail_h - 4) then
            ImGui.TableSetupScrollFreeze(0, 1)
            ImGui.TableSetupColumn('Name', ImGuiTableColumnFlags.WidthStretch, 1.0)
            ImGui.TableSetupColumn('Dist', ImGuiTableColumnFlags.WidthFixed, 42)
            ImGui.TableSetupColumn('Dir',  ImGuiTableColumnFlags.WidthFixed, 30)
            ImGui.TableSetupColumn('HP%',  ImGuiTableColumnFlags.WidthFixed, 36)
            ImGui.TableHeadersRow()

            for _, sp in ipairs(nearby) do
                ImGui.TableNextRow()

                ImGui.TableSetColumnIndex(0)
                local nr,ng,nb = 1.00,0.20,0.75
                if sp.is_named then nr,ng,nb = 1.00,0.85,0.10 end
                ImGui.TextColored(nr,ng,nb,1, sp.name or '?')

                ImGui.TableSetColumnIndex(1)
                local dr,dg,db = color_for_dist(sp.dist)
                ImGui.TextColored(dr,dg,db,1, string.format('%.0f', sp.dist or 0))

                ImGui.TableSetColumnIndex(2)
                ImGui.TextDisabled(bearing(sp))

                ImGui.TableSetColumnIndex(3)
                local hr,hg,hb = color_for_hp(sp.hp)
                ImGui.TextColored(hr,hg,hb,1, string.format('%d%%', sp.hp or 0))
            end
            ImGui.EndTable()
        end
    end

    ImGui.End()
    pop_theme(pv,pc)
end

-----------------------------------------------------------------------
-- ── Event Log window ─────────────────────────────────────────────────
-----------------------------------------------------------------------
local log_scroll_bottom = true

local function draw_log()
    if not open_log then return end

    local pv,pc = push_theme()
    ImGui.SetNextWindowSize(500,300,ImGuiCond.FirstUseEver)
    local is_open, show = ImGui.Begin('SpawnWatch — Event Log###SWLog', open_log)
    open_log = is_open
    if not show then ImGui.End(); pop_theme(pv,pc); return end

    if ImGui.SmallButton('Clear') then event_log = {} end
    ImGui.SameLine()
    local new_scroll, cb_changed = ImGui.Checkbox('Auto-scroll', log_scroll_bottom)
    if cb_changed then log_scroll_bottom = new_scroll end

    ImGui.Separator()

    local lflags = ImGuiWindowFlags.HorizontalScrollbar
    ImGui.BeginChild('##logscroll', 0, 0, false, lflags)

    for _, entry in ipairs(event_log) do
        ImGui.TextDisabled('[' .. entry.t .. ']')
        ImGui.SameLine()
        ImGui.TextColored(entry.r, entry.g, entry.b, 1.0, entry.msg)
    end

    if log_scroll_bottom then
        ImGui.SetScrollHereY(1.0)
    end

    ImGui.EndChild()
    ImGui.End()
    pop_theme(pv,pc)
end

-----------------------------------------------------------------------
-- ── Note popup (inline) ──────────────────────────────────────────────
-----------------------------------------------------------------------
local function draw_note_popup()
    if not note_popup_open then return end
    ImGui.SetNextWindowSize(340, 110, ImGuiCond.Always)
    local _, show = ImGui.Begin('Edit Note###SWNote', true)
    if not show then ImGui.End(); return end
    ImGui.TextColored(0.90,0.88,0.30,1, note_popup_key)
    ImGui.SetNextItemWidth(-1)
    local nv, nc = ImGui.InputText('##noteval', note_popup_val, 256)
    if nc then note_popup_val = nv end
    if ImGui.Button('Save') then
        spawn_notes[note_popup_key] = note_popup_val
        mark_display_dirty()
        save_all()
        note_popup_open = false
        last_poll_ms = 0
    end
    ImGui.SameLine()
    if ImGui.Button('Cancel') then note_popup_open = false end
    ImGui.SameLine()
    if ImGui.Button('Clear') then
        spawn_notes[note_popup_key] = nil
        mark_display_dirty()
        save_all()
        note_popup_open = false
        last_poll_ms = 0
    end
    ImGui.End()
end

-----------------------------------------------------------------------
-- ── Main Spawn Viewer ────────────────────────────────────────────────
-----------------------------------------------------------------------
local function draw_spawn_viewer()
    if not open_viewer then return end

    local pv,pc = push_theme()
    ImGui.SetNextWindowSize(820,400,ImGuiCond.FirstUseEver)
    ImGui.SetNextWindowBgAlpha(0.95)

    local wflags = 0
    if lock_window then
        wflags = ImGuiWindowFlags.NoMove + ImGuiWindowFlags.NoResize
    end

    local cur_zone = mq.TLO.Zone.ShortName() or 'Unknown'
    local title = string.format('SpawnWatch v%s  [%s]  |  %d up  |  %d named###SWMain',
        VERSION, cur_zone, total_spawns, total_named)

    local is_open, show = ImGui.Begin(title, open_viewer, wflags)
    open_viewer = is_open
    if not show then ImGui.End(); pop_theme(pv,pc); return end

    -- ── Toolbar ──
    if ImGui.Button(I.edit..' Edit') then open_editor = not open_editor end
    ImGui.SameLine()

    if ImGui.Button(I.refresh..' Refresh') then scan_requested = true end
    ImGui.SameLine()

    local lbl = lock_window and (I.lock..' Locked') or (I.unlock..' Lock')
    if ImGui.Button(lbl) then lock_window = not lock_window end
    ImGui.SameLine()

    local alert_lbl = alerts_on and (I.bell..' Alerts') or (I.bell_o..' Muted')
    if ImGui.Button(alert_lbl) then alerts_on = not alerts_on end
    ImGui.SameLine()

    local scan_lbl = auto_scan and (I.refresh..' Auto') or (I.refresh..' Manual')
    if ImGui.Button(scan_lbl) then
        auto_scan = not auto_scan
        save_all()
        set_status(auto_scan and 'Auto scanning enabled.' or 'Manual scan mode enabled.', 0.10,0.95,0.80)
        if auto_scan then last_poll_ms = 0 end
    end
    ImGui.SameLine()

    local zone_lbl = show_all_zones and 'All Zones' or 'Cur Zone'
    if ImGui.Button(zone_lbl) then show_all_zones = not show_all_zones; request_scan(); last_poll_ms=0 end
    ImGui.SameLine()

    if ImGui.Button(I.map..' Nearby') then open_minimap = not open_minimap end
    ImGui.SameLine()

    if ImGui.Button(I.eye..' Mini') then activate_mini_mode() end
    ImGui.SameLine()

    if ImGui.Button(I.clock..' Log') then open_log = not open_log end
    ImGui.SameLine()

    -- Camp radius
    ImGui.TextDisabled('Radius')
    ImGui.SameLine()
    ImGui.SetNextItemWidth(90)
    local nr, nc = ImGui.InputInt('##radius', camp_radius, 1, 10)
    if nc then camp_radius = math.max(0, nr or 0); request_scan() end
    ImGui.SameLine()
    if camp_radius > 0 then
        ImGui.TextDisabled('(on)')
    else
        ImGui.TextDisabled('(off)')
    end
    ImGui.SameLine()

    -- Filter
    ImGui.SetNextItemWidth(130)
    local nf,fc = ImGui.InputText('##flt', filter_text, 64)
    if fc then filter_text = nf; mark_display_dirty() end
    if ImGui.IsItemHovered() then ImGui.SetTooltip('Filter by name / ID / loc') end
    ImGui.SameLine()
    ImGui.TextDisabled('Filter')

    ImGui.Separator()

    -- ── Status bar ──
    if status_msg ~= '' then
        ImGui.TextColored(status_color[1],status_color[2],status_color[3],status_color[4], status_msg)
        ImGui.Separator()
    end

    -- ── Table ──
    local display = get_display_spawns()
    if #display == 0 then
        ImGui.TextColored(0.95,0.30,0.30,1,
            "Nothing tracked in this zone. Use '"..I.edit.." Edit' to add spawn queries.")
    else
        local tflags = ImGuiTableFlags.Borders
                     + ImGuiTableFlags.RowBg
                     + ImGuiTableFlags.ScrollY
                     + ImGuiTableFlags.Resizable
                     + ImGuiTableFlags.SizingFixedFit

        local _, avail_h = ImGui.GetContentRegionAvail()
        avail_h = avail_h or 200
        local tbl_h = math.max(avail_h - 26, 60)   -- leave room for sort footer

        if ImGui.BeginTable('##sw_tbl', 10, tflags, 0, tbl_h) then
            ImGui.TableSetupScrollFreeze(0,1)

            -- Columns
            local function col(name, flags, w) ImGui.TableSetupColumn(name,flags,w) end
            local WF = ImGuiTableColumnFlags.WidthFixed
            local WS = ImGuiTableColumnFlags.WidthStretch
            col('Name',    WS, 1.0)
            col('Lvl',     WF, 30)
            col('HP%',     WF, 90)
            col('Dist',    WF, 48)
            col('Timer',   WF, 110)
            col('Loc',     WS, 0.7)
            col('Zone',    WF, 72)
            col('Type',    WF, 52)
            col('Note',    WF, 28)
            col('Actions', WF, 100)
            ImGui.TableHeadersRow()

            for row_i, sp in ipairs(display) do
                local row_uid = tostring(sp.id or 0) .. '|' .. tostring(sp.zone or '') .. '|' .. tostring(sp.name or '') .. '|' .. tostring(row_i)
                ImGui.PushID(row_uid)
                ImGui.TableNextRow()

                local is_dead = sp.is_dead or false

                -- (Row selection indicated via name color, not bg tint)

                -- Col 0: Name
                ImGui.TableSetColumnIndex(0)
                local nr2,ng,nb = 0.60,0.50,0.60   -- dead grey-ish
                if not is_dead then
                    if sp.is_named then nr2,ng,nb = 1.00,0.85,0.10
                    else nr2,ng,nb = 1.00,0.20,0.75 end
                end
                local prefix = is_dead and (I.skull..' ') or (sp.is_named and (I.star..' ') or '  ')
                ImGui.TextColored(nr2,ng,nb,1, prefix..(sp.name or '?'))

                -- Col 1: Level
                ImGui.TableSetColumnIndex(1)
                if sp.level and sp.level > 0 then
                    ImGui.TextColored(0.50,0.80,1.00,1, tostring(sp.level))
                else
                    ImGui.TextDisabled('--')
                end

                -- Col 2: HP bar
                ImGui.TableSetColumnIndex(2)
                if is_dead then
                    ImGui.TextDisabled('  DEAD')
                else
                    draw_hp_bar(sp.hp, 55)
                    ImGui.SameLine()
                    local hr2,hg,hb = color_for_hp(sp.hp)
                    ImGui.TextColored(hr2,hg,hb,1, string.format('%d%%', sp.hp or 0))
                end

                -- Col 3: Distance
                ImGui.TableSetColumnIndex(3)
                if is_dead then
                    ImGui.TextDisabled('--')
                else
                    local dr,dg,db = color_for_dist(sp.dist)
                    ImGui.TextColored(dr,dg,db,1, string.format('%.0f', sp.dist or 0))
                end

                -- Col 4: Spawn timer
                ImGui.TableSetColumnIndex(4)
                local until_min, until_max, frac = sp.timer_until_min, sp.timer_until_max, sp.timer_frac
                if until_min or until_max then
                    -- Has a timer
                    draw_timer_bar(frac or 0, until_min, until_max, 70)
                    ImGui.SameLine()
                    local in_win = (until_min and until_min <= 0) and (until_max and until_max > 0)
                    local expired = until_max and until_max < 0
                    if expired then
                        ImGui.TextColored(1.00,0.20,0.20,1,'LATE')
                    elseif in_win then
                        ImGui.TextColored(0.10,1.00,0.90,1,'NOW!')
                    else
                        local u = math.max(0, until_min or 0)
                        ImGui.TextColored(0.90,0.70,0.10,1, fmt_seconds(u))
                    end
                else
                    ImGui.TextDisabled('  --')
                    -- Show set-timer button
                    ImGui.SameLine()
                    if ImGui.SmallButton(I.clock..'##timer'..tostring(sp.id)..sp.name) then
                        -- Pre-fill editor timer for this spawn
                        input_timer_key = spawn_key(sp.zone, sp.name)
                        local tcfg = get_timer_cfg(sp.zone, sp.name)
                        input_timer_min = tcfg.min
                        input_timer_max = tcfg.max
                        open_editor = true
                        editor_tab  = 2
                    end
                    if ImGui.IsItemHovered() then ImGui.SetTooltip('Set respawn timer') end
                end

                -- Col 5: Location
                ImGui.TableSetColumnIndex(5)
                ImGui.TextDisabled(sp.loc or '')

                -- Col 6: Zone
                ImGui.TableSetColumnIndex(6)
                ImGui.TextDisabled(sp.zone or '')

                -- Col 7: Type badge
                ImGui.TableSetColumnIndex(7)
                if is_dead then
                    ImGui.TextColored(0.60,0.20,0.20,1,'[dead]')
                elseif sp.is_named then
                    ImGui.TextColored(1.00,0.85,0.10,1,'[NAMED]')
                else
                    ImGui.TextColored(0.55,0.45,0.75,1,'[ npc ]')
                end

                -- Col 8: Note icon
                ImGui.TableSetColumnIndex(8)
                local has_note = sp.note and sp.note ~= ''
                local note_col = has_note and {0.10,0.80,1.00,1} or {0.35,0.25,0.50,1}
                ImGui.PushStyleColor(ImGuiCol.Text, note_col[1],note_col[2],note_col[3],note_col[4])
                if ImGui.SmallButton(I.note..'##note'..sp.name..sp.zone) then
                    note_popup_key  = spawn_key(sp.zone, sp.name)
                    note_popup_val  = spawn_notes[note_popup_key] or ''
                    note_popup_open = true
                end
                ImGui.PopStyleColor()
                if ImGui.IsItemHovered() then
                    ImGui.SetTooltip(has_note and ('Note: '..sp.note) or 'Add note')
                end

                -- Col 9: Actions
                ImGui.TableSetColumnIndex(9)
                if not is_dead then
                    if ImGui.SmallButton(I.target..'##t'..sp.id) then
                        action_target(sp.id, sp.name)
                    end
                    if ImGui.IsItemHovered() then ImGui.SetTooltip('Target') end
                    ImGui.SameLine()

                    if ImGui.SmallButton(I.nav..'##n'..sp.id) then
                        action_nav(sp.id, sp.name)
                    end
                    if ImGui.IsItemHovered() then ImGui.SetTooltip('Navigate') end
                    ImGui.SameLine()

                    if ImGui.SmallButton(I.eye..'##c'..sp.id) then
                        action_check(sp.id, sp.name)
                    end
                    if ImGui.IsItemHovered() then ImGui.SetTooltip('Check status') end
                    ImGui.SameLine()
                end

                -- Manual timer start/clear
                if until_min or until_max then
                    if ImGui.SmallButton('X##clrt'..sp.name..sp.zone) then
                        clear_timer(sp.zone, sp.name)
                        log_event('Timer cleared: '..sp.name, 0.60,0.60,0.60)
                    end
                    if ImGui.IsItemHovered() then ImGui.SetTooltip('Clear timer') end
                else
                    if is_dead then
                        -- nothing extra
                    else
                        if ImGui.SmallButton(I.skull..'##kt'..sp.name..sp.zone) then
                            record_death(sp.zone, sp.name)
                        end
                        if ImGui.IsItemHovered() then ImGui.SetTooltip('Mark as killed (start timer)') end
                    end
                end
                ImGui.PopID()
            end

            ImGui.EndTable()
        end
    end

    -- ── Sort footer ──
    ImGui.Separator()
    ImGui.TextDisabled('Sort:')
    ImGui.SameLine()
    sort_btn('Dist',  'dist')
    sort_btn('Name',  'name')
    sort_btn('HP%',   'hp')
    sort_btn('Level', 'level')
    sort_btn('Timer', 'timer')
    ImGui.TextDisabled(string.format('  sel#%s  camp:%s',
        selected_id > 0 and tostring(selected_id) or '--',
        camp_radius  > 0 and tostring(camp_radius)..'u' or 'off'))

    ImGui.End()
    pop_theme(pv,pc)
end

local function draw_mini_hud()
    if not open_hud then return end

    local pv,pc = push_theme()
    ImGui.SetNextWindowSize(320, 220, ImGuiCond.FirstUseEver)
    ImGui.SetNextWindowBgAlpha(0.92)

    local wflags = 0
    if lock_window then
        wflags = ImGuiWindowFlags.NoMove + ImGuiWindowFlags.NoResize
    end

    local cur_zone = mq.TLO.Zone.ShortName() or 'Unknown'
    local title = string.format('SpawnWatch Mini [%s]###SWHud', cur_zone)
    local is_open, show = ImGui.Begin(title, open_hud, wflags)
    open_hud = is_open
    if not show then ImGui.End(); pop_theme(pv,pc); return end

    if ImGui.SmallButton(I.refresh..' Scan') then request_scan() end
    ImGui.SameLine()
    if ImGui.SmallButton(I.edit..' Advanced') then activate_advanced_mode() end
    ImGui.SameLine()
    if ImGui.SmallButton(I.clock..' Log') then open_log = not open_log end

    ImGui.Separator()
    ImGui.TextColored(0.10,0.95,0.80,1, string.format('%d up  |  %d named', total_spawns, total_named))
    ImGui.Separator()

    local display = get_display_spawns()
    if #display == 0 then
        ImGui.TextDisabled('No tracked spawns up.')
    else
        ImGui.BeginChild('##swhudlist', 0, 0, true)
        local shown = 0
        for _, sp in ipairs(display) do
            if shown >= hud_rows then break end
            if not sp.is_dead then
                local key = tostring(sp.id) .. tostring(sp.zone) .. tostring(sp.name)
                ImGui.PushID(key)

                if ImGui.SmallButton(I.target) then action_target(sp.id, sp.name) end
                ImGui.SameLine()
                if ImGui.SmallButton(I.nav) then action_nav(sp.id, sp.name) end
                ImGui.SameLine()

                local nr,ng,nb = sp.is_named and 1.00 or 1.00, sp.is_named and 0.85 or 0.20, sp.is_named and 0.10 or 0.75
                ImGui.TextColored(nr,ng,nb,1, string.format('%s  [%.0f]', sp.name or '?', sp.dist or 0))
                ImGui.PopID()
                shown = shown + 1
            end
        end
        if shown == 0 then
            ImGui.TextDisabled('Only timer/dead entries right now.')
        end
        ImGui.EndChild()
    end

    ImGui.End()
    pop_theme(pv,pc)
end

-----------------------------------------------------------------------
-- ── Watchlist / Notes / Timers Editor ────────────────────────────────
-----------------------------------------------------------------------
local function draw_editor()
    if not open_editor then return end

    local pv,pc = push_theme()
    ImGui.SetNextWindowSize(500,540,ImGuiCond.FirstUseEver)
    ImGui.SetNextWindowBgAlpha(0.95)
    local is_open, show = ImGui.Begin('SpawnWatch — Editor###SWEditor', open_editor)
    open_editor = is_open
    if not show then ImGui.End(); pop_theme(pv,pc); return end

    local cur_zone = mq.TLO.Zone.ShortName() or 'unknown'
    local _, avail_h = ImGui.GetContentRegionAvail()
    avail_h = avail_h or 300

    if ImGui.BeginTabBar('##SpawnWatchEditorTabsSafe') then
        if ImGui.BeginTabItem('Watchlist') then
            editor_tab = 0
            ImGui.TextColored(0.90,0.88,0.30,1,'Add query for zone: '..cur_zone)
            ImGui.SetNextItemWidth(280)
            local nq, qc = ImGui.InputText('##nq_safe', input_query, 128)
            if qc then input_query = nq end
            ImGui.SameLine()
            if ImGui.Button(I.plus..' Add##safe') and input_query ~= '' then
                local ok_add, msg = add_zone_query(cur_zone, input_query)
                if ok_add then
                    save_all()
                    set_status('Added query: '..input_query, 0.10,0.95,0.50)
                    input_query = ''
                    request_scan()
                else
                    set_status(msg, 0.95,0.60,0.10)
                end
            end
            ImGui.SameLine()
            if ImGui.Button(I.target..' Add Target##safe') then
                local ok_add, msg = add_target_to_watchlist()
                set_status(msg, ok_add and 0.10 or 0.95, ok_add and 0.95 or 0.60, ok_add and 0.50 or 0.10)
            end
            ImGui.SameLine()
            if ImGui.Button(I.star..' Scan Named##safe') then
                local ok_add, msg = add_named_in_zone()
                set_status(msg, ok_add and 0.10 or 0.95, ok_add and 0.95 or 0.60, ok_add and 0.50 or 0.10)
            end

            ImGui.SetNextItemWidth(280)
            local new_import_path, import_changed = ImGui.InputText('##legacyimport_safe', import_path, 260)
            if import_changed then import_path = new_import_path end
            ImGui.SameLine()
            if ImGui.Button(I.refresh..' Import Legacy##safe') then
                local ok_import, msg = import_legacy_data(import_path)
                if ok_import then
                    set_status(msg, 0.10,0.95,0.50)
                else
                    set_status(msg, 0.95,0.30,0.30)
                end
            end

            ImGui.Separator()
            local tf = ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg + ImGuiTableFlags.ScrollY
            if ImGui.BeginTable('##wl_safe', 3, tf, 0, avail_h-60) then
                ImGui.TableSetupScrollFreeze(0,1)
                ImGui.TableSetupColumn('Zone',  ImGuiTableColumnFlags.WidthFixed,  100)
                ImGui.TableSetupColumn('Query', ImGuiTableColumnFlags.WidthStretch, 1)
                ImGui.TableSetupColumn('Del',   ImGuiTableColumnFlags.WidthFixed,   28)
                ImGui.TableHeadersRow()

                local zones={}; for z in pairs(npc_list) do zones[#zones+1]=z end; table.sort(zones)
                local to_rm = nil
                for _,zone in ipairs(zones) do
                    for i,query in ipairs(npc_list[zone] or {}) do
                        ImGui.TableNextRow()
                        ImGui.TableSetColumnIndex(0)
                        if zone==cur_zone then ImGui.TextColored(0.10,0.95,0.80,1,zone)
                        else ImGui.TextDisabled(zone) end
                        ImGui.TableSetColumnIndex(1)
                        ImGui.Text(query)
                        ImGui.TableSetColumnIndex(2)
                        if ImGui.SmallButton(I.trash..'##d_safe'..zone..i) then to_rm={zone,i} end
                    end
                end
                if to_rm then
                    local rm_zone = to_rm[1]
                    local rm_query = npc_list[rm_zone] and npc_list[rm_zone][to_rm[2]] or ''
                    local rm_name = parse_query_exact_name(rm_query)
                    table.remove(npc_list[rm_zone], to_rm[2])
                    if #npc_list[rm_zone]==0 then npc_list[rm_zone]=nil end
                    local timer_removed = clear_query_timer_state(rm_zone, rm_query)
                    timer_removed = timer_removed + prune_orphan_timers_in_zone(rm_zone)
                    if rm_name and rm_name ~= '' then
                        set_ignored_named(rm_zone, rm_name, true)
                    end
                    save_all()
                    request_scan()
                    if timer_removed > 0 then
                        set_status(('Query removed. Cleared %d timer entries.'):format(timer_removed), 0.95,0.60,0.10)
                    else
                        if rm_name and rm_name ~= '' then
                            set_status('Query removed and remembered in ignore list.', 0.95,0.60,0.10)
                        else
                            set_status('Query removed.', 0.95,0.60,0.10)
                        end
                    end
                end
                ImGui.EndTable()
            end
            ImGui.EndTabItem()
        end

        if ImGui.BeginTabItem('Notes') then
            editor_tab = 1
            ImGui.TextColored(0.90,0.88,0.30,1, 'Per-spawn notes  (key = zone:name)')
            ImGui.Separator()
            local keys={}; for k in pairs(spawn_notes) do keys[#keys+1]=k end; table.sort(keys)
            local del_key=nil
            if #keys == 0 then
                ImGui.TextDisabled('No saved notes.')
            else
                for _,k in ipairs(keys) do
                    ImGui.TextColored(0.10,0.95,0.80,1, tostring(k))
                    ImGui.Text(tostring(spawn_notes[k] or ''))
                    if ImGui.SmallButton(I.trash..' Remove##nd_safe'..tostring(k)) then del_key=k end
                    ImGui.Separator()
                end
            end
            if del_key then
                spawn_notes[del_key]=nil
                mark_display_dirty()
                save_all()
                set_status('Note removed.', 0.95,0.60,0.10)
            end
            ImGui.EndTabItem()
        end

        if ImGui.BeginTabItem('Timers') then
            editor_tab = 2
            ImGui.TextColored(0.90,0.88,0.30,1, 'Respawn timer configuration')
            ImGui.TextDisabled('Key format: zone:SpawnName')
            ImGui.Separator()

            ImGui.SetNextItemWidth(220)
            local ntk,tkc = ImGui.InputText('Key##tkey_safe', input_timer_key, 128)
            if tkc then input_timer_key=ntk end
            ImGui.Text('Min (sec)')
            ImGui.SameLine()
            ImGui.SetNextItemWidth(150)
            local ntmin, tminc = ImGui.InputInt('##tmin_safe', input_timer_min, 1, 10)
            if tminc then input_timer_min = math.max(0, ntmin or 0) end
            ImGui.Text('Max (sec)')
            ImGui.SameLine()
            ImGui.SetNextItemWidth(150)
            local ntmax, tmaxc = ImGui.InputInt('##tmax_safe', input_timer_max, 1, 10)
            if tmaxc then input_timer_max = math.max(input_timer_min, ntmax or 0) end
            if ImGui.Button('Set Timer##safe') and input_timer_key ~= '' then
                timer_cfg[input_timer_key] = {
                    min = input_timer_min,
                    max = math.max(input_timer_min, input_timer_max),
                }
                save_all()
                set_status('Timer set: '..input_timer_key, 0.10,0.95,0.50)
            end

            ImGui.Separator()
            ImGui.TextColored(0.90,0.88,0.30,1, 'Active countdown timers:')
            local clr_key=nil
            local death_keys = {}
            for key in pairs(death_log) do death_keys[#death_keys+1] = key end
            table.sort(death_keys)
            if #death_keys == 0 then
                ImGui.TextDisabled('No active death timers.')
            else
                for _,key in ipairs(death_keys) do
                    local dl_entry = death_log[key]
                    local um, ux = get_timer_info(dl_entry.zone, dl_entry.name)
                    ImGui.TextColored(0.95,0.85,0.10,1, tostring(dl_entry.name or key))
                    ImGui.TextDisabled(tostring(dl_entry.zone or ''))
                    if um and um <= 0 then ImGui.TextColored(0.10,1,0.50,1,'Min: POP?')
                    elseif um then ImGui.TextColored(0.90,0.70,0.10,1,'Min: '..fmt_seconds(um))
                    else ImGui.TextDisabled('Min: --') end
                    if ux and ux <= 0 then ImGui.TextColored(1,0.20,0.20,1,'Max: LATE')
                    elseif ux then ImGui.Text('Max: '..fmt_seconds(ux))
                    else ImGui.TextDisabled('Max: --') end
                    if ImGui.SmallButton('Clear##cl_safe'..tostring(key)) then clr_key=key end
                    ImGui.Separator()
                end
            end
            if clr_key then
                death_log[clr_key]=nil
                mark_display_dirty()
            end

            ImGui.Separator()
            ImGui.TextColored(0.90,0.88,0.30,1,'Saved timer configs:')
            local tkeys={}; for k in pairs(timer_cfg) do tkeys[#tkeys+1]=k end; table.sort(tkeys)
            local del_tkey=nil
            if #tkeys == 0 then
                ImGui.TextDisabled('No saved timer configs.')
            else
                for _,k in ipairs(tkeys) do
                    local tc=timer_cfg[k] or {}
                    ImGui.TextColored(0.10,0.95,0.80,1, tostring(k))
                    ImGui.Text(string.format('Min: %s   Max: %s', tostring(tc.min or 0), tostring(tc.max or 0)))
                    if ImGui.SmallButton(I.trash..' Remove##td_safe'..tostring(k)) then del_tkey=k end
                    ImGui.Separator()
                end
            end
            if del_tkey then
                timer_cfg[del_tkey]=nil
                save_all()
                set_status('Timer config removed.', 0.95,0.60,0.10)
            end
            ImGui.EndTabItem()
        end
        if ImGui.BeginTabItem('Cleanup') then
            editor_tab = 3
            ImGui.TextColored(0.90,0.88,0.30,1,'Bulk timer cleanup')
            ImGui.TextDisabled('Select timers then clear selected, or clear by zone/all.')
            ImGui.Separator()

            local death_keys = {}
            for key in pairs(death_log) do death_keys[#death_keys+1] = key end
            table.sort(death_keys)

            if ImGui.SmallButton('Select All##bulk') then
                bulk_timer_sel = {}
                for _, key in ipairs(death_keys) do bulk_timer_sel[key] = true end
            end
            ImGui.SameLine()
            if ImGui.SmallButton('Select Zone##bulk') then
                for _, key in ipairs(death_keys) do
                    local dl = death_log[key]
                    if dl and dl.zone == cur_zone then bulk_timer_sel[key] = true end
                end
            end
            ImGui.SameLine()
            if ImGui.SmallButton('Clear Select##bulk') then
                local n = 0
                for key, selected in pairs(bulk_timer_sel) do
                    if selected and death_log[key] then
                        death_log[key] = nil
                        n = n + 1
                    end
                end
                if n > 0 then
                    bulk_timer_sel = {}
                    mark_display_dirty()
                    save_all()
                    set_status(('Cleared %d selected timers.'):format(n), 0.95,0.60,0.10)
                end
            end
            ImGui.SameLine()
            if ImGui.SmallButton('Clear Zone##bulk') then
                local n = 0
                for key, dl in pairs(death_log) do
                    if dl and dl.zone == cur_zone then
                        death_log[key] = nil
                        bulk_timer_sel[key] = nil
                        n = n + 1
                    end
                end
                if n > 0 then
                    mark_display_dirty()
                    save_all()
                    set_status(('Cleared %d timers in %s.'):format(n, cur_zone), 0.95,0.60,0.10)
                end
            end
            ImGui.SameLine()
            if ImGui.SmallButton('Clear All##bulk') then
                local n = 0
                for _ in pairs(death_log) do n = n + 1 end
                death_log = {}
                bulk_timer_sel = {}
                mark_display_dirty()
                save_all()
                set_status(('Cleared %d timers.'):format(n), 0.95,0.60,0.10)
            end

            ImGui.Separator()
            if #death_keys == 0 then
                ImGui.TextDisabled('No active death timers.')
            else
                ImGui.BeginChild('##bulkcleanup_list', 0, 0, true)
                for _, key in ipairs(death_keys) do
                    local dl = death_log[key]
                    if dl then
                        local checked = bulk_timer_sel[key] == true
                        local um, ux = get_timer_info(dl.zone, dl.name)
                        local timer_txt = 'n/a'
                        if ux then
                            timer_txt = (ux <= 0) and 'late' or fmt_seconds(ux)
                        elseif um then
                            timer_txt = fmt_seconds(math.max(0, um))
                        end
                        local label = string.format('%s  [%s]  %s', tostring(dl.name or key), tostring(dl.zone or '?'), timer_txt)
                        local nv, changed = ImGui.Checkbox(label .. '##bulk_' .. key, checked)
                        if changed then bulk_timer_sel[key] = nv end
                    end
                end
                ImGui.EndChild()
            end

            ImGui.Separator()
            ImGui.TextColored(0.90,0.88,0.30,1,'Ignored named memory')
            ImGui.TextDisabled('Deleted exact-name entries are remembered here and skipped by Scan Named.')

            local ignored_keys = {}
            for key in pairs(ignored_named) do ignored_keys[#ignored_keys+1] = key end
            table.sort(ignored_keys)

            if ImGui.SmallButton('Select All##ign') then
                bulk_ignore_sel = {}
                for _, key in ipairs(ignored_keys) do bulk_ignore_sel[key] = true end
            end
            ImGui.SameLine()
            if ImGui.SmallButton('Select Zone##ign') then
                for _, key in ipairs(ignored_keys) do
                    local z = key:match('^(.-):') or ''
                    if z == cur_zone then bulk_ignore_sel[key] = true end
                end
            end
            ImGui.SameLine()
            if ImGui.SmallButton('Restore Select##ign') then
                local n = 0
                for key, selected in pairs(bulk_ignore_sel) do
                    if selected and ignored_named[key] then
                        ignored_named[key] = nil
                        bulk_ignore_sel[key] = nil
                        n = n + 1
                    end
                end
                if n > 0 then
                    save_all()
                    set_status(('Restored %d ignored names.'):format(n), 0.10,0.95,0.50)
                end
            end
            ImGui.SameLine()
            if ImGui.SmallButton('Restore Zone##ign') then
                local n = 0
                for _, key in ipairs(ignored_keys) do
                    local z = key:match('^(.-):') or ''
                    if z == cur_zone and ignored_named[key] then
                        ignored_named[key] = nil
                        bulk_ignore_sel[key] = nil
                        n = n + 1
                    end
                end
                if n > 0 then
                    save_all()
                    set_status(('Restored %d ignored names in %s.'):format(n, cur_zone), 0.10,0.95,0.50)
                end
            end
            ImGui.SameLine()
            if ImGui.SmallButton('Clear Ignore All##ign') then
                local n = 0
                for _ in pairs(ignored_named) do n = n + 1 end
                ignored_named = {}
                bulk_ignore_sel = {}
                save_all()
                set_status(('Cleared %d ignored names.'):format(n), 0.10,0.95,0.50)
            end

            if #ignored_keys == 0 then
                ImGui.TextDisabled('No ignored names saved.')
            else
                ImGui.BeginChild('##ignored_named_list', 0, 130, true)
                for _, key in ipairs(ignored_keys) do
                    if ignored_named[key] then
                        local checked = bulk_ignore_sel[key] == true
                        local nv, changed = ImGui.Checkbox(key .. '##ign_' .. key, checked)
                        if changed then bulk_ignore_sel[key] = nv end
                    end
                end
                ImGui.EndChild()
            end
            ImGui.EndTabItem()
        end
        ImGui.EndTabBar()
    end

    ImGui.End()
    pop_theme(pv,pc)
    return
end

-----------------------------------------------------------------------
-- ── Slash commands ───────────────────────────────────────────────────
-----------------------------------------------------------------------
mq.bind('/sw_toggle', function() open_viewer = not open_viewer end)
mq.bind('/sw_hud', function()
    if open_hud then
        activate_advanced_mode()
    else
        activate_mini_mode()
    end
end)
mq.bind('/sw_edit',   function() open_editor = not open_editor end)
mq.bind('/sw_lock',   function() lock_window = not lock_window end)
mq.bind('/sw_alert',  function()
    alerts_on = not alerts_on
    print('[SpawnWatch] Alerts: '..tostring(alerts_on))
end)
mq.bind('/sw_beep', function()
    alerts_beep = not alerts_beep
    save_all()
    print('[SpawnWatch] Alert beep: '..tostring(alerts_beep))
end)
mq.bind('/sw_auto', function(arg)
    local v = trim(arg):lower()
    if v == 'on' then
        auto_scan = true
    elseif v == 'off' then
        auto_scan = false
    else
        auto_scan = not auto_scan
    end
    save_all()
    print('[SpawnWatch] Auto scan: '..tostring(auto_scan))
    if auto_scan then last_poll_ms = 0 end
end)
mq.bind('/sw_sort', function(col)
    col = col or 'dist'
    local valid = {dist=1,name=1,hp=1,level=1,timer=1}
    if valid[col] then toggle_sort(col)
    else print('[SpawnWatch] Valid sort cols: dist name hp level timer') end
end)
mq.bind('/sw_radius', function(n)
    camp_radius = math.max(0, tonumber(n) or 0)
    print('[SpawnWatch] Camp radius: '..tostring(camp_radius))
    scan_requested = true
end)
mq.bind('/sw_import', function(path)
    local ok_import, msg = import_legacy_data(path)
    if ok_import then
        print('[SpawnWatch] ' .. msg)
        set_status(msg, 0.10,0.95,0.50)
    else
        print('[SpawnWatch] ' .. msg)
        set_status(msg, 0.95,0.30,0.30)
    end
end)
mq.bind('/sw_addtarget', function()
    local ok_add, msg = add_target_to_watchlist()
    print('[SpawnWatch] ' .. msg)
    set_status(msg, ok_add and 0.10 or 0.95, ok_add and 0.95 or 0.60, ok_add and 0.50 or 0.10)
end)
mq.bind('/sw_addnamed', function()
    local ok_add, msg = add_named_in_zone()
    print('[SpawnWatch] ' .. msg)
    set_status(msg, ok_add and 0.10 or 0.95, ok_add and 0.95 or 0.60, ok_add and 0.50 or 0.10)
end)

-- Legacy compat
mq.bind('/showspawns', function() open_viewer = true end)
mq.bind('/sm_edit',    function() open_editor = true end)
mq.bind('/sm_lock',    function() lock_window = not lock_window end)

-----------------------------------------------------------------------
-- ── ImGui registrations ──────────────────────────────────────────────
-----------------------------------------------------------------------
mq.imgui.init('SWViewer',  draw_spawn_viewer)
mq.imgui.init('SWHud',     draw_mini_hud)
mq.imgui.init('SWEditor',  draw_editor)
mq.imgui.init('SWLog',     draw_log)
mq.imgui.init('SWNearby',  draw_nearby)
mq.imgui.init('SWNote',    draw_note_popup)

-----------------------------------------------------------------------
-- ── Main loop ────────────────────────────────────────────────────────
-----------------------------------------------------------------------
local function main()
    load_all()
    set_status('SpawnWatch v'..VERSION..' ready.  /sw_edit to manage watchlist.', 0.10,0.95,0.80)
    print('[SpawnWatch] v'..VERSION..' started.')
    print('[SpawnWatch] Commands: /sw_toggle /sw_edit /sw_lock /sw_alert /sw_beep /sw_auto /sw_sort /sw_radius /sw_addtarget /sw_addnamed')
    if auto_scan then
        last_poll_ms = 0
    else
        last_poll_ms = now_ms()
        set_status('SpawnWatch ready. Manual scan mode: click Refresh to scan.', 0.10,0.95,0.80)
    end

    while open_viewer or open_hud or open_editor or open_log or open_minimap do
        mq.doevents()

        local t = now_ms()
        if scan_requested and not scan_state then
            begin_scan()
            if not scan_state then
                scan_requested = false
            end
        end
        if auto_scan and not scan_requested and not scan_state and (t - last_poll_ms) >= POLL_MS then
            begin_scan()
            last_poll_ms = t
        end
        if scan_state and update_spawns_step() then
            scan_requested = false
            last_poll_ms = t
        end

        mq.delay(LOOP_DELAY_MS)
    end

    -- Save state on exit
    save_all()
    print('[SpawnWatch] Exited cleanly.')
end

main()

