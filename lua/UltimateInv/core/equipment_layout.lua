--[[
  UltimateInv — worn slot order + inventory indices (EQ/MacroQuest convention).
]]

local M = {}

--- Human order for vertical equipment list (matches common paper-doll flow).
M.WORN_ORDER = {
    { key = 'head',       label = 'Head',       slot = 2 },
    { key = 'neck',       label = 'Neck',       slot = 5 },
    { key = 'face',       label = 'Face',       slot = 3 },
    { key = 'leftear',    label = 'Ear L',      slot = 1 },
    { key = 'rightear',   label = 'Ear R',      slot = 4 },
    { key = 'shoulder',   label = 'Shoulders',  slot = 6 },
    { key = 'arms',       label = 'Arms',       slot = 7 },
    { key = 'back',       label = 'Back',       slot = 8 },
    { key = 'leftwrist',  label = 'Wrist L',    slot = 9 },
    { key = 'rightwrist', label = 'Wrist R',    slot = 10 },
    { key = 'hands',      label = 'Hands',      slot = 12 },
    { key = 'chest',      label = 'Chest',      slot = 17 },
    { key = 'legs',       label = 'Legs',       slot = 18 },
    { key = 'feet',       label = 'Feet',       slot = 19 },
    { key = 'waist',      label = 'Waist',      slot = 20 },
    { key = 'charm',      label = 'Charm',      slot = 0 },
    { key = 'leftfinger', label = 'Finger L',   slot = 15 },
    { key = 'rightfinger',label = 'Finger R',   slot = 16 },
    { key = 'mainhand',   label = 'Primary',    slot = 13 },
    { key = 'offhand',    label = 'Secondary',  slot = 14 },
    { key = 'range',      label = 'Range',      slot = 11 },
    { key = 'ammo',       label = 'Ammo',       slot = 22 },
}

--- Pack slots on character (top-level bags).
M.PACK_INV_SLOTS = {}
for i = 23, 34 do
    M.PACK_INV_SLOTS[#M.PACK_INV_SLOTS + 1] = i
end

return M
