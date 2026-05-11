-----------------------------------------------------------
-- ueqcredit.lua — Alt-currency merchant buyer (MacroQuest Lua)
--
-- Works with standard MerchantWnd and NewPointMerchantWnd (tier / point vendors).
-- Leave NPC_NAME empty to use whoever you have targeted; open their shop first or
-- let the script right-click your target.
--
-- INSTALL: <MQ>/lua/ueqcredit.lua
-- RUN:     /lua run ueqcredit
--
-- Item icons use MQ's A_DragItem atlas (same as GearScoreX). Optional static `items.json` for IDs/stats
-- (ship under lua/ueqcredit/catalog/<server>/ or config/ueqcredit/catalog/<server>/; legacy Prism/ paths still work).
--
-- /ueqcredit buy <qty>     begin buying selected item
-- /ueqcredit queue [qty]   buy checked list rows top-to-bottom (qty each; default = Quantity field)
-- /ueqcredit stop          stop current run
-----------------------------------------------------------

local mq = require('mq')
require 'ImGui'   -- global injection per kaen01 / RedGuides canonical pattern
local ui_theme = require('ui.theme')

------------------------------------------------------------
-- CONFIG
------------------------------------------------------------
--- Vendor spawn search name. **Empty string** = use current target only (any merchant).
local NPC_NAME      = ''
--- Default item substring (optional). Empty = choose from LOAD MERCHANT LIST only.
local ITEM_NAME     = ''
local OPEN_DELAY    = 1500
local BUY_DELAY     = 900
local CONFIRM_DELAY = 500
local NP_SELECT_DELAY = 70
local NP_CLICK_DELAY = 120
local NP_CONFIRM_WAIT_MAX = 900
local NP_INTERBUY_DELAY = 180
local ALLOW_MANUAL_SELECTED_FALLBACK = false

--- Static item DB (`items.json`): IDs, icons, GearScore-style hover stats — bundled for redistribution.
--- Search order (first file wins): see resolve_catalog_items_json_path() — ueqcredit/ paths first, then legacy Prism/.
--- Absolute override:
--- local UEQCREDIT_ITEMS_JSON = [[D:\MQ\config\ueqcredit\catalog\PEQ\items.json]]
---
--- Folder names under lua/ueqcredit/catalog/ or UltDev/catalog/ (PEQ, Ultimate_EQ, …).
local UEQCREDIT_ITEMS_JSON = ''
local UEQCREDIT_CATALOG_SERVER = 'PEQ'
--- Optional: explicit …/config path when mq.luaDir is not inside your repo (contains ueqcredit/, Prism/, or UltDev/).
local UEQCREDIT_CONFIG_ROOT = ''

--- Hover panel: 'catalog' = stats from items.json (GearScore-style table).
--- 'mq' = MacroQuest Item() TLO. 'both' = catalog first, then fill gaps from MQ.
local UEQCREDIT_STATS_TOOLTIP = 'catalog'
--- If false, skip MQ/Lua queries for chat item links in hover (Merchant/Item/LinkDB parse). Icons/IDs still use catalog + merchant for buying.
--- Right-click (Lua list): main loop selects that row on the NPC merchant window and sends a coordinate right-click on the list, then ItemLink/ExecuteTextLink if needed.
local UEQCREDIT_RESOLVE_MQ_ITEMLINKS = false

------------------------------------------------------------
-- STATE
------------------------------------------------------------
-- ImGui window vars - exactly as kaen01 pattern from RedGuides
local Open   = true
local ShowUI = true

-- Buy state machine
local running    = false
local shouldStop = false
local buyQty     = 0
local bought     = 0
local statusMsg  = 'Idle - Ready'
local step       = 'idle'
local itemIdx    = -1

-- GUI input - plain string, no buffer size
local inputQtyStr = '1'
local debugMode   = false
local targetItemName = ITEM_NAME
local uiMerchantItems = {}
local uiSelectedItemIndex = -1
--- Checkbox queue: parallel to uiMerchantItems indices (top = 1). Rebuilt on LOAD MERCHANT LIST.
local buyQueueChecked = {}
--- Active multi-item queue: snapshots taken at start so names stay stable while buying.
local queueBuyActive = false
local queueBuySnapshots = {} --- ordered { name, row, child }
local queueBuyCursor = 1       --- 1-based index into queueBuySnapshots
local queueBuyQtyEach = 1      --- qty field applies per queued item

--- Right-click item link: ImGui thread cannot mq.delay — stash row here; main loop opens link.
local pendingItemLinkEntry = nil

--- Filled by refresh_currency_detection() when NewPointMerchantWnd (or similar) is open.
local detectedCurrency = {
    wndName = '',
    merchantName = '',
    tier = nil,           --- number 1–8+ when parsed from UI text
    currencyName = '',    --- e.g. "Tier 3 Credits" for Me.AltCurrency()
    labelLine = '',       --- raw UI line mentioning Credits
    balance = -1,         --- from Me.AltCurrency when possible
    hint = '',
}
local LIST_CHILD_CANDIDATES = { 'NewPointMerchant_ItemList', 'MW_ItemList', 'ItemList' }
local NOTIFY_LIST_CANDIDATES = { 'NewPointMerchant_ItemList', 'MW_ItemList', 'ItemList' }
local BUY_BUTTON_CANDIDATES = { 'NewPointMerchant_PurchaseButton', 'MW_Purchase_Button', 'MW_Buy_Button' }
local DONE_BUTTON_CANDIDATES = { 'NewPointMerchant_DoneButton', 'MW_Done_Button' }

------------------------------------------------------------
-- LOGGING
------------------------------------------------------------
local function log(msg)
    msg = tostring(msg)
    print('\at[UEQC]\ax ' .. msg)
end

local function setStatus(s)
    statusMsg = s or ''
end

local function dbg(msg)
    if not debugMode then return end
    log('[DBG] ' .. tostring(msg))
end

------------------------------------------------------------
-- WAIT  (only called from main loop / state machine)
------------------------------------------------------------
local function wait(ms)
    mq.delay(ms, function() return shouldStop end)
end

local function safe_bool(v) return v and true or false end
local function safe_num(v) return tonumber(v) or 0 end
local function safe_eval(fn, default)
    local ok, v = pcall(fn)
    if ok then return v end
    return default
end
local function mq_parse(expr, default)
    if type(expr) ~= 'string' or expr == '' then return default end
    local ok, v = pcall(function() return mq.parse(expr) end)
    if ok then return v end
    return default
end

--- Defined before resolve_merchant_item_meta / nested closures (Lua binds locals after declaration).
local function strip_item_text(s)
    s = tostring(s or '')
    s = s:gsub('%c', ' ')
    s = s:gsub('%s+', ' ')
    s = s:gsub('^%s+', ''):gsub('%s+$', '')
    return s
end

local function normalize_null_text(s)
    s = strip_item_text(s)
    if s == 'NULL' then return '' end
    return s
end

--- Safe tonumber after stripping commas (gsub returns count as 2nd value — must not reach tonumber's base arg).
local function parse_price_digits(s)
    s = strip_item_text(s)
    if s == '' then return nil end
    local cleaned = (s:gsub(',', ''))
    return tonumber(cleaned)
end

--- UI list cells: pick the column that is numeric-only (vendor credits), never reuse item name text.
local function cell_looks_like_price(s)
    s = strip_item_text(s)
    if s == '' then return false end
    if s:find('%a') then return false end
    return parse_price_digits(s) ~= nil
end

local function infer_merchant_row_price(c0, c1, c2, c3)
    for _, c in ipairs({ c3, c1, c2, c0 }) do
        if cell_looks_like_price(c) then
            local n = parse_price_digits(c)
            if n then return tostring(math.floor(n + 0.5)) end
        end
    end
    return ''
end

------------------------------------------------------------
-- Static catalog (items.json); UltDev paths are optional dev fallbacks
------------------------------------------------------------
local catalogByNameLower = nil --- [string]= { id=n, icon=n|nil, raw=table }
local catalogLoadAttempted = false

local function catalog_file_exists(path)
    local f = io.open(path, 'r')
    if f then f:close(); return true end
    return false
end

--- If Lua dir is .../<project>/lua, shared config is usually .../<project>/config
local function guess_mq_fresh_config_root()
    local ld = tostring(mq.luaDir or ''):gsub('\\', '/')
    if ld == '' or not ld:lower():find('mq fresh', 1, true) then return '' end
    ld = ld:gsub('/+$', '')
    if ld:lower():sub(-4) == '/lua' then
        return ld:sub(1, -5) .. '/config'
    end
    return ''
end

local function resolve_catalog_items_json_path()
    if type(UEQCREDIT_ITEMS_JSON) == 'string' and UEQCREDIT_ITEMS_JSON ~= '' then
        return UEQCREDIT_ITEMS_JSON
    end

    local servers = { UEQCREDIT_CATALOG_SERVER, 'PEQ', 'Ultimate_EQ' }
    local seen = {}
    local ordered = {}
    for _, s in ipairs(servers) do
        if type(s) == 'string' and s ~= '' and not seen[s] then
            seen[s] = true
            ordered[#ordered + 1] = s
        end
    end

    --- Prefer ueqcredit/ folders; still accept legacy Prism/ so old installs keep working.
    local function pick_first(...)
        local t = { ... }
        for i = 1, #t do
            local path = t[i]
            if path and catalog_file_exists(path) then return path end
        end
        return nil
    end

    --- 1) Explicit config root
    local root = strip_item_text(tostring(UEQCREDIT_CONFIG_ROOT or ''))
    if root ~= '' then
        local rb = root:gsub('\\', '/')
        for _, srv in ipairs(ordered) do
            local ok = pick_first(
                string.format('%s/ueqcredit/catalog/%s/items.json', rb, srv),
                string.format('%s/Prism/catalog/%s/items.json', rb, srv),
                string.format('%s/UltDev/catalog/%s/items.json', rb, srv)
            )
            if ok then return ok end
        end
    end

    --- 2) Bundled under lua/: ueqcredit/ then legacy prism/
    for _, srv in ipairs(ordered) do
        local ok = pick_first(
            string.format('%s/ueqcredit/catalog/%s/items.json', mq.luaDir, srv),
            string.format('%s/prism/catalog/%s/items.json', mq.luaDir, srv)
        )
        if ok then return ok end
    end

    --- 3) Sibling config/
    for _, srv in ipairs(ordered) do
        local ok = pick_first(
            string.format('%s/../config/ueqcredit/catalog/%s/items.json', mq.luaDir, srv),
            string.format('%s/../config/Prism/catalog/%s/items.json', mq.luaDir, srv)
        )
        if ok then return ok end
    end

    --- 4) MQ Fresh guessed config root
    local guessed = guess_mq_fresh_config_root()
    if guessed ~= '' then
        local gb = guessed:gsub('\\', '/')
        for _, srv in ipairs(ordered) do
            local ok = pick_first(
                string.format('%s/ueqcredit/catalog/%s/items.json', gb, srv),
                string.format('%s/Prism/catalog/%s/items.json', gb, srv),
                string.format('%s/UltDev/catalog/%s/items.json', gb, srv)
            )
            if ok then return ok end
        end
    end

    --- 5) UltDev layouts + mq.configDir
    for _, srv in ipairs(ordered) do
        local p = string.format('%s/../config/UltDev/catalog/%s/items.json', mq.luaDir, srv)
        if catalog_file_exists(p) then return p end
    end
    for _, srv in ipairs(ordered) do
        local ok = pick_first(
            string.format('%s/UltDev/catalog/%s/items.json', mq.configDir, srv),
            string.format('%s/ueqcredit/catalog/%s/items.json', mq.configDir, srv),
            string.format('%s/Prism/catalog/%s/items.json', mq.configDir, srv)
        )
        if ok then return ok end
    end

    return string.format('%s/../config/ueqcredit/catalog/%s/items.json', mq.luaDir, UEQCREDIT_CATALOG_SERVER)
end

--- MQ often lacks dkjson on package.path; bundled copies ship next to UltDev/smartloot/EZInventory.
local function try_load_json_decode()
    local function as_decoder(lib)
        if type(lib) == 'table' and type(lib.decode) == 'function' then return lib end
        return nil
    end
    local okReq, reqLib = pcall(require, 'dkjson')
    local lib = as_decoder(okReq and reqLib or nil)
    if lib then return lib end
    local paths = {
        mq.luaDir .. '/UltDev/dkjson.lua',
        mq.luaDir .. '/smartloot/dkjson.lua',
        mq.luaDir .. '/EZInventory/dkjson.lua',
    }
    for _, p in ipairs(paths) do
        local okDf, dfLib = pcall(function() return dofile(p) end)
        lib = as_decoder(okDf and dfLib or nil)
        if lib then return lib end
    end
    return nil
end

local function ensure_catalog_loaded()
    if catalogLoadAttempted then
        return
    end
    catalogLoadAttempted = true
    catalogByNameLower = {}
    local path = resolve_catalog_items_json_path()
    local f = io.open(path, 'r')
    if not f then
        dbg('[UEQCredit] catalog not found (optional): ' .. path)
        return
    end
    local text = f:read('*a')
    f:close()
    local jsonLib = try_load_json_decode()
    if not jsonLib then
        dbg('[UEQCredit] catalog: JSON decoder unavailable (copy dkjson next to ueqcredit.lua)')
        return
    end
    local okDec, dec = pcall(function() return jsonLib.decode(text) end)
    if not okDec or not dec then
        dbg('[UEQCredit] catalog: decode failed')
        return
    end
    local list = dec
    if type(dec) == 'table' and type(dec.data) == 'table' then
        list = dec.data
    end
    if type(dec) == 'table' and type(dec.items) == 'table' then
        list = dec.items
    end
    if type(list) ~= 'table' then
        return
    end
    local uniq = 0
    for _, e in ipairs(list) do
        if type(e) == 'table' then
            local id = tonumber(e.id)
            local nm = e.name or e.Name
            local ic = tonumber(e.icon)
            if id and id > 0 and nm and strip_item_text(tostring(nm)) ~= '' then
                local key = strip_item_text(tostring(nm)):lower()
                if not catalogByNameLower[key] then
                    catalogByNameLower[key] = {
                        id = id,
                        icon = (ic and ic > 0) and ic or nil,
                        raw = e,
                    }
                    uniq = uniq + 1
                end
            end
        end
    end
    dbg(string.format('[UEQCredit] catalog loaded: %d items', uniq))
end

local function catalog_lookup_item(itemName)
    ensure_catalog_loaded()
    if not catalogByNameLower then
        return nil
    end
    local key = strip_item_text(itemName):lower()
    return catalogByNameLower[key]
end

--- GearScore-style stat keys (aligned with GearScoreX itemTooltip + weapon damage).
local UEQCREDIT_GS_KEYS = {
    'HP', 'Mana', 'Endurance', 'AC', 'ATK', 'Damage', 'STR', 'STA', 'AGI', 'DEX', 'WIS', 'INT', 'CHA',
    'HeroicSTR', 'HeroicSTA', 'HeroicAGI', 'HeroicDEX', 'HeroicWIS', 'HeroicINT', 'HeroicCHA',
    'HastePct', 'DoTShield', 'SpellShield', 'Avoidance', 'Shielding', 'CombatEffects', 'StrikeThrough', 'Accuracy',
}

local itemTypeLabels = nil --- nil = unloaded, false = missing file

local function load_item_type_labels()
    if itemTypeLabels ~= nil then return end
    itemTypeLabels = false
    local paths = {
        mq.luaDir .. '/ueqcredit/constants/item-types.json',
        mq.luaDir .. '/prism/constants/item-types.json',
        mq.luaDir .. '/../config/ueqcredit/constants/item-types.json',
        mq.luaDir .. '/../config/Prism/constants/item-types.json',
        mq.luaDir .. '/UltDev/constants/spire/item-types.json',
    }
    local text = nil
    for _, p in ipairs(paths) do
        local f = io.open(p, 'r')
        if f then
            text = f:read('*a')
            f:close()
            break
        end
    end
    if not text then return end
    local jlib = try_load_json_decode()
    if not jlib then return end
    local ok, d = pcall(function() return jlib.decode(text) end)
    if ok and type(d) == 'table' then itemTypeLabels = d end
end

local function itemtype_label(n)
    local it = tonumber(n)
    if not it then return '' end
    load_item_type_labels()
    if type(itemTypeLabels) == 'table' and itemTypeLabels[tostring(it)] then
        return tostring(itemTypeLabels[tostring(it)])
    end
    return ''
