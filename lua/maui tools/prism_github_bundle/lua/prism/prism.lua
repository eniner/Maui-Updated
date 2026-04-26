-----------------------------------------------------------
-- CharmPrismBuyer.lua  (v4 - API-correct)
-- Buys "Charm Prism Upgrade" from The Hive Queen
--
-- INSTALL: <MQ>/lua/CharmPrismBuyer.lua
-- RUN:     /lua run CharmPrismBuyer
--
-- /cpb buy <qty>   begin buying
-- /cpb stop        stop current run
-----------------------------------------------------------

local mq = require('mq')
require 'ImGui'   -- global injection per kaen01 / RedGuides canonical pattern

------------------------------------------------------------
-- CONFIG
------------------------------------------------------------
local NPC_NAME      = 'The Hive Queen'
local ITEM_NAME     = 'Charm Prism Upgrade'
local OPEN_DELAY    = 1500
local BUY_DELAY     = 900
local CONFIRM_DELAY = 500
local NP_SELECT_DELAY = 70
local NP_CLICK_DELAY = 120
local NP_CONFIRM_WAIT_MAX = 900
local NP_INTERBUY_DELAY = 180
local ALLOW_MANUAL_SELECTED_FALLBACK = false

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
local logLines   = {}
local step       = 'idle'
local itemIdx    = -1

-- GUI input - plain string, no buffer size
local inputQtyStr = '10'
local debugMode   = false
local targetItemName = ITEM_NAME
local uiMerchantItems = {}
local uiSelectedItemIndex = -1
local LIST_CHILD_CANDIDATES = { 'NewPointMerchant_ItemList', 'MW_ItemList', 'ItemList' }
local NOTIFY_LIST_CANDIDATES = { 'NewPointMerchant_ItemList', 'MW_ItemList', 'ItemList' }
local BUY_BUTTON_CANDIDATES = { 'NewPointMerchant_PurchaseButton', 'MW_Purchase_Button', 'MW_Buy_Button' }
local DONE_BUTTON_CANDIDATES = { 'NewPointMerchant_DoneButton', 'MW_Done_Button' }
local SELECTED_LABEL_CANDIDATES = { 'NewPointMerchant_SelectedItemLabel', 'MW_SelectedItemLabel' }

------------------------------------------------------------
-- LOGGING
------------------------------------------------------------
local function log(msg)
    msg = tostring(msg)
    local line = string.format('[%s] %s', os.date('%H:%M:%S'), msg)
    table.insert(logLines, line)
    if #logLines > 150 then table.remove(logLines, 1) end
    print('\at[CPB]\ax ' .. msg)
end

local function setStatus(s)
    statusMsg = s
    log(s)
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

local function strip_item_text(s)
    s = tostring(s or '')
    s = s:gsub('%c', ' ')
    s = s:gsub('%s+', ' ')
    s = s:gsub('^%s+', ''):gsub('%s+$', '')
    return s
end

local function get_target_item_name()
    local n = strip_item_text(targetItemName)
    if n == '' then n = ITEM_NAME end
    return n
end

