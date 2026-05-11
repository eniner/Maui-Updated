--[[
  EQUI Module 0 — Core Framework (MQ Fresh / MacroQuest Lua)

  NOTE: MQ Fresh registers ImGui via mq.imgui.init(name, callback). There is no mq.AddCallback
  for Lua UI in this stack — treat imgui.init as the canonical hook.

  Constraints from design brief:
  - TLO-only reads, pcall-wrapped
  - mq.delay() in main loop (never os.sleep)
  - Config under mq.configDir .. '/EQUI/'
]]

local mq = require('mq')
require('ImGui')

local Core = {
    _version = '0.1.0',
    running = true,
    debug_overlay = false,
    --- perf
    _frame_ms = 0,
    _last_clock = nil,
    _tlo_errors = 0,
    _tlo_errors_sec = 0,
    _last_err_tick = 0,
    --- module render: suspend after pcall failure (ms timestamp per module)
    _render_fail_until = {},
}

-- ─────────────────────────────────────────────────────────────────────────────
-- Safe TLO wrapper (counts failures per second for debug HUD)
-- ─────────────────────────────────────────────────────────────────────────────

local function safe_tlo(fn, default)
    local ok, a, b, c = pcall(fn)
    if ok then
        if a ~= nil then return a, b, c end
        return default
    end
    Core._tlo_errors = Core._tlo_errors + 1
    return default
end

Core.safe_tlo = safe_tlo

--- Per-module visibility (menu / future binds). Hidden modules skip render but stay loaded.
Core._module_hidden = {}

function Core.module_is_visible(name)
    return Core._module_hidden[name] ~= true
end

---@param name string
---@param visible boolean
function Core.set_module_visible(name, visible)
    Core._module_hidden[name] = not visible
end

-- ─────────────────────────────────────────────────────────────────────────────
-- CONFIG (INI-style Lua pickle — MQ convention)
-- ─────────────────────────────────────────────────────────────────────────────

local Config = {
    _data = {},
}

local function sanitize(s)
    return tostring(s or 'unknown'):gsub('[^%w%-_]', '_')
end

local function config_path()
    local server = sanitize(safe_tlo(function() return mq.TLO.MacroQuest.Server() end, 'server'))
    local name = sanitize(safe_tlo(function() return mq.TLO.Me.CleanName() end, 'char'))
    return string.format('%s/EQUI/%s_%s_core.lua', mq.configDir, server, name)
end

function Config.ensure_dir()
    local dir = mq.configDir .. '/EQUI'
    os.execute('mkdir "' .. dir:gsub('/', '\\') .. '" 2>nul') -- Windows; fails silently on *nix if absent
end

function Config.load()
    Config.ensure_dir()
    local path = config_path()
    local ok, data = pcall(dofile, path)
    if ok and type(data) == 'table' then
        Config._data = data
    end
end

function Config.get(key, default)
    local cur = Config._data
    for part in string.gmatch(key, '[^.]+') do
        if type(cur) ~= 'table' then return default end
        cur = cur[part]
        if cur == nil then return default end
    end
    return cur
end

