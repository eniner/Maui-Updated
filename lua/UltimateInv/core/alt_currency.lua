--[[
  UltimateInv — alternate currency balances.

  Ultimate EQ (and live) often expose the same balance under several spellings.
  Uses Me.AltCurrency(name) + mq.parse fallback (same approach as UltimateEQ HUD).
]]

local M = {}

--- Primary display name → variant spellings tried in order.
M.CURRENCY_DEFINITIONS = {
    { name = 'Tier 1 Credits',  variants = { 'Tier 1 Credits', 'Tier 1 Credit', 'Tier1 Credits' } },
    { name = 'Tier 2 Credits',  variants = { 'Tier 2 Credits', 'Tier 2 Credit', 'Tier2 Credits' } },
    { name = 'Tier 3 Credits',  variants = { 'Tier 3 Credits', 'Tier 3 Credit', 'Tier3 Credits' } },
    { name = 'Tier 4 Credits',  variants = { 'Tier 4 Credits', 'Tier 4 Credit', 'Tier4 Credits' } },
    { name = 'Tier 5 Credits',  variants = { 'Tier 5 Credits', 'Tier 5 Credit', 'Tier5 Credits' } },
    { name = 'Tier 6 Credits',  variants = { 'Tier 6 Credits', 'Tier 6 Credit', 'Tier6 Credits' } },
    { name = 'Tier 7 Credits',  variants = { 'Tier 7 Credits', 'Tier 7 Credit', 'Tier7 Credits' } },
    { name = 'Tier 8 Credits',  variants = { 'Tier 8 Credits', 'Tier 8 Credit', 'Tier8 Credits' } },
    { name = 'Tier 9 Credits',  variants = { 'Tier 9 Credits', 'Tier 9 Credit', 'Tier9 Credits' } },
    { name = 'Tier 10 Credits', variants = { 'Tier 10 Credits', 'Tier 10 Credit', 'Tier10 Credits' } },
    { name = 'Energy Crystals', variants = { 'Energy Crystals', 'Energy Crystal', 'EnergyCrystals' } },
    { name = 'Ebon Crystals',   variants = { 'Ebon Crystals', 'Ebon Crystal', 'EbonCrystals' } },
    { name = 'Radiant Crystals',variants = { 'Radiant Crystals', 'Radiant Crystal', 'RadiantCrystals' } },
    { name = 'Commemoratives',  variants = { 'Commemoratives', 'Commemorative' } },
    { name = 'Chronobines',     variants = { 'Chronobines', 'Chronobine' } },
    { name = 'Doubloons',       variants = { 'Doubloons', 'Doubloon' } },
    { name = 'Faycites',        variants = { 'Faycites', 'Faycite' } },
}

local function read_one(mq, variants)
    local Me = mq.TLO.Me
    for _, key in ipairs(variants) do
        local ok, val = pcall(function()
            local ac = Me.AltCurrency(key)
            if ac == nil then
                return nil
            end
            local v = ac()
            return tonumber(v)
        end)
        if ok and type(val) == 'number' and val >= 0 then
            return val
        end
    end
    for _, key in ipairs(variants) do
        local pat = '${Me.AltCurrency["' .. key:gsub('"', '\\"') .. '"]}'
        local ok, result = pcall(function()
            return mq.parse(pat)
        end)
        if ok and result and result ~= 'NULL' and result ~= '' then
            local num = tonumber(result)
            if num and num >= 0 then
                return num
            end
        end
    end
    return nil
end

--- Returns sorted list { name, qty } with qty > 0 first, optional zeros at end.
function M.snapshot(mq, opts)
    opts = opts or {}
    local show_zero = opts.show_zero == true
    local rows = {}

    for _, def in ipairs(M.CURRENCY_DEFINITIONS) do
        local q = read_one(mq, def.variants)
        if q == nil then
            q = 0
        end
        if show_zero or q > 0 then
            rows[#rows + 1] = { name = def.name, qty = q }
        end
    end

    table.sort(rows, function(a, b)
        if a.qty ~= b.qty then
            return a.qty > b.qty
        end
        return a.name < b.name
    end)

    return rows
end

return M
