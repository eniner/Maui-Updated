local mq = require('mq')
require('ImGui')
local Icons = require('mq/Icons')

local has_json, json = pcall(require, 'dkjson')

local function file_exists(path)
    local f = io.open(tostring(path or ''), 'r')
    if not f then return false end
    f:close()
    return true
end

local function path_join(a, b)
    local left = tostring(a or ''):gsub('\\', '/'):gsub('/+$', '')
    local right = tostring(b or ''):gsub('\\', '/'):gsub('^/+', '')
    if left == '' then return right end
    if right == '' then return left end
    return left .. '/' .. right
end

local function unique_push(list, seen, value)
    local v = tostring(value or '')
    if v == '' then return end
    if seen[v] then return end
    seen[v] = true
    list[#list + 1] = v
end

local function resolve_eq_data_file(filename, fallback_path)
    local roots, seen = {}, {}
    local config_dir = tostring(mq.configDir or '.')
    local lua_dir = tostring(mq.luaDir or '.')
    local user_profile = tostring(os.getenv('USERPROFILE') or '')
    local eq_env = tostring(os.getenv('EQPATH') or '')
    local eq_env2 = tostring(os.getenv('EVERQUEST_PATH') or '')

    unique_push(roots, seen, eq_env)
    unique_push(roots, seen, eq_env2)
    unique_push(roots, seen, path_join(user_profile, 'EverQuest'))
    unique_push(roots, seen, path_join(user_profile, 'Desktop/Emul Stuff/Ultimate/Ultimate'))
    unique_push(roots, seen, 'C:/EverQuest')

    local bases = { config_dir, lua_dir }
    for _, base in ipairs(bases) do
        unique_push(roots, seen, base)
        unique_push(roots, seen, path_join(base, '..'))
        unique_push(roots, seen, path_join(base, '../..'))
        unique_push(roots, seen, path_join(base, '../../..'))
        unique_push(roots, seen, path_join(base, '../../../..'))
        unique_push(roots, seen, path_join(base, '../../../../..'))
        unique_push(roots, seen, path_join(base, '../../../../../..'))
        unique_push(roots, seen, path_join(base, '../../../../../../..'))

        unique_push(roots, seen, path_join(base, '../EverQuest'))
        unique_push(roots, seen, path_join(base, '../../EverQuest'))
        unique_push(roots, seen, path_join(base, '../../../EverQuest'))
        unique_push(roots, seen, path_join(base, '../../../../EverQuest'))
        unique_push(roots, seen, path_join(base, '../../../../../EverQuest'))
        unique_push(roots, seen, path_join(base, '../../../../../../EverQuest'))
    end

    for _, root in ipairs(roots) do
        local candidate = path_join(root, filename)
        if file_exists(candidate) then
            return candidate
        end
    end
    return tostring(fallback_path or path_join(config_dir, '../../../../EverQuest/' .. filename))
end

local function icon_or(value, fallback)
    if type(value) ~= 'string' or value == '' then return fallback end
    return value
end

local I = {
    play    = icon_or(Icons.FA_PLAY,          '[>]'),
    pause   = icon_or(Icons.FA_PAUSE,         '[||]'),
    save    = icon_or(Icons.FA_SAVE,          '[S]'),
    check   = icon_or(Icons.FA_CHECK,         '[OK]'),
    ban     = icon_or(Icons.FA_BAN,           '[X]'),
    clear   = icon_or(Icons.FA_TRASH,         '[CLR]'),
    refresh = icon_or(Icons.FA_REFRESH,       '[R]'),
    clock   = icon_or(Icons.FA_CLOCK_O,       '[~]'),
}

local SCRIPT_NAME = 'npc_dialog_console'
local EVENT_NAME = 'npc_dialog_console_chat'
local CMD_NAME = '/ndc'
local BASE_DIR = (mq.configDir or '.') .. '/npc_dialog_logger'
local SITE_DIR = BASE_DIR .. '/site_export'
local NPC_EXPORT_NPCS_DIR = SITE_DIR .. '/npcs'
local MASTER_FILE = BASE_DIR .. '/master_dialog.json'
local DBSTR_SOURCE = resolve_eq_data_file('dbstr_us.txt', (mq.configDir or '.') .. '/../../../../EverQuest/dbstr_us.txt')
local SPELLS_SOURCE = resolve_eq_data_file('spells_us.txt', (mq.configDir or '.') .. '/../../../../EverQuest/spells_us.txt')
local USER_DBSTR_HINT = path_join(os.getenv('USERPROFILE') or '', 'Desktop/Emul Stuff/Ultimate/Ultimate/dbstr_us.txt')
local USER_SPELLS_HINT = path_join(os.getenv('USERPROFILE') or '', 'Desktop/Emul Stuff/Ultimate/Ultimate/spells_us.txt')
local USER_MD_HINT = path_join(os.getenv('USERPROFILE') or '', 'Downloads/dbstr_spells_builder_prompt.md')
local DBSTR_OUT = BASE_DIR .. '/dbstr_us_patched.txt'
local SPELLS_OUT = BASE_DIR .. '/spells_us_patched.txt'
local DBSTR_BUILDER_SETTINGS_FILE = BASE_DIR .. '/dbstr_spells_builder_settings.json'
local DBSTR_SCAN_CACHE_FILE = BASE_DIR .. '/scan_cache.json'
local SAFE_SPELL_ID_MIN = 40000
local SAFE_SPELL_ID_MAX = 49999

local ui_open = true
local logging_enabled = false
local auto_scroll = true
local status_msg = 'Idle'
local status_color = { 0.90, 0.88, 0.30, 1.0 }
local loop_active = true
local dbstr_builder = {
    open = false,
    status = 'Idle',
    status_color = { 0.90, 0.88, 0.30, 1.0 },
    dbstr_path = DBSTR_SOURCE,
    spells_path = SPELLS_SOURCE,
    dbstr_out = DBSTR_OUT,
    spells_out = SPELLS_OUT,
    problems = {},
    proposals = {},
    log = {},
    running = false,
    scan_dialog_relevant_only = false,
    markdown_path = USER_MD_HINT,
    imported_hints = {},
    imported_spell_candidates = {},
    imported_hint_count = 0,
    table_search = '',
    create_missing_spell_entries = true,
    search_use_regex = false,
    saved_searches = {},
    proposal_confidence_threshold = 70,
    proposal_source_filter = 'all',
    scan_file_scope = 'both',
    scan_issue_scope = 'descriptions_only',
    scan_incremental = false,
    dry_run_mode = false,
    scan_cache = {},
    selected_problem_rows = {},
    selected_proposal_rows = {},
    edit_before_accept = false,
    show_spell_panel = false,
    spell_panel_id = 0,
    spell_panel_raw = '',
    show_preview_patch = false,
    preview_patch_text = '',
    last_action_undo = nil,
    live_feed_search = '',
    pending_search = '',
    accepted_search = '',
    active_npc_filter = 'All',
    line_tags = {},
    last_scan_at = '',
    last_write_at = '',
    unsaved_changes = false,
}

local player_name = mq.TLO.Me.CleanName() or 'unknown'
local server_name = mq.TLO.EverQuest.Server() or ''

local pending_player = nil
local last_npc = nil
local active_npc = nil
local active_npc_ts = 0
local pending_records = {}
local accepted_records = {}
local feed = {}
local FEED_MAX = 400
local feed_dirty = false
local last_popup_signature = nil
local section_header_warned = {}
-- CONFIG: minimum overlap ratio to consider two non-section dialog blocks duplicates.
local BLOCK_DEDUPE_SIMILARITY = 0.80
-- CONFIG: many direct-cast spells legitimately have no wear-off text.
local REQUIRE_WEAR_OFF_MESSAGE = false
local CHECK_SPELL_CAST_MESSAGES = false
-- PERF: keep live logging snappy; expensive duplicate math is optional.
local ENABLE_LIVE_DUPLICATE_DETECTION = false
-- PERF: when proposal set is huge, use fast matching path.
local FAST_PROPOSE_THRESHOLD = 5000
-- PERF/QUALITY: exported site markdown can be very large/noisy.
local USE_EXPORTED_MARKDOWN_CONTEXT = false
-- PERF: live feed link button lookup can be expensive on huge datasets.
local ENABLE_FEED_LINK_BUTTONS = false

local function now_iso()
    return os.date('!%Y-%m-%dT%H:%M:%SZ')
end

local function trim(s)
    return tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

local function normalize_key(s)
    return trim(s):lower()
end

local function sanitize_text(s)
    local t = tostring(s or '')
    t = t:gsub('\\a[%a%+%-]', '')
    t = t:gsub('\r', '')
    t = t:gsub('[%z\1-\31]', '')
    return trim(t)
end

local function strip_log_prefix(line)
    local t = tostring(line or '')
    t = t:gsub("^%b[]%s*", "")
    return t
end

local function strip_wrapping_quotes(text)
    local t = trim(text or '')
    if t:sub(1, 1) == "'" and t:sub(-1) == "'" and #t >= 2 then
        t = t:sub(2, -2)
    end
    return trim(t)
end

local function normalize_dialog_text(text)
    local t = sanitize_text(strip_wrapping_quotes(text))
    -- Convert popup HTML-ish breaks to spaces before further cleanup.
    t = t:gsub("<%s*[bB][rR]%s*/?%s*>", " ")
    -- Strip remaining UI/markup tags (e.g. <c "#00FFFF">, </c>, etc.).
    t = t:gsub("<[^>]->", " ")
    t = t:gsub("%[([^%]]+)%]", function(inner)
        local cleaned = trim(inner or '')
        -- MQ payload may start with long hex and run directly into label text.
        -- Use frontier so first label letter (A-F included) is not consumed.
        cleaned = cleaned:gsub("^(%x+)%f[%a]", function(prefix)
            if #prefix >= 16 then return '' end
            return prefix
        end)
        cleaned = trim(cleaned)
        if cleaned == '' then return '' end
        return "[" .. cleaned .. "]"
    end)
    -- Catch payload blobs that can appear outside bracket replacements.
    t = t:gsub("(0%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x+)%f[%a]", "")
    t = t:gsub("%f[%w]0%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x+%f[^%w]", "")
    t = t:gsub("&nbsp;", " ")
    t = t:gsub("%s+", " ")
    return trim(t)
end

local function parse_section_header_title(line)
    local l = normalize_dialog_text(line)
    local title = l:match("^%-+%s*[iI][nN][fF][oO]%s*%-%s*(.-)%s*%-*%s*$")
    if not title then
        title = l:match("[iI][nN][fF][oO]%s*%-%s*(.-)%s*%-*%s*$")
    end
    if not title then return nil end
    title = trim(title:gsub("^%-+", ""):gsub("%-+$", ""))
    if title == '' then return nil end
    title = title:gsub('^%l', string.upper)
    return title
end

local function looks_like_section_hint(line)
    local l = tostring(line or ''):lower()
    return l:find('info%s*%-') ~= nil
end

local function keywordize_html(line)
    local function esc(s)
        local t = tostring(s or '')
        t = t:gsub('&', '&amp;')
        t = t:gsub('<', '&lt;')
        t = t:gsub('>', '&gt;')
        t = t:gsub('"', '&quot;')
        return t
    end
    local src = tostring(line or '')
    local out = {}
    local idx = 1
    while true do
        local s, e, kw = src:find('%[([^%]]+)%]', idx)
        if not s then
            out[#out + 1] = esc(src:sub(idx))
            break
        end
        out[#out + 1] = esc(src:sub(idx, s - 1))
        out[#out + 1] = '<span class="keyword">[' .. esc(kw) .. ']</span>'
        idx = e + 1
    end
    return table.concat(out)
end

local function response_total_for_record(rec)
    local total = 0
    for _, r in pairs(rec.responses or {}) do
        total = total + (tonumber(r.count) or 1)
    end
    return total
end

local function token_set(text)
    local set = {}
    for w in tostring(text or ''):lower():gmatch('[%a%d_]+') do
        if #w > 1 then set[w] = true end
    end
    return set
end

local function cosine_like_similarity(a, b)
    local sa, sb = token_set(a), token_set(b)
    local da, db, dot = 0, 0, 0
    for k in pairs(sa) do
        da = da + 1
        if sb[k] then dot = dot + 1 end
    end
    for _ in pairs(sb) do db = db + 1 end
    if da == 0 or db == 0 then return 0 end
    return dot / math.sqrt(da * db)
end

local function parse_npc_dialog_line(line)
    local l = trim(line or '')
    if l == '' then return nil, nil end

    local patterns = {
        "^(.-) says, in .-,%s*(.+)$",
        "^(.-) says,%s*(.+)$",
        "^(.-) says%s+(.+)$",
        "^(.-) whispers, in .-,%s*(.+)$",
        "^(.-) whispers,%s*(.+)$",
        "^(.-) whispers%s+(.+)$",
        "^(.-) whispers to you, in .-,%s*(.+)$",
        "^(.-) whispers to you,%s*(.+)$",
        "^(.-) whispers to you%s+(.+)$",
        "^(.-) tells you, in .-,%s*(.+)$",
        "^(.-) tells you,%s*(.+)$",
        "^(.-) tells you%s+(.+)$",
    }

    for _, pat in ipairs(patterns) do
        local npc, text = l:match(pat)
        if npc and text then
            return sanitize_text(npc), normalize_dialog_text(text)
        end
    end
    return nil, nil
end

local function is_non_npc_chat_line(line)
    local l = (line or ''):lower()
    if l:find(' says out of character,', 1, true) then return true end
    if l:find(' says from discord,', 1, true) then return true end
    if l:find(' tells out of character,', 1, true) then return true end
    return false
end

local function active_chain_continuation_npc()
    local now_ts = os.time()
    if active_npc and (now_ts - active_npc_ts) <= 8 then
        return active_npc
    end
    return nil
end

local function zone_short()
    return mq.TLO.Zone.ShortName() or ''
end

local function zone_long()
    return mq.TLO.Zone.Name() or ''
end

local function ensure_dir(path)
    if not path or path == '' then return end
    os.execute(('mkdir "%s" >nul 2>nul'):format(path))
end

local function push_feed(kind, msg, r, g, b)
    local dup = false
    if ENABLE_LIVE_DUPLICATE_DETECTION and kind == 'pending' and msg and msg ~= '' then
        for _, rec in pairs(accepted_records or {}) do
            for _, ln in ipairs(rec.ordered_lines or {}) do
                if cosine_like_similarity(msg, ln.text or '') > 0.85 then
                    dup = true
                    break
                end
            end
            if dup then break end
        end
    end
    local key = tostring(os.time()) .. '|' .. tostring(#feed + 1) .. '|' .. tostring(msg or '')
    feed[#feed + 1] = {
        key = key,
        t = os.date('%H:%M:%S'),
        kind = kind,
        msg = msg,
        r = r or 0.90,
        g = g or 0.90,
        b = b or 0.90,
        dup = dup,
        tag = dbstr_builder.line_tags[key],
    }
    if #feed > FEED_MAX then
        table.remove(feed, 1)
    end
    feed_dirty = true
end

local function fallback_json_encode(value)
    local tv = type(value)
    if tv == 'nil' then return 'null' end
    if tv == 'boolean' then return value and 'true' or 'false' end
    if tv == 'number' then return tostring(value) end
    if tv == 'string' then
        local escaped = value
            :gsub('\\', '\\\\')
            :gsub('"', '\\"')
            :gsub('\n', '\\n')
            :gsub('\r', '\\r')
            :gsub('\t', '\\t')
        return '"' .. escaped .. '"'
    end
    if tv ~= 'table' then return 'null' end

    local is_array = true
    local max_index = 0
    for k in pairs(value) do
        if type(k) ~= 'number' or k < 1 or k % 1 ~= 0 then
            is_array = false
            break
        end
        if k > max_index then max_index = k end
    end

    local out = {}
    if is_array then
        for i = 1, max_index do out[#out + 1] = fallback_json_encode(value[i]) end
        return '[' .. table.concat(out, ',') .. ']'
    end

    for k, v in pairs(value) do
        out[#out + 1] = fallback_json_encode(tostring(k)) .. ':' .. fallback_json_encode(v)
    end
    return '{' .. table.concat(out, ',') .. '}'
end

local function encode_json(value)
    if has_json and json and json.encode then
        local s = json.encode(value, { indent = true })
        if s then return s end
    end
    return fallback_json_encode(value)
end

local function decode_json(content)
    if has_json and json and json.decode then
        local decoded = json.decode(content)
        if decoded then return decoded end
    end
    return nil
end

local function record_count(map)
    local c = 0
    for _ in pairs(map) do c = c + 1 end
    return c
end

local function response_count(map)
    local c = 0
    for _, rec in pairs(map) do
        for _ in pairs(rec.responses or {}) do c = c + 1 end
    end
    return c
end

local function ensure_record(store, npc_name)
    local key = normalize_key(npc_name)
    if key == '' then key = '__unknown_npc__' end

    local rec = store[key]
    if rec then return rec end

    rec = {
        npc_name = trim(npc_name) ~= '' and trim(npc_name) or 'Unknown NPC',
        zone_short = zone_short(),
        zone_long = zone_long(),
        first_seen_at = now_iso(),
        last_seen_at = now_iso(),
        ordered_lines = {},
        item_details = {},
        responses = {},
    }
    store[key] = rec
    return rec
end

local function upsert_response(rec, response_text, triggered_by)
    local key = normalize_key(response_text)
    local r = rec.responses[key]
    if not r then
        r = {
            text = response_text,
            count = 0,
            triggered_by = {},
        }
        rec.responses[key] = r
    end

    r.count = r.count + 1

    if triggered_by and triggered_by ~= '' then
        local tkey = normalize_key(triggered_by)
        if tkey ~= '' then
            r.triggered_by[tkey] = (r.triggered_by[tkey] or 0) + 1
        end
    end

end

local function extract_dialog_links(raw_msg)
    local out = {}
    local links = mq.ExtractLinks(raw_msg)
    if not links then return out end

    for _, link in ipairs(links) do
        if link.type == mq.LinkTypes.Dialog then
            local parsed = mq.ParseDialogLink(link.link)
            out[#out + 1] = {
                keyword = sanitize_text(parsed.keyword or parsed.text or ''),
                text = sanitize_text(parsed.text or parsed.keyword or ''),
                raw = link.link,
            }
        end
    end
    return out
end

local function capture_player_say(text)
    local keyword = sanitize_text(text)
    if keyword == '' then return end

    local target_name = ''
    if mq.TLO.Target.ID() and mq.TLO.Target.ID() > 0 and (mq.TLO.Target.Type() or ''):lower() == 'npc' then
        target_name = mq.TLO.Target.CleanName() or mq.TLO.Target.Name() or ''
    elseif last_npc and (os.time() - (last_npc.when or 0) <= 12) then
        target_name = last_npc.name or ''
    end

    pending_player = {
        keyword = keyword,
        npc_name = target_name,
        ts = os.time(),
    }

    push_feed('player', 'You -> "' .. keyword .. '"', 0.80, 0.92, 1.00)
end

local function capture_npc_say(npc_name, text, raw_msg, force_capture, opts)
    local npc = sanitize_text(npc_name)
    local response = normalize_dialog_text(text)
    if npc == '' or response == '' then return end

    last_npc = { name = npc, when = os.time() }

    local links = extract_dialog_links(raw_msg)
    local trigger = nil

    if pending_player and (os.time() - pending_player.ts <= 12) then
        if pending_player.npc_name == '' or normalize_key(pending_player.npc_name) == normalize_key(npc) then
            trigger = pending_player.keyword
            pending_player = nil
        end
    end

    if response == '' or response == '-' or response:match("^%-[%-%s]+$") then
        return
    end

    local now_ts = os.time()
    local in_active_chain = (active_npc and normalize_key(active_npc) == normalize_key(npc) and (now_ts - active_npc_ts) <= 8)

    if force_capture then
        active_npc = npc
        active_npc_ts = now_ts
    elseif trigger or #links > 0 then
        active_npc = npc
        active_npc_ts = now_ts
    elseif in_active_chain then
        active_npc_ts = now_ts
    else
        return
    end

    local rec = ensure_record(pending_records, npc)
    rec.last_seen_at = now_iso()
    rec.zone_short = zone_short()
    rec.zone_long = zone_long()
    local response_key = normalize_key(response)
    local existing_line = nil
    for _, line in ipairs(rec.ordered_lines or {}) do
        if normalize_key(line.text or '') == response_key then
            existing_line = line
            break
        end
    end
    if existing_line then
        existing_line.repeat_count = (tonumber(existing_line.repeat_count) or 1) + 1
    else
        rec.ordered_lines[#rec.ordered_lines + 1] = {
            ts = now_iso(),
            player_trigger = trigger,
            text = response,
            repeat_count = 1,
        }
    end

    if opts and opts.item_context and opts.item_context ~= '' then
        local item_key = normalize_key(opts.item_context)
        if item_key ~= '' then
            if not rec.item_details[item_key] then
                rec.item_details[item_key] = { item_name = opts.item_context, lines = {} }
            end
            local entry = rec.item_details[item_key]
            local duplicate = false
            for _, existing in ipairs(entry.lines) do
                if normalize_key(existing) == normalize_key(response) then
                    duplicate = true
                    break
                end
            end
            if not duplicate then
                entry.lines[#entry.lines + 1] = response
            end
        end
    end

    upsert_response(rec, response, trigger)

    local note = ('%s: %s'):format(npc, response)
    if parse_section_header_title(response) then
        push_feed('pending', note, 0.55, 0.55, 0.55)
    else
        push_feed('pending', note, 1.00, 0.84, 0.20)
    end
end

local function split_lines(text)
    local out = {}
    local src = tostring(text or '')
    src = src:gsub("<%s*[bB][rR]%s*/?%s*>", "\n")
    for line in src:gmatch("[^\r\n]+") do
        out[#out + 1] = trim(line)
    end
    return out
end

local function infer_popup_item(lines)
    for _, line in ipairs(lines or {}) do
        local l = normalize_dialog_text(line)
        if l ~= '' and not l:match("^Cost%s*%d+") and not l:match("^%d+%.") and #l <= 80 then
            return l
        end
    end
    return nil
end

local function read_window_text(window_name, child_name)
    local w = mq.TLO.Window(window_name)
    if not w() or not w.Open() then return nil end
    local target = w
    if child_name and child_name ~= '' then
        target = w.Child and w.Child(child_name) or nil
    end
    if not target then return nil end
    local ok, txt = pcall(function()
        if target.Text then return target.Text() end
        return nil
    end)
    if ok and type(txt) == 'string' and trim(txt) ~= '' then
        return txt
    end
    return nil
end

local function popup_capture_npc_name()
    if active_npc and active_npc ~= '' then return active_npc end
    if mq.TLO.Target.ID() and mq.TLO.Target.ID() > 0 and (mq.TLO.Target.Type() or ''):lower() == 'npc' then
        return mq.TLO.Target.CleanName() or mq.TLO.Target.Name() or 'Popup'
    end
    return 'Popup'
end

local function capture_popup_windows()
    if not logging_enabled then return end

    local candidates = {
        { wnd = 'LargeDialogWindow', child = 'LDW_TextBox' },
        { wnd = 'Buy', child = 'LDW_TextBox' },
        { wnd = 'Buy', child = '' },
    }

    local saw_popup = false
    for _, c in ipairs(candidates) do
        local txt = read_window_text(c.wnd, c.child)
        if txt and txt ~= '' then
            saw_popup = true
            local sig = c.wnd .. '|' .. txt
            if sig ~= last_popup_signature then
                last_popup_signature = sig
                local npc = popup_capture_npc_name()
                local popup_lines = split_lines(txt)
                local popup_item = infer_popup_item(popup_lines)
                for _, line in ipairs(popup_lines) do
                    local cleaned = normalize_dialog_text(line)
                    if cleaned ~= '' and cleaned:lower() ~= 'yes' and cleaned:lower() ~= 'no' then
                        capture_npc_say(npc, cleaned, cleaned, true, { item_context = popup_item })
                    end
                end
            end
            return
        end
    end

    -- Reset dedupe once popup is no longer open so reopening same content captures again.
    if not saw_popup then
        last_popup_signature = nil
    end
end

local function on_chat(msg)
    if not logging_enabled then return end
    local line = sanitize_text(strip_log_prefix(msg))
    if line == '' then return end
    if is_non_npc_chat_line(line) then return end

    local you_say = line:match("^You say, '(.*)'$")
    if you_say then
        capture_player_say(you_say)
        return
    end

    local npc_name, npc_text = parse_npc_dialog_line(line)
    if npc_name and npc_text then
        capture_npc_say(npc_name, npc_text, msg)
        return
    else
        local chain_npc = active_chain_continuation_npc()
        if chain_npc and not line:match('^You%s') and not line:match('^%b[]') then
            -- Some merchant/guide outputs continue on plain lines without "NPC whispers," prefix.
            capture_npc_say(chain_npc, line, msg)
            return
        end
    end
end

local function merge_store_into(target, source)
    for key, rec in pairs(source) do
        if not target[key] then
            target[key] = {
                npc_name = rec.npc_name,
                zone_short = rec.zone_short,
                zone_long = rec.zone_long,
                first_seen_at = rec.first_seen_at,
                last_seen_at = rec.last_seen_at,
                ordered_lines = {},
                item_details = {},
                responses = {},
            }
        end

        local dst = target[key]
        if rec.first_seen_at and (not dst.first_seen_at or rec.first_seen_at < dst.first_seen_at) then
            dst.first_seen_at = rec.first_seen_at
        end
        if rec.last_seen_at and (not dst.last_seen_at or rec.last_seen_at > dst.last_seen_at) then
            dst.last_seen_at = rec.last_seen_at
        end
        if (dst.zone_short or '') == '' then dst.zone_short = rec.zone_short or '' end
        if (dst.zone_long or '') == '' then dst.zone_long = rec.zone_long or '' end

        for _, line in ipairs(rec.ordered_lines or {}) do
            dst.ordered_lines[#dst.ordered_lines + 1] = {
                ts = line.ts,
                player_trigger = line.player_trigger,
                text = line.text,
            }
        end

        for ikey, detail in pairs(rec.item_details or {}) do
            if not dst.item_details[ikey] then
                dst.item_details[ikey] = { item_name = detail.item_name, lines = {} }
            end
            local d = dst.item_details[ikey]
            for _, ln in ipairs(detail.lines or {}) do
                local exists = false
                for _, eln in ipairs(d.lines) do
                    if normalize_key(eln) == normalize_key(ln) then
                        exists = true
                        break
                    end
                end
                if not exists then d.lines[#d.lines + 1] = ln end
            end
        end

        for rkey, r in pairs(rec.responses or {}) do
            if not dst.responses[rkey] then
                dst.responses[rkey] = {
                    text = r.text,
                    count = 0,
                    triggered_by = {},
                }
            end
            local dr = dst.responses[rkey]
            dr.count = dr.count + (tonumber(r.count) or 1)

            for tkey, cnt in pairs(r.triggered_by or {}) do
                dr.triggered_by[tkey] = (dr.triggered_by[tkey] or 0) + (tonumber(cnt) or 1)
            end
        end
    end
end

local function clear_store(store)
    for k in pairs(store) do store[k] = nil end
end

local function session_file_name(prefix)
    return ('%s_%s_%s_%s.json'):format(prefix, player_name, zone_short() ~= '' and zone_short() or 'unknownzone', os.date('%Y%m%d_%H%M%S'))
end

local function write_snapshot(path, records, reason)
    ensure_dir(BASE_DIR)

    local payload = {
        meta = {
            script = SCRIPT_NAME,
            reason = reason or 'manual',
            saved_at = now_iso(),
            player = player_name,
            server = server_name,
            zone_short = zone_short(),
            zone_long = zone_long(),
        },
        records = records,
    }

    local f, err = io.open(path, 'w')
    if not f then
        status_msg = 'Save failed: ' .. tostring(err)
        status_color = { 0.95, 0.30, 0.30, 1.0 }
        return false
    end
    f:write(encode_json(payload))
    f:close()
    return true
end

local function read_json_file(path)
    local f = io.open(path, 'r')
    if not f then return nil end
    local raw = f:read('*a')
    f:close()
    if not raw or raw == '' then return nil end
    return decode_json(raw)
end

local function write_json_file(path, payload)
    local f, err = io.open(path, 'w')
    if not f then return false, err end
    f:write(encode_json(payload))
    f:close()
    return true
end

local function save_dbstr_builder_settings()
    ensure_dir(BASE_DIR)
    local payload = {
        saved_at = now_iso(),
        dbstr_path = dbstr_builder.dbstr_path,
        spells_path = dbstr_builder.spells_path,
        dbstr_out = dbstr_builder.dbstr_out,
        spells_out = dbstr_builder.spells_out,
        scan_dialog_relevant_only = dbstr_builder.scan_dialog_relevant_only and true or false,
        markdown_path = dbstr_builder.markdown_path,
        create_missing_spell_entries = dbstr_builder.create_missing_spell_entries and true or false,
        imported_spell_candidates = dbstr_builder.imported_spell_candidates or {},
        table_search = dbstr_builder.table_search,
        search_use_regex = dbstr_builder.search_use_regex and true or false,
        saved_searches = dbstr_builder.saved_searches,
        proposal_confidence_threshold = tonumber(dbstr_builder.proposal_confidence_threshold) or 70,
        proposal_source_filter = dbstr_builder.proposal_source_filter or 'all',
        scan_file_scope = dbstr_builder.scan_file_scope or 'both',
        scan_issue_scope = dbstr_builder.scan_issue_scope or 'descriptions_only',
        scan_incremental = dbstr_builder.scan_incremental and true or false,
        dry_run_mode = dbstr_builder.dry_run_mode and true or false,
        live_feed_search = dbstr_builder.live_feed_search or '',
        pending_search = dbstr_builder.pending_search or '',
        accepted_search = dbstr_builder.accepted_search or '',
        active_npc_filter = dbstr_builder.active_npc_filter or 'All',
        line_tags = dbstr_builder.line_tags or {},
        last_scan_at = dbstr_builder.last_scan_at or '',
        last_write_at = dbstr_builder.last_write_at or '',
    }
    local ok, err = write_json_file(DBSTR_BUILDER_SETTINGS_FILE, payload)
    if not ok then
        push_feed('warn', 'Builder settings save failed: ' .. tostring(err), 0.95, 0.60, 0.20)
    end
end

local function load_dbstr_builder_settings()
    local payload = read_json_file(DBSTR_BUILDER_SETTINGS_FILE)
    if type(payload) ~= 'table' then return end
    if type(payload.dbstr_path) == 'string' and payload.dbstr_path ~= '' then
        dbstr_builder.dbstr_path = payload.dbstr_path
    end
    if type(payload.spells_path) == 'string' and payload.spells_path ~= '' then
        dbstr_builder.spells_path = payload.spells_path
    end
    if type(payload.dbstr_out) == 'string' and payload.dbstr_out ~= '' then
        dbstr_builder.dbstr_out = payload.dbstr_out
    end
    if type(payload.spells_out) == 'string' and payload.spells_out ~= '' then
        dbstr_builder.spells_out = payload.spells_out
    end
    if type(payload.scan_dialog_relevant_only) == 'boolean' then
        dbstr_builder.scan_dialog_relevant_only = payload.scan_dialog_relevant_only
    end
    if type(payload.markdown_path) == 'string' and payload.markdown_path ~= '' then
        dbstr_builder.markdown_path = payload.markdown_path
    end
    if type(payload.create_missing_spell_entries) == 'boolean' then
        dbstr_builder.create_missing_spell_entries = payload.create_missing_spell_entries
    end
    if type(payload.imported_spell_candidates) == 'table' then
        dbstr_builder.imported_spell_candidates = payload.imported_spell_candidates
    end
    if type(payload.table_search) == 'string' then
        dbstr_builder.table_search = payload.table_search
    end
    if type(payload.search_use_regex) == 'boolean' then
        dbstr_builder.search_use_regex = payload.search_use_regex
    end
    if type(payload.saved_searches) == 'table' then
        dbstr_builder.saved_searches = payload.saved_searches
    end
    if type(payload.proposal_confidence_threshold) == 'number' then
        dbstr_builder.proposal_confidence_threshold = payload.proposal_confidence_threshold
    end
    if type(payload.proposal_source_filter) == 'string' and payload.proposal_source_filter ~= '' then
        dbstr_builder.proposal_source_filter = payload.proposal_source_filter
    end
    if type(payload.scan_file_scope) == 'string' and payload.scan_file_scope ~= '' then
        dbstr_builder.scan_file_scope = payload.scan_file_scope
    end
    if type(payload.scan_issue_scope) == 'string' and payload.scan_issue_scope ~= '' then
        dbstr_builder.scan_issue_scope = payload.scan_issue_scope
    end
    if dbstr_builder.scan_issue_scope == 'all' then
        dbstr_builder.scan_issue_scope = 'descriptions_only'
    end
    if type(payload.scan_incremental) == 'boolean' then
        dbstr_builder.scan_incremental = payload.scan_incremental
    end
    if type(payload.dry_run_mode) == 'boolean' then
        dbstr_builder.dry_run_mode = payload.dry_run_mode
    end
    if type(payload.live_feed_search) == 'string' then dbstr_builder.live_feed_search = payload.live_feed_search end
    if type(payload.pending_search) == 'string' then dbstr_builder.pending_search = payload.pending_search end
    if type(payload.accepted_search) == 'string' then dbstr_builder.accepted_search = payload.accepted_search end
    if type(payload.active_npc_filter) == 'string' and payload.active_npc_filter ~= '' then dbstr_builder.active_npc_filter = payload.active_npc_filter end
    if type(payload.line_tags) == 'table' then dbstr_builder.line_tags = payload.line_tags end
    if type(payload.last_scan_at) == 'string' then dbstr_builder.last_scan_at = payload.last_scan_at end
    if type(payload.last_write_at) == 'string' then dbstr_builder.last_write_at = payload.last_write_at end
end

local function load_master_records()
    local decoded = read_json_file(MASTER_FILE)
    if decoded and type(decoded.records) == 'table' then
        return decoded.records
    end
    if decoded and type(decoded.npcs) == 'table' then
        local records = {}
        for i, npc in ipairs(decoded.npcs) do
            if type(npc) == 'table' then
                local key = normalize_key(npc.npc_name or tostring(i))
                if key ~= '' then
                    local rec = {
                        npc_name = sanitize_text(npc.npc_name or 'Unknown NPC'),
                        zone_short = sanitize_text(npc.zone_short or ''),
                        zone_long = sanitize_text(npc.zone_long or ''),
                        first_seen_at = npc.first_seen_at,
                        last_seen_at = npc.last_seen_at,
                        ordered_lines = {},
                        item_details = {},
                        responses = {},
                    }
                    for _, line in ipairs(npc.ordered_lines or {}) do
                        rec.ordered_lines[#rec.ordered_lines + 1] = {
                            ts = line.ts,
                            player_trigger = line.player_trigger,
                            text = sanitize_text(line.text or ''),
                            repeat_count = tonumber(line.repeat_count) or 1,
                        }
                    end
                    if type(npc.responses) == 'table' then
                        if npc.responses[1] ~= nil then
                            for _, r in ipairs(npc.responses) do
                                local rtext = sanitize_text(r.text or '')
                                local rkey = normalize_key(rtext)
                                if rkey ~= '' then
                                    local triggered = {}
                                    if type(r.triggered_by) == 'table' then
                                        if r.triggered_by[1] ~= nil then
                                            for _, t in ipairs(r.triggered_by) do
                                                local tkey = normalize_key(t.keyword or t.text or '')
                                                if tkey ~= '' then
                                                    triggered[tkey] = (triggered[tkey] or 0) + (tonumber(t.count) or 1)
                                                end
                                            end
                                        else
                                            for tkey, cnt in pairs(r.triggered_by) do
                                                local nk = normalize_key(tkey)
                                                if nk ~= '' then
                                                    triggered[nk] = (triggered[nk] or 0) + (tonumber(cnt) or 1)
                                                end
                                            end
                                        end
                                    end
                                    rec.responses[rkey] = {
                                        text = rtext,
                                        count = tonumber(r.count) or 1,
                                        triggered_by = triggered,
                                    }
                                end
                            end
                        else
                            rec.responses = npc.responses
                        end
                    end
                    records[key] = rec
                end
            end
        end
        return records
    end
    return {}
end

local function save_master_records(records)
    ensure_dir(BASE_DIR)
    local payload = {
        meta = {
            script = SCRIPT_NAME,
            kind = 'master',
            saved_at = now_iso(),
            player = player_name,
            server = server_name,
            zone_short = zone_short(),
            zone_long = zone_long(),
        },
        records = records,
    }
    return write_json_file(MASTER_FILE, payload)
end

load_dbstr_builder_settings()
if not file_exists(dbstr_builder.dbstr_path) and file_exists(USER_DBSTR_HINT) then
    dbstr_builder.dbstr_path = USER_DBSTR_HINT
end
if not file_exists(dbstr_builder.spells_path) and file_exists(USER_SPELLS_HINT) then
    dbstr_builder.spells_path = USER_SPELLS_HINT
end
save_dbstr_builder_settings()

local function accept_pending()
    local n = record_count(pending_records)
    if n == 0 then
        status_msg = 'No pending logs to accept'
        status_color = { 0.95, 0.60, 0.20, 1.0 }
        return
    end
    merge_store_into(accepted_records, pending_records)
    clear_store(pending_records)
    status_msg = ('Accepted %d pending NPC record(s)'):format(n)
    status_color = { 0.10, 0.95, 0.80, 1.0 }
    push_feed('accept', status_msg, 0.10, 0.95, 0.80)
end

local function reject_pending()
    local n = record_count(pending_records)
    clear_store(pending_records)
    pending_player = nil
    status_msg = ('Rejected %d pending NPC record(s)'):format(n)
    status_color = { 0.95, 0.60, 0.20, 1.0 }
    push_feed('reject', status_msg, 0.95, 0.60, 0.20)
end

local function save_accepted()
    if record_count(accepted_records) == 0 then
        status_msg = 'No accepted data to save'
        status_color = { 0.95, 0.60, 0.20, 1.0 }
        return
    end

    local path = BASE_DIR .. '/' .. session_file_name('accepted')
    if write_snapshot(path, accepted_records, 'accepted_save') then
        local master_records = load_master_records()
        merge_store_into(master_records, accepted_records)
        local ok, err = save_master_records(master_records)
        if ok then
            status_msg = 'Saved snapshot + merged master'
            status_color = { 0.10, 1.00, 0.50, 1.0 }
            push_feed('save', 'Snapshot: ' .. path, 0.10, 1.00, 0.50)
            push_feed('save', 'Master: ' .. MASTER_FILE, 0.10, 1.00, 0.50)
        else
            status_msg = 'Snapshot saved, master merge failed: ' .. tostring(err)
            status_color = { 0.95, 0.60, 0.20, 1.0 }
            push_feed('save', 'Snapshot: ' .. path, 0.10, 1.00, 0.50)
            push_feed('error', 'Master merge failed', 0.95, 0.35, 0.35)
        end
    end
end

local function save_pending_snapshot()
    local path = BASE_DIR .. '/' .. session_file_name('pending')
    if write_snapshot(path, pending_records, 'pending_snapshot') then
        status_msg = 'Saved pending snapshot -> ' .. path
        status_color = { 0.10, 1.00, 0.50, 1.0 }
        push_feed('save', 'Saved pending snapshot', 0.10, 1.00, 0.50)
    end
end

local function clean_export_text(s)
    local t = normalize_dialog_text(s or '')
    t = t:gsub('[%z\1-\31]', '')
    t = t:gsub('%s+', ' ')
    return trim(t)
end

local function html_escape(s)
    local t = tostring(s or '')
    t = t:gsub('&', '&amp;')
    t = t:gsub('<', '&lt;')
    t = t:gsub('>', '&gt;')
    t = t:gsub('"', '&quot;')
    return t
end

local function slugify(s)
    local t = clean_export_text(s):lower()
    t = t:gsub('[^%w%s%-_]', '')
    t = t:gsub('%s+', '-')
    t = t:gsub('%-+', '-')
    if t == '' then t = 'npc' end
    return t
end

local function section_title_from_line(line)
    return parse_section_header_title(clean_export_text(line))
end

local function build_sections(ordered_lines)
    local filtered_lines = {}
    local seen_blocks = {}
    local current_block = {}

    local function flush_block()
        if #current_block == 0 then return end
        local set = {}
        local size = 0
        for _, entry in ipairs(current_block) do
            local key = normalize_key(entry.text or '')
            if key ~= '' and not set[key] then
                set[key] = true
                size = size + 1
            end
        end
        if size == 0 then
            current_block = {}
            return
        end

        local duplicate = false
        for _, seen in ipairs(seen_blocks) do
            local overlap = 0
            for key in pairs(set) do
                if seen.set[key] then overlap = overlap + 1 end
            end
            local denom = math.max(size, seen.size)
            local similarity = denom > 0 and (overlap / denom) or 0
            if similarity >= BLOCK_DEDUPE_SIMILARITY then
                duplicate = true
                break
            end
        end

        if not duplicate then
            for _, entry in ipairs(current_block) do
                filtered_lines[#filtered_lines + 1] = entry
            end
            seen_blocks[#seen_blocks + 1] = { set = set, size = size }
        end

        current_block = {}
    end

    for _, entry in ipairs(ordered_lines or {}) do
        local text = clean_export_text(entry.text or '')
        if text ~= '' then
            local maybe_title = section_title_from_line(text)
            if maybe_title then
                flush_block()
                filtered_lines[#filtered_lines + 1] = { text = text }
            else
                if looks_like_section_hint(text) then
                    local wkey = normalize_key(text)
                    if not section_header_warned[wkey] then
                        section_header_warned[wkey] = true
                        push_feed('warn', 'Section-like line not parsed: ' .. text, 0.95, 0.60, 0.20)
                    end
                end
                current_block[#current_block + 1] = { text = text }
            end
        end
    end
    flush_block()

    local sections = { { title = 'Overview', lines = {} } }
    local current = sections[1]
    local title_counts = {}

    local function unique_title(base_title)
        local key = normalize_key(base_title)
        title_counts[key] = (title_counts[key] or 0) + 1
        if title_counts[key] == 1 then return base_title end
        return ('%s (%d)'):format(base_title, title_counts[key])
    end

    for _, entry in ipairs(filtered_lines) do
        local text = clean_export_text(entry.text or '')
        if text ~= '' then
            local maybe_title = section_title_from_line(text)
            if maybe_title then
                current = { title = unique_title(maybe_title), lines = {} }
                sections[#sections + 1] = current
            else
                local prev = current.lines[#current.lines]
                if normalize_key(prev or '') ~= normalize_key(text) then
                    current.lines[#current.lines + 1] = text
                end
            end
        end
    end

    local out = {}
    for _, sec in ipairs(sections) do
        if #sec.lines > 0 then out[#out + 1] = sec end
    end
    return out
end

local function extract_item_listing_name(line)
    local l = clean_export_text(line or '')
    local item = l:match("^%d+%.%s*(.-)%s*%[Info%s*&%s*Purchase%]$")
    if item and item ~= '' then return item end
    return nil
end

local function render_npc_html(npc_name, zone, sections, item_details)
    local lines = {}
    lines[#lines + 1] = '<!doctype html>'
    lines[#lines + 1] = '<html lang="en"><head><meta charset="utf-8">'
    lines[#lines + 1] = '<meta name="viewport" content="width=device-width, initial-scale=1">'
    lines[#lines + 1] = '<title>' .. html_escape(npc_name) .. ' Guide</title>'
    lines[#lines + 1] = '<style>'
    lines[#lines + 1] = '.npc-dialog-page{line-height:1.6;padding:16px;color:#1f2937;background:#f8fafc;border:1px solid #e2e8f0;border-radius:10px}'
    lines[#lines + 1] = '.npc-dialog-page h1{margin:0 0 4px 0;font-size:1.8rem}'
    lines[#lines + 1] = '.npc-dialog-page .npc-breadcrumb{margin:0 0 14px 0;font-size:.95rem}'
    lines[#lines + 1] = '.npc-dialog-page .npc-breadcrumb a{text-decoration:none;color:#0f766e}'
    lines[#lines + 1] = '.npc-dialog-page .meta{color:#475569;margin-bottom:18px}'
    lines[#lines + 1] = '.npc-dialog-page .sec{margin:20px 0}'
    lines[#lines + 1] = '.npc-dialog-page .line{margin:6px 0}'
    lines[#lines + 1] = '.npc-dialog-page .keyword{color:#0f766e;font-weight:600}'
    lines[#lines + 1] = '@media (prefers-color-scheme: dark){.npc-dialog-page{color:#e2e8f0;background:#0f172a;border-color:#334155}.npc-dialog-page .meta{color:#94a3b8}.npc-dialog-page .npc-breadcrumb a{color:#5eead4}.npc-dialog-page .keyword{color:#5eead4}}'
    lines[#lines + 1] = '</style>'
    lines[#lines + 1] = '</head><body>'
    lines[#lines + 1] = '<div class="npc-dialog-page">'
    lines[#lines + 1] = '<div class="npc-breadcrumb"><a href="../index.html">&larr; NPC Index</a></div>'
    lines[#lines + 1] = '<h1>' .. html_escape(npc_name) .. '</h1>'
    lines[#lines + 1] = '<div class="meta">Zone: ' .. html_escape(zone or '') .. '</div>'

    for _, sec in ipairs(sections) do
        lines[#lines + 1] = '<div class="sec"><h2>' .. html_escape(sec.title) .. '</h2>'
        for _, line in ipairs(sec.lines) do
            lines[#lines + 1] = '<div class="line">' .. keywordize_html(line) .. '</div>'
            local item_name = extract_item_listing_name(line)
            if item_name then
                local key = normalize_key(item_name)
                local details = item_details and item_details[key]
                if details and details.lines and #details.lines > 0 then
                    lines[#lines + 1] = '<div class="line"><strong>Details:</strong></div>'
                    for _, dline in ipairs(details.lines) do
                        lines[#lines + 1] = '<div class="line" style="margin-left:20px;">' .. keywordize_html(dline) .. '</div>'
                    end
                end
            end
        end
        lines[#lines + 1] = '</div>'
    end

    lines[#lines + 1] = '</div>'
    lines[#lines + 1] = '</body></html>'
    return table.concat(lines, '\n')
end

local function render_npc_md(rec, npc_name, zone, sections, item_details)
    local function yaml_quote(s)
        local t = tostring(s or ''):gsub('"', '\\"')
        return '"' .. t .. '"'
    end

    local lines = {}
    lines[#lines + 1] = '---'
    lines[#lines + 1] = 'npc: ' .. yaml_quote(npc_name)
    lines[#lines + 1] = 'zone: ' .. yaml_quote(zone or '')
    lines[#lines + 1] = 'zone_short: ' .. yaml_quote(rec.zone_short or '')
    lines[#lines + 1] = 'first_seen: ' .. yaml_quote(rec.first_seen_at or '')
    lines[#lines + 1] = 'response_count: ' .. tostring(response_total_for_record(rec))
    lines[#lines + 1] = '---'
    lines[#lines + 1] = ''
    lines[#lines + 1] = '# ' .. npc_name
    lines[#lines + 1] = ''
    lines[#lines + 1] = 'Zone: ' .. (zone or '')
    lines[#lines + 1] = ''
    for _, sec in ipairs(sections) do
        lines[#lines + 1] = '## ' .. sec.title
        lines[#lines + 1] = ''
        for _, line in ipairs(sec.lines) do
            lines[#lines + 1] = '- ' .. line
            local item_name = extract_item_listing_name(line)
            if item_name then
                local key = normalize_key(item_name)
                local details = item_details and item_details[key]
                if details and details.lines and #details.lines > 0 then
                    for _, dline in ipairs(details.lines) do
                        lines[#lines + 1] = '  - ' .. dline
                    end
                end
            end
        end
        lines[#lines + 1] = ''
    end
    return table.concat(lines, '\n')
end

local function build_website_export()
    local source_records = load_master_records()
    if record_count(accepted_records) > 0 then
        merge_store_into(source_records, accepted_records)
    end

    if record_count(source_records) == 0 then
        status_msg = 'Nothing to export: no master or accepted records'
        status_color = { 0.95, 0.60, 0.20, 1.0 }
        return false
    end

    ensure_dir(SITE_DIR)
    ensure_dir(SITE_DIR .. '/npcs')

    local index = {}
    index[#index + 1] = '<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>NPC Guide Export</title><style>body{font-family:Segoe UI,Arial,sans-serif;max-width:980px;margin:20px auto;padding:0 16px}li{margin:8px 0}.zone{margin:24px 0 6px 0}</style></head><body>'
    index[#index + 1] = '<h1>NPC Guide Export</h1>'

    local zones = {}
    local count = 0
    for _, rec in pairs(source_records) do
        local npc_name = clean_export_text(rec.npc_name or 'Unknown NPC')
        local zone = clean_export_text(rec.zone_long or rec.zone_short or '')
        local sections = build_sections(rec.ordered_lines or {})
        if #sections > 0 then
            local slug = slugify(npc_name)
            local html_path = SITE_DIR .. '/npcs/' .. slug .. '.html'
            local md_path = SITE_DIR .. '/npcs/' .. slug .. '.md'
            local f = io.open(html_path, 'w')
            if f then
                f:write(render_npc_html(npc_name, zone, sections, rec.item_details or {}))
                f:close()
            end
            local f2 = io.open(md_path, 'w')
            if f2 then f2:write(render_npc_md(rec, npc_name, zone, sections, rec.item_details or {})); f2:close() end

            local zone_name = zone ~= '' and zone or clean_export_text(rec.zone_short or 'Unknown Zone')
            local zkey = normalize_key(zone_name)
            if zkey == '' then zkey = 'unknown' end
            if not zones[zkey] then
                zones[zkey] = { zone = zone_name, entries = {} }
            end
            zones[zkey].entries[#zones[zkey].entries + 1] = {
                npc_name = npc_name,
                slug = slug,
                response_total = response_total_for_record(rec),
            }
            count = count + 1
        end
    end

    local zone_rows = {}
    for _, z in pairs(zones) do
        table.sort(z.entries, function(a, b) return a.npc_name < b.npc_name end)
        zone_rows[#zone_rows + 1] = z
    end
    table.sort(zone_rows, function(a, b) return (a.zone or '') < (b.zone or '') end)

    for _, zone_row in ipairs(zone_rows) do
        index[#index + 1] = '<h2 class="zone">' .. html_escape(zone_row.zone) .. '</h2><ul>'
        for _, e in ipairs(zone_row.entries) do
            index[#index + 1] = '<li><a href="npcs/' .. e.slug .. '.html">' .. html_escape(e.npc_name) .. '</a> - ' .. tostring(e.response_total) .. ' responses</li>'
        end
        index[#index + 1] = '</ul>'
    end

    index[#index + 1] = '</body></html>'
    local ifile = io.open(SITE_DIR .. '/index.html', 'w')
    if ifile then
        ifile:write(table.concat(index, '\n'))
        ifile:close()
    end

    status_msg = ('Website export ready: %d page(s) -> %s'):format(count, SITE_DIR)
    status_color = { 0.10, 1.00, 0.50, 1.0 }
    push_feed('export', status_msg, 0.10, 1.00, 0.50)
    return true
end

local function save_and_build()
    if record_count(accepted_records) == 0 then
        status_msg = 'Nothing to save/build: no accepted records yet'
        status_color = { 0.95, 0.60, 0.20, 1.0 }
        return
    end
    save_accepted()
    build_website_export()
end

local function open_export_folder()
    ensure_dir(SITE_DIR)
    os.execute(('start "" "%s"'):format(SITE_DIR:gsub('/', '\\')))
end

local push_theme
local pop_theme

local function dbstr_builder_log(msg)
    dbstr_builder.log[#dbstr_builder.log + 1] = ('[%s] %s'):format(os.date('%H:%M:%S'), tostring(msg))
    if #dbstr_builder.log > 200 then table.remove(dbstr_builder.log, 1) end
end

local function split_caret_fields(raw)
    local fields = {}
    for f in (tostring(raw or '') .. '^'):gmatch('([^%^]*)%^') do
        fields[#fields + 1] = f
    end
    return fields
end

local function parse_dbstr_line(raw)
    local fields = split_caret_fields(raw)
    if #fields < 4 then return nil end
    local a = tonumber(fields[1] or '')
    local b = tonumber(fields[2] or '')
    if not a or not b then return nil end
    local desc = tostring(fields[3] or '')

    -- Support both layouts observed in the wild:
    -- 1) type_id^str_id^desc^flag
    -- 2) str_id^type_id^desc^flag
    local type_id, str_id = a, b
    if b <= 10 and a > 10 then
        type_id, str_id = b, a
    end
    return {
        type_id = tonumber(type_id) or 0,
        str_id = tonumber(str_id) or 0,
        desc = desc,
        raw = raw,
    }
end

local function truncate_text(s, max_len)
    local t = tostring(s or '')
    local n = tonumber(max_len) or 80
    if #t > n then return t:sub(1, n - 3) .. '...' end
    return t
end

local function builder_row_matches_search(search_text, ...)
    local q = trim(search_text or '')
    if q == '' then return true end

    local fields = { ... }
    local map = {
        id = tostring(fields[2] or ''),
        file = tostring(fields[1] or ''),
        name = tostring(fields[3] or ''),
        issue = tostring(fields[4] or ''),
        source = tostring(fields[5] or ''),
        value = tostring(fields[6] or ''),
    }
    local haystack = table.concat({
        map.file, map.id, map.name, map.issue, map.source, map.value
    }, ' ')

    local function atom_matches(atom)
        atom = trim(atom or '')
        if atom == '' then return true end
        local k, v = atom:match('^(%w+)%s*:%s*(.+)$')
        if k and v then
            k = k:lower()
            local target = map[k] or ''
            if dbstr_builder.search_use_regex then
                local ok, res = pcall(function() return target:lower():match(v:lower()) ~= nil end)
                return ok and res or false
            end
            return target:lower():find(v:lower(), 1, true) ~= nil
        end
        if dbstr_builder.search_use_regex then
            local ok, res = pcall(function() return haystack:lower():match(atom:lower()) ~= nil end)
            return ok and res or false
        end
        return haystack:lower():find(atom:lower(), 1, true) ~= nil
    end

    local parts = {}
    for tok in q:gmatch('%S+') do
        parts[#parts + 1] = tok
    end
    if #parts == 0 then return true end

    local result = nil
    local pending_op = 'and'
    for i = 1, #parts do
        local tok = parts[i]
        local upper = tok:upper()
        if upper == 'AND' then
            pending_op = 'and'
        elseif upper == 'OR' then
            pending_op = 'or'
        else
            local matched = atom_matches(tok)
            if result == nil then
                result = matched
            elseif pending_op == 'and' then
                result = result and matched
            else
                result = result or matched
            end
        end
    end
    return result == nil and true or result
end

local function levenshtein(a, b)
    local s = tostring(a or '')
    local t = tostring(b or '')
    if s == t then return 0 end
    local m, n = #s, #t
    if m == 0 then return n end
    if n == 0 then return m end
    local d = {}
    for i = 0, m do
        d[i] = { [0] = i }
    end
    for j = 0, n do
        d[0][j] = j
    end
    for i = 1, m do
        local si = s:sub(i, i)
        for j = 1, n do
            local cost = (si == t:sub(j, j)) and 0 or 1
            local del = d[i - 1][j] + 1
            local ins = d[i][j - 1] + 1
            local sub = d[i - 1][j - 1] + cost
            local best = del < ins and del or ins
            if sub < best then best = sub end
            d[i][j] = best
        end
    end
    return d[m][n]
end

local function strip_rank_suffix(name)
    local n = clean_export_text(name or '')
    n = n:gsub('%s+[IVX]+$', '')
    n = n:gsub('%s+[0-9]+$', '')
    return trim(n)
end

local function rank_suffix(name)
    local n = clean_export_text(name or '')
    local r = n:match('%s+([IVX]+)$') or n:match('%s+([0-9]+)$')
    return r
end

local normalize_builder_name

local function infer_from_dialog_keywords(name, context)
    local nkey = normalize_builder_name(name)
    if nkey == '' then return nil end
    local best, score = nil, 0
    for _, line in ipairs(context.lines or {}) do
        local txt = line.text or ''
        local lower = (line.lower_text or ''):lower()
        if lower:find(nkey, 1, true) then
            local s = 10
            if lower:find('cost', 1, true) then s = s + 25 end
            if lower:find('tier', 1, true) then s = s + 20 end
            if lower:find('chance', 1, true) or lower:find('increase', 1, true) or lower:find('damage', 1, true) then s = s + 25 end
            if lower:find('you learn a new spell', 1, true) then s = s - 35 end
            if lower:find('single%-target heal') or lower:find('regeneration') or lower:find('haste') then s = s + 25 end
            if #txt > 30 then s = s + 10 end
            if s > score then
                score = s
                best = txt
            end
        end
    end
    return best, score
end

local function derive_spell_description_from_dialog(name, context)
    local target = normalize_builder_name(name or '')
    local target_base = normalize_builder_name(strip_rank_suffix(name or ''))
    if target == '' and target_base == '' then return nil, 0 end

    local best_text, best_score = nil, -1
    for _, line in ipairs(context.lines or {}) do
        local txt = clean_export_text(line.text or '')
        if txt ~= '' and not txt:find('%[%+%]') then
            local lhs, rhs = txt:match('^(.-):%s*(.+)$')
            if lhs and rhs then
                local rhs_clean = clean_export_text(rhs)
                local rhs_lower = rhs_clean:lower()
                if rhs_clean ~= '' and rhs_clean ~= '0' and #rhs_clean >= 8 and not rhs_lower:find('you learn a new spell', 1, true) then
                    local lhs_key = normalize_builder_name(lhs)
                    local lhs_base = normalize_builder_name(strip_rank_suffix(lhs))
                    local score = 0
                    if lhs_key == target and target ~= '' then score = score + 60 end
                    if lhs_base == target_base and target_base ~= '' then score = score + 45 end
                    if rhs_lower:find('chance', 1, true) or rhs_lower:find('damage', 1, true) or rhs_lower:find('heal', 1, true) then score = score + 20 end
                    if rhs_lower:find('increase', 1, true) or rhs_lower:find('regeneration', 1, true) or rhs_lower:find('haste', 1, true) then score = score + 15 end
                    if score > best_score then
                        best_score = score
                        best_text = rhs_clean
                    end
                end
            end
        end
    end
    if best_score <= 0 then return nil, 0 end
    return best_text, best_score
end

local function read_lines_file(path)
    local f = io.open(path, 'r')
    if not f then return nil end
    local lines = {}
    for line in f:lines() do
        lines[#lines + 1] = line
    end
    f:close()
    return lines
end

local function list_md_files(dir_path)
    local out = {}
    local dir_win = tostring(dir_path or ''):gsub('/', '\\')
    if dir_win == '' then return out end
    local p = io.popen(('dir /b "%s\\*.md" 2>nul'):format(dir_win))
    if not p then return out end
    for name in p:lines() do
        local n = trim(name)
        if n ~= '' then
            out[#out + 1] = path_join(dir_path, n)
        end
    end
    p:close()
    return out
end

local function load_builder_dialog_records()
    local records = load_master_records()
    if record_count(accepted_records) > 0 then
        merge_store_into(records, accepted_records)
    end
    if record_count(pending_records) > 0 then
        merge_store_into(records, pending_records)
    end
    return records
end

normalize_builder_name = function(s)
    local t = clean_export_text(s or ''):lower()
    t = t:gsub('%b[]', ' ')
    t = t:gsub('%b()', ' ')
    t = t:gsub('^talent%s+purchase:%s*', '')
    t = t:gsub('^rank%s+[%d%-]+%s*:%s*', '')
    t = t:gsub('^rank%s+[%d%-]+%s*%([^)]*%)%s*:%s*', '')
    t = t:gsub('^ranks%s+[%d%-]+%s*:%s*', '')
    t = t:gsub('^additional%s+detail:%s*', '')
    t = t:gsub('[^%w%s]', ' ')
    t = t:gsub('%s+', ' ')
    return trim(t)
end

local function import_markdown_hints()
    local path = trim(dbstr_builder.markdown_path or '')
    if path == '' then
        dbstr_builder.status = 'Markdown path is empty'
        dbstr_builder.status_color = { 0.95, 0.35, 0.35, 1.0 }
        return
    end

    local hints = {}
    local spell_candidates = {}
    local topic = nil
    local imported = 0
    local function store_hint(name_raw, desc_raw, source)
        local key = normalize_builder_name(name_raw)
        local desc = clean_export_text(desc_raw or '')
        if key == '' or desc == '' or #desc < 10 then return end
        if not hints[key] then
            hints[key] = { name = clean_export_text(name_raw), desc = desc, source = source }
            imported = imported + 1
            return
        end
        local cur = hints[key]
        if #desc > #cur.desc then
            cur.desc = desc
            cur.source = source
        end
    end
    local function store_spell_candidate(name_raw, source)
        local cleaned = clean_export_text(name_raw or '')
        cleaned = cleaned:gsub('^["' .. "'" .. ']', ''):gsub('["' .. "'" .. ']$', '')
        cleaned = trim(cleaned)
        local key = normalize_builder_name(cleaned)
        if key == '' then return end
        if not spell_candidates[key] then
            spell_candidates[key] = { name = cleaned, source = source }
        end
    end
    local function parse_lines(lines, source_path)
        for _, raw in ipairs(lines or {}) do
            local line = trim(raw or '')
            if line ~= '' then
                line = line:gsub('^[-*]%s*', '')
                line = line:gsub('^#+%s*', '')
                line = line:gsub('^>%s*', '')
                line = line:gsub('%*%*(.-)%*%*', '%1')
                line = line:gsub('`', '')

                local purch = line:match('^[Tt]alent%s+[Pp]urchase:%s*(.+)$')
                if purch then
                    topic = clean_export_text(purch)
                    store_spell_candidate(topic, 'markdown:' .. source_path)
                end

                local link_name = line:match("^['\"]?(.-)['\"]?%s*%[%+%]%s*[,;%.!\"']*$")
                if link_name and link_name ~= '' then
                    store_spell_candidate(link_name, 'markdown-link:' .. source_path)
                end
                for linked in line:gmatch("([%w%s%-%(%):'\"_/&]+)%s*%[%+%]") do
                    local cleaned_link = trim(linked or '')
                    if cleaned_link ~= '' then
                        store_spell_candidate(cleaned_link, 'markdown-link:' .. source_path)
                    end
                end

                local rank_desc = line:match('^[Rr]ank%s+[%d%-]+%s*%([^)]*%)%s*:%s*(.+)$')
                    or line:match('^[Rr]ank%s+[%d%-]+%s*:%s*(.+)$')
                    or line:match('^[Rr]anks%s+[%d%-]+%s*:%s*(.+)$')
                local add_desc = line:match('^[Aa]dditional%s+[Dd]etail:%s*(.+)$')
                if topic and (rank_desc or add_desc) then
                    store_hint(topic, rank_desc or add_desc, 'markdown:' .. source_path)
                end

                local lhs, rhs = line:match('^(.-):%s*(.+)$')
                if lhs and rhs and #lhs <= 96 then
                    local ll = normalize_builder_name(lhs)
                    if ll ~= '' and ll ~= 'rank' and ll ~= 'ranks' and ll ~= 'additional detail' and ll ~= 'talent purchase' then
                        store_hint(lhs, rhs, 'markdown:' .. source_path)
                    end
                end
            end
        end
    end

    local lines = read_lines_file(path)
    local parsed_files = 0
    if lines then
        parse_lines(lines, path)
        parsed_files = parsed_files + 1
    else
        local files = list_md_files(path)
        for _, fpath in ipairs(files) do
            local flines = read_lines_file(fpath)
            if flines then
                parse_lines(flines, fpath)
                parsed_files = parsed_files + 1
            end
        end
    end
    if parsed_files == 0 then
        dbstr_builder.status = 'Cannot open markdown file/folder: ' .. path
        dbstr_builder.status_color = { 0.95, 0.35, 0.35, 1.0 }
        return
    end
    local function table_count(tbl)
        local n = 0
        for _ in pairs(tbl or {}) do n = n + 1 end
        return n
    end
    if imported == 0 and table_count(spell_candidates) == 0 then
        local fallback_files = list_md_files(NPC_EXPORT_NPCS_DIR)
        local fallback_loaded = 0
        for _, fpath in ipairs(fallback_files) do
            local flines = read_lines_file(fpath)
            if flines then
                parse_lines(flines, fpath)
                fallback_loaded = fallback_loaded + 1
            end
        end
        if fallback_loaded > 0 then
            dbstr_builder_log(('No hint rows found in selected markdown; fallback-loaded %d NPC markdown file(s).'):format(fallback_loaded))
            parsed_files = parsed_files + fallback_loaded
        end
    end

    dbstr_builder.imported_hints = hints
    dbstr_builder.imported_spell_candidates = spell_candidates
    dbstr_builder.imported_hint_count = imported
    local candidate_count = table_count(spell_candidates)
    dbstr_builder.status = ('Imported markdown hints: %d | spell candidates: %d | files: %d'):format(imported, candidate_count, parsed_files)
    dbstr_builder.status_color = imported > 0 and { 0.10, 0.95, 0.80, 1.0 } or { 0.95, 0.60, 0.20, 1.0 }
    dbstr_builder_log(dbstr_builder.status)
end

local function proposal_source_bucket(p)
    local s = normalize_key((p and p.source) or '')
    if s == '' or s == 'no match' then return 'no match' end
    if s:find('family', 1, true) then return 'Family Fill' end
    if s:find('semantic', 1, true) then return 'Dialog Inference' end
    if s:find('dialog', 1, true) or s:find('npc:', 1, true) then return 'Dialog Inference' end
    if s:find('markdown', 1, true) then return 'NPC: Exported Markdown' end
    return p.source
end

local function proposal_matches_source_filter(p)
    local f = dbstr_builder.proposal_source_filter or 'all'
    if f == 'all' then return true end
    return proposal_source_bucket(p) == f
end

local function find_spell_problem_id_by_text(text)
    local lower = normalize_builder_name(text or '')
    if lower == '' then return nil end
    for _, p in ipairs(dbstr_builder.problems or {}) do
        if normalize_key(p.file) == 'spells' then
            local nm = normalize_builder_name(p.name or '')
            if nm ~= '' and lower:find(nm, 1, true) then
                return tonumber(p.str_id) or nil
            end
        end
    end
    return nil
end

local function feed_npc_name(msg)
    local npc = tostring(msg or ''):match('^([^:]+):')
    if npc and npc ~= '' then return trim(npc) end
    return nil
end

local function safe_builder_action(label, fn)
    local ok, err = pcall(fn)
    if not ok then
        dbstr_builder.status = ('%s failed: %s'):format(label, tostring(err))
        dbstr_builder.status_color = { 0.95, 0.35, 0.35, 1.0 }
        dbstr_builder_log(dbstr_builder.status)
        push_feed('error', dbstr_builder.status, 0.95, 0.35, 0.35)
    end
    return ok
end

local function bulk_set_accept_by_confidence(min_conf)
    local changed = 0
    for _, p in ipairs(dbstr_builder.proposals or {}) do
        if proposal_matches_source_filter(p) and (tonumber(p.confidence) or 0) >= (tonumber(min_conf) or 0) then
            if not p.accepted then
                p.accepted = true
                changed = changed + 1
            end
        end
    end
    if changed > 0 then
        dbstr_builder.last_action_undo = {
            kind = 'bulk_accept',
            expires_at = os.time() + 5,
            changed = changed,
            before = {},
        }
        dbstr_builder.status = ('Accepted %d proposals by confidence >= %d%%'):format(changed, tonumber(min_conf) or 0)
        dbstr_builder.status_color = { 0.10, 0.95, 0.80, 1.0 }
    end
end

local function bulk_set_accept_filtered(value)
    local changed = 0
    for _, p in ipairs(dbstr_builder.proposals or {}) do
        if proposal_matches_source_filter(p) then
            if (p.accepted and not value) or ((not p.accepted) and value) then
                p.accepted = value
                changed = changed + 1
            end
        end
    end
    dbstr_builder.status = value and ('Accepted %d visible proposals'):format(changed) or ('Rejected %d visible proposals'):format(changed)
    dbstr_builder.status_color = { 0.90, 0.88, 0.30, 1.0 }
end

local function build_dialog_context()
    local source_records = load_builder_dialog_records()
    local lines = {}
    local joined = {}
    local named_desc = {}

    local function push_named_desc(name_raw, desc_raw, source)
        local nkey = normalize_builder_name(name_raw)
        local desc = clean_export_text(desc_raw or '')
        if nkey == '' or desc == '' then return end
        if #desc < 12 then return end
        if not named_desc[nkey] then
            named_desc[nkey] = { name = clean_export_text(name_raw), desc = desc, source = source }
            return
        end
        local cur = named_desc[nkey]
        if #desc > #cur.desc + 8 then
            cur.desc = desc
            cur.source = source
        elseif not cur.desc:find(desc, 1, true) and #cur.desc < 240 then
            cur.desc = cur.desc .. ' ' .. desc
        end
    end

    for _, rec in pairs(source_records) do
        local npc_name = sanitize_text(rec.npc_name or 'Unknown NPC')
        local topic_name = nil
        for _, line in ipairs(rec.ordered_lines or {}) do
            local text = clean_export_text(line.text or '')
            if text ~= '' then
                local lower = text:lower()
                lines[#lines + 1] = {
                    npc_name = npc_name,
                    text = text,
                    lower_text = lower,
                    has_trigger = trim(line.player_trigger or '') ~= '',
                }
                joined[#joined + 1] = lower

                local purch = text:match('^[Tt]alent%s+[Pp]urchase:%s*(.+)$')
                if purch then
                    topic_name = clean_export_text(purch)
                end

                local rank_desc = text:match('^[Rr]ank%s+[%d%-]+%s*%([^)]*%)%s*:%s*(.+)$')
                    or text:match('^[Rr]ank%s+[%d%-]+%s*:%s*(.+)$')
                    or text:match('^[Rr]anks%s+[%d%-]+%s*:%s*(.+)$')
                local add_desc = text:match('^[Aa]dditional%s+[Dd]etail:%s*(.+)$')
                if topic_name and (rank_desc or add_desc) then
                    push_named_desc(topic_name, rank_desc or add_desc, 'NPC: ' .. npc_name)
                end

                local lhs2, rhs2 = text:match('^.-:%s*([^:]+):%s*(.+)$')
                if lhs2 and rhs2 then
                    push_named_desc(lhs2, rhs2, 'NPC: ' .. npc_name)
                else
                    local lhs, rhs = text:match('^(.-):%s*(.+)$')
                    if lhs and rhs then
                        local lhl = normalize_builder_name(lhs)
                        if lhl ~= '' and lhl ~= 'rank' and lhl ~= 'ranks' and lhl ~= 'additional detail' and lhl ~= 'talent purchase' then
                            push_named_desc(lhs, rhs, 'NPC: ' .. npc_name)
                        end
                    end
                end
            end
        end
    end

    if USE_EXPORTED_MARKDOWN_CONTEXT then
        local exported_md = list_md_files(NPC_EXPORT_NPCS_DIR)
        for _, md_path in ipairs(exported_md) do
            local mlines = read_lines_file(md_path)
            if mlines then
                local topic_name = nil
                for _, raw in ipairs(mlines) do
                    local text = clean_export_text(raw or '')
                    if text ~= '' then
                        local lower = text:lower()
                        lines[#lines + 1] = {
                            npc_name = 'Exported Markdown',
                            text = text,
                            lower_text = lower,
                            has_trigger = false,
                        }
                        joined[#joined + 1] = lower

                        local purch = text:match('^[Tt]alent%s+[Pp]urchase:%s*(.+)$')
                        if purch then
                            topic_name = clean_export_text(purch)
                        end

                        local rank_desc = text:match('^[Rr]ank%s+[%d%-]+%s*%([^)]*%)%s*:%s*(.+)$')
                            or text:match('^[Rr]ank%s+[%d%-]+%s*:%s*(.+)$')
                            or text:match('^[Rr]anks%s+[%d%-]+%s*:%s*(.+)$')
                        local add_desc = text:match('^[Aa]dditional%s+[Dd]etail:%s*(.+)$')
                        if topic_name and (rank_desc or add_desc) then
                            push_named_desc(topic_name, rank_desc or add_desc, 'markdown:' .. md_path)
                        end

                        local lhs2, rhs2 = text:match('^.-:%s*([^:]+):%s*(.+)$')
                        if lhs2 and rhs2 then
                            push_named_desc(lhs2, rhs2, 'markdown:' .. md_path)
                        else
                            local lhs, rhs = text:match('^(.-):%s*(.+)$')
                            if lhs and rhs then
                                local lhl = normalize_builder_name(lhs)
                                if lhl ~= '' and lhl ~= 'rank' and lhl ~= 'ranks' and lhl ~= 'additional detail' and lhl ~= 'talent purchase' then
                                    push_named_desc(lhs, rhs, 'markdown:' .. md_path)
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    for k, v in pairs(dbstr_builder.imported_hints or {}) do
        if not named_desc[k] then
            named_desc[k] = { name = v.name, desc = v.desc, source = v.source or 'markdown' }
        else
            local cur = named_desc[k]
            if #tostring(v.desc or '') > #tostring(cur.desc or '') then
                cur.desc = v.desc
                cur.source = v.source or 'markdown'
            end
        end
    end

    return {
        lines = lines,
        joined_text = table.concat(joined, ' '),
        named_desc = named_desc,
    }
end

local function is_name_relevant_to_dialog(name, context)
    local cleaned = clean_export_text(name or '')
    if cleaned == '' then return false end
    local nkey = normalize_builder_name(cleaned)
    if nkey ~= '' and context.named_desc[nkey] then return true end
    if #nkey >= 4 and context.joined_text:find(nkey, 1, true) then return true end
    return false
end

local function build_spell_candidates_from_context(context)
    local out = {}
    local function add_candidate(name, source)
        local clean = clean_export_text(name or '')
        clean = clean:gsub('^%-?%d+%.%s*', '')
        clean = clean:gsub('%s*%(%s*[Cc]ost[^)]*%)%s*$', '')
        clean = clean:gsub("^['\"`]+", ''):gsub("['\"`]+$", '')
        clean = clean:gsub('^%p+', ''):gsub('%p+$', '')
        clean = trim(clean)
        local key = normalize_builder_name(clean)
        if clean == '' or key == '' then return end
        if #key < 3 then return end
        if key == 'view my talents' or key == 'spend talent points' or key == 'reset my talents' then return end
        if key == 'convert tier credits to talent points' then return end
        if key:find(' task ', 1, true) or key:find('task ', 1, true) then return end
        if key:find('credits', 1, true) then return end
        if not out[key] then out[key] = { name = clean, source = source or 'dialog' } end
    end

    local function json_unescape_minimal(s)
        local t = tostring(s or '')
        t = t:gsub('\\"', '"')
        t = t:gsub('\\\\', '\\')
        t = t:gsub('\\/', '/')
        t = t:gsub('\\n', '\n')
        t = t:gsub('\\r', '\r')
        t = t:gsub('\\t', '\t')
        return t
    end

    local function ingest_text_line(text, source)
        local line = clean_export_text(text or '')
        if line == '' then return end
        line = line:gsub('^[-*]%s*', '')
        local linked = line:match("^['\"]?(.-)['\"]?%s*%[%+%]%s*[,;%.!\"']*$")
        if linked then
            add_candidate(linked, source)
        end
        for linked_any in line:gmatch("([%w%s%-%(%):'\"_/&]+)%s*%[%+%]") do
            add_candidate(linked_any, source)
        end
        local purch = line:match('^[Tt]alent%s+[Pp]urchase:%s*(.+)$')
        if purch then
            add_candidate(purch, source)
        end
    end

    for _, entry in ipairs(context.lines or {}) do
        local text = clean_export_text(entry.text or '')
        ingest_text_line(text, 'dialog-link')
    end
    for _, c in pairs(dbstr_builder.imported_spell_candidates or {}) do
        add_candidate(c.name or '', c.source or 'markdown-link')
    end

    -- Hard fallback source 1: read text lines from master_dialog.json directly.
    local mf = io.open(MASTER_FILE, 'r')
    if mf then
        local raw = mf:read('*a') or ''
        mf:close()
        for encoded in raw:gmatch('"text"%s*:%s*"(.-)"') do
            ingest_text_line(json_unescape_minimal(encoded), 'master-json')
        end
    end

    -- Hard fallback source 2: exported NPC markdown files.
    local md_files = list_md_files(NPC_EXPORT_NPCS_DIR)
    for _, md_path in ipairs(md_files) do
        local lines = read_lines_file(md_path)
        for _, raw in ipairs(lines or {}) do
            ingest_text_line(raw, 'markdown-link:' .. md_path)
        end
    end
    return out
end

local function load_scan_cache()
    local payload = read_json_file(DBSTR_SCAN_CACHE_FILE)
    if type(payload) == 'table' then
        dbstr_builder.scan_cache = payload
    else
        dbstr_builder.scan_cache = {}
    end
end

local function get_spell_raw_by_id(spell_id)
    local sid = tonumber(spell_id) or 0
    if sid <= 0 then return '' end
    local lines = read_lines_file(dbstr_builder.spells_path) or {}
    for _, raw in ipairs(lines) do
        local fields = split_caret_fields(raw)
        if tonumber(fields[1] or 0) == sid then
            return raw
        end
    end
    return ''
end

local function build_preview_patch_text()
    local out = {}
    out[#out + 1] = 'Preview Patch'
    out[#out + 1] = '============='
    for _, p in ipairs(dbstr_builder.proposals or {}) do
        if p.accepted and trim(p.proposed or '') ~= '' then
            out[#out + 1] = ('[%s:%d] %s'):format(p.file or '?', tonumber(p.str_id) or 0, p.issue or '')
            out[#out + 1] = ('- before: %s'):format(truncate_text(p.current or '', 120))
            out[#out + 1] = ('+ after : %s'):format(truncate_text(p.proposed or '', 120))
            out[#out + 1] = ''
        end
    end
    return table.concat(out, '\n')
end

local function save_scan_cache()
    ensure_dir(BASE_DIR)
    write_json_file(DBSTR_SCAN_CACHE_FILE, dbstr_builder.scan_cache or {})
end

local function problem_key(file, type_id, str_id, issue)
    return table.concat({
        tostring(file or ''),
        tostring(type_id or 0),
        tostring(str_id or 0),
        tostring(issue or '')
    }, '|')
end

local function issue_matches_scope(issue)
    local scope = dbstr_builder.scan_issue_scope or 'descriptions_only'
    local issue_key = normalize_key(issue)
    if scope == 'descriptions_only' then
        local allowed = {
            [normalize_key('Empty description')] = true,
            [normalize_key('Placeholder text')] = true,
            [normalize_key('Stub (< 10 chars)')] = true,
            [normalize_key('Missing dbstr description entry')] = true,
            [normalize_key('Missing description (dbstr type5)')] = true,
            [normalize_key('Missing spell entry (not in spells_us)')] = true,
            [normalize_key('Missing spell name')] = true,
            [normalize_key('Unknown spell name')] = true,
        }
        return allowed[issue_key] == true
    end
    if scope == 'all' then return true end
    return issue_key == normalize_key(scope)
end

local function file_matches_scope(file_name)
    local scope = dbstr_builder.scan_file_scope or 'both'
    if scope == 'both' then return true end
    return normalize_key(file_name) == normalize_key(scope)
end

local function allocate_safe_spell_ids(occupied_set, requested_count)
    local allocated = {}
    local need = tonumber(requested_count) or 0
    if need <= 0 then return allocated end
    local taken = occupied_set or {}
    for sid = SAFE_SPELL_ID_MIN, SAFE_SPELL_ID_MAX do
        if not taken[sid] then
            allocated[#allocated + 1] = sid
            taken[sid] = true
            if #allocated >= need then break end
        end
    end
    return allocated
end

local function scan_dbstr_problems(relevant_only_override)
    dbstr_builder.running = true
    dbstr_builder.problems = {}
    dbstr_builder.proposals = {}
    dbstr_builder.log = {}

    load_scan_cache()

    local dbstr_lines = read_lines_file(dbstr_builder.dbstr_path)
    if not dbstr_lines then
        dbstr_builder.status = 'Cannot open: ' .. tostring(dbstr_builder.dbstr_path)
        dbstr_builder.status_color = { 0.95, 0.35, 0.35, 1.0 }
        dbstr_builder.running = false
        return
    end

    local spell_lines = read_lines_file(dbstr_builder.spells_path) or {}
    local spell_name_by_id = {}
    local spell_name_key_to_id = {}
    local spell_base_key_to_ids = {}
    local occupied_spell_ids = {}
    local dialog_context = build_dialog_context()
    dbstr_builder_log(('Dialog context: lines=%d named_desc=%d'):format(
        #(dialog_context.lines or {}),
        (function(tbl) local n = 0; for _ in pairs(tbl or {}) do n = n + 1 end; return n end)(dialog_context.named_desc)
    ))
    local skipped_irrelevant = 0
    local skipped_incremental = 0
    local dbstr_spell_desc_ids = {}
    local seen_problem = {}
    local use_relevant = dbstr_builder.scan_dialog_relevant_only and true or false
    if type(relevant_only_override) == 'boolean' then
        use_relevant = relevant_only_override
    end

    for _, raw in ipairs(spell_lines) do
        local fields = split_caret_fields(raw)
        local sid = tonumber(fields[1] or '')
        if sid then
            occupied_spell_ids[sid] = true
            local sname = trim(fields[2] or '')
            spell_name_by_id[sid] = sname
            local nkey = normalize_builder_name(sname)
            if nkey ~= '' and not spell_name_key_to_id[nkey] then
                spell_name_key_to_id[nkey] = sid
            end
            local bkey = normalize_builder_name(strip_rank_suffix(sname))
            if bkey ~= '' then
                spell_base_key_to_ids[bkey] = spell_base_key_to_ids[bkey] or {}
                spell_base_key_to_ids[bkey][#spell_base_key_to_ids[bkey] + 1] = sid
            end
        end
    end

    local function add_problem(rec)
        local key = table.concat({
            tostring(rec.file or ''),
            tostring(rec.type_id or 0),
            tostring(rec.str_id or 0),
            tostring(rec.issue or ''),
            normalize_key(rec.name or '')
        }, '|')
        if seen_problem[key] then return end
        seen_problem[key] = true
        dbstr_builder.problems[#dbstr_builder.problems + 1] = rec
    end

    for _, raw in ipairs(dbstr_lines) do
        local parsed = parse_dbstr_line(raw)
        if parsed then
            local issue = nil
            local d = trim(parsed.desc or '')
            local tnum = tonumber(parsed.type_id) or 0
            local snum = tonumber(parsed.str_id) or 0
            local name = spell_name_by_id[snum] or ''
            if tnum == 5 or tnum == 6 then
                dbstr_spell_desc_ids[snum] = true
                occupied_spell_ids[snum] = true
            end
            local dl = d:lower()
            if d == '' then
                issue = 'Empty description'
            elseif dl == 'oops' or dl == 'unknown race' or dl == 'unknown class' or dl:find('^unknown') then
                issue = 'Placeholder text'
            elseif (tnum == 1 or tnum == 2 or tnum == 5) and #d < 10 then
                issue = 'Stub (< 10 chars)'
            end
            if issue and file_matches_scope('dbstr') and issue_matches_scope(issue) then
                if use_relevant and not is_name_relevant_to_dialog(name, dialog_context) then
                    skipped_irrelevant = skipped_irrelevant + 1
                else
                    local rec = {
                        file = 'dbstr',
                        type_id = tnum,
                        str_id = snum,
                        name = name,
                        issue = issue,
                        current = d,
                        raw_line = raw,
                    }
                    local pkey = problem_key(rec.file, rec.type_id, rec.str_id, rec.issue)
                    local sig = normalize_key(rec.current) .. '|' .. normalize_key(rec.name)
                    if dbstr_builder.scan_incremental and dbstr_builder.scan_cache[pkey] == sig then
                        skipped_incremental = skipped_incremental + 1
                    else
                        add_problem(rec)
                        dbstr_builder.scan_cache[pkey] = sig
                    end
                end
            end
        end
    end

    for _, raw in ipairs(spell_lines) do
        local fields = split_caret_fields(raw)
        if #fields >= 10 then
            local spell_id = tonumber(fields[1]) or 0
            local spell_name = trim(fields[2] or '')
            local cast_you = trim(fields[7] or '')
            local cast_other = trim(fields[8] or '')
            local wear_off = trim(fields[9] or '')
            local duration = tonumber(fields[10]) or 0
            local lower_name = spell_name:lower()
            local relevant = (not use_relevant) or is_name_relevant_to_dialog(spell_name, dialog_context)

            local function add_spell_issue(issue, current)
                if not relevant then
                    skipped_irrelevant = skipped_irrelevant + 1
                    return
                end
                if not file_matches_scope('spells') or not issue_matches_scope(issue) then
                    return
                end
                local rec = {
                    file = 'spells',
                    type_id = 0,
                    str_id = spell_id,
                    name = spell_name,
                    issue = issue,
                    current = current,
                    raw_line = raw,
                }
                local pkey = problem_key(rec.file, rec.type_id, rec.str_id, rec.issue)
                local sig = normalize_key(rec.current) .. '|' .. normalize_key(rec.name)
                if dbstr_builder.scan_incremental and dbstr_builder.scan_cache[pkey] == sig then
                    skipped_incremental = skipped_incremental + 1
                else
                    add_problem(rec)
                    dbstr_builder.scan_cache[pkey] = sig
                end
            end

            if spell_name == '' or lower_name:find('unknown', 1, true) then
                add_spell_issue(spell_name == '' and 'Missing spell name' or 'Unknown spell name', spell_name)
            end
            if CHECK_SPELL_CAST_MESSAGES and duration > 0 and cast_you == '' then
                add_spell_issue('Missing cast_on_you message', cast_you)
            end
            if CHECK_SPELL_CAST_MESSAGES and duration > 0 and cast_other == '' then
                add_spell_issue('Missing cast_on_other message', cast_other)
            end
            if REQUIRE_WEAR_OFF_MESSAGE and duration > 0 and wear_off == '' then
                add_spell_issue('Missing wear_off message', wear_off)
            end
        end
    end

    for sid, sname in pairs(spell_name_by_id) do
        if not dbstr_spell_desc_ids[sid] then
            local relevant = (not use_relevant) or is_name_relevant_to_dialog(sname, dialog_context)
            if relevant and file_matches_scope('dbstr') and issue_matches_scope('Missing dbstr description entry') then
                local rec = {
                    file = 'dbstr',
                    type_id = 5,
                    str_id = sid,
                    name = sname,
                    issue = 'Missing dbstr description entry',
                    current = '',
                    raw_line = '',
                }
                local pkey = problem_key(rec.file, rec.type_id, rec.str_id, rec.issue)
                local sig = normalize_key(rec.current) .. '|' .. normalize_key(rec.name)
                if dbstr_builder.scan_incremental and dbstr_builder.scan_cache[pkey] == sig then
                    skipped_incremental = skipped_incremental + 1
                else
                    add_problem(rec)
                    dbstr_builder.scan_cache[pkey] = sig
                end
            else
                skipped_irrelevant = skipped_irrelevant + 1
            end
        end
    end

    if dbstr_builder.create_missing_spell_entries then
        local candidates = build_spell_candidates_from_context(dialog_context)
        local candidate_keys = {}
        local remapped_to_existing = 0
        local skipped_existing_desc = 0
        local function pick_sid(ids)
            if type(ids) ~= 'table' or #ids == 0 then return nil end
            table.sort(ids, function(a, b) return (tonumber(a) or 0) < (tonumber(b) or 0) end)
            return tonumber(ids[1]) or nil
        end
        local function find_existing_sid(ckey, cname)
            local exact_sid = spell_name_key_to_id[ckey]
            if exact_sid then return exact_sid end

            local direct_base_sid = pick_sid(spell_base_key_to_ids[ckey])
            if direct_base_sid then return direct_base_sid end

            local cbase = normalize_builder_name(strip_rank_suffix(cname or ''))
            if cbase ~= '' then
                local by_cbase = pick_sid(spell_base_key_to_ids[cbase])
                if by_cbase then return by_cbase end
            end

            local best_sid, best_dist = nil, 999
            for bkey, ids in pairs(spell_base_key_to_ids) do
                local dist = levenshtein(ckey, bkey)
                if dist <= 2 and dist < best_dist then
                    best_dist = dist
                    best_sid = pick_sid(ids)
                end
            end
            return best_sid
        end
        for ckey, c in pairs(candidates) do
            local remap_sid = find_existing_sid(ckey, c.name)
            if remap_sid then
                -- Candidate already maps to an existing spell/rank; do not create synthetic.
                if not dbstr_spell_desc_ids[remap_sid] then
                    local rec = {
                        file = 'spells',
                        type_id = 5,
                        str_id = remap_sid,
                        name = spell_name_by_id[remap_sid] or c.name or '',
                        issue = 'Missing description (dbstr type5)',
                        current = '',
                        raw_line = '',
                        source = c.source,
                    }
                    local pkey = problem_key(rec.file, rec.type_id, rec.str_id, rec.issue)
                    local sig = normalize_key(rec.current) .. '|' .. normalize_key(rec.name)
                    if dbstr_builder.scan_incremental and dbstr_builder.scan_cache[pkey] == sig then
                        skipped_incremental = skipped_incremental + 1
                    else
                        add_problem(rec)
                        dbstr_builder.scan_cache[pkey] = sig
                    end
                    remapped_to_existing = remapped_to_existing + 1
                else
                    skipped_existing_desc = skipped_existing_desc + 1
                end
            else
                candidate_keys[#candidate_keys + 1] = { key = ckey, item = c }
            end
        end
        dbstr_builder_log(('Spell candidates from dialog/markdown: %d | missing in spells_us: %d'):format(
            (function(tbl) local n = 0; for _ in pairs(tbl or {}) do n = n + 1 end; return n end)(candidates),
            #candidate_keys
        ))
        local total_candidates = (function(tbl) local n = 0; for _ in pairs(tbl or {}) do n = n + 1 end; return n end)(candidates)
        if total_candidates == 0 then
            dbstr_builder_log('WARNING: candidate extraction returned 0. Checked sources: context lines, imported hints, master_dialog.json text, site_export/npcs/*.md')
            dbstr_builder_log('master file: ' .. tostring(MASTER_FILE))
            dbstr_builder_log('npc md dir: ' .. tostring(NPC_EXPORT_NPCS_DIR))
        end
        if remapped_to_existing > 0 then
            dbstr_builder_log(('Remapped %d candidate spell(s) to existing ranked spells for dbstr type 5 fixes'):format(remapped_to_existing))
        end
        if skipped_existing_desc > 0 then
            dbstr_builder_log(('Skipped %d candidate spell(s) already mapped with existing dbstr type 5 entries'):format(skipped_existing_desc))
        end
        table.sort(candidate_keys, function(a, b)
            return (a.item.name or '') < (b.item.name or '')
        end)
        local safe_ids = allocate_safe_spell_ids(occupied_spell_ids, #candidate_keys)
        local id_idx = 1
        local skipped_no_safe_id = 0
        for _, wrapped in ipairs(candidate_keys) do
            local ckey, c = wrapped.key, wrapped.item
            local sid = safe_ids[id_idx]
            if sid and file_matches_scope('spells') and issue_matches_scope('Missing spell entry (not in spells_us)') then
                local rec = {
                    file = 'spells',
                    type_id = 0,
                    str_id = sid,
                    name = c.name,
                    issue = 'Missing spell entry (not in spells_us)',
                    current = '',
                    raw_line = '',
                    synthetic_new_spell = true,
                    source = c.source,
                }
                local pkey = problem_key(rec.file, rec.type_id, rec.str_id, rec.issue)
                local sig = normalize_key(rec.current) .. '|' .. normalize_key(rec.name)
                if dbstr_builder.scan_incremental and dbstr_builder.scan_cache[pkey] == sig then
                    skipped_incremental = skipped_incremental + 1
                else
                    add_problem(rec)
                    dbstr_builder.scan_cache[pkey] = sig
                end
                id_idx = id_idx + 1
            elseif not sid then
                skipped_no_safe_id = skipped_no_safe_id + 1
            end
        end
        if skipped_no_safe_id > 0 then
            dbstr_builder_log(('Safe ID pool exhausted (%d-%d). Skipped %d new spell(s).'):format(
                SAFE_SPELL_ID_MIN, SAFE_SPELL_ID_MAX, skipped_no_safe_id
            ))
        end
    end

    save_scan_cache()
    table.sort(dbstr_builder.problems, function(a, b)
        if (a.file or '') ~= (b.file or '') then return (a.file or '') < (b.file or '') end
        if (a.str_id or 0) ~= (b.str_id or 0) then return (a.str_id or 0) < (b.str_id or 0) end
        return (a.issue or '') < (b.issue or '')
    end)

    dbstr_builder.status = ('Scan complete: %d problems found'):format(#dbstr_builder.problems)
    dbstr_builder.status_color = #dbstr_builder.problems > 0 and { 0.95, 0.60, 0.20, 1.0 } or { 0.10, 0.95, 0.80, 1.0 }
    dbstr_builder_log(dbstr_builder.status)
    if use_relevant then
        dbstr_builder_log(('Filtered out %d non-dialog entries'):format(skipped_irrelevant))
    end
    if dbstr_builder.scan_incremental then
        dbstr_builder_log(('Incremental mode skipped %d unchanged entries'):format(skipped_incremental))
    end
    dbstr_builder.last_scan_at = os.date('%Y-%m-%d %H:%M:%S')
    dbstr_builder.unsaved_changes = true
    save_dbstr_builder_settings()
    dbstr_builder.running = false
end

local function propose_fixes_from_dialog()
    dbstr_builder.running = true
    dbstr_builder.proposals = {}

    if #dbstr_builder.problems == 0 then
        dbstr_builder.status = 'No problems to propose from'
        dbstr_builder.status_color = { 0.95, 0.60, 0.20, 1.0 }
        dbstr_builder.running = false
        return
    end

    local context = build_dialog_context()
    local fast_mode = #dbstr_builder.problems > FAST_PROPOSE_THRESHOLD
    local keyword_index = {}
    local do_fuzzy = not fast_mode
    local do_dialog_inference = not fast_mode
    local do_semantic = not fast_mode
    local do_family = not fast_mode

    local function add_index_word(word, entry_idx)
        keyword_index[word] = keyword_index[word] or {}
        keyword_index[word][#keyword_index[word] + 1] = entry_idx
    end

    if do_dialog_inference then
        for idx, entry in ipairs(context.lines) do
            local seen = {}
            for word in entry.lower_text:gmatch('[%a%d_]+') do
                if #word >= 4 and not seen[word] then
                    seen[word] = true
                    add_index_word(word, idx)
                end
            end
        end
    end

    local family_by_base = {}
    if do_family then
        for _, v in pairs(context.named_desc or {}) do
            local nm = clean_export_text(v.name or '')
            local base = normalize_builder_name(strip_rank_suffix(nm))
            if base ~= '' then
                family_by_base[base] = family_by_base[base] or {}
                family_by_base[base][#family_by_base[base] + 1] = v
            end
        end
    end

    local matched, unmatched = 0, 0
    for _, p in ipairs(dbstr_builder.problems) do
        local name = clean_export_text(p.name or '')
        if name == '' then name = tostring(p.str_id or '') end
        local nkey = normalize_builder_name(name)
        local sources = {}
        local best_proposed, best_source = '', 'no match'
        local best_conf = 0

        local function add_candidate(source_label, proposed_text, conf)
            local text = clean_export_text(proposed_text or '')
            if text == '' then return end
            local c = math.max(0, math.min(100, tonumber(conf) or 0))
            sources[#sources + 1] = { source = source_label, proposed = text, confidence = c }
            if c > best_conf then
                best_conf = c
                best_proposed = text
                best_source = source_label
            end
        end

        if nkey ~= '' and context.named_desc[nkey] then
            local hit = context.named_desc[nkey]
            add_candidate('markdown/dialog', hit.desc, 95)
        end

        if do_fuzzy and nkey ~= '' then
            local bestf, bestd, bests = nil, nil, nil
            for k, v in pairs(context.named_desc or {}) do
                local dist = levenshtein(nkey, k)
                if dist <= 2 then
                    if not bestf or dist < bestf then
                        bestf, bestd, bests = dist, v.desc, v.source
                    end
                end
            end
            if bestf then
                add_candidate('fuzzy-hint', bestd, 80 - (bestf * 10))
            end
        end

        if do_dialog_inference and nkey ~= '' then
            local candidate_idxs, seen_idx = {}, {}
            for word in nkey:gmatch('[%a%d_]+') do
                if #word >= 4 then
                    for _, idx in ipairs(keyword_index[word] or {}) do
                        if not seen_idx[idx] then
                            seen_idx[idx] = true
                            candidate_idxs[#candidate_idxs + 1] = idx
                        end
                    end
                end
            end

            local best, best_score = nil, -1000000
            for _, idx in ipairs(candidate_idxs) do
                local c = context.lines[idx]
                if c and c.lower_text:find(nkey, 1, true) then
                    local score = 0
                    if #c.text > 20 then score = score + 10 end
                    local start_idx = c.lower_text:find(nkey, 1, true) or 1000
                    if start_idx <= 8 then score = score + 12 end
                    if start_idx <= 24 then score = score + 6 end
                    if c.has_trigger then score = score + 5 end
                    score = score + math.min(8, math.floor(#c.text / 40))
                    if c.lower_text:find('you learn a new spell', 1, true) then score = score - 35 end
                    if c.lower_text:find('single%-target heal') or c.lower_text:find('regeneration') or c.lower_text:find('haste') then score = score + 20 end
                    if score > best_score then
                        best_score = score
                        best = c
                    end
                end
            end
            if best then
                add_candidate('dialog-inference', best.text, 72)
            end
        end

        if do_semantic then
            local sem_text, sem_score = infer_from_dialog_keywords(name, context)
            if sem_text and sem_score > 0 then
                add_candidate('semantic-inference', sem_text, math.min(88, 45 + sem_score))
            end
        end

        if do_family then
            local base = normalize_builder_name(strip_rank_suffix(name))
            local my_rank = rank_suffix(name)
            if base ~= '' and my_rank and family_by_base[base] and #family_by_base[base] > 0 then
                local best_family = family_by_base[base][1]
                add_candidate('family-fill', best_family.desc, 68)
            end
        end

        if p.issue == 'Missing spell entry (not in spells_us)' then
            local direct_desc, direct_score = derive_spell_description_from_dialog(name, context)
            if direct_desc and direct_score > 0 then
                add_candidate('dialog-spell-line', direct_desc, math.min(96, 70 + direct_score))
            end
        end

        if best_proposed ~= '' then
            matched = matched + 1
        else
            if p.issue == 'Missing spell entry (not in spells_us)' then
                best_proposed = ('Description placeholder for %s. Captured from NPC dialog links.'):format(name)
                best_source = (p.source and p.source ~= '' and p.source) or 'dialog-link'
                best_conf = 60
                sources[#sources + 1] = { source = best_source, proposed = best_proposed, confidence = best_conf }
                matched = matched + 1
            else
                unmatched = unmatched + 1
            end
        end

        table.sort(sources, function(a, b) return (a.confidence or 0) > (b.confidence or 0) end)

        dbstr_builder.proposals[#dbstr_builder.proposals + 1] = {
            file = p.file,
            type_id = p.type_id,
            str_id = p.str_id,
            name = name,
            source = (p.source and p.source ~= '' and p.source) or best_source,
            proposed = best_proposed,
            accepted = (best_proposed ~= '') and ((best_conf or 0) >= (tonumber(dbstr_builder.proposal_confidence_threshold) or 70)) or false,
            raw_line = p.raw_line,
            issue = p.issue,
            current = p.current,
            synthetic_new_spell = p.synthetic_new_spell and true or false,
            source_candidates = sources,
            confidence = best_conf,
        }
    end

    table.sort(dbstr_builder.proposals, function(a, b)
        local ac, bc = tonumber(a.confidence) or 0, tonumber(b.confidence) or 0
        if ac ~= bc then return ac > bc end
        if (a.file or '') ~= (b.file or '') then return (a.file or '') < (b.file or '') end
        return (a.str_id or 0) < (b.str_id or 0)
    end)

    dbstr_builder.status = ('Proposals ready: %d matched, %d unmatched%s'):format(
        matched,
        unmatched,
        fast_mode and ' (fast mode)' or ''
    )
    dbstr_builder.status_color = matched > 0 and { 0.10, 0.95, 0.80, 1.0 } or { 0.95, 0.60, 0.20, 1.0 }
    dbstr_builder_log(dbstr_builder.status)
    if fast_mode then
        dbstr_builder_log(('Fast mode enabled for %d problems (threshold %d)'):format(#dbstr_builder.problems, FAST_PROPOSE_THRESHOLD))
    end
    dbstr_builder.running = false
end

local function backup_original_files()
    local stamp = os.date('%Y-%m-%d_%H-%M-%S')
    local backup_dir = BASE_DIR .. '/backups/' .. stamp
    ensure_dir(BASE_DIR .. '/backups')
    ensure_dir(backup_dir)
    local copied = 0
    local srcs = {
        { src = dbstr_builder.dbstr_path, dst = backup_dir .. '/dbstr_us.txt' },
        { src = dbstr_builder.spells_path, dst = backup_dir .. '/spells_us.txt' },
    }
    for _, e in ipairs(srcs) do
        if file_exists(e.src) then
            local in_f = io.open(e.src, 'r')
            local out_f = io.open(e.dst, 'w')
            if in_f and out_f then
                out_f:write(in_f:read('*a') or '')
                out_f:close()
                in_f:close()
                copied = copied + 1
            else
                if in_f then in_f:close() end
                if out_f then out_f:close() end
            end
        end
    end
    return backup_dir, copied
end

local function write_patched_files(target_scope)
    dbstr_builder.running = true
    local scope = target_scope or 'both'

    local accepted = {}
    for _, p in ipairs(dbstr_builder.proposals) do
        if p.accepted and trim(p.proposed or '') ~= '' then
            if scope == 'both' or normalize_key(scope) == normalize_key(p.file) then
            accepted[#accepted + 1] = p
            end
        end
    end
    if #accepted == 0 then
        dbstr_builder.status = 'No accepted proposals to write'
        dbstr_builder.status_color = { 0.95, 0.60, 0.20, 1.0 }
        dbstr_builder.running = false
        return
    end

    local dbstr_lines = read_lines_file(dbstr_builder.dbstr_path)
    if not dbstr_lines then
        dbstr_builder.status = 'Cannot open: ' .. tostring(dbstr_builder.dbstr_path)
        dbstr_builder.status_color = { 0.95, 0.35, 0.35, 1.0 }
        dbstr_builder.running = false
        return
    end
    local spell_lines = read_lines_file(dbstr_builder.spells_path) or {}

    local dbstr_updates = {}
    local spell_updates = {}
    local dbstr_appends = {}
    local spell_appends = {}
    for _, p in ipairs(accepted) do
        if p.file == 'dbstr' then
            local tnum = tonumber(p.type_id) or 0
            local sid = tonumber(p.str_id) or 0
            local key = tostring(tnum) .. ':' .. tostring(sid)
            if p.issue == 'Missing dbstr description entry' then
                dbstr_appends[#dbstr_appends + 1] = { type_id = tnum, str_id = sid, desc = p.proposed }
            else
                dbstr_updates[key] = p.proposed
            end
        elseif p.file == 'spells' then
            local sid = tostring(tonumber(p.str_id) or 0)
            if p.issue == 'Missing description (dbstr type5)' then
                local add_sid = tonumber(sid) or 0
                if add_sid > 0 then
                    dbstr_appends[#dbstr_appends + 1] = { type_id = 5, str_id = add_sid, desc = p.proposed or '' }
                end
            elseif p.issue == 'Missing spell entry (not in spells_us)' or p.synthetic_new_spell then
                spell_appends[#spell_appends + 1] = {
                    str_id = tonumber(sid) or 0,
                    name = p.name or '',
                    desc = p.proposed or '',
                }
            else
                spell_updates[sid] = spell_updates[sid] or {}
                if p.issue == 'Missing spell name' or p.issue == 'Unknown spell name' then
                    spell_updates[sid][2] = p.proposed
                elseif p.issue == 'Missing cast_on_you message' then
                    spell_updates[sid][7] = p.proposed
                elseif p.issue == 'Missing cast_on_other message' then
                    spell_updates[sid][8] = p.proposed
                elseif p.issue == 'Missing wear_off message' then
                    spell_updates[sid][9] = p.proposed
                end
            end
        end
    end

    local dbstr_fix_count = 0
    local dbstr_existing = {}
    for i, raw in ipairs(dbstr_lines) do
        local type_id, str_id = raw:match('^(%d+)%^(%d+)%^')
        if type_id and str_id then
            local key = tostring(tonumber(type_id) or 0) .. ':' .. tostring(tonumber(str_id) or 0)
            dbstr_existing[key] = true
            local repl = dbstr_updates[key]
            if repl and trim(repl) ~= '' then
                local suffix_flag = raw:match('%^(%d+)%s*$') or '0'
                local safe = tostring(repl):gsub('[\r\n%^]', ' ')
                dbstr_lines[i] = ('%s^%s^%s^%s'):format(type_id, str_id, safe, suffix_flag)
                dbstr_fix_count = dbstr_fix_count + 1
            end
        end
    end
    for _, add in ipairs(dbstr_appends) do
        local tnum = tonumber(add.type_id) or 5
        local sid = tonumber(add.str_id) or 0
        local key = tostring(tnum) .. ':' .. tostring(sid)
        if sid > 0 and not dbstr_existing[key] then
            local safe = tostring(add.desc or ''):gsub('[\r\n%^]', ' ')
            dbstr_lines[#dbstr_lines + 1] = ('%d^%d^%s^0'):format(tnum, sid, safe)
            dbstr_existing[key] = true
            dbstr_fix_count = dbstr_fix_count + 1
        end
    end

    local spell_fix_count = 0
    local spell_existing = {}
    for i, raw in ipairs(spell_lines) do
        local fields = split_caret_fields(raw)
        local sid = tostring(tonumber(fields[1] or 0) or 0)
        spell_existing[sid] = true
        local updates = spell_updates[sid]
        if updates then
            local changed = false
            for idx, val in pairs(updates) do
                while #fields < idx do fields[#fields + 1] = '' end
                local safe = tostring(val):gsub('[\r\n%^]', ' ')
                if trim(fields[idx] or '') ~= trim(safe) then
                    fields[idx] = safe
                    changed = true
                end
            end
            if changed then
                spell_lines[i] = table.concat(fields, '^')
                spell_fix_count = spell_fix_count + 1
            end
        end
    end

    -- Cleanup pass: remove stale synthetic safe-range spell rows when a real-ranked spell already exists.
    local function is_safe_id(sid)
        local n = tonumber(sid) or 0
        return n >= SAFE_SPELL_ID_MIN and n <= SAFE_SPELL_ID_MAX
    end
    local base_to_ids = {}
    for _, raw in ipairs(spell_lines) do
        local fields = split_caret_fields(raw)
        local sid = tonumber(fields[1] or 0) or 0
        local sname = trim(fields[2] or '')
        local bkey = normalize_builder_name(strip_rank_suffix(sname))
        if sid > 0 and bkey ~= '' then
            base_to_ids[bkey] = base_to_ids[bkey] or {}
            base_to_ids[bkey][#base_to_ids[bkey] + 1] = sid
        end
    end
    local remove_safe_ids = {}
    for _, ids in pairs(base_to_ids) do
        local has_non_safe = false
        for _, sid in ipairs(ids) do
            if not is_safe_id(sid) then
                has_non_safe = true
                break
            end
        end
        if has_non_safe then
            for _, sid in ipairs(ids) do
                if is_safe_id(sid) then
                    remove_safe_ids[sid] = true
                end
            end
        end
    end
    local removed_spells = 0
    if next(remove_safe_ids) ~= nil then
        local keep_spell_lines = {}
        for _, raw in ipairs(spell_lines) do
            local fields = split_caret_fields(raw)
            local sid = tonumber(fields[1] or 0) or 0
            if remove_safe_ids[sid] then
                removed_spells = removed_spells + 1
            else
                keep_spell_lines[#keep_spell_lines + 1] = raw
            end
        end
        spell_lines = keep_spell_lines

        local removed_dbstr = 0
        local keep_dbstr_lines = {}
        for _, raw in ipairs(dbstr_lines) do
            local parsed = parse_dbstr_line(raw)
            if parsed and tonumber(parsed.type_id) == 5 and remove_safe_ids[tonumber(parsed.str_id) or 0] then
                removed_dbstr = removed_dbstr + 1
            else
                keep_dbstr_lines[#keep_dbstr_lines + 1] = raw
            end
        end
        dbstr_lines = keep_dbstr_lines

        if removed_spells > 0 or removed_dbstr > 0 then
            dbstr_builder_log(('Cleanup removed %d synthetic spell row(s) and %d dbstr type 5 row(s) mapped to real spell IDs'):format(
                removed_spells, removed_dbstr
            ))
        end
    end

    local write_taken_ids = {}
    for sid_str in pairs(spell_existing) do
        local sid_num = tonumber(sid_str)
        if sid_num then write_taken_ids[sid_num] = true end
    end
    for key in pairs(dbstr_existing) do
        local sid = tonumber((tostring(key):match('^%d+:(%d+)$') or ''))
        if sid then write_taken_ids[sid] = true end
    end

    for _, add in ipairs(spell_appends) do
        local req_sid = tonumber(add.str_id) or 0
        local final_sid = req_sid
        if final_sid < SAFE_SPELL_ID_MIN or final_sid > SAFE_SPELL_ID_MAX or write_taken_ids[final_sid] then
            local alloc = allocate_safe_spell_ids(write_taken_ids, 1)
            final_sid = alloc[1] or 0
        end
        local sid = tostring(final_sid)
        if sid ~= '0' and not spell_existing[sid] then
            local fname = tostring(add.name or ''):gsub('[\r\n%^]', ' ')
            local new_fields = {
                sid, fname, 'PLAYER_1', '', '', '', '', '', '', '0'
            }
            spell_lines[#spell_lines + 1] = table.concat(new_fields, '^')
            spell_existing[sid] = true
            write_taken_ids[tonumber(sid) or 0] = true
            spell_fix_count = spell_fix_count + 1

            local dkey = '5:' .. sid
            if not dbstr_existing[dkey] then
                local ddesc = tostring(add.desc or ''):gsub('[\r\n%^]', ' ')
                dbstr_lines[#dbstr_lines + 1] = ('5^%s^%s^0'):format(sid, ddesc)
                dbstr_existing[dkey] = true
                write_taken_ids[tonumber(sid) or 0] = true
                dbstr_fix_count = dbstr_fix_count + 1
            end
        end
    end

    local backup_dir, copied = '', 0
    if not dbstr_builder.dry_run_mode then
        backup_dir, copied = backup_original_files()
        ensure_dir(BASE_DIR)
        local out_db = io.open(dbstr_builder.dbstr_out, 'w')
        if not out_db then
            dbstr_builder.status = 'Cannot write: ' .. tostring(dbstr_builder.dbstr_out)
            dbstr_builder.status_color = { 0.95, 0.35, 0.35, 1.0 }
            dbstr_builder.running = false
            return
        end
        if scope == 'both' or scope == 'dbstr' then
            out_db:write(table.concat(dbstr_lines, '\n'))
        else
            local src_db = io.open(dbstr_builder.dbstr_path, 'r')
            out_db:write(src_db and (src_db:read('*a') or '') or '')
            if src_db then src_db:close() end
        end
        out_db:close()

        local out_sp = io.open(dbstr_builder.spells_out, 'w')
        if not out_sp then
            dbstr_builder.status = 'Cannot write: ' .. tostring(dbstr_builder.spells_out)
            dbstr_builder.status_color = { 0.95, 0.35, 0.35, 1.0 }
            dbstr_builder.running = false
            return
        end
        if scope == 'both' or scope == 'spells' then
            out_sp:write(table.concat(spell_lines, '\n'))
        else
            local src_sp = io.open(dbstr_builder.spells_path, 'r')
            out_sp:write(src_sp and (src_sp:read('*a') or '') or '')
            if src_sp then src_sp:close() end
        end
        out_sp:close()
    end

    local changelog = {}
    changelog[#changelog + 1] = ('Patch generated at %s'):format(os.date('%Y-%m-%d %H:%M:%S'))
    changelog[#changelog + 1] = ('Scope: %s'):format(scope)
    changelog[#changelog + 1] = ('dbstr fixes: %d'):format(dbstr_fix_count)
    changelog[#changelog + 1] = ('spells fixes: %d'):format(spell_fix_count)
    for _, p in ipairs(accepted) do
        changelog[#changelog + 1] = ('- [%s:%d] %s | %s -> %s'):format(
            p.file or '?',
            tonumber(p.str_id) or 0,
            p.issue or '',
            truncate_text(p.current or '', 60),
            truncate_text(p.proposed or '', 80)
        )
    end
    local log_path = BASE_DIR .. '/patch_log_' .. os.date('%Y%m%d_%H%M%S') .. '.txt'
    local logf = io.open(log_path, 'w')
    if logf then
        logf:write(table.concat(changelog, '\n'))
        logf:close()
    end

    dbstr_builder.status = ('Wrote patched files: %d dbstr fixes, %d spells fixes'):format(dbstr_fix_count, spell_fix_count)
    dbstr_builder.status_color = { 0.10, 0.95, 0.80, 1.0 }
    dbstr_builder_log(dbstr_builder.status)
    if not dbstr_builder.dry_run_mode then
        dbstr_builder_log(('Backed up %d source files -> %s'):format(copied, backup_dir))
        dbstr_builder_log('dbstr output: ' .. dbstr_builder.dbstr_out)
        dbstr_builder_log('spells output: ' .. dbstr_builder.spells_out)
    end
    dbstr_builder_log('changelog: ' .. log_path)
    if not dbstr_builder.dry_run_mode then
        dbstr_builder.last_write_at = os.date('%Y-%m-%d %H:%M:%S')
        dbstr_builder.unsaved_changes = false
    end
    save_dbstr_builder_settings()
    push_feed('export', dbstr_builder.status, 0.10, 1.00, 0.50)

    if dbstr_builder.dry_run_mode then
        dbstr_builder.status = ('Dry run complete: would modify %d dbstr and %d spells entries'):format(dbstr_fix_count, spell_fix_count)
        dbstr_builder.status_color = { 0.90, 0.88, 0.30, 1.0 }
    else
        local prev_inc = dbstr_builder.scan_incremental
        dbstr_builder.scan_incremental = false
        scan_dbstr_problems(false)
        dbstr_builder.scan_incremental = prev_inc
        dbstr_builder_log(('Post-write validation remaining issues: %d'):format(#dbstr_builder.problems))
    end
    dbstr_builder.running = false
end

local function draw_dbstr_builder()
    if not dbstr_builder.open then return end
    local pv, pc = push_theme()
    ImGui.SetNextWindowSize(820, 580, ImGuiCond.FirstUseEver)

    dbstr_builder.open = ImGui.Begin('DBStr & Spells Builder###DBStrBuilder', dbstr_builder.open)
    if dbstr_builder.open then
        ImGui.Text('dbstr_us.txt path')
        ImGui.SameLine()
        ImGui.SetNextItemWidth(500)
        local db_path, db_changed = ImGui.InputText('##dbstr_path', dbstr_builder.dbstr_path)
        if db_changed then
            dbstr_builder.dbstr_path = db_path
            save_dbstr_builder_settings()
        end
        ImGui.SameLine()
        if ImGui.Button('Use Default##dbstr_default') then
            dbstr_builder.dbstr_path = DBSTR_SOURCE
            save_dbstr_builder_settings()
        end

        ImGui.Text('spells_us.txt path')
        ImGui.SameLine()
        ImGui.SetNextItemWidth(500)
        local sp_path, sp_changed = ImGui.InputText('##spells_path', dbstr_builder.spells_path)
        if sp_changed then
            dbstr_builder.spells_path = sp_path
            save_dbstr_builder_settings()
        end
        ImGui.SameLine()
        if ImGui.Button('Use Default##spells_default') then
            dbstr_builder.spells_path = SPELLS_SOURCE
            save_dbstr_builder_settings()
        end

        ImGui.Text('markdown hints path')
        ImGui.SameLine()
        ImGui.SetNextItemWidth(500)
        local md_path, md_changed = ImGui.InputText('##markdown_path', dbstr_builder.markdown_path)
        if md_changed then
            dbstr_builder.markdown_path = md_path
            save_dbstr_builder_settings()
        end
        ImGui.SameLine()
        if ImGui.Button('Load Markdown Hints') then
            safe_builder_action('Load Markdown Hints', import_markdown_hints)
        end

        local relevant_only, relevant_changed = ImGui.Checkbox('Scan dialog-relevant only', dbstr_builder.scan_dialog_relevant_only)
        if relevant_changed then
            dbstr_builder.scan_dialog_relevant_only = relevant_only
            save_dbstr_builder_settings()
        end
        ImGui.SameLine()
        ImGui.TextDisabled('(off = full scan)')
        ImGui.SameLine()
        ImGui.TextDisabled(('Hints loaded: %d'):format(tonumber(dbstr_builder.imported_hint_count) or 0))

        local create_missing, create_missing_changed = ImGui.Checkbox('Create missing spell entries from dialog links', dbstr_builder.create_missing_spell_entries)
        if create_missing_changed then
            dbstr_builder.create_missing_spell_entries = create_missing
            save_dbstr_builder_settings()
        end

        local dry_run, dry_changed = ImGui.Checkbox('Dry run mode (no file writes)', dbstr_builder.dry_run_mode)
        if dry_changed then
            dbstr_builder.dry_run_mode = dry_run
            save_dbstr_builder_settings()
        end
        ImGui.SameLine()
        local inc_scan, inc_changed = ImGui.Checkbox('Incremental scan', dbstr_builder.scan_incremental)
        if inc_changed then
            dbstr_builder.scan_incremental = inc_scan
            save_dbstr_builder_settings()
        end

        local file_scopes = { 'both', 'dbstr', 'spells' }
        local next_file_scope = nil
        for i, v in ipairs(file_scopes) do
            if v == dbstr_builder.scan_file_scope then
                next_file_scope = file_scopes[(i % #file_scopes) + 1]
                break
            end
        end
        if not next_file_scope then next_file_scope = 'both' end
        if ImGui.Button('Scan File: ' .. tostring(dbstr_builder.scan_file_scope or 'both')) then
            dbstr_builder.scan_file_scope = next_file_scope
            save_dbstr_builder_settings()
        end
        ImGui.SameLine()
        local issue_scopes = {
            'descriptions_only', 'all', 'Empty description', 'Placeholder text', 'Stub (< 10 chars)',
            'Missing dbstr description entry', 'Missing description (dbstr type5)', 'Missing spell entry (not in spells_us)',
            'Missing spell name', 'Unknown spell name'
        }
        local next_issue_scope = nil
        for i, v in ipairs(issue_scopes) do
            if v == dbstr_builder.scan_issue_scope then
                next_issue_scope = issue_scopes[(i % #issue_scopes) + 1]
                break
            end
        end
        if not next_issue_scope then next_issue_scope = 'descriptions_only' end
        if ImGui.Button('Issue: ' .. tostring(dbstr_builder.scan_issue_scope or 'descriptions_only')) then
            dbstr_builder.scan_issue_scope = next_issue_scope
            save_dbstr_builder_settings()
        end

        ImGui.Separator()
        if ImGui.Button('Scan for Problems') then
            safe_builder_action('Scan for Problems', function() scan_dbstr_problems() end)
        end
        ImGui.SameLine()
        if ImGui.Button('Scan All Problems') then
            safe_builder_action('Scan All Problems', function() scan_dbstr_problems(false) end)
        end
        ImGui.SameLine()
        if ImGui.Button('Scan Relevant Only') then
            safe_builder_action('Scan Relevant Only', function() scan_dbstr_problems(true) end)
        end
        ImGui.SameLine()
        if ImGui.Button('Dry Run Cycle') then
            safe_builder_action('Dry Run Cycle', function()
                local prev = dbstr_builder.dry_run_mode
                dbstr_builder.dry_run_mode = true
                scan_dbstr_problems()
                propose_fixes_from_dialog()
                write_patched_files('both')
                dbstr_builder.dry_run_mode = prev
            end)
        end
        ImGui.SameLine()
        if ImGui.Button('Propose Fixes (Dialog + Markdown)') then
            safe_builder_action('Propose Fixes', propose_fixes_from_dialog)
        end
        ImGui.SameLine()
        if ImGui.Button('Write Patched Files') then
            safe_builder_action('Write Patched Files', function() write_patched_files('both') end)
        end
        ImGui.SameLine()
        if ImGui.Button('Write dbstr only') then
            safe_builder_action('Write dbstr only', function() write_patched_files('dbstr') end)
        end
        ImGui.SameLine()
        if ImGui.Button('Write spells only') then
            safe_builder_action('Write spells only', function() write_patched_files('spells') end)
        end
        ImGui.SameLine()
        if ImGui.Button('Preview Patch') then
            dbstr_builder.preview_patch_text = build_preview_patch_text()
            dbstr_builder.show_preview_patch = true
        end
        ImGui.SameLine()
        if ImGui.Button(I.clear .. ' Clear') then
            dbstr_builder.problems = {}
            dbstr_builder.proposals = {}
            dbstr_builder.log = {}
            dbstr_builder.status = 'Cleared'
            dbstr_builder.status_color = { 0.90, 0.88, 0.30, 1.0 }
        end
        ImGui.SameLine()
        if ImGui.Button(I.ban .. ' Close') then dbstr_builder.open = false end

        ImGui.Separator()
        ImGui.Text('Search')
        ImGui.SameLine()
        ImGui.SetNextItemWidth(320)
        local sv, schanged = ImGui.InputText('##dbstr_table_search', dbstr_builder.table_search or '')
        if schanged then dbstr_builder.table_search = sv end
        ImGui.SameLine()
        if ImGui.Button('Clear Search##dbstr_table_search_clear') then dbstr_builder.table_search = '' end
        ImGui.SameLine()
        local rgx, rgx_changed = ImGui.Checkbox('Regex', dbstr_builder.search_use_regex)
        if rgx_changed then dbstr_builder.search_use_regex = rgx; save_dbstr_builder_settings() end
        ImGui.SameLine()
        if ImGui.Button('Save Search') then
            local q = trim(dbstr_builder.table_search or '')
            if q ~= '' then
                dbstr_builder.saved_searches[#dbstr_builder.saved_searches + 1] = q
                save_dbstr_builder_settings()
            end
        end
        ImGui.SameLine()
        if ImGui.Button('Next Saved') then
            if #dbstr_builder.saved_searches > 0 then
                local first = table.remove(dbstr_builder.saved_searches, 1)
                table.insert(dbstr_builder.saved_searches, first)
                dbstr_builder.table_search = first
            end
        end
        ImGui.SameLine()
        ImGui.TextDisabled('Filters by name/id/issue/source/value')

        ImGui.Separator()
        ImGui.TextColored(
            dbstr_builder.status_color[1],
            dbstr_builder.status_color[2],
            dbstr_builder.status_color[3],
            dbstr_builder.status_color[4],
            dbstr_builder.status
        )
        ImGui.TextDisabled(('Problems: %d   Proposals: %d'):format(#dbstr_builder.problems, #dbstr_builder.proposals))
        ImGui.TextDisabled(('Last Scan: %s | Last Write: %s | Unsaved: %s'):format(
            dbstr_builder.last_scan_at ~= '' and dbstr_builder.last_scan_at or 'never',
            dbstr_builder.last_write_at ~= '' and dbstr_builder.last_write_at or 'never',
            dbstr_builder.unsaved_changes and 'yes' or 'no'
        ))

        ImGui.Separator()
        ImGui.Text('Proposal Source Filter')
        ImGui.SameLine()
        local src_filters = { 'all', 'NPC: Exported Markdown', 'Family Fill', 'Dialog Inference', 'no match' }
        local next_src = nil
        for i, v in ipairs(src_filters) do
            if v == dbstr_builder.proposal_source_filter then
                next_src = src_filters[(i % #src_filters) + 1]
                break
            end
        end
        if not next_src then next_src = 'all' end
        if ImGui.Button(dbstr_builder.proposal_source_filter or 'all') then
            dbstr_builder.proposal_source_filter = next_src
            save_dbstr_builder_settings()
        end
        ImGui.SameLine()
        ImGui.Text('Min Confidence')
        ImGui.SameLine()
        ImGui.SetNextItemWidth(140)
        local conf, conf_changed = ImGui.SliderInt('##bulk_conf', tonumber(dbstr_builder.proposal_confidence_threshold) or 70, 0, 100)
        if conf_changed then
            dbstr_builder.proposal_confidence_threshold = conf
            save_dbstr_builder_settings()
        end
        ImGui.SameLine()
        if ImGui.Button('Bulk Accept >= Threshold') then
            bulk_set_accept_by_confidence(dbstr_builder.proposal_confidence_threshold)
        end
        ImGui.SameLine()
        if ImGui.Button('Accept Visible') then bulk_set_accept_filtered(true) end
        ImGui.SameLine()
        if ImGui.Button('Reject Visible') then bulk_set_accept_filtered(false) end
        ImGui.SameLine()
        local eba, ebac = ImGui.Checkbox('Edit before accepting', dbstr_builder.edit_before_accept)
        if ebac then dbstr_builder.edit_before_accept = eba end

        if dbstr_builder.last_action_undo and os.time() <= (dbstr_builder.last_action_undo.expires_at or 0) then
            ImGui.SameLine()
            if ImGui.Button('Undo Last') then
                -- Simple undo: invert last bulk accept operation quickly.
                if dbstr_builder.last_action_undo.kind == 'bulk_accept' then
                    for _, p in ipairs(dbstr_builder.proposals or {}) do
                        if (tonumber(p.confidence) or 0) >= (tonumber(dbstr_builder.proposal_confidence_threshold) or 0) then
                            p.accepted = false
                        end
                    end
                end
                dbstr_builder.last_action_undo = nil
            end
        end

        if ImGui.BeginTabBar('##dbstr_builder_tabs') then
            if ImGui.BeginTabItem('Problems') then
                local tflags = ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg + ImGuiTableFlags.ScrollY + ImGuiTableFlags.Resizable + ImGuiTableFlags.Sortable
                local selected_count = 0
                for _, v in pairs(dbstr_builder.selected_problem_rows or {}) do if v then selected_count = selected_count + 1 end end
                if selected_count > 1 then
                    if ImGui.Button('Bulk Reject Selected') then
                        local kept = {}
                        for i, p in ipairs(dbstr_builder.problems) do
                            if not dbstr_builder.selected_problem_rows[i] then kept[#kept + 1] = p end
                        end
                        dbstr_builder.problems = kept
                        dbstr_builder.selected_problem_rows = {}
                    end
                    ImGui.SameLine()
                    if ImGui.Button('Bulk Accept Selected -> Proposals') then
                        for i, p in ipairs(dbstr_builder.problems) do
                            if dbstr_builder.selected_problem_rows[i] then
                                dbstr_builder.proposals[#dbstr_builder.proposals + 1] = {
                                    file = p.file, type_id = p.type_id, str_id = p.str_id, name = p.name,
                                    source = 'manual', proposed = p.current or '', accepted = true, raw_line = p.raw_line,
                                    issue = p.issue, current = p.current, confidence = 100, source_candidates = {},
                                }
                            end
                        end
                        dbstr_builder.selected_problem_rows = {}
                    end
                end
                if ImGui.BeginTable('##dbstr_problems_tbl', 7, tflags, 0, 300) then
                    ImGui.TableSetupScrollFreeze(0, 1)
                    ImGui.TableSetupColumn('Sel', ImGuiTableColumnFlags.WidthFixed, 44)
                    ImGui.TableSetupColumn('File', ImGuiTableColumnFlags.WidthFixed, 80)
                    ImGui.TableSetupColumn('ID', ImGuiTableColumnFlags.WidthFixed, 60)
                    ImGui.TableSetupColumn('Name / Key', ImGuiTableColumnFlags.WidthStretch, 0.35)
                    ImGui.TableSetupColumn('Issue', ImGuiTableColumnFlags.WidthStretch, 0.35)
                    ImGui.TableSetupColumn('Current Value', ImGuiTableColumnFlags.WidthStretch, 0.30)
                    ImGui.TableSetupColumn('Jump', ImGuiTableColumnFlags.WidthFixed, 62)
                    ImGui.TableHeadersRow()

                    local shown = 0
                    for i, p in ipairs(dbstr_builder.problems) do
                        if builder_row_matches_search(
                            dbstr_builder.table_search,
                            p.file, p.str_id, p.name, p.issue, p.current
                        ) then
                        local r, g, b = 0.90, 0.88, 0.30
                        local il = (p.issue or ''):lower()
                        if il:find('empty', 1, true) or il:find('missing', 1, true) then
                            r, g, b = 0.95, 0.35, 0.35
                        elseif il:find('placeholder', 1, true) or il:find('unknown', 1, true) or il:find('oops', 1, true) then
                            r, g, b = 0.95, 0.60, 0.20
                        elseif il:find('stub', 1, true) then
                            r, g, b = 0.90, 0.88, 0.30
                        end

                        ImGui.TableNextRow()
                        ImGui.TableSetColumnIndex(0)
                        local selv, selc = ImGui.Checkbox('##psel_' .. tostring(i), dbstr_builder.selected_problem_rows[i] or false)
                        if selc then dbstr_builder.selected_problem_rows[i] = selv end
                        ImGui.TableSetColumnIndex(1); ImGui.TextDisabled(p.file or '')
                        ImGui.TableSetColumnIndex(2); ImGui.Text(tostring(p.str_id or 0))
                        ImGui.TableSetColumnIndex(3); ImGui.TextDisabled(truncate_text(p.name or tostring(p.str_id or ''), 60))
                        ImGui.TableSetColumnIndex(4); ImGui.TextColored(r, g, b, 1.0, p.issue or '')
                        ImGui.TableSetColumnIndex(5)
                        local cv, cvc = ImGui.InputText('##curv_' .. tostring(i), tostring(p.current or ''))
                        if cvc then
                            p.current = cv
                            p.manual_override = true
                        end
                        ImGui.TableSetColumnIndex(6)
                        if ImGui.SmallButton('Jump##jump_' .. tostring(i)) then
                            dbstr_builder.spell_panel_id = tonumber(p.str_id) or 0
                            dbstr_builder.show_spell_panel = true
                        end
                            shown = shown + 1
                        end
                    end
                    ImGui.EndTable()
                    ImGui.TextDisabled(('Showing %d / %d'):format(shown, #dbstr_builder.problems))
                end
                ImGui.EndTabItem()
            end

            if ImGui.BeginTabItem('Proposals') then
                local tflags = ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg + ImGuiTableFlags.ScrollY + ImGuiTableFlags.Resizable
                if ImGui.BeginTable('##dbstr_proposals_tbl', 7, tflags + ImGuiTableFlags.Sortable, 0, 300) then
                    ImGui.TableSetupScrollFreeze(0, 1)
                    ImGui.TableSetupColumn('Accept', ImGuiTableColumnFlags.WidthFixed, 66)
                    ImGui.TableSetupColumn('File', ImGuiTableColumnFlags.WidthFixed, 80)
                    ImGui.TableSetupColumn('ID', ImGuiTableColumnFlags.WidthFixed, 60)
                    ImGui.TableSetupColumn('Name', ImGuiTableColumnFlags.WidthStretch, 0.25)
                    ImGui.TableSetupColumn('Source', ImGuiTableColumnFlags.WidthStretch, 0.25)
                    ImGui.TableSetupColumn('Confidence', ImGuiTableColumnFlags.WidthFixed, 90)
                    ImGui.TableSetupColumn('Proposed Description', ImGuiTableColumnFlags.WidthStretch, 0.50)
                    ImGui.TableHeadersRow()

                    local shown = 0
                    for i, p in ipairs(dbstr_builder.proposals) do
                        if proposal_matches_source_filter(p) then
                        if builder_row_matches_search(
                            dbstr_builder.table_search,
                            p.file, p.str_id, p.name, p.source, p.issue, p.proposed, p.current
                        ) then
                        ImGui.TableNextRow()
                        ImGui.TableSetColumnIndex(0)
                        local nv, changed = ImGui.Checkbox('##accept_proposal_' .. tostring(i), p.accepted or false)
                        if changed then
                            if nv and dbstr_builder.edit_before_accept then
                                p.edit_buffer = p.proposed or ''
                            end
                            p.accepted = nv
                        end
                        ImGui.TableSetColumnIndex(1); ImGui.TextDisabled(p.file or '')
                        ImGui.TableSetColumnIndex(2); ImGui.Text(tostring(p.str_id or 0))
                        ImGui.TableSetColumnIndex(3); ImGui.TextDisabled(truncate_text(p.name or '', 40))
                        ImGui.TableSetColumnIndex(4); ImGui.TextDisabled(proposal_source_bucket(p))
                        ImGui.TableSetColumnIndex(5); ImGui.TextDisabled(('%d%%'):format(tonumber(p.confidence) or 0))
                        ImGui.TableSetColumnIndex(6); ImGui.TextDisabled(truncate_text(p.proposed or '', 80))
                        if ImGui.IsItemHovered() then
                            ImGui.BeginTooltip()
                            ImGui.TextWrapped(p.proposed or '')
                            if p.source_candidates and #p.source_candidates > 0 then
                                ImGui.Separator()
                                for _, src in ipairs(p.source_candidates) do
                                    ImGui.TextDisabled(('[%d%%] %s'):format(tonumber(src.confidence) or 0, src.source or ''))
                                end
                            end
                            ImGui.EndTooltip()
                        end
                        if p.accepted and dbstr_builder.edit_before_accept then
                            ImGui.TableSetColumnIndex(6)
                            ImGui.SetNextItemWidth(-1)
                            local ev, ec = ImGui.InputText('##edit_before_accept_' .. tostring(i), p.edit_buffer or p.proposed or '')
                            if ec then
                                p.edit_buffer = ev
                                p.proposed = ev
                            end
                        end
                            shown = shown + 1
                        end
                        end
                    end
                    ImGui.EndTable()
                    ImGui.TextDisabled(('Showing %d / %d'):format(shown, #dbstr_builder.proposals))
                end
                ImGui.EndTabItem()
            end
            ImGui.EndTabBar()
        end

        ImGui.Separator()
        ImGui.BeginChild('##dbstr_log', 0, 100, true, ImGuiWindowFlags.HorizontalScrollbar)
        for _, line in ipairs(dbstr_builder.log) do
            ImGui.TextDisabled(line)
        end
        ImGui.EndChild()
    end

    ImGui.End()
    pop_theme(pv, pc)

    if dbstr_builder.show_spell_panel and (tonumber(dbstr_builder.spell_panel_id) or 0) > 0 then
        local open_panel = true
        ImGui.SetNextWindowSize(760, 280, ImGuiCond.FirstUseEver)
        open_panel = ImGui.Begin('Spell Side Panel###DBStrSpellPanel', open_panel)
        if open_panel then
            local sid = tonumber(dbstr_builder.spell_panel_id) or 0
            if sid > 0 then
                ImGui.Text('Spell ID: ' .. tostring(sid))
                dbstr_builder.spell_panel_raw = get_spell_raw_by_id(sid)
                ImGui.BeginChild('##spell_raw_child', 0, 0, true, ImGuiWindowFlags.HorizontalScrollbar)
                ImGui.TextWrapped(dbstr_builder.spell_panel_raw ~= '' and dbstr_builder.spell_panel_raw or '(not found in spells_us.txt)')
                ImGui.EndChild()
            end
        end
        ImGui.End()
        if not open_panel then dbstr_builder.show_spell_panel = false end
    end

    if dbstr_builder.show_preview_patch then
        local open_prev = true
        ImGui.SetNextWindowSize(820, 420, ImGuiCond.FirstUseEver)
        open_prev = ImGui.Begin('Patch Preview###DBStrPatchPreview', open_prev)
        if open_prev then
            ImGui.BeginChild('##patch_preview_child', 0, 0, true, ImGuiWindowFlags.HorizontalScrollbar)
            ImGui.TextWrapped(dbstr_builder.preview_patch_text or '')
            ImGui.EndChild()
        end
        ImGui.End()
        if not open_prev then dbstr_builder.show_preview_patch = false end
    end
end

push_theme = function()
    local pv, pc = 0, 0
    local function sv(var, ...) ImGui.PushStyleVar(var, ...); pv = pv + 1 end
    local function sc(col, ...) ImGui.PushStyleColor(col, ...); pc = pc + 1 end

    sv(ImGuiStyleVar.WindowRounding, 4)
    sv(ImGuiStyleVar.FrameRounding, 5)
    sv(ImGuiStyleVar.FrameBorderSize, 1)
    sv(ImGuiStyleVar.WindowPadding, 8, 6)
    sv(ImGuiStyleVar.ItemSpacing, 6, 4)
    sv(ImGuiStyleVar.CellPadding, 4, 3)

    sc(ImGuiCol.WindowBg,            0.04, 0.02, 0.08, 0.95)
    sc(ImGuiCol.TitleBg,             0.14, 0.02, 0.22, 1.00)
    sc(ImGuiCol.TitleBgActive,       0.24, 0.04, 0.32, 1.00)
    sc(ImGuiCol.MenuBarBg,           0.08, 0.03, 0.14, 1.00)
    sc(ImGuiCol.Button,              0.18, 0.06, 0.26, 1.00)
    sc(ImGuiCol.ButtonHovered,       0.36, 0.09, 0.44, 1.00)
    sc(ImGuiCol.ButtonActive,        0.50, 0.12, 0.58, 1.00)
    sc(ImGuiCol.FrameBg,             0.10, 0.04, 0.16, 1.00)
    sc(ImGuiCol.FrameBgHovered,      0.18, 0.07, 0.26, 1.00)
    sc(ImGuiCol.FrameBgActive,       0.26, 0.10, 0.36, 1.00)
    sc(ImGuiCol.Header,              0.22, 0.07, 0.30, 1.00)
    sc(ImGuiCol.HeaderHovered,       0.34, 0.10, 0.42, 1.00)
    sc(ImGuiCol.HeaderActive,        0.44, 0.13, 0.52, 1.00)
    sc(ImGuiCol.TableRowBg,          0.00, 0.00, 0.00, 0.00)
    sc(ImGuiCol.TableRowBgAlt,       0.08, 0.03, 0.14, 0.60)
    sc(ImGuiCol.TableBorderLight,    0.30, 0.10, 0.40, 0.60)
    sc(ImGuiCol.TableBorderStrong,   0.60, 0.18, 0.80, 0.80)
    sc(ImGuiCol.Border,              0.90, 0.16, 0.68, 0.70)
    sc(ImGuiCol.Separator,           0.22, 0.90, 0.84, 0.60)
    sc(ImGuiCol.ScrollbarBg,         0.02, 0.01, 0.06, 0.80)
    sc(ImGuiCol.ScrollbarGrab,       0.30, 0.08, 0.40, 0.80)
    sc(ImGuiCol.ScrollbarGrabHovered,0.50, 0.14, 0.60, 0.90)
    sc(ImGuiCol.Text,                0.92, 0.96, 1.00, 1.00)
    return pv, pc
end

pop_theme = function(pv, pc)
    if pc and pc > 0 then ImGui.PopStyleColor(pc) end
    if pv and pv > 0 then ImGui.PopStyleVar(pv) end
end

local function draw_console()
    if not ui_open then return end
    local pv, pc = push_theme()
    ImGui.SetNextWindowSize(980, 620, ImGuiCond.FirstUseEver)
    ImGui.SetNextWindowBgAlpha(0.95)

    local is_open, show = ImGui.Begin('NPC Dialog Console###NPCDialogConsole', ui_open)
    ui_open = is_open
    if not show then
        ImGui.End()
        pop_theme(pv, pc)
        return
    end

    if logging_enabled then
        if ImGui.Button(I.pause .. ' Stop Logging') then
            logging_enabled = false
            status_msg = 'Logging paused'
            status_color = { 0.95, 0.70, 0.20, 1.0 }
            push_feed('state', 'Logging OFF', 0.95, 0.70, 0.20)
        end
    else
        if ImGui.Button(I.play .. ' Start Logging') then
            logging_enabled = true
            status_msg = 'Logging active'
            status_color = { 0.10, 1.00, 0.50, 1.0 }
            push_feed('state', 'Logging ON', 0.10, 1.00, 0.50)
        end
    end

    ImGui.SameLine()
    if ImGui.Button(I.check .. ' Accept Pending') then accept_pending() end
    ImGui.SameLine()
    if ImGui.Button(I.ban .. ' Reject Pending') then reject_pending() end
    ImGui.SameLine()
    if ImGui.Button(I.save .. ' Save Accepted') then save_accepted() end
    ImGui.SameLine()
    if ImGui.Button(I.clock .. ' Save Pending Snapshot') then save_pending_snapshot() end
    ImGui.SameLine()
    if ImGui.Button(I.refresh .. ' Build Website') then build_website_export() end
    ImGui.SameLine()
    if ImGui.Button(I.refresh .. ' Build DBStr & Spells') then dbstr_builder.open = true end
    ImGui.SameLine()
    if ImGui.Button(I.save .. ' Save + Build') then save_and_build() end
    ImGui.SameLine()
    if ImGui.Button('Open Export Folder') then open_export_folder() end
    ImGui.SameLine()
    if ImGui.Button(I.clear .. ' Clear Feed') then feed = {} end

    ImGui.Separator()
    ImGui.TextColored(status_color[1], status_color[2], status_color[3], status_color[4], status_msg)
    ImGui.TextDisabled(string.format(
        'Pending NPCs: %d  Pending Responses: %d  |  Accepted NPCs: %d  Accepted Responses: %d',
        record_count(pending_records), response_count(pending_records),
        record_count(accepted_records), response_count(accepted_records)
    ))
    ImGui.TextDisabled('Output Dir: ' .. BASE_DIR)
    ImGui.TextDisabled('Master File: ' .. MASTER_FILE)
    ImGui.Separator()

    if ImGui.BeginTabBar('##npc_dialog_tabs') then
        if ImGui.BeginTabItem('Live Feed') then
            local nv, changed = ImGui.Checkbox('Auto-scroll', auto_scroll)
            if changed then auto_scroll = nv end
            ImGui.SameLine()
            ImGui.SetNextItemWidth(260)
            local fsv, fsc = ImGui.InputText('Feed Search##feed_search', dbstr_builder.live_feed_search or '')
            if fsc then dbstr_builder.live_feed_search = fsv end
            ImGui.SameLine()
            local npc_set, npc_list = {}, { 'All' }
            for _, e in ipairs(feed) do
                local n = feed_npc_name(e.msg)
                if n and not npc_set[n] then npc_set[n] = true; npc_list[#npc_list + 1] = n end
            end
            local next_npc = 'All'
            for i, n in ipairs(npc_list) do
                if n == (dbstr_builder.active_npc_filter or 'All') then
                    next_npc = npc_list[(i % #npc_list) + 1]
                    break
                end
            end
            if ImGui.Button('NPC Filter: ' .. (dbstr_builder.active_npc_filter or 'All')) then
                dbstr_builder.active_npc_filter = next_npc
                save_dbstr_builder_settings()
            end
            ImGui.Separator()
            ImGui.BeginChild('##feed', 0, 0, true, ImGuiWindowFlags.HorizontalScrollbar)
            for _, entry in ipairs(feed) do
                local passes_npc = true
                if (dbstr_builder.active_npc_filter or 'All') ~= 'All' then
                    passes_npc = normalize_key(feed_npc_name(entry.msg) or '') == normalize_key(dbstr_builder.active_npc_filter or '')
                end
                if passes_npc and builder_row_matches_search(dbstr_builder.live_feed_search, entry.kind, '', entry.msg, '', '', '') then
                    ImGui.TextDisabled('[' .. entry.t .. ']')
                    ImGui.SameLine()
                    local rr, gg, bb = entry.r, entry.g, entry.b
                    if entry.dup then rr, gg, bb = 0.95, 0.45, 0.45 end
                    ImGui.TextColored(rr, gg, bb, 1.0, entry.msg)
                    if entry.tag and entry.tag ~= '' then
                        ImGui.SameLine()
                        ImGui.TextColored(0.45, 0.90, 1.00, 1.0, '[' .. entry.tag .. ']')
                    end
                    if ENABLE_FEED_LINK_BUTTONS then
                        local spell_id = find_spell_problem_id_by_text(entry.msg or '')
                        if spell_id then
                            ImGui.SameLine()
                            if ImGui.SmallButton('Link to Spell##' .. tostring(entry.key)) then
                                dbstr_builder.open = true
                                dbstr_builder.table_search = 'id:' .. tostring(spell_id)
                                dbstr_builder.spell_panel_id = spell_id
                                dbstr_builder.show_spell_panel = true
                            end
                        end
                    end
                    if ImGui.BeginPopupContextItem('feed_tag_popup##' .. tostring(entry.key)) then
                        if ImGui.MenuItem('Tag talent') then dbstr_builder.line_tags[entry.key] = 'talent'; save_dbstr_builder_settings() end
                        if ImGui.MenuItem('Tag flavor') then dbstr_builder.line_tags[entry.key] = 'flavor'; save_dbstr_builder_settings() end
                        if ImGui.MenuItem('Tag warning') then dbstr_builder.line_tags[entry.key] = 'warning'; save_dbstr_builder_settings() end
                        if ImGui.MenuItem('Tag lore') then dbstr_builder.line_tags[entry.key] = 'lore'; save_dbstr_builder_settings() end
                        if ImGui.MenuItem('Clear tag') then dbstr_builder.line_tags[entry.key] = nil; save_dbstr_builder_settings() end
                        ImGui.EndPopup()
                    end
                end
            end
            if auto_scroll and feed_dirty then
                ImGui.SetScrollHereY(1.0)
                feed_dirty = false
            end
            ImGui.EndChild()
            ImGui.EndTabItem()
        end

        if ImGui.BeginTabItem('Pending Review') then
            ImGui.SetNextItemWidth(260)
            local psv, psc = ImGui.InputText('Pending Search##pending_search', dbstr_builder.pending_search or '')
            if psc then dbstr_builder.pending_search = psv end
            local tflags = ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg + ImGuiTableFlags.ScrollY + ImGuiTableFlags.Resizable
            if ImGui.BeginTable('##pending_tbl', 5, tflags, 0, 0) then
                ImGui.TableSetupScrollFreeze(0, 1)
                ImGui.TableSetupColumn('NPC', ImGuiTableColumnFlags.WidthStretch, 0.28)
                ImGui.TableSetupColumn('Zone', ImGuiTableColumnFlags.WidthFixed, 120)
                ImGui.TableSetupColumn('Responses', ImGuiTableColumnFlags.WidthFixed, 85)
                ImGui.TableSetupColumn('Last Seen', ImGuiTableColumnFlags.WidthFixed, 170)
                ImGui.TableSetupColumn('Preview', ImGuiTableColumnFlags.WidthStretch, 0.48)
                ImGui.TableHeadersRow()

                for _, rec in pairs(pending_records) do
                    local rc = 0
                    for _ in pairs(rec.responses or {}) do rc = rc + 1 end
                    local preview = ''
                    if rec.ordered_lines and rec.ordered_lines[1] and rec.ordered_lines[1].text then
                        preview = clean_export_text(rec.ordered_lines[1].text)
                    end
                    if #preview > 60 then
                        preview = preview:sub(1, 57) .. '...'
                    end
                    if builder_row_matches_search(dbstr_builder.pending_search, 'pending', '', rec.npc_name, rec.zone_short, preview, tostring(rc)) then
                        ImGui.TableNextRow()
                        ImGui.TableSetColumnIndex(0)
                        ImGui.TextColored(0.95, 0.85, 0.10, 1.0, rec.npc_name or '?')
                        ImGui.TableSetColumnIndex(1)
                        ImGui.TextDisabled(rec.zone_short or '')
                        ImGui.TableSetColumnIndex(2)
                        ImGui.Text(tostring(rc))
                        ImGui.TableSetColumnIndex(3)
                        ImGui.TextDisabled(rec.last_seen_at or '')
                        ImGui.TableSetColumnIndex(4)
                        ImGui.TextDisabled(preview)
                    end
                end
                ImGui.EndTable()
            end
            ImGui.EndTabItem()
        end

        if ImGui.BeginTabItem('Accepted') then
            ImGui.SetNextItemWidth(260)
            local asv, asc = ImGui.InputText('Accepted Search##accepted_search', dbstr_builder.accepted_search or '')
            if asc then dbstr_builder.accepted_search = asv end
            ImGui.SameLine()
            if ImGui.Button('Export Accepted CSV') then
                ensure_dir(BASE_DIR)
                local csv_path = BASE_DIR .. '/accepted_export_' .. os.date('%Y%m%d_%H%M%S') .. '.csv'
                local cf = io.open(csv_path, 'w')
                if cf then
                    cf:write('npc,zone,responses,first_seen\n')
                    for _, rec in pairs(accepted_records) do
                        local rc = 0
                        for _ in pairs(rec.responses or {}) do rc = rc + 1 end
                        cf:write(('%q,%q,%d,%q\n'):format(rec.npc_name or '', rec.zone_short or '', rc, rec.first_seen_at or ''))
                    end
                    cf:close()
                    push_feed('export', 'Accepted CSV: ' .. csv_path, 0.10, 1.00, 0.50)
                end
            end
            local tflags = ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg + ImGuiTableFlags.ScrollY + ImGuiTableFlags.Resizable
            if ImGui.BeginTable('##accepted_tbl', 4, tflags, 0, 0) then
                ImGui.TableSetupScrollFreeze(0, 1)
                ImGui.TableSetupColumn('NPC', ImGuiTableColumnFlags.WidthStretch, 0.34)
                ImGui.TableSetupColumn('Zone', ImGuiTableColumnFlags.WidthFixed, 120)
                ImGui.TableSetupColumn('Responses', ImGuiTableColumnFlags.WidthFixed, 85)
                ImGui.TableSetupColumn('First Seen', ImGuiTableColumnFlags.WidthFixed, 170)
                ImGui.TableHeadersRow()

                for _, rec in pairs(accepted_records) do
                    local rc = 0
                    for _ in pairs(rec.responses or {}) do rc = rc + 1 end
                    if builder_row_matches_search(dbstr_builder.accepted_search, 'accepted', '', rec.npc_name, rec.zone_short, rec.first_seen_at, tostring(rc)) then
                        ImGui.TableNextRow()
                        ImGui.TableSetColumnIndex(0)
                        ImGui.TextColored(0.10, 0.95, 0.80, 1.0, rec.npc_name or '?')
                        ImGui.TableSetColumnIndex(1)
                        ImGui.TextDisabled(rec.zone_short or '')
                        ImGui.TableSetColumnIndex(2)
                        ImGui.Text(tostring(rc))
                        ImGui.TableSetColumnIndex(3)
                        ImGui.TextDisabled(rec.first_seen_at or '')
                    end
                end
                ImGui.EndTable()
            end
            ImGui.EndTabItem()
        end
        ImGui.EndTabBar()
    end

    ImGui.Separator()
    ImGui.TextDisabled(('Status | Last Scan: %s | Last Write: %s | Unsaved: %s'):format(
        dbstr_builder.last_scan_at ~= '' and dbstr_builder.last_scan_at or 'never',
        dbstr_builder.last_write_at ~= '' and dbstr_builder.last_write_at or 'never',
        dbstr_builder.unsaved_changes and 'yes' or 'no'
    ))
    ImGui.SameLine()
    ImGui.TextDisabled(('dbstr: %s'):format(dbstr_builder.dbstr_path or ''))

    ImGui.End()
    pop_theme(pv, pc)
end

local function cmd_handler(line)
    local sub = trim(line):lower()
    if sub == '' or sub == 'toggle' then
        ui_open = not ui_open
        return
    end
    if sub == 'show' then ui_open = true; return end
    if sub == 'hide' then ui_open = false; return end
    if sub == 'start' then logging_enabled = true; return end
    if sub == 'stop' then logging_enabled = false; return end
    if sub == 'accept' then accept_pending(); return end
    if sub == 'reject' then reject_pending(); return end
    if sub == 'save' then save_accepted(); return end
    if sub == 'dbstr scan' then scan_dbstr_problems(); dbstr_builder.open = true; return end
    if sub == 'dbstr scanall' then scan_dbstr_problems(false); dbstr_builder.open = true; return end
    if sub == 'dbstr scanrelevant' then scan_dbstr_problems(true); dbstr_builder.open = true; return end
    if sub == 'dbstr importmd' then import_markdown_hints(); dbstr_builder.open = true; return end
    if sub == 'dbstr propose' then propose_fixes_from_dialog(); dbstr_builder.open = true; return end
    if sub == 'dbstr write' then write_patched_files(); dbstr_builder.open = true; return end
    if sub == 'quit' or sub == 'exit' then loop_active = false; return end
    printf('[NDC] %s toggle|show|hide|start|stop|accept|reject|save|dbstr scan|dbstr scanall|dbstr scanrelevant|dbstr importmd|dbstr propose|dbstr write|quit', CMD_NAME)
end

mq.bind(CMD_NAME, cmd_handler)
mq.event(EVENT_NAME, '#*#', function(msg) on_chat(msg) end, { keepLinks = true })
mq.imgui.init('NPCDialogConsole', draw_console)
mq.imgui.init('DBStrSpellsBuilder', draw_dbstr_builder)

printf('[NDC] Loaded. %s to show/hide, %s start to begin logging.', CMD_NAME, CMD_NAME)

while loop_active do
    mq.doevents()
    capture_popup_windows()
    mq.delay(50)
end
