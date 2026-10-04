--[[
  Ultimate EQ — God Tier + God Talents (RmlUi)

  Run:   /lua run godtier
  Stop:  /godtier quit   or   /lua stop godtier

  Commands:
    /godtier            toggle progression window
    /godtalents         toggle talent window
    /godtier both       show both
    /godtier hide       hide both
    /godtier refresh    reload talent catalog
]]

local mq = require('mq')
local rmlui = require('rmlui')

local running = true
local showProgress = true
local showTalents = true
local search = ''
local selectedTalent = 1
local catalog = { classes = {}, talents = {} }
local filtered_cache = {}

local CLASS_NAME = {
  [1] = 'Warrior', [2] = 'Cleric', [3] = 'Paladin', [4] = 'Ranger',
  [5] = 'Shadowknight', [6] = 'Druid', [7] = 'Monk', [8] = 'Bard',
  [9] = 'Rogue', [10] = 'Shaman', [11] = 'Necromancer', [12] = 'Wizard',
  [13] = 'Magician', [14] = 'Enchanter', [15] = 'Beastlord', [16] = 'Berserker',
}

local GOD_ZONES = {
  elddar = 'Elddar Forest (71+)',
  oldkurn = 'Old Kurns Tower (71+)',
  crystallos = 'Crystallos (75+)',
  soldungc = 'Caverns / soldungc (maps)',
  bloodmoon = 'Bloodmoon Keep (maps)',
  guildlobby = 'Guild Lobby',
}

local STEPS = {
  {
    level = 71,
    title = '71 — enter Elddar or Old Kurn at 70',
    detail = 'Hail Illuminous. Seism ports to the zone. Auto-level on enter.',
    check = function(ctx) return ctx.level >= 71 end,
  },
  {
    level = 72,
    title = '72 — 250 Tier 9 credits to Illuminous',
    detail = 'Say "I Have Proven Myself" at 71 with 250 T9 credits.',
    check = function(ctx) return ctx.level >= 72 end,
  },
  {
    level = 73,
    title = '73 — 4x item 149854 (Power of the Ancients / Medallion of Tactics)',
    detail = 'Boss drops in Elddar / Old Kurn (level 78).',
    item_id = 149854,
    need = 4,
    check = function(ctx) return ctx.level >= 73 or ctx.items[149854] >= 4 end,
  },
  {
    level = 74,
    title = '74 — four Keeper icons 149855–149858',
    detail = 'Keepers in Elddar / Old Kurn. Reserved out of random pools.',
    item_ids = { 149855, 149856, 149857, 149858 },
    check = function(ctx)
      if ctx.level >= 74 then return true end
      for _, id in ipairs({ 149855, 149856, 149857, 149858 }) do
        if (ctx.items[id] or 0) < 1 then return false end
      end
      return true
    end,
  },
  {
    level = 75,
    title = '75 — Medallion of Ether 149859',
    detail = 'Raid (level 80) in Elddar / Old Kurn. Strips 70 talents; opens Crumble God talents + Crystallos.',
    item_id = 149859,
    need = 1,
    check = function(ctx) return ctx.level >= 75 or ctx.items[149859] >= 1 end,
  },
}

local TRACK_ITEMS = {
  { id = 149854, name = '149854 Power / Medallion of Tactics' },
  { id = 149855, name = '149855 Icon of The Keeper (Depths)' },
  { id = 149856, name = '149856 Icon of The Keeper (Wind)' },
  { id = 149857, name = '149857 Icon of The Keeper (Fear)' },
  { id = 149858, name = '149858 Icon of The Keeper (Pain)' },
  { id = 149859, name = '149859 Medallion of Ether' },
  { id = 149918, name = '149918 Caverns Map' },
  { id = 149919, name = '149919 Bloodmoon Map' },
}

local function safe(fn, default)
  local ok, v = pcall(fn)
  if ok and v ~= nil and v ~= '' then return v end
  return default
end

local function num(fn, default)
  local v = safe(fn, default)
  local n = tonumber(v)
  return n or default