end

local function catalog_field(raw, ...)
    if type(raw) ~= 'table' then return nil end
    local names = { ... }
    for _, w in ipairs(names) do
        local wl = tostring(w):lower()
        for k, v in pairs(raw) do
            if type(k) == 'string' and k:lower() == wl then return v end
        end
    end
    return nil
end

local function catalog_field_n(raw, ...)
    return tonumber(catalog_field(raw, ...)) or 0
end

--- Map PEQ-style JSON row -> GearScoreX stats table (no MQ calls).
local function catalog_raw_to_gs_stats(raw)
    if type(raw) ~= 'table' then return nil end
    local s = {}
    s.Name = strip_item_text(tostring(catalog_field(raw, 'name', 'Name') or ''))
    s.Icon = tonumber(catalog_field(raw, 'icon', 'Icon')) or 0
    local ity = tonumber(catalog_field(raw, 'itemtype', 'item_type', 'ItemType'))
    s.ItemType = itemtype_label(ity)
    s.HP = catalog_field_n(raw, 'hp', 'HP')
    s.Mana = catalog_field_n(raw, 'mana', 'Mana')
    s.Endurance = catalog_field_n(raw, 'endurance', 'endur', 'Endurance')
    s.AC = catalog_field_n(raw, 'ac', 'AC')
    s.ATK = catalog_field_n(raw, 'attack', 'atk', 'Attack')
    s.Damage = catalog_field_n(raw, 'damage', 'dmg', 'Damage')
    s.STR = catalog_field_n(raw, 'astr', 'str', 'STR')
    s.STA = catalog_field_n(raw, 'asta', 'sta', 'STA', 'stamina', 'Stamina')
    s.AGI = catalog_field_n(raw, 'aagi', 'agi', 'AGI')
    s.DEX = catalog_field_n(raw, 'adex', 'dex', 'DEX')
    s.WIS = catalog_field_n(raw, 'awis', 'wis', 'WIS')
    s.INT = catalog_field_n(raw, 'aint', 'int', 'INT')
    s.CHA = catalog_field_n(raw, 'acha', 'cha', 'CHA')
    s.HeroicSTR = catalog_field_n(raw, 'heroic_str', 'HeroicSTR')
    s.HeroicSTA = catalog_field_n(raw, 'heroic_sta', 'HeroicSTA')
    s.HeroicAGI = catalog_field_n(raw, 'heroic_agi', 'HeroicAGI')
    s.HeroicDEX = catalog_field_n(raw, 'heroic_dex', 'HeroicDEX')
    s.HeroicWIS = catalog_field_n(raw, 'heroic_wis', 'HeroicWIS')
    s.HeroicINT = catalog_field_n(raw, 'heroic_int', 'HeroicINT')
    s.HeroicCHA = catalog_field_n(raw, 'heroic_cha', 'HeroicCHA')
    s.HastePct = catalog_field_n(raw, 'haste', 'HastePct')
    if s.HastePct == 0 then
        s.Haste = catalog_field_n(raw, 'Haste')
        s.HastePct = s.Haste
    end
    s.DoTShield = catalog_field_n(raw, 'dotshield', 'dot_shield', 'DoTShield')
    s.SpellShield = catalog_field_n(raw, 'spellshield', 'spell_shield', 'SpellShield')
    s.Avoidance = catalog_field_n(raw, 'avoidance', 'Avoidance')
    s.Shielding = catalog_field_n(raw, 'shielding', 'Shielding')
    s.CombatEffects = catalog_field_n(raw, 'combateffects', 'combat_effects', 'CombatEffects')
    s.StrikeThrough = catalog_field_n(raw, 'strikethrough', 'StrikeThrough')
    s.Accuracy = catalog_field_n(raw, 'accuracy', 'Accuracy')
    s.Weight = catalog_field_n(raw, 'weight', 'Weight')
    local lore = catalog_field(raw, 'loreflag', 'lore', 'Lore')
    s.Lore = lore == true or tonumber(lore) == 1 or tostring(lore):lower() == 'true'
    local nod = catalog_field(raw, 'nodrop', 'notrade', 'no_trade', 'NoDrop')
    s.NoDrop = nod == true or tonumber(nod) == 1 or tostring(nod):lower() == 'true'
    s.RequiredLevel = catalog_field_n(raw, 'reqlevel', 'req_level', 'RequiredLevel')
    s.RecommendedLevel = catalog_field_n(raw, 'reclevel', 'rec_level', 'RecommendedLevel')
    s.Focus = strip_item_text(tostring(catalog_field(raw, 'clickname', 'click_name', 'procname', 'Focus') or ''))
    return s
end

local function catalog_stats_meaningful(stats)
    if not stats then return false end
    for _, k in ipairs(UEQCREDIT_GS_KEYS) do
        local v = stats[k]
        if k == 'HastePct' and (not v or v == 0) then v = stats.Haste end
        if v and tonumber(v) and tonumber(v) ~= 0 then return true end
    end
    if stats.Focus and stats.Focus ~= '' then return true end
    if stats.Weight and stats.Weight ~= 0 then return true end
    return false
end

--- Draw GearScoreX-like tooltip body from catalog stats (no EQ item links required).
local function draw_ueqcredit_gearscore_catalog_tooltip(entry, stats)
    local ta_r, ta_g, ta_b, ta_a = ui_theme.rgba(ui_theme.TEXT_ACCENT)
    local tm_r, tm_g, tm_b, tm_a = ui_theme.rgba(ui_theme.TEXT_SECONDARY)
    local tp_r, tp_g, tp_b, tp_a = ui_theme.rgba(ui_theme.TEXT_PRIMARY)
    ImGui.BeginGroup()
    draw_ueqcredit_item_icon(entry.icon or stats.Icon or 500, 32)
    ImGui.SameLine()
    ImGui.BeginGroup()
    ImGui.TextColored(ta_r, ta_g, ta_b, ta_a, '%s', stats.Name ~= '' and stats.Name or (entry.name or ''))
    if entry.price and entry.price ~= '' then
        ImGui.TextColored(tm_r, tm_g, tm_b, tm_a, 'Vendor price: %s', entry.price)
    end
    ImGui.TextColored(tm_r, tm_g, tm_b, tm_a, '%s', stats.ItemType or '')
    if stats.Weight and stats.Weight ~= 0 then
        ImGui.TextColored(tm_r, tm_g, tm_b, tm_a, 'Weight: %s', tostring(stats.Weight))
    end
    if stats.RequiredLevel and stats.RequiredLevel > 0 then
        ImGui.TextColored(tm_r, tm_g, tm_b, tm_a, 'Required level: %d', stats.RequiredLevel)
    end
    if stats.RecommendedLevel and stats.RecommendedLevel > 0 then
        ImGui.TextColored(tm_r, tm_g, tm_b, tm_a, 'Recommended level: %d', stats.RecommendedLevel)
    end
    ImGui.EndGroup()
    ImGui.EndGroup()
    if stats.Lore then ImGui.TextColored(0.72, 0.58, 0.92, 1, 'Lore') end
    if stats.NoDrop then ImGui.TextColored(0.92, 0.42, 0.42, 1, 'No Trade') end
    ImGui.Separator()
    ImGui.PushStyleColor(ImGuiCol.Text, tm_r, tm_g, tm_b, tm_a)
    ImGui.Text('Stats (catalog)')
    ImGui.PopStyleColor()
    if ImGui.BeginTable('ueqc_gs_table', 2, ImGuiTableFlags.SizingStretchProp) then
        for _, k in ipairs(UEQCREDIT_GS_KEYS) do
            local v = stats[k]
            if k == 'HastePct' and (not v or v == 0) then v = stats.Haste end
            if v and tonumber(v) and tonumber(v) ~= 0 then
                ImGui.TableNextRow()
                ImGui.TableNextColumn()
                ImGui.TextColored(tm_r, tm_g, tm_b, tm_a, '%s', k)
                ImGui.TableNextColumn()
                ImGui.TextColored(tp_r, tp_g, tp_b, tp_a, '%s', tostring(v))
            end
        end
        ImGui.EndTable()
    end
    if stats.Focus and stats.Focus ~= '' then
        ImGui.Separator()
        ImGui.TextColored(0.48, 0.72, 0.92, 1, 'Focus / click')
        ImGui.TextWrapped('%s', stats.Focus)
    end
    ImGui.Separator()
    ImGui.TextColored(tm_r, tm_g, tm_b, tm_a, 'Reference ID %d — catalog link-offline', tonumber(entry.id) or 0)
end

------------------------------------------------------------
-- Item icons + metadata (A_DragItem; aligns with GearScoreX)
------------------------------------------------------------
local ueqcreditAnimItems = nil

local function get_ueqcredit_item_anim()
    if ueqcreditAnimItems then return ueqcreditAnimItems end
    local ok, a = pcall(function() return mq.FindTextureAnimation('A_DragItem') end)
    if ok and a then ueqcreditAnimItems = a end
    return ueqcreditAnimItems
end

local function draw_ueqcredit_item_icon(iconID, size)
    size = size or 20
    local anim = get_ueqcredit_item_anim()
    local id = tonumber(iconID) or 500
    local cell = math.max(0, id - 500)
    if anim then
        anim:SetTextureCell(cell)
        ImGui.DrawTextureAnimation(anim, size, size)
        return
    end
    ImGui.Dummy(size, size)
end

local function read_item_meta_from_tlo(it)
    local meta = { id = 0, icon = 500, itemLink = '', vendorPrice = nil }
    if not it then return meta end
    local exists = safe_eval(function() return it() end, false)
    if not exists then return meta end
    meta.id = tonumber(safe_eval(function() return it.ID() end, 0)) or 0
    meta.icon = tonumber(safe_eval(function() return it.Icon() end, 500)) or 500
    meta.vendorPrice = tonumber(safe_eval(function() return it.Value() end, nil))
    meta.itemLink = safe_eval(function()
        if not it.ItemLink then return '' end
        local x = it.ItemLink('CLICKABLE')
        if type(x) == 'function' then return x() end
        return ''
    end, '')
    if meta.itemLink == '' then
        meta.itemLink = safe_eval(function()
            if not it.ItemLink then return '' end
            local x = it.ItemLink()
            if type(x) == 'function' then return x() end
            return tostring(x or '')
        end, '')
    end
    return meta
end

--- Static item DB by ID (does not require inventory); emu/live both expose this when Item IDs exist.
local function item_tlo_by_id(id)
    local n = tonumber(id)
    if not n or n <= 0 then return nil end
    local it = nil
    pcall(function() it = mq.TLO.Item(n) end)
    if it and safe_eval(function() return it() end, false) then return it end
    pcall(function() it = mq.TLO.Item(tostring(n)) end)
    if it and safe_eval(function() return it() end, false) then return it end
    return nil
end

