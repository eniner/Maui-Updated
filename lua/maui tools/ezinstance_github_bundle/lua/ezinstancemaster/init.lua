--[[
    EZ Instance Master
--]]

local version          = "3.0"
local APP_NAME         = "EZ Instance Master"
local APP_ACTOR        = "EZInstanceMaster"
local mq               = require('mq')

EZIMActors             = require 'actors'
Icons                  = require('mq.ICONS')
ezimSettings             = require('ezimSettings').new()
EZIMEditPopup            = require('ezimEditButtonPopup')

local ezimHotbarClass    = require('ezimHotbarClass')
local btnUtils         = require('lib.buttonUtils')
local ezimButtonHandlers = require('ezimButtonHandlers')

-- globals
EZIMHotbars              = {}
EZIMReloadSettings       = false
EZIMUpdateSettings       = false

-- [[ UI ]] --
local openGUI          = true

local EZ_INSTANCE_PROFILE_VERSION = 6
local EZ_INSTANCE_META_KEY = "EZInstanceMasterProfile"

local EZ_FONT_PACKS = {
    awesome = { Font = 12, ButtonSize = 7, Theme = "SpawnWatchNeon", Width = 760, Height = 260, },
    readable = { Font = 11, ButtonSize = 7, Theme = "SpawnWatchNeon", Width = 730, Height = 250, },
    compact = { Font = 10, ButtonSize = 6, Theme = "SpawnWatchNeon", Width = 680, Height = 235, },
}

local EZ_INSTANCE_BUTTONS = {
    { id = "ctrl_create_solo_here", label = "Create-Solo", cmd = "/eziminstances create solo here", },
    { id = "ctrl_create_raid_here", label = "Create-Raid", cmd = "/eziminstances create raid here", },
    { id = "ctrl_create_guild_here", label = "Create-Guild", cmd = "/eziminstances create guild here", },
    { id = "ctrl_quick_solo_here", label = "Quick-Solo", cmd = "/eziminstances quick solo here", },
    { id = "ctrl_quick_raid_here", label = "Quick-Raid", cmd = "/eziminstances quick raid here", },
    { id = "ctrl_quick_guild_here", label = "Quick-Guild", cmd = "/eziminstances quick guild here", },
    { id = "ctrl_invite_auto_raid", label = "InviteAuto-Raid", cmd = "/eziminstances inviteauto raid here", },
    { id = "ctrl_invite_auto_solo", label = "InviteAuto-Solo", cmd = "/eziminstances inviteauto solo here", },
    { id = "ctrl_invite_auto_guild", label = "InviteAuto-Guild", cmd = "/eziminstances inviteauto guild here", },
    { id = "ctrl_scan_online", label = "Scan-Online", cmd = "/eziminstances scanonline", },
    { id = "ctrl_invite_group_online", label = "InviteGroup-Online", cmd = "/eziminstances invitegroup", },
    { id = "ctrl_invite_raid_online", label = "InviteRaid-Online", cmd = "/eziminstances inviteraid", },
    { id = "ctrl_autoaccept_setup", label = "AutoAccept-Setup", cmd = "/eziminstances autoacceptsetup me", },
    { id = "ctrl_enter_my_raid", label = "EnterMy-Raid", cmd = "/eziminstances enter raid me here", },
    { id = "ctrl_enter_my_guild", label = "EnterMy-Guild", cmd = "/eziminstances enter guild me here", },
    { id = "ctrl_enter_my_solo", label = "EnterMy-Solo", cmd = "/eziminstances enter solo me here", },
    { id = "ctrl_enter_all_raid", label = "EnterAll-Raid", cmd = "/eziminstances enterall raid me here", },
    { id = "ctrl_enter_all_guild", label = "EnterAll-Guild", cmd = "/eziminstances enterall guild me here", },
    { id = "ctrl_enter_all_solo", label = "EnterAll-Solo", cmd = "/eziminstances enterall solo me here", },
    { id = "ctrl_repop", label = "Repop-Instance", cmd = "/eziminstances repop", },
    { id = "ctrl_list", label = "List-Instances", cmd = "/say instance list", },
    { id = "ctrl_list_guild", label = "List-Guild", cmd = "/say instance list guild", },
    { id = "ctrl_delete_all", label = "Delete-All", cmd = "/say instance delete allinstances", },
    { id = "ctrl_create_double", label = "Create-Double", cmd = "/say create double instance", },
    { id = "ctrl_create_triple", label = "Create-Triple", cmd = "/say create triple instance", },
    { id = "ctrl_help", label = "Instance-Help", cmd = "/eziminstances help", },
}

