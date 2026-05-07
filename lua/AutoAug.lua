local mq = require('mq')
local ImGui = require('ImGui')
local ueqFloat = require('ueq_logo_float')

local SCRIPT_NAME = 'AutoAugClose'
local CONFIG_FILE = string.format('%s/%s.ini', mq.configDir, SCRIPT_NAME)
local DUMP_FILE = string.format('%s/%s_windows_dump.txt', mq.configDir, SCRIPT_NAME)
local DUMP_FILE_SAFE = DUMP_FILE:gsub('\\', '/')

local colors = {
    ok = '\ag',
    warn = '\ay',
    err = '\ar',
    info = '\at',
    reset = '\ax',
}

local defaults = {
    enabled = true,
    debug = false,
    showUI = false,
    minDelay = 50,
    maxDelay = 150,
    pulseMs = 75,
    requireCursorSolvent = false,
    requireKeywordMatch = true,
    autoDisableCombat = true,
    autoDisableZoning = true,
    allowInsertPrompts = true,
    aggressiveYesSpam = true,
    blindConfirmFallback = true,
    forceEnterMode = false,
    mqNativeYesMode = true,
    exactDialogNotifyMode = true,
    allowedSlots = '',
    whitelistItems = '',
    blacklistItems = '',
}

local cfg = {}
local running = true
local zonedPause = false
local lastToggleAt = {}
local lastEnterPressMs = 0
local getWindow
local childExists

local targetWindows = {
    'ConfirmationDialogBox',
    'ConfirmationDialogWnd',
    'ConfirmationDialog',
    'LargeDialogWnd',
    'LargeDialogWindow',
    'AugmentRemovalWnd',
    'ItemDisplayWindow',
    'IDW_Socket_Slot_1_Screen',
    'IDW_Socket_Slot_2_Screen',
    'IDW_Socket_Slot_3_Screen',
    'IDW_Socket_Slot_4_Screen',
    'IDW_Socket_Slot_5_Screen',
    'IDW_Socket_Slot_6_Screen',
    'IDW_Appearance_Socket_Screen',
}