local function normalize_null_text(s)
    s = strip_item_text(s)
    if s == 'NULL' then return '' end
    return s
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
    out[#out + 1] = '=== Prism Window ItemList Dump ==='
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
    local path = mq.luaDir .. '/prism_win_itemlist_' .. os.date('%Y%m%d_%H%M%S') .. '.txt'
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
    if not si or not si() then return '' end
    local n = si.Name and si.Name() or ''
    return strip_item_text(n)
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
    out[#out + 1] = '=== Prism Selection Probe ==='
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

    local path = mq.luaDir .. '/prism_selprobe_' .. os.date('%Y%m%d_%H%M%S') .. '.txt'
    if write_lines(path, out) then
        log(('Dumped selection probe to: %s'):format(path))
    else
        log('ERROR: Failed to write selection probe file.')
    end
end

local function snapshot_path()
    local ts = os.date('%Y%m%d_%H%M%S')
    return mq.luaDir .. '/prism_merchant_dump_' .. ts .. '.txt'
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
        local price = strip_item_text(c3 ~= '' and c3 or (c1 ~= '' and c1 or c0))
        if name ~= '' and not seen[name:lower()] then
            seen[name:lower()] = true
            uiMerchantItems[#uiMerchantItems + 1] = {
                row = row,
                name = name,
                price = price,
                child = child or '',
            }
            if name:lower() == get_target_item_name():lower() then
                uiSelectedItemIndex = #uiMerchantItems
            end
        end
    end

    log(('Loaded %d merchant items into picker (%s).'):format(#uiMerchantItems, tostring(child)))
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
    out[#out + 1] = '=== Prism Merchant List Matrix Dump ==='
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
    out[#out + 1] = '=== Prism Merchant Index Probe ==='
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
    out[#out + 1] = '=== Prism Merchant Coord Probe ==='
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

    local path = mq.luaDir .. '/prism_merchant_coordprobe_' .. os.date('%Y%m%d_%H%M%S') .. '.txt'
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

    local path = mq.luaDir .. '/prism_merchant_tree_' .. os.date('%Y%m%d_%H%M%S') .. '.txt'
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
    setStatus('Searching for ' .. NPC_NAME)
    local sid = 0
    local queries = {
        -- SpawnWatch-style exact matching is more reliable for multi-word names.
        'npc radius 300 = ' .. NPC_NAME,
        'npc = ' .. NPC_NAME,
        -- Some servers flag shopkeepers via merchant filter.
        'merchant radius 300 = ' .. NPC_NAME,
        'merchant = ' .. NPC_NAME,
        -- Legacy/fuzzy fallback.
        'npc radius 300 name ' .. NPC_NAME,
        'npc name ' .. NPC_NAME,
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

    if sid == 0 then log('ERROR: NPC not found'); return false end
    mq.cmdf('/target id %d', sid)
    wait(700)
    local tid = mq.TLO.Target.ID and mq.TLO.Target.ID() or 0
    if tid ~= sid then log('ERROR: Target failed'); return false end
    setStatus('Targeted ' .. NPC_NAME)
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
    out[#out + 1] = '=== Prism Merchant Inventory Dump ==='
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

    local path = mq.luaDir .. '/prism_merchant_items_' .. os.date('%Y%m%d_%H%M%S') .. '.txt'
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

    local path = mq.luaDir .. '/prism_merchant_scan_' .. os.date('%Y%m%d_%H%M%S') .. '.txt'
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
        local listChild = 'NewPointMerchant_ItemList'
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
        if nowCount > preCount then return true end
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
local function tick()
    if not running then return end
    if shouldStop then
        setStatus('Stopped. Bought ' .. bought)
        running = false; shouldStop = false; step = 'idle'
        return
    end
    if step == 'target' then
        if stepTarget() then step = 'open' else running=false; step='idle' end
    elseif step == 'open' then
        if stepOpen() then step = 'find' else running=false; step='idle' end
    elseif step == 'find' then
        itemIdx = stepFind()
        if itemIdx >= 0 then step = 'buy'
        else running=false; step='idle' end
    elseif step == 'buy' then
        if buyQty <= 0 then
            setStatus('Done! Bought ' .. bought .. ' x ' .. get_target_item_name())
            running=false; step='idle'
            return
        end
        local st = merchant_state()
        if not merchant_ready(st) then
            log('Merchant closed. Stopping.')
            running=false; step='idle'; return
        end
        if stepBuyOne(itemIdx) then
            bought = bought + 1; buyQty = buyQty - 1
            setStatus('Bought ' .. bought .. ', ' .. buyQty .. ' left')
        else
            log('Purchase failed. Stopping.')
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
    bought=0; buyQty=qty; shouldStop=false; running=true; step='target'
    log('Starting: buy ' .. qty .. ' x ' .. get_target_item_name())
end

------------------------------------------------------------
-- UI THEME (mirrors spawn.lua style)
------------------------------------------------------------
local function push_theme()
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

local function pop_theme(pv, pc)
    if pc and pc > 0 then ImGui.PopStyleColor(pc) end
    if pv and pv > 0 then ImGui.PopStyleVar(pv) end
end

------------------------------------------------------------
-- IMGUI CALLBACK
-- Exact kaen01 / RedGuides canonical pattern:
--   Open, ShowUI = ImGui.Begin('Title', Open)
--   if ShowUI then ... end
--   ImGui.End()   -- always, unconditionally
-- NO mq.delay anywhere in this function.
-- Buttons only SET STATE - main loop does the work.
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
    local pv, pc = push_theme()
    ImGui.SetNextWindowSize(500, 540, ImGuiCond.FirstUseEver)
    ImGui.SetNextWindowBgAlpha(0.95)
    -- kaen01 pattern: pass Open in, get Open+ShowUI back
    Open, ShowUI = ImGui.Begin('Charm Prism Buyer', Open)

    if ShowUI then
        ImGui.Text('NPC:  ' .. NPC_NAME)
        ImGui.Text('Item: ' .. get_target_item_name())
        ImGui.Separator()
        ImGui.Text('Status: ' .. statusMsg)
        ImGui.Text('Bought this session: ' .. tostring(bought))
        ImGui.Separator()

        if ImGui.Button('LOAD MERCHANT LIST') then
            refresh_ui_merchant_items(250)
        end
        ImGui.SameLine()
        ImGui.TextDisabled('Pick item from list, then buy qty')

        if ImGui.BeginChild('cpb_itempicker', 0, 120) then
            if #uiMerchantItems == 0 then
                ImGui.TextDisabled('No items loaded. Open merchant and click LOAD MERCHANT LIST.')
            else
                for i = 1, #uiMerchantItems do
                    local it = uiMerchantItems[i]
                    local selected = (uiSelectedItemIndex == i)
                    local priceTxt = (it.price and it.price ~= '') and (' [' .. it.price .. ']') or ''
                    local label = string.format('%s%s##item%d', it.name, priceTxt, i)
                    local clicked = ImGui.Selectable(label, selected)
                    if clicked then
                        if uiSelectedItemIndex ~= i or targetItemName ~= it.name then
                            uiSelectedItemIndex = i
                            targetItemName = it.name
                            log('Selected UI item: ' .. targetItemName)
                        end
                    end
                end
            end
        end
        ImGui.EndChild()

        ImGui.Text('Quantity:')
        ImGui.SameLine()
        ImGui.SetNextItemWidth(80)
        -- InputText: (label, text) -> newText, changed  (NO buffer size arg)
        local newQty, _ = ImGui.InputText('##qty', inputQtyStr)
        if newQty ~= nil then inputQtyStr = newQty end
        ImGui.SameLine()

        if running then
            if ImGui.Button('STOP') then
                shouldStop = true
                log('Stop via GUI')
            end
        else
            if ImGui.Button('BUY NOW') then
                local n = tonumber(inputQtyStr)
                if n and n >= 1 then
                    startBuy(math.floor(n))
                else
                    log('Invalid qty: ' .. tostring(inputQtyStr))
                end
            end
        end

        ImGui.Separator()
        ImGui.Text('Log:')
        -- BeginChild with only id, width, height (no flags - avoids arg errors)
        if ImGui.BeginChild('cpblog', 0, 0) then
            for i = #logLines, math.max(1, #logLines - 60), -1 do
                ImGui.TextUnformatted(logLines[i])
            end
            ImGui.SetScrollHereY(1.0)
        end
        ImGui.EndChild()
    end

    ImGui.End()  -- ALWAYS called outside/after the if ShowUI block
    pop_theme(pv, pc)
end

------------------------------------------------------------
-- BIND /cpb
------------------------------------------------------------
mq.bind('/cpb', function(cmd, arg1, arg2)
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
            if not n or n < 1 then log('Usage: /cpb buy <number>'); return end
            if running then log('Already running. /cpb stop first'); return end
            startBuy(math.floor(n))
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
        else
            print('\at[CPB]\ax /cpb buy <qty> | stop | status | debug [on|off] | diag | dumpwin | dumpwintree | dumplist [rows] | dumpmerchant [rows] | winlist [rows] | selprobe [maxIndex] | scan | probelist [maxIndex] | probecoords [stepY]')
        end
    end, function(e) return debug.traceback(e, 2) end)
    if not ok then
        log('ERROR: /cpb handler crashed: ' .. tostring(err))
    end
end)

------------------------------------------------------------
-- REGISTER IMGUI
------------------------------------------------------------
mq.imgui.init('CharmPrismBuyerUI', drawGUI)

------------------------------------------------------------
-- STARTUP
------------------------------------------------------------
log('CharmPrismBuyer loaded. /cpb buy <qty> or use the GUI.')
setStatus('Idle - Ready')

------------------------------------------------------------
-- MAIN LOOP  (canonical RedGuides pattern)
-- Loop runs while window Open=true.
-- Closing the X sets Open=false -> script exits cleanly.
------------------------------------------------------------
while Open do
    mq.doevents()
    tick()
    mq.delay(100)
end

log('Window closed - exiting.')