local EZ_INSTANCE_ZONE_BUTTONS = {
    {
        set = "EZIM - Hubs+T70",
        rows = {
            { id = "zone_qrg", zone = "qrg", short = "QRG", },
            { id = "zone_stonehive", zone = "stonehive", short = "STONE", },
            { id = "zone_potime", zone = "potimeb", short = "POTIME", },
            { id = "zone_ldon", zone = "ldon", short = "LDON", },
            { id = "zone_misty", zone = "misty", short = "MISTY", },
            { id = "zone_hushed", zone = "hushed", short = "HUSHED", },
        },
    },
    {
        set = "EZIM - T1 to T4",
        rows = {
            { id = "zone_qvic", zone = "qvic", short = "QVIC", },
            { id = "zone_cazic", zone = "cazicthule", short = "CAZIC", },
            { id = "zone_arthicrex", zone = "arthicrex", short = "ARTHIC", },
            { id = "zone_pod", zone = "podragons", short = "POD", },
            { id = "zone_hoh", zone = "hohonora", short = "HOH", },
            { id = "zone_airplane", zone = "poair", short = "POAIR", },
        },
    },
    {
        set = "EZIM - T5 to T8",
        rows = {
            { id = "illsalin", zone = "illsalin", short = "illsalin", },
            { id = "zone_anguish", zone = "anguish", short = "ANGUISH", },
            { id = "zone_loping", zone = "lopingplains", short = "LOPING", },
            { id = "zone_tov", zone = "templeveeshan", short = "TOV", },
            { id = "zone_blackburrow", zone = "oldblackburrow", short = "OBB", },
            { id = "zone_bloodmoon", zone = "bloodmoon", short = "BMOON", },
        },
    },
    {
        set = "EZIM - T9 to T12+",
        rows = {
            { id = "zone_oldcommons", zone = "oldcommons", short = "OC", },
            { id = "zone_sunderock", zone = "sunderock", short = "SUNDR", },
            { id = "zone_sleepers", zone = "sleeper", short = "SLEEP", },
            { id = "zone_veeshans", zone = "veeshan", short = "VEESH", },
            { id = "zone_kael", zone = "kael", short = "KAEL", },
            { id = "zone_blightfire", zone = "blightfire", short = "BLGHT", },
            { id = "zone_direwind", zone = "direwind", short = "DIRE", },
            { id = "zone_dranik", zone = "dranikcatacombs", short = "DRNK", },
            { id = "zone_convorteum", zone = "convorteum", short = "CNVR", },
        },
    },
}

local EZ_INSTANCE_MODES = {
    { key = "solo", short = "S", },
    { key = "raid", short = "R", },
    { key = "guild", short = "G", },
}

local function is_ez_set_name(name)
    return type(name) == "string" and name:find("^EZIM %-") ~= nil
end

local function window_has_ez_sets(windowData)
    for _, setName in ipairs((windowData and windowData.Sets) or {}) do
        if is_ez_set_name(setName) then
            return true
        end
    end
    return false
end

