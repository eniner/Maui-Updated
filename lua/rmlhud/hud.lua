--[[
  rmlhud core — RmlUi vitals window (used by /lua run rmlhud and teghud wrapper).
]]

local mq = require('mq')
local rml = require('rmlui')

local WINDOW = 'Vitals'
local DEFAULT = { x = 60, y = 420, width = 384, height = 420 }

local CLASS_COLORS = {
    WAR = '#b0533f', CLR = '#c9c6b8', PAL = '#d18fb4', RNG = '#5f9c4a', SHD = '#6b3fa0',
    DRU = '#d07a2a', MNK = '#3f9c8c', BRD = '#c4a43b', ROG = '#b8a742', SHM = '#3f6fb0',
    NEC = '#7a4fb8', WIZ = '#3f6fd8', MAG = '#c0503b', ENC = '#a05ac8', BST = '#9c6b3f',
    BER = '#b03f3f',
}

local CON_COLORS = {
    GREY = '#9aa0ab', GREEN = '#5fd068', ['LIGHT BLUE'] = '#6fd3ff', BLUE = '#5a8dff',
    WHITE = '#ffffff', YELLOW = '#f2d44b', RED = '#ff5d5d',
}

local function commas(n)
    local s = tostring(math.floor(tonumber(n) or 0))
    local out = s:reverse():gsub('(%d%d%d)', '%1,'):reverse()
    return (out:gsub('^,', ''))
end

local function pct(n)
    n = tonumber(n) or 0
    if n < 0 then n = 0 elseif n > 100 then n = 100 end
    return n
end

local function s(fn, default)
    local ok, v = pcall(fn)
    if not ok or v == nil or v == '' then return default end
    return tostring(v)
end

local M = {}

function M.default_pos()
    return DEFAULT
end

---@return table|nil ctx, string|nil err
function M.open()
    local win, err = rml.open(WINDOW, 'rmlhud/vitals.rml', DEFAULT)
    if not win then return nil, err end

    local ctx = {
        win = win,
        running = true,
        next_update = 0,
    }

    local function set_bar(prefix, cur, max, percent)
        percent = pct(percent)
        win:style(prefix .. '_fill', 'width', string.format('%.1f%%', percent))
        win:text(prefix .. '_pct', string.format('%d%%', math.floor(percent + 0.5)))
        if cur and max then
            win:text(prefix .. '_txt', commas(cur) .. ' / ' .. commas(max))
        end
    end

    function ctx:update()
        if mq.TLO.MacroQuest.GameState() ~= 'INGAME' then return end
        local me = mq.TLO.Me
        if not me() then return end

        local cls = me.Class.ShortName() or ''
        win:text('name', me.CleanName() or me.Name() or '?')
        local zone = s(function() return mq.TLO.Zone.ShortName() end, '')
        win:text('sub', string.format('Level %d %s%s',
            me.Level() or 0, me.Class.Name() or '', zone ~= '' and ('  ·  ' .. zone) or ''))
        win:text('classtile', cls)
        win:style('classtile', 'background-color', CLASS_COLORS[cls] or '#3b4a6b')

        local hp = pct(me.PctHPs())
        set_bar('hp', me.CurrentHPs(), me.MaxHPs(), hp)
        win:class('hp_row', 'low', hp > 0 and hp < 25)

        local maxMana = me.MaxMana() or 0
        win:class('mana_row', 'off', maxMana <= 0)
        if maxMana > 0 then set_bar('mana', me.CurrentMana(), maxMana, me.PctMana()) end

        set_bar('end', me.CurrentEndurance(), me.MaxEndurance(), me.PctEndurance())

        local xp = pct(me.PctExp())
        win:style('xp_fill', 'width', string.format('%.1f%%', xp))
        win:text('xp_txt', string.format('%.1f%%', xp))
        local aaPct = pct(me.PctAAExp())
        win:style('aa_fill', 'width', string.format('%.1f%%', aaPct))
        win:text('aa_txt', string.format('%d pts', me.AAPoints() or 0))

        win:class('body', 'combat', me.Combat() == true)
        win:text('btn_sit', me.Sitting() and 'Stand' or 'Sit')

        local t = mq.TLO.Target
        if t() then
            local tp = pct(t.PctHPs())
            win:class('target', 'empty', false)
            win:text('t_name', t.CleanName() or '')
            win:style('t_name', 'color', CON_COLORS[t.ConColor() or ''] or '#ffffff')
            win:text('t_info', string.format('L%d %s  ·  %d%%  ·  %.0fft',
                t.Level() or 0, t.Class.ShortName() or '', math.floor(tp + 0.5), t.Distance() or 0))
            win:style('t_fill', 'width', string.format('%.1f%%', tp))
        else
            win:class('target', 'empty', true)
            win:text('t_name', 'No target')
            win:style('t_name', 'color', nil)
            win:text('t_info', '')
            win:style('t_fill', 'width', '0%')
        end

        local parts = {}
        for i = 1, 42 do
            local nm = s(function() return me.Buff(i).Name() end, '')
            if nm ~= '' then
                local dur = s(function() return me.Buff(i).Duration.TimeHMS() end, '')
                parts[#parts + 1] = string.format(
                    '<div class="buff-line"><span class="buff-name">%s</span><span class="buff-dur">%s</span></div>',
                    nm, dur)
            end
        end
        if #parts == 0 then
            parts[1] = '<div class="buff-empty">none</div>'
        end
        win:rml('buff_list', table.concat(parts))
    end

    ctx.actions = {
        ['window:close'] = function() ctx.running = false end,
        sit = function() mq.cmd(mq.TLO.Me.Sitting() and '/stand' or '/sit') end,
        target_self = function() mq.cmd('/target myself') end,
        clear_target = function() mq.cmd('/target clear') end,
    }

    function ctx:process_events()
        for ev in win:events() do
            if ev.type == 'click' and self.actions[ev.action] then
                self.actions[ev.action]()
            end
        end
    end

    function ctx:tick()
        local now = mq.gettime()
        if now >= self.next_update then
            self.next_update = now + 100
            self:update()
        end
    end

    function ctx:close()
        win:close()
    end

    return ctx
end

return M