end

local function item_count(id)
  local n = num(function() return mq.TLO.FindItemCount(id)() end, -1)
  if n >= 0 then return n end
  n = num(function() return mq.TLO.FindItemCount('=' .. tostring(id))() end, -1)
  if n >= 0 then return n end
  return 0
end

local function load_catalog()
  package.loaded['godtier_talents'] = nil
  local ok, data = pcall(require, 'godtier_talents')
  if ok and type(data) == 'table' then
    catalog = data
    return true
  end
  return false
end

local function me_ctx()
  local items = {}
  for _, row in ipairs(TRACK_ITEMS) do
    items[row.id] = item_count(row.id)
  end
  local zone = tostring(safe(function() return mq.TLO.Zone.ShortName() end, '?'))
  return {
    name = tostring(safe(function() return mq.TLO.Me.Name() end, 'Unknown')),
    level = num(function() return mq.TLO.Me.Level() end, 0),
    class_id = num(function() return mq.TLO.Me.Class.ID() end, 0),
    class_name = tostring(safe(function() return mq.TLO.Me.Class() end, '?')),
    zone = zone,
    zone_label = GOD_ZONES[zone:lower()] or zone,
    gm = safe(function() return mq.TLO.Me.GM() end, false) == true
      or num(function() return mq.TLO.Me.GM() end, 0) == 1,
    items = items,
  }
end

local function class_talents(class_id)
  local t = catalog.talents and catalog.talents[class_id]
  if type(t) == 'table' then return t end
  return {}
end