local function remove_non_ezim_windows()
    local settings = ezimSettings:GetSettings()
    local charConfig = ezimSettings:GetCharConfig()
    if not settings or not charConfig then
        return false, 0
    end

    settings[EZ_INSTANCE_META_KEY] = settings[EZ_INSTANCE_META_KEY] or {}
    local meta = settings[EZ_INSTANCE_META_KEY]
    local targetWindowId = tonumber(meta.WindowId or 0) or 0

    local windows = charConfig.Windows or {}
    if #windows == 0 then
        return false, 0
    end

    local kept = {}
    local newTargetWindowId = nil
    for oldWindowId, windowData in ipairs(windows) do
        local shouldKeep = (oldWindowId == targetWindowId) or window_has_ez_sets(windowData)
        if shouldKeep then
            kept[#kept + 1] = windowData
            if oldWindowId == targetWindowId then
                newTargetWindowId = #kept
            end
        end
    end

    local removedCount = #windows - #kept
    if removedCount <= 0 then
        return false, 0
    end

    charConfig.Windows = kept
    if newTargetWindowId then
        meta.WindowId = newTargetWindowId
        settings[EZ_INSTANCE_META_KEY] = meta
    end

    return true, removedCount
end

local function trim(s)
    return tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function tolower(s)
    return trim(s):lower()
end

local EZ_ZONE_ALIASES = {
    ["planeoftime"] = "potimeb",
    ["potime"] = "potimeb",
    ["mistythicket"] = "misty",
    ["hushedbanquet"] = "hushed",
    ["hallsofhonor"] = "hohonora",
    ["airplane"] = "poair",
    ["bloodmoontemple"] = "bloodmoon",
    ["sunderocksprings"] = "sunderock",
    ["sleeperstomb"] = "sleeper",
    ["veeshanspeak"] = "veeshan",
    ["kaeldrakkel"] = "kael",
}

local function get_zone_or_default(zone)
    local z = trim(zone)
    if z == "" or z:lower() == "here" then
        z = tostring(mq.TLO.Zone.ShortName() or "")
    end
    local key = z:lower():gsub("[%s%p_%-]", "")
    z = EZ_ZONE_ALIASES[key] or z
    return z
end

local function get_me_name()
    return tostring(mq.TLO.Me.CleanName() or mq.TLO.Me.Name() or "")
end

local function cmd_say(msg)
    mq.cmd("/say " .. msg)
    btnUtils.Output("\\agEZ Instance Master\\aw: /say %s", msg)
end

local function collect_group_members()
    local names, seen = {}, {}
    local me = get_me_name()
    if me ~= "" then
        seen[me:lower()] = true
        table.insert(names, me)
    end

    for i = 1, 6 do
        local n = tostring(mq.TLO.Group.Member(i).Name() or "")
        n = trim(n)
        local key = n:lower()
        if n ~= "" and not seen[key] then
            seen[key] = true
            table.insert(names, n)
        end
    end
    return names
end

local function collect_raid_members()
    local names, seen = {}, {}
    local count = tonumber(mq.TLO.Raid.Members() or 0) or 0
    if count <= 0 then
        return names
    end

    for i = 1, count do
        local n = tostring(mq.TLO.Raid.Member(i).Name() or "")
        n = trim(n)
        local key = n:lower()
        if n ~= "" and not seen[key] then
            seen[key] = true
            table.insert(names, n)
        end
    end
    return names
end

local function invite_member_batch(mode, zone, names)
    if #names == 0 then
        return
    end

    for _, n in ipairs(names) do
        cmd_say(string.format("%s invite %s %s", mode, zone, n))
        mq.delay(40)
    end
end

local get_cached_or_scan_peers

local function invite_auto(mode, zone)
    local raid_members = collect_raid_members()
    local members = #raid_members > 0 and raid_members or collect_group_members()
    local seen = {}
    local merged = {}

    for _, n in ipairs(members) do
        local key = trim(n):lower()
        if key ~= "" and not seen[key] then
            seen[key] = true
            merged[#merged + 1] = n
        end
    end

    local relay, peers = get_cached_or_scan_peers()
    if relay ~= "none" then
        for _, n in ipairs(peers or {}) do
            local key = trim(n):lower()
            if key ~= "" and not seen[key] then
                seen[key] = true
                merged[#merged + 1] = n
            end
        end
    end

    members = merged
    invite_member_batch(mode, zone, members)
    if relay ~= "none" and #peers > 0 then
        return #members, (#raid_members > 0 and "raid+online" or "group+online")
    end
    return #members, (#raid_members > 0 and "raid" or "group")
end

local function plugin_loaded(name)
    return tostring(mq.TLO.Plugin(name).IsLoaded() or "false") == "true"
end

local ONLINE_PEERS_CACHE = {
    method = "none",
    names = {},
    targets = {},
    at = 0,
}

local function title_case(s)
    s = trim(s)
    if s == "" then return s end
    return s:sub(1, 1):upper() .. s:sub(2):lower()
end

local function extract_character_name(peerName)
    local s = trim(peerName)
    if s == "" then return "" end
    if s:find("_") then
        local parts = {}
        for part in s:gmatch("[^_]+") do
            parts[#parts + 1] = part
        end
        s = parts[#parts] or s
    end
    s = s:gsub("%s*[%`’']s [Cc]orpse%d*$", "")
    return title_case(s)
end

local function list_connected_peers()
    local myName = extract_character_name(get_me_name())
    local method = "none"
    local entries, seen = {}, {}

    if plugin_loaded("MQ2DanNet") then
        method = "DanNet"
        local peersStr = tostring(mq.TLO.DanNet.Peers() or "")
        for raw in peersStr:gmatch("([^|]+)") do
            local rawPeer = trim(raw)
            local name = extract_character_name(rawPeer)
            local key = name:lower()
            if name ~= "" and key ~= myName:lower() and not seen[key] then
                seen[key] = true
                entries[#entries + 1] = { name = name, target = rawPeer, }
            end
        end
    elseif plugin_loaded("MQ2EQBC") and tostring(mq.TLO.EQBC.Connected() or "false") == "true" then
        method = "EQBC"
        local namesStr = tostring(mq.TLO.EQBC.Names() or "")
        for raw in namesStr:gmatch("([^%s]+)") do
            local name = extract_character_name(raw)
            local key = name:lower()
            if name ~= "" and key ~= myName:lower() and not seen[key] then
                seen[key] = true
                entries[#entries + 1] = { name = name, target = name, }
            end
        end
    end

    table.sort(entries, function(a, b) return a.name < b.name end)
    local names, targets = {}, {}
    for _, e in ipairs(entries) do
        names[#names + 1] = e.name
        targets[#targets + 1] = e.target
    end
    table.sort(names)
    ONLINE_PEERS_CACHE.method = method
    ONLINE_PEERS_CACHE.names = names
    ONLINE_PEERS_CACHE.targets = targets
    ONLINE_PEERS_CACHE.at = os.time()
    return method, names, targets
end

get_cached_or_scan_peers = function()
    if #ONLINE_PEERS_CACHE.names == 0 then
        return list_connected_peers()
    end
    return ONLINE_PEERS_CACHE.method, ONLINE_PEERS_CACHE.names, ONLINE_PEERS_CACHE.targets
end

local function invite_online_peers(inviteType)
    local method, peers = get_cached_or_scan_peers()
    if #peers == 0 then
        return 0, method
    end
    for _, name in ipairs(peers) do
        if inviteType == "raid" then
            mq.cmdf("/raidinvite %s", name)
        else
            mq.cmdf("/invite %s", name)
        end
        mq.delay(60)
    end
    return #peers, method
end

local function autoaccept_apply_local(inviter)
    mq.cmd("/autoaccept on")
    mq.cmd("/autoaccept group on")
    mq.cmd("/autoaccept raid on")
    mq.cmdf("/autoaccept add %s", inviter)
    mq.cmd("/autoaccept save")
end

local function autoaccept_apply_remote(inviter)
    local method, peers, targets = get_cached_or_scan_peers()
    if method == "none" or #peers == 0 then
        return "local"
    end

    if method == "DanNet" then
        -- Use group execute to avoid stale per-peer target names.
        mq.cmd("/dgaexecute all /autoaccept on")
        mq.delay(20)
        mq.cmd("/dgaexecute all /autoaccept group on")
        mq.delay(20)
        mq.cmd("/dgaexecute all /autoaccept raid on")
        mq.delay(20)
        mq.cmdf("/dgaexecute all /autoaccept add %s", inviter)
        mq.delay(20)
        mq.cmd("/dgaexecute all /autoaccept save")
        return "DanNet(all)"
    end

    for i, _ in ipairs(peers) do
        local target = targets[i] or peers[i]
        mq.cmdf("/bct %s //autoaccept on", target)
        mq.delay(20)
        mq.cmdf("/bct %s //autoaccept group on", target)
        mq.delay(20)
        mq.cmdf("/bct %s //autoaccept raid on", target)
        mq.delay(20)
        mq.cmdf("/bct %s //autoaccept add %s", target, inviter)
        mq.delay(20)
        mq.cmdf("/bct %s //autoaccept save", target)
        mq.delay(20)
    end
    return method
end

local function remote_enter_character(name, mode, owner, zone)
    local me = get_me_name()
    if trim(name) == "" then return false, "empty" end
    if trim(name):lower() == me:lower() then
        cmd_say(string.format("enter %s %s %s", mode, owner, zone))
        return true, "local"
    end

    if plugin_loaded("MQ2EQBC") then
        mq.cmdf("/bct %s //say enter %s %s %s", name, mode, owner, zone)
        return true, "eqbc"
    end

    if plugin_loaded("MQ2DanNet") then
        mq.cmdf("/dexecute %s /say enter %s %s %s", name, mode, owner, zone)
        return true, "dannet"
    end

    return false, "none"
end

local function enter_auto(mode, owner, zone)
    local raid_members = collect_raid_members()
    local members = #raid_members > 0 and raid_members or collect_group_members()

    if plugin_loaded("MQ2DanNet") then
        mq.cmdf("/dgaexecute all /say enter %s %s %s", mode, owner, zone)
        return #members, (#raid_members > 0 and "raid" or "group"), "dannet(all)"
    end

    if plugin_loaded("MQ2EQBC") then
        mq.cmdf("/bcga //say enter %s %s %s", mode, owner, zone)
        return #members, (#raid_members > 0 and "raid" or "group"), "eqbc(all)"
    end

    local sent = 0
    local remoteMode = "local"
    for _, n in ipairs(members) do
        local ok, via = remote_enter_character(n, mode, owner, zone)
        if ok then
            sent = sent + 1
            if via ~= "local" then
                remoteMode = via
            end
            mq.delay(30)
        end
    end
    return sent, (#raid_members > 0 and "raid" or "group"), remoteMode
end

local function set_contains(tbl, value)
    for _, v in ipairs(tbl or {}) do
        if v == value then return true end
    end
    return false
end

local function upsert_ez_button(meta, id, label, cmd)
    meta.ButtonKeys = meta.ButtonKeys or {}
    local key = meta.ButtonKeys[id]
    if not key or not ezimSettings:GetSettings().Buttons[key] then
        key = ezimSettings:GenerateButtonKey()
        meta.ButtonKeys[id] = key
    end

    ezimSettings:GetSettings().Buttons[key] = {
        Label = label,
        Cmd = cmd,
    }
    return key
end

local function upsert_ez_header_button(meta, id, label)
    meta.ButtonKeys = meta.ButtonKeys or {}
    local key = meta.ButtonKeys[id]
    if not key or not ezimSettings:GetSettings().Buttons[key] then
        key = ezimSettings:GenerateButtonKey()
        meta.ButtonKeys[id] = key
    end

    ezimSettings:GetSettings().Buttons[key] = {
        Label = label,
        Cmd = "",
        SectionHeader = true,
        ShowLabel = true,
    }
    return key
end

local function ensure_instance_window(meta, pack)
    local windows = ezimSettings:GetCharConfig().Windows or {}
    local windowId = tonumber(meta.WindowId or 0) or 0
    if windowId <= 0 or not windows[windowId] then
        windowId = #windows + 1
        windows[windowId] = {
            Visible = true,
            Pos = { x = 40, y = 120, },
            Width = pack.Width,
            Height = pack.Height,
            Sets = {},
            Locked = false,
            HideTitleBar = false,
            CompactMode = false,
            AdvTooltips = true,
            ShowSearch = true,
            Theme = pack.Theme,
            Font = pack.Font,
            ButtonSize = pack.ButtonSize,
            HideScrollbar = false,
            FPS = 10,
        }
        ezimSettings:GetCharConfig().Windows = windows
    else
        local win = windows[windowId]
        win.Theme = pack.Theme
        win.Font = pack.Font
        win.ButtonSize = pack.ButtonSize
        win.Width = pack.Width
        win.Height = pack.Height
        win.Pos = win.Pos or { x = 40, y = 120, }
        win.Sets = win.Sets or {}
    end
    meta.WindowId = windowId
    return windowId
end

local function EnsureEZInstanceProfile(force)
    local settings = ezimSettings:GetSettings()
    settings.Sets = settings.Sets or {}
    settings.Buttons = settings.Buttons or {}
    settings[EZ_INSTANCE_META_KEY] = settings[EZ_INSTANCE_META_KEY] or {}
    local meta = settings[EZ_INSTANCE_META_KEY]
    meta.FontPack = meta.FontPack or "awesome"
    local pack = EZ_FONT_PACKS[meta.FontPack] or EZ_FONT_PACKS.awesome

    if not force and (meta.Version or 0) >= EZ_INSTANCE_PROFILE_VERSION and meta.WindowId and meta.ButtonKeys then
        return false, string.format("EZ Instance Master profile already installed (v%d).", meta.Version or 0)
    end

    local windowId = ensure_instance_window(meta, pack)
    local setOrder = {}
    local controlSet = "EZIM - Control"
    local controlKeys = {}
    for _, b in ipairs(EZ_INSTANCE_BUTTONS) do
        controlKeys[#controlKeys + 1] = upsert_ez_button(meta, b.id, b.label, b.cmd)
    end
    settings.Sets[controlSet] = controlKeys
    setOrder[#setOrder + 1] = controlSet

    for _, setDef in ipairs(EZ_INSTANCE_ZONE_BUTTONS) do
        local keys = {}
        for _, mode in ipairs(EZ_INSTANCE_MODES) do
            local modeName = mode.key:upper()
            local setSlug = setDef.set:gsub("%W", "_")
            local createHeaderId = string.format("hdr_%s_%s_create", setSlug, mode.key)
            keys[#keys + 1] = upsert_ez_header_button(meta, createHeaderId, "[" .. modeName .. " CREATE]")
            for _, row in ipairs(setDef.rows) do
                local zoneLabel = tostring(row.short or row.zone):upper()
                local createCmd = string.format("/eziminstances quick %s %s", mode.key, row.zone)
                local createId = string.format("%s_%s_create", row.id, mode.key)
                keys[#keys + 1] = upsert_ez_button(meta, createId, zoneLabel, createCmd)
            end
            local enterHeaderId = string.format("hdr_%s_%s_enter", setSlug, mode.key)
            keys[#keys + 1] = upsert_ez_header_button(meta, enterHeaderId, "[" .. modeName .. " ENTER]")
            for _, row in ipairs(setDef.rows) do
                local zoneLabel = tostring(row.short or row.zone):upper()
                local enterCmd = string.format("/eziminstances enterall %s me %s", mode.key, row.zone)
                local enterId = string.format("%s_%s_enter", row.id, mode.key)
                keys[#keys + 1] = upsert_ez_button(meta, enterId, zoneLabel, enterCmd)
            end
        end
        settings.Sets[setDef.set] = keys
        setOrder[#setOrder + 1] = setDef.set
    end

    local win = ezimSettings:GetCharacterWindow(windowId)
    local cleaned = {}
    for _, setName in ipairs(win.Sets or {}) do
        if not is_ez_set_name(setName) then
            cleaned[#cleaned + 1] = setName
        end
    end
    win.Sets = cleaned
    for _, setName in ipairs(setOrder) do
        if not set_contains(win.Sets, setName) then
            table.insert(win.Sets, setName)
        end
    end

    meta.Version = EZ_INSTANCE_PROFILE_VERSION
    settings[EZ_INSTANCE_META_KEY] = meta
    ezimSettings:SaveSettings(true)
    return true, string.format("Installed EZ Instance Master profile on window %d with %d sets.", windowId, #setOrder)
end

local function SetEZFontPack(name)
    local key = tolower(name)
    local pack = EZ_FONT_PACKS[key]
    if not pack then
        return false, "Unknown font pack. Use: awesome, readable, compact."
    end

    local settings = ezimSettings:GetSettings()
    settings[EZ_INSTANCE_META_KEY] = settings[EZ_INSTANCE_META_KEY] or {}
    local meta = settings[EZ_INSTANCE_META_KEY]
    meta.FontPack = key
    settings[EZ_INSTANCE_META_KEY] = meta
    local changed, _ = EnsureEZInstanceProfile(true)
    return true, changed and ("Applied font pack: " .. key) or ("Font pack stored: " .. key)
end

-- binds
local function BindBtn(num)
    if not num then num = 1 else num = (tonumber(num) or 1) end
    if EZIMHotbars[num] then
        EZIMHotbars[num]:ToggleVisible()
    end
end

function CopyLocalSet(key)
    local newTable = btnUtils.deepcopy(ezimSettings:GetSettings().Characters[key])
    ezimSettings:GetSettings().Characters[ezimSettings.CharConfig] = newTable
    ezimSettings:SaveSettings(true)
    EZIMUpdateSettings = true
end

local function BindBtnCopy(server, character)
    if not server or not character then return end

    local cname = character:sub(1, 1):upper() .. character:sub(2)
    local key = server .. "_" .. cname
    if not ezimSettings:GetSettings().Characters[key] then
        btnUtils.Output("\arError: \ayProfile: \at%s\ay not found!", key)
        return
    end

    CopyLocalSet(key)
end

local function BindBtnExec(set, index)
    if not set or not index then
        btnUtils.Output("\agUsage\aw: \am/ezimexec \aw<\at\"set\"\aw> \aw<\atindex\aw>")
        return
    end

    index = tonumber(index) or 0
    local Button = ezimSettings:GetButtonBySetIndex(set, index)

    if Button.Unassigned then
        btnUtils.Output("\arError\aw: \amSet: \at'%s' \amButtonIndex: \at%d \awIs Not Assigned!", set, index)
        for s, data in pairs(ezimSettings:GetSettings().Sets) do
            btnUtils.Output("\awSet: \at%s", s)
            for i, b in ipairs(data) do
                btnUtils.Output("\t \aw[\at%d\aw] \am%s", i, b)
            end
        end
        return
    end

    btnUtils.Output("\agRunning\aw: \amSet: \at%s \amButtonIndex: \at%d \aw:: \at%s", set, index, Button.Label)
    ezimButtonHandlers.Exec(Button)
end

local function BindBtnInstances(...)
    local args = { ... }
    local action = tolower(args[1] or "install")

    if action == "help" then
        btnUtils.Output("\\ag/eziminstances\\aw commands:")
        btnUtils.Output("  /eziminstances install")
        btnUtils.Output("  /eziminstances font [awesome|readable|compact]")
        btnUtils.Output("  /eziminstances create [solo|guild|raid] [zone|here]")
        btnUtils.Output("  /eziminstances inviteauto [solo|guild|raid] [zone|here]")
        btnUtils.Output("  /eziminstances scanonline")
        btnUtils.Output("  /eziminstances invitegroup")
        btnUtils.Output("  /eziminstances inviteraid")
        btnUtils.Output("  /eziminstances autoacceptsetup [inviter|me]")
        btnUtils.Output("  /eziminstances quick [solo|guild|raid] [zone|here]")
        btnUtils.Output("  /eziminstances enter [solo|guild|raid] [owner|me] [zone|here]")
        btnUtils.Output("  /eziminstances enterall [solo|guild|raid] [owner|me] [zone|here]")
        btnUtils.Output("  /eziminstances repop")
        return
    end

    if action == "install" or action == "refresh" then
        local changed, msg = EnsureEZInstanceProfile(action == "refresh")
        btnUtils.Output("\\agEZ Instance Master\\aw: %s", msg)
        if changed then
            EZIMUpdateSettings = true
        end
        return
    end

    if action == "font" then
        local ok, msg = SetEZFontPack(args[2] or "awesome")
        btnUtils.Output("\\agEZ Instance Master\\aw: %s", msg)
        if ok then
            EZIMUpdateSettings = true
        end
        return
    end

    if action == "create" then
        local mode = tolower(args[2] or "raid")
        local raw = trim(args[3])
        if raw == "" or raw:lower() == "here" then
            cmd_say(string.format("create %s instance confirm", mode))
        else
            local zone = get_zone_or_default(raw)
            cmd_say(string.format("create %s instance %s confirm", mode, zone))
        end
        return
    end

    if action == "inviteauto" then
        local mode = tolower(args[2] or "raid")
        local zone = get_zone_or_default(args[3])
        local n, source = invite_auto(mode, zone)
        btnUtils.Output("\\agEZ Instance Master\\aw: invited %d players from %s to %s %s instance.", n, source, mode, zone)
        return
    end

    if action == "scanonline" then
        local method, peers = list_connected_peers()
        if #peers == 0 then
            if method == "none" then
                btnUtils.Output("\\ayEZ Instance Master\\aw: no peer relay loaded. Load MQ2DanNet or MQ2EQBC.")
            else
                btnUtils.Output("\\ayEZ Instance Master\\aw: no online peers detected via %s.", method)
            end
            return
        end
        btnUtils.Output("\\agEZ Instance Master\\aw: detected %d online peers via %s: %s",
            #peers, method, table.concat(peers, ", "))
        return
    end

    if action == "invitegroup" then
        local n, method = invite_online_peers("group")
        if n == 0 then
            btnUtils.Output("\\ayEZ Instance Master\\aw: no online peers to group invite (scan: /eziminstances scanonline).")
            return
        end
        btnUtils.Output("\\agEZ Instance Master\\aw: sent group invites to %d peers via %s list.", n, method)
        return
    end

    if action == "inviteraid" then
        local n, method = invite_online_peers("raid")
        if n == 0 then
            btnUtils.Output("\\ayEZ Instance Master\\aw: no online peers to raid invite (scan: /eziminstances scanonline).")
            return
        end
        btnUtils.Output("\\agEZ Instance Master\\aw: sent raid invites to %d peers via %s list.", n, method)
        return
    end

    if action == "autoacceptsetup" then
        local inviter = trim(args[2])
        if inviter == "" or inviter:lower() == "me" then inviter = get_me_name() end
        autoaccept_apply_local(inviter)
        local relay = autoaccept_apply_remote(inviter)
        btnUtils.Output("\\agEZ Instance Master\\aw: autoaccept configured for inviter \\at%s\\aw (relay: %s).", inviter, relay)
        return
    end

    if action == "quick" then
        local mode = tolower(args[2] or "raid")
        local raw = trim(args[3])
        local zone = get_zone_or_default(raw)
        if raw == "" or raw:lower() == "here" then
            cmd_say(string.format("create %s instance confirm", mode))
        else
            cmd_say(string.format("create %s instance %s confirm", mode, zone))
        end
        mq.delay(150)
        local n, source = invite_auto(mode, zone)
        btnUtils.Output("\\agEZ Instance Master\\aw: quick setup complete (%d invited from %s).", n, source)
        return
    end

    if action == "enter" then
        local mode = tolower(args[2] or "raid")
        local owner = trim(args[3])
        if owner == "" or owner:lower() == "me" then owner = get_me_name() end
        local zone = get_zone_or_default(args[4])
        cmd_say(string.format("enter %s %s %s", mode, owner, zone))
        return
    end

    if action == "enterall" then
        local mode = tolower(args[2] or "raid")
        local owner = trim(args[3])
        if owner == "" or owner:lower() == "me" then owner = get_me_name() end
        local zone = get_zone_or_default(args[4])
        local sent, source, remoteMode = enter_auto(mode, owner, zone)
        if remoteMode == "none" and sent <= 1 then
            btnUtils.Output("\\ayEZ Instance Master\\aw: no remote relay found (load MQ2EQBC or MQ2DanNet). Sent local enter only.")
        else
            btnUtils.Output("\\agEZ Instance Master\\aw: enter-all sent to %d %s members via %s for %s %s %s.",
                sent, source, remoteMode, mode, owner, zone)
        end
        return
    end

    if action == "repop" then
        cmd_say("repop instance")
        return
    end

    btnUtils.Output("\\arUnknown /eziminstances action: \\at%s\\aw", action)
    btnUtils.Output("Use \\at/eziminstances help\\aw for valid options.")
end

local function EZIMGUI()
    if not openGUI then return end
    if not ezimSettings:GetCharConfig() then return end

    -- Set this way up here so the theme can override.
    ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 0.9, 0.9, 0.9, 0.5)
    ImGui.PushStyleColor(ImGuiCol.HeaderHovered, 0.9, 0.9, 0.9, 0.0)
    for hotbarId, hotbar in ipairs(EZIMHotbars) do
        local flags = ImGuiWindowFlags.NoFocusOnAppearing
        if ezimSettings:GetCharacterWindow(hotbarId).HideTitleBar then
            flags = bit32.bor(flags, ImGuiWindowFlags.NoTitleBar)
        end
        if ezimSettings:GetCharacterWindow(hotbarId).Locked then
            flags = bit32.bor(flags, ImGuiWindowFlags.NoMove, ImGuiWindowFlags.NoResize)
        end
        if ezimSettings:GetCharacterWindow(hotbarId).HideScrollbar then
            flags = bit32.bor(flags, ImGuiWindowFlags.NoScrollbar)
        end
        hotbar:RenderHotbar(flags)
    end
    EZIMEditPopup:RenderEditButtonPopup()
    ImGui.PopStyleColor(2)
end

local function Setup()
    if not ezimSettings:LoadSettings() then return end
    local changed, msg = EnsureEZInstanceProfile(false)
    if changed then
        btnUtils.Output("\\agEZ Instance Master\\aw: %s", msg)
    end

    local pruned, removedCount = remove_non_ezim_windows()
    if pruned then
        ezimSettings:SaveSettings(true)
        btnUtils.Output("\\agEZ Instance Master\\aw: removed %d legacy non-EZIM window(s).", removedCount)
    end

    EZIMHotbars = {}

    for idx, _ in ipairs(ezimSettings:GetCharConfig().Windows or {}) do
        table.insert(EZIMHotbars, ezimHotbarClass.new(idx, false))
    end

    if #EZIMHotbars == 0 then
        table.insert(EZIMHotbars, ezimHotbarClass.new(1, true))
    end

    EZIMEditPopup:CloseEditPopup()
    btnUtils.Output('\ay%s v%s - \atLoaded!', APP_NAME, version)
end

local args = ... or ""
if args:lower() == "upgrade" then
    ezimSettings:ConvertToLatestConfigVersion()
    mq.exit()
end

local function GiveTime()
    while mq.TLO.MacroQuest.GameState() == "INGAME" do
        mq.delay(10)
        if EZIMReloadSettings then
            EZIMReloadSettings = false
            ezimSettings:LoadSettings()
        end

        if EZIMUpdateSettings then
            EZIMUpdateSettings = false

            Setup()

            for _, hotbar in ipairs(EZIMHotbars) do
                hotbar:ReloadConfig()
            end
        end

        if #EZIMHotbars > 0 then
            for _, hotbar in ipairs(EZIMHotbars) do
                if hotbar:IsVisible() then
                    hotbar:GiveTime()
                end
            end
        end
    end
    btnUtils.Output('\arNot in game, stopping %s.\ax', APP_NAME)
end

-- Global Messaging callback
---@diagnostic disable-next-line: unused-local
local script_actor = EZIMActors.register(function(message)
    local msg = message()

    if mq.TLO.MacroQuest.GameState() ~= "INGAME" then return end

    btnUtils.Debug("MSG! " .. msg["script"] .. " " .. msg["from"])

    if msg["from"] == mq.TLO.Me.DisplayName() then
        return
    end
    if msg["script"] ~= APP_ACTOR then
        return
    end

    btnUtils.Output("\ayGot Event from(\am%s\ay) event(\at%s\ay)", msg["from"], msg["event"])

    if msg["event"] == "SaveSettings" then
        btnUtils.Debug("Got new settings:\n%s", btnUtils.dumpTable(msg.newSettings))
        ezimSettings.settings = msg.newSettings
    elseif msg["event"] == "CopyLoc" then
        if msg.windowId <= #EZIMHotbars then
            EZIMHotbars[msg.windowId]:UpdatePosition((tonumber(msg["width"]) or 100), (tonumber(msg["height"]) or 100), (tonumber(msg["x"]) or 0), (tonumber(msg["y"]) or 0),
                msg["hideTitleBar"], msg["compactMode"])
            btnUtils.Debug("\agReplicating dimentions: \atw\ax(\am%d\ax) \ath\ax(\am%d\ax) \atx\ax(\am%d\ax) \aty\ax(\am%d\ax)",
                ezimSettings.Globals.newWidth,
                ezimSettings.Globals.newHeight,
                ezimSettings.Globals.newX,
                ezimSettings.Globals.newY)
        else
            btnUtils.Output("\ayFailed to replicate dimentions, you don't have a window id = %d", msg.windowId)
        end
    end
end)

Setup()

if ezimSettings:NeedUpgrade() then
    btnUtils.Output("\aw%s needs to upgrade! Please run: \at'/lua run ezinstancemaster upgrade'\ay on one character, then restart.", APP_NAME)
    mq.exit()
end

-- Make sure to start after the settings are validated.
mq.imgui.init('EZInstanceMasterGUI', EZIMGUI)
mq.bind('/ezim', BindBtn)
mq.bind('/ezimexec', BindBtnExec)
mq.bind('/ezimcopy', BindBtnCopy)
mq.bind('/eziminstances', BindBtnInstances)

GiveTime()
