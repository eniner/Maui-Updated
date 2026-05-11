--[[
  GearScoreX — gear compare UI for MacroQuest Lua (0–100 slot ratings vs your best worn piece; weights follow Me.Class() automatically).
  Deploy: MacroQuest/lua/GearScoreX.lua plus MacroQuest/lua/ui/theme.lua, ui_helpers.lua, main_window.lua
  Run:  /lua run GearScoreX    (also works: gearscorex)
  Stop: /gsxquit

  NOTE: MacroQuest injects into EverQuest; many antivirus apps flag MQ as suspicious.
  Add your MacroQuest install folder to AV exclusions (not this script specifically).
  Settings are kept in memory only (no loadfile / no disk pickle) to reduce junk detections.
]]

local mq = require('mq')
local ImGui = require('ImGui')
local ui_theme = require('ui.theme')
local ui_help = require('ui.ui_helpers')
local main_window = require('ui.main_window')

--- MQ ImGui: GetContentRegionAvail returns (width, height) as numbers — not ImVec2 with .x (see maui/init.lua).
local function RegionAvailW()
    local w, _h = ImGui.GetContentRegionAvail()
    if type(w) == 'number' then return w end
    if w ~= nil then
        local ok, x = pcall(function() return w.x end)
        if ok and type(x) == 'number' then return x end
    end
    return 400
end

--- Several ImGui getters return (x, y) as two numbers instead of a vec-like value with .x / .y.
local function vec2XY(a, b)
    if type(a) == 'number' and type(b) == 'number' then
        return a, b
    end
    if a ~= nil and type(a) ~= 'number' then
        local okx, x = pcall(function() return a.x end)
        local oky, y = pcall(function() return a.y end)
        if okx and oky and type(x) == 'number' and type(y) == 'number' then
            return x, y
        end
    end
    return 0, 0
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Config / presets / persistence
-- ═══════════════════════════════════════════════════════════════════════════

local function deepCopy(t)
    if type(t) ~= 'table' then return t end
    local r = {}
    for k, v in pairs(t) do r[k] = type(v) == 'table' and deepCopy(v) or v end
    return r
end

local function monkBase()
    return {
        HP = 1.0, Mana = 0.3, Endurance = 0.8,
        AC = 2.5, ATK = 3.0,
        STR = 2.0, STA = 1.5, AGI = 2.0, DEX = 3.5, WIS = 0.5, INT = 0.5, CHA = 0.0,
        HeroicSTR = 2.0, HeroicSTA = 2.0, HeroicAGI = 4.0, HeroicDEX = 5.0,
        HeroicWIS = 1.0, HeroicINT = 1.0, HeroicCHA = 0.0,
        HastePct = 50.0,
        DoTShield = 5.0, SpellShield = 5.0, Avoidance = 6.0, Shielding = 6.0,
        CombatEffects = 10.0, StrikeThrough = 8.0, Accuracy = 8.0,
        Weight = 0.0,
    }
end

--- Keys present in every weight table (used for Custom sliders).
local WEIGHT_KEYS_TEMPLATE = monkBase()

--- Class-specific stat priorities for weighted score & compare (EQ live-style roles).
local function weightsTankPlate()
    local w = monkBase()
    w.HP = 2.2; w.AC = 4.0; w.STA = 3.2; w.ATK = 2.2; w.Endurance = 1.0
    w.STR = 2.2; w.DEX = 1.8; w.AGI = 1.5; w.WIS = 0.15; w.INT = 0.05; w.Mana = 0.08
    w.Shielding = 10.0; w.Avoidance = 9.0; w.DoTShield = 7.0; w.SpellShield = 7.0
    w.HastePct = 38.0; w.StrikeThrough = 7.0; w.Accuracy = 7.0; w.CombatEffects = 9.0
    w.HeroicSTA = 4.0; w.HeroicSTR = 2.5; w.HeroicDEX = 2.0; w.HeroicAGI = 2.0
    return w
end

local function weightsWarrior() return weightsTankPlate() end

local function weightsPaladin()
    local w = weightsTankPlate()
    w.Mana = 1.4; w.WIS = 1.2; w.INT = 0.4; w.HeroicWIS = 3.0
    return w
end

local function weightsShadowKnight()
    local w = weightsTankPlate()
    w.Mana = 1.6; w.INT = 1.0; w.WIS = 0.6; w.HeroicINT = 2.5; w.HeroicWIS = 1.5
    return w
end

local function weightsPriestWis()
    local w = monkBase()
    w.Mana = 4.5; w.WIS = 4.5; w.HeroicWIS = 7.0
    w.INT = 0.2; w.HP = 1.8; w.AC = 2.8; w.STA = 2.5; w.HeroicSTA = 4.0
    w.ATK = 0.5; w.STR = 0.4; w.DEX = 0.6; w.AGI = 0.8
    w.HastePct = 42.0; w.SpellShield = 8.0; w.DoTShield = 7.0
    w.HeroicINT = 1.5; w.HeroicDEX = 2.0; w.HeroicAGI = 2.0
    return w
end

local function weightsCasterInt()
    local w = monkBase()
    w.Mana = 4.8; w.INT = 4.8; w.HeroicINT = 7.5
    w.WIS = 0.25; w.HP = 1.4; w.AC = 2.0; w.STA = 1.8; w.HeroicSTA = 3.0
    w.ATK = 0.6; w.STR = 0.35; w.DEX = 0.5; w.AGI = 0.7
    w.HastePct = 45.0; w.SpellShield = 8.0; w.CombatEffects = 11.0
    w.HeroicWIS = 1.5; w.HeroicDEX = 2.0; w.HeroicAGI = 2.0
    return w
end

local function weightsEnchanter()
    local w = weightsCasterInt()
    w.Mana = w.Mana * 1.05; w.INT = w.INT * 1.05; w.HeroicINT = w.HeroicINT * 1.05
    w.CHA = 1.5; w.HeroicCHA = 2.0
    return w
end

local function weightsRanger()
    local w = monkBase()
    w.DEX = 4.0; w.AGI = 3.0; w.ATK = 3.2; w.HeroicDEX = 5.5; w.HeroicAGI = 4.5
    w.Mana = 1.8; w.WIS = 2.2; w.HeroicWIS = 3.5
    w.HP = 1.3; w.AC = 2.6; w.Endurance = 1.2
    return w
end

local function weightsBeastlord()
    local w = monkBase()
    w.DEX = 3.6; w.WIS = 3.2; w.Mana = 2.8; w.HeroicDEX = 5.0; w.HeroicWIS = 4.5
    w.ATK = 2.8; w.AGI = 2.8; w.HP = 1.4; w.AC = 2.6; w.STR = 2.2
    return w
end

local function weightsBard()
    local w = monkBase()
    w.DEX = 3.2; w.AGI = 2.8; w.AC = 2.6; w.ATK = 2.6; w.Mana = 2.0; w.STA = 2.0; w.HeroicDEX = 4.5
    w.WIS = 0.6; w.INT = 0.5; w.CHA = 2.0; w.HeroicCHA = 2.5
    return w
end