function Config.set(key, value)
    local parts = {}
    for p in string.gmatch(key, '[^.]+') do parts[#parts + 1] = p end
    local leaf = parts[#parts]
    table.remove(parts, #parts)
    local cur = Config._data
    for _, p in ipairs(parts) do
        cur[p] = cur[p] or {}
        cur = cur[p]
    end
    cur[leaf] = value
end

function Config.save()
    Config.ensure_dir()
    local path = config_path()
    pcall(function() mq.pickle(path, Config._data) end)
end

Core.Config = Config

-- ─────────────────────────────────────────────────────────────────────────────
-- THEME (Dark EQ-inspired)
-- ─────────────────────────────────────────────────────────────────────────────

local Theme = {
    colors = {
        health = { 0.22, 0.82, 0.42, 1 },
        mana = { 0.28, 0.52, 0.98, 1 },
        endurance = { 0.96, 0.76, 0.28, 1 },
        xp = { 0.42, 0.82, 0.96, 1 },
        danger = { 0.92, 0.28, 0.28, 1 },
        buff = { 0.32, 0.72, 0.62, 1 },
        debuff = { 0.72, 0.35, 0.92, 1 },
        accent_gold = { 0.93, 0.72, 0.28, 1 },
        bg_deep = { 0.05, 0.06, 0.10, 0.94 },
        frame = { 0.14, 0.16, 0.22, 1 },
        text = { 0.92, 0.94, 0.97, 1 },
        muted = { 0.55, 0.58, 0.65, 1 },
    },
    _push_depth = 0,
}

function Theme.apply()
    local ImGui = ImGui
    local c = Theme.colors
    ImGui.PushStyleColor(ImGuiCol.WindowBg, c.bg_deep[1], c.bg_deep[2], c.bg_deep[3], c.bg_deep[4])
    ImGui.PushStyleColor(ImGuiCol.ChildBg, c.frame[1], c.frame[2], c.frame[3], 0.92)
    ImGui.PushStyleColor(ImGuiCol.Border, 0.35, 0.30, 0.22, 0.65)
    ImGui.PushStyleColor(ImGuiCol.Text, c.text[1], c.text[2], c.text[3], c.text[4])
    Theme._push_depth = 4
end

function Theme.pop()
    if Theme._push_depth > 0 then
        ImGui.PopStyleColor(Theme._push_depth)
        Theme._push_depth = 0
    end
end

Core.Theme = Theme

-- ─────────────────────────────────────────────────────────────────────────────
-- FONT (fallback: window font scale — true font loading is build-dependent)
-- ─────────────────────────────────────────────────────────────────────────────

local Font = {
    size_stack = {},
}

function Font.push(size_key)
    local scale = 1.0
    if size_key == 'small' then scale = 0.85 end
    if size_key == 'large' then scale = 1.15 end
    if size_key == 'header' then scale = 1.35 end
    Font.size_stack[#Font.size_stack + 1] = scale
    ImGui.SetWindowFontScale(scale)
end

function Font.pop()
    ImGui.SetWindowFontScale(1.0)
    Font.size_stack[#Font.size_stack] = nil
end

Core.Font = Font

-- ─────────────────────────────────────────────────────────────────────────────
-- STATE
-- ─────────────────────────────────────────────────────────────────────────────

local State = {
    data = {
        inCombat = false,
        isDead = false,
        isZoning = false,
        isMedding = false,
        groupSize = 0,
        raidSize = 0,
        currentZone = '',
        gameState = '',
    },
    listeners = {},
}

function State.get(key)
    return State.data[key]
end

function State.update()
    local gs = safe_tlo(function() return mq.TLO.MacroQuest.GameState() end, '')
    State.data.gameState = gs or ''
    State.data.isZoning = (gs ~= 'INGAME')

    State.data.isDead = safe_tlo(function() return mq.TLO.Me.Dead() end, false) and true or false
    local comb = safe_tlo(function() return mq.TLO.Me.Combat() end, false)
    State.data.inCombat = comb and comb ~= 0 and comb ~= false

    local med = safe_tlo(function() return mq.TLO.Me.Sitting() end, false)
    State.data.isMedding = med and true or false

    State.data.groupSize = tonumber(safe_tlo(function() return mq.TLO.Group.Members() end, 0)) or 0
    State.data.raidSize = tonumber(safe_tlo(function() return mq.TLO.Raid.Members() end, 0)) or 0
    State.data.currentZone = safe_tlo(function() return mq.TLO.Zone.ShortName() end, '')
end

function State.on(event, cb)
    State.listeners[event] = State.listeners[event] or {}
    table.insert(State.listeners[event], cb)
end

function State.fire(event, payload)
    local list = State.listeners[event]
    if not list then return end
    for _, cb in ipairs(list) do
        pcall(cb, payload)
    end
end

Core.State = State

-- ─────────────────────────────────────────────────────────────────────────────
-- MODULE REGISTRY (lazy require by name under lua/EQUI/modules/)
-- ─────────────────────────────────────────────────────────────────────────────

local Modules = {
    loaded = {},
}

--- Startup order and ImGui draw order (later windows paint on top).
Modules.AUTOLOAD_ORDER = {
    'vitals',
    'target',
    'buffs',
    'group',
    'spellbar',
    'hotbar',
    'inventory',
    'combatlog',
    'minimap',
    'menu',
}

function Modules.autoload_all()
    local n_ok = 0
    for _, name in ipairs(Modules.AUTOLOAD_ORDER) do
        if Modules.load(name) then
            n_ok = n_ok + 1
        end
    end
    print(('[EQUI] Autoload finished (%d/%d modules).'):format(n_ok, #Modules.AUTOLOAD_ORDER))
end

function Modules.load(name)
    if Modules.loaded[name] then return true end
    local path = 'EQUI.modules.' .. name
    local ok, mod = pcall(require, path)
    if not ok or type(mod) ~= 'table' then
        print(('[EQUI] Failed to load module %s: %s'):format(name, tostring(mod)))
        return false
    end
    Modules.loaded[name] = mod
    if type(mod.init) == 'function' then
        pcall(mod.init, Core)
    end
    print(('[EQUI] Loaded module: %s'):format(name))
    return true
end

function Modules.unload(name)
    local mod = Modules.loaded[name]
    if mod and type(mod.unload) == 'function' then
        pcall(mod.unload)
    end
    Modules.loaded[name] = nil
    package.loaded['EQUI.modules.' .. name] = nil
    print(('[EQUI] Unloaded module: %s'):format(name))
end

function Modules.reload(name)
    Modules.unload(name)
    return Modules.load(name)
end

Core.Modules = Modules

-- ─────────────────────────────────────────────────────────────────────────────
-- RENDER: core window + debug HUD
-- ─────────────────────────────────────────────────────────────────────────────

local function render_debug_overlay()
    if not Core.debug_overlay then return end
    ImGui.SetNextWindowBgAlpha(0.65)
    ImGui.Begin('EQUI Debug##equi_dbg', true, bit32.bor(ImGuiWindowFlags.AlwaysAutoResize, ImGuiWindowFlags.NoSavedSettings))
    ImGui.Text('EQUI Core v%s', Core._version)
    ImGui.Separator()
    ImGui.Text('Frame ~%.1f ms', Core._frame_ms)
    ImGui.Text('TLO errors (session): %d', Core._tlo_errors)
    ImGui.Text('TLO errors/sec: %d', Core._tlo_errors_sec)
    ImGui.Text('GameState: %s', tostring(State.data.gameState))
    ImGui.Text('Zone: %s', tostring(State.data.currentZone))
    ImGui.Text('Combat: %s  Dead: %s  Zoning: %s', tostring(State.data.inCombat), tostring(State.data.isDead),
        tostring(State.data.isZoning))
    ImGui.Text('Group: %d  Raid: %d', State.data.groupSize, State.data.raidSize)
    local n = 0
    local names = {}
    for _, nm in ipairs(Modules.AUTOLOAD_ORDER) do
        if Modules.loaded[nm] then
            n = n + 1
            names[#names + 1] = nm
        end
    end
    ImGui.Text('Loaded modules: %d', n)
    if #names > 0 then
        ImGui.PushTextWrapPos(ImGui.GetCursorPosX() + 280)
        ImGui.TextWrapped('%s', table.concat(names, ', '))
        ImGui.PopTextWrapPos()
    end
    ImGui.End()
end

local function render_main()
    local skip = State.data.isZoning or State.data.gameState ~= 'INGAME'
    if skip then
        ImGui.SetNextWindowBgAlpha(0.55)
        ImGui.Begin('EQUI##equi_zoning', true, bit32.bor(ImGuiWindowFlags.AlwaysAutoResize, ImGuiWindowFlags.NoSavedSettings))
        ImGui.TextColored(0.95, 0.55, 0.22, 1, State.data.isZoning and 'Zoning / not INGAME…' or 'Waiting for INGAME…')
        ImGui.End()
        render_debug_overlay()
        return
    end

    if not Config.get('show_core_shell', false) then
        render_debug_overlay()
        return
    end

    -- Compact shell: no giant empty panel (saves fill-rate + avoids imgui.ini remembering a huge rect).
    ImGui.SetNextWindowPos(24, 80, ImGuiCond.FirstUseEver)
    Theme.apply()
    local core_flags = bit32.bor(
        ImGuiWindowFlags.AlwaysAutoResize,
        ImGuiWindowFlags.NoSavedSettings
    )
    ImGui.Begin('EQUI Core##equi_main', true, core_flags)
    Font.push('header')
    ImGui.Text('EQUI — EverQuest UI overlay')
    Font.pop()
    ImGui.Separator()
    ImGui.PushTextWrapPos(ImGui.GetCursorPosX() + 420)
    ImGui.TextWrapped('Framework loaded. Add modules under lua/EQUI/modules/<name>.lua returning { init=..., render=..., unload=... }.')
    ImGui.PopTextWrapPos()
    ImGui.Spacing()
    if ImGui.Button('Toggle debug##equi_td') then
        Core.debug_overlay = not Core.debug_overlay
        Config.set('debug_overlay', Core.debug_overlay)
        Config.save()
    end
    ImGui.SameLine()
    if ImGui.Button('Save config##equi_sv') then
        Config.save()
    end
    Theme.pop()

    ImGui.End()

    render_debug_overlay()
end

local function measure_frame_start()
    local t = mq.gettime and mq.gettime() or (os.clock() * 1000)
    if Core._last_clock then
        Core._frame_ms = t - Core._last_clock
        if Core._frame_ms > 60 then
            -- degrade: skip optional work in future modules here
        end
    end
    Core._last_clock = t

    local sec = math.floor(t / 1000)
    if sec ~= Core._last_err_tick then
        Core._tlo_errors_sec = Core._tlo_errors - (Core._tlo_errors_snapshot or 0)
        Core._tlo_errors_snapshot = Core._tlo_errors
        Core._last_err_tick = sec
    end
end

local function now_ms()
    if mq.gettime then
        local ok, t = pcall(mq.gettime)
        if ok and type(t) == 'number' then return t end
    end
    return math.floor(os.clock() * 1000)
end

local function render_modules()
    local t = now_ms()
    for _, name in ipairs(Modules.AUTOLOAD_ORDER) do
        local mod = Modules.loaded[name]
        if mod and Core.module_is_visible(name) then
            local until_ms = Core._render_fail_until[name]
            if not (until_ms and t < until_ms) and type(mod.render) == 'function' then
                local ok, err = pcall(mod.render)
                if ok then
                    Core._render_fail_until[name] = nil
                else
                    Core._render_fail_until[name] = t + 5000
                    print(('[EQUI] render error in %s (paused 5s): %s'):format(name, tostring(err)))
                end
            end
        end
    end
end

local function on_gui()
    measure_frame_start()
    State.update()
    render_main()
    render_modules()
end

function Core.start()
    Config.load()
    Core.debug_overlay = Config.get('debug_overlay', false)

    mq.bind('/equi', function(cmd, arg1, arg2)
        local parts = {}
        local function add_tokens(s)
            if s == nil then return end
            if type(s) ~= 'string' then s = tostring(s) end
            for tok in s:gmatch('%S+') do
                parts[#parts + 1] = tok
            end
        end
        add_tokens(cmd); add_tokens(arg1); add_tokens(arg2)
        local sub = (parts[2] or ''):lower()
        local p1 = parts[3]

        if sub == '' or sub == 'help' then
            print('[EQUI] /equi help | debug | quit | core | load <name> | unload <name> | reload <name>')
        elseif sub == 'core' then
            local cur = not Config.get('show_core_shell', false)
            Config.set('show_core_shell', cur)
            Config.save()
            print(('[EQUI] Framework shell window = %s (/equi core toggles)'):format(cur and 'ON' or 'OFF'))
        elseif sub == 'debug' then
            Core.debug_overlay = not Core.debug_overlay
            Config.set('debug_overlay', Core.debug_overlay)
            Config.save()
            print(('[EQUI] debug overlay = %s'):format(tostring(Core.debug_overlay)))
        elseif sub == 'quit' then
            Core.running = false
        elseif sub == 'load' and p1 then
            Modules.load(p1)
        elseif sub == 'unload' and p1 then
            Modules.unload(p1)
        elseif sub == 'reload' and p1 then
            Modules.reload(p1)
        else
            print('[EQUI] Unknown /equi command. Try /equi help')
        end
    end)

    mq.imgui.init('EQUI_Core', function()
        if Core.running then
            pcall(on_gui)
        end
    end)

    Modules.autoload_all()

    print(('[EQUI] Core v%s started. Modules autoloaded — /equi help  (/equi core = framework readme window)'):format(Core._version))

    while Core.running do
        mq.delay(0)
        if mq.doevents then mq.doevents() end
    end

    pcall(function() mq.imgui.destroy('EQUI_Core') end)
    for i = #Modules.AUTOLOAD_ORDER, 1, -1 do
        local name = Modules.AUTOLOAD_ORDER[i]
        if Modules.loaded[name] then
            Modules.unload(name)
        end
    end
    Config.save()
    print('[EQUI] Core stopped (modules unloaded, native /showwindow restored where applicable).')
    mq.exit()
end

return Core
