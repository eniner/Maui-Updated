--[[
  rmlui - Lua binding for the MQ2RmlUi plugin (RmlUi HTML/CSS-style windows).

    local rml = require('rmlui')
    local win = rml.open('mywin', 'myscript/ui/main.rml', { width = 320, height = 240 })
    win:text('title', 'Hello')
    win:style('bar', 'width', '42%')        -- animates if the RCSS has a transition on width
    win:class('card', 'combat', true)
    for ev in win:events() do print(ev.type, ev.id, ev.action, ev.value) end

  Ownership / lifetime:
    - Each script's Lua state tracks windows it opened.
    - On /lua stop the state is destroyed and a GC finalizer closes those windows
      immediately (no 5s wait). Explicit win:close() / rml.close_all() also work.
    - autoclose=true (default) is a plugin-side backup if events() stops without
      state teardown. Prefer leaving it on.

  RML attributes understood by the plugin:
    action="name"   reported as ev.action on click events (also stops window dragging on that element)
    drag="1"        mouse-drag on this element moves the window
    resize="1"      mouse-drag on this element resizes the window
]]

local mq = require('mq')
local ffi = require('ffi')

ffi.cdef [[
int rml_api_version();
int rml_ready();
int rml_open(const char* name, const char* path, int width, int height, int flags);
int rml_close(const char* name);
int rml_reload(const char* name);
int rml_show(const char* name, int show);
int rml_is_open(const char* name);
int rml_set_window(const char* name, float x, float y, float width, float height);
int rml_set_default_pos(const char* name, float x, float y);
int rml_set_rml(const char* window, const char* id, const char* rml);
int rml_set_text(const char* window, const char* id, const char* text);
int rml_set_attr(const char* window, const char* id, const char* attr, const char* value);
int rml_set_class(const char* window, const char* id, const char* cls, int on);
int rml_set_style(const char* window, const char* id, const char* property, const char* value);
int rml_set_value(const char* window, const char* id, const char* value);
const char* rml_get_value(const char* window, const char* id);
const char* rml_poll(const char* name);
int rml_load_font(const char* path, int fallback);
int rml_debugger(const char* name, int show);
]]

local PLUGIN = 'MQ2RmlUi'
local API_VERSION = 1

local M = {
    FLAG_AUTOCLOSE = 1,
    FLAG_CLICKTHROUGH = 2,
}

local lib

-- Windows opened by THIS script's Lua state (MacroQuest gives each /lua run its own state).
local owned = {}

local function plugin_loaded()
    return mq.TLO.Plugin(PLUGIN).IsLoaded() == true
end

local function ensure()
    if not plugin_loaded() then
        mq.cmd('/squelch /plugin ' .. PLUGIN .. ' noauto')
        mq.delay(3000, plugin_loaded)
        if not plugin_loaded() then
            error(PLUGIN .. ' is not loaded and could not be loaded (is plugins\\' .. PLUGIN .. '.dll present?)', 3)
        end
    end
    if not lib then
        lib = ffi.load(PLUGIN)
        local v = lib.rml_api_version()
        if v ~= API_VERSION then
            lib = nil
            error(string.format('%s API version %d, this script expects %d', PLUGIN, v, API_VERSION), 3)
        end
    end
    if lib.rml_ready() == 0 then
        error(PLUGIN .. ' is loaded but RmlUi is not initialized', 3)
    end
    return lib
end

local function resolve(path)
    if path:match('^%a:[\\/]') or path:match('^[\\/]') then return path end
    return mq.luaDir .. '/' .. path
end

local function track(name)
    if name and name ~= '' then owned[name] = true end
end

local function untrack(name)
    if name then owned[name] = nil end
end