--- mq.TLO.Me.Class() → builder (fallback: monkBase).
local CLASS_WEIGHT_BUILDER = {
    Warrior = weightsWarrior,
    Paladin = weightsPaladin,
    ['Shadow Knight'] = weightsShadowKnight,
    Cleric = weightsPriestWis,
    Druid = weightsPriestWis,
    Shaman = weightsPriestWis,
    Ranger = weightsRanger,
    Monk = function() return deepCopy(monkBase()) end,
    Rogue = function() return deepCopy(monkBase()) end,
    Berserker = function() return deepCopy(monkBase()) end,
    Bard = weightsBard,
    Beastlord = weightsBeastlord,
    Necromancer = weightsCasterInt,
    Wizard = weightsCasterInt,
    Magician = weightsCasterInt,
    Enchanter = weightsEnchanter,
}

local function weightsForClass(className)
    local key = tostring(className or '')
    local fn = CLASS_WEIGHT_BUILDER[key]
    if type(fn) == 'function' then return deepCopy(fn()) end
    return deepCopy(monkBase())
end

local config = {
    colors = {
        windowBg = { 0.051, 0.059, 0.078, 1.0 },
        headerBg = { 0.102, 0.118, 0.165, 1.0 },
        accent = { 0.239, 0.420, 0.624, 1.0 },
        upgrade = { 0.298, 0.686, 0.490, 1.0 },
        downgrade = { 0.812, 0.294, 0.294, 1.0 },
        amber = { 0.831, 0.635, 0.298, 1.0 },
        text = { 0.910, 0.922, 0.941, 1.0 },
        textMuted = { 0.478, 0.514, 0.580, 1.0 },
        border = { 0.165, 0.184, 0.239, 1.0 },
        ringOffense = { 0.898, 0.361, 0.361, 1.0 },
        ringDefense = { 0.361, 0.624, 0.898, 1.0 },
        ringUtility = { 0.482, 0.811, 0.624, 1.0 },
    },
}

config.weightsForClass = weightsForClass

function config.defaultSettings()
    return {
        version = 5,
        compareMode = false,
        comparePinned = false,
    }
end

--- Session-only settings: avoids loadfile() and mq.pickle() touching disk (fewer AV heuristics).
function config.load()
    return config.defaultSettings()
end

function config.save(_data)
    --- Intentionally no-op: persistence removed for AV/telemetry-sensitive setups.
end

--- Weights always follow mq.TLO.Me.Class() — no user profiles or sliders.
function config.effectiveWeightsAndScale(_settings)
    local cls = ''
    if mq and mq.TLO and mq.TLO.Me and mq.TLO.Me.Class then
        local ok, c = pcall(function() return mq.TLO.Me.Class() end)
        if ok and c then cls = c end
    end
    return deepCopy(weightsForClass(cls)), 1.0
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Drag-drop token cache (ImGui payloads only carry small types)
-- ═══════════════════════════════════════════════════════════════════════════

local drag = { nextId = 1, cache = {} }

function drag.put(tbl)
    drag.nextId = drag.nextId + 1
    local id = drag.nextId
    drag.cache[id] = tbl
    if drag.nextId > 10000 then drag.cache = {}; drag.nextId = 1; drag.cache[1] = tbl; return 1 end
    return id
end

function drag.take(id)
    local t = drag.cache[id]; drag.cache[id] = nil; return t
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Scoring
-- ═══════════════════════════════════════════════════════════════════════════

local CATEGORY = {
    offensive = {
        ATK = true, STR = true, DEX = true, AGI = true,
        HeroicSTR = true, HeroicDEX = true, HeroicAGI = true,
        HastePct = true, Accuracy = true, StrikeThrough = true, CombatEffects = true,
    },
    defensive = {
        HP = true, AC = true, STA = true, HeroicSTA = true,
        DoTShield = true, SpellShield = true, Avoidance = true, Shielding = true,
    },
    utility = {
        Mana = true, Endurance = true, WIS = true, INT = true, CHA = true,
        HeroicWIS = true, HeroicINT = true, HeroicCHA = true, Weight = true,
    },
}

local function statValue(stats, key)
    if not stats then return 0 end
    local v = stats[key]
    if v ~= nil then return tonumber(v) or 0 end
    if key == 'HastePct' then return tonumber(stats.HastePct or stats.Haste) or 0 end
    if key == 'DoTShield' then return tonumber(stats.DoTShield or stats.DoTShielding) or 0 end
    return 0
end

local function categorizeContribution(key, contribution)
    if contribution == 0 then return nil end
    if CATEGORY.offensive[key] then return 'offensive', contribution end
    if CATEGORY.defensive[key] then return 'defensive', contribution end
    if CATEGORY.utility[key] then return 'utility', contribution end
    return 'utility', contribution
end

local scoring = {}

function scoring.scoreItem(itemStats, preset, contentScale)
    preset = preset or {}
    contentScale = contentScale or 1.0
    local total = 0
    local breakdown = { offensive = 0, defensive = 0, utility = 0 }
    for key, weight in pairs(preset) do
        if type(weight) == 'number' and weight ~= 0 then
            local raw = statValue(itemStats, key)
            local contrib = raw * weight * contentScale
            total = total + contrib
            local cat, c = categorizeContribution(key, contrib)
            if cat then breakdown[cat] = breakdown[cat] + c end
        end
    end
    return total, breakdown
end

function scoring.maxSlotScore(rows)
    local m = 1
    for _, row in ipairs(rows or {}) do
        if row.score and row.score > m then m = row.score end
    end
    return m
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Items / inventory
-- ═══════════════════════════════════════════════════════════════════════════

local items = {}

--- Display order: armor → accessories → weapons (section dividers in main_window SECTION_ROW).
items.SLOT_ORDER = {
    -- Armor
    { key = 'head', label = 'Helm' },
    { key = 'chest', label = 'Chest' },
    { key = 'arms', label = 'Arms' },
    { key = 'leftwrist', label = 'Wrist L' },
    { key = 'rightwrist', label = 'Wrist R' },
    { key = 'hands', label = 'Gloves' },
    { key = 'legs', label = 'Legs' },
    { key = 'feet', label = 'Boots' },
    -- Accessories
    { key = 'neck', label = 'Neck' },
    { key = 'leftear', label = 'Ear L' },
    { key = 'rightear', label = 'Ear R' },
    { key = 'leftfinger', label = 'Finger L' },
    { key = 'rightfinger', label = 'Finger R' },
    { key = 'shoulder', label = 'Shoulders' },
    { key = 'back', label = 'Back' },
    { key = 'waist', label = 'Waist' },
    { key = 'charm', label = 'Charm' },
    { key = 'face', label = 'Face' },
    -- Weapons
    { key = 'mainhand', label = 'Primary' },
    { key = 'offhand', label = 'Secondary' },
    { key = 'range', label = 'Range' },
    { key = 'ammo', label = 'Ammo' },
}

--- MQ numeric worn slot IDs (EZInventory slot-id map; bags filter uses these indices).
items.WORN_SLOT_NUM = {
    charm = 0, leftear = 1, head = 2, face = 3, rightear = 4, neck = 5,
    shoulder = 6, arms = 7, back = 8, leftwrist = 9, rightwrist = 10, range = 11,
    hands = 12, mainhand = 13, offhand = 14, leftfinger = 15, rightfinger = 16,
    chest = 17, legs = 18, feet = 19, waist = 20, ammo = 22,
}

