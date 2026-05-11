--[[
  UltimateInv — live inventory snapshot (MacroQuest TLO only).
  Independent implementation; not derived from other inventory Lua products.
]]

local M = {}

--- EQ item icon atlas uses index - 500 for A_DragItem cells (client convention).
M.EQ_ICON_OFFSET = 500

local function item_qty(item)
    if not item then return 0 end
    local ok, q = pcall(function()
        local s = item.Stack()
        if type(s) == 'number' and s > 0 then return s end
        if item.Charges then
            local c = item.Charges()
            if type(c) == 'number' and c > 0 then return c end
        end
        if item.Count then
            local n = item.Count()
            if type(n) == 'number' and n > 0 then return n end
        end
        return 1
    end)
    return (ok and q) or 1
end

local function item_present(item)
    if not item then return false end
    local ok, exists = pcall(function() return item() end)
    if not ok or not exists then return false end
    local ok2, id = pcall(function() return item.ID() end)
    return ok2 and type(id) == 'number' and id > 0
end

--- Build hierarchical snapshot: equipped, pack tops, nested bag contents, optional bank.
function M.build(mq, opts)
    opts = opts or {}
    local include_bank = opts.include_bank ~= false

    local snap = {
        equipped = {},
        packs = {},
        bank = {},
    }

    for slot = 0, 22 do
        local inv = mq.TLO.Me.Inventory(slot)
        if item_present(inv) then
            local okn, name = pcall(function() return inv.Name() end)
            local oki, icon = pcall(function() return inv.Icon() end)
            local okd, id = pcall(function() return inv.ID() end)
            table.insert(snap.equipped, {
                slot = slot,
                name = (okn and name) or '?',
                id = (okd and id) or 0,
                icon = (oki and icon) or 0,
                qty = item_qty(inv),
                label = string.format('Worn slot %d', slot),
            })
        end
    end

    for invSlot = 23, 34 do
        local pack = mq.TLO.Me.Inventory(invSlot)
        if item_present(pack) then
            local okn, name = pcall(function() return pack.Name() end)
            local oki, icon = pcall(function() return pack.Icon() end)
            local okd, id = pcall(function() return pack.ID() end)
            local pack_num = invSlot - 22
            local entry = {
                inv_slot = invSlot,
                pack_num = pack_num,
                name = (okn and name) or '?',
                id = (okd and id) or 0,
                icon = (oki and icon) or 0,
                qty = item_qty(pack),
                contents = {},
            }
            local okc, cap = pcall(function() return pack.Container() end)
            local slots = (okc and type(cap) == 'number') and cap or 0
            if slots > 0 then
                for bagSlot = 1, slots do
                    local it = pack.Item(bagSlot)
                    if item_present(it) then
                        local nok, nm = pcall(function() return it.Name() end)
                        local iok, ic = pcall(function() return it.Icon() end)
                        local dok, did = pcall(function() return it.ID() end)
                        table.insert(entry.contents, {
                            bag_slot = bagSlot,
                            name = (nok and nm) or '?',
                            id = (dok and did) or 0,
                            icon = (iok and ic) or 0,
                            qty = item_qty(it),
                            label = string.format('Pack %d · slot %d', pack_num, bagSlot),
                        })
                    end
                end
            end
            snap.packs[invSlot] = entry
        end
    end

    if include_bank then
        for bankSlot = 1, 24 do
            local bankItem = mq.TLO.Me.Bank(bankSlot)
            if item_present(bankItem) then
                local okn, name = pcall(function() return bankItem.Name() end)
                local oki, icon = pcall(function() return bankItem.Icon() end)
                local okd, id = pcall(function() return bankItem.ID() end)
                local row = {
                    bank_slot = bankSlot,
                    name = (okn and name) or '?',
                    id = (okd and id) or 0,
                    icon = (oki and icon) or 0,
                    qty = item_qty(bankItem),
                    contents = {},
                    label = string.format('Bank %d', bankSlot),
                }
                local okc, cap = pcall(function() return bankItem.Container() end)
                local slots = (okc and type(cap) == 'number') and cap or 0
                if slots > 0 then
                    for i = 1, slots do
                        local it = bankItem.Item(i)
                        if item_present(it) then
                            local nok, nm = pcall(function() return it.Name() end)
                            local iok, ic = pcall(function() return it.Icon() end)
                            local dok, did = pcall(function() return it.ID() end)
                            table.insert(row.contents, {
                                bag_slot = i,
                                name = (nok and nm) or '?',
                                id = (dok and did) or 0,
                                icon = (iok and ic) or 0,
                                qty = item_qty(it),
                                label = string.format('Bank %d · bag slot %d', bankSlot, i),
                            })
                        end
                    end
                end
                table.insert(snap.bank, row)
            end
        end
    end

    return snap
