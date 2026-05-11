--[[
  UltimateInv — character sheet snapshot via mq.TLO.Me (safe pcall reads).
]]

local equipment = require('UltimateInv.core.equipment_layout')

local M = {}

local function n(fn, default)
    local ok, v = pcall(fn)
    if ok and type(v) == 'number' then return v end
    return default or 0
end

local function s(fn, default)
    local ok, v = pcall(fn)
    if ok and v ~= nil and v ~= '' then return tostring(v) end
    return default or ''
end

local function try_me_num(Me, method, default)
    if not Me or not Me[method] then return default or 0 end
    return n(function() return Me[method]() end, default)
end

local function push_mod(list, label, value)
    if value == nil then return end
    list[#list + 1] = { label = label, value = value }
end

function M.build(mq)
    local Me = mq.TLO.Me
    local profile = {
        identity = {},
        vitals = {},
        combat = {},
        attrs = {},
        resists = {},
        weight = {},
        coins = {},
        mods = {},
        progress = {},
        worn = {},
        packs = {},
    }

    profile.identity = {
        name = s(function() return Me.CleanName() end, '?'),
        level = n(function() return Me.Level() end, 0),
        class = s(function() return Me.Class.Name() end, '?'),
        server = s(function() return mq.TLO.MacroQuest.Server() end, '?'),
        aa_title = s(function() return Me.AATitle() end, ''),
    }

    profile.vitals = {
        hp_cur = n(function() return Me.CurrentHPs() end, 0),
        hp_max = n(function() return Me.MaxHPs() end, 0),
        hp_pct = n(function() return Me.PctHPs() end, 0),
        mana_cur = n(function() return Me.CurrentMana() end, 0),
        mana_max = n(function() return Me.MaxMana() end, 0),
        mana_pct = n(function() return Me.PctMana() end, 0),
        end_cur = n(function() return Me.CurrentEndurance() end, 0),
        end_max = n(function() return Me.MaxEndurance() end, 0),
        end_pct = n(function() return Me.PctEndurance() end, 0),
    }

    local ac = n(function() return Me.AC() end, 0)
    if ac == 0 then
        ac = n(function() return Me.MitigationAC() end, 0)
    end
    profile.combat = {
        ac = ac,
        atk = n(function() return Me.AttackBonus() end, 0),
        haste = n(function() return Me.AttackSpeed() end, 0),
    }

    local attrs = {
        { 'STR', 'STR', 'BaseSTR', 'HeroicSTRBonus' },
        { 'STA', 'STA', 'BaseSTA', 'HeroicSTABonus' },
        { 'AGI', 'AGI', 'BaseAGI', 'HeroicAGIBonus' },
        { 'DEX', 'DEX', 'BaseDEX', 'HeroicDEXBonus' },
        { 'WIS', 'WIS', 'BaseWIS', 'HeroicWISBonus' },
        { 'INT', 'INT', 'BaseINT', 'HeroicINTBonus' },
        { 'CHA', 'CHA', 'BaseCHA', 'HeroicCHABonus' },
    }
    for _, row in ipairs(attrs) do
        local tag, totK, baseK, heroK = row[1], row[2], row[3], row[4]
        profile.attrs[#profile.attrs + 1] = {
            tag = tag,
            total = try_me_num(Me, totK, 0),
            base = try_me_num(Me, baseK, 0),
            heroic = try_me_num(Me, heroK, 0),
        }
    end

    profile.resists = {
        { label = 'Poison',    v = n(function() return Me.svPoison() end, 0) },
        { label = 'Magic',     v = n(function() return Me.svMagic() end, 0) },
        { label = 'Disease',   v = n(function() return Me.svDisease() end, 0) },
        { label = 'Fire',      v = n(function() return Me.svFire() end, 0) },
        { label = 'Cold',      v = n(function() return Me.svCold() end, 0) },
        { label = 'Corruption',v = n(function() return Me.svCorruption() end, 0) },
    }

    local cap = nil
    local okc, cv = pcall(function() return Me.Capacity() end)
    if okc and type(cv) == 'number' and cv > 0 then
        cap = cv
    end
    if not cap then
        local okw, wv = pcall(function() return Me.MaxWeight() end)
        if okw and type(wv) == 'number' and wv > 0 then
            cap = wv
        end
    end
    profile.weight = {
        cur = n(function() return Me.CurrentWeight() end, 0),
        cap = cap or 0,
    }

    profile.coins = {
        platinum = n(function() return Me.Platinum() end, 0),
        gold = n(function() return Me.Gold() end, 0),
        silver = n(function() return Me.Silver() end, 0),
        copper = n(function() return Me.Copper() end, 0),
    }

    profile.progress = {
        pct_exp = n(function() return Me.PctExp() end, 0),
        pct_aa = n(function() return Me.PctAAExp() end, 0),
    }

    local mods = {}
    push_mod(mods, 'HP Regen', n(function() return Me.HPRegen() end, nil))
    push_mod(mods, 'Mana Regen', n(function() return Me.ManaRegen() end, nil))
    push_mod(mods, 'Endurance Regen', n(function() return Me.EnduranceRegen() end, nil))
    push_mod(mods, 'Spell Shield', n(function() return Me.SpellShieldBonus() end, nil))
    push_mod(mods, 'Shielding', n(function() return Me.ShieldingBonus() end, nil))
    push_mod(mods, 'Avoidance', n(function() return Me.AvoidanceBonus() end, nil))
    push_mod(mods, 'Accuracy', n(function() return Me.AccuracyBonus() end, nil))
    push_mod(mods, 'Strike Through', n(function() return Me.StrikeThroughBonus() end, nil))
    push_mod(mods, 'Combat Effects', n(function() return Me.CombatEffectsBonus() end, nil))
    push_mod(mods, 'DoT Shield', n(function() return Me.DoTShieldBonus() end, nil))
    push_mod(mods, 'Damage Shield', n(function() return Me.DamageShieldBonus() end, nil))
    push_mod(mods, 'Heal Amount', n(function() return Me.HealAmountBonus() end, nil))
    push_mod(mods, 'Spell Damage', n(function() return Me.SpellDamageBonus() end, nil))
    push_mod(mods, 'Clairvoyance', n(function() return Me.ClairvoyanceBonus() end, nil))
    push_mod(mods, 'Stun Resist', n(function() return Me.StunResistBonus() end, nil))
    profile.mods = mods

    for _, def in ipairs(equipment.WORN_ORDER) do
        local inv = Me.Inventory(def.slot)
        local ok = pcall(function() return inv() end)
        local entry = { label = def.label, slot = def.slot, name = '', icon = 0, id = 0,
            notify_cmd = string.format('/nomodkey /shift /itemnotify %d leftmouseup', def.slot) }
        if ok and inv() then
            entry.name = s(function() return inv.Name() end, '')
            entry.icon = n(function() return inv.Icon() end, 0)
            entry.id = n(function() return inv.ID() end, 0)
        end
        profile.worn[#profile.worn + 1] = entry
    end

    for _, invSlot in ipairs(equipment.PACK_INV_SLOTS) do
        local pack = Me.Inventory(invSlot)
        local ok = pcall(function() return pack() end)
        local idx = invSlot - 22
        local entry = {
            inv_slot = invSlot,
            pack_num = idx,
            name = '',
            icon = 0,
            id = 0,
            notify_cmd = string.format('/nomodkey /shift /itemnotify %d leftmouseup', invSlot),
        }
        if ok and pack() then
            entry.name = s(function() return pack.Name() end, '')
            entry.icon = n(function() return pack.Icon() end, 0)
            entry.id = n(function() return pack.ID() end, 0)
        end
        profile.packs[#profile.packs + 1] = entry
    end

    return profile
end

return M