local function safe(call, default)
    local ok, r = pcall(call)
    if ok and r ~= nil then return r end
    return default
end

function items.extractStats(item)
    if not item or not item() then return nil end
    local s = {}
    s.Name = safe(function() return item.Name() end, '')
    s.ID = safe(function() return item.ID() end, 0)
    s.Icon = safe(function() return item.Icon() end, 0)
    s.HP = safe(function() return item.HP() end, 0)
    s.Mana = safe(function() return item.Mana() end, 0)
    s.Endurance = safe(function() return item.Endurance() end, 0)
    s.AC = safe(function() return item.AC() end, 0)
    s.ATK = safe(function() return item.Attack() end, 0)
    s.STR = safe(function() return item.STR() end, 0)
    s.STA = safe(function() return item.STA() end, 0)
    s.AGI = safe(function() return item.AGI() end, 0)
    s.DEX = safe(function() return item.DEX() end, 0)
    s.WIS = safe(function() return item.WIS() end, 0)
    s.INT = safe(function() return item.INT() end, 0)
    s.CHA = safe(function() return item.CHA() end, 0)
    s.HeroicSTR = safe(function() return item.HeroicSTR() end, 0)
    s.HeroicSTA = safe(function() return item.HeroicSTA() end, 0)
    s.HeroicAGI = safe(function() return item.HeroicAGI() end, 0)
    s.HeroicDEX = safe(function() return item.HeroicDEX() end, 0)
    s.HeroicWIS = safe(function() return item.HeroicWIS() end, 0)
    s.HeroicINT = safe(function() return item.HeroicINT() end, 0)
    s.HeroicCHA = safe(function() return item.HeroicCHA() end, 0)
    s.HastePct = safe(function() return item.HastePct() end, 0)
    if s.HastePct == 0 then s.Haste = safe(function() return item.Haste() end, 0); s.HastePct = s.Haste end
    s.DoTShield = safe(function() return item.DoTShielding() end, 0)
    s.SpellShield = safe(function() return item.SpellShield() end, 0)
    s.Avoidance = safe(function() return item.Avoidance() end, 0)
    s.Shielding = safe(function() return item.Shielding() end, 0)
    s.CombatEffects = safe(function() return item.CombatEffects() end, 0)
    s.StrikeThrough = safe(function() return item.StrikeThrough() end, 0)
    s.Accuracy = safe(function() return item.Accuracy() end, 0)
    s.Weight = safe(function() return item.Weight() end, 0)
    s.Focus = safe(function() return item.Focus() end, '')
    s.Clicky = safe(function() return item.Clicky() end, '')
    s.ItemType = safe(function() return item.Type() end, '')
    s.Lore = safe(function() return item.Lore() end, false)
    s.NoDrop = safe(function() return item.NoDrop() end, false)
    s.Augments = {}
    for i = 1, 5 do
        local aug = safe(function() return item.Augment(i) end, nil)
        local name = aug and aug() and safe(function() return aug.Name() end, '') or ''
        if name ~= '' then s.Augments[i] = name end
    end
    s.FocusEffects = {}
    if s.Focus and s.Focus ~= '' then table.insert(s.FocusEffects, s.Focus) end
    return s
end

function items.getEquippedItem(slotKey)
    local inv = mq.TLO.Me.Inventory(slotKey)
    if inv and inv() then return inv end
    return nil
end

function items.scanEquipped()
    local rows = {}
    for _, def in ipairs(items.SLOT_ORDER) do
        local item = items.getEquippedItem(def.key)
        local stats = item and items.extractStats(item) or nil
        rows[#rows + 1] = {
            slotKey = def.key, slotLabel = def.label, item = item, stats = stats,
            empty = not stats or (stats.Name == ''),
        }
    end
    return rows
end

function items.findItemTLOByName(name)
    if not name or name == '' then return nil end
    local fi = mq.TLO.FindItem('=' .. name)
    if fi and fi() then return fi end
    fi = mq.TLO.FindItem(name)
    if fi and fi() then return fi end
    return nil
end

local function itemClassesOkForMe(it)
    if not it or not it() then return false end
    local mc = mq.TLO.Me.Class() or ''
    local nc = it.Classes() or 0
    if nc <= 0 then return true end
    if nc >= 16 then return true end
    for i = 1, nc do
        local ok, cn = pcall(function() return it.Class(i)() end)
        if ok and cn == mc then return true end
    end
    return false
end