local dynamicItemWindows = {
    'ItemDisplayWnd',
    'ItemDisplayWindow',
    'ItemDisplay',
    'ItemWindow',
}
for i = 1, 40 do
    dynamicItemWindows[#dynamicItemWindows + 1] = string.format('ItemDisplayWindow%d', i)
    dynamicItemWindows[#dynamicItemWindows + 1] = string.format('ItemDisplayWnd%d', i)
    dynamicItemWindows[#dynamicItemWindows + 1] = string.format('ItemWindow%d', i)
end

local positiveButtons = {
    'CD_Yes_Button',
    'Yes_Button', -- Custom UI-specific alias shown by /windows ConfirmationDialogBox
    'CD_YesBtn',
    'LDW_YesButton',
    'LD_YesButton',
    'ADW_Remove_Button',
    'Yes_Button',
    'YesButton',
    'Yes',
    'Accept_Button',
    'AcceptButton',
    'Accept',
    'OK_Button',
    'OK',
    'Button1',
    'Btn_Yes',
    'BD_Yes_Button',
    'YES_Button',
    'YES',
    'IDW_YesButton',
    'IDW_Yes_Button',
}

local function clickConfirmedDialogBox()
    local wndName = 'ConfirmationDialogBox'
    local wnd = getWindow(wndName)
    if not wnd then return false end

    -- Exact controls verified from your /windows output.
    local exactButtons = { 'CD_Yes_Button', 'Yes_Button' }
    for i = 1, #exactButtons do
        if childExists(wnd, exactButtons[i]) then
            mq.cmdf('/notify %s %s leftmouse', wndName, exactButtons[i])
            mq.cmdf('/notify %s %s leftmouseup', wndName, exactButtons[i])
            return true
        end
    end
    return false
end

local function forceExactDialogNotify()
    mq.cmd('/squelch /notify ConfirmationDialogBox CD_Yes_Button leftmouseup')
    mq.cmd('/squelch /notify ConfirmationDialogBox Yes_Button leftmouseup')
end

local textControls = {
    'CD_TextOutput',
    'LDW_Text',
    'ADW_Text',
    'Description',
    'ItemDescription',
    'Text',
    'Label',
    'CD_Label',
    'Message',
    'IDW_ItemDescription',
    'IDW_Description',
}

local keywordFilters = {
    'augment',
    'augs',
    'solvent',
    'remove',
    'insert',
    'socket',
    'are you sure',
    'destroy',
}

local function log(kind, msg)
    local c = colors[kind] or colors.info
    mq.cmdf('/echo %s[%s] %s%s', c, SCRIPT_NAME, msg, colors.reset)
end

local function dlog(msg)
    if cfg.debug then
        log('info', msg)
    end
end

local function trim(s)
    if not s then return '' end
    return s:match('^%s*(.-)%s*$') or ''
end

local function splitCSV(s)
    local raw = string.lower(trim(s or ''))
    if raw == '' or raw == 'false' or raw == 'nil' or raw == '0' then
        return {}
    end
    local out = {}
    for token in string.gmatch((s or '') .. ',', '([^,]*),') do
        local t = string.lower(trim(token))
        if t ~= '' and t ~= 'false' and t ~= 'nil' and t ~= '0' then
            out[#out + 1] = t
        end
    end
    return out
end

local function csvContains(csv, value)
    local v = string.lower(trim(value or ''))
    if v == '' then return false end
    local parts = splitCSV(csv)
    for i = 1, #parts do
        if v:find(parts[i], 1, true) then
            return true
        end
    end
    return false
end

local function toBool(v, fallback)
    if v == nil then return fallback end
    local s = string.lower(tostring(v))
    return s == '1' or s == 'true' or s == 'yes' or s == 'on'
end

local function loadConfig()
    for k, v in pairs(defaults) do
        cfg[k] = v
    end

    local f = io.open(CONFIG_FILE, 'r')
    if not f then return end

    for line in f:lines() do
        local key, value = line:match('^([%w_]+)%s*=%s*(.*)$')
        if key and defaults[key] ~= nil then
            if type(defaults[key]) == 'boolean' then
                cfg[key] = toBool(value, defaults[key])
            elseif type(defaults[key]) == 'number' then
                local n = tonumber(value)
                if n then cfg[key] = n end
            else
                cfg[key] = tostring(value)
            end
        end
    end

    f:close()

    -- sanitize legacy/bad values written by incompatible UI bindings
    local function cleanCsvField(v)
        local s = string.lower(trim(tostring(v or '')))
        if s == '' or s == 'false' or s == 'nil' or s == '0' then
            return ''
        end
        return tostring(v)
    end
    cfg.whitelistItems = cleanCsvField(cfg.whitelistItems)
    cfg.blacklistItems = cleanCsvField(cfg.blacklistItems)
    cfg.allowedSlots = cleanCsvField(cfg.allowedSlots)
end

local function saveConfig()
    local ok, err = pcall(function()
        local f = assert(io.open(CONFIG_FILE, 'w'))
        for k, _ in pairs(defaults) do
            f:write(string.format('%s=%s\n', k, tostring(cfg[k])))
        end
        f:close()
    end)

    if not ok then
        log('err', string.format('Failed to save config: %s', tostring(err)))
    end
end

getWindow = function(name)
    local ok, wnd = pcall(function() return mq.TLO.Window(name) end)
    if not ok or not wnd then return nil end
    local isOpen = false
    local isVisible = false
    pcall(function() isOpen = wnd.Open() end)
    pcall(function() isVisible = wnd.Visible() end)
    if isOpen and isVisible then return wnd end
    return nil
end

local function getWndName(wnd)
    local n = ''
    pcall(function() n = wnd.Name() or '' end)
    return n
end

local function getWndText(wnd)
    local t = ''
    pcall(function() t = wnd.Text() or '' end)
    return string.lower(t)
end

childExists = function(wnd, child)
    local exists = false
    pcall(function() exists = wnd.Child(child)() ~= nil end)
    return exists
end

local function childText(wnd, child)
    local text = ''
    pcall(function()
        local c = wnd.Child(child)
        if c() ~= nil then
            text = c.Text() or ''
        end
    end)
    return string.lower(text)
end

local function keywordsMatch(haystack)
    local h = string.lower(haystack or '')
    for i = 1, #keywordFilters do
        if h:find(keywordFilters[i], 1, true) then
            return true
        end
    end
    return false
end

local function getCursorItemName()
    local name = ''
    pcall(function() name = mq.TLO.Cursor.Name() or '' end)
    return name
end

local function hasAugRemovalCursorItem()
    local lc = string.lower(getCursorItemName() or '')
    if lc == '' then return false end
    return lc:find('distiller', 1, true) or lc:find('solvent', 1, true)
end

local function getLastInvSlotName()
    local s = ''
    pcall(function() s = mq.TLO.InvSlot(mq.TLO.Me.InventorySlot).Name() or '' end)
    return s
end

local function isCombat()
    local state = ''
    pcall(function() state = mq.TLO.Me.CombatState() or '' end)
    state = string.upper(state)
    return state == 'COMBAT' or state == 'ACTIVE'
end

local function isZoningOrNotReady()
    local gameState = ''
    pcall(function() gameState = mq.TLO.EverQuest.GameState() or '' end)
    return gameState ~= 'INGAME'
end

local function isAllowedByLists()
    local cursorItem = getCursorItemName()
    if cfg.requireCursorSolvent then
        local lc = string.lower(cursorItem)
        if lc == '' or (not lc:find('solvent', 1, true) and not lc:find('augment distiller', 1, true)) then
            dlog('Cursor solvent requirement not met.')
            return false
        end
    end

    if cfg.whitelistItems ~= '' and not csvContains(cfg.whitelistItems, cursorItem) then
        dlog(string.format('Cursor item [%s] not in whitelist.', cursorItem))
        return false
    end

    if cfg.blacklistItems ~= '' and csvContains(cfg.blacklistItems, cursorItem) then
        log('warn', string.format('Blocked by blacklist item match: %s', cursorItem))
        return false
    end

    if cfg.allowedSlots ~= '' then
        local slotName = getLastInvSlotName()
        if slotName ~= '' and not csvContains(cfg.allowedSlots, slotName) then
            dlog(string.format('Slot [%s] not in allowedSlots.', slotName))
            return false
        end
    end

    return true
end

local function safeRandomDelay()
    local minD = math.max(1, tonumber(cfg.minDelay) or 50)
    local maxD = math.max(minD, tonumber(cfg.maxDelay) or minD)
    mq.delay(math.random(minD, maxD))
end

local function clickPositiveButton(windowName, wnd)
    for i = 1, #positiveButtons do
        local btn = positiveButtons[i]
        if childExists(wnd, btn) then
            mq.cmdf('/notify %s %s leftmouseup', windowName, btn)
            dlog(string.format('Clicked %s on %s', btn, windowName))
            safeRandomDelay()
            return true, btn
        end
    end

    -- Fallback attempts used on some emu/custom UIs
    local fallback = { 'Yes', 'Accept', 'OK', 'Button2' }
    for i = 1, #fallback do
        mq.cmdf('/notify %s %s leftmouseup', windowName, fallback[i])
    end

    return false, 'none'
end

-- Hard fallback for UI packs/clients where TLO child introspection differs.
-- This directly tries /notify against known dialog window/button pairs.
local function bruteForceNotifyFallback()
    local winNames = {
        'ConfirmationDialogWnd', 'ConfirmationDialogBox', 'ConfirmationDialog',
        'LargeDialogWnd', 'LargeDialogWindow', 'AugmentRemovalWnd',
    }
    local btnNames = {
        'CD_Yes_Button', 'CD_YesBtn', 'LDW_YesButton', 'LD_YesButton',
        'ADW_Remove_Button', 'Yes_Button', 'YesButton', 'Yes',
        'Accept_Button', 'AcceptButton', 'Accept', 'OK_Button', 'OK',
        'Button1', 'Btn_Yes',
    }

    local clickEvents = { 'leftmouse', 'leftmouseup' }
    for i = 1, #winNames do
        local wnd = getWindow(winNames[i])
        if wnd then
            for j = 1, #btnNames do
                if childExists(wnd, btnNames[j]) then
                    for k = 1, #clickEvents do
                        mq.cmdf('/notify %s %s %s', winNames[i], btnNames[j], clickEvents[k])
                    end
                end
            end
        end
    end
end

local function spamKnownAugYesButtons()
    local winNames = {
        'ConfirmationDialogWnd', 'ConfirmationDialogBox', 'ConfirmationDialog',
        'LargeDialogWnd', 'LargeDialogWindow', 'AugmentRemovalWnd',
        'ItemDisplayWindow',
        'IDW_Socket_Slot_1_Screen', 'IDW_Socket_Slot_2_Screen', 'IDW_Socket_Slot_3_Screen',
        'IDW_Socket_Slot_4_Screen', 'IDW_Socket_Slot_5_Screen', 'IDW_Socket_Slot_6_Screen',
        'IDW_Appearance_Socket_Screen',
    }
    local yesOnly = {
        'CD_Yes_Button', 'CD_YesBtn', 'LDW_YesButton', 'LD_YesButton',
        'ADW_Remove_Button', 'Yes_Button', 'YesButton', 'Yes', 'Btn_Yes', 'YES_Button', 'YES',
    }
    for i = 1, #winNames do
        local wnd = getWindow(winNames[i])
        if wnd then
            for j = 1, #yesOnly do
                if childExists(wnd, yesOnly[j]) then
                    mq.cmdf('/notify %s %s leftmouse', winNames[i], yesOnly[j])
                    mq.cmdf('/notify %s %s leftmouseup', winNames[i], yesOnly[j])
                end
            end
        end
    end
end

local function dumpAugWindows()
    local ok, err = pcall(function()
        local f = assert(io.open(DUMP_FILE, 'w'))
        f:write(string.format('[%s] Aug Window Dump\n', os.date('%Y-%m-%d %H:%M:%S')))
        for i = 1, #targetWindows do
            local wname = targetWindows[i]
            local wnd = getWindow(wname)
            local openStr = 'false'
            local visStr = 'false'
            local text = ''
            if wnd then
                openStr = 'true'
                visStr = 'true'
                text = scanWindowText(wname, wnd)
            end
            f:write(string.format('\nWindow=%s Open=%s Visible=%s\n', wname, openStr, visStr))
            if text ~= '' then
                f:write(string.format('Text=%s\n', text:gsub('\n', ' ')))
            end
            if wnd then
                for j = 1, #positiveButtons do
                    local b = positiveButtons[j]
                    f:write(string.format('  Button[%s]=%s\n', b, tostring(childExists(wnd, b))))
                end
            end
        end
        f:write('\n-- Dynamic ItemDisplay Candidates --\n')
        for i = 1, #dynamicItemWindows do
            local wname = dynamicItemWindows[i]
            local wnd = getWindow(wname)
            if wnd then
                f:write(string.format('\nWindow=%s Open=true Visible=true\n', wname))
                local text = scanWindowText(wname, wnd)
                if text ~= '' then
                    f:write(string.format('Text=%s\n', text:gsub('\n', ' ')))
                end
                for j = 1, #positiveButtons do
                    local b = positiveButtons[j]
                    f:write(string.format('  Button[%s]=%s\n', b, tostring(childExists(wnd, b))))
                end
            end
        end
        f:close()
    end)
    if ok then
        -- Use forward slashes so EQ chat color parser does not mangle backslash sequences.
        log('ok', string.format('Dump written: %s', DUMP_FILE_SAFE))
    else
        log('err', string.format('Dump failed: %s', tostring(err)))
    end
end

local function scanWindowText(windowName, wnd)
    local combined = windowName .. ' ' .. getWndName(wnd) .. ' ' .. getWndText(wnd)

    for i = 1, #textControls do
        local txt = childText(wnd, textControls[i])
        if txt ~= '' then combined = combined .. ' ' .. txt end
    end

    for i = 1, #positiveButtons do
        local txt = childText(wnd, positiveButtons[i])
        if txt ~= '' then combined = combined .. ' ' .. txt end
    end

    return string.lower(combined)
end

local function tryItemDisplayYesFallback()
    local hit = false
    for wi = 1, #dynamicItemWindows do
        local wndName = dynamicItemWindows[wi]
        local wnd = getWindow(wndName)
        if wnd then
            local blob = scanWindowText(wndName, wnd)
            local isRemovePrompt = blob:find('are you sure', 1, true)
                and (blob:find('distiller', 1, true) or blob:find('solvent', 1, true))
                and (blob:find('remove', 1, true) or blob:find('remove your', 1, true))
                and blob:find('augment', 1, true)
            if isRemovePrompt then
                local idwButtons = {
                    'IDW_YesButton', 'IDW_Yes_Button', 'Yes_Button', 'YesButton', 'Yes', 'Button1',
                }
                for i = 1, #idwButtons do
                    if childExists(wnd, idwButtons[i]) then
                        mq.cmdf('/notify %s %s leftmouse', wndName, idwButtons[i])
                        mq.cmdf('/notify %s %s leftmouseup', wndName, idwButtons[i])
                        hit = true
                    end
                end
            end
        end
    end

    if hit then
        local nowMs = math.floor(os.clock() * 1000)
        if nowMs - lastEnterPressMs > 120 then
            lastEnterPressMs = nowMs
            mq.cmd('/keypress ENTER')
        end
    end
    return hit
end

local function isAugPrompt(windowName, wnd)
    local blob = scanWindowText(windowName, wnd)
    if cfg.requireKeywordMatch and not keywordsMatch(blob) then
        dlog(string.format('Keyword filter rejected window %s', windowName))
        return false
    end

    if (not cfg.allowInsertPrompts) and blob:find('insert', 1, true) then
        dlog('Insert prompt found but disabled in settings.')
        return false
    end

    return true
end

local function checkForPrompts(forceRun)
    if not cfg.enabled and not forceRun then return end

    if cfg.autoDisableZoning and isZoningOrNotReady() then
        if not zonedPause then
            zonedPause = true
            log('warn', 'Paused while zoning / not in game.')
        end
        return
    end

    if zonedPause then
        zonedPause = false
        log('info', 'Resumed after zoning.')
    end

    if cfg.autoDisableCombat and isCombat() then
        dlog('In combat; skipping prompt click this pulse.')
        return
    end

    if not isAllowedByLists() then return end

    local clickedAny = false

    if cfg.exactDialogNotifyMode then
        forceExactDialogNotify()
    end

    -- Highest-priority exact path from your real /windows data.
    if clickConfirmedDialogBox() then
        clickedAny = true
    end

    for i = 1, #targetWindows do
        local wndName = targetWindows[i]
        local wnd = getWindow(wndName)
        if wnd and isAugPrompt(wndName, wnd) then
            local ok, btn = clickPositiveButton(wndName, wnd)
            if ok then
                clickedAny = true
                log('ok', string.format('Accepted prompt in %s via %s.', wndName, btn))
            else
                dlog(string.format('Window %s matched but no known positive button found.', wndName))
            end
        end
    end

    for i = 1, #dynamicItemWindows do
        local wndName = dynamicItemWindows[i]
        local wnd = getWindow(wndName)
        if wnd and isAugPrompt(wndName, wnd) then
            local ok, btn = clickPositiveButton(wndName, wnd)
            if ok then
                clickedAny = true
                log('ok', string.format('Accepted prompt in %s via %s.', wndName, btn))
            end
        end
    end

    -- If no normal path click happened, still try hard fallback.
    if not clickedAny then
        bruteForceNotifyFallback()
    end

    if cfg.aggressiveYesSpam then
        spamKnownAugYesButtons()
    end

    -- Explicit support for the classic ItemDisplay-window embedded remove-confirm prompt.
    if tryItemDisplayYesFallback() then
        clickedAny = true
    end

    -- Preferred MQ-native confirmation path. This uses MQ's own mapped yes handlers.
    if cfg.mqNativeYesMode and (hasAugRemovalCursorItem() or clickedAny) then
        mq.cmd('/squelch /yes')
        clickedAny = true
    end

    -- Deterministic no-window-name mode for heavily customized UIs:
    -- press ENTER while enabled so default "Yes" prompts close instantly.
    if cfg.forceEnterMode then
        local nowMs = math.floor(os.clock() * 1000)
        if nowMs - lastEnterPressMs > 120 then
            lastEnterPressMs = nowMs
            mq.cmd('/keypress ENTER')
            clickedAny = true
        end
    end

    -- Some client/UI combinations expose the confirm as a non-addressable modal.
    -- Fallback: when in augment-removal context, press Enter (default "Yes").
    if (not clickedAny) and cfg.blindConfirmFallback and hasAugRemovalCursorItem() then
        local nowMs = math.floor(os.clock() * 1000)
        if nowMs - lastEnterPressMs > 120 then
            lastEnterPressMs = nowMs
            mq.cmd('/keypress ENTER')
            dlog('Blind confirm fallback sent ENTER.')
        end
    end

    if clickedAny then
        safeRandomDelay()
    end
end

local function drawTextInput(label, value)
    local a, b = ImGui.InputText(label, value or '')
    if type(a) == 'boolean' then
        if a then
            return true, b
        end
        return false, value
    end
    local newVal = tostring(a or value or '')
    return newVal ~= (value or ''), newVal
end

-- MQ ImGui bindings differ by build:
-- some return (changed, value), others return only value.
local function sliderIntCompat(label, current, minV, maxV)
    local a, b = ImGui.SliderInt(label, current, minV, maxV)
    if type(a) == 'boolean' then
        return a, b
    end
    local newVal = tonumber(a) or current
    return newVal ~= current, newVal
end

-- PocketFarm-style neon theme helpers
local function pushAutoAugTheme()
    local nc, nv = 0, 0
    local function pv(var, ...)
        ImGui.PushStyleVar(var, ...)
        nv = nv + 1
    end
    local function pc(col, ...)
        ImGui.PushStyleColor(col, ...)
        nc = nc + 1
    end

    pv(ImGuiStyleVar.WindowRounding,   6)
    pv(ImGuiStyleVar.FrameRounding,    4)
    pv(ImGuiStyleVar.ItemSpacing,      6, 4)
    pv(ImGuiStyleVar.WindowBorderSize, 1.5)
    pv(ImGuiStyleVar.FrameBorderSize,  1)
    pv(ImGuiStyleVar.ScrollbarSize,    10)

    pc(ImGuiCol.WindowBg,              0.05, 0.06, 0.07, 0.97)
    pc(ImGuiCol.ChildBg,               0.04, 0.06, 0.04, 1.00)
    pc(ImGuiCol.Border,                0.12, 0.55, 0.22, 0.70)
    pc(ImGuiCol.FrameBg,               0.04, 0.07, 0.04, 1.00)
    pc(ImGuiCol.FrameBgHovered,        0.07, 0.14, 0.07, 1.00)
    pc(ImGuiCol.TitleBg,               0.04, 0.16, 0.08, 1.00)
    pc(ImGuiCol.TitleBgActive,         0.05, 0.22, 0.10, 1.00)
    pc(ImGuiCol.Header,                0.05, 0.20, 0.09, 1.00)
    pc(ImGuiCol.HeaderHovered,         0.08, 0.30, 0.13, 1.00)
    pc(ImGuiCol.Separator,             0.10, 0.50, 0.18, 0.80)
    pc(ImGuiCol.ScrollbarBg,           0.00, 0.00, 0.00, 0.50)
    pc(ImGuiCol.ScrollbarGrab,         0.10, 0.45, 0.18, 1.00)
    pc(ImGuiCol.ScrollbarGrabHovered,  0.15, 0.65, 0.25, 1.00)
    pc(ImGuiCol.CheckMark,             0.20, 1.00, 0.40, 1.00)
    pc(ImGuiCol.SliderGrab,            0.20, 1.00, 0.40, 1.00)
    pc(ImGuiCol.Text,                  0.88, 0.92, 0.88, 1.00)
    pc(ImGuiCol.Button,                0.08, 0.28, 0.12, 1.00)
    pc(ImGuiCol.ButtonHovered,         0.12, 0.42, 0.18, 1.00)
    pc(ImGuiCol.ButtonActive,          0.16, 0.58, 0.24, 1.00)

    return nc, nv
end

local function popAutoAugTheme(nc, nv)
    if nc and nc > 0 then ImGui.PopStyleColor(nc) end
    if nv and nv > 0 then ImGui.PopStyleVar(nv) end
end

local function neonButton(label, w, h)
    ImGui.PushStyleColor(ImGuiCol.Button,        0.08, 0.28, 0.12, 1.00)
    ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 0.14, 0.50, 0.22, 1.00)
    ImGui.PushStyleColor(ImGuiCol.ButtonActive,  0.18, 0.62, 0.27, 1.00)
    ImGui.PushStyleColor(ImGuiCol.Text,          0.88, 0.95, 0.88, 1.00)
    local r = ImGui.Button(label, w or 0, h or 0)
    ImGui.PopStyleColor(4)
    return r
end

-- Debounced button toggle to avoid double-flip behavior on MQ builds
-- that evaluate click state more than once per visible frame.
local function toggleCompat(id, label, current)
    local nowMs = math.floor(os.clock() * 1000)
    local text = string.format('%s: %s', label, current and 'ON' or 'OFF')
    if neonButton(text .. '##' .. id, 0, 0) then
        local last = lastToggleAt[id] or 0
        if (nowMs - last) > 180 then
            lastToggleAt[id] = nowMs
            return true, not current
        end
    end
    return false, current
end

local function DrawUI()
    ueqFloat.drawFloating({
        id = 'AutoAugClose',
        resourceName = 'AutoAugClose',
        windowTitle = 'Hide / show — AutoAug',
        --- Float art: lua/autoaug/ueq-autoaug.png (Ultimate EQ AutoAug); not the shared MAUI default.
        imageRelPath = 'autoaug/ueq-autoaug.png',
        placement = 'bottom_right',
        sizePx = 100,
        fallbackLabel = 'AUG',
        isAnyOpen = function()
            return cfg.showUI == true
        end,
        onClick = function()
            cfg.showUI = not cfg.showUI
            saveConfig()
            log('info', string.format('UI toggled to %s.', tostring(cfg.showUI)))
        end,
        tooltipHide = 'Hide settings UI (automation keeps running)',
        tooltipShow = 'Show settings UI',
    })

    if cfg.showUI then
        local open = true
        local beginOk = false
        local beginVisible = false
        local ncolors, nvars = pushAutoAugTheme()

        local cond = nil
        if _G.ImGuiCond and _G.ImGuiCond.FirstUseEver then
            cond = _G.ImGuiCond.FirstUseEver
        end

        if cond then
            pcall(ImGui.SetNextWindowSize, 520, 460, cond)
        else
            pcall(ImGui.SetNextWindowSize, 520, 460)
        end

        local okBegin, visibleOrErr = pcall(ImGui.Begin, string.format('%s##Main', SCRIPT_NAME), open)
        if okBegin then
            beginOk = true
            beginVisible = visibleOrErr and true or false
        else
            log('err', string.format('ImGui.Begin failed: %s', tostring(visibleOrErr)))
            popAutoAugTheme(ncolors, nvars)
        end

        if beginOk then
            local okBody, errBody = xpcall(function()
                if not beginVisible then return end
                local changed

                changed, cfg.enabled = toggleCompat('enabled', 'Enabled', cfg.enabled)
                if changed then saveConfig() end

                ImGui.SameLine()
                changed, cfg.debug = toggleCompat('debug', 'Debug', cfg.debug)
                if changed then saveConfig() end

                changed, cfg.exactDialogNotifyMode = toggleCompat('exact_notify', 'Exact notify mode (ConfirmationDialogBox)', cfg.exactDialogNotifyMode)
                if changed then saveConfig() end

                local pulse = tonumber(cfg.pulseMs) or 75
                changed, pulse = sliderIntCompat('Pulse (ms)', pulse, 50, 250)
                if changed then
                    cfg.pulseMs = tonumber(pulse) or 75
                    saveConfig()
                end

                local minDelay = tonumber(cfg.minDelay) or 50
                changed, minDelay = sliderIntCompat('Min click delay (ms)', minDelay, 25, 500)
                if changed then
                    cfg.minDelay = tonumber(minDelay) or 50
                    saveConfig()
                end

                local maxDelay = tonumber(cfg.maxDelay) or 150
                changed, maxDelay = sliderIntCompat('Max click delay (ms)', maxDelay, 25, 1000)
                if changed then
                    cfg.maxDelay = math.max(tonumber(maxDelay) or 150, tonumber(cfg.minDelay) or 50)
                    saveConfig()
                end

                ImGui.Separator()
                if neonButton('Save Now', 0, 0) then
                    saveConfig()
                    log('ok', 'Configuration saved.')
                end
                ImGui.SameLine()
                if neonButton('Toggle On/Off', 0, 0) then
                    cfg.enabled = not cfg.enabled
                    saveConfig()
                    log('info', string.format('Enabled: %s', tostring(cfg.enabled)))
                end
                ImGui.SameLine()
                if neonButton('Hide UI', 0, 0) then
                    cfg.showUI = false
                    saveConfig()
                end
            end, debug.traceback)

            pcall(ImGui.End)

            if not okBody then
                log('err', string.format('UI draw error: %s', tostring(errBody)))
            end
            popAutoAugTheme(ncolors, nvars)
        end
    end
end

local function printStatus()
    log('info', string.format('Enabled=%s Debug=%s Pulse=%dms Delay=%d-%dms',
        tostring(cfg.enabled), tostring(cfg.debug), tonumber(cfg.pulseMs) or 75, tonumber(cfg.minDelay) or 50, tonumber(cfg.maxDelay) or 150))
end

local function handleCommand(line)
    local args = {}
    for a in string.gmatch(line or '', '%S+') do
        args[#args + 1] = string.lower(a)
    end

    local cmd = args[1] or 'status'
    if cmd == 'on' then
        cfg.enabled = true
        saveConfig()
        log('ok', 'Auto close enabled.')
    elseif cmd == 'off' then
        cfg.enabled = false
        saveConfig()
        log('warn', 'Auto close disabled.')
    elseif cmd == 'toggle' then
        cfg.enabled = not cfg.enabled
        saveConfig()
        log('info', string.format('Auto close toggled to %s.', tostring(cfg.enabled)))
    elseif cmd == 'debug' then
        cfg.debug = not cfg.debug
        saveConfig()
        log('info', string.format('Debug toggled to %s.', tostring(cfg.debug)))
    elseif cmd == 'ui' then
        cfg.showUI = not cfg.showUI
        saveConfig()
        log('info', string.format('UI toggled to %s.', tostring(cfg.showUI)))
    elseif cmd == 'status' then
        printStatus()
    elseif cmd == 'dump' then
        dumpAugWindows()
    elseif cmd == 'test' or cmd == 'click' then
        checkForPrompts(true)
        log('info', 'Ran forced prompt scan.')
    elseif cmd == 'help' then
        log('info', 'Usage: /augclose on|off|toggle|status|debug|ui|test|dump|help')
    else
        log('warn', string.format('Unknown subcommand: %s', cmd))
        log('info', 'Usage: /augclose on|off|toggle|status|debug|ui|test|dump|help')
    end
end

local function cleanup()
    pcall(function() mq.unbind('/augclose') end)
    pcall(function() mq.imgui.destroy(SCRIPT_NAME) end)
    saveConfig()
    log('info', 'Stopped.')
end

math.randomseed(os.time())
loadConfig()

mq.bind('/augclose', handleCommand)
mq.imgui.init(SCRIPT_NAME, DrawUI)

log('ok', 'Loaded. Command: /augclose help')
printStatus()
log('info', 'Headless mode ready. Use /augclose on and /augclose test to verify.')

while running do
    checkForPrompts()
    mq.delay(math.max(50, tonumber(cfg.pulseMs) or 75))
end

cleanup()