end

--- MacroQuest pickup / click parity with native inventory (EZInventory-style paths).
local function notify_worn(slot)
    return string.format('/nomodkey /shift /itemnotify %d leftmouseup', slot)
end

local function notify_inv_top(inv_slot)
    return string.format('/nomodkey /shift /itemnotify %d leftmouseup', inv_slot)
end

local function notify_pack_item(pack_num, bag_slot)
    return string.format('/nomodkey /shift /itemnotify in pack%d %d leftmouseup', pack_num, bag_slot)
end

local function notify_bank_top(bank_slot)
    return string.format('/nomodkey /shift /itemnotify bank%d leftmouseup', bank_slot)
end

local function notify_bank_item(bank_slot, bag_slot)
    return string.format('/nomodkey /shift /itemnotify in bank%d %d leftmouseup', bank_slot, bag_slot)
end

--- Flat list for search / list-mode table; each row includes notify_cmd when applicable.
function M.flatten(snap)
    local rows = {}
    if not snap then return rows end

    for _, e in ipairs(snap.equipped or {}) do
        rows[#rows + 1] = {
            icon = e.icon,
            name = e.name,
            id = e.id,
            qty = e.qty,
            where = e.label,
            row_kind = 'worn',
            notify_cmd = notify_worn(e.slot),
        }
    end

    local packKeys = {}
    for k in pairs(snap.packs or {}) do
        packKeys[#packKeys + 1] = k
    end
    table.sort(packKeys)
    for _, invSlot in ipairs(packKeys) do
        local pack = snap.packs[invSlot]
        if pack then
            rows[#rows + 1] = {
                icon = pack.icon,
                name = pack.name,
                id = pack.id,
                qty = pack.qty,
                where = string.format('Pack %d (bag on character)', pack.pack_num),
                row_kind = 'pack_top',
                notify_cmd = notify_inv_top(pack.inv_slot),
            }
            for _, it in ipairs(pack.contents or {}) do
                rows[#rows + 1] = {
                    icon = it.icon,
                    name = it.name,
                    id = it.id,
                    qty = it.qty,
                    where = it.label,
                    row_kind = 'pack_item',
                    notify_cmd = notify_pack_item(pack.pack_num, it.bag_slot),
                }
            end
        end
    end

    for _, bank in ipairs(snap.bank or {}) do
        rows[#rows + 1] = {
            icon = bank.icon,
            name = bank.name,
            id = bank.id,
            qty = bank.qty,
            where = bank.label,
            row_kind = 'bank_top',
            notify_cmd = notify_bank_top(bank.bank_slot),
        }
        for _, it in ipairs(bank.contents or {}) do
            rows[#rows + 1] = {
                icon = it.icon,
                name = it.name,
                id = it.id,
                qty = it.qty,
                where = it.label,
                row_kind = 'bank_item',
                notify_cmd = notify_bank_item(bank.bank_slot, it.bag_slot),
            }
        end
    end

    return rows
end

return M