local function close_owned()
    local api = lib
    if not api then return end
    local okReady, ready = pcall(function() return api.rml_ready() end)
    if not okReady or ready ~= 1 then return end
    local names = {}
    for name in pairs(owned) do names[#names + 1] = name end
    for _, name in ipairs(names) do
        pcall(function() api.rml_close(name) end)
        owned[name] = nil
    end
end

-- Close owned windows the instant this script's Lua state is torn down (/lua stop).
-- Plugin autoclose is only a backup (~seconds); this is what makes stop feel instant.
do
    local guard = ffi.new('char[1]')
    ffi.gc(guard, function()
        close_owned()
    end)
    M._unload_guard = guard
end

local Window = {}
Window.__index = Window

---@return table|nil window, string|nil err
function M.open(name, path, opts)
    opts = opts or {}
    local api = ensure()
    local flags = 0
    if opts.autoclose ~= false then flags = flags + M.FLAG_AUTOCLOSE end
    if opts.clickthrough then flags = flags + M.FLAG_CLICKTHROUGH end

    local full = resolve(path)
    if api.rml_open(name, full, opts.width or 0, opts.height or 0, flags) == 0 then
        return nil, 'could not open ' .. full
    end
    if opts.x and opts.y then api.rml_set_default_pos(name, opts.x, opts.y) end
    track(name)
    return setmetatable({ name = name, path = full, cache = {} }, Window)
end

function M.load_font(path, fallback)
    return ensure().rml_load_font(resolve(path), fallback and 1 or 0) == 1
end

-- Only forward changes: every DOM write invalidates layout in RmlUi.
local function cached(self, key, value, fn)
    if self.cache[key] == value then return true end
    if fn() == 1 then
        self.cache[key] = value
        return true
    end
    return false
end

function Window:text(id, value)
    value = tostring(value == nil and '' or value)
    return cached(self, 't\0' .. id, value, function() return lib.rml_set_text(self.name, id, value) end)
end

function Window:rml(id, value)
    value = tostring(value or '')
    return cached(self, 'r\0' .. id, value, function() return lib.rml_set_rml(self.name, id, value) end)
end

function Window:style(id, property, value)
    value = value ~= nil and tostring(value) or ''
    return cached(self, 's\0' .. id .. '\0' .. property, value, function() return lib.rml_set_style(self.name, id, property, value) end)
end

function Window:class(id, cls, on)
    on = on and true or false
    return cached(self, 'c\0' .. id .. '\0' .. cls, on, function() return lib.rml_set_class(self.name, id, cls, on and 1 or 0) end)
end

function Window:attr(id, name, value)
    local key = 'a\0' .. id .. '\0' .. name
    if value == nil then
        self.cache[key] = nil
        return lib.rml_set_attr(self.name, id, name, nil) == 1
    end
    value = tostring(value)
    return cached(self, key, value, function() return lib.rml_set_attr(self.name, id, name, value) end)
end

local THEMES = { 'azure', 'violet', 'ember', 'jade', 'rose' }

-- Accent theme of the rmlui/theme/window.rml chrome.
function Window:theme(name)
    for _, t in ipairs(THEMES) do
        self:class('body', 'theme-' .. t, t == name)
    end
end

function Window:set_value(id, value)
    return lib.rml_set_value(self.name, id, tostring(value or '')) == 1
end

function Window:value(id)
    local p = lib.rml_get_value(self.name, id)
    if p == nil then return nil end
    return ffi.string(p)
end

function Window:events()
    return function()
        local p = lib.rml_poll(self.name)
        if p == nil then return nil end
        local t, id, action, value, button = ffi.string(p):match('^(.-)\t(.-)\t(.-)\t(.-)\t(.-)$')
        return { type = t, id = id, action = action, value = value, button = tonumber(button) }
    end
end

function Window:show(visible)
    return lib.rml_show(self.name, visible == false and 0 or 1) == 1
end

function Window:place(x, y, width, height)
    return lib.rml_set_window(self.name, x or -1, y or -1, width or 0, height or 0) == 1
end

function Window:reload()
    self.cache = {}
    return lib.rml_reload(self.name) == 1
end

function Window:is_open()
    return lib ~= nil and lib.rml_ready() == 1 and lib.rml_is_open(self.name) == 1
end

function Window:debugger(show)
    return lib.rml_debugger(self.name, show == false and 0 or 1) == 1
end

function Window:close()
    untrack(self.name)
    if lib and lib.rml_ready() == 1 then lib.rml_close(self.name) end
    self.cache = {}
end

--- Close a window by name (also untracks it from this script).
function M.close(name)
    name = tostring(name or '')
    if name == '' then return false end
    untrack(name)
    local api = ensure()
    return api.rml_close(name) == 1
end

--- Close every window this script opened. Call from intentional quit paths.
function M.close_all()
    ensure()
    close_owned()
end

return M