local function item_stat_lines_from_tlo(it)
    if not it or not safe_eval(function() return it() end, false) then return {} end
    local lines = {}
    local function try_int(label, fn)
        local v = tonumber(safe_eval(fn, nil))
        if v and v ~= 0 then
            lines[#lines + 1] = string.format('%s: %d', label, math.floor(v + 0.5))
        end
    end
    local function try_str(label, fn)
        local v = strip_item_text(tostring(safe_eval(fn, '') or ''))
        if v ~= '' and v ~= 'NULL' then
            lines[#lines + 1] = string.format('%s: %s', label, v)
        end
    end

    try_str('Type', function() return it.Type() end)
    try_int('Req lvl', function() return it.RequiredLevel() end)
    try_int('Rec lvl', function() return it.RecommendedLevel() end)
    try_int('AC', function() return it.AC() end)
    try_int('HP', function() return it.HP() end)
    try_int('Mana', function() return it.Mana() end)
    try_int('End', function() return it.Endurance() end)
    try_int('STR', function() return it.STR() end)
    try_int('STA', function() return it.STA() end)
    try_int('AGI', function() return it.AGI() end)
    try_int('DEX', function() return it.DEX() end)
    try_int('WIS', function() return it.WIS() end)
    try_int('INT', function() return it.INT() end)
    try_int('CHA', function() return it.CHA() end)
    try_int('ATK', function() return it.Attack() end)
    try_int('DMG', function() return it.Damage() end)
    try_int('Haste', function() return it.Haste() end)
    local w = tonumber(safe_eval(function() return it.Weight() end, nil))
    if w and w ~= 0 then
        lines[#lines + 1] = string.format('Weight: %s', tostring(w))
    end
    if safe_eval(function() return it.Lore() end, false) then
        lines[#lines + 1] = 'Lore'
    end
    if safe_eval(function() return it.NoDrop() end, false) or safe_eval(function() return it.NoTrade() end, false) then
        lines[#lines + 1] = 'No Trade'
    end

    local maxL = 28
    while #lines > maxL do table.remove(lines) end
    return lines
end

--- Prefer list row index: Merchant.Item(n) is 1-based and matches NewPointMerchant list rows on most builds.
--- forceResolveLinks: when true, resolve ItemLink even if UEQCREDIT_RESOLVE_MQ_ITEMLINKS is off (e.g. right-click open link).
local function resolve_merchant_item_meta(itemName, listRow0, forceResolveLinks)
    local resolveLinks = (forceResolveLinks == true) or UEQCREDIT_RESOLVE_MQ_ITEMLINKS
    local empty = { id = 0, icon = 500, itemLink = '', vendorPrice = nil, catalogRaw = nil }
    if not itemName or itemName == '' then return empty end

    local idx1 = (listRow0 ~= nil) and (tonumber(listRow0) + 1) or nil
    if idx1 and idx1 < 1 then idx1 = nil end

    local tries = {}
    if idx1 then
        tries[#tries + 1] = { slot = 'idx', fn = function() return mq.TLO.Merchant.Item(idx1) end }
    end
    tries[#tries + 1] = { slot = 'eq', fn = function() return mq.TLO.Merchant.Item('=' .. itemName) end }
    tries[#tries + 1] = { slot = 'sub', fn = function() return mq.TLO.Merchant.Item(itemName) end }
    tries[#tries + 1] = { slot = 'find', fn = function() return mq.TLO.FindItem('=' .. itemName) end }

    local best = empty
    for _, t in ipairs(tries) do
        local ok, it = pcall(t.fn)
        if ok and it then
            local m = read_item_meta_from_tlo(it)
            if m.id > 0 or m.icon ~= 500 or (m.itemLink and m.itemLink ~= '') or (m.vendorPrice and m.vendorPrice > 0) then
                best = m
                if t.slot == 'idx' then break end
                if m.itemLink ~= '' and m.id > 0 then break end
            end
        end
    end

    local function clean_link(s)
        s = strip_item_text(tostring(s or ''))
        if s == '' or s == 'NULL' then return '' end
        return s
    end

    if resolveLinks then
        if clean_link(best.itemLink) == '' and idx1 then
            local plink = clean_link(mq_parse(string.format('${Merchant.Item[%d].ItemLink}', idx1), ''))
            if plink ~= '' then best.itemLink = plink end
        end
        if clean_link(best.itemLink) == '' then
            local esc = itemName:gsub('%]', '')
            local plink = clean_link(mq_parse(string.format('${Merchant.Item[=%s].ItemLink}', esc), ''))
            if plink ~= '' then best.itemLink = plink end
        end
    end

    local cat = catalog_lookup_item(itemName)
    if cat then
        if best.id == 0 and cat.id and cat.id > 0 then
            best.id = cat.id
        end
        if (best.icon == 500 or best.icon == 0) and cat.icon and cat.icon > 0 then
            best.icon = cat.icon
        end
        best.catalogRaw = cat.raw
    end

    if resolveLinks then
        if clean_link(best.itemLink) == '' and best.id > 0 then
            local plink = clean_link(mq_parse(string.format('${Item[%d].ItemLink}', best.id), ''))
            if plink ~= '' then best.itemLink = plink end
        end
        if clean_link(best.itemLink) == '' and best.id > 0 then
            local esc = itemName:gsub('%]', '')
            local plink = clean_link(mq_parse(string.format('${Item[=%s].ItemLink}', esc), ''))
            if plink ~= '' then best.itemLink = plink end
        end

        --- Item(id) TLO sometimes exposes ItemLink when emu DB matches.
        if clean_link(best.itemLink) == '' and best.id > 0 then
            local itDb = item_tlo_by_id(best.id)
            if itDb then
                local lm = read_item_meta_from_tlo(itDb)
                if clean_link(lm.itemLink) ~= '' then best.itemLink = lm.itemLink end
            end
        end

        --- MQ2LinkDB v2
        if clean_link(best.itemLink) == '' then
            local esc = itemName:gsub('%]', '')
            local ldb = clean_link(mq_parse(string.format('${LinkDB[=%s]}', esc), ''))
            if ldb ~= '' then best.itemLink = ldb end
        end
    end

    if not resolveLinks then
        best.itemLink = ''
    end

    return best
end

local function draw_merchant_item_tooltip(entry)
    ui_theme.push_tooltip_obsidian()
    ImGui.BeginTooltip()
    ImGui.PushTextWrapPos(ImGui.GetFontSize() * 36)

    local ta_r, ta_g, ta_b, ta_a = ui_theme.rgba(ui_theme.TEXT_ACCENT)
    local tm_r, tm_g, tm_b, tm_a = ui_theme.rgba(ui_theme.TEXT_SECONDARY)
    local mode = UEQCREDIT_STATS_TOOLTIP or 'catalog'
    local statsCat = entry.catalogRaw and catalog_raw_to_gs_stats(entry.catalogRaw) or nil

    if mode == 'catalog' or mode == 'both' then
        if statsCat and catalog_stats_meaningful(statsCat) then
            draw_ueqcredit_gearscore_catalog_tooltip(entry, statsCat)
        elseif statsCat then
            ImGui.BeginGroup()
            draw_ueqcredit_item_icon(entry.icon or 500, 28)
            ImGui.SameLine()
            ImGui.BeginGroup()
            ImGui.TextColored(ta_r, ta_g, ta_b, ta_a, '%s', entry.name or '')
            if entry.price and entry.price ~= '' then
                ImGui.TextColored(tm_r, tm_g, tm_b, tm_a, 'Vendor price: %s', entry.price)
            end
            if statsCat.ItemType and statsCat.ItemType ~= '' then
                ImGui.TextColored(tm_r, tm_g, tm_b, tm_a, '%s', statsCat.ItemType)
            end
            ImGui.EndGroup()
            ImGui.EndGroup()
            ImGui.Separator()
            ImGui.TextWrapped(
                'This items.json row has no combat stats (only id/name/icon/itemtype). Export from your PEQ DB — see lua/UltDev/tools/peq_export_prism_items_extended.sql.')
        else
            ImGui.TextColored(ta_r, ta_g, ta_b, ta_a, '%s', entry.name or '')
            if entry.price and entry.price ~= '' then
                ImGui.TextColored(tm_r, tm_g, tm_b, tm_a, 'Vendor price: %s', entry.price)
            end
            ImGui.TextWrapped('No catalog row for this item name (check items.json / folder UEQCREDIT_CATALOG_SERVER).')
        end
    end

    if mode == 'mq' or mode == 'both' then
        local idn = tonumber(entry.id) or 0
        local itLive = (idn > 0) and item_tlo_by_id(idn) or nil
        local statLines = itLive and item_stat_lines_from_tlo(itLive) or {}
        if #statLines > 0 then
            ImGui.Separator()
            ImGui.TextColored(tm_r, tm_g, tm_b, tm_a, 'Stats (MQ Item TLO)')
            for _, ln in ipairs(statLines) do
                ImGui.TextUnformatted(ln)
            end
        end
    end

    if UEQCREDIT_RESOLVE_MQ_ITEMLINKS and entry.itemLink and entry.itemLink ~= '' then
        ImGui.Separator()
        ImGui.TextUnformatted(entry.itemLink)
    end

    ImGui.PopTextWrapPos()
    ImGui.EndTooltip()
    ui_theme.pop_tooltip_obsidian()
end

local MERCHANT_WINDOW_CANDIDATES = { 'NewPointMerchantWnd', 'MerchantWnd' }

local function merchant_window_name()
    for _, wndName in ipairs(MERCHANT_WINDOW_CANDIDATES) do
        local w = mq.TLO.Window(wndName)
        local isOpen = safe_bool(safe_eval(function() return w and w.Open and w.Open() end, false))
        local isVisible = safe_bool(safe_eval(function() return w and w.Visible and w.Visible() end, false))
        if w and (isOpen or isVisible) then return wndName end
    end
    for _, wndName in ipairs(MERCHANT_WINDOW_CANDIDATES) do
        if mq.TLO.Window(wndName) then return wndName end
    end
    return MERCHANT_WINDOW_CANDIDATES[1]
end

local function merchant_window(path)
    local base = merchant_window_name()
    if path and path ~= '' then
        return mq.TLO.Window(base .. '/' .. path), base
    end
    return mq.TLO.Window(base), base
end

--- Read visible text from a UI control if supported by this MQ build.
local function control_display_text(ctrl)
    if not ctrl then return '' end
    return normalize_null_text(safe_eval(function()
        if ctrl.Text then return ctrl.Text() end
        return ''
    end, ''))
end

local function walk_window_texts(win, bucket, depth, maxDepth)
    if not win or depth > (maxDepth or 8) then return end
    local t = control_display_text(win)
    if t ~= '' then bucket[#bucket + 1] = t end
    local c = safe_eval(function() return win.FirstChild and win.FirstChild() end, nil)
    local guard = 0
    while c and guard < 500 do
        walk_window_texts(c, bucket, depth + 1, maxDepth)
        c = safe_eval(function() return c.Next and c.Next() end, nil)
        guard = guard + 1
    end
end

--- Known optional ScreenIDs for currency lines (server-dependent); mq.parse fills gaps.
local CURRENCY_PARSE_CANDIDATES = {
    'NewPointMerchant_MerchantName',
    'NewPointMerchant_AltCurrencyLabel',
    'NewPointMerchant_PointsLabel',
    'NewPointMerchant_AltCurrencyAmt',
    'NewPointMerchant_AltCurrencyValue',
    'MW_MerchantName',
}

local function refresh_currency_detection()
    local wname = merchant_window_name()
    detectedCurrency.wndName = wname
    detectedCurrency.merchantName = tostring(safe_eval(function()
        return mq.TLO.Merchant and mq.TLO.Merchant.CleanName and mq.TLO.Merchant.CleanName()
    end, ''))
    if detectedCurrency.merchantName == '' then
        detectedCurrency.merchantName = tostring(safe_eval(function()
            return mq.TLO.Target and mq.TLO.Target.CleanName and mq.TLO.Target.CleanName()
        end, ''))
    end

    detectedCurrency.tier = nil
    detectedCurrency.currencyName = ''
    detectedCurrency.labelLine = ''
    detectedCurrency.balance = -1
    detectedCurrency.hint = ''

    if wname ~= 'NewPointMerchantWnd' then
        detectedCurrency.hint = 'Standard merchant (plat/copper) — no tier credit strip.'
        return
    end

    local texts = {}
    local w = merchant_window()
    if w then walk_window_texts(w, texts, 0, 10) end

    for _, sid in ipairs(CURRENCY_PARSE_CANDIDATES) do
        local expr = '${Window[' .. wname .. '].Child[' .. sid .. '].Text}'
        local tx = normalize_null_text(mq_parse(expr, ''))
        if tx ~= '' then texts[#texts + 1] = tx end
    end

    local tier = nil
    local labelFull = ''
    for _, s in ipairs(texts) do
        local ti = s:match('Tier%s+(%d+)%s+Credits')
        if ti then
            tier = tonumber(ti)
            labelFull = s
            break
        end
    end
    if not tier then
        for _, s in ipairs(texts) do
            local ti = s:match('(%d+)%s*[Cc]redits')
            if ti and s:lower():find('tier', 1, true) then
                tier = tonumber(ti)
                labelFull = s
                break
            end
        end
    end

    detectedCurrency.tier = tier
    detectedCurrency.labelLine = labelFull

    if tier then
        detectedCurrency.currencyName = string.format('Tier %d Credits', tier)
        local bal = safe_num(safe_eval(function()
            local cur = mq.TLO.Me.AltCurrency(detectedCurrency.currencyName)
            return cur and cur() or -1
        end, -1))
        if bal >= 0 then
            detectedCurrency.balance = bal
        end
    end

    if detectedCurrency.balance < 0 then
        for _, s in ipairs(texts) do
            local n = s:match('^(%d+)$')
            if n and tonumber(n) > 50 then
                detectedCurrency.balance = tonumber(n)
                break
            end
        end
    end

    if tier then
        detectedCurrency.hint = string.format(
            'Detected %s — UI balance≈%s (AltCurrency TLO when available).',
            detectedCurrency.currencyName,
            detectedCurrency.balance >= 0 and tostring(detectedCurrency.balance) or '?')
    else
        detectedCurrency.hint = ''
    end
end

local function active_list_child_name()
    local w = merchant_window()
    if not w then return LIST_CHILD_CANDIDATES[1] end
    for _, childName in ipairs(LIST_CHILD_CANDIDATES) do
        local c = safe_eval(function() return w.Child and w.Child(childName) end, nil)
        if c then return childName end
    end
    return LIST_CHILD_CANDIDATES[1]
end
local function safe_index(v)
    local n = tonumber(v)
    if not n then return -1 end
    n = math.floor(n)
    if n < 0 then return -1 end
    return n
end

local function get_target_item_name()
    --- BUY QUEUE: ImGui.InputText overwrites targetItemName every frame with the stale field buffer —
    --- always drive the merchant target from the queue snapshot while a queue run is active.
    if queueBuyActive and queueBuySnapshots and #queueBuySnapshots > 0 then
        local cur = queueBuySnapshots[queueBuyCursor]
        if cur and cur.name and strip_item_text(cur.name) ~= '' then
            return strip_item_text(cur.name)
        end
    end
    local n = strip_item_text(targetItemName)
    if n == '' then n = ITEM_NAME end
    return n
end

local function row_matches_item(list, row, itemName)
    if not list or row == nil or row < 0 then return false end
    local txt = ''
    if list.List then
        txt = normalize_null_text(list.List(row))
        if txt == '' then txt = normalize_null_text(list.List(row, 0)) end
        if txt == '' then txt = normalize_null_text(list.List(row, 1)) end
        if txt == '' then txt = normalize_null_text(list.List(row, 2)) end
    end
    if txt == '' then return false end
    local needle = strip_item_text(itemName):lower()
    return txt:lower():find(needle, 1, true) ~= nil
end

local function dump_window_tree(win, depth, maxDepth)
    if not win or depth > maxDepth then return end
    local indent = string.rep(' ', depth * 2)
    local name = tostring(safe_eval(function() return win.Name and win.Name() end, '<?>'))
    local sid = tostring(safe_eval(function() return win.ScreenID and win.ScreenID() end, '<?>'))
    local wtype = tostring(safe_eval(function() return win.Type and win.Type() end, '<?>'))
    local open = tostring(safe_eval(function() return win.Open and win.Open() end, false))
    local vis = tostring(safe_eval(function() return win.Visible and win.Visible() end, false))
    local items = tonumber(safe_eval(function() return win.Items and win.Items() end, -1)) or -1
    local list0 = normalize_null_text(safe_eval(function() return win.List and win.List(0) end, ''))
    if list0 == '' then list0 = normalize_null_text(safe_eval(function() return win.List and win.List(0, 1) end, '')) end

    dbg(('%s%s [ScreenID=%s Type=%s Open=%s Vis=%s Items=%d List0="%s"]'):format(
        indent, name, sid, wtype, open, vis, items, list0
    ))

    local c = safe_eval(function() return win.FirstChild and win.FirstChild() end, nil)
    local guard = 0
    while c and guard < 300 do
        dump_window_tree(c, depth + 1, maxDepth)
        c = safe_eval(function() return c.Next and c.Next() end, nil)
        guard = guard + 1
    end
end

local function dump_merchant_window()
    local w = merchant_window()
    if not w then
        dbg('Merchant window not found for dump.')
        return
    end
    dbg('--- MerchantWnd Tree Dump (start) ---')
    local ok, err = xpcall(function()
        dump_window_tree(w, 0, 4)
    end, function(e) return debug.traceback(e, 2) end)
    if not ok then
        log('ERROR: dumpwin failed: ' .. tostring(err))
    end
    dbg('--- MerchantWnd Tree Dump (end) ---')
end

local function merchant_state()
    local st = {
        wndExists = false, open = false, visible = false,
        listExists = false, items = -1, firstItem = '',
        doneExists = false, doneEnabled = false,
        buyExists = false, buyEnabled = false,
    }

    local w, wndName = merchant_window()
    if not w then return st end
    st.wndExists = true
    st.open = safe_bool(w.Open and w.Open())
    st.visible = safe_bool(w.Visible and w.Visible())

    for _, childName in ipairs(LIST_CHILD_CANDIDATES) do
        local list = w.Child and w.Child(childName)
        if list then
            st.listExists = true
            st.items = safe_num(list.Items and list.Items())
            st.firstItem = strip_item_text(list.List and list.List(0) or '')
            dbg(('merchant_state wnd=%s list child=%s items=%d first="%s"'):format(wndName, childName, st.items, st.firstItem))
            break
        end
    end

    for _, childName in ipairs(DONE_BUTTON_CANDIDATES) do
        local done = w.Child and w.Child(childName)
        if done then
            st.doneExists = true
            st.doneEnabled = safe_bool(done.Enabled and done.Enabled())
            break
        end
    end

    for _, childName in ipairs(BUY_BUTTON_CANDIDATES) do
        local buy = w.Child and w.Child(childName)
        if buy then
            st.buyExists = true
            st.buyEnabled = safe_bool(buy.Enabled and buy.Enabled())
            break
        end
    end

    return st
end

local function merchant_ready(st)
    st = st or merchant_state()
    if st.open or st.visible then return true end
    if st.doneEnabled then return true end
    if st.items > 0 then return true end
    if st.firstItem ~= '' then return true end
    return false
end

local function log_merchant_state(tag)
    local st = merchant_state()
    dbg(('%s wnd=%s open=%s vis=%s list=%s items=%d done=%s/%s buy=%s/%s first="%s"'):format(
        tostring(tag or 'state'),
        tostring(st.wndExists),
        tostring(st.open),
        tostring(st.visible),
        tostring(st.listExists),
        st.items,
        tostring(st.doneExists),
        tostring(st.doneEnabled),
        tostring(st.buyExists),
        tostring(st.buyEnabled),
        st.firstItem
    ))
    return st
end

local function merchant_items_received()
    local m = mq.TLO.Merchant
    return safe_bool(m and m.ItemsReceived and m.ItemsReceived())
end

local function merchant_diag_state()
    local d = {}
    d.target_exists = safe_bool(safe_eval(function() return mq.TLO.Target and mq.TLO.Target() end, false))
    d.target_name = tostring(safe_eval(function() return mq.TLO.Target and mq.TLO.Target.CleanName and mq.TLO.Target.CleanName() end, ''))
    d.target_type = tostring(safe_eval(function() return mq.TLO.Target and mq.TLO.Target.Type and mq.TLO.Target.Type() end, ''))
    d.target_is_merchant = safe_bool(safe_eval(function() return mq.TLO.Target and mq.TLO.Target.Merchant and mq.TLO.Target.Merchant() end, false))

    local wnd, wndName = merchant_window()
    d.wnd_exists = wnd ~= nil
    d.wnd_open = safe_bool(safe_eval(function() return wnd and wnd.Open and wnd.Open() end, false))
    d.wnd_visible = safe_bool(safe_eval(function() return wnd and wnd.Visible and wnd.Visible() end, false))
    d.wnd_type = tostring(safe_eval(function() return wnd and wnd.Type and wnd.Type() end, ''))
    d.wnd_name = tostring(wndName or '')
    d.itemlist_exists = false
    d.itemlist_items = 0
    d.itemlist_child = ''
    if wnd and wnd.Child then
        for _, childName in ipairs(LIST_CHILD_CANDIDATES) do
            local il = safe_eval(function() return wnd.Child(childName) end, nil)
            if il then
                d.itemlist_exists = true
                d.itemlist_items = safe_num(safe_eval(function() return il.Items and il.Items() end, 0))
                d.itemlist_child = childName
                break
            end
        end
    end
    d.newpoint_open = safe_bool(safe_eval(function() return mq.TLO.Window('NewPointMerchantWnd') and mq.TLO.Window('NewPointMerchantWnd').Open and mq.TLO.Window('NewPointMerchantWnd').Open() end, false))
    d.newpoint_visible = safe_bool(safe_eval(function() return mq.TLO.Window('NewPointMerchantWnd') and mq.TLO.Window('NewPointMerchantWnd').Visible and mq.TLO.Window('NewPointMerchantWnd').Visible() end, false))
    d.merchantwnd_open = safe_bool(safe_eval(function() return mq.TLO.Window('MerchantWnd') and mq.TLO.Window('MerchantWnd').Open and mq.TLO.Window('MerchantWnd').Open() end, false))
    d.merchantwnd_visible = safe_bool(safe_eval(function() return mq.TLO.Window('MerchantWnd') and mq.TLO.Window('MerchantWnd').Visible and mq.TLO.Window('MerchantWnd').Visible() end, false))

    d.merchant_open = safe_bool(safe_eval(function() return mq.TLO.Merchant and mq.TLO.Merchant.Open and mq.TLO.Merchant.Open() end, false))
    d.items_received = safe_bool(safe_eval(function() return merchant_items_received() end, false))
    d.items = safe_num(safe_eval(function() return merchant_items_count() end, 0))
    d.merchant_name = tostring(safe_eval(function() return mq.TLO.Merchant and mq.TLO.Merchant.CleanName and mq.TLO.Merchant.CleanName() end, ''))
    d.points_text = ''
    if detectedCurrency.currencyName ~= '' then
        d.points_text = string.format('%s balance=%s', detectedCurrency.currencyName,
            detectedCurrency.balance >= 0 and tostring(detectedCurrency.balance) or '?')
    elseif detectedCurrency.labelLine ~= '' then
        d.points_text = detectedCurrency.labelLine
    end
    return d
end

local function log_merchant_diag(tag)
    local ok, d = pcall(merchant_diag_state)
    if not ok or type(d) ~= 'table' then
        log('[DIAG] ERROR: merchant_diag_state failed: ' .. tostring(d))
        return {}
    end
    local line = string.format(
        '[DIAG] %s targetExists=%s targetName="%s" targetType="%s" targetMerchant=%s wndName=%s wndExists=%s wndOpen=%s wndVisible=%s wndType="%s" itemListExists=%s itemListChild=%s itemListItems=%s merchantOpen=%s itemsReceived=%s items=%s merchantName="%s" points="%s" npOpen=%s npVisible=%s mwOpen=%s mwVisible=%s',
        tostring(tag or 'state'),
        tostring(d.target_exists), tostring(d.target_name), tostring(d.target_type), tostring(d.target_is_merchant),
        tostring(d.wnd_name),
        tostring(d.wnd_exists), tostring(d.wnd_open), tostring(d.wnd_visible), tostring(d.wnd_type),
        tostring(d.itemlist_exists), tostring(d.itemlist_child), tostring(d.itemlist_items),
        tostring(d.merchant_open), tostring(d.items_received), tostring(d.items), tostring(d.merchant_name), tostring(d.points_text),
        tostring(d.newpoint_open), tostring(d.newpoint_visible), tostring(d.merchantwnd_open), tostring(d.merchantwnd_visible)
    )
    log(line)
    return d
end

local function window_itemlist_find_index(itemName)
    local name = tostring(itemName or '')
    local wndName = merchant_window_name()
    for _, childName in ipairs(LIST_CHILD_CANDIDATES) do
        local exactCol2 = safe_index(mq_parse(('${Window[%s].Child[%s].List[=%s,2]}'):format(wndName, childName, name), -1))
        if exactCol2 >= 0 then return exactCol2, childName end
        local exact = safe_index(mq_parse(('${Window[%s].Child[%s].List[=%s]}'):format(wndName, childName, name), -1))
        if exact >= 0 then return exact, childName end
        local partialCol2 = safe_index(mq_parse(('${Window[%s].Child[%s].List[%s,2]}'):format(wndName, childName, name), -1))
        if partialCol2 >= 0 then return partialCol2, childName end
        local partial = safe_index(mq_parse(('${Window[%s].Child[%s].List[%s]}'):format(wndName, childName, name), -1))
        if partial >= 0 then return partial, childName end
    end
    return -1, ''
end

--- Exact list row only (no substring) — used when we must target the correct merchant line for right-click.
local function window_itemlist_find_row_exact(itemName)
    local name = strip_item_text(tostring(itemName or ''))
    if name == '' then return -1, '' end
    local wndName = merchant_window_name()
    for _, childName in ipairs(LIST_CHILD_CANDIDATES) do
        local col2 = safe_index(mq_parse(('${Window[%s].Child[%s].List[=%s,2]}'):format(wndName, childName, name), -1))
        if col2 >= 0 then return col2, childName end
        local full = safe_index(mq_parse(('${Window[%s].Child[%s].List[=%s]}'):format(wndName, childName, name), -1))
        if full >= 0 then return full, childName end
    end
    return -1, ''
end

local function select_itemlist_index(idx)
    idx = safe_index(idx)
    if idx < 0 then return false end
    local wndName = merchant_window_name()
    local childName = active_list_child_name()
    mq.cmdf('/squelch /notify %s %s listselect %d', wndName, childName, idx)
    wait(120)
    if merchant_buy_button_enabled() then return true end
    mq.cmdf('/squelch /notify %s %s leftmouse %d', wndName, childName, idx)
    wait(120)
    return merchant_buy_button_enabled()
end

local function dump_window_itemlist(rows)
    rows = tonumber(rows) or 120
    rows = math.max(10, math.min(600, math.floor(rows)))
    local childName = active_list_child_name()
    local itemList = merchant_window(childName)
    if not itemList then
        log(('ERROR: Window[<merchant>/%s] not available.'):format(childName))
        return
    end

    local out = {}
    out[#out + 1] = '=== UEQCredit Window ItemList Dump ==='
    out[#out + 1] = 'time=' .. os.date('%Y-%m-%d %H:%M:%S')
    out[#out + 1] = 'child=' .. tostring(childName)
    out[#out + 1] = 'items=' .. tostring(safe_num(safe_eval(function() return itemList.Items() end, 0)))
    out[#out + 1] = 'format: row | c0 | c1 | c2(name) | c3'
    for i = 0, rows - 1 do
        local c0 = normalize_null_text(safe_eval(function() return itemList.List(i, 0) end, ''))
        local c1 = normalize_null_text(safe_eval(function() return itemList.List(i, 1) end, ''))
        local c2 = normalize_null_text(safe_eval(function() return itemList.List(i, 2) end, ''))
        local c3 = normalize_null_text(safe_eval(function() return itemList.List(i, 3) end, ''))
        out[#out + 1] = string.format('%d | %s | %s | %s | %s', i, c0, c1, c2, c3)
    end
    local path = mq.luaDir .. '/ueqcredit_win_itemlist_' .. os.date('%Y%m%d_%H%M%S') .. '.txt'
    if write_lines(path, out) then
        log(('Dumped window itemlist to: %s'):format(path))
    else
        log('ERROR: Failed to write window itemlist dump.')
    end
end

local function get_merchant_list_child()
    local w = merchant_window()
    if not w then return nil, nil end
    for _, childName in ipairs(LIST_CHILD_CANDIDATES) do
        local list = w.Child and w.Child(childName)
        if list then return list, childName end
    end
    return nil, nil
end

local function merchant_items_count()
    local m = mq.TLO.Merchant
    return safe_num(m and m.Items and m.Items())
end

local function wait_for_merchant_ready(openTimeoutMs, itemsTimeoutMs)
    openTimeoutMs = tonumber(openTimeoutMs) or 3000
    itemsTimeoutMs = tonumber(itemsTimeoutMs) or 10000

    local elapsed = 0
    while elapsed < openTimeoutMs do
        if safe_bool(mq.TLO.Merchant and mq.TLO.Merchant.Open and mq.TLO.Merchant.Open()) then
            break
        end
        wait(100)
        elapsed = elapsed + 100
    end

    elapsed = 0
    while elapsed < itemsTimeoutMs do
        if merchant_items_received() then return true end
        wait(100)
        elapsed = elapsed + 100
    end
    return merchant_items_received()
end

local function merchant_selected_item_name()
    local m = mq.TLO.Merchant
    if not m then return '' end
    local si = m.SelectedItem
    if si and safe_eval(function() return si() end, false) then
        local n = safe_eval(function()
            if si.Name then return si.Name() end
            return ''
        end, '')
        n = strip_item_text(tostring(n))
        if n ~= '' and n ~= 'NULL' then return n end
    end
    --- NewPointMerchant / some emu builds leave SelectedItem Lua Name() empty — parse only (no Window.Child[..].Text: many builds expose Child as int and spam No such 'int' member 'Text').
    local via = strip_item_text(tostring(mq_parse('${Merchant.SelectedItem.Name}', '') or ''))
    if via ~= '' and via ~= 'NULL' then return via end

    return ''
end

local function merchant_selected_item_id()
    local m = mq.TLO.Merchant
    if not m then return 0 end
    local si = m.SelectedItem
    if not si or not si() then return 0 end
    return safe_num(si.ID and si.ID())
end

local function merchant_buy_button_enabled()
    local w = merchant_window()
    if not w then return false end
    for _, childName in ipairs(BUY_BUTTON_CANDIDATES) do
        local enabled = safe_eval(function()
            local c = w.Child and w.Child(childName)
            return c and c.Enabled and c.Enabled()
        end, false)
        if safe_bool(enabled) then return true end
    end
    return false
end

local function merchant_has_manual_selection()
    return merchant_buy_button_enabled()
end

local function selected_label_text()
    -- Avoid .Text parsing here: on some clients these controls evaluate as ints and spam "No such 'int' member 'Text'".
    -- Merchant.SelectedItem.Name is reliable for our matching checks.
    return merchant_selected_item_name()
end

local function selected_item_matches_target()
    local lbl = selected_label_text()
    if lbl == '' then return false end
    return lbl:lower() == get_target_item_name():lower()
end

local function select_via_e3next_pattern(itemName)
    local target = strip_item_text(itemName or '')
    if target == '' then return false, -1 end

    local listPosition, listChild = window_itemlist_find_index(target)
    if listPosition < 0 then
        return false, -1
    end
    if listChild == '' then listChild = active_list_child_name() end

    local buying = selected_label_text()
    local counter = 0
    while buying:lower() ~= target:lower() and counter < 10 do
        counter = counter + 1
        local wndName = merchant_window_name()
        mq.cmdf('/nomodkey /notify %s %s listselect %d', wndName, listChild, listPosition)
        wait(200)
        buying = selected_label_text()
    end

    if buying:lower() ~= target:lower() then
        return false, listPosition
    end

    wait(300)
    if not merchant_buy_button_enabled() then
        return false, listPosition
    end
    return true, listPosition
end

local function merchant_item_lookup(name)
    local exact = safe_eval(function() return mq.TLO.Merchant.Item('=' .. tostring(name)) end, nil)
    local exactOk = safe_eval(function() return exact and exact() end, false)
    if exactOk then return true, exact, true end
    local partial = safe_eval(function() return mq.TLO.Merchant.Item(tostring(name)) end, nil)
    local partialOk = safe_eval(function() return partial and partial() end, false)
    return partialOk, partial, false
end

local function notify_select_index(childName, idx, method)
    idx = tonumber(idx) or 0
    if idx < 1 then return false end
    method = tostring(method or 'listselect')
    local wndName = merchant_window_name()
    if method == 'leftmouse' then
        mq.cmdf('/squelch /notify %s %s leftmouse %d', wndName, childName, idx)
        wait(80)
        return merchant_buy_button_enabled()
    end

    mq.cmdf('/squelch /notify %s %s listselect %d', wndName, childName, idx)
    wait(80)
    if merchant_buy_button_enabled() then return true end
    -- fallback click style
    mq.cmdf('/squelch /notify %s %s leftmouse %d', wndName, childName, idx)
    wait(80)
    return merchant_buy_button_enabled()
end

--- ItemLink on many builds is empty until that row is the merchant's selected item — read from SelectedItem.
local function selected_merchant_item_link()
    local m = mq.TLO.Merchant
    if not m then return '' end
    local si = m.SelectedItem
    if not si or not safe_eval(function() return si() end, false) then return '' end
    local meta = read_item_meta_from_tlo(si)
    local s = strip_item_text(tostring(meta.itemLink or ''))
    if s ~= '' and s ~= 'NULL' then return s end
    s = strip_item_text(tostring(mq_parse('${Merchant.SelectedItem.ItemLink}', '') or ''))
    if s ~= '' and s ~= 'NULL' then return s end
    s = strip_item_text(tostring(mq_parse('${Merchant.SelectedItem.ItemLink[CLICKABLE]}', '') or ''))
    if s ~= '' and s ~= 'NULL' then return s end
    return ''
end

--- True when EQ item examine / display window is up (not the Lua overlay).
local function item_display_window_open()
    for _, wname in ipairs({ 'ItemDisplayWindow', 'ItemDisplayWnd' }) do
        local w = mq.TLO.Window(wname)
        if w and safe_bool(safe_eval(function() return w.Open and w.Open() end, false)) then
            return true
        end
    end
    for i = 1, 6 do
        for _, base in ipairs({ 'ItemDisplayWindow', 'ItemDisplayWnd' }) do
            local w = mq.TLO.Window(base .. i)
            if w and safe_bool(safe_eval(function() return w.Open and w.Open() end, false)) then
                return true
            end
        end
    end
    return false
end

--- Close item inspect popups so success detection is not fooled by a stale window (wrong item / no row change).
local function close_item_inspect_displays()
    local function try_close(name)
        pcall(function()
            local w = mq.TLO.Window(name)
            if w and w() and w.Open and w.Open() and w.DoClose then w.DoClose() end
        end)
    end
    for _, n in ipairs({ 'ItemDisplayWindow', 'ItemDisplayWnd' }) do
        try_close(n)
    end
    for i = 1, 6 do
        try_close('ItemDisplayWindow' .. i)
        try_close('ItemDisplayWnd' .. i)
    end
    wait(90)
end

local function merchant_selection_matches_entry(entry)
    local want = strip_item_text(entry.name or ''):lower()
    if want == '' then return false end
    local got = strip_item_text(merchant_selected_item_name()):lower()
    if got == '' then return false end
    if got == want then return true end
    if got:find(want, 1, true) or want:find(got, 1, true) then return true end
    return false
end

--- Vendor SelectedItem name must equal UI row (substring matching caused wrong-row targets).
local function merchant_selected_name_strict_matches(entry)
    local want = strip_item_text(entry.name or ''):lower()
    local got = strip_item_text(merchant_selected_item_name()):lower()
    return want ~= '' and got == want
end

local function merchant_item_name_at_line(idx1)
    idx1 = tonumber(idx1)
    if not idx1 or idx1 < 1 then return '' end
    return strip_item_text(tostring(mq_parse(string.format('${Merchant.Item[%d].Name}', idx1), '') or ''))
end

--- Read visible list cell text for row (same source as LOAD MERCHANT LIST).
local function merchant_row_cell_equals_name(wndName, listChild, row0, wantLower)
    if not wndName or listChild == '' or row0 == nil or row0 < 0 then return false end
    wantLower = strip_item_text(tostring(wantLower or '')):lower()
    if wantLower == '' then return false end
    for col = 0, 3 do
        local expr = ('${Window[%s].Child[%s].List[%d,%d]}'):format(wndName, listChild, row0, col)
        local t = strip_item_text(tostring(mq_parse(expr, '') or '')):lower()
        if t == wantLower then return true end
    end
    return false
end

--- NewPointMerchant often leaves SelectedItem empty AND Merchant.Item[=name].Name is NULL on emu — still OK if Window.List matched the row.
--- rowList0: 0-based list row (same index family as get_merchant_list_child / LOAD MERCHANT LIST).
local function merchant_selection_verified_for_inspect(entry, rowList0, wndName, listChild)
    local want = strip_item_text(entry.name or ''):lower()
    if want == '' then return false end
    if merchant_selected_name_strict_matches(entry) then return true end

    local esc = strip_item_text(entry.name or ''):gsub('%]', '')
    local byLookup = strip_item_text(tostring(mq_parse(('${Merchant.Item[=%s].Name}'):format(esc), '') or '')):lower()
    if byLookup ~= '' and byLookup ~= 'null' and byLookup == want then return true end

    if rowList0 >= 0 then
        for _, idx1 in ipairs({ rowList0 + 1, rowList0, rowList0 + 2 }) do
            if idx1 >= 1 then
                local nm = merchant_item_name_at_line(idx1):lower()
                if nm ~= '' and nm ~= 'null' and nm == want then return true end
            end
        end
    end

    if rowList0 >= 0 and wndName and listChild and listChild ~= '' then
        if merchant_row_cell_equals_name(wndName, listChild, rowList0, want) then return true end
        if merchant_row_cell_equals_name(wndName, listChild, rowList0 + 1, want) then return true end
    end

    return false
end

--- MQ list line ops: one indexed notify per try — rightmouse+rightmouseup both fire inspect and double-open the same row.
local function merchant_list_try_row_rightclick(wndName, childName, n)
    n = math.floor(tonumber(n) or 0)
    if n < 1 then return false end
    pcall(function()
        mq.cmdf('/nomodkey /notify %s %s rightmouse %d', wndName, childName, n)
    end)
    wait(130)
    if item_display_window_open() then return true end
    return false
end

local function merchant_list_try_row_rightclick_variants(wndName, childName, baseIdx, narrow)
    baseIdx = math.floor(tonumber(baseIdx) or 0)
    local deltas = narrow and { 0, 1, -1 } or { 0, 1, -1, 2, -2 }
    local seen = {}
    local function try_one(x)
        x = math.floor(x)
        if x < 1 or seen[x] then return false end
        seen[x] = true
        return merchant_list_try_row_rightclick(wndName, childName, x)
    end
    for _, d in ipairs(deltas) do
        if try_one(baseIdx + d) then return true end
    end
    if baseIdx == 0 then
        if try_one(1) then return true end
    end
    return false
end

--- Simulate a real right-click on the NPC merchant list at row Y (coordinates hit the EQ control, not this UI).
local function merchant_list_rightclick_row_pixels(wndName, childName, row0based)
    local w = merchant_window()
    if not w then return false end
    local c = w.Child and w.Child(childName)
    if not c then return false end
    local width = safe_num(c.Width and c.Width())
    local height = safe_num(c.Height and c.Height())
    if width <= 8 or height <= 8 then return false end
    local nItems = safe_num(c.Items and c.Items())
    if nItems <= 0 then nItems = math.max(8, (tonumber(row0based) or 0) + 4) end
    local rowH = math.max(13, math.floor(height / math.min(nItems, 100)))
    local x = math.max(10, math.floor(width * 0.38))
    row0based = math.max(0, math.floor(tonumber(row0based) or 0))

    local function y_for_row(rb)
        local y = 12 + rb * rowH + math.floor(rowH / 2)
        return math.min(height - 4, math.max(8, y))
    end

    for _, dy in ipairs({ 0, -1, 1, -2, 2 }) do
        local rb = math.max(0, row0based + dy)
        local y = y_for_row(rb)
        pcall(function()
            mq.cmdf('/nomodkey /notify %s %s rightmouseup %d %d', wndName, childName, x, y)
        end)
        wait(100)
        if item_display_window_open() then return true end
    end
    return false
end

--- /executelink and ExecuteTextLink simulate a click; bring EQ to the foreground so it does not hit the ImGui overlay.
local function focus_eq_for_synthetic_link_click()
    pcall(function() mq.cmd('/foreground') end)
    wait(80)
end

--- Run ItemLink / chat link text through MQ (picker cache, catalog, or MQ resolve — does not require Merchant.SelectedItem text).
local function try_execute_any_item_link_text(linkStr, logLine)
    linkStr = strip_item_text(tostring(linkStr or ''))
    if linkStr == '' or linkStr == 'NULL' then return false end
    if not mq or not mq.ExecuteTextLink then return false end
    local links = mq.ExtractLinks and mq.ExtractLinks(linkStr) or nil
    focus_eq_for_synthetic_link_click()
    if links and #links > 0 then
        mq.ExecuteTextLink(links[1])
        log(logLine or 'UEQCredit: opened item link')
        return true
    end
    local ok = pcall(function() mq.ExecuteTextLink(linkStr) end)
    if ok then
        log(logLine or 'UEQCredit: opened item link')
        return true
    end
    return false
end

--- After Merchant.SelectedItem matches the target row, MQ often exposes ItemLink — open without /notify (some list widgets reject rightmouseup).
local function try_execute_merchant_selected_item_link(logLine)
    local link = strip_item_text(tostring(selected_merchant_item_link() or ''))
    if link == '' or link == 'NULL' then return false end
    if not mq or not mq.ExecuteTextLink then return false end
    local links = mq.ExtractLinks and mq.ExtractLinks(link) or nil
    if not links or #links == 0 then return false end
    focus_eq_for_synthetic_link_click()
    mq.ExecuteTextLink(links[1])
    log(logLine or 'UEQCredit: opened via Merchant.SelectedItem link')
    return true
end

--- Open inspect: foreground → SelectItem (exact) → optional exact listselect → right-click THAT row on vendor UI only.
local function open_merchant_item_link(entry)
    if not entry or not entry.name or entry.name == '' then return end

    pcall(function() mq.cmd('/foreground') end)
    wait(50)
    close_item_inspect_displays()

    local wnd = merchant_window_name()
    local child = (entry.child and entry.child ~= '') and entry.child or active_list_child_name()
    if child == '' then
        log('UEQCredit: keep vendor window open and click LOAD MERCHANT LIST.')
        return
    end

    local want = strip_item_text(entry.name)
    local esc = want:gsub('%]', '')
    local rowExact, childExact = window_itemlist_find_row_exact(want)
    local useChild = (childExact ~= '' and childExact) or child
    local rowScrape = tonumber(entry.row)

    --- Picker row comes from the same List(row,col) scrape as LOAD MERCHANT LIST. ${Window...List[=%s]} often returns row 0 on NewPointMerchantWnd — must NOT override a correct scraped index or every click hits the first NPC line (e.g. Blastwave Wand).
    local rowPrimary0 = nil
    if rowScrape ~= nil and rowScrape >= 0 then
        rowPrimary0 = math.floor(rowScrape)
    elseif rowExact >= 0 then
        rowPrimary0 = math.floor(rowExact)
    end
    if rowExact >= 0 and rowPrimary0 ~= nil and rowScrape ~= nil and rowScrape >= 0 and rowExact ~= rowPrimary0 then
        dbg(('UEQCredit: Window List[=%s] idx %d vs scraped row %d — using scraped'):format(want, rowExact, rowPrimary0))
    end

    local rowProbe = -1
    if rowPrimary0 ~= nil then rowProbe = rowPrimary0 elseif rowExact >= 0 then rowProbe = rowExact end

    mq.cmdf('/invoke ${Merchant.SelectItem[=%s]}', esc)
    wait(110)

    local ok = merchant_selection_verified_for_inspect(entry, rowProbe, wnd, useChild)
    if not ok and rowProbe >= 0 then
        mq.cmdf('/nomodkey /notify %s %s listselect %d', wnd, useChild, rowProbe)
        wait(90)
        ok = merchant_selection_verified_for_inspect(entry, rowProbe, wnd, useChild)
    end
    if not ok and rowProbe >= 0 then
        mq.cmdf('/nomodkey /notify %s %s listselect %d', wnd, useChild, rowProbe + 1)
        wait(90)
        ok = merchant_selection_verified_for_inspect(entry, rowProbe, wnd, useChild)
    end

    --- Window.List already mapped this name to rowExact; Merchant.Item[=].Name is often NULL on emu — still proceed.
    if not ok and rowProbe >= 0 then
        ok = true
    end

    if not ok then
        if rowProbe < 0 and (rowScrape == nil or rowScrape < 0) and rowExact < 0 then
            log(('UEQCredit: vendor window has no List line matching "%s" exactly — spelling must match the NPC list (check typos vs game text).'):format(want))
        else
            log(('UEQCredit: could not open inspect for "%s" (listselect/verify failed).'):format(want))
        end
        return
    end

    --- Indexed right-click: same line numbering as listselect + 1 for /notify … rightmouse N on most builds (see stepBuyOne listselect vs row).
    local baseNotify = 1
    if rowPrimary0 ~= nil then
        baseNotify = rowPrimary0 + 1
    end

    --- When we know the picker row, hit exactly that line — variants were opening neighbors that still raise ItemDisplay (wrong item, looks like "stuck on first row").
    local clickedRow = false
    if rowPrimary0 ~= nil then
        clickedRow = merchant_list_try_row_rightclick(wnd, useChild, baseNotify)
    end
    if not clickedRow then
        clickedRow = merchant_list_try_row_rightclick_variants(wnd, useChild, baseNotify, rowPrimary0 ~= nil)
    end
    if clickedRow then
        log(('UEQCredit: inspect — vendor list row (%s)'):format(want))
        return
    end

    local rowPix = rowPrimary0 or rowExact
    if rowPix == nil or rowPix < 0 then rowPix = tonumber(rowScrape) or 0 end
    if merchant_list_rightclick_row_pixels(wnd, useChild, rowPix) then
        log(('UEQCredit: inspect — vendor pixel (%s)'):format(want))
        return
    end

    if merchant_selected_name_strict_matches(entry) and try_execute_merchant_selected_item_link('UEQCredit: opened via ItemLink') then
        return
    end

    if not mq or not mq.ExecuteTextLink then
        log('UEQCredit: ExecuteTextLink unavailable; item window did not open.')
        return
    end

    local meta = resolve_merchant_item_meta(entry.name, entry.row, true)
    local link = strip_item_text(tostring(meta.itemLink or ''))
    if link == '' or link == 'NULL' then
        link = strip_item_text(tostring(entry.itemLink or ''))
    end
    if link == '' or link == 'NULL' then
        link = strip_item_text(tostring(selected_merchant_item_link() or ''))
    end
    if link == '' or link == 'NULL' then
        meta = resolve_merchant_item_meta(entry.name, entry.row, true)
        link = strip_item_text(tostring(meta.itemLink or ''))
    end
    if link == '' or link == 'NULL' then
        local cat = catalog_lookup_item(want)
        if cat and cat.raw then
            link = strip_item_text(tostring(catalog_field(cat.raw, 'itemlink', 'ItemLink', 'link', 'chatlink') or ''))
        end
    end
    if link == '' or link == 'NULL' then
        log(('UEQCredit: no ItemLink for "%s" after vendor click (MQ emu often has no Item() link — add items.json or LinkDB).'):format(want))
        return
    end
    --- Do not require Merchant.SelectedItem.Name here: NewPoint leaves it empty; strict match blocked catalog/MQ links.
    if try_execute_any_item_link_text(link, ('UEQCredit: ItemLink — %s'):format(want)) then
        return
    end
    log(('UEQCredit: bad ItemLink text for "%s"'):format(want))
end

local function queue_open_merchant_item_link(entry)
    if not entry or not entry.name or entry.name == '' then return end
    pendingItemLinkEntry = {
        name = entry.name,
        row = tonumber(entry.row),
        child = entry.child,
        itemLink = entry.itemLink,
    }
end

local function process_pending_item_link()
    if not pendingItemLinkEntry then return end
    local entry = pendingItemLinkEntry
    pendingItemLinkEntry = nil
    local ok, err = pcall(function()
        open_merchant_item_link(entry)
    end)
    if not ok then
        log('UEQCredit: open item link failed: ' .. tostring(err))
    end
end

local function try_select_via_mq_expr(control, itemName)
    local name = tostring(itemName or '')
    if name == '' then return false end

    local wndName = merchant_window_name()
    local exprs = {
        ('${Window[%s].Child[%s].List[=%s]}'):format(wndName, control, name),
        ('${Window[%s].Child[%s].List[%s]}'):format(wndName, control, name),
        ('${Window[%s].Child[%s].List[=%s,1]}'):format(wndName, control, name),
        ('${Window[%s].Child[%s].List[%s,1]}'):format(wndName, control, name),
    }

    for _, expr in ipairs(exprs) do
        mq.cmd('/squelch /notify ' .. wndName .. ' ' .. control .. ' listselect ' .. expr)
        wait(120)
        if merchant_buy_button_enabled() then
            log(('Selected via MQ expr on %s: %s'):format(control, expr))
            return true
        end
    end
    return false
end

local function select_probe_by_label(itemName, maxIdx)
    itemName = strip_item_text(itemName or '')
    if itemName == '' then return false, -1, '' end
    maxIdx = tonumber(maxIdx) or 120
    maxIdx = math.max(20, math.min(400, math.floor(maxIdx)))

    local wndName = merchant_window_name()
    local controls = NOTIFY_LIST_CANDIDATES
    for _, control in ipairs(controls) do
        for idx = 1, maxIdx do
            mq.cmdf('/squelch /notify %s %s listselect %d', wndName, control, idx)
            wait(90)
            local lbl = selected_label_text()
            local buy = merchant_buy_button_enabled()
            if lbl ~= '' then
                dbg(('selprobe control=%s idx=%d label="%s" buy=%s'):format(control, idx, lbl, tostring(buy)))
            end
            if lbl:lower():find(itemName:lower(), 1, true) then
                return true, idx, control
            end
        end
    end
    return false, -1, ''
end

local function dump_selection_probe(maxIdx)
    maxIdx = tonumber(maxIdx) or 120
    maxIdx = math.max(20, math.min(400, math.floor(maxIdx)))
    local out = {}
    out[#out + 1] = '=== UEQCredit Selection Probe ==='
    out[#out + 1] = 'time=' .. os.date('%Y-%m-%d %H:%M:%S')
    out[#out + 1] = 'maxIdx=' .. tostring(maxIdx)
    out[#out + 1] = 'control\tidx\tbuyEnabled\tlabel'

    local wndName = merchant_window_name()
    local controls = NOTIFY_LIST_CANDIDATES
    for _, control in ipairs(controls) do
        for idx = 1, maxIdx do
            mq.cmdf('/squelch /notify %s %s listselect %d', wndName, control, idx)
            wait(75)
            local lbl = selected_label_text()
            local buy = merchant_buy_button_enabled()
            out[#out + 1] = string.format('%s\t%d\t%s\t%s', control, idx, tostring(buy), lbl ~= '' and lbl or '<none>')
        end
    end

    local path = mq.luaDir .. '/ueqcredit_selprobe_' .. os.date('%Y%m%d_%H%M%S') .. '.txt'
    if write_lines(path, out) then
        log(('Dumped selection probe to: %s'):format(path))
    else
        log('ERROR: Failed to write selection probe file.')
    end
end

local function snapshot_path()
    local ts = os.date('%Y%m%d_%H%M%S')
    return mq.luaDir .. '/ueqcredit_merchant_dump_' .. ts .. '.txt'
end

local function write_lines(path, lines)
    local f = io.open(path, 'w')
    if not f then return false end
    for i = 1, #lines do
        f:write(lines[i], '\n')
    end
    f:close()
    return true
end

local function list_cell_text(list, row, col)
    if not list or not list.List then return '' end
    local v
    if col == nil then v = list.List(row) else v = list.List(row, col) end
    return normalize_null_text(v)
end

local function build_row_line(base, row, cells)
    return string.format('%s[%d] raw="%s" c0="%s" c1="%s" c2="%s" c3="%s"',
        base, row, cells.raw or '', cells.c0 or '', cells.c1 or '', cells.c2 or '', cells.c3 or '')
end

local function refresh_ui_merchant_items(maxRows)
    maxRows = tonumber(maxRows) or 200
    maxRows = math.max(20, math.min(600, math.floor(maxRows)))
    uiMerchantItems = {}
    uiSelectedItemIndex = -1

    local list, child = get_merchant_list_child()
    if not list then
        log('ERROR: No merchant list control found for UI list.')
        return 0
    end

    local seen = {}
    for row = 0, maxRows - 1 do
        local c0 = list_cell_text(list, row, 0)
        local c1 = list_cell_text(list, row, 1)
        local c2 = list_cell_text(list, row, 2)
        local c3 = list_cell_text(list, row, 3)
        local raw = list_cell_text(list, row, nil)
        -- Prefer the first column that looks like an item name (contains letters),
        -- then fall back to any non-empty text.
        local function has_letters(s) return s and s:match('%a') ~= nil end
        local name = ''
        if has_letters(c2) then name = c2
        elseif has_letters(c1) then name = c1
        elseif has_letters(c0) then name = c0
        elseif has_letters(c3) then name = c3
        elseif has_letters(raw) then name = raw
        end
        if name == '' then
            if c2 ~= '' then name = c2
            elseif c1 ~= '' then name = c1
            elseif c0 ~= '' then name = c0
            elseif c3 ~= '' then name = c3
            else name = raw end
        end
        name = strip_item_text(name)
        local priceUi = infer_merchant_row_price(c0, c1, c2, c3)
        if name ~= '' and not seen[name:lower()] then
            seen[name:lower()] = true
            local meta = resolve_merchant_item_meta(name, row)
            local price = priceUi
            if meta.vendorPrice and meta.vendorPrice > 0 then
                price = tostring(math.floor(meta.vendorPrice + 0.5))
            elseif priceUi ~= '' then
                price = priceUi
            end
            uiMerchantItems[#uiMerchantItems + 1] = {
                row = row,
                name = name,
                price = price,
                child = child or '',
                id = meta.id,
                icon = meta.icon,
                itemLink = meta.itemLink,
                catalogRaw = meta.catalogRaw,
            }
            if name:lower() == get_target_item_name():lower() then
                uiSelectedItemIndex = #uiMerchantItems
            end
        end
    end

    refresh_currency_detection()
    --- Preserve checkbox flags by row index where list length matches; otherwise trim/pad.
    local newChk = {}
    for i = 1, #uiMerchantItems do
        newChk[i] = buyQueueChecked[i] == true
    end
    buyQueueChecked = newChk

    dbg(('Loaded %d merchant rows.'):format(#uiMerchantItems))
    return #uiMerchantItems
end

local function dump_list_matrix(maxRows)
    maxRows = tonumber(maxRows) or 120
    maxRows = math.max(10, math.min(400, math.floor(maxRows)))

    local list, child = get_merchant_list_child()
    if not list then
        log('ERROR: No merchant list child found for dump.')
        return
    end

    local out = {}
    out[#out + 1] = '=== UEQCredit Merchant List Matrix Dump ==='
    out[#out + 1] = 'time=' .. os.date('%Y-%m-%d %H:%M:%S')
    out[#out + 1] = 'child=' .. tostring(child)
    out[#out + 1] = 'items=' .. tostring(safe_num(list.Items and list.Items()))
    out[#out + 1] = 'merchant_items_tlo=' .. tostring(merchant_items_count())
    out[#out + 1] = 'merchant_items_received=' .. tostring(merchant_items_received())
    out[#out + 1] = '-- 0-based rows --'

    for row = 0, maxRows - 1 do
        local cells = {
            raw = list_cell_text(list, row, nil),
            c0 = list_cell_text(list, row, 0),
            c1 = list_cell_text(list, row, 1),
            c2 = list_cell_text(list, row, 2),
            c3 = list_cell_text(list, row, 3),
        }
        out[#out + 1] = build_row_line('r0', row, cells)
    end

    out[#out + 1] = '-- 1-based rows --'
    for row = 1, maxRows do
        local cells = {
            raw = list_cell_text(list, row, nil),
            c0 = list_cell_text(list, row, 0),
            c1 = list_cell_text(list, row, 1),
            c2 = list_cell_text(list, row, 2),
            c3 = list_cell_text(list, row, 3),
        }
        out[#out + 1] = build_row_line('r1', row, cells)
    end

    local path = snapshot_path()
    if write_lines(path, out) then
        log(('Dumped merchant list matrix to: %s'):format(path))
        dbg('Preview: ' .. (out[7] or ''))
        dbg('Preview: ' .. (out[8] or ''))
        dbg('Preview: ' .. (out[9] or ''))
    else
        log('ERROR: Failed to write merchant list matrix dump file.')
    end
end

local function dump_probe_indexes(maxIdx)
    maxIdx = tonumber(maxIdx) or 200
    maxIdx = math.max(20, math.min(600, math.floor(maxIdx)))

    local out = {}
    out[#out + 1] = '=== UEQCredit Merchant Index Probe ==='
    out[#out + 1] = 'time=' .. os.date('%Y-%m-%d %H:%M:%S')
    out[#out + 1] = 'children=' .. table.concat(NOTIFY_LIST_CANDIDATES, ',')
    out[#out + 1] = 'maxIdx=' .. tostring(maxIdx)
    out[#out + 1] = 'control\tmethod\tidx\tbuyEnabled\tselectedId\tselectedName'
    log(('Probelist started: controls=%s max=%d'):format(table.concat(NOTIFY_LIST_CANDIDATES, ','), maxIdx))

    local function add_probe(control, method, idx)
        local ok = notify_select_index(control, idx, method)
        local sid = merchant_selected_item_id()
        local sname = merchant_selected_item_name()
        if sname == '' then sname = '<none>' end
        out[#out + 1] = string.format('%s\t%s\t%d\t%s\t%d\t%s', control, method, idx, tostring(ok), sid, sname)
    end

    local methods = { 'listselect', 'leftmouse' }
    for _, control in ipairs(NOTIFY_LIST_CANDIDATES) do
        for _, method in ipairs(methods) do
            for idx = 1, maxIdx do
                add_probe(control, method, idx)
                if (idx % 25) == 0 then
                    log(('Probelist progress: %s/%s %d/%d'):format(control, method, idx, maxIdx))
                end
            end
        end
    end

    local path = snapshot_path():gsub('dump', 'probe')
    if write_lines(path, out) then
        log(('Dumped merchant index probe to: %s'):format(path))
        log('Probelist complete.')
    else
        log('ERROR: Failed to write merchant index probe dump file.')
    end
end

local function dump_probe_coords(stepY)
    stepY = tonumber(stepY) or 16
    stepY = math.max(4, math.min(40, math.floor(stepY)))

    local w, wndName = merchant_window()
    if not w then
        log('ERROR: Merchant window not found for coord probe.')
        return
    end

    local out = {}
    out[#out + 1] = '=== UEQCredit Merchant Coord Probe ==='
    out[#out + 1] = 'time=' .. os.date('%Y-%m-%d %H:%M:%S')
    out[#out + 1] = 'stepY=' .. tostring(stepY)
    out[#out + 1] = 'control\tx\ty\tbuyEnabled\tselectedId\tselectedName'

    local function probe_control(control)
        local c = w.Child and w.Child(control)
        if not c then
            out[#out + 1] = string.format('%s\t%s\t%s\t%s\t%s\t%s', control, '-', '-', 'false', '0', '<no-control>')
            return
        end

        local width = safe_num(c.Width and c.Width())
        local height = safe_num(c.Height and c.Height())
        local x = math.max(8, math.floor(width * 0.35))
        if height <= 0 then height = 320 end

        out[#out + 1] = string.format('%s\tmeta\tw=%d\th=%d\t-\t-', control, width, height)
        local maxY = math.max(24, height - 8)
        for y = 8, maxY, stepY do
            mq.cmdf('/squelch /notify %s %s leftmouseup %d %d', wndName, control, x, y)
            wait(90)
            local be = merchant_buy_button_enabled()
            local sid = merchant_selected_item_id()
            local sname = merchant_selected_item_name()
            if sname == '' then sname = '<none>' end
            out[#out + 1] = string.format('%s\t%d\t%d\t%s\t%d\t%s', control, x, y, tostring(be), sid, sname)
        end
    end

    for _, control in ipairs(NOTIFY_LIST_CANDIDATES) do
        probe_control(control)
    end

    local path = mq.luaDir .. '/ueqcredit_merchant_coordprobe_' .. os.date('%Y%m%d_%H%M%S') .. '.txt'
    if write_lines(path, out) then
        log(('Dumped merchant coord probe to: %s'):format(path))
    else
        log('ERROR: Failed to write merchant coord probe file.')
    end
end

local function dump_window_tree_file()
    local w, wndName = merchant_window()
    if not w then
        log('ERROR: Merchant window not found for tree file dump.')
        return
    end

    local lines = {}
    local function walk(win, depth, maxDepth)
        if not win or depth > maxDepth then return end
        local indent = string.rep(' ', depth * 2)
        local name = tostring(safe_eval(function() return win.Name and win.Name() end, '<?>'))
        local sid = tostring(safe_eval(function() return win.ScreenID and win.ScreenID() end, '<?>'))
        local wtype = tostring(safe_eval(function() return win.Type and win.Type() end, '<?>'))
        local items = tonumber(safe_eval(function() return win.Items and win.Items() end, -1)) or -1
        lines[#lines + 1] = ('%s%s | ScreenID=%s Type=%s Items=%d'):format(indent, name, sid, wtype, items)
        local c = safe_eval(function() return win.FirstChild and win.FirstChild() end, nil)
        local guard = 0
        while c and guard < 500 do
            walk(c, depth + 1, maxDepth)
            c = safe_eval(function() return c.Next and c.Next() end, nil)
            guard = guard + 1
        end
    end

    lines[#lines + 1] = '=== Merchant Window Tree File Dump ==='
    lines[#lines + 1] = 'window=' .. tostring(wndName)
    lines[#lines + 1] = 'time=' .. os.date('%Y-%m-%d %H:%M:%S')
    local ok, err = xpcall(function()
        walk(w, 0, 8)
    end, function(e) return debug.traceback(e, 2) end)
    if not ok then
        log('ERROR: dumpwintree failed: ' .. tostring(err))
        return
    end

    local path = mq.luaDir .. '/ueqcredit_merchant_tree_' .. os.date('%Y%m%d_%H%M%S') .. '.txt'
    if write_lines(path, lines) then
        log(('Dumped merchant tree to: %s'):format(path))
    else
        log('ERROR: Failed to write merchant tree dump file.')
    end
end

------------------------------------------------------------
-- BUY STEPS
------------------------------------------------------------
local function stepTarget()
    local filter = strip_item_text(NPC_NAME)
    if filter == '' then
        local tid = mq.TLO.Target and mq.TLO.Target.ID and mq.TLO.Target.ID() or 0
        if tid <= 0 then
            log('ERROR: No NPC_NAME set — target your vendor first, then run buy.')
            return false
        end
        local nm = safe_eval(function() return mq.TLO.Target.CleanName() end, '') or ''
        setStatus('Using current target: ' .. tostring(nm))
        return true
    end

    setStatus('Searching for ' .. filter)
    local sid = 0
    local queries = {
        'npc radius 300 = ' .. filter,
        'npc = ' .. filter,
        'merchant radius 300 = ' .. filter,
        'merchant = ' .. filter,
        'npc radius 300 name ' .. filter,
        'npc name ' .. filter,
    }

    for _, q in ipairs(queries) do
        local s = mq.TLO.NearestSpawn(q)
        sid = s and s.ID and s.ID() or 0
        if sid == 0 then
            s = mq.TLO.Spawn(q)
            sid = s and s.ID and s.ID() or 0
        end
        if sid > 0 then break end
    end

    if sid == 0 then log('ERROR: NPC not found: ' .. filter); return false end
    mq.cmdf('/target id %d', sid)
    wait(700)
    local tid = mq.TLO.Target.ID and mq.TLO.Target.ID() or 0
    if tid ~= sid then log('ERROR: Target failed'); return false end
    setStatus('Targeted ' .. filter)
    return true
end

local function stepOpen()
    setStatus('Opening merchant...')
    log_merchant_state('pre-click')
    local rc_ok = safe_eval(function()
        local t = mq.TLO.Target
        if t and t() and t.RightClick then
            t.RightClick()
            return true
        end
        return false
    end, false)
    if not rc_ok then
        mq.cmd('/click right target')
    end

    local elapsed = 0
    while elapsed < (OPEN_DELAY + 3000) do
        local st = log_merchant_state('open-wait+' .. tostring(elapsed))
        if merchant_ready(st) or safe_bool(mq.TLO.Merchant and mq.TLO.Merchant.Open and mq.TLO.Merchant.Open()) then
            wait_for_merchant_ready(500, 5000)
            setStatus('Merchant open')
            return true
        end
        wait(100)
        elapsed = elapsed + 100
    end

    log('ERROR: Merchant did not open')
    log_merchant_state('open-fail')
    return false
end

local function dump_merchant_inventory(maxRows)
    maxRows = tonumber(maxRows) or 500
    maxRows = math.max(1, math.min(2000, math.floor(maxRows)))

    local out = {}
    out[#out + 1] = '=== UEQCredit Merchant Inventory Dump ==='
    out[#out + 1] = 'time=' .. os.date('%Y-%m-%d %H:%M:%S')
    out[#out + 1] = 'merchant_open=' .. tostring(safe_bool(mq.TLO.Merchant and mq.TLO.Merchant.Open and mq.TLO.Merchant.Open()))
    out[#out + 1] = 'items_received=' .. tostring(merchant_items_received())
    out[#out + 1] = 'items=' .. tostring(merchant_items_count())

    local count = merchant_items_count()
    if count == 0 then
        out[#out + 1] = 'NOTE: Merchant.Items() == 0 on this client/build.'
    end

    local lim = math.min(maxRows, math.max(count, maxRows))
    for i = 1, lim do
        local item = safe_eval(function() return mq.TLO.Merchant.Item(i) end, nil)
        local exists = safe_eval(function() return item and item() end, false)
        if exists then
            local name = safe_eval(function() return item.Name and item.Name() end, '')
            local id = safe_num(safe_eval(function() return item.ID and item.ID() end, 0))
            local val = safe_num(safe_eval(function() return item.Value and item.Value() end, 0))
            local st = safe_num(safe_eval(function() return item.Stack and item.Stack() end, 1))
            out[#out + 1] = string.format('[%d] name="%s" id=%d stack=%d value=%d', i, tostring(name), id, st, val)
        elseif i <= math.max(50, count + 5) then
            out[#out + 1] = string.format('[%d] <empty>', i)
        end
    end

    local path = mq.luaDir .. '/ueqcredit_merchant_items_' .. os.date('%Y%m%d_%H%M%S') .. '.txt'
    if write_lines(path, out) then
        log(('Dumped merchant items to: %s'):format(path))
    else
        log('ERROR: Failed to write merchant items dump file.')
    end
end

local function run_merchant_scan()
    local out = {}
    local function push(line)
        out[#out + 1] = tostring(line)
        log(tostring(line))
    end

    push('=== Merchant Scan ===')
    push('time=' .. os.date('%Y-%m-%d %H:%M:%S'))

    local d0 = merchant_diag_state()
    push(('[scan-start] targetExists=%s targetMerchant=%s wndOpen=%s wndVisible=%s merchantOpen=%s'):format(
        tostring(d0.target_exists), tostring(d0.target_is_merchant), tostring(d0.wnd_open), tostring(d0.wnd_visible), tostring(d0.merchant_open)
    ))

    local hasMerchantContext =
        d0.target_is_merchant
        or d0.wnd_open
        or d0.wnd_visible
        or d0.merchant_open
        or (d0.wnd_exists and d0.target_exists)
        or (tostring(d0.merchant_name or '') ~= '')

    if not hasMerchantContext then
        push('ERROR: No merchant context (target/window/merchant TLO all false).')
        log_merchant_diag('scan-no-context')
        return false
    end

    -- If merchant state is not explicitly open, try right-click on current target anyway.
    -- Some client/server builds report Target.Merchant/Open/Visible unreliably.
    if d0.target_exists and not (d0.wnd_open or d0.wnd_visible or d0.merchant_open) then
        push('Opening merchant with Target.RightClick...')
        safe_eval(function()
            mq.TLO.Target.RightClick()
            return true
        end, false)
        mq.delay(3000, function()
            local d = merchant_diag_state()
            return d.wnd_open or d.wnd_visible or d.merchant_open
        end)
    else
        push('Using existing merchant window/TLO context (no re-open needed).')
    end

    local d1 = merchant_diag_state()
    if not (d1.wnd_open or d1.wnd_visible or d1.merchant_open or (d1.wnd_exists and d1.target_exists)) then
        push('ERROR: Merchant context unavailable before scan.')
        log_merchant_diag('scan-context-lost')
        return false
    end

    push('Waiting for merchant items...')
    mq.delay(8000, function() return merchant_items_received() end)

    local merchantName = safe_eval(function() return mq.TLO.Merchant.CleanName() end, '')
    if merchantName == '' then merchantName = safe_eval(function() return mq.TLO.Target.CleanName() end, '') end
    if merchantName == '' then merchantName = 'Unknown' end

    local itemCount = merchant_items_count()
    push(string.format('Merchant: %s | Merchant.Items=%d | ItemsReceived=%s',
        merchantName, itemCount, tostring(merchant_items_received())))

    if itemCount > 0 then
        push('Reading Merchant.Item(index)...')
        local lim = math.min(itemCount, 80)
        for i = 1, lim do
            local item = safe_eval(function() return mq.TLO.Merchant.Item(i) end, nil)
            local exists = safe_eval(function() return item and item() end, false)
            if exists then
                local nm = safe_eval(function() return item.Name and item.Name() end, '')
                local v = safe_num(safe_eval(function() return item.Value and item.Value() end, 0))
                local id = safe_num(safe_eval(function() return item.ID and item.ID() end, 0))
                push(string.format('  [%d] %s | Price:%d | ID:%d', i, tostring(nm), v, id))
            end
        end
    else
        push('Merchant.Items() returned 0.')
    end

    push('Searching by FindItem / FindItemCount...')
    local itemsToCheck = {
        get_target_item_name(),
        'Augment Upgrade Token III',
        'Augment Upgrade Token II',
        'Ignore Death',
        'Amplify Vulnerability',
        'Ultimate Protection',
        'Superior Lightstone',
        'Hive Shards',
    }

    for _, searchName in ipairs(itemsToCheck) do
        local found = safe_eval(function() return mq.TLO.FindItem(searchName) end, nil)
        local ok = safe_eval(function() return found and found() end, false)
        if not ok then
            local exact = safe_eval(function() return mq.TLO.FindItem('=' .. searchName) end, nil)
            ok = safe_eval(function() return exact and exact() end, false)
            found = exact
        end

        if ok then
            local nm = safe_eval(function() return found.Name and found.Name() end, searchName)
            local v = safe_num(safe_eval(function() return found.Value and found.Value() end, 0))
            push(string.format('FOUND: %s (value~%d)', tostring(nm), v))
        else
            push(string.format('Not found: %s', searchName))
        end
    end

    local c = safe_num(safe_eval(function() return mq.TLO.FindItemCount(get_target_item_name()) end, 0))
    push(string.format('FindItemCount("%s")=%d', get_target_item_name(), c))

    local miOk, miObj, isExact = merchant_item_lookup(get_target_item_name())
    if miOk then
        local nm = safe_eval(function() return miObj.Name and miObj.Name() end, get_target_item_name())
        push(string.format('Merchant.Item lookup success (%s): %s', isExact and 'exact' or 'partial', tostring(nm)))
    else
        push('Merchant.Item lookup failed for target item.')
    end

    local path = mq.luaDir .. '/ueqcredit_merchant_scan_' .. os.date('%Y%m%d_%H%M%S') .. '.txt'
    if write_lines(path, out) then
        log(('Dumped merchant scan to: %s'):format(path))
    else
        log('ERROR: Failed to write merchant scan file.')
    end
    return true
end

local function stepFind()
    local targetItem = get_target_item_name()
    local st = log_merchant_state('find-start')
    if not merchant_ready(st) then
        log('ERROR: Merchant not open')
        return -1
    end

    -- Direct NewPoint flow (macro-style): resolve row index once, select once, no probe loops.
    local wndName = merchant_window_name()
    if wndName == 'NewPointMerchantWnd' then
        local listChild = active_list_child_name()
        local idx = safe_index(mq_parse(('${Window[%s].Child[%s].List[=%s]}'):format(wndName, listChild, targetItem), -1))
        if idx < 0 then
            idx = safe_index(mq_parse(('${Window[%s].Child[%s].List[%s]}'):format(wndName, listChild, targetItem), -1))
        end
        if idx < 0 then
            log(('ERROR: NewPoint item index lookup failed for "%s"'):format(targetItem))
            return -1
        end

        mq.cmdf('/notify %s %s listselect %d', wndName, listChild, idx)
        wait(150)
        log(('Selected from %s at index %d'):format(listChild, idx))
        return idx
    end

    if ALLOW_MANUAL_SELECTED_FALLBACK and merchant_has_manual_selection() and selected_item_matches_target() then
        log('Using manual merchant selection (target item is selected).')
        return 0
    end

    -- Primary path (E3Next/RedGuides ecosystem): list index -> select -> label validate.
    local okE3, idxE3 = select_via_e3next_pattern(targetItem)
    if okE3 then
        log(('Selected via E3 pattern at index %d'):format(idxE3))
        return idxE3
    elseif idxE3 and idxE3 >= 0 then
        log(('E3 pattern found index %d but validation failed.'):format(idxE3))
    end

    setStatus('Trying selection-label probe...')
    local okSel, idxSel, ctlSel = select_probe_by_label(targetItem, 120)
    if okSel then
        log(('Selected via label probe: control=%s idx=%d'):format(ctlSel, idxSel))
        return idxSel
    end

    local list, listChildName = get_merchant_list_child()
    if list then
        local function row_text(row)
            local txt = normalize_null_text(list.List and list.List(row))
            if txt == '' then txt = normalize_null_text(list.List and list.List(row, 0)) end
            if txt == '' then txt = normalize_null_text(list.List and list.List(row, 1)) end
            if txt == '' then txt = normalize_null_text(list.List and list.List(row, 2)) end
            return txt
        end

        local needle = strip_item_text(targetItem):lower()
        local count = safe_num(list.Items and list.Items())
        log(('Merchant list child: %s items:%d'):format(tostring(listChildName), count))

        for row = 0, math.max(60, count + 10) do
            local txt = row_text(row)
            if txt ~= '' then
                dbg(('row[%d]="%s"'):format(row, txt))
                if txt:lower():find(needle, 1, true) then
                    mq.cmdf('/notify %s %s listselect %d', merchant_window_name(), listChildName, row)
                    wait(120)
                    if row_matches_item(list, row, targetItem) then
                        log(('Selected from %s at index %d'):format(listChildName, row))
                        return row
                    end
                end
            end
        end

        -- Some list controls are 1-based.
        for row = 1, 60 do
            local txt = row_text(row)
            if txt ~= '' then
                dbg(('row1[%d]="%s"'):format(row, txt))
                if txt:lower():find(needle, 1, true) then
                    mq.cmdf('/notify %s %s listselect %d', merchant_window_name(), listChildName, row)
                    wait(120)
                    if row_matches_item(list, row, targetItem) or row_matches_item(list, row - 1, targetItem) then
                        log(('Selected from %s at row %d (1-based?)'):format(listChildName, row))
                        return math.max(0, row - 1)
                    end
                end
            end
        end

        -- Last UI fallback: brute-force selectable rows by index, then verify selection via Merchant.SelectedItem.
        local needle = strip_item_text(targetItem):lower()
        setStatus('Trying MQ index probe...')
        for idx = 1, 80 do
            if notify_select_index(listChildName, idx) then
                local selName = merchant_selected_item_name()
                local selId = merchant_selected_item_id()
                if selName ~= '' then
                    dbg(('probe idx=%d selected="%s" id=%d'):format(idx, selName, selId))
                end
                if selName ~= '' and selName:lower():find(needle, 1, true) then
                    log(('Selected from %s by index probe: %d -> %s'):format(listChildName, idx, selName))
                    return idx
                end
            end
        end
    end

    -- New: command-side list expression lookup can work even when Lua list APIs are blind.
    setStatus('Trying MQ expression select...')
    for _, control in ipairs(NOTIFY_LIST_CANDIDATES) do
        if try_select_via_mq_expr(control, targetItem) then
            return 0
        end
    end

    local waited = 0
    while waited <= 4000 and not merchant_items_received() do
        wait(100)
        waited = waited + 100
    end

    local mcount = merchant_items_count()
    log('Merchant items(TLO): ' .. tostring(mcount))
    dbg('Selecting via Merchant.SelectItem: "' .. targetItem .. '"')

    -- Try direct Merchant.Item(name) lookup first on clients where Items() stays zero.
    local miOk = merchant_item_lookup(targetItem)
    if miOk then
        mq.cmdf('/invoke ${Merchant.SelectItem[=%s]}', targetItem)
        wait(150)
        if merchant_buy_button_enabled() then
            log('Selection accepted via Merchant.Item/SelectItem (buy button enabled).')
            return 0
        end
        mq.cmdf('/invoke ${Merchant.SelectItem[%s]}', targetItem)
        wait(150)
        if merchant_buy_button_enabled() then
            log('Selection accepted via Merchant.Item partial/SelectItem (buy button enabled).')
            return 0
        end
    end

    mq.cmdf('/invoke ${Merchant.SelectItem[=%s]}', targetItem)
    wait(150)

    local selected = merchant_selected_item_name()
    if selected ~= '' and selected:lower() == strip_item_text(targetItem):lower() then
        log('Selected merchant item: ' .. selected)
        return 0
    end

    -- Fallback to partial match selection.
    mq.cmdf('/invoke ${Merchant.SelectItem[%s]}', targetItem)
    wait(150)
    selected = merchant_selected_item_name()
    if selected ~= '' and selected:lower():find(strip_item_text(targetItem):lower(), 1, true) then
        log('Selected merchant item (partial): ' .. selected)
        return 0
    end

    log('ERROR: Item not found in merchant selection')
    return -1
end

local function stepBuyOne(idx)
    local targetItem = get_target_item_name()
    idx = safe_index(idx)
    if idx < 0 then
        log('ERROR: No selected item index to buy.')
        return false
    end
    local wndName = merchant_window_name()
    local listChild = active_list_child_name()
    local buttonCandidates = BUY_BUTTON_CANDIDATES
    if wndName == 'NewPointMerchantWnd' then
        buttonCandidates = { 'NewPointMerchant_PurchaseButton' }
        -- Macro-style reliability: re-select target row every purchase attempt.
        mq.cmdf('/notify %s %s listselect %d', wndName, listChild, idx)
        wait(NP_SELECT_DELAY)
    end
    if wndName ~= 'NewPointMerchantWnd' and not selected_item_matches_target() then
        log(('ERROR: Selected item does not match target. selected="%s" target="%s"'):format(
            selected_label_text(), targetItem))
        return false
    end

    local preCount = safe_num(safe_eval(function() return mq.TLO.FindItemCount and mq.TLO.FindItemCount('=' .. targetItem)() end, 0))
    local preCursor = safe_num(safe_eval(function() return mq.TLO.Cursor and mq.TLO.Cursor.ID and mq.TLO.Cursor.ID() end, 0))
    local clickedBuy = false
    local primaryButton = buttonCandidates[1]
    if primaryButton and primaryButton ~= '' then
        mq.cmdf('/nomodkey /notify %s %s leftmouseup', wndName, primaryButton)
        wait(wndName == 'NewPointMerchantWnd' and NP_CLICK_DELAY or 220)
        clickedBuy = true
    end

    local qw = mq.TLO.Window('QuantityWnd')
    local hasQty = qw and qw.Open and qw.Open()
    if not hasQty and wndName ~= 'NewPointMerchantWnd' then
        local mWnd = merchant_window()
        if mWnd and mWnd.Child then
            for _, buttonName in ipairs(buttonCandidates) do
                local btn = mWnd.Child(buttonName)
                if btn and btn.Enabled and btn.Enabled() and btn.LeftMouseUp then
                    dbg(('Merchant.Buy produced no quantity window; clicking %s fallback.'):format(buttonName))
                    btn.LeftMouseUp()
                    wait(300)
                    clickedBuy = true
                    break
                end
            end
        end
    end

    wait(CONFIRM_DELAY)
    -- QuantityWnd
    qw = mq.TLO.Window('QuantityWnd')
    if qw and qw.Open() then
        mq.cmd('/nomodkey /notify QuantityWnd QTYW_Slider newvalue 1')
        wait(150)
        mq.cmd('/nomodkey /notify QuantityWnd QTYW_Accept_Button leftmouseup')
        wait(CONFIRM_DELAY)
        pcall(function() mq.cmd('/autoinventory') end)
        wait(60)
        return true
    end
    -- Generic confirm dialogs
    for _, dname in ipairs({
        'ConfirmationDialogBox',
        'ConfirmationDialog',
        'LargeDialogWindow',
        'MQ2Confirm',
        'GenericDialog'
    }) do
        local dw = mq.TLO.Window(dname)
        if dw and dw.Open() then
            for _, bname in ipairs({
                'Yes_Button',
                'CD_Yes_Button',
                'LDW_YesButton',
                'CONFIRMATION_YesButton',
                'OK_Button',
                'Accept_Button'
            }) do
                local b = dw.Child and dw.Child(bname)
                local exists = safe_bool(safe_eval(function() return b ~= nil end, false))
                local isOpen = safe_bool(safe_eval(function() return b and b.Open and b.Open() end, false))
                if exists and (isOpen or b.LeftMouseUp) then
                    if b.LeftMouseUp then
                        b.LeftMouseUp()
                    else
                        mq.cmdf('/notify %s %s leftmouseup', dname, bname)
                    end
                    log(('Accepted confirmation: %s/%s'):format(dname, bname))
                    wait(CONFIRM_DELAY)
                    pcall(function() mq.cmd('/autoinventory') end)
                    wait(60)
                    return true
                end
            end
        end
    end

    -- Point-merchant/no-confirm path: require real evidence of a buy.
    local waited = 0
    local maxWait = (wndName == 'NewPointMerchantWnd') and NP_CONFIRM_WAIT_MAX or 1500
    while waited < maxWait do
        local curCursor = safe_num(safe_eval(function() return mq.TLO.Cursor and mq.TLO.Cursor.ID and mq.TLO.Cursor.ID() end, 0))
        if curCursor > 0 and curCursor ~= preCursor then
            mq.cmd('/autoinventory')
            wait(wndName == 'NewPointMerchantWnd' and 60 or 120)
            return true
        end
        local nowCount = safe_num(safe_eval(function() return mq.TLO.FindItemCount and mq.TLO.FindItemCount('=' .. targetItem)() end, 0))
        if nowCount > preCount then
            pcall(function() mq.cmd('/autoinventory') end)
            wait(80)
            return true
        end
        wait(100)
        waited = waited + 100
    end

    if not clickedBuy then
        log('ERROR: No merchant purchase button control was clickable.')
    else
        log(('ERROR: Buy click produced no confirmed result (no qty dialog, no cursor gain, no item-count gain). preCount=%d'):format(preCount))
    end
    return false
end

------------------------------------------------------------
-- STATE MACHINE TICK
------------------------------------------------------------
local function clear_queue_session()
    queueBuyActive = false
    queueBuySnapshots = {}
end

local function tick()
    if not running then return end
    if shouldStop then
        clear_queue_session()
        setStatus('Stopped. Bought ' .. bought)
        running = false; shouldStop = false; step = 'idle'
        return
    end
    if step == 'target' then
        if stepTarget() then step = 'open' else clear_queue_session(); running=false; step='idle' end
    elseif step == 'open' then
        if stepOpen() then step = 'find' else clear_queue_session(); running=false; step='idle' end
    elseif step == 'find' then
        itemIdx = stepFind()
        if itemIdx >= 0 then step = 'buy'
        else clear_queue_session(); running=false; step='idle' end
    elseif step == 'buy' then
        if buyQty <= 0 then
            if queueBuyActive and queueBuySnapshots and #queueBuySnapshots > 0 then
                queueBuyCursor = queueBuyCursor + 1
                if queueBuyCursor > #queueBuySnapshots then
                    clear_queue_session()
                    setStatus('Queue finished — ' .. tostring(bought) .. ' buy(s) this session.')
                    log(('Queue complete (%d buys).'):format(bought))
                    running = false
                    step = 'idle'
                    return
                end
                local snap = queueBuySnapshots[queueBuyCursor]
                targetItemName = snap.name
                uiSelectedItemIndex = -1
                local wantLow = strip_item_text(snap.name):lower()
                for ix = 1, #uiMerchantItems do
                    if strip_item_text(uiMerchantItems[ix].name):lower() == wantLow then
                        uiSelectedItemIndex = ix
                        break
                    end
                end
                buyQty = queueBuyQtyEach
                step = 'find'
                itemIdx = -1
                setStatus(('Queue %d/%d: %s (x%d each)'):format(
                    queueBuyCursor, #queueBuySnapshots, snap.name, queueBuyQtyEach))
                log(('Queue next (%d/%d): %s'):format(queueBuyCursor, #queueBuySnapshots, snap.name))
                return
            end
            setStatus('Done! Bought ' .. bought .. ' x ' .. get_target_item_name())
            running=false; step='idle'
            return
        end
        local st = merchant_state()
        if not merchant_ready(st) then
            log('Merchant closed. Stopping.')
            clear_queue_session()
            running=false; step='idle'; return
        end
        if stepBuyOne(itemIdx) then
            bought = bought + 1; buyQty = buyQty - 1
            setStatus('Bought ' .. bought .. ', ' .. buyQty .. ' left')
        else
            log('Purchase failed. Stopping.')
            clear_queue_session()
            running=false; step='idle'
        end
        local postDelay = BUY_DELAY
        if merchant_window_name() == 'NewPointMerchantWnd' then
            postDelay = NP_INTERBUY_DELAY
        end
        wait(postDelay)
    end
end

local function startBuy(qty)
    local want = strip_item_text(get_target_item_name())
    if want == '' then
        log('ERROR: Pick an item from LOAD MERCHANT LIST or set Item name in the UI.')
        return
    end
    queueBuyActive = false
    queueBuySnapshots = {}
    bought = 0; buyQty = qty; shouldStop = false; running = true; step = 'target'
    log('Starting: buy ' .. qty .. ' x ' .. want)
end

--- Buy checked rows top-to-bottom: Quantity applies to each line; one purchase cycle at a time.
local function startBuyQueue(overrideQty)
    if running then
        log('Already running. STOP first.')
        return
    end
    if #uiMerchantItems == 0 then
        log('ERROR: LOAD MERCHANT LIST first.')
        return
    end
    local snaps = {}
    for i = 1, #uiMerchantItems do
        if buyQueueChecked[i] then
            local it = uiMerchantItems[i]
            snaps[#snaps + 1] = {
                name = it.name,
                row = it.row,
                child = it.child,
            }
        end
    end
    if #snaps == 0 then
        log('ERROR: Check one or more items in the list (checkbox column).')
        return
    end
    local n = tonumber(overrideQty) or tonumber(inputQtyStr)
    if not n or n < 1 then
        log('Invalid Quantity for queue: ' .. tostring(inputQtyStr))
        return
    end
    n = math.floor(n)
    queueBuySnapshots = snaps
    queueBuyCursor = 1
    queueBuyQtyEach = n
    queueBuyActive = true
    targetItemName = snaps[1].name
    bought = 0
    buyQty = n
    shouldStop = false
    running = true
    step = 'target'
    uiSelectedItemIndex = 1
    for i = 1, #uiMerchantItems do
        if buyQueueChecked[i] then uiSelectedItemIndex = i; break end
    end
    log(('Queue start: %d item(s) top-to-bottom, %d x each (autoinventory after buys).'):format(#snaps, n))
    setStatus(('Queue 1/%d: %s'):format(#snaps, snaps[1].name))
end

--- GearScoreX Obsidian buttons (panel bg + accent label), stacked on theme.push_obsidian_frame.
local function push_obsidian_accent_button()
    local fr, fg, fb, fa = ui_theme.rgba(ui_theme.BACKGROUND_PANEL)
    local fh, fgh, fgb, fga = ui_theme.rgba(ui_theme.BACKGROUND_HOVER)
    ImGui.PushStyleColor(ImGuiCol.Button, fr, fg, fb, fa)
    ImGui.PushStyleColor(ImGuiCol.ButtonHovered, fh, fgh, fgb, fga)
    local ar, ag, ab, aa = ui_theme.rgba(ui_theme.TEXT_ACCENT)
    ImGui.PushStyleColor(ImGuiCol.Text, ar, ag, ab, aa)
end

local function pop_obsidian_accent_button()
    ImGui.PopStyleColor(3)
end

local function push_secondary_text()
    local r, g, b, a = ui_theme.rgba(ui_theme.TEXT_SECONDARY)
    ImGui.PushStyleColor(ImGuiCol.Text, r, g, b, a)
end

------------------------------------------------------------
-- IMGUI CALLBACK
-- Exact kaen01 / RedGuides canonical pattern:
--   Open, ShowUI = ImGui.Begin('Title', Open)
--   if ShowUI then ... end
--   ImGui.End()   -- always, unconditionally
-- NO mq.delay anywhere in this function (non-yieldable ImGui thread).
-- Buttons / right-click only SET STATE — main loop does delays (see process_pending_item_link).
-- Using only confirmed-working API calls:
--   ImGui.Text(string)
--   ImGui.TextUnformatted(string)
--   ImGui.InputText(label, text) -> text, changed
--   ImGui.Button(label) -> bool
--   ImGui.SameLine()
--   ImGui.Separator()
--   ImGui.SetNextItemWidth(w)
--   ImGui.BeginChild(id, w, h) -> bool  (2 float args only, no flags)
--   ImGui.EndChild()
--   ImGui.SetScrollHereY(1.0)
------------------------------------------------------------
local function drawGUI()
    ui_theme.push_obsidian_frame()
    ImGui.SetNextWindowSize(520, 620, ImGuiCond.FirstUseEver)
    Open, ShowUI = ImGui.Begin('UEQCredit — Alt currency buyer', Open)

    if ShowUI then
        if NPC_NAME ~= '' then
            ImGui.Text('Vendor filter: %s', NPC_NAME)
        end
        if detectedCurrency.merchantName ~= '' then
            ImGui.Text('Vendor: %s', detectedCurrency.merchantName)
        end
        if detectedCurrency.tier then
            local ar, ag, ab, aa = ui_theme.rgba(ui_theme.TEXT_ACCENT)
            ImGui.PushStyleColor(ImGuiCol.Text, ar, ag, ab, aa)
            ImGui.Text('%s  ·  %s',
                detectedCurrency.currencyName,
                detectedCurrency.balance >= 0 and tostring(detectedCurrency.balance) or '?')
            ImGui.PopStyleColor()
        end
        push_secondary_text()
        ImGui.TextWrapped('%s  ·  Bought: %d', statusMsg, bought)
        ImGui.PopStyleColor()
        ImGui.Separator()

        push_secondary_text()
        ImGui.Text('Name filter')
        ImGui.PopStyleColor()
        ImGui.SetNextItemWidth(320)
        --- During BUY QUEUE, do not feed InputText every frame — it fights Selectable and retriggers "Selected UI item" spam.
        if queueBuyActive and running and queueBuySnapshots[queueBuyCursor] then
            push_secondary_text()
            ImGui.TextWrapped('Queue buying: %s', strip_item_text(queueBuySnapshots[queueBuyCursor].name))
            ImGui.PopStyleColor()
        else
            local newItemStr, itemCh = ImGui.InputText('##targetitem', targetItemName)
            if newItemStr ~= nil then targetItemName = newItemStr end
        end

        local loadClicked = false
        if running then
            ImGui.BeginDisabled(true)
            ImGui.Button('LOAD (busy)##ueqcredit')
            ImGui.EndDisabled()
        else
            push_obsidian_accent_button()
            loadClicked = ImGui.Button('LOAD MERCHANT LIST##ueqcredit')
            pop_obsidian_accent_button()
        end
        if loadClicked then
            refresh_ui_merchant_items(250)
        end

        local _, listRegionH = ImGui.GetContentRegionAvail()
        local footerH = 118
        local listH = math.max(160, listRegionH - footerH)
        if ImGui.BeginChild('ueqc_itempicker', 0, listH) then
            if #uiMerchantItems == 0 then
                push_secondary_text()
                ImGui.TextWrapped('No items — open the vendor and press LOAD MERCHANT LIST.')
                ImGui.PopStyleColor()
            else
                push_secondary_text()
                ImGui.TextWrapped('Queue ☑  ·  row click = select for BUY NOW  ·  right-click = link')
                ImGui.PopStyleColor()
                ImGui.Separator()
                for i = 1, #uiMerchantItems do
                    local it = uiMerchantItems[i]
                    local selected = (uiSelectedItemIndex == i)
                    local priceTxt = (it.price and it.price ~= '') and (' [' .. it.price .. ']') or ''
                    local label = string.format('%s%s##item%d', it.name, priceTxt, i)
                    ImGui.PushID(i)
                    ImGui.AlignTextToFramePadding()
                    local chkOn = buyQueueChecked[i] == true
                    ImGui.PushStyleVar(ImGuiStyleVar.FrameBorderSize, 1)
                    do
                        local br, bg, bb, ba = ui_theme.rgba(ui_theme.BORDER_ACCENT)
                        ImGui.PushStyleColor(ImGuiCol.Border, br, bg, bb, ba)
                        local fr, fg, fb, fa = ui_theme.rgba(0xFF353B48)
                        ImGui.PushStyleColor(ImGuiCol.FrameBg, fr, fg, fb, fa)
                        local fh, fgh, fgb, fga = ui_theme.rgba(0xFF3D4A5C)
                        ImGui.PushStyleColor(ImGuiCol.FrameBgHovered, fh, fgh, fgb, fga)
                        ImGui.PushStyleColor(ImGuiCol.FrameBgActive, fh, fgh, fgb, fga)
                        local cr, cg, cb, ca = ui_theme.rgba(ui_theme.TEXT_ACCENT)
                        ImGui.PushStyleColor(ImGuiCol.CheckMark, cr, cg, cb, ca)
                    end
                    local chkNew, _ = ImGui.Checkbox('##qbuy' .. i, chkOn)
                    buyQueueChecked[i] = chkNew and true or false
                    ImGui.PopStyleColor(5)
                    ImGui.PopStyleVar(1)
                    ImGui.SameLine(0, 6)
                    ImGui.BeginGroup()
                    ImGui.AlignTextToFramePadding()
                    draw_ueqcredit_item_icon(it.icon or 500, 20)
                    ImGui.SameLine(0, 6)
                    local clicked = ImGui.Selectable(label, selected)
                    local rowHover = ImGui.IsItemHovered()
                    local rightOpen = ImGui.IsItemClicked(ImGuiMouseButton.Right)
                    ImGui.EndGroup()
                    if clicked and not (queueBuyActive and running) then
                        if uiSelectedItemIndex ~= i or targetItemName ~= it.name then
                            uiSelectedItemIndex = i
                            targetItemName = it.name
                            log('Selected UI item: ' .. targetItemName)
                        end
                    end
                    if rightOpen then
                        uiSelectedItemIndex = i
                        targetItemName = it.name
                        queue_open_merchant_item_link(it)
                    end
                    if rowHover then
                        draw_merchant_item_tooltip(it)
                    end
                    ImGui.PopID()
                end
            end
        end
        ImGui.EndChild()

        if uiSelectedItemIndex >= 1 and uiSelectedItemIndex <= #uiMerchantItems then
            local it = uiMerchantItems[uiSelectedItemIndex]
            local priceNum = tonumber((tostring(it.price or ''):match('%d+')))
            if priceNum and detectedCurrency.balance >= 0 then
                local ok = priceNum <= detectedCurrency.balance
                local hr, hg, hb, ha
                if ok then hr, hg, hb, ha = ui_theme.rgba(ui_theme.DELTA_UPGRADE)
                else hr, hg, hb, ha = ui_theme.rgba(ui_theme.DELTA_DOWNGRADE) end
                ImGui.PushStyleColor(ImGuiCol.Text, hr, hg, hb, ha)
                ImGui.Text('Selected price %s — need %d %s (%s)',
                    tostring(it.price or '?'), priceNum,
                    detectedCurrency.currencyName ~= '' and detectedCurrency.currencyName or 'credits',
                    ok and 'affordable' or 'INSUFFICIENT balance')
                ImGui.PopStyleColor()
            elseif priceNum then
                ImGui.Text('Selected price: %s (%d)', tostring(it.price), priceNum)
            end
        end

        push_secondary_text()
        ImGui.Text('Quantity:')
        ImGui.PopStyleColor()
        ImGui.SameLine()
        ImGui.SetNextItemWidth(80)
        local newQty, _ = ImGui.InputText('##qty', inputQtyStr)
        if newQty ~= nil then inputQtyStr = newQty end
        ImGui.SameLine()

        if running then
            push_obsidian_accent_button()
            if ImGui.Button('STOP##ueqcredit') then
                shouldStop = true
                log('Stop via GUI')
            end
            pop_obsidian_accent_button()
        else
            push_obsidian_accent_button()
            if ImGui.Button('BUY NOW##ueqcredit') then
                local n = tonumber(inputQtyStr)
                if n and n >= 1 then
                    startBuy(math.floor(n))
                else
                    log('Invalid qty: ' .. tostring(inputQtyStr))
                end
            end
            ImGui.SameLine()
            if ImGui.Button('BUY QUEUE##ueqcredit') then
                startBuyQueue(nil)
            end
            pop_obsidian_accent_button()
            ImGui.SameLine()
            push_secondary_text()
            if ImGui.Button('CLEAR CHECKS##ueqcredit') then
                for j = 1, #uiMerchantItems do
                    buyQueueChecked[j] = false
                end
            end
            ImGui.PopStyleColor()
        end
    end

    ImGui.End()  -- ALWAYS called outside/after the if ShowUI block
    ui_theme.pop_obsidian_frame()
end

------------------------------------------------------------
-- BIND /ueqcredit (chat tag [UEQC])
------------------------------------------------------------
mq.bind('/ueqcredit', function(cmd, arg1, arg2)
    local ok, err = xpcall(function()
        -- Different MQ builds pass bind args differently. Normalize to a token list.
        local parts = {}
        local function add_tokens(s)
            if s == nil then return end
            if type(s) ~= 'string' then s = tostring(s) end
            for tok in s:gmatch('%S+') do
                parts[#parts + 1] = tok
            end
        end
        add_tokens(cmd); add_tokens(arg1); add_tokens(arg2)

        local sub = (parts[1] or ''):lower()
        local p1 = parts[2]

        if sub == 'buy' then
            local n = tonumber(p1)
            if not n or n < 1 then log('Usage: /ueqcredit buy <number>'); return end
            if running then log('Already running. /ueqcredit stop first'); return end
            startBuy(math.floor(n))
        elseif sub == 'queue' then
            if running then log('Already running. /ueqcredit stop first'); return end
            local qn = tonumber(p1)
            startBuyQueue(qn)
        elseif sub == 'stop' then
            if running then shouldStop=true; log('Stopping...')
            else log('Not running') end
        elseif sub == 'dumpwin' then
            -- Always generate a file-backed dump for user-visible output.
            log('Running dumpwin (file)...')
            dump_window_tree_file()
        elseif sub == 'dumpwintree' then
            dump_window_tree_file()
        elseif sub == 'dumplist' then
            log('Running dumplist...')
            dump_list_matrix(p1)
        elseif sub == 'dumpmerchant' then
            log('Running dumpmerchant...')
            if not safe_bool(mq.TLO.Merchant and mq.TLO.Merchant.Open and mq.TLO.Merchant.Open()) then
                stepOpen()
            end
            wait_for_merchant_ready(3000, 10000)
            dump_merchant_inventory(p1)
        elseif sub == 'scan' then
            log('Running scan...')
            run_merchant_scan()
        elseif sub == 'winlist' then
            log('Running winlist...')
            dump_window_itemlist(p1)
        elseif sub == 'selprobe' then
            log('Running selprobe...')
            dump_selection_probe(p1)
        elseif sub == 'diag' then
            log_merchant_diag('manual')
        elseif sub == 'probelist' then
            log('Running probelist...')
            dump_probe_indexes(p1)
        elseif sub == 'probecoords' then
            log('Running probecoords...')
            dump_probe_coords(p1)
        elseif sub == 'debug' then
            local a = (p1 or ''):lower()
            if a == 'on' then
                debugMode = true
                log('Debug mode ON')
                log_merchant_state('manual-dump')
            elseif a == 'off' then
                debugMode = false
                log('Debug mode OFF')
            else
                log_merchant_state('manual-dump')
            end
        elseif sub == 'status' then
            log('step='..step..' bought='..bought..' remaining='..buyQty..' running='..tostring(running))
        elseif sub == 'currency' or sub == 'cur' then
            refresh_currency_detection()
            if detectedCurrency.currencyName ~= '' then
                log(string.format('%s = %s', detectedCurrency.currencyName,
                    detectedCurrency.balance >= 0 and tostring(detectedCurrency.balance) or '?'))
            else
                log('Credits line not matched on this merchant window.')
            end
        else
            print('\at[UEQC]\ax /ueqcredit buy <qty> | queue [qty] | stop | status | currency | debug [on|off] | diag | dumpwin | dumpwintree | dumplist [rows] | dumpmerchant [rows] | winlist [rows] | selprobe [maxIndex] | scan | probelist [maxIndex] | probecoords [stepY]')
        end
    end, function(e) return debug.traceback(e, 2) end)
    if not ok then
        log('ERROR: /ueqcredit crashed: ' .. tostring(err))
    end
end)

------------------------------------------------------------
-- REGISTER IMGUI
------------------------------------------------------------
mq.imgui.init('UEQCreditBuyerUI', drawGUI)

------------------------------------------------------------
-- STARTUP
------------------------------------------------------------
log('UEQCredit ready (/ueqcredit).')
setStatus('Idle — open vendor, LOAD MERCHANT LIST')

------------------------------------------------------------
-- MAIN LOOP  (canonical RedGuides pattern)
-- Loop runs while window Open=true.
-- Closing the X sets Open=false -> script exits cleanly.
------------------------------------------------------------
while Open do
    mq.doevents()
    process_pending_item_link()
    tick()
    mq.delay(100)
end

log('Window closed - exiting.')