local function collectItemIntoBagSlots(it, bySlot)
    if not itemClassesOkForMe(it) then return end
    local typ = it.Type() or ''
    if tostring(typ):lower():find('augment') then return end
    local name = it.Name()
    if not name or name == '' then return end
    local nw = it.WornSlots() or 0
    for wi = 1, nw do
        local sn
        local ok, v = pcall(function()
            local ws = it.WornSlot(wi)
            if not ws then return nil end
            if type(ws) == 'number' then return ws end
            local t = ws()
            return tonumber(t)
        end)
        if ok and v ~= nil then sn = tonumber(v) end
        if sn and sn >= 0 and sn <= 22 then
            bySlot[sn][#bySlot[sn] + 1] = name
        end
    end
end

--- Scan pack contents (inv 23–34); group item names by MQ worn-slot ID for dropdown filters.
function items.rebuildBagSlotOptions(app)
    local bySlot = {}
    for i = 0, 22 do bySlot[i] = {} end
    for invSlot = 23, 34 do
        local pack = mq.TLO.Me.Inventory(invSlot)
        if pack and pack() and (pack.Container() or 0) > 0 then
            for ii = 1, pack.Container() do
                collectItemIntoBagSlots(pack.Item(ii), bySlot)
            end
        end
    end
    for sn = 0, 22 do
        local seen = {}
        local uniq = {}
        for _, nm in ipairs(bySlot[sn]) do
            if not seen[nm] then seen[nm] = true; uniq[#uniq + 1] = nm end
        end
        table.sort(uniq)
        bySlot[sn] = uniq
    end
    app.bagSlotOptions = bySlot
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Compare helpers
-- ═══════════════════════════════════════════════════════════════════════════

local compare = {}

compare.COMPARE_KEYS = {
    { label = 'HP', key = 'HP' }, { label = 'Mana', key = 'Mana' }, { label = 'Endurance', key = 'Endurance' },
    { label = 'AC', key = 'AC' }, { label = 'ATK', key = 'ATK' },
    { label = 'STR', key = 'STR' }, { label = 'STA', key = 'STA' }, { label = 'AGI', key = 'AGI' }, { label = 'DEX', key = 'DEX' },
    { label = 'WIS', key = 'WIS' }, { label = 'INT', key = 'INT' }, { label = 'CHA', key = 'CHA' },
    { label = 'Heroic STR', key = 'HeroicSTR' }, { label = 'Heroic STA', key = 'HeroicSTA' },
    { label = 'Heroic AGI', key = 'HeroicAGI' }, { label = 'Heroic DEX', key = 'HeroicDEX' },
    { label = 'Heroic WIS', key = 'HeroicWIS' }, { label = 'Heroic INT', key = 'HeroicINT' }, { label = 'Heroic CHA', key = 'HeroicCHA' },
    { label = 'Haste %', key = 'HastePct' }, { label = 'DoT Shield', key = 'DoTShield' },
    { label = 'Spell Shield', key = 'SpellShield' }, { label = 'Avoidance', key = 'Avoidance' },
    { label = 'Shielding', key = 'Shielding' }, { label = 'Combat Effects', key = 'CombatEffects' },
    { label = 'Strike Through', key = 'StrikeThrough' }, { label = 'Accuracy', key = 'Accuracy' }, { label = 'Weight', key = 'Weight' },
}

local function cmpVal(stats, key)
    if not stats then return 0 end
    local v = stats[key]
    if v == nil and key == 'HastePct' then v = stats.Haste end
    if v == nil and key == 'DoTShield' then v = stats.DoTShielding end
    return tonumber(v) or 0
end

function compare.iterComparedRows(statsA, statsB)
    local out = {}
    for _, row in ipairs(compare.COMPARE_KEYS) do
        local a = cmpVal(statsA, row.key)
        local b = cmpVal(statsB, row.key)
        if a ~= 0 or b ~= 0 then
            out[#out + 1] = { label = row.label, key = row.key, a = a, b = b, d = b - a }
        end
    end
    return out
end

function compare.classify(scoreA, scoreB, statsA, statsB, weightPreset)
    local d = (scoreB or 0) - (scoreA or 0)
    local thresh = math.max(math.abs(scoreA or 0), math.abs(scoreB or 0)) * 0.02
    if thresh < 50 then thresh = 50 end
    if d > thresh then return 'upgrade', d end
    if d < -thresh then return 'downgrade', d end
    weightPreset = weightPreset or WEIGHT_KEYS_TEMPLATE
    local winsA, winsB = 0, 0
    for _, row in ipairs(compare.iterComparedRows(statsA, statsB)) do
        local wt = weightPreset[row.key]
        if type(wt) == 'number' and wt > 0.0001 then
            if row.a > row.b then winsA = winsA + 1 elseif row.b > row.a then winsB = winsB + 1 end
        end
    end
    return 'sidegrade', d
end

--- Only counts rows whose weight > 0 for your class (so INT doesn't vote for a Warrior).
function compare.countStatWins(statsA, statsB, weightPreset)
    weightPreset = weightPreset or WEIGHT_KEYS_TEMPLATE
    local winsA, winsB = 0, 0
    for _, row in ipairs(compare.iterComparedRows(statsA, statsB)) do
        local wt = weightPreset[row.key]
        if type(wt) == 'number' and wt > 0.0001 then
            if row.a > row.b then winsA = winsA + 1 elseif row.b > row.a then winsB = winsB + 1 end
        end
    end
    return winsA, winsB
end

--- Human-readable % vs worn: (B−A) / max(|A|,|B|,1) × 100, clamped to ±100.
function compare.relativePercent(scoreA, scoreB)
    local a = tonumber(scoreA) or 0
    local b = tonumber(scoreB) or 0
    local delta = b - a
    local base = math.max(math.abs(a), math.abs(b), 1)
    local pct = (delta / base) * 100
    if pct > 100 then pct = 100 elseif pct < -100 then pct = -100 end
    return delta, pct
end

--- One-line summary for the compare banner (percent-first).
function compare.bannerPercentSummary(scoreA, scoreB)
    local _d, pct = compare.relativePercent(scoreA, scoreB)
    local ap = math.abs(pct)
    if ap < 0.05 then
        return string.format('Nearly tied (<0.1%% apart)'), pct
    end
    local sign = pct >= 0 and '+' or ''
    return string.format('Candidate %s%.1f%% vs worn (same 0-100 scale)', sign, pct), pct
end

--- Compact signed number for tiny footer (e.g. -9.2k).
local function fmtSignedCompact(n)
    local x = tonumber(n) or 0
    local ax = math.abs(x)
    local sign = x >= 0 and '+' or '-'
    if ax >= 1e6 then return string.format('%s%.2fm', sign, ax / 1e6) end
    if ax >= 1e3 then return string.format('%s%.1fk', sign, ax / 1e3) end
    return string.format('%s%.0f', sign, ax)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Icons
-- ═══════════════════════════════════════════════════════════════════════════

local icons = {}
local animItems = nil

local function getItemAnim()
    if animItems then return animItems end
    local ok, a = pcall(function() return mq.FindTextureAnimation('A_DragItem') end)
    if ok and a then animItems = a end
    return animItems
end

function icons.DrawItemIcon(iconID, size)
    size = size or 24
    local anim = getItemAnim()
    local id = tonumber(iconID) or 500
    local cell = math.max(0, id - 500)
    if anim then anim:SetTextureCell(cell); ImGui.DrawTextureAnimation(anim, size, size); return end
    local dl = ImGui.GetWindowDrawList()
    local px, py = vec2XY(ImGui.GetCursorScreenPosVec())
    dl:AddRectFilled(ImVec2(px, py), ImVec2(px + size, py + size), ImGui.GetColorU32(0.15, 0.17, 0.22, 1))
end

function icons.DrawItemIconAt(screenX, screenY, iconID, size)
    ImGui.SetCursorScreenPos(screenX, screenY)
    icons.DrawItemIcon(iconID, size)
end

local SLOT_STYLE = {
    head = { 0.55, 0.45, 0.75 }, chest = { 0.35, 0.55, 0.82 }, legs = { 0.35, 0.62, 0.55 },
    feet = { 0.72, 0.52, 0.38 }, hands = { 0.82, 0.42, 0.42 }, arms = { 0.48, 0.62, 0.82 },
    leftwrist = { 0.5, 0.58, 0.75 }, rightwrist = { 0.5, 0.58, 0.75 },
    leftfinger = { 0.65, 0.55, 0.8 }, rightfinger = { 0.65, 0.55, 0.8 },
    shoulder = { 0.45, 0.55, 0.65 }, waist = { 0.55, 0.5, 0.45 }, charm = { 0.75, 0.55, 0.85 },
    face = { 0.6, 0.5, 0.7 },
    mainhand = { 0.92, 0.72, 0.35 }, offhand = { 0.72, 0.72, 0.35 },
    neck = { 0.55, 0.82, 0.82 }, back = { 0.42, 0.55, 0.72 }, range = { 0.72, 0.55, 0.42 }, ammo = { 0.55, 0.55, 0.55 },
}

function icons.DrawSlotBadge(slotKey, side)
    side = side or 16
    local rgb = SLOT_STYLE[slotKey] or { 0.45, 0.48, 0.55 }
    local dl = ImGui.GetWindowDrawList()
    local cx, cy = vec2XY(ImGui.GetCursorScreenPosVec())
    dl:AddRectFilled(ImVec2(cx + 2, cy + 2), ImVec2(cx + side - 2, cy + side - 2), ImGui.GetColorU32(rgb[1], rgb[2], rgb[3], 1), 3)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Tooltip
-- ═══════════════════════════════════════════════════════════════════════════

--- 0-100: slot vs strongest worn piece this refresh (defined before any caller — MQ Lua may not forward-ref locals).
local function slotRating100(score, maxScore)
    local ms = tonumber(maxScore) or 1
    if ms <= 0 then ms = 1 end
    local s = tonumber(score) or 0
    local r = 100 * s / ms
    if r > 100 then r = 100 elseif r < 0 then r = 0 end
    return r
end

local function itemTooltip(stats, slotLabel, score, maxScore)
    if not stats or stats.Name == '' then return end
    ui_theme.push_tooltip_obsidian()
    ImGui.BeginTooltip()
    ImGui.PushTextWrapPos(ImGui.GetFontSize() * 30)
    local tm_r, tm_g, tm_b, tm_a = ui_theme.rgba(ui_theme.TEXT_SECONDARY)
    local ta_r, ta_g, ta_b, ta_a = ui_theme.rgba(ui_theme.TEXT_ACCENT)
    local tp_r, tp_g, tp_b, tp_a = ui_theme.rgba(ui_theme.TEXT_PRIMARY)
    ImGui.BeginGroup()
    icons.DrawItemIcon(stats.Icon, 32)
    ImGui.SameLine()
    ImGui.BeginGroup()
    ImGui.TextColored(ta_r, ta_g, ta_b, ta_a, '%s', stats.Name)
    ImGui.TextColored(tm_r, tm_g, tm_b, tm_a, '%s  |  %s', slotLabel or '', stats.ItemType or '')
    if stats.Weight and stats.Weight ~= 0 then ImGui.TextColored(tm_r, tm_g, tm_b, tm_a, 'Weight: %.1f', stats.Weight) end
    ImGui.EndGroup(); ImGui.EndGroup()
    if stats.Lore then ImGui.TextColored(0.72, 0.58, 0.92, 1, 'Lore') end
    if stats.NoDrop then ImGui.TextColored(0.92, 0.42, 0.42, 1, 'No Trade') end
    ImGui.Separator()
    ImGui.PushStyleColor(ImGuiCol.Text, tm_r, tm_g, tm_b, tm_a)
    ImGui.Text('Stats')
    ImGui.PopStyleColor()
    local keys = {
        'HP','Mana','Endurance','AC','ATK','STR','STA','AGI','DEX','WIS','INT','CHA',
        'HeroicSTR','HeroicSTA','HeroicAGI','HeroicDEX','HeroicWIS','HeroicINT','HeroicCHA',
        'HastePct','DoTShield','SpellShield','Avoidance','Shielding','CombatEffects','StrikeThrough','Accuracy',
    }
    if ImGui.BeginTable('gstt', 2, ImGuiTableFlags.SizingStretchProp) then
        for _, k in ipairs(keys) do
            local v = stats[k]
            if k == 'HastePct' and (not v or v == 0) then v = stats.Haste end
            if v and v ~= 0 then
                ImGui.TableNextRow(); ImGui.TableNextColumn(); ImGui.TextColored(tm_r, tm_g, tm_b, tm_a, '%s', k)
                ImGui.TableNextColumn(); ImGui.TextColored(tp_r, tp_g, tp_b, tp_a, '%s', tostring(v))
            end
        end
        ImGui.EndTable()
    end
    if stats.Focus and stats.Focus ~= '' then
        ImGui.Separator()
        ImGui.TextColored(0.48, 0.72, 0.92, 1, 'Focus')
        ImGui.TextWrapped('%s', stats.Focus)
        local spell = mq.TLO.Spell(stats.Focus)
        if spell and spell() then
            local ok, desc = pcall(function() return spell.Description() or '' end)
            if ok and desc and desc ~= '' then
                ImGui.PushTextWrapPos(ImGui.GetFontSize() * 28)
                ImGui.TextColored(0.65, 0.68, 0.74, 1, '%s', desc)
                ImGui.PopTextWrapPos()
            end
        end
    end
    local anyAug = false
    for i = 1, 5 do if stats.Augments and stats.Augments[i] then anyAug = true break end end
    if anyAug then
        ImGui.Separator(); ImGui.Text('Augments')
        for i = 1, 5 do
            local n = stats.Augments and stats.Augments[i]
            if n then ImGui.BulletText('%d: %s', i, n) end
        end
    end
    if score and maxScore then
        ImGui.Separator()
        ImGui.TextColored(ta_r, ta_g, ta_b, ta_a, 'Rating vs best worn slot: %.0f / 100', slotRating100(score, maxScore))
        ImGui.TextColored(ta_r, ta_g, ta_b, ta_a, 'Score: %.0f pts', tonumber(score) or 0)
    end
    ImGui.PopTextWrapPos()
    ImGui.EndTooltip()
    ui_theme.pop_tooltip_obsidian()
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Main window
-- ═══════════════════════════════════════════════════════════════════════════

local function overallAvgRating(rows, maxScore)
    local ms = tonumber(maxScore) or 1
    if ms <= 0 then ms = 1 end
    local sum, n = 0, 0
    for _, row in ipairs(rows or {}) do
        if row.score and row.score > 0 and not row.empty then
            sum = sum + slotRating100(row.score, ms)
            n = n + 1
        end
    end
    return n > 0 and (sum / n) or 0
end

local function currentClassTag()
    local c = ''
    if mq and mq.TLO and mq.TLO.Me and mq.TLO.Me.Class then
        local ok, x = pcall(function() return mq.TLO.Me.Class() end)
        if ok and x then c = tostring(x) end
    end
    return c
end

local function rebuildCache(app)
    local weights, scale = config.effectiveWeightsAndScale(app.settings)
    local raw = items.scanEquipped()
    local rows = {}
    local bd = { offensive = 0, defensive = 0, utility = 0 }
    local total = 0
    for _, r in ipairs(raw) do
        local score, br = 0, { offensive = 0, defensive = 0, utility = 0 }
        if r.stats and not r.empty then
            score, br = scoring.scoreItem(r.stats, weights, scale)
            total = total + score
            for k, v in pairs(br) do bd[k] = bd[k] + v end
        end
        rows[#rows + 1] = {
            slotKey = r.slotKey, slotLabel = r.slotLabel, stats = r.stats, empty = r.empty,
            score = score, breakdown = br,
        }
    end
    app.cachedRows = rows
    app.totalScore = total
    app.breakdownTotal = bd
    app.maxScore = scoring.maxSlotScore(rows)
    app.overallRating = overallAvgRating(rows, app.maxScore)
    items.rebuildBagSlotOptions(app)
    app._cacheClass = currentClassTag()
end

local function ensureCache(app)
    local tag = currentClassTag()
    if app.cachedRows and app._cacheClass == tag then return end
    rebuildCache(app)
end

local function refresh(app)
    app.refreshBusy = true
    app.refreshAnimStart = mq.gettime()
    rebuildCache(app)
    local t0 = os.clock()
    app.barAnim = {}
    for i, row in ipairs(app.cachedRows or {}) do
        local tgt = slotRating100(row.score or 0, app.maxScore or 1)
        app.barAnim[row.slotKey] = { v = 0, target = tgt, start = t0 + (i - 1) * 0.04 }
    end
end

local function copySummary(app)
    local line = string.format('GearScoreX avg_rating=%.0f/100 class=%s %s', app.overallRating or 0,
        mq.TLO.Me.Class() or '', mq.TLO.Me.CleanName() or '')
    mq.cmdf('/clipboard set "%s"', line:gsub('"', "'"))
end

--- Payload from EQ inspect / some drag sources (see MQ ImGui drag-drop).
local function parseInspectPayload(data)
    if type(data) ~= 'string' then return nil end
    local idStr, itemName = data:match('^EQ_ITEM_INSPECT|([^|]+)|(.+)$')
    if not idStr or not itemName then return nil end
    return { id = tonumber(idStr) or 0, name = itemName }
end

--- Bring the Compare window to front when A+B can be shown side-by-side.
local function openComparePanel(app)
    if not app then return end
    app.compareOpen = true
end

--- Fill compare slot A from the cached worn row for this equipment slot (bags dropdown / slot-aware compare).
local function syncSlotAFromWorn(app, slotKey)
    if not slotKey or slotKey == 'cursor' or slotKey == 'inspect' then return end
    for _, row in ipairs(app.cachedRows or {}) do
        if row.slotKey == slotKey and row.stats and not row.empty then
            app.slotA = {
                slotKey = row.slotKey,
                name = row.stats.Name,
                id = row.stats.ID or 0,
                stats = row.stats,
                score = row.score or 0,
                icon = row.stats.Icon,
            }
            return
        end
    end
end

--- Set compare slot B from extracted item stats. opts.slotKey from internal row drag overrides auto slot.
local function assignCompareB(app, stats, opts)
    opts = opts or {}
    if not stats or (stats.Name or '') == '' then return false end
    ensureCache(app)
    local sk = opts.slotKey
    if sk == nil or sk == '' then
        sk = 'cursor'
        if app.slotA and app.slotA.slotKey then sk = app.slotA.slotKey end
    end
    if sk and sk ~= 'cursor' and sk ~= 'inspect' then
        syncSlotAFromWorn(app, sk)
    end
    local w, scale = config.effectiveWeightsAndScale(app.settings)
    local sc = select(1, scoring.scoreItem(stats, w, scale))
    app.slotB = { slotKey = sk, name = stats.Name, id = stats.ID, stats = stats, score = sc, icon = stats.Icon }
    local r = slotRating100(sc, app.maxScore or sc)
    print(string.format('\ag[GearScoreX]\ax Compare (B) = \ay%s\ax — rating \ag%.0f\ax/100 vs worn %s.',
        stats.Name, r, (sk and sk ~= 'cursor') and ('(' .. tostring(sk) .. ')') or 'slot'))
    openComparePanel(app)
    return true
end

local function assignCompareBFromItemName(app, itemName)
    if not itemName or itemName == '' then return false end
    local st = items.findItemTLOByName(itemName)
    if not st then
        print(string.format('\ar[GearScoreX]\ax Could not resolve item \ay%s\ax (bags / inventory).', itemName))
        return false
    end
    local stats = items.extractStats(st)
    if not stats then return false end
    return assignCompareB(app, stats)
end

--- EQ_ITEM payload may be inspect-format or plain item name (depends on MQ build).
local function assignCompareBFromDragPayloadString(app, data)
    if type(data) ~= 'string' then return false end
    local parsed = parseInspectPayload(data)
    if parsed and parsed.name then return assignCompareBFromItemName(app, parsed.name) end
    local trimmed = data:match('^%s*(.-)%s*$')
    if trimmed and trimmed ~= '' and not trimmed:find('|', 1, true) then
        return assignCompareBFromItemName(app, trimmed)
    end
    return false
end

local function deltaBadge(app, row)
    local b = app.slotB
    if not b or not b.stats or not row.stats then return '' end
    --- Same equipment slot as worn row + candidate (cursor copies slot from A when set).
    if b.slotKey ~= row.slotKey then return '' end
    local d = (b.score or 0) - (row.score or 0)
    local _, rp = compare.relativePercent(row.score or 0, b.score or 0)
    if math.abs(rp) < 0.05 and math.abs(d) < 1 then return '~' end
    if d > 0.5 then return string.format('+%.1f%% ▲', rp) end
    if d < -0.5 then return string.format('%.1f%% ▼', rp) end
    return '~'
end

main_window.init({
    mq = mq,
    ImGui = ImGui,
    RegionAvailW = RegionAvailW,
    slotRating100 = slotRating100,
    ensureCache = ensureCache,
    refresh = refresh,
    copySummary = copySummary,
    assignCompareB = assignCompareB,
    openComparePanel = openComparePanel,
    deltaBadge = deltaBadge,
    itemTooltip = itemTooltip,
    items = items,
    icons = icons,
    drag = drag,
    config = config,
    scoring = scoring,
    compare = compare,
})

local function drawMain(app)
    main_window.draw(app)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Compare window
-- ═══════════════════════════════════════════════════════════════════════════

local function scoreSlot(stats, app)
    if not stats then return 0 end
    local w, scale = config.effectiveWeightsAndScale(app.settings)
    return select(1, scoring.scoreItem(stats, w, scale))
end

local function loadSlotFromName(itemName, app)
    local st = items.findItemTLOByName(itemName)
    if not st then return nil end
    local stats = items.extractStats(st)
    if not stats then return nil end
    return {
        slotKey = 'inspect', name = stats.Name, id = stats.ID, stats = stats,
        score = scoreSlot(stats, app), icon = stats.Icon,
    }
end

local function spellTooltipIfAny(name)
    if not name or name == '' then return end
    local sp = mq.TLO.Spell(name)
    if sp and sp() and ImGui.IsItemHovered() then
        ui_theme.push_tooltip_obsidian()
        ImGui.BeginTooltip()
        local ok, d = pcall(function() return sp.Description() end)
        if ok and d then ImGui.TextWrapped('%s', d) end
        ImGui.EndTooltip()
        ui_theme.pop_tooltip_obsidian()
    end
end

local function focusBlock(title, stats, other)
    local tr, tg, tb, ta = ui_theme.rgba(ui_theme.TEXT_ACCENT)
    ImGui.PushStyleColor(ImGuiCol.Text, tr, tg, tb, ta)
    ImGui.Text('%s', title)
    ImGui.PopStyleColor()
    local f = stats and stats.Focus or ''
    local o = other and other.Focus or ''
    local c = stats and stats.Clicky or ''
    if f == '' and c == '' then
        local mr, mg, mb, ma = ui_theme.rgba(ui_theme.TEXT_SECONDARY)
        ImGui.PushStyleColor(ImGuiCol.Text, mr, mg, mb, ma * 0.85)
        ImGui.Text('(none)')
        ImGui.PopStyleColor()
        return
    end
    if f ~= '' then
        local uniq = (f ~= o)
        if uniq then
            local ur, ug, ub, ua = ui_theme.rgba(ui_theme.DELTA_UPGRADE)
            ImGui.PushStyleColor(ImGuiCol.Text, ur, ug, ub, ua)
        end
        ImGui.BulletText('Focus: %s', f)
        if uniq then ImGui.PopStyleColor() end
        spellTooltipIfAny(f)
    end
    if c ~= '' then ImGui.BulletText('Clicky: %s', c); spellTooltipIfAny(c) end
end

local function deltaBarFrac(a, b)
    local maxv = math.max(math.abs(a), math.abs(b), 1)
    local diff = (b - a) / maxv
    if diff > 1 then diff = 1 elseif diff < -1 then diff = -1 end
    return diff
end

local function drawCompare(app)
    local T = ui_theme
    local bothReady = app.slotA and app.slotB and app.slotA.stats and app.slotB.stats
    if not app.settings.compareMode and not app.settings.comparePinned and not bothReady then return end

    ImGui.SetNextWindowSize(ImVec2(620, 480), ImGuiCond.FirstUseEver)
    if app.compareOpen == nil then app.compareOpen = true end
    local cmpOpen, drawWin = ImGui.Begin('GearScoreX Compare', app.compareOpen, ImGuiWindowFlags.NoCollapse)
    app.compareOpen = cmpOpen
    if not drawWin then ImGui.End(); return end

    local sa, sb = app.slotA, app.slotB
    if sa and sb and sa.stats and sb.stats then
        local effW = select(1, config.effectiveWeightsAndScale(app.settings))
        local cls, deltaPts = compare.classify(sa.score, sb.score, sa.stats, sb.stats, effW)
        local winsA, winsB = compare.countStatWins(sa.stats, sb.stats, effW)
        local sym = '◈ SIDEGRADE'
        if cls == 'upgrade' then sym = '✦ UPGRADE' elseif cls == 'downgrade' then sym = '✖ DOWNGRADE' end
        local bannerHex = T.DELTA_NEUTRAL
        if cls == 'upgrade' then bannerHex = T.DELTA_UPGRADE elseif cls == 'downgrade' then bannerHex = T.DELTA_DOWNGRADE end
        local br, bg, bb, _ba = T.rgba(bannerHex)
        local pctLine = select(1, compare.bannerPercentSummary(sa.score, sb.score))
        ImGui.PushStyleColor(ImGuiCol.ChildBg, br, bg, bb, 0.42)
        if ImGui.BeginChild('cmp_banner', 0, 58, false) then
            ImGui.SetWindowFontScale(1.1)
            local hr, hg, hb, ha = T.rgba(T.TEXT_HIGHLIGHT)
            ImGui.PushStyleColor(ImGuiCol.Text, hr, hg, hb, ha)
            ImGui.Text('%s  %s', sym, pctLine)
            ImGui.PopStyleColor()
            if ImGui.IsItemHovered() then
                T.push_tooltip_obsidian()
                ImGui.BeginTooltip()
                ImGui.TextWrapped('%s',
                    'Percent compares internal rating points: (B - A) / max(|A|,|B|). Same scale as the 0-100 column.')
                ImGui.Separator()
                ImGui.Text('Worn rating (A): %.0f / 100', slotRating100(sa.score or 0, app.maxScore or 1))
                ImGui.Text('Candidate rating (B): %.0f / 100', slotRating100(sb.score or 0, app.maxScore or 1))
                local sr, sg, sb_, sa_ = T.rgba(T.TEXT_SECONDARY)
                ImGui.PushStyleColor(ImGuiCol.Text, sr, sg, sb_, sa_)
                ImGui.Text('Weighted score pts  A=%.0f  B=%.0f  (%s)', sa.score or 0, sb.score or 0, mq.TLO.Me.Class() or '')
                ImGui.PopStyleColor()
                ImGui.Text('Point gap (B-A): %s', fmtSignedCompact(deltaPts))
                local _, rp = compare.relativePercent(sa.score, sb.score)
                ImGui.Text('Ratio: %+.2f%%', rp)
                ImGui.EndTooltip()
                T.pop_tooltip_obsidian()
            end
            ImGui.SetWindowFontScale(1.0)
            local wr, wg, wb, wa = T.rgba(T.TEXT_SECONDARY)
            ImGui.PushStyleColor(ImGuiCol.Text, wr, wg, wb, wa)
            ImGui.Text('Stat wins: A=%d  B=%d   ·   pts %s', winsA, winsB, fmtSignedCompact(deltaPts))
            ImGui.PopStyleColor()
        end
        ImGui.EndChild(); ImGui.PopStyleColor()
    else
        local mr, mg, mb, ma = T.rgba(T.TEXT_SECONDARY)
        ImGui.PushStyleColor(ImGuiCol.Text, mr, mg, mb, ma)
        ImGui.TextWrapped('A = left-click worn row · B = bags dropdown, right-click worn row, or drag item here')
        ImGui.PopStyleColor()
    end

    do
        local fr, fg, fb, fa = T.rgba(T.BACKGROUND_PANEL)
        local fh, fgh, fgb, fga = T.rgba(T.BACKGROUND_HOVER)
        ImGui.PushStyleColor(ImGuiCol.Button, fr, fg, fb, fa)
        ImGui.PushStyleColor(ImGuiCol.ButtonHovered, fh, fgh, fgb, fga)
        local ar, ag, ab, aa = T.rgba(T.TEXT_ACCENT)
        ImGui.PushStyleColor(ImGuiCol.Text, ar, ag, ab, aa)
        if ImGui.Button('Reset##cmp') then app.slotA, app.slotB = nil, nil end
        ImGui.PopStyleColor(3)
    end
    ImGui.SameLine()
    do
        local fr, fg, fb, fa = T.rgba(T.BACKGROUND_PANEL)
        local fh, fgh, fgb, fga = T.rgba(T.BACKGROUND_HOVER)
        ImGui.PushStyleColor(ImGuiCol.Button, fr, fg, fb, fa)
        ImGui.PushStyleColor(ImGuiCol.ButtonHovered, fh, fgh, fgb, fga)
        local ar, ag, ab, aa = T.rgba(T.TEXT_ACCENT)
        ImGui.PushStyleColor(ImGuiCol.Text, ar, ag, ab, aa)
        if ImGui.Button(app.settings.comparePinned and 'Pinned##cmp' or 'Pin panel##cmp') then
            app.settings.comparePinned = not app.settings.comparePinned
            config.save(app.settings)
        end
        ImGui.PopStyleColor(3)
    end

    local half = (RegionAvailW() - 18) * 0.5

    local function headerSlot(which, slotTbl)
        ImGui.BeginChild(which .. '_hdr', half, 104, false)
        local ww = RegionAvailW()
        local dl = ImGui.GetWindowDrawList()
        local ax, ay = vec2XY(ImGui.GetCursorScreenPosVec())
        local hh = 102
        dl:AddRectFilled(ImVec2(ax, ay), ImVec2(ax + ww, ay + hh), T.u32(T.BACKGROUND_PANEL), 4)
        dl:AddRect(ImVec2(ax, ay), ImVec2(ax + ww, ay + hh), T.u32(T.BORDER_ACCENT), 4, 0, 1)
        ImGui.SetCursorScreenPos(ax + 10, ay + 10)
        if slotTbl and slotTbl.stats then
            icons.DrawItemIcon(slotTbl.icon or slotTbl.stats.Icon, 32)
            ImGui.SameLine()
            ImGui.BeginGroup()
            local pr, pg, pb, pa = T.rgba(T.TEXT_PRIMARY)
            ImGui.PushStyleColor(ImGuiCol.Text, pr, pg, pb, pa)
            ImGui.TextWrapped('%s', slotTbl.name or '')
            ImGui.PopStyleColor()
            local sr, sg, sb_, sa_ = T.rgba(T.TEXT_SECONDARY)
            ImGui.PushStyleColor(ImGuiCol.Text, sr, sg, sb_, sa_)
            ImGui.Text('%s', slotTbl.slotKey or '')
            ImGui.PopStyleColor()
            local ar, ag, ab, aa = T.rgba(T.TEXT_ACCENT)
            ImGui.PushStyleColor(ImGuiCol.Text, ar, ag, ab, aa)
            ImGui.Text('Rating %.0f / 100', slotRating100(slotTbl.score or 0, app.maxScore or 1))
            ImGui.Text('Pts %.0f', slotTbl.score or 0)
            ImGui.PopStyleColor()
            ImGui.EndGroup()
        else
            local nr, ng, nb, na = T.rgba(T.TEXT_SECONDARY)
            ImGui.SetCursorScreenPos(ax + 12, ay + 38)
            ImGui.PushStyleColor(ImGuiCol.Text, nr, ng, nb, na)
            ImGui.Text('Drop item here')
            ImGui.PopStyleColor()
        end

        if ImGui.BeginDragDropTarget() then
            local pl = ImGui.AcceptDragDropPayload('GEARSCORE_ITEM')
            if pl ~= nil then
                local data = drag.take(pl.Data)
                if data and data.stats then
                    local entry = {
                        slotKey = data.slotKey, name = data.itemName, id = data.itemID,
                        stats = data.stats, score = data.score, icon = data.stats.Icon,
                    }
                    if which == 'A' then app.slotA = entry else app.slotB = entry end
                    openComparePanel(app)
                end
            end
            local pl2 = ImGui.AcceptDragDropPayload('EQ_ITEM_INSPECT')
            if pl2 ~= nil and type(pl2.Data) == 'string' then
                local parsed = parseInspectPayload(pl2.Data)
                if parsed and parsed.name then
                    local slot = loadSlotFromName(parsed.name, app)
                    if slot then
                        if which == 'A' then app.slotA = slot else app.slotB = slot end
                        openComparePanel(app)
                    end
                end
            end
            ImGui.EndDragDropTarget()
        end
        ImGui.EndChild()
    end

    headerSlot('A', app.slotA); ImGui.SameLine(); headerSlot('B', app.slotB)

    ImGui.Spacing()

    sa, sb = app.slotA, app.slotB
    if sa and sb and sa.stats and sb.stats then
        do
            local leg = '← worse    stat    better →'
            local avail = RegionAvailW()
            local lw = ui_help.calcTextWidth(leg)
            ImGui.SetCursorPosX(ImGui.GetCursorPosX() + math.max(0, (avail - lw) * 0.5))
            local lr, lg, lb, la = T.rgba(T.TEXT_SECONDARY)
            ImGui.PushStyleColor(ImGuiCol.Text, lr, lg, lb, la)
            ImGui.Text('%s', leg)
            ImGui.PopStyleColor()
        end
        ImGui.Separator()

        local rows = compare.iterComparedRows(sa.stats, sb.stats)
        local t = mq.gettime() / 1000
        local pulse = 0.85 + 0.15 * math.sin(t * 4)

        if ImGui.BeginTable('cmp_stats', 4, bit32.bor(ImGuiTableFlags.BordersInnerV, ImGuiTableFlags.RowBg)) then
            ImGui.TableSetupColumn('Stat', ImGuiTableColumnFlags.WidthFixed, 120)
            ImGui.TableSetupColumn('A', ImGuiTableColumnFlags.WidthFixed, 72)
            ImGui.TableSetupColumn('Δ', ImGuiTableColumnFlags.WidthStretch)
            ImGui.TableSetupColumn('B', ImGuiTableColumnFlags.WidthFixed, 72)
            ImGui.TableHeadersRow()

            for _, row in ipairs(rows) do
                ImGui.TableNextRow(); ImGui.TableNextColumn(); ImGui.Text('%s', row.label)

                ImGui.TableNextColumn()
                local hexA = T.TEXT_PRIMARY
                if row.a > row.b then hexA = T.TEXT_ACCENT elseif row.a < row.b then hexA = T.TEXT_SECONDARY end
                local ca1, ca2, ca3, ca4 = T.rgba(hexA)
                ImGui.PushStyleColor(ImGuiCol.Text, ca1, ca2, ca3, ca4)
                ImGui.Text('%s', string.format('%.0f', row.a))
                ImGui.PopStyleColor()

                ImGui.TableNextColumn()
                local frac = deltaBarFrac(row.a, row.b)
                local cx, cy = vec2XY(ImGui.GetCursorScreenPosVec())
                local avail = RegionAvailW()
                local mid = cx + avail * 0.5
                local barW = math.abs(frac) * (avail * 0.45)
                local dl = ImGui.GetWindowDrawList()
                local th = ImGui.GetTextLineHeight()
                dl:AddRectFilled(ImVec2(mid - 1, cy + 2), ImVec2(mid + 1, cy + th + 2), T.u32(T.BORDER_SUBTLE))
                local winB = row.b > row.a
                local ur, ug, ub, ua = T.rgba(T.DELTA_UPGRADE)
                local kr, kg, kb, ka = T.rgba(T.TEXT_ACCENT)
                local r, g, b = ur, ug, ub
                if not winB then r, g, b = kr, kg, kb end
                if frac > 0 then
                    dl:AddRectFilled(ImVec2(mid, cy + 4), ImVec2(mid + barW * pulse, cy + th), ImGui.GetColorU32(r, g, b, 0.88))
                elseif frac < 0 then
                    dl:AddRectFilled(ImVec2(mid - barW * pulse, cy + 4), ImVec2(mid, cy + th), ImGui.GetColorU32(r, g, b, 0.88))
                end
                ImGui.Dummy(avail, th)

                ImGui.TableNextColumn()
                local hexB = T.TEXT_PRIMARY
                if row.b > row.a then hexB = T.DELTA_UPGRADE elseif row.b < row.a then hexB = T.TEXT_SECONDARY end
                local cb1, cb2, cb3, cb4 = T.rgba(hexB)
                ImGui.PushStyleColor(ImGuiCol.Text, cb1, cb2, cb3, cb4)
                ImGui.Text('%s', string.format('%.0f', row.b))
                ImGui.PopStyleColor()
            end
            ImGui.EndTable()
        end

        ImGui.Spacing(); ImGui.Separator(); ImGui.Columns(2, 'focus_cols', false)
        focusBlock('Focus / clicky (A)', sa.stats, sb.stats); ImGui.NextColumn()
        focusBlock('Focus / clicky (B)', sb.stats, sa.stats); ImGui.Columns(1)
    end

    ImGui.End()
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Theme + entry
-- ═══════════════════════════════════════════════════════════════════════════

local app = {
    open = true,
    compareOpen = true,
    running = true,
    settings = config.load(),
    cachedRows = nil,
    totalScore = 0,
    overallRating = 0,
    breakdownTotal = { offensive = 0, defensive = 0, utility = 0 },
    maxScore = 1,
    refreshBusy = false,
    refreshAnimStart = 0,
    slotA = nil,
    slotB = nil,
    bagSlotOptions = nil,
}

local function onGui()
    ui_theme.push_obsidian_frame()
    drawMain(app)
    drawCompare(app)
    ui_theme.pop_obsidian_frame()
end

pcall(function() mq.event('InspectItem', '#*#', function() end) end)

mq.bind('/gsxquit', function() app.running = false end)

mq.imgui.init('GearScoreX', onGui)

print('\ag[GearScoreX]\ax Single-file UI loaded. \at/gsxquit\ax to stop.')

while app.running do
    mq.delay(0)
    mq.doevents()
end

pcall(function() mq.imgui.destroy('GearScoreX') end)
mq.exit()