local function filtered_talents(class_id)
  local q = search:lower()
  local out = {}
  for _, row in ipairs(class_talents(class_id)) do
    if q == '' or (row.name or ''):lower():find(q, 1, true) or (row.description or ''):lower():find(q, 1, true) then
      out[#out + 1] = row
    end
  end
  return out
end

local function esc(s)
  s = tostring(s or '')
  s = s:gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;'):gsub('"', '&quot;')
  return s
end

-----------------------------------------------------------------------
-- RmlUi windows
-----------------------------------------------------------------------
local UI = {
  prog = nil,
  tal = nil,
  next_prog = 0,
  next_tal = 0,
  item_slots = -1,
  step_slots = -1,
  tal_slots = -1,
}

local function open_win(name, path, w, h)
  -- Instant close on /lua stop via rmlui GC + close_all in cleanup.
  -- autoclose=true remains as a plugin backup only.
  local win, err = rmlui.open(name, path, { width = w, height = h, autoclose = true })
  if not win then
    print('[GodTier] RmlUi open failed (' .. name .. '): ' .. tostring(err))
    return nil
  end
  win:theme('violet')
  return win
end

local function ensure_windows()
  if not UI.prog then
    UI.prog = open_win('GodTierProgress', 'godtier/ui/progress.rml', 560, 720)
    UI.item_slots, UI.step_slots = -1, -1
  end
  if not UI.tal then
    UI.tal = open_win('GodTierTalents', 'godtier/ui/talents.rml', 720, 680)
    UI.tal_slots = -1
  end
end

local function update_progress()
  local win = UI.prog
  if not win then return end
  local ctx = me_ctx()

  win:text('char_line', string.format('%s  ·  %s', ctx.name, ctx.class_name))
  win:text('st_level', tostring(ctx.level))
  win:text('st_zone', ctx.zone_label)
  win:class('gm_banner', 'show', ctx.gm)
  win:class('gate_banner', 'show', true)

  local have = 0
  for _, row in ipairs(TRACK_ITEMS) do
    if (ctx.items[row.id] or 0) > 0 then have = have + 1 end
  end
  win:text('items_have', string.format('%d / %d', have, #TRACK_ITEMS))

  if UI.item_slots ~= #TRACK_ITEMS then
    local parts = {}
    for i, row in ipairs(TRACK_ITEMS) do
      parts[i] = string.format(
        '<div id="it%d" class="item"><span id="it%dq" class="item-qty"></span><span id="it%dn" class="item-name">%s</span></div>',
        i, i, i, esc(row.name))
    end
    win.cache = {}
    win:rml('items', table.concat(parts))
    UI.item_slots = #TRACK_ITEMS
  end
  for i, row in ipairs(TRACK_ITEMS) do
    local n = ctx.items[row.id] or 0
    win:text('it' .. i .. 'q', 'x' .. n)
    win:class('it' .. i, 'have', n > 0)
  end

  if UI.step_slots ~= #STEPS then
    local parts = {}
    for i, step in ipairs(STEPS) do
      parts[i] = string.format(
        '<div id="st%d" class="step"><div class="step-top"><span id="st%db" class="badge">OPEN</span><span class="step-title">%s</span></div><div class="step-detail">%s</div></div>',
        i, i, esc(step.title), esc(step.detail))
    end
    win.cache = {}
    win:rml('steps', table.concat(parts))
    UI.step_slots = #STEPS
  end

  local done = 0
  for i, step in ipairs(STEPS) do
    local ok = false
    pcall(function() ok = step.check(ctx) and true or false end)
    if ok then done = done + 1 end
    win:class('st' .. i, 'done', ok)
    win:text('st' .. i .. 'b', ok and 'DONE' or 'OPEN')
  end
  win:text('st_done', string.format('%d/%d', done, #STEPS))
end

local function detail_rml(row)
  if not row then
    return '<div class="empty-ico">&#xE8F1;</div><div class="empty-title">Select a talent</div><div class="empty-sub">Pick one from the list to see cost, ranks, and description.</div>'
  end
  return table.concat({
    '<div class="detail-name">', esc(row.name), '</div>',
    '<div class="detail-meta">',
    '<span class="meta accent">Cost ', tostring(row.cost or 0), '</span>',
    '<span class="meta">Ranks ', tostring(row.rankcount or 0), '</span>',
    '<span class="meta">Scroll ', tostring(row.scrollid), '</span>',
    '<span class="meta">Spell ', tostring(row.spellid), '</span>',
    '</div>',
    '<div class="detail-key">Key: ', esc(row.datakey), '</div>',
    '<div class="detail-desc">', esc(row.description), '</div>',
  })
end

local function update_talents()
  local win = UI.tal
  if not win then return end
  local ctx = me_ctx()
  local cid = ctx.class_id
  if cid < 1 or cid > 16 then cid = 1 end
  local rows = filtered_talents(cid)
  filtered_cache = rows
  if selectedTalent > #rows then selectedTalent = math.max(1, #rows) end
  if selectedTalent < 1 then selectedTalent = 1 end

  local cname = (catalog.classes and catalog.classes[cid]) or CLASS_NAME[cid] or ctx.class_name
  win:text('tal_title', string.format('God Talents — %s', cname))
  win:text('tal_sub', 'Crumble trains these after 75 · 200 T9 credits per talent point')
  win:text('tal_count', tostring(#class_talents(cid)))
  win:text('tal_shown', tostring(#rows))
  win:class('search_box', 'filled', search ~= '')

  local n = math.min(#rows, 120)
  if n ~= UI.tal_slots then
    local parts = {}
    for i = 1, n do
      parts[i] = string.format(
        '<div id="tr%d" class="tal-row" action="sel:%d"><span id="tr%dn" class="tal-name"></span><span id="tr%dc" class="chip"></span></div>',
        i, i, i, i)
    end
    win.cache = {}
    win:rml('tal_list', table.concat(parts))
    UI.tal_slots = n
  end

  for i = 1, n do
    local row = rows[i]
    win:text('tr' .. i .. 'n', row.name or '?')
    win:text('tr' .. i .. 'c', string.format('%d pt · %dr', row.cost or 0, row.rankcount or 0))
    win:class('tr' .. i, 'sel', i == selectedTalent)
  end

  local sel = rows[selectedTalent]
  win:class('tal_detail', 'empty-detail', sel == nil)
  win:rml('tal_detail', detail_rml(sel))
end

local function handle(ev, which)
  local a = ev.action or ''
  if ev.type == 'change' and ev.id == 'search' and which == 'tal' then
    search = ev.value or ''
    selectedTalent = 1
    UI.next_tal = 0
    UI.tal_slots = -1
    return
  end
  if ev.type ~= 'click' and ev.type ~= 'dblclick' then return end

  if a == 'window:close' then
    if which == 'prog' then showProgress = false
    else showTalents = false end
    print('[GodTier] Window hidden. /godtier or /godtalents to reopen, /godtier quit to stop.')
    return
  end

  if a == 'quit' then
    running = false
    return
  end
  if a == 'open:talents' then
    showTalents = true
    UI.next_tal = 0
    return
  end
  if a == 'open:progress' then
    showProgress = true
    UI.next_prog = 0
    return
  end
  if a == 'refresh' then
    load_catalog()
    UI.tal_slots = -1
    UI.next_tal = 0
    mq.cmd('/echo [GodTier] catalog reloaded')
    return
  end

  local idx = tonumber(a:match('^sel:(%d+)$'))
  if idx and which == 'tal' then
    selectedTalent = idx
    UI.next_tal = 0
  end
end

local function tick()
  ensure_windows()

  if UI.prog then
    for ev in UI.prog:events() do
      local ok, err = pcall(handle, ev, 'prog')
      if not ok then print('[GodTier] prog event: ' .. tostring(err)) end
    end
    UI.prog:show(showProgress)
  end
  if UI.tal then
    for ev in UI.tal:events() do
      local ok, err = pcall(handle, ev, 'tal')
      if not ok then print('[GodTier] tal event: ' .. tostring(err)) end
    end
    UI.tal:show(showTalents)
  end

  local t = mq.gettime and mq.gettime() or (os.time() * 1000)
  if showProgress and UI.prog and t >= UI.next_prog then
    UI.next_prog = t + 400
    local ok, err = pcall(update_progress)
    if not ok then
      print('[GodTier] progress update: ' .. tostring(err))
      UI.next_prog = t + 1500
    end
  end
  if showTalents and UI.tal and t >= UI.next_tal then
    UI.next_tal = t + 250
    local ok, err = pcall(update_talents)
    if not ok then
      print('[GodTier] talents update: ' .. tostring(err))
      UI.next_tal = t + 1500
    end
  end
end

local function cmd(...)
  local a = tostring(select(1, ...) or ''):lower()
  if a == 'quit' or a == 'exit' then
    running = false
    return
  end
  if a == 'both' or a == 'on' then
    showProgress = true
    showTalents = true
    UI.next_prog, UI.next_tal = 0, 0
    return
  end
  if a == 'hide' or a == 'off' then
    showProgress = false
    showTalents = false
    return
  end
  if a == 'talents' or a == 'talent' then
    showTalents = not showTalents
    UI.next_tal = 0
    return
  end
  if a == 'refresh' then
    load_catalog()
    UI.tal_slots = -1
    UI.next_tal = 0
    mq.cmd('/echo [GodTier] catalog reloaded')
    return
  end
  showProgress = not showProgress
  UI.next_prog = 0
end

-----------------------------------------------------------------------
load_catalog()
mq.bind('/godtier', cmd)
mq.bind('/godtalents', function()
  showTalents = not showTalents
  UI.next_tal = 0
end)
mq.cmd('/echo [GodTier] RmlUi windows loaded. /godtier  /godtalents  /godtier quit')

local function cleanup()
  pcall(function() rmlui.close_all() end)
  pcall(function() mq.unbind('/godtier') end)
  pcall(function() mq.unbind('/godtalents') end)
  mq.cmd('/echo [GodTier] stopped.')
end

local ok, err = pcall(function()
  while running do
    local tok, terr = pcall(tick)
    if not tok then
      print('[GodTier] tick error: ' .. tostring(terr))
      mq.delay(500)
    else
      mq.delay(50)
    end
  end
end)
if not ok and err then print('[GodTier] stop: ' .. tostring(err)) end
cleanup()
