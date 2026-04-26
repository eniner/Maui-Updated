local mq = require('mq')
local ImGui = require('ImGui')

local ITEM_NAMES = {
    'Bottle of Condensed Jenkins',
}
local PRE_CLICK_DELAY_MS = 400

local queue = {}
local queued = {}
local state = {
    running = true,
    enabled = true,
    show_ui = true,
}

local function log(fmt, ...)
    printf('[HailItemBuffBot] ' .. fmt, ...)
end

local function enqueue(name)
    if not name or name == '' then return end
    if not state.enabled then return end
    if queued[name] then return end
    queued[name] = true
    table.insert(queue, name)
    log('Queued %s', name)
end

local function target_player(name)
    local spawn_id = mq.TLO.Spawn(string.format('pc =%s', name)).ID()
    if not spawn_id then
        return nil
    end

    mq.cmdf('/target id %d', spawn_id)
    mq.delay(2500, function() return mq.TLO.Target.ID() == spawn_id end)

    if mq.TLO.Target.ID() ~= spawn_id then
        return nil
    end

    if mq.TLO.Target.Type() ~= 'PC' then
        return nil
    end

    if mq.TLO.Target.CleanName() ~= name then
        return nil
    end

    return spawn_id
end

local function use_item(item_name, expected_target_id, expected_name)
    if not mq.TLO.FindItem('=' .. item_name)() then
        log('Missing item: %s', item_name)
        return false
    end

    if mq.TLO.Target.ID() ~= expected_target_id then
        log('Target changed, skipping %s on %s', item_name, expected_name)
        return false
    end

    if mq.TLO.Target.ID() == mq.TLO.Me.ID() then
        log('Safety block: refusing to click %s on self', item_name)
        return false
    end

    mq.delay(3000, function() return not mq.TLO.Me.Casting.ID() end)
    mq.delay(PRE_CLICK_DELAY_MS)
    mq.cmdf('/itemnotify "%s" rightmouseup', item_name)
    mq.delay(8000, function() return not mq.TLO.Me.Casting.ID() end)
    return true
end

local function handle_hail(_line, sender)
    enqueue(sender)
end

mq.event('HIBB_Hail1', "#1# says, 'Hail, " .. mq.TLO.Me.Name() .. "#*#'", handle_hail)
mq.event('HIBB_Hail2', "#1# says, in #*#, 'Hail, " .. mq.TLO.Me.Name() .. "#*#'", handle_hail)
mq.event('HIBB_Hail3', "#1# says, 'buff me#*#'", handle_hail)
mq.event('HIBB_Hail4', "#1# says, in #*#, 'buff me#*#'", handle_hail)
mq.event('HIBB_Hail5', "#1# tells you, 'buff me#*#'", handle_hail)
mq.event('HIBB_Hail6', "#1# tells you, in #*#, 'buff me#*#'", handle_hail)

mq.bind('/hibb', function(...)
    local arg = table.concat({ ... }, ' ')
    local cmd = (arg or ''):lower()
    if cmd == 'on' then
        state.enabled = true
        log('Enabled')
    elseif cmd == 'off' then
        state.enabled = false
        log('Disabled')
    elseif cmd == 'toggle' then
        state.enabled = not state.enabled
        log(state.enabled and 'Enabled' or 'Disabled')
    elseif cmd == 'show' then
        state.show_ui = true
    elseif cmd == 'hide' then
        state.show_ui = false
    else
        log('Commands: /hibb on | off | toggle | show | hide')
    end
end)

local function draw_ui()
    if not state.show_ui then return end
    local is_open
    state.show_ui, is_open = ImGui.Begin('Hail Item BuffBot##HIBB', state.show_ui, ImGuiWindowFlags.AlwaysAutoResize)
    if is_open then
        state.enabled = ImGui.Checkbox('Enabled', state.enabled)
        ImGui.Text(string.format('Queue: %d', #queue))
        if ImGui.Button('Clear Queue') then
            queue = {}
            queued = {}
            log('Queue cleared')
        end
        ImGui.SameLine()
        if ImGui.Button('Stop Script') then
            state.running = false
        end
    end
    ImGui.End()
end

mq.imgui.init('HailItemBuffBotUI', draw_ui)

log('Running. Say "Hail, %s" (or "buff me") to receive clickies.', mq.TLO.Me.Name())
log('Use /hibb on|off|toggle|show|hide')

while state.running do
    mq.doevents()

    if state.enabled and #queue > 0 then
        local name = table.remove(queue, 1)
        queued[name] = nil

        local target_id = target_player(name)
        if target_id then
            log('Targeted %s, using clickies...', name)
            for _, item_name in ipairs(ITEM_NAMES) do
                use_item(item_name, target_id, name)
            end
        else
            log('Could not target %s', name)
        end
    end

    mq.delay(50)
end

mq.unbind('/hibb')
log('Stopped')
