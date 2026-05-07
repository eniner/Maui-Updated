--[[
  Transmute.lua — MacroQuest Lua (ImGui)

  Transmutation Assistant: recipe scroll turn-ins (385 vendor.scroll), targets CONFIG.npcTarget.

  Arcane Transmutation Device: optional second panel — zone loot rows for dust breakdown,
  and multi-reagent crafts from 385 vendor.craft (embedded in this file).

  Install: copy Transmute.lua + folder lua/transmute/ (ueq-transmute.png) to MacroQuest "lua", then:
    /lua run Transmute

  Persistence: TransmuteAssistantTurnIn.ini — scroll id=0|1, dust d<itemid>=0|1, recipe r_<key>=0|1.
  Recipe rows are embedded in TRANSMUTE_SCROLLS below (edit there when the shard updates JSON).
  SCROLL_CATEGORY maps each scroll id to a tier band (from craft requiredskill / itemtier in
  385_craft_and_gamble.json). Assistant scroll counts use FindItemCount with quoted names (colons
  break the old unquoted macro form). Device recipe mat counts use one throttled Me.Inventory id scan
  (FindItemCount by id is unreliable). Live rescan defaults OFF — use Rescan or turn-in to refresh;
  optional slow live scan in CONFIG. Row on/off uses SmallButton [x]/[ ] (reliable on MQ Lua).

  Hand-in flow follows RedGuides GiveIt (towbes/giveit): InventoryWindow.DoOpen (not INVENTORY toggle),
  target+face, /itemnotify on bag slot (+ QuantityWnd), fixed delay, /click left target, then GiveWnd (no Cursor polling).
  Device crafts and assistant scroll batches: each stack is handed with /click left target (same as first
  slot); the client fills the next Give slot. Then one Give button click. Matches server check_handin bundles.
  Recipe/dust icons: embedded TRANSMUTE_ITEM_ICONS (PEQ UltDev catalog) so the UI can
  draw tiles without owning items; counts still come from MQ inventory logic.
  See: https://github.com/towbes/giveit/blob/main/init.lua — OpenInventory, Give(), /click left target.

  Terminology (MQ macros, not “made up”): In-game you have bags/containers in bag slots. MacroQuest’s
  /itemnotify token is still spelled `in pack1` … `in pack12` = first through twelfth equipped bag slot
  (same as Me.Inventory(23)…(34)). GiveIt uses the same string. Docs: https://docs.macroquest.org/reference/commands/itemnotify

  Before pickup, default behavior uses the same bind as the game: `/keypress OPEN_INV_BAGS` (toggle all
  inventory bags — see MacroQuest /keypress “Common EQUI Keybinds” and `/bind eqlist` to confirm the name
  on your client/emulator).
]]

local mq = require('mq')
local ImGui = require('ImGui')
local ueqFloat = require('ueq_logo_float')

--- vendor.scroll from server/quests/global/vendordata/385_craft_and_gamble.json
local TRANSMUTE_SCROLLS = {
  { id = 1, name = 'Transmutation Recipe: Arcane Dust' },
  { id = 2, name = 'Transmutation Recipe: Arcane Crystal' },
  { id = 3, name = 'Transmutation Recipe: Blasting Powder' },
  { id = 150060, name = 'Transmutation Recipe: Ghoul Lord Summoning Focus' },
  { id = 150061, name = 'Transmutation Recipe: Bubbling Jar of Immolation' },
  { id = 150062, name = 'Transmutation Recipe: Stone of Ultimate Stamina' },
  { id = 150063, name = 'Transmutation Recipe: Stone of Ultimate Agility' },
  { id = 150064, name = 'Transmutation Recipe: Stone of Ultimate Intelligence' },
  { id = 150065, name = 'Transmutation Recipe: Stone of Ultimate Dexterity' },
  { id = 150066, name = 'Transmutation Recipe: Stone of Ultimate Strength' },
  { id = 150074, name = 'Transmutation Recipe: Ultimate Token to Legendary Mold' },
  { id = 150075, name = 'Transmutation Recipe: Legendary Mold to Ultimate Token' },
  { id = 150076, name = 'Transmutation Recipe: Goblin Duplicator XL' },
  { id = 150077, name = 'Transmutation Recipe: Trakanons Annihilator' },
  { id = 150135, name = 'Transmutation Recipe: Goblin Hate Generator XTZ' },
  { id = 150078, name = 'Transmutation Recipe: Vision Dust' },
  { id = 150079, name = 'Transmutation Recipe: Gleaming Crystal' },
  { id = 150080, name = 'Transmutation Recipe: Refined Nightshade' },
  { id = 150081, name = 'Transmutation Recipe: Brittle Arclight Spanner' },
  { id = 150083, name = 'Transmutation Recipe: Stone of Avatar Agility' },
  { id = 150084, name = 'Transmutation Recipe: Stone of Avatar Intelligence' },
  { id = 150085, name = 'Transmutation Recipe: Stone of Avatar Dexterity' },
  { id = 150086, name = 'Transmutation Recipe: Stone of Avatar Strength' },
  { id = 150087, name = 'Transmutation Recipe: Goblin Sapper Charge 1A' },
  { id = 150088, name = 'Transmutation Recipe: Gnomish Death Ray 1A' },
  { id = 150089, name = 'Transmutation Recipe: Cursed Fang of Mayong' },
  { id = 150090, name = 'Transmutation Recipe: Sublime Dust' },
  { id = 150091, name = 'Transmutation Recipe: Empyreal Crystal' },
  { id = 150092, name = 'Transmutation Recipe: Simmering Pitch' },
  { id = 150145, name = 'Transmutation Recipe: Demigod Flux' },
  { id = 150094, name = 'Transmutation Recipe: Stone of Demigod Agility' },
  { id = 150095, name = 'Transmutation Recipe: Stone of Demigod Intelligence' },
  { id = 150096, name = 'Transmutation Recipe: Stone of Demigod Dexterity' },
  { id = 150097, name = 'Transmutation Recipe: Stone of Demigod Strength' },
  { id = 150098, name = 'Transmutation Recipe: Gnomish Death Ray 2B' },
  { id = 150099, name = 'Transmutation Recipe: Gnomish Jumper Cables XLT' },
  { id = 150100, name = 'Transmutation Recipe: Elixir of Ascendence' },
  { id = 150101, name = 'Transmutation Recipe: Gnomish Rocket Boots' },
  { id = 150102, name = 'Transmutation Recipe: Angelic Dust' },
  { id = 150103, name = 'Transmutation Recipe: Angelic Crystal' },
  { id = 150104, name = 'Transmutation Recipe: Cloudy Chromatic Gem' },
  { id = 150110, name = 'Transmutation Recipe: Goblin Mind Control Device' },
  { id = 150112, name = 'Transmutation Recipe: Philosophers Stone' },
  { id = 150111, name = 'Transmutation Recipe: Goblin Harm Prevention Ring' },
  { id = 150166, name = 'Transmutation Recipe: Trademaster Assembly' },
  { id = 150113, name = 'Transmutation Recipe: Socket Fitter XXL' },
  { id = 150106, name = 'Transmutation Recipe: Stone of Godly Agility' },
  { id = 150107, name = 'Transmutation Recipe: Stone of Godly Intelligence' },
  { id = 150108, name = 'Transmutation Recipe: Stone of Godly Dexterity' },
  { id = 150109, name = 'Transmutation Recipe: Stone of Godly Strength' },
  { id = 150114, name = 'Transmutation Recipe: Gnomish Death Ray X1' },
  { id = 150117, name = 'Transmutation Recipe: Nightfall' },
  { id = 150115, name = 'Transmutation Recipe: Corrupted Prismatic Bauble' },
  { id = 150116, name = 'Transmutation Recipe: Chained Essence of Kerafyrm' },
  { id = 150215, name = 'Transmutation Recipe: Repurposed Alert-O-Bot' },
  { id = 150216, name = 'Transmutation Recipe: Super Jenkins' },
  { id = 150217, name = 'Transmutation Recipe: Goblin Suppression Device' },
  { id = 150225, name = 'Transmutation Recipe: Advanced Boss Summon Device' },
}

local SCROLL_BY_ID = {}
for _, row in ipairs(TRANSMUTE_SCROLLS) do
  SCROLL_BY_ID[row.id] = row
end

--- Per scroll id: tier (edit here when the shard adds recipes; no external tooling).
--- Convention: Starter = free starter scroll ids 1–3; else Ultimate 1–75 / Avatar 76–150 /
--- Demigod 151–225 / Godly 226+ skill on the matching craft in 385_craft_and_gamble.json,
--- or the craft itemtier string when present.
local SCROLL_CATEGORY = {
  [1] = 'Starter',
  [2] = 'Starter',
  [3] = 'Starter',
  [150060] = 'Ultimate',
  [150061] = 'Ultimate',
  [150062] = 'Ultimate',
  [150063] = 'Ultimate',
  [150064] = 'Ultimate',
  [150065] = 'Ultimate',
  [150066] = 'Ultimate',
  [150074] = 'Ultimate',
  [150075] = 'Ultimate',
  [150076] = 'Ultimate',
  [150077] = 'Ultimate',
  [150135] = 'Ultimate',
  [150078] = 'Avatar',
  [150079] = 'Avatar',
  [150080] = 'Avatar',
  [150081] = 'Avatar',
  [150083] = 'Avatar',
  [150084] = 'Avatar',
  [150085] = 'Avatar',
  [150086] = 'Avatar',
  [150087] = 'Avatar',
  [150088] = 'Avatar',
  [150089] = 'Avatar',
  [150090] = 'Demigod',
  [150091] = 'Demigod',
  [150092] = 'Demigod',
  [150145] = 'Demigod',
  [150094] = 'Demigod',
  [150095] = 'Demigod',
  [150096] = 'Demigod',
  [150097] = 'Demigod',
  [150098] = 'Demigod',
  [150099] = 'Demigod',
  [150100] = 'Demigod',
  [150101] = 'Demigod',
  [150102] = 'Godly',
  [150103] = 'Godly',
  [150104] = 'Godly',
  [150110] = 'Godly',
  [150112] = 'Godly',
  [150111] = 'Godly',
  [150166] = 'Godly',
  [150113] = 'Godly',
  [150106] = 'Godly',
  [150107] = 'Godly',
  [150108] = 'Godly',
  [150109] = 'Godly',
  [150114] = 'Godly',
  [150117] = 'Godly',
  [150115] = 'Godly',
  [150116] = 'Godly',
  [150215] = 'Godly',
  [150216] = 'Godly',
  [150217] = 'Godly',
  [150225] = 'Godly',
}

local CATEGORY_ORDER = { 'Starter', 'Ultimate', 'Avatar', 'Demigod', 'Godly', 'Unknown', 'Misc' }

local CONFIG = {
  --- Substring for /target (use /echo ${Target.CleanName} while targeting the NPC)
  npcTarget = 'Transmutation',
  --- If you know the NPC spawn ID: set > 0 to use /target id (more reliable than name)
  npcSpawnId = 0,
  --- If set, CleanName must contain this (e.g. Transmutation). '' skips the check.
  npcNameMustContain = '',
  delayAfterTarget = 0.55,
  --- After /face (when not using open-inventory wait), pause before Give click so the client catches up
  delayBeforeGiveClick = 0.22,
  delayGiveWnd = 0.85,
  delayAfterGive = 1.35,
  --- Optional: your in-game Give-to-target keybind name for /keypress (see MQ docs)
  keypressOpenGive = '',
  maxGiveOpenTries = 8,
  --- Max distance to NPC for trade (game units)
  maxGiveDistance = 25,
  --- Run /face before each click attempt
  faceBeforeGive = true,
  --- On failed GiveWnd, alternate /click right target with left (some UIs need it)
  tryRightClickGive = true,
  --- Open main inventory once per queue via DoOpen (GiveIt-style). Set false if you already have it open.
  openInventoryBeforeGive = true,
  --- Use Window.InventoryWindow.DoOpen() (recommended). If false, only keypress path is used when waiting fails.
  inventoryUseDoOpen = true,
  --- After many failed DoOpen polls, send /keypress INVENTORY once (can toggle EZ — default off).
  inventoryFallbackKeypressOnce = false,
  --- MacroQuest /keypress name when inventoryFallbackKeypressOnce runs
  inventoryKeypress = 'INVENTORY',
  --- Polls (~50ms each) waiting for InventoryWindow.Open() before pickup
  maxInventoryOpenWaitTries = 36,
  --- Seconds after inventory reports open before pickup (GiveIt uses a long delay after open)
  delayAfterInventoryOpen = 0.45,
  --- Pause before /click left target after bag-slot pickup (no Cursor TLO gate)
  delayAfterPickupBeforeClick = 0.55,
  --- Seconds between /itemnotify and the quantity/click-target phase (ImGui tick spacing)
  delayAfterItemnotify = 0.12,
  --- GiveIt uses plain /itemnotify; /nomodkey can block pickup on some clients — try false first
  pickupUseNomodkey = false,
  --- Fixed ms after /itemnotify on the bag slot (client processes lift; we do not poll Cursor)
  delayMsAfterItemnotifyPickup = 650,
  --- Also try TargetWindow give-button /notify lines (default UI names; turn off if wrong for your UI)
  tryTargetWindowGive = true,
  --- In-game hotkey: open/toggle ALL inventory bag windows (EQ bind name; use /bind eqlist if yours differs)
  keypressOpenAllBags = 'OPEN_INV_BAGS',
  --- Send /keypress before each /itemnotify pickup so items inside bags are reachable
  useKeypressOpenAllBags = true,
  --- Milliseconds to wait after OPEN_INV_BAGS before itemnotify (bags need time to open)
  delayMsAfterOpenAllBags = 550,
  --- Optional: right-click one bag via /itemnotify in packN (often redundant if keypressOpenAllBags works)
  tryOpenBagBeforePickup = false,
  --- If ${FindItem} parse fails, scan Me.Inventory like EZInventory (slots 0–22 + bags 23–34)
  useInventorySlotScanFallback = true,
  --- Live rescan: OFF by default (avoids hammering mq.parse / FindItemCount every frame).
  invLiveScan = false,
  --- When invLiveScan is true, minimum seconds between full scans
  invRefreshSec = 5.0,
  --- Recipes tab: reuse one Me.Inventory id scan for this many seconds (ImGui redraws every frame).
  recipeCountUiCacheSec = 0.65,
  --- Item icons (A_DragItem atlas, PEQ-seeded + MQ fallbacks): Device recipes table, Assistant scroll rows, and Dust loot rows.
  recipeRowItemIcons = true,
  recipeRowIconSize = 22,
  --- Mode row: show a representative item tile before each tab (PEQ-seeded + MQ fallbacks).
  modeTabItemIcons = true,
  modeTabIconSize = 20,
  --- Assistant: pack this many scrolls into one Give (matches server loop in Transmutation_Assistant.pl). Set 1 for one-at-a-time.
  assistantScrollsPerGive = 4,
  --- When Run cannot queue recipes, also /echo the reason to MQ chat (off = no chat spam).
  echoWhenRecipeBlocked = false,
  --- Arcane Transmutation Device (matches guildlobby Arcane_Transmutation_Device.pl — NOT the assistant NPC)
  deviceNpcTarget = 'Arcane',
  deviceNpcSpawnId = 0,
  deviceNameMustContain = '',
}

local SCRIPT_ID = 'transmute_assistant_turnin'
local INI_NAME = 'TransmuteAssistantTurnIn.ini'

--- UI tab: assistant | dust_u | dust_a | dust_d | recipes
local uiTab = 'assistant'
local dustInventoryOnly = true

local uiOpen = true
local terminate = false
local filterBuf = ''
local statusLine = 'Idle.'
local enabled = {}
local dirty = false
local checkboxClickAt = {}

local TI = {
  active = false,
  phase = 0,
  queue = {},
  currentName = nil,
  nextAt = 0,
  giveTries = 0,
  --- Phase 1: 0 = validate+face+start inv, 10 = wait InventoryWindow.Open, 1 = delay then go pickup
  p1sub = 0,
  --- Phase 2: 0 = validate+keypress bags, 1 = wait bags open, 2 = fire itemnotify+wait, 3 = cursor check
  p2sub = 0,
  --- Resolved /itemnotify token for current item (set in phase 2 sub 0, cleared on popQueue/abort)
  resolvedToken = nil,
  --- After first successful inventory open (or give up), skip DoOpen for rest of queue
  invInventoryPrimed = false,
  invOpenWaitTries = 0,
  invFallbackKeyDone = false,
  pickupHandName = nil,
  --- Phase 3: attempts while QuantityWnd is still open
  p3tries = 0,
  --- 'assistant' uses CONFIG.npcTarget; 'device' uses CONFIG.deviceNpcTarget
  tradeTarget = 'assistant',
  --- Multi-item device recipes (Arcane_Transmutation_Device.pl reagent bundles)
  recipePhase = 0,
  recipeMatIdx = 1,
  recipeEntry = nil,
  --- Assistant scroll batch (one Give, multiple scroll ids)
  sbPhase = 0,
  sbIdx = 1,
  sbIds = nil,
  --- Pickup: ticks while QuantityWnd is open (cursor stays empty until accepted)
  qtyWndStuck = 0,
}

local function cleanTargetName()
  local ok, n = pcall(function()
    return mq.TLO.Target.CleanName()
  end)
  if ok and n then
    return tostring(n)
  end
  return ''
end

local function targetId()
  local ok, id = pcall(function()
    return tonumber(mq.TLO.Target.ID() or 0) or 0
  end)
  return ok and id or 0
end

local function targetDistance()
  local ok, d = pcall(function()
    return tonumber(mq.TLO.Target.Distance() or 999) or 999
  end)
  return ok and d or 999
end

local function validateTargetForTrade()
  local id = targetId()
  if id <= 0 then
    return false,
      'No target after /target. Target the NPC manually once, /echo ${Target.CleanName}, then set CONFIG.npcTarget / deviceNpcTarget (or spawn id).'
  end
  local maxd = CONFIG.maxGiveDistance or 25
  local dist = targetDistance()
  if dist > maxd then
    return false, string.format('Too far from target (%.1f > %d). Move closer and try again.', dist, maxd)
  end
  local need = ''
  if TI.tradeTarget == 'device' then
    need = CONFIG.deviceNameMustContain or ''
  else
    need = CONFIG.npcNameMustContain or ''
  end
  if need ~= '' then
    local nm = cleanTargetName():lower()
    if not nm:find(need:lower(), 1, true) then
      return false,
        string.format(
          'Wrong target "%s" (expected CleanName to contain "%s").',
          cleanTargetName(),
          need
        )
    end
  end
  return true, ''
end

local function giveFailureSummary()
  local hint =
    'Flow: bag-slot /itemnotify, /click left target. Try delayMsAfterItemnotifyPickup, delayAfterPickupBeforeClick, delayGiveWnd, tryTargetWindowGive=false, keypressOpenGive, npcSpawnId.'
  local bits = {
    'GiveWnd did not open after /click target (item may not have left the bag — check /itemnotify token).',
    string.format('Target="%s" id=%s dist=%.1f.', cleanTargetName(), tostring(targetId()), targetDistance()),
    hint,
  }
  return table.concat(bits, ' ')
end

local function inventoryMainOpen()
  local ok, o = pcall(function()
    return mq.TLO.Window('InventoryWindow').Open()
  end)
  return ok and o
end

local function tryInventoryDoOpen()
  if not CONFIG.inventoryUseDoOpen then
    return
  end
  pcall(function()
    mq.TLO.Window('InventoryWindow').DoOpen()
  end)
end

local function quantityWndOpen()
  local ok, o = pcall(function()
    return mq.TLO.Window('QuantityWnd').Open()
  end)
  return ok and o
end

local function acceptQuantityWnd()
  if not quantityWndOpen() then
    return false
  end
  -- Stack split: set quantity to 1 then Accept (names vary by client; see prism.lua / MQ docs).
  pcall(function()
    mq.cmd('/nomodkey /notify QuantityWnd QTYW_slider newvalue 1')
  end)
  pcall(function()
    mq.cmd('/nomodkey /notify QuantityWnd QTYW_Slider newvalue 1')
  end)
  pcall(function()
    mq.cmd('/notify QuantityWnd QTYW_slider newvalue 1')
  end)
  pcall(function()
    mq.cmd('/notify QuantityWnd QTYW_Slider newvalue 1')
  end)
  pcall(function()
    mq.cmd('/notify QuantityWnd QTYW_SliderInput newvalue 1')
  end)
  pcall(function()
    mq.cmd('/nomodkey /notify QuantityWnd QTYW_Accept_Button leftmouseup')
  end)
  pcall(function()
    mq.cmd('/notify QuantityWnd QTYW_Accept_Button leftmouseup')
  end)
  return true
end

--- Cached counts + resolved item name for /itemnotify (macro parser is picky about ":")
local invCache = {}
local invHandName = {}
local invScanAt = 0
local invScanGen = 0
--- Single-pass slot scan: item id -> stack count (device recipe UI + queue; rebuilt on refresh / turn-in).
local invIdCount = {}
--- Last rebuild time (mq.gettime ms); 0 = never / force refresh.
local invIdCountAtMs = 0
--- Cached FindItem.Icon() for recipe row tiles (cleared in refreshInventoryCache).
local eqItemIconCache = {}

local function clock()
  if os and os.clock then
    return os.clock()
  end
  return 0
end

--- Wall-ish clock for UI cache TTL (os.clock is CPU time and can lag perception of "seconds").
local function timeMs()
  local ok, t = pcall(function()
    return mq.gettime()
  end)
  if ok and type(t) == 'number' and t >= 0 then
    return t
  end
  return math.floor(clock() * 1000)
end

--- Normalize MQ item datatype ID() to a positive item id.
local function itemNumericId(it)
  if not it then
    return 0
  end
  local ok, raw = pcall(function()
    return it.ID()
  end)
  if not ok or raw == nil then
    return 0
  end
  local n = tonumber(raw)
  if n and n > 0 then
    return n
  end
  local s = tostring(raw):match('^%s*(%d+)')
  return tonumber(s) or 0
end

local function macroQuestLuaDir()
  local ok, p = pcall(function()
    return mq.TLO.MacroQuest.Path('lua')()
  end)
  if ok and p and p ~= '' then
    return p
  end
  ok, p = pcall(function()
    return mq.TLO.MacroQuest.Path()()
  end)
  if ok and p and p ~= '' then
    return p .. '\\lua'
  end
  return '.'
end

local function iniPath()
  return macroQuestLuaDir() .. '\\' .. INI_NAME
end

--- Embedded device data (generated from shard JSON).
local TRANSMUTE_DEVICE_DATA = (function()
-- AUTO-GENERATED — edit gen_transmute_device_data.py and re-run: python gen_transmute_device_data.py
-- Floating logo / UI art: Transmute.lua uses lua/transmute/ueq-transmute.png (`imageRelPath` in ueq_logo_float); this file is data-only.
-- Source: 385_craft_and_gamble.json + ultimatedata zone item tables + UltDev/catalog/PEQ/items.json (icon seed)
-- Zones Ultimate 65,66,89,113,124,128 | Avatar 17,31,39,59,108,111 | Demigod 63,69,72,112,469

local ULTIMATE_LOOT = {
  { id = 10012, name = 'Black Pearl' },
  { id = 10029, name = 'Emerald' },
  { id = 147496, name = 'Ultimate Token' },
  { id = 147732, name = 'Heels of Amelioration' },
  { id = 147733, name = 'Guk Chitin Protector' },
  { id = 147734, name = 'Guktan Slacks of Preservation' },
  { id = 147735, name = 'Slime-Soaked Guktan Gloves' },
  { id = 147736, name = 'Clasp of Determination' },
  { id = 147737, name = 'Sleeves of Traction' },
  { id = 147738, name = 'Turban of The Majority' },
  { id = 147740, name = 'Shield of Flux' },
  { id = 147741, name = 'Sacrificial Neckguard' },
  { id = 147743, name = 'Bracer of The Fragile' },
  { id = 147744, name = 'Bracer of The Broken' },
  { id = 147745, name = 'Ring of The Unstoppable Force' },
  { id = 147746, name = 'Mantle of the Cascade' },
  { id = 147747, name = 'Earring of The Insects' },
  { id = 147748, name = 'Cloak of Guk\'s Fury' },
  { id = 147749, name = 'Necklace of The Cripple' },
  { id = 147750, name = 'Shiny Metallic Robe of Arch Magus' },
  { id = 147751, name = 'Orb of Flowing Mana' },
  { id = 147752, name = 'The Frenzied Belt' },
  { id = 147753, name = 'The Master\'s Sandals' },
  { id = 147754, name = 'Warboots of The Enthused' },
  { id = 147756, name = 'Guktan Healthstone' },
  { id = 147757, name = 'Superior Guktan Stone' },
  { id = 147758, name = 'Chains of The Lunar Eclipse' },
  { id = 147759, name = 'Gloves of the Dead Man' },
  { id = 147760, name = 'Stained Mask of The Deceiver' },
  { id = 147761, name = 'Ancient Sleeves' },
  { id = 147762, name = 'Barrier of Insanity' },
  { id = 147763, name = 'Legendary Mold' },
  { id = 147780, name = 'Shin Lord\'s Steel Carapace ' },
  { id = 147781, name = 'Bracer of The Coil' },
  { id = 147782, name = 'Ring of The Overflowing Tempest' },
  { id = 147783, name = 'Helmet of Unending War' },
  { id = 147784, name = 'Earring of Midnight Mist' },
  { id = 147785, name = 'Bracer of Northern Grit' },
  { id = 147786, name = 'Belt of Subtlety' },
  { id = 147787, name = 'Ring of Tactics' },
  { id = 147788, name = 'Lifebane Gorget' },
  { id = 147789, name = 'Guk-Woven Cloak of Protection' },
  { id = 147790, name = 'Pauldrons of Decimation' },
  { id = 147791, name = 'Cover of The Unseen' },
  { id = 147792, name = 'Gloves of Questionable Ambition' },
  { id = 147793, name = 'Jewel of Enlightenment' },
  { id = 147794, name = 'Bloodstained Greaves of The Realist' },
  { id = 147795, name = 'Slimy Trousers of The Idealist' },
  { id = 147796, name = 'Armguards of Disdain' },
  { id = 147797, name = 'Gravelord\'s Desirable Fetish' },
  { id = 147798, name = 'Lunar Robe of the Whistling Fists' },
  { id = 147799, name = 'Orb of Sharp Spikes' },
  { id = 147800, name = 'Ghoul Lord\'s Head' },
  { id = 147801, name = 'Froglok King\'s Head' },
  { id = 147802, name = 'Shin Lord\'s Head' },
  { id = 147803, name = 'Ancient Croc\'s Head' },
  { id = 147805, name = 'Chaosforged Helmet' },
  { id = 147806, name = 'Chaosforged Breastplate' },
  { id = 147807, name = 'Chaosforged Gauntlets' },
  { id = 147808, name = 'Chaosforged Bracer' },
  { id = 147809, name = 'Chaosforged Vambraces' },
  { id = 147810, name = 'Chaosforged Boots' },
  { id = 147811, name = 'Chaosforged Greaves' },
  { id = 147812, name = 'Chaoslinked Coif' },
  { id = 147813, name = 'Chaoslinked Tunic' },
  { id = 147814, name = 'Chaoslinked Gauntlets' },
  { id = 147815, name = 'Chaoslinked Wristwraps' },
  { id = 147816, name = 'Chaoslinked Armguards' },
  { id = 147817, name = 'Chaoslinked Sandals' },
  { id = 147818, name = 'Chaoslinked Trousers' },
  { id = 147819, name = 'Chaoswoven Cap' },
  { id = 147820, name = 'Chaoswoven Robe' },
  { id = 147821, name = 'Chaoswoven Gloves' },
  { id = 147822, name = 'Chaoswoven Wristband' },
  { id = 147823, name = 'Chaoswoven Sleeves' },
  { id = 147824, name = 'Chaoswoven Slippers' },
  { id = 147825, name = 'Chaoswoven Leggings' },
  { id = 147858, name = 'Sebilite Stone of Health' },
  { id = 147859, name = 'Sebilite Ring of Insanity' },
  { id = 147860, name = 'Soulbroken Earring' },
  { id = 147861, name = 'Necklace of The Blazing Forest' },
  { id = 147862, name = 'Reinforced Belt of The Emperor' },
  { id = 147863, name = 'Harbinger\'s Cord of The Corona' },
  { id = 147864, name = 'Wedding Ring of Adjudication' },
  { id = 147865, name = 'Earring of Rusty Gears' },
  { id = 147866, name = 'Mask of The Perilous' },
  { id = 147867, name = 'Death\'s Visage' },
  { id = 147868, name = 'Armorer\'s Reinforced Steel Cloak' },
  { id = 147869, name = 'Cloak of Sebilite Fury' },
  { id = 147870, name = 'Wolfbane Shoulderpads' },
  { id = 147871, name = 'Spiked Pauldrons of Frozen Waves' },
  { id = 147872, name = 'Crystalized Jewel of Foresight' },
  { id = 147873, name = 'Shield of Brutality' },
  { id = 147875, name = 'Sebilite Stone of Immaculate Health' },
  { id = 147876, name = 'Perfected Sebilite Stone' },
  { id = 147877, name = 'Ultimate Trakanon\'s Fist Stone' },
  { id = 147878, name = 'Ultimate Trakanon\'s Slashing Stone' },
  { id = 147879, name = 'Ultimate Trakanon\'s 2H Slashing Stone' },
  { id = 147880, name = 'Ultimate Trakanon\'s Bowmaster Stone' },
  { id = 147881, name = 'Ultimate Trakanon\'s Fiery Stone' },
  { id = 147882, name = 'Ultimate Trakanon\'s Diseased Stone' },
  { id = 147883, name = 'Ultimate Trakanon\'s Refreshing Stone' },
  { id = 147884, name = 'Talking Head Necklace' },
  { id = 147896, name = 'Ultimate Trakanon\'s Heart' },
  { id = 147898, name = 'Mask of Consequences' },
  { id = 147910, name = 'Vulakian Armor Token' },
  { id = 148026, name = 'Stone of the Temple' },
  { id = 148027, name = 'Veeshan\'s Seal of the Cryomancer' },
  { id = 148028, name = 'Veeshan\'s Seal of the Pyromancer' },
  { id = 148029, name = 'Veeshan\'s Seal of the Arcanist' },
  { id = 148030, name = 'Veeshan\'s Seal of the Assassin' },
  { id = 148031, name = 'Veeshan\'s Seal of the Plagued' },
  { id = 148033, name = 'Veeshan\'s Seal of the Healer' },
  { id = 148034, name = 'Veeshan\'s Seal of the Benevolent' },
  { id = 148035, name = 'Veeshan\'s Seal of the Aggressor' },
  { id = 148036, name = 'Veeshan\'s Seal of the Expedient' },
  { id = 148037, name = 'Veeshan\'s Seal of the Oracle' },
  { id = 148038, name = 'Veeshan\'s Seal of the Nimble' },
  { id = 148039, name = 'Veeshan\'s Seal of the Juggernaut' },
  { id = 148040, name = 'Veeshan\'s Seal of the Ferocious' },
  { id = 148041, name = 'Veeshan\'s Seal of the Wild' },
  { id = 148055, name = 'Veeshan\'s Seal of the Champion' },
  { id = 148056, name = 'Veeshan\'s Seal of the Frenzied' },
  { id = 148065, name = 'Veeshan\'s Earring of the Hero' },
  { id = 148066, name = 'Earring of the Dojo' },
  { id = 148067, name = 'Tagar\'s Lost Necklace' },
  { id = 148068, name = 'Brown Belt of the Dragonbrood' },
  { id = 148069, name = 'Reinforced Belt of the Brood' },
  { id = 148070, name = 'Ring of the Everlasting' },
  { id = 148071, name = 'Dreadnought\'s Ring of Grit' },
  { id = 148072, name = 'Polished Mask of Insanity' },
  { id = 148073, name = 'Faceguard of the Pantheon' },
  { id = 148074, name = 'Dagarn\'s Cloak of Reflection' },
  { id = 148075, name = 'Cloak of Deadly Dreams' },
  { id = 148076, name = 'Cloudburst, Fist of Eashen' },
  { id = 148077, name = 'Corruption, Ikatiar\'s End' },
  { id = 148078, name = 'Singed Shoulderguards' },
  { id = 148079, name = 'Nevederia\'s Treasured Pauldrons' },
  { id = 148080, name = 'Sublimating Focus' },
  { id = 148081, name = 'Shield of Primal Fusion' },
  { id = 148082, name = 'Koi\'s Shield of Soothing Waves' },
  { id = 148083, name = 'Necklace of Forgotten Mistakes' },
  { id = 148084, name = 'Divinity, Sword of the Protectorate' },
  { id = 148085, name = 'Trinket of the Valiant' },
  { id = 148086, name = 'Trinket of the Aggressor' },
  { id = 148087, name = 'Veeshan\'s Seal of the Silent' },
  { id = 148089, name = 'Veeshan\'s Seal of the Professional' },
  { id = 148090, name = 'Veeshan\'s Seal of the Twinhealer' },
  { id = 148091, name = 'Earring of Grit' },
  { id = 148094, name = 'Tunic of the Misguided' },
  { id = 148096, name = 'Autumn, Blade of Command' },
  { id = 148097, name = 'Orb of Acceleration' },
  { id = 148098, name = 'Orb of the Everliving' },
  { id = 148099, name = 'Ultimate Vulak\'s Scale' },
  { id = 148100, name = 'Zek\'s Seal of the Cryomancer' },
  { id = 148101, name = 'Zek\'s Seal of the Pyromancer' },
  { id = 148102, name = 'Zek\'s Seal of the Arcanist' },
  { id = 148103, name = 'Zek\'s Seal of the Assassin' },
  { id = 148104, name = 'Zek\'s Seal of the Plagued' },
  { id = 148105, name = 'Zek\'s Seal of the Stargazer' },
  { id = 148106, name = 'Zek\'s Seal of the Healer' },
  { id = 148107, name = 'Zek\'s Seal of the Benevolent' },
  { id = 148108, name = 'Zek\'s Seal of the Aggressor' },
  { id = 148109, name = 'Zek\'s Seal of the Expedient' },
  { id = 148110, name = 'Zek\'s Seal of the Oracle' },
  { id = 148111, name = 'Zek\'s Seal of the Nimble' },
  { id = 148112, name = 'Zek\'s Seal of the Juggernaut' },
  { id = 148113, name = 'Zek\'s Seal of the Ferocious' },
  { id = 148114, name = 'Zek\'s Seal of the Wild' },
  { id = 148115, name = 'Zek\'s Seal of the Champion' },
  { id = 148116, name = 'Zek\'s Seal of the Frenzied' },
  { id = 148117, name = 'Zek\'s Seal of the Silent' },
  { id = 148118, name = 'Zek\'s Seal of the Professional' },
  { id = 148119, name = 'Zek\'s Seal of the Twinhealer' },
  { id = 148123, name = 'Ultimate Kael Artifact (Common)' },
  { id = 148124, name = 'Ultimate Kael Artifact (Rare)' },
  { id = 148165, name = 'Ultimate Kael Completion Pass (Complete)' },
  { id = 148188, name = 'Ultimate Primal Warsword' },
  { id = 148189, name = 'Ultimate Primal Broadsword' },
  { id = 148190, name = 'Ultimate Primal Bow' },
  { id = 148191, name = 'Ultimate Primal Dagger' },
  { id = 148193, name = 'Ultimate Primal Warhammer' },
  { id = 148195, name = 'Ultimate Primal Fist' },
  { id = 148197, name = 'Ultimate Primal Battleaxe' },
  { id = 148198, name = 'Spell: Shroud of Deathwhisper I' },
  { id = 148214, name = 'Spell: Spear of Gloom I' },
  { id = 148215, name = 'Spell: Curse of Dread I' },
  { id = 148216, name = 'Spell: Dread Inferno I' },
  { id = 148217, name = 'Spell: Touch of Obliteration I' },
  { id = 148218, name = 'Spell: Core Fusion I' },
  { id = 148219, name = 'Spell: Lance of Elements I' },
  { id = 148220, name = 'Spell: Molten Rain I' },
  { id = 148221, name = 'Spell: Void Strike I' },
  { id = 148222, name = 'Spell: Volcanic Earth I' },
  { id = 148223, name = 'Spell: Detention I' },
  { id = 148224, name = 'Spell: Triple Rashomon I' },
  { id = 148225, name = 'Spell: Elemental Insanity I' },
  { id = 148226, name = 'Spell: Dictate Time I' },
  { id = 148227, name = 'Spell: Reptilian Inversion I' },
  { id = 148228, name = 'Spell: Treant Regeneration I' },
  { id = 148229, name = 'Spell: Chlorolust I' },
  { id = 148230, name = 'Spell: Impound I' },
  { id = 148231, name = 'Spell: Winterfell Mending I' },
  { id = 148232, name = 'Spell: Northern Serenity I' },
  { id = 148233, name = 'Spell: Turgur\'s Blood I' },
  { id = 148234, name = 'Spell: Fury of the Pantheon I' },
  { id = 148235, name = 'Spell: Light of Divinity I' },
  { id = 148236, name = 'Spell: Wave of Divinity I' },
  { id = 148237, name = 'Spell: Fiery Requiem I' },
  { id = 148238, name = 'Spell: Harmony of Kerafyrm I' },
  { id = 148239, name = 'Spell: Nocturn I' },
  { id = 148240, name = 'Spell: Chaotic Disempowerment I' },
  { id = 148241, name = 'Spell: Uplifting Light I' },
  { id = 148242, name = 'Spell: Tomb Armor I' },
  { id = 148243, name = 'Spell: Elixir of the Patriarchy I' },
  { id = 148244, name = 'Spell: Instant Denial I' },
  { id = 148245, name = 'Spell: Festerwound I' },
  { id = 148246, name = 'Spell: Growlmend I' },
  { id = 148247, name = 'Spell: Frozen Claw I' },
  { id = 148248, name = 'Spell: Color Vortex I' },
  { id = 148250, name = 'Sleeper\'s Seal of the Pyromancer' },
  { id = 148251, name = 'Sleeper\'s Seal of the Arcanist' },
  { id = 148252, name = 'Sleeper\'s Seal of the Assassin' },
  { id = 148253, name = 'Sleeper\'s Seal of the Plagued' },
  { id = 148254, name = 'Sleeper\'s Seal of the Stargazer' },
  { id = 148255, name = 'Sleeper\'s Seal of the Healer' },
  { id = 148256, name = 'Sleeper\'s Seal of the Benevolent' },
  { id = 148257, name = 'Sleeper\'s Seal of the Aggressor' },
  { id = 148258, name = 'Sleeper\'s Seal of the Expedient' },
  { id = 148259, name = 'Sleeper\'s Seal of the Oracle' },
  { id = 148260, name = 'Sleeper\'s Seal of the Nimble' },
  { id = 148261, name = 'Sleeper\'s Seal of the Juggernaut' },
  { id = 148262, name = 'Sleeper\'s Seal of the Ferocious' },
  { id = 148263, name = 'Sleeper\'s Seal of the Wild' },
  { id = 148264, name = 'Sleeper\'s Seal of the Champion' },
  { id = 148265, name = 'Sleeper\'s Seal of the Frenzied' },
  { id = 148266, name = 'Sleeper\'s Seal of the Silent' },
  { id = 148267, name = 'Sleeper\'s Seal of the Professional' },
  { id = 148268, name = 'Sleeper\'s Seal of the Twinhealer' },
  { id = 148269, name = 'Sleeper\'s Seal of the Cryomancer' },
  { id = 148270, name = 'Kerafyrm Seal Artifact' },
  { id = 148271, name = 'Avatar: Bond of Tears I' },
  { id = 148272, name = 'Avatar: Touch of Obliteration I' },
  { id = 148273, name = 'Avatar: Molten Rain I' },
  { id = 148274, name = 'Avatar: Void Strike I' },
  { id = 148275, name = 'Avatar: Triple Rashomon I' },
  { id = 148276, name = 'Avatar: Reptilian Inversion I' },
  { id = 148277, name = 'Avatar: Northern Serenity I' },
  { id = 148278, name = 'Avatar: Light of Divinity I' },
  { id = 148279, name = 'Avatar: Nocturn I' },
  { id = 148280, name = 'Avatar: Tomb Armor I' },
  { id = 148281, name = 'Avatar: Festerwound I' },
  { id = 148282, name = 'Spell: Bond of Tears I' },
  { id = 148283, name = 'Ultimate Sleeper\'s 1H Stone' },
  { id = 148284, name = 'Ultimate Sleeper\'s Fist Stone' },
  { id = 148285, name = 'Ultimate Sleeper\'s 2H Stone' },
  { id = 148286, name = 'Ultimate Sleeper\'s Bowmaster Stone' },
  { id = 148287, name = 'Tomb Defiler\'s Ring' },
  { id = 148288, name = 'Tomb Guardian\'s Earring' },
  { id = 148289, name = 'Prismatic Velium Helmet' },
  { id = 148290, name = 'Prismatic Velium Breastplate' },
  { id = 148291, name = 'Prismatic Velium Vambraces' },
  { id = 148292, name = 'Prismatic Velium Legplates' },
  { id = 148293, name = 'Prismatic Velium Plate Boots' },
  { id = 148294, name = 'Prismatic Velium Bracer' },
  { id = 148295, name = 'Prismatic Velium Gauntlets' },
  { id = 148296, name = 'Prismatic Velium Cowl' },
  { id = 148297, name = 'Prismatic Velium Tunic' },
  { id = 148298, name = 'Prismatic Velium Armguards' },
  { id = 148299, name = 'Prismatic Velium Shinguards' },
  { id = 148300, name = 'Prismatic Velium Boots' },
  { id = 148301, name = 'Prismatic Velium Handguards' },
  { id = 148302, name = 'Prismatic Velium Wristguards' },
  { id = 148303, name = 'Prismatic Velium Cap' },
  { id = 148304, name = 'Prismatic Velium Robe' },
  { id = 148305, name = 'Prismatic Velium Sleeves' },
  { id = 148306, name = 'Prismatic Velium Slacks' },
  { id = 148307, name = 'Prismatic Velium Slippers' },
  { id = 148308, name = 'Prismatic Velium Bracelet' },
  { id = 148309, name = 'Prismatic Velium Gloves' },
  { id = 148310, name = 'Glacierbane, Shield of the First Brood' },
  { id = 148311, name = 'Ultimate Scepter of Destruction' },
  { id = 148312, name = 'Ultimate Staff of the Elder Claws' },
  { id = 148313, name = 'Ultimate Mask of Tinkering' },
  { id = 148729, name = 'Spell: Agile Minion I' },
  { id = 148736, name = 'Spell: Vigor of the Gladestrider I' },
  { id = 148737, name = 'Spell: Sylvan Remedy I' },
  { id = 149860, name = 'Ultimate Kerafyrm\'s Scale' },
  { id = 150053, name = 'Beating Heart of Flame' },
  { id = 150054, name = 'Essence of Ultimate Stamina' },
  { id = 150055, name = 'Essence of Ultimate Agility' },
  { id = 150056, name = 'Essence of Ultimate Intelligence' },
  { id = 150057, name = 'Essence of Ultimate Dexterity' },
  { id = 150058, name = 'Essence of Ultimate Strength' },
  { id = 150059, name = 'Bottled Soul of the Guk Lord' },
  { id = 150060, name = 'Transmutation Recipe: Ghoul Lord Summoning Focus' },
  { id = 150061, name = 'Transmutation Recipe: Bubbling Jar of Immolation' },
  { id = 150062, name = 'Transmutation Recipe: Stone of Ultimate Stamina' },
  { id = 150063, name = 'Transmutation Recipe: Stone of Ultimate Agility' },
  { id = 150064, name = 'Transmutation Recipe: Stone of Ultimate Intelligence' },
  { id = 150065, name = 'Transmutation Recipe: Stone of Ultimate Dexterity' },
  { id = 150066, name = 'Transmutation Recipe: Stone of Ultimate Strength' },
  { id = 150074, name = 'Transmutation Recipe: Ultimate Token to Legendary Mold' },
  { id = 150075, name = 'Transmutation Recipe: Legendary Mold to Ultimate Token' },
  { id = 150076, name = 'Transmutation Recipe: Goblin Duplicator XL' },
  { id = 150077, name = 'Transmutation Recipe: Trakanon\'s Annihilator' },
  { id = 150135, name = 'Transmutation Recipe: Goblin Hate Generator XTZ' },
  { id = 150137, name = 'Essence of Ultimate Anger' },
}

local AVATAR_LOOT = {
  { id = 3889, name = 'Mirror of Self-loathing' },
  { id = 10012, name = 'Black Pearl' },
  { id = 20080, name = 'Nimbus of Ky`Shien' },
  { id = 40619, name = 'Nimbus of the Plaguebringer' },
  { id = 40620, name = 'Nimbus of the Burning Prince' },
  { id = 40621, name = 'Nimbus of the Storm Lord' },
  { id = 40628, name = 'Familiar of Lord Nagafen' },
  { id = 40629, name = 'Familiar of Hulcror' },
  { id = 40630, name = 'Familiar of the Girplan Guardian' },
  { id = 40631, name = 'Familiar of Lightningcaller Vhalek' },
  { id = 40657, name = 'Nimbus of the Rain Keeper' },
  { id = 40658, name = 'Nimbus of Growth' },
  { id = 40659, name = 'Nimbus of the Faceless' },
  { id = 40660, name = 'Nimbus of the Lover' },
  { id = 40671, name = 'Familiar of Lady Vox' },
  { id = 40687, name = 'Nimbus of the Wisp' },
  { id = 40688, name = 'Nimbus of the Tranquil' },
  { id = 40689, name = 'Nimbus of the Jester' },
  { id = 40690, name = 'Nimbus of the Air Queen' },
  { id = 40691, name = 'Nimbus of the Ocean Lord' },
  { id = 40716, name = 'Nimbus of the Crystal Gelidran' },
  { id = 40717, name = 'Nimbus of the Frozen Gelidran' },
  { id = 40718, name = 'Nimbus of the Molten Pyrilen' },
  { id = 40719, name = 'Nimbus of the Burning Pyrilen' },
  { id = 40720, name = 'Nimbus of the Riftseeker' },
  { id = 40730, name = 'Familiar of Warden Hanvar' },
  { id = 40731, name = 'Familiar of King Gelaqua' },
  { id = 40748, name = 'Nimbus of Discordant Energy' },
  { id = 40749, name = 'Nimbus of Discordant Chains' },
  { id = 40750, name = 'Nimbus of Discordant Spines' },
  { id = 40751, name = 'Nimbus of Mata Muram' },
  { id = 40752, name = 'Nimbus of Discordant Souls' },
  { id = 40762, name = 'Familiar of Trakanon' },
  { id = 40764, name = 'Familiar of the Armored Worg' },
  { id = 40781, name = 'Nimbus of the Rumbling Earth' },
  { id = 40782, name = 'Nimbus of the Howling Wind' },
  { id = 40783, name = 'Nimbus of the Void' },
  { id = 40784, name = 'Nimbus of Burning Steps' },
  { id = 40785, name = 'Nimbus of Rushing Water' },
  { id = 43974, name = 'Nimbus of the Inquisition' },
  { id = 43976, name = 'Nimbus of the Dead' },
  { id = 43977, name = 'Nimbus of Daylight' },
  { id = 43978, name = 'Nimbus of Midnight' },
  { id = 48972, name = 'Nimbus of the Green Thumb' },
  { id = 48974, name = 'Nimbus of the Dazed' },
  { id = 48975, name = 'Nimbus of the Confused' },
  { id = 48987, name = 'Broken Heart Nimbus' },
  { id = 50490, name = 'Spinefist Nimbus' },
  { id = 50491, name = 'Crown of Roses Nimbus' },
  { id = 50855, name = 'Nimbus of Runes' },
  { id = 50856, name = 'Bladestorm Nimbus' },
  { id = 50857, name = 'Nimbus of the Gambler' },
  { id = 50858, name = 'Nimbus of Dust Storm' },
  { id = 52194, name = 'Dreamcatcher Nimbus' },
  { id = 52195, name = 'Nightmare Nimbus' },
  { id = 53358, name = 'Cherry Blossom Nimbus' },
  { id = 53752, name = 'Nimbus of the Tempest' },
  { id = 53753, name = 'Nimbus of the Ocean' },
  { id = 54915, name = 'Nimbus of Fire and Ice' },
  { id = 54918, name = 'Crystalline Shield Nimbus' },
  { id = 54984, name = 'Death and Decay Nimbus' },
  { id = 54985, name = 'Path of Fire Nimbus' },
  { id = 56060, name = 'Crown of Feathers Nimbus' },
  { id = 57379, name = 'Nimbus of Holly' },
  { id = 57380, name = 'Fruitcake Nimbus' },
  { id = 57381, name = 'Nimbus of Frost' },
  { id = 57382, name = 'Party Popper Nimbus' },
  { id = 57474, name = 'Crocus Nimbus' },
  { id = 57529, name = 'Rose Petal Nimbus' },
  { id = 57530, name = 'Share the Love Nimbus' },
  { id = 57531, name = 'Share the Pain Nimbus' },
  { id = 57601, name = 'Erollisi Day Nimbus Package' },
  { id = 60946, name = 'Crown of Fire Nimbus' },
  { id = 60947, name = 'Path of Ice Nimbus' },
  { id = 61035, name = 'Butterfly Nimbus' },
  { id = 61955, name = 'Fae Spirit Nimbus' },
  { id = 62769, name = 'Fireworks Nimbus' },
  { id = 64708, name = 'Arachnophobia Nimbus' },
  { id = 65589, name = 'Nightshade' },
  { id = 147496, name = 'Ultimate Token' },
  { id = 148363, name = 'Avatar\'s 1H Stone I' },
  { id = 148364, name = 'Avatar\'s Fist Stone I' },
  { id = 148365, name = 'Avatar\'s 2H Stone I' },
  { id = 148366, name = 'Avatar\'s Bowmaster Stone I' },
  { id = 148368, name = 'Ultimate Avatar Token' },
  { id = 148369, name = 'Ultimate Avatar Plate Mold (Breastplate)' },
  { id = 148370, name = 'Ultimate Avatar Plate Mold (Helmet)' },
  { id = 148371, name = 'Ultimate Avatar Plate Mold (Vambraces)' },
  { id = 148372, name = 'Ultimate Avatar Plate Mold (Boots)' },
  { id = 148373, name = 'Ultimate Avatar Plate Mold (Leggings)' },
  { id = 148374, name = 'Ultimate Avatar Chain Mold (Tunic)' },
  { id = 148375, name = 'Ultimate Avatar Chain Mold (Coif)' },
  { id = 148376, name = 'Ultimate Avatar Chain Mold (Vambraces)' },
  { id = 148377, name = 'Ultimate Avatar Chain Mold (Boots)' },
  { id = 148378, name = 'Ultimate Avatar Chain Mold (Shinguards)' },
  { id = 148379, name = 'Ultimate Avatar Leather Pattern (Tunic)' },
  { id = 148380, name = 'Ultimate Avatar Leather Pattern (Cap)' },
  { id = 148381, name = 'Ultimate Avatar Leather Pattern (Armguards)' },
  { id = 148382, name = 'Ultimate Avatar Leather Pattern (Boots)' },
  { id = 148383, name = 'Ultimate Avatar Leather Pattern (Leggings)' },
  { id = 148384, name = 'Ultimate Avatar Cloth Pattern (Robe)' },
  { id = 148385, name = 'Ultimate Avatar Cloth Pattern (Cap)' },
  { id = 148386, name = 'Ultimate Avatar Cloth Pattern (Sleeves)' },
  { id = 148387, name = 'Ultimate Avatar Cloth Pattern (Sandals)' },
  { id = 148388, name = 'Ultimate Avatar Cloth Pattern (Slacks)' },
  { id = 148389, name = 'Ultimate Avatar Plate Mold (Bracer)' },
  { id = 148390, name = 'Ultimate Avatar Chain Mold (Bracer)' },
  { id = 148391, name = 'Ultimate Avatar Leather Pattern (Wristguard)' },
  { id = 148392, name = 'Ultimate Avatar Cloth Pattern (Bracelet)' },
  { id = 148446, name = 'Ultimate Avatar Chain Mold (Gloves)' },
  { id = 148508, name = 'Spell: Drape of Temerity I' },
  { id = 148509, name = 'Spell: Hateful Instigation I' },
  { id = 148510, name = 'Spell: Underworld Blood I' },
  { id = 148511, name = 'Spell: Netherworld Venom I' },
  { id = 148512, name = 'Spell: Surging Infection I' },
  { id = 148513, name = 'Spell: Paralyzing Shock I' },
  { id = 148514, name = 'Spell: Salve of Terris I' },
  { id = 148515, name = 'Spell: Magmatic Reverberation I' },
  { id = 148516, name = 'Spell: Coronal Burst I' },
  { id = 148517, name = 'Spell: Elemental Rejuvenation I' },
  { id = 148518, name = 'Spell: Moonshade I' },
  { id = 148519, name = 'Spell: Fling I' },
  { id = 148521, name = 'Spell: Atomize I' },
  { id = 148522, name = 'Spell: Almighty Push I' },
  { id = 148523, name = 'Spell: Arcane Shackles I' },
  { id = 148524, name = 'Spell: Glacial Crash I' },
  { id = 148525, name = 'Spell: Temporalis I' },
  { id = 148526, name = 'Spell: North Rend I' },
  { id = 148527, name = 'Spell: Ssraeshzan Fever I' },
  { id = 148528, name = 'Spell: Viral Cascade I' },
  { id = 148529, name = 'Spell: Totemic Sundering I' },
  { id = 148530, name = 'Spell: Enlistment I' },
  { id = 148531, name = 'Spell: Heavensward I' },
  { id = 148532, name = 'Spell: Holy Contravention I' },
  { id = 148533, name = 'Spell: Ediction I' },
  { id = 148534, name = 'Spell: Jungle Rot I' },
  { id = 148536, name = 'Skill: Exploding Palm I' },
  { id = 148537, name = 'Skill: Shadowslice I' },
  { id = 148538, name = 'Spell: Bolt of Nature I' },
  { id = 148539, name = 'Spell: Frigid Winds I' },
  { id = 148540, name = 'Spell: Erupting Earth I' },
  { id = 148541, name = 'Spell: Wreckless Blade I' },
  { id = 148542, name = 'Skill: Arc of Death I' },
  { id = 148543, name = 'Skill: Veteran Tactics I' },
  { id = 148544, name = 'Skill: Battle Frenzy I' },
  { id = 148545, name = 'Ultimate Avatar Plate Mold (Gauntlets)' },
  { id = 148546, name = 'Ultimate Avatar Leather Pattern (Gloves)' },
  { id = 148547, name = 'Ultimate Avatar Cloth Pattern (Gloves)' },
  { id = 148548, name = 'Avatar Stone I' },
  { id = 148549, name = 'Spell: Avatar Rune I' },
  { id = 148550, name = 'Skill: Tone of the Avatar I' },
  { id = 148551, name = 'Stone of Jordan' },
  { id = 148552, name = 'Elder Titan\'s Band' },
  { id = 148553, name = 'Archon\'s Ring of Invocation' },
  { id = 148554, name = 'Terminus Band' },
  { id = 148555, name = 'Dreadlord\'s Hoop' },
  { id = 148556, name = 'Mentalist\'s Studded Earring' },
  { id = 148557, name = 'Earring of Tragedy' },
  { id = 148558, name = 'Earring of Ascendency' },
  { id = 148559, name = 'Blood-Splattered Visor' },
  { id = 148561, name = 'String of Elf Ears' },
  { id = 148562, name = 'Teir\'dal Rosary' },
  { id = 148563, name = 'Mayong\'s Head' },
  { id = 148564, name = 'Fippy\'s Head' },
  { id = 148565, name = 'Goblin King\'s Head' },
  { id = 148567, name = 'High Warlord\'s Ceremonial Cloak' },
  { id = 148568, name = 'Arch-Tactician\'s Drape' },
  { id = 148569, name = 'Cloak of Infinite Wisdom' },
  { id = 148577, name = 'Pauldrons of Mastery' },
  { id = 148578, name = 'Heartless Shoulderpads' },
  { id = 148579, name = 'Plated Belt of Tactics' },
  { id = 148580, name = 'Flowing Black Leather Sash' },
  { id = 148581, name = 'Belt of the Cool Breeze' },
  { id = 148588, name = 'Spell: Reptilian Inversion II' },
  { id = 148589, name = 'Primal Weapon Rk. II Mold' },
  { id = 148590, name = 'Spell: Fast Forward I' },
  { id = 148591, name = 'Spell: Ethereal Sleet I' },
  { id = 148592, name = 'Spell: Garou I' },
  { id = 148604, name = 'Ultimate Avatar Armor Upgrade Token' },
  { id = 148605, name = 'An Earthen Soulstone' },
  { id = 148606, name = 'Coalesced Avatar Energy' },
  { id = 148608, name = 'Primal Weapon Rk. III Mold' },
  { id = 148616, name = 'Spell: Boon of the Summoner I' },
  { id = 148617, name = 'Spell: Ultimate Harm Touch I' },
  { id = 148618, name = 'Spell: Shroud of Doomgaze I' },
  { id = 148619, name = 'Spell: Spear of Totality I' },
  { id = 148620, name = 'Spell: Touch of Midnight I' },
  { id = 148621, name = 'Spell: Spectral Possession I' },
  { id = 148622, name = 'Spell: Curse of Spite I' },
  { id = 148623, name = 'Spell: Mind Flay I' },
  { id = 148624, name = 'Spell: Magma Deluge I' },
  { id = 148625, name = 'Spell: Planetary Annihilation I' },
  { id = 148626, name = 'Spell: Evasive Minion I' },
  { id = 148627, name = 'Spell: Convective Skin I' },
  { id = 148628, name = 'Spell: Elemental Overdrive I' },
  { id = 148629, name = 'Spell: Summon Meteor Shard I' },
  { id = 148630, name = 'Spell: Servitude I' },
  { id = 148631, name = 'Spell: Rune of Shinra I' },
  { id = 148632, name = 'Spell: Natureburst I' },
  { id = 148633, name = 'Spell: Woodland Rejuvination I' },
  { id = 148634, name = 'Spell: Blessing of the Void I' },
  { id = 148635, name = 'Spell: Legacy of Steelvine I' },
  { id = 148636, name = 'Spell: Eternal Companion I' },
  { id = 148637, name = 'Spell: Tribal Mending I' },
  { id = 148638, name = 'Spell: Torpor of Halas I' },
  { id = 148639, name = 'Spell: Light of Transcendency I' },
  { id = 148640, name = 'Spell: Wave of Transcendency I' },
  { id = 148641, name = 'Spell: Exonerate Undead I' },
  { id = 148642, name = 'Spell: Requiem of Cinders I' },
  { id = 148643, name = 'Spell: Melodic Crippling I' },
  { id = 148644, name = 'Spell: Chorus of Solace I' },
  { id = 148645, name = 'Spell: Exalting Light I' },
  { id = 148646, name = 'Spell: Underfoot Armor I' },
  { id = 148647, name = 'Spell: Elixir of the Sanctification I' },
  { id = 148648, name = 'Spell: Denial of the Demigod I' },
  { id = 148649, name = 'Spell: Blistering Malady I' },
  { id = 148650, name = 'Spell: Roarmend I' },
  { id = 148651, name = 'Avatar Stone II' },
  { id = 148652, name = 'Avatar: Netherworld Venom I' },
  { id = 148653, name = 'Avatar: Paralyzing Shock I' },
  { id = 148654, name = 'Avatar: Arcane Shackles I' },
  { id = 148655, name = 'Avatar: Coronal Burst I' },
  { id = 148656, name = 'Avatar: Garou I' },
  { id = 148657, name = 'Avatar: Temporalis I' },
  { id = 148658, name = 'Avatar: Totemic Sundering I' },
  { id = 148659, name = 'Avatar: Bolt of Nature I' },
  { id = 148696, name = 'Avatar\'s 1H Stone II' },
  { id = 148697, name = 'Avatar\'s Fist Stone II' },
  { id = 148698, name = 'Avatar\'s 2H Stone II' },
  { id = 148699, name = 'Avatar\'s Bowmaster Stone II' },
  { id = 148700, name = 'Avatar\'s Healer Stone I' },
  { id = 148701, name = 'Underfoot Band of Stone' },
  { id = 148702, name = 'Ring of the Templebound' },
  { id = 148703, name = 'Basalt Band of Aggression' },
  { id = 148704, name = 'Ancient Gargoyle\'s Earring' },
  { id = 148705, name = 'Earclasp of the Pit' },
  { id = 148706, name = 'Excavator\'s Hoop' },
  { id = 148707, name = 'Shimmering Paineel Earring' },
  { id = 148708, name = 'Faceguard of Encroachment' },
  { id = 148709, name = 'Loam-Infused Veil' },
  { id = 148710, name = 'Choker of Rotten Leaves' },
  { id = 148711, name = 'Bejeweled Necklace of Animosity' },
  { id = 148712, name = 'Fired Golem Cloak' },
  { id = 148713, name = 'Pitlord\'s Drape' },
  { id = 148714, name = 'Cloak of the Ancient Library' },
  { id = 148715, name = 'Spaulders of the Ruins' },
  { id = 148716, name = 'Loam-Covered Spiked Shoulderpads' },
  { id = 148717, name = 'Hardened Loam Buckle' },
  { id = 148718, name = 'Loam-Engraved Ornate Belt' },
  { id = 148719, name = 'Damp Silky Belt' },
  { id = 148720, name = 'Spell: Sonata of Slavery I' },
  { id = 148725, name = 'Faceguard of the Mechanic' },
  { id = 148726, name = 'Mask of the Dedicated Protector' },
  { id = 148730, name = 'Spell: Wily Minion I' },
  { id = 148731, name = 'Orb of Plastic Surgery' },
  { id = 148738, name = 'Spell: Wasteland Mending I' },
  { id = 148739, name = 'Spell: Vitality of the Gladestrider I' },
  { id = 148741, name = 'Spell: Drape of Temerity II' },
  { id = 148742, name = 'Spell: Hateful Instigation II' },
  { id = 148743, name = 'Spell: Underworld Blood II' },
  { id = 148744, name = 'Spell: Reaper Strike I' },
  { id = 148745, name = 'Spell: Netherworld Venom II' },
  { id = 148746, name = 'Spell: Surging Infection II' },
  { id = 148747, name = 'Spell: Paralyzing Shock II' },
  { id = 148748, name = 'Spell: Servant of Blood I' },
  { id = 148749, name = 'Spell: Atomize II' },
  { id = 148750, name = 'Spell: Almighty Push II' },
  { id = 148751, name = 'Spell: Arcane Shackles II' },
  { id = 148752, name = 'Spell: Magmatic Reverberation II' },
  { id = 148753, name = 'Spell: Coronal Burst II' },
  { id = 148754, name = 'Spell: Summon Core of Absolute Zero I' },
  { id = 148755, name = 'Spell: Elemental Insanity II' },
  { id = 148756, name = 'Spell: Servitude II' },
  { id = 148757, name = 'Spell: Garou II' },
  { id = 148758, name = 'Spell: Reptilian Inversion III' },
  { id = 148759, name = 'Spell: Regrowth of the Avatar I' },
  { id = 148760, name = 'Spell: Northern Serenity II' },
  { id = 148761, name = 'Spell: Turgur\'s Blood II' },
  { id = 148762, name = 'Spell: Enlistment II' },
  { id = 148763, name = 'Spell: Heavensward II' },
  { id = 148764, name = 'Spell: Fury of the Pantheon II' },
  { id = 148765, name = 'Spell: Desperate Word I' },
  { id = 148766, name = 'Spell: Jungle Rot II' },
  { id = 148767, name = 'Spell: Swamp Claw I' },
  { id = 148768, name = 'Spell: Thunderhead  I' },
  { id = 148769, name = 'Spell: Death March I' },
  { id = 148770, name = 'Spell: Avatar Rune II' },
  { id = 148771, name = 'Spell: Ultimate Haste I' },
  { id = 148772, name = 'Skill: Exploding Palm II' },
  { id = 148773, name = 'Skill: Shadowslice II' },
  { id = 148774, name = 'Skill: Arc of Death II' },
  { id = 148775, name = 'Spell: Psalm of the Avatar I' },
  { id = 148804, name = 'Spell: Spiritual Lucidity I' },
  { id = 148805, name = 'Spell: Predator I' },
  { id = 148806, name = 'Primal Weapon Rk. IV Mold' },
  { id = 148807, name = 'Frozen Avatar Energy' },
  { id = 148808, name = 'Avatar\'s 1H Stone III' },
  { id = 148809, name = 'Avatar\'s 2H Stone III' },
  { id = 148810, name = 'Avatar\'s Fist Stone III' },
  { id = 148811, name = 'Avatar\'s Bowmaster Stone III' },
  { id = 148812, name = 'Avatar\'s Healer Stone II' },
  { id = 148822, name = 'Amelioration Stone (Avatar)' },
  { id = 148823, name = 'Dead Man\'s Stone (Avatar)' },
  { id = 148824, name = 'Cascade Stone (Avatar)' },
  { id = 148825, name = 'The Master\'s Stone (Avatar)' },
  { id = 148826, name = 'Coil Stone (Avatar)' },
  { id = 148827, name = 'The Hypnotic Stone (Avatar)' },
  { id = 148828, name = 'Stone of Supplication (Avatar)' },
  { id = 148829, name = 'Harbinger\'s Corona Stone (Avatar)' },
  { id = 148830, name = 'Stone of the Hero (Avatar)' },
  { id = 148831, name = 'Tagar\'s Lost Stone (Avatar)' },
  { id = 148832, name = 'Aggressor\'s Stone (Avatar)' },
  { id = 148833, name = 'Sublimating Stone (Avatar)' },
  { id = 148840, name = 'Sharpened Tower Stone (1H)' },
  { id = 148841, name = 'Sharpened Tower Stone (2H)' },
  { id = 148842, name = 'Havoc, The Bringer of Ruin' },
  { id = 148843, name = 'Blitzkrieg, Barricade of the Juggernaut' },
  { id = 148844, name = 'Reckoner, Shield of Rapture' },
  { id = 148845, name = 'Visage of Forbearance' },
  { id = 148846, name = 'Avatar Stone III' },
  { id = 148847, name = 'Ring of the Cursed Tower' },
  { id = 148848, name = 'Band of Dark Secrets' },
  { id = 148849, name = 'Wasteland Hoop' },
  { id = 148850, name = 'Earring of the Pretender' },
  { id = 148851, name = 'The Dancer\'s Earclasp' },
  { id = 148852, name = 'Wintery Earring' },
  { id = 148853, name = 'Frost Giant\'s Earstud' },
  { id = 148854, name = 'Twice-Polished Kromzek Faceguard' },
  { id = 148855, name = 'Veil of Emeralds' },
  { id = 148856, name = 'Gorget of the Advisor' },
  { id = 148857, name = 'Necklace of Fangs' },
  { id = 148858, name = 'Mayong\'s Ceremonial Cloak' },
  { id = 148859, name = 'Slimy Cloak of the Eternal' },
  { id = 148860, name = 'Zombie-Skin Drape' },
  { id = 148861, name = 'Pauldrons of the Barbarian' },
  { id = 148862, name = 'Shoulderguards of the Serene' },
  { id = 148863, name = 'Clasp of Tactical Advantage' },
  { id = 148864, name = 'Belt of Artistic Destruction' },
  { id = 148865, name = 'Blood-Drenched Cinch' },
  { id = 148872, name = 'Ultimate Primal Defender\'s Sword (Ascended)' },
  { id = 148873, name = 'Ultimate Primal Warsword (Ascended)' },
  { id = 148874, name = 'Ultimate Primal Broadsword (Ascended)' },
  { id = 148875, name = 'Ultimate Primal Bow (Ascended)' },
  { id = 148876, name = 'Ultimate Primal Dagger (Ascended)' },
  { id = 148877, name = 'Ultimate Primal Fist (Ascended)' },
  { id = 148878, name = 'Ultimate Primal Warhammer (Ascended)' },
  { id = 148879, name = 'Ultimate Primal Battleaxe (Ascended)' },
  { id = 148882, name = 'Ultimate Avatar Helmet (Ascended)' },
  { id = 148883, name = 'Ultimate Avatar Breastplate (Ascended)' },
  { id = 148884, name = 'Ultimate Avatar Vambraces (Ascended)' },
  { id = 148885, name = 'Ultimate Avatar Plate Boots (Ascended)' },
  { id = 148886, name = 'Ultimate Avatar Legplates (Ascended)' },
  { id = 148887, name = 'Ultimate Avatar Bracer (Ascended)' },
  { id = 148888, name = 'Ultimate Avatar Gauntlets (Ascended)' },
  { id = 148889, name = 'Ultimate Avatar Coif (Ascended)' },
  { id = 148890, name = 'Ultimate Avatar Chain Tunic (Ascended)' },
  { id = 148891, name = 'Ultimate Avatar Chain Vambraces (Ascended)' },
  { id = 148892, name = 'Ultimate Avatar Chain Boots (Ascended)' },
  { id = 148893, name = 'Ultimate Avatar Shinguards (Ascended)' },
  { id = 148894, name = 'Ultimate Avatar Chain Bracer (Ascended)' },
  { id = 148895, name = 'Ultimate Avatar Chain Gloves (Ascended)' },
  { id = 148896, name = 'Ultimate Avatar Leather Cap (Ascended)' },
  { id = 148897, name = 'Ultimate Avatar Chestwraps (Ascended)' },
  { id = 148898, name = 'Ultimate Avatar Leather Armguards (Ascended)' },
  { id = 148899, name = 'Ultimate Avatar Leather Boots (Ascended)' },
  { id = 148900, name = 'Ultimate Avatar Legwraps (Ascended)' },
  { id = 148901, name = 'Ultimate Avatar Leather Bracer (Ascended)' },
  { id = 148902, name = 'Ultimate Avatar Leather Gloves (Ascended)' },
  { id = 148903, name = 'Ultimate Avatar Cap (Ascended)' },
  { id = 148904, name = 'Ultimate Avatar Robe (Ascended)' },
  { id = 148905, name = 'Ultimate Avatar Sleeves (Ascended)' },
  { id = 148906, name = 'Ultimate Avatar Slippers (Ascended)' },
  { id = 148907, name = 'Ultimate Avatar Slacks (Ascended)' },
  { id = 148908, name = 'Ultimate Avatar Bracelet (Ascended)' },
  { id = 148909, name = 'Ultimate Avatar Gloves (Ascended)' },
  { id = 148910, name = 'Avatar Stone IV' },
  { id = 148913, name = 'Avatar: Touch Of Midnight II' },
  { id = 148914, name = 'Avatar: Dread Inferno II' },
  { id = 148915, name = 'Avatar: Magma Deluge II' },
  { id = 148916, name = 'Avatar: Magmatic Reverberation II' },
  { id = 148917, name = 'Avatar: Rune of Shinra II' },
  { id = 148918, name = 'Avatar: Reptilian Inversion III' },
  { id = 148919, name = 'Avatar: Northern Serenity II' },
  { id = 148920, name = 'Avatar: Enlistment II' },
  { id = 148921, name = 'Avatar: Jungle Rot II' },
  { id = 148922, name = 'Avatar: Melodic Crippling I' },
  { id = 148923, name = 'Spell: Spear of Totality II' },
  { id = 148924, name = 'Spell: Touch of Midnight II' },
  { id = 148925, name = 'Spell: Drape of Temerity III' },
  { id = 148926, name = 'Spell: Spiteful Minion I' },
  { id = 148927, name = 'Spell: Curse of Spite II' },
  { id = 148928, name = 'Spell: Dread Inferno II' },
  { id = 148929, name = 'Spell: Touch of Obliteration II' },
  { id = 148930, name = 'Spell: Planetary Annihilation II' },
  { id = 148931, name = 'Spell: Magma Deluge II' },
  { id = 148932, name = 'Spell: Lance of Elements II' },
  { id = 148934, name = 'Spell: Summon Hurricane Orb I' },
  { id = 148935, name = 'Spell: Rune of Shinra II' },
  { id = 148937, name = 'Spell: Natureburst II' },
  { id = 148938, name = 'Spell: Wildsurge I' },
  { id = 148939, name = 'Spell: Gelidspike I' },
  { id = 148940, name = 'Spell: Reptilian Inversion IV' },
  { id = 148941, name = 'Spell: Torpor of Halas II' },
  { id = 148943, name = 'Spell: Tribal Mending II' },
  { id = 148944, name = 'Spell: Light of Transcendency II' },
  { id = 148945, name = 'Spell: Ultimate Lay on Hands I' },
  { id = 148946, name = 'Spell: Enlistment III' },
  { id = 148947, name = 'Spell: Heavensward III' },
  { id = 148948, name = 'Spell: Exalting Light II' },
  { id = 148949, name = 'Spell: Underfoot Armor II' },
  { id = 148950, name = 'Spell: Elixir of Sanctification II' },
  { id = 148951, name = 'Spell: Blistering Malady II' },
  { id = 148952, name = 'Spell: Beastial Furor I' },
  { id = 148953, name = 'Spell: Chorus of Solace II' },
  { id = 148954, name = 'Spell: Requiem of Cinders II' },
  { id = 148955, name = 'Spell: Echo of Levity I' },
  { id = 148956, name = 'Spell: Deepforest Protector I' },
  { id = 148957, name = 'Spell: Vitality of the Gladestrider II' },
  { id = 148958, name = 'Spell: Blessing of the Void II' },
  { id = 148959, name = 'Spell: Regrowth of the Avatar II' },
  { id = 148960, name = 'Spell: Avatar Rune III' },
  { id = 148962, name = 'Sharpened Tower Stone (Ranged)' },
  { id = 148963, name = 'Spell: Wave of Transcendency II' },
  { id = 148964, name = 'Spell: Boon of the Summoner II' },
  { id = 148965, name = 'Spell: Evasive Minion II' },
  { id = 148968, name = 'Ultimate Veeshan\'s Peak Artifact (Charm)' },
  { id = 148973, name = 'Heart of the Peak' },
  { id = 148997, name = 'Ultimate Avatar Breastplate (Perfected)' },
  { id = 148998, name = 'Ultimate Avatar Chain Tunic (Perfected)' },
  { id = 148999, name = 'Ultimate Avatar Chestwraps (Perfected)' },
  { id = 149000, name = 'Ultimate Avatar Robe (Perfected)' },
  { id = 149001, name = 'Pyros, Seal of Total Annihilation' },
  { id = 149002, name = 'Fatality, Seal of Midnight' },
  { id = 149003, name = 'Simulacrum, Seal of Spite' },
  { id = 149004, name = 'Tyrant, Seal of Elements' },
  { id = 149005, name = 'Spell: Servant of Elements II' },
  { id = 149006, name = 'Spell: Juggernaut Defender II' },
  { id = 149007, name = 'Overlord, Seal of Order' },
  { id = 149008, name = 'Grovestrider, Seal of Wildsurge' },
  { id = 149009, name = 'Frozenbrood, Seal of the Companion' },
  { id = 149010, name = 'Spell: Totemic Companion II' },
  { id = 149011, name = 'Spell: Defender of Justice I' },
  { id = 149012, name = 'Arbiter, Seal of the Defender' },
  { id = 149013, name = 'Zealot, Seal of Exalt' },
  { id = 149014, name = 'Primeval, Seal of the Savage' },
  { id = 149015, name = 'Echoplex, Seal of Attuned' },
  { id = 149016, name = 'Netherstrand, Seal of the Warden' },
  { id = 149017, name = 'Skill: Exploding Palm III' },
  { id = 149018, name = 'Skill: Shadowslice III' },
  { id = 149019, name = 'Tranquility, Seal of the Palm' },
  { id = 149020, name = 'Shadowswarm, Seal of the Hidden' },
  { id = 149021, name = 'Deathcleave, Seal of the Arc' },
  { id = 149022, name = 'Skill: Arc of Death III' },
  { id = 149023, name = 'Deathmask of the Dragonbrood' },
  { id = 149024, name = 'Skill: Battle Frenzy II' },
  { id = 149025, name = 'Lunacy, Seal of Frenzy' },
  { id = 149026, name = 'Orb of Levant' },
  { id = 149027, name = 'Spell: Bonefury I' },
  { id = 149028, name = 'Spell: Dismal Deeds I' },
  { id = 149224, name = 'Skill: Dreadful Volley I' },
  { id = 150078, name = 'Transmutation Recipe: Vision Dust' },
  { id = 150079, name = 'Transmutation Recipe: Gleaming Crystal' },
  { id = 150080, name = 'Transmutation Recipe: Refined Nightshade' },
  { id = 150081, name = 'Transmutation Recipe: Brittle Arclight Spanner' },
  { id = 150082, name = 'Transmutation Recipe: Stone of Avatar Stamina' },
  { id = 150083, name = 'Transmutation Recipe: Stone of Avatar Agility' },
  { id = 150084, name = 'Transmutation Recipe: Stone of Avatar Intelligence' },
  { id = 150085, name = 'Transmutation Recipe: Stone of Avatar Dexterity' },
  { id = 150086, name = 'Transmutation Recipe: Stone of Avatar Strength' },
  { id = 150087, name = 'Transmutation Recipe: Gnomish Sapper Charge 1A' },
  { id = 150088, name = 'Transmutation Recipe: Gnomish Death Ray 1A' },
  { id = 150089, name = 'Transmutation Recipe: Cursed Fang of Mayong' },
  { id = 150128, name = 'Essence of Avatar Agility' },
  { id = 150129, name = 'Essence of Avatar Dexterity' },
  { id = 150130, name = 'Essence of Avatar Intelligence' },
  { id = 150131, name = 'Essence of Avatar Strength' },
}

local DEMIGOD_LOOT = {
  { id = 40703, name = 'Familiar of the Hooded Scrykin' },
  { id = 40704, name = 'Familiar of the Gorged Eye' },
  { id = 40728, name = 'Familiar of the Zombie Doorman' },
  { id = 64728, name = 'Ravager\'s Sword Ornamentation' },
  { id = 64729, name = 'Ravager\'s Great Sword Ornamentation' },
  { id = 64730, name = 'Ravager\'s Mace Ornamentation' },
  { id = 64731, name = 'Ravager\'s Maul Ornamentation' },
  { id = 64732, name = 'Ravager\'s Rapier Ornamentation' },
  { id = 64733, name = 'Ravager\'s Lance Ornamentation' },
  { id = 64734, name = 'Ravager\'s Claw Ornamentation' },
  { id = 64735, name = 'Ravager\'s Shield Ornamentation' },
  { id = 64736, name = 'Ravager\'s Bow Ornamentation' },
  { id = 71982, name = 'Dreadful Totem: Bone Golem' },
  { id = 72000, name = 'Dreadful Totem: Night Harvest Scarecrow' },
  { id = 77402, name = 'Dreadful Totem: Phase Spider' },
  { id = 77464, name = 'Dreadful Totem: Rotted Treant' },
  { id = 148368, name = 'Ultimate Avatar Token' },
  { id = 148987, name = 'Incredibly Salty Tears' },
  { id = 149040, name = 'Cyclops Island Key' },
  { id = 149041, name = 'Undead Island Key' },
  { id = 149042, name = 'Allizewsaur Island Key' },
  { id = 149043, name = 'Aviak Island Key' },
  { id = 149044, name = 'Goblin Island Key' },
  { id = 149045, name = 'Antonica Training Camp Island Key' },
  { id = 149046, name = 'Death\'s Door Island Key' },
  { id = 149048, name = 'Demigod Essence' },
  { id = 149049, name = 'Demigod Stone I' },
  { id = 149050, name = 'Coalesced Demigod Energy' },
  { id = 149072, name = 'Razor Sharp Demigod Stone I (1H)' },
  { id = 149073, name = 'Razor Sharp Demigod Stone I (2H)' },
  { id = 149074, name = 'Razor Sharp Demigod Stone I (Ranged)' },
  { id = 149075, name = 'Razor Sharp Demigod Stone I (Healer)' },
  { id = 149088, name = 'Ultimate Avatar Helmet (Perfected)' },
  { id = 149089, name = 'Ultimate Avatar Coif (Perfected)' },
  { id = 149090, name = 'Ultimate Avatar Leather Cap (Perfected)' },
  { id = 149091, name = 'Ultimate Avatar Cap (Perfected)' },
  { id = 149092, name = 'Ultimate Coin Purse Token' },
  { id = 149100, name = 'Frenzied Stone of Salik (Demigod)' },
  { id = 149101, name = 'Realist\'s Stone of The Leopard (Demigod)' },
  { id = 149102, name = 'Stone of Ironvines (Demigod)' },
  { id = 149103, name = 'Everlasting Stone (Demigod)' },
  { id = 149104, name = 'Stone of the Valiant (Demigod)' },
  { id = 149105, name = 'Stone of the Tactics (Demigod)' },
  { id = 149106, name = 'Butcher, Seal of Mutilation' },
  { id = 149107, name = 'Glaciate, Seal of Frozen Waves' },
  { id = 149123, name = 'Soul-Essence of Mata Muram' },
  { id = 149125, name = 'Demigod\'s 1H Stone I' },
  { id = 149126, name = 'Demigod\'s 2H Stone I' },
  { id = 149127, name = 'Demigod\'s Fist Stone I' },
  { id = 149128, name = 'Demigod\'s Bowmaster Stone I' },
  { id = 149129, name = 'Spell: Lance of Mutilation I' },
  { id = 149130, name = 'Spell: Minion of Hatred I' },
  { id = 149131, name = 'Spell: Dreadlord\'s Provocation I' },
  { id = 149132, name = 'Spell: Swarm of the Darklord I' },
  { id = 149133, name = 'Spell: Death Touch I' },
  { id = 149135, name = 'Spell: Supplicate I' },
  { id = 149136, name = 'Spell: Abyssal Beckoning I' },
  { id = 149137, name = 'Spell: Swarm of Puss I' },
  { id = 149138, name = 'Spell: Raging Hellfire I' },
  { id = 149139, name = 'Spell: Contamination I' },
  { id = 149140, name = 'Spell: Summon Deadlock Sphere I' },
  { id = 149141, name = 'Spell: Standstill I' },
  { id = 149142, name = 'Spell: Ethereal Barrage I' },
  { id = 149143, name = 'Spell: Scorching Blitz I' },
  { id = 149144, name = 'Spell: Hailstorm I' },
  { id = 149145, name = 'Spell: Arcane Construct I' },
  { id = 149146, name = 'Spell: Summon Chromatic Gem I' },
  { id = 149147, name = 'Spell: Gather Elements I' },
  { id = 149148, name = 'Spell: Pyreshield I' },
  { id = 149149, name = 'Spell: Furor I' },
  { id = 149150, name = 'Spell: Flashfreeze I' },
  { id = 149151, name = 'Spell: Garoulize I' },
  { id = 149152, name = 'Spell: Chaotic Rapture I' },
  { id = 149153, name = 'Spell: Imperile I' },
  { id = 149154, name = 'Spell: Enfeeble I' },
  { id = 149155, name = 'Spell: Arcanist\'s Focusing I' },
  { id = 149156, name = 'Spell: Warlord\'s Focusing I' },
  { id = 149157, name = 'Spell: Berserk Spirit I' },
  { id = 149158, name = 'Spell: Bulwark of Spines I' },
  { id = 149159, name = 'Spell: Reprisal of Tunare I' },
  { id = 149160, name = 'Spell: Meandering Death I' },
  { id = 149161, name = 'Spell: Infestation I' },
  { id = 149162, name = 'Spell: Ascension I' },
  { id = 149163, name = 'Spell: Omnipotence I' },
  { id = 149164, name = 'Spell: Authority I' },
  { id = 149166, name = 'Spell: Holy Bolt I' },
  { id = 149167, name = 'Spell: Holy Nova I' },
  { id = 149168, name = 'Spell: Spiteful Beckoning I' },
  { id = 149169, name = 'Spell: Wild Cascade I' },
  { id = 149170, name = 'Spell: Lucid Dream I' },
  { id = 149171, name = 'Spell: Seethe I' },
  { id = 149172, name = 'Spell: Black Plague I' },
  { id = 149173, name = 'Skill: Savage I' },
  { id = 149174, name = 'Spell: Ultimate Predator I' },
  { id = 149175, name = 'Spell: Hawkeye I' },
  { id = 149176, name = 'Spell: Crossfire I' },
  { id = 149177, name = 'Spell: Sickle Winds I' },
  { id = 149178, name = 'Spell: Melody of the Imperiled I' },
  { id = 149179, name = 'Spell: Melody of Enfeeblement I' },
  { id = 149180, name = 'Spell: Dire Blade I' },
  { id = 149181, name = 'Skill: Form of Dvinn I' },
  { id = 149182, name = 'Skill: Form of Zephyl I' },
  { id = 149183, name = 'Skill: Echo of Rallos I' },
  { id = 149184, name = 'Skill: Maniacal Volley I' },
  { id = 149195, name = 'Spell: Arcanist\'s Ascension I' },
  { id = 149196, name = 'Fallout, Seal of Desecration' },
  { id = 149197, name = 'Tempest, Seal of the Storm' },
  { id = 149198, name = 'Menace, Seal of the Imperiled' },
  { id = 149199, name = 'Fealty, Seal of the Tribe' },
  { id = 149200, name = 'Wander, Seal of Debilitation' },
  { id = 149201, name = 'Direward, Seal of Desperation' },
  { id = 149202, name = 'Benefactor, Seal of Transcendency' },
  { id = 149203, name = 'Calamity, Seal of the Fierce' },
  { id = 149204, name = 'Griffin, Seal of the Berserk' },
  { id = 149205, name = 'Ascendance, Seal of the Arcane' },
  { id = 149206, name = 'Blackguard, Seal of Dvinn' },
  { id = 149207, name = 'Mantra, Seal of Zephyl' },
  { id = 149208, name = 'Stormrage, Seal of the Betrayer' },
  { id = 149209, name = 'Ritual, Seal of Bleeding' },
  { id = 149212, name = 'All Hallows Eve Ornament (2HS)' },
  { id = 149213, name = 'All Hallows Eve Ornament (1HS)' },
  { id = 149214, name = 'All Hallows Eve Ornament (1HB)' },
  { id = 149215, name = 'All Hallows Eve Ornament (Fist)' },
  { id = 149216, name = 'All Hallows Eve Ornament (Bow)' },
  { id = 149217, name = 'All Hallows Eve Ornament (Glaive)' },
  { id = 149220, name = 'Orb of the Scarecrow' },
  { id = 149221, name = 'Orb of the Amygdalan' },
  { id = 149222, name = 'Orb of the Spectre' },
  { id = 149225, name = 'Dreadful Staff of Temperate Flux' },
  { id = 149226, name = 'Dreadful Clasp' },
  { id = 149227, name = 'Dreadful Belt' },
  { id = 149228, name = 'Dreadful Cinch' },
  { id = 149234, name = 'Homunculus Parts (1)' },
  { id = 149235, name = 'Homunculus Parts (2)' },
  { id = 149236, name = 'Homunculus Parts (3)' },
  { id = 149237, name = 'Homunculus Parts (4)' },
  { id = 149239, name = 'Ultimate Illusion Orb: Discord' },
  { id = 149240, name = 'Ultimate Illusion Orb: Halloween' },
  { id = 149241, name = 'Ultimate Unrest Commendation' },
  { id = 149243, name = 'Dreadful Ring of the Protector' },
  { id = 149244, name = 'Dreadful Ring of the Tactician' },
  { id = 149245, name = 'Dreadful Earring of the Protector' },
  { id = 149246, name = 'Dreadful Earring of the Tactician' },
  { id = 149247, name = 'Dreadful Vizor' },
  { id = 149248, name = 'Dreadful Veil' },
  { id = 149249, name = 'Dreadful Plate Gorget' },
  { id = 149250, name = 'Dreadful Choker' },
  { id = 149251, name = 'Dreadful Cloak of the Protector' },
  { id = 149252, name = 'Dreadful Cloak of the Tactician' },
  { id = 149253, name = 'Dreadful Cloak of the Arcanist' },
  { id = 149254, name = 'Dreadful Pauldrons' },
  { id = 149255, name = 'Dreadful Shoulderpads' },
  { id = 149256, name = 'Spell: Bonefury II' },
  { id = 149257, name = 'A Freshly Severed Head' },
  { id = 149263, name = 'Ultimate Avatar Vambraces (Perfected)' },
  { id = 149264, name = 'Ultimate Avatar Plate Boots (Perfected)' },
  { id = 149265, name = 'Ultimate Avatar Legplates (Perfected)' },
  { id = 149266, name = 'Ultimate Avatar Bracer (Perfected)' },
  { id = 149267, name = 'Ultimate Avatar Chain Vambraces (Perfected)' },
  { id = 149268, name = 'Ultimate Avatar Chain Boots (Perfected)' },
  { id = 149269, name = 'Ultimate Avatar Shinguards (Perfected)' },
  { id = 149270, name = 'Ultimate Avatar Chain Bracer (Perfected)' },
  { id = 149271, name = 'Ultimate Avatar Leather Armguards (Perfected)' },
  { id = 149272, name = 'Ultimate Avatar Leather Boots (Perfected)' },
  { id = 149273, name = 'Ultimate Avatar Legwraps (Perfected)' },
  { id = 149274, name = 'Ultimate Avatar Leather Bracer (Perfected)' },
  { id = 149275, name = 'Ultimate Avatar Sleeves (Perfected)' },
  { id = 149276, name = 'Ultimate Avatar Slippers (Perfected)' },
  { id = 149277, name = 'Ultimate Avatar Slacks (Perfected)' },
  { id = 149278, name = 'Ultimate Avatar Bracelet (Perfected)' },
  { id = 149279, name = 'Ultimate Avatar Gauntlets (Perfected)' },
  { id = 149280, name = 'Ultimate Avatar Chain Gloves (Perfected)' },
  { id = 149281, name = 'Ultimate Avatar Leather Gloves (Perfected)' },
  { id = 149282, name = 'Ultimate Avatar Gloves (Perfected)' },
  { id = 149283, name = 'Fear-Touched Perfected Seal' },
  { id = 149284, name = 'Barricade of Death' },
  { id = 149285, name = 'Barricade of the Righteous' },
  { id = 149286, name = 'Shield of the Tribe' },
  { id = 149287, name = 'Shield of Surging' },
  { id = 149288, name = 'Shield of Ether' },
  { id = 149289, name = 'Fearsome Cloak of Scorching' },
  { id = 149290, name = 'Fearsome Cloak of Freezing' },
  { id = 149291, name = 'Shield of the Servant' },
  { id = 149292, name = 'Shield of the Abyss' },
  { id = 149293, name = 'Fearsome Cloak of the Vortex' },
  { id = 149294, name = 'Fearsome Cloak of the Winds' },
  { id = 149295, name = 'Fearsome Mask of the Summoner' },
  { id = 149296, name = 'Fearsome Mask of the Dreadlord' },
  { id = 149297, name = 'Fearsome Mask of the Exalted' },
  { id = 149298, name = 'Fearsome Cloak of the Holy' },
  { id = 149299, name = 'Pantheon Cloak of the Savage' },
  { id = 149300, name = 'Fearsome Mask of the Claw' },
  { id = 149301, name = 'Pantheon Mask of the Axe Master' },
  { id = 149302, name = 'Pantheon Mask of the Palm' },
  { id = 149336, name = 'Pantheon Mask of the Dagger' },
  { id = 149355, name = 'Strange Coal' },
  { id = 149359, name = 'Velketor\'s Barrier Notes (1)' },
  { id = 149360, name = 'Velketor\'s Barrier Notes (2)' },
  { id = 149361, name = 'Velketor\'s Barrier Notes (3)' },
  { id = 149391, name = 'Velketorian Essence' },
  { id = 149392, name = 'Glinting Velketorian Shard' },
  { id = 149400, name = 'Demigod Armor Fragment' },
  { id = 149401, name = 'Executus, Death\'s Companion (Trait +)' },
  { id = 149403, name = 'Gatekeeper, Shield of Souls (Trait+)' },
  { id = 149404, name = 'Velketorian Protector\'s Ring' },
  { id = 149405, name = 'Velketorian Tactician\'s Ring' },
  { id = 149406, name = 'Velketorian Protector\'s Earring' },
  { id = 149407, name = 'Velketorian Tactician\'s Earring' },
  { id = 149408, name = 'Velketorian Vizor of Mutilation' },
  { id = 149409, name = 'Velketorian Sorcerer\'s Veil' },
  { id = 149410, name = 'Velketorian Neckguard' },
  { id = 149411, name = 'Velketorian Choker' },
  { id = 149412, name = 'Velketorian Protector\'s Cloak' },
  { id = 149413, name = 'Velketorian Tactician\'s Cloak' },
  { id = 149414, name = 'Velketorian Cloak of the Sorcerer' },
  { id = 149415, name = 'Velketorian Pauldrons' },
  { id = 149416, name = 'Velketorian Shoulderpads' },
  { id = 149417, name = 'Demigod Stone II' },
  { id = 149419, name = 'Delirious, The Frenzied Bracer (Trait +)' },
  { id = 149420, name = 'Oblivion, Shield of Lifeburn (Trait+)' },
  { id = 149424, name = 'Azurewrath, Shield of Obliteration (Trait+)' },
  { id = 149426, name = 'Payload, Blade of Suppressing Fire (Trait +)' },
  { id = 149427, name = 'Portal of War Power Source' },
  { id = 149428, name = 'Cutthroat, The Bracer of Twin Daggers (Trait +)' },
  { id = 149439, name = 'Razor Sharp Demigod Stone II (1H)' },
  { id = 149440, name = 'Razor Sharp Demigod Stone II (2H)' },
  { id = 149441, name = 'Razor Sharp Demigod Stone II (Ranged)' },
  { id = 149442, name = 'Razor Sharp Demigod Stone II (Healer)' },
  { id = 149447, name = 'Goblin DoT Enhancement Device' },
  { id = 149452, name = 'Portal of War Power Key' },
  { id = 149456, name = 'Razor Sharp Demigod Stone II (Shield)' },
  { id = 150051, name = 'Arcane Crystal' },
  { id = 150090, name = 'Transmutation Recipe: Sublime Dust' },
  { id = 150091, name = 'Transmutation Recipe: Empyreal Crystal' },
  { id = 150092, name = 'Transmutation Recipe: Simmering Pitch' },
  { id = 150093, name = 'Transmutation Recipe: Stone of Demigod Stamina' },
  { id = 150094, name = 'Transmutation Recipe: Stone of Demigod Agility' },
  { id = 150095, name = 'Transmutation Recipe: Stone of Demigod Intelligence' },
  { id = 150096, name = 'Transmutation Recipe: Stone of Demigod Dexterity' },
  { id = 150097, name = 'Transmutation Recipe: Stone of Demigod Strength' },
  { id = 150098, name = 'Transmutation Recipe: Gnomish Death Ray 2B' },
  { id = 150099, name = 'Transmutation Recipe: Gnomish Jumper Cables XLT' },
  { id = 150100, name = 'Transmutation Recipe: Elixir of Ascendance' },
  { id = 150101, name = 'Transmutation Recipe: Gnomish Rocket Boots' },
  { id = 150144, name = 'Elemental Fire' },
  { id = 150145, name = 'Transmutation Recipe: Demigod Flux' },
  { id = 150147, name = 'Ancient Coin of Agility' },
  { id = 150148, name = 'Ancient Coin of Intelligence' },
  { id = 150149, name = 'Ancient Coin of Dexterity' },
  { id = 150150, name = 'Ancient Coin of Strength' },
  { id = 150206, name = 'A Fear-Touched Brain' },
  { id = 150215, name = 'Transmutation Recipe: Repurposed Alert-O-Bot' },
  { id = 150223, name = 'Whizzing Alert-o-Bot Core' },
}

local DEVICE_RECIPES = {
  { key = 'arcanecrystal', name = 'Arcane Crystal', outputId = 150051, category = 'Ultimate', mats = { 150050, 10029 } },
  { key = 'blastingpowder', name = 'Blasting Powder', outputId = 150052, category = 'Ultimate', mats = { 150050, 150053 } },
  { key = 'ghoullordsummoningfocus', name = 'Ghoul Lord Summoning Focus', outputId = 150073, category = 'Ultimate', mats = { 150050, 150051, 9963, 150059 } },
  { key = 'bubblingjarofimmolation', name = 'Bubbling Jar of Immolation', outputId = 150072, category = 'Ultimate', mats = { 150051, 150052 } },
  { key = 'stoneofultimatestamina', name = 'Stone of Ultimate Stamina', outputId = 150067, category = 'Ultimate', mats = { 150051, 150054 } },
  { key = 'stoneofultimateagility', name = 'Stone of Ultimate Agility', outputId = 150068, category = 'Ultimate', mats = { 150051, 150055 } },
  { key = 'stoneofultimateintelligence', name = 'Stone of Ultimate Intelligence', outputId = 150069, category = 'Ultimate', mats = { 150051, 150056 } },
  { key = 'stoneofultimatedexterity', name = 'Stone of Ultimate Dexterity', outputId = 150070, category = 'Ultimate', mats = { 150051, 150057 } },
  { key = 'stoneofultimatestrength', name = 'Stone of Ultimate Strength', outputId = 150071, category = 'Ultimate', mats = { 150051, 150058 } },
  { key = 'ultimatetokentolegendarymold', name = 'Ultimate Token to Legendary Mold', outputId = 147763, category = 'Ultimate', mats = { 147496, 150051, 150050 } },
  { key = 'legendarymoldtoultimatetoken', name = 'Legendary Mold to Ultimate Token', outputId = 147496, category = 'Ultimate', mats = { 147763, 150051, 150050 } },
  { key = 'goblinduplicatorxl', name = 'Goblin Duplicator XL', outputId = 150119, category = 'Ultimate', mats = { 150051, 2469, 2300, 148097 } },
  { key = 'trakanonsannihilator', name = 'Trakanons Annihilator', outputId = 150118, category = 'Ultimate', mats = { 150051, 147878, 147881, 147787 } },
  { key = 'goblinhategeneratorxtz', name = 'Goblin Hate Generator XTZ', outputId = 150136, category = 'Ultimate', mats = { 150051, 150137, 150072 } },
  { key = 'gleamingcrystal', name = 'Gleaming Crystal', outputId = 150121, category = 'Avatar', mats = { 150120, 10012 } },
  { key = 'refinednightshade', name = 'Refined Nightshade', outputId = 150122, category = 'Avatar', mats = { 150120, 65589 } },
  { key = 'brittlearclightspanner', name = 'Brittle Arclight Spanner', outputId = 150123, category = 'Avatar', mats = { 150120, 150121, 16283, 34240 } },
  { key = 'stoneofavataragility', name = 'Stone of Avatar Agility', outputId = 150124, category = 'Avatar', mats = { 150121, 150128, 150068 } },
  { key = 'stoneofavatarintelligence', name = 'Stone of Avatar Intelligence', outputId = 150125, category = 'Avatar', mats = { 150121, 150130, 150069 } },
  { key = 'stoneofavatardexterity', name = 'Stone of Avatar Dexterity', outputId = 150126, category = 'Avatar', mats = { 150121, 150129, 150070 } },
  { key = 'stoneofavatarstrength', name = 'Stone of Avatar Strength', outputId = 150127, category = 'Avatar', mats = { 150121, 150131, 150071 } },
  { key = 'goblinsappercharge1a', name = 'Goblin Sapper Charge 1A', outputId = 150132, category = 'Avatar', mats = { 150121, 150122, 150052 } },
  { key = 'gnomishdeathray1a', name = 'Gnomish Death Ray 1A', outputId = 150133, category = 'Avatar', mats = { 150120, 150122, 150052, 150123 } },
  { key = 'cursedfangofmayong', name = 'Cursed Fang of Mayong', outputId = 150134, category = 'Avatar', mats = { 150121, 148563, 20656, 150123 } },
  { key = 'empyrealcrystal', name = 'Empyreal Crystal', outputId = 150142, category = 'Demigod', mats = { 150141, 150121, 148987 } },
  { key = 'simmeringpitch', name = 'Simmering Pitch', outputId = 150143, category = 'Demigod', mats = { 150141, 150144 } },
  { key = 'demigodflux', name = 'Demigod Flux', outputId = 150146, category = 'Demigod', mats = { 150142, 149417, 149355 } },
  { key = 'stoneofdemigodagility', name = 'Stone of Demigod Agility', outputId = 150151, category = 'Demigod', mats = { 150142, 150147, 150124, 148551 } },
  { key = 'stoneofdemigodintelligence', name = 'Stone of Demigod Intelligence', outputId = 150152, category = 'Demigod', mats = { 150142, 150148, 150125, 148551 } },
  { key = 'stoneofdemigoddexterity', name = 'Stone of Demigod Dexterity', outputId = 150153, category = 'Demigod', mats = { 150142, 150149, 150126, 148551 } },
  { key = 'stoneofdemigodstrength', name = 'Stone of Demigod Strength', outputId = 150154, category = 'Demigod', mats = { 150142, 150150, 150127, 148551 } },
  { key = 'gnomishdeathray2b', name = 'Gnomish Death Ray 2B', outputId = 150155, category = 'Demigod', mats = { 150142, 150146, 150143, 150123 } },
  { key = 'gnomishjumpercablesxlt', name = 'Gnomish Jumper Cables XLT', outputId = 150156, category = 'Demigod', mats = { 150142, 150146, 150143, 148312 } },
  { key = 'elixirofascendence', name = 'Elixir of Ascendence', outputId = 150157, category = 'Demigod', mats = { 150142, 150146, 149257, 32557 } },
  { key = 'gnomishrocketboots', name = 'Gnomish Rocket Boots', outputId = 150158, category = 'Demigod', mats = { 150142, 150146, 150143, 2300 } },
  { key = 'angeliccrystal', name = 'Angelic Crystal', outputId = 150160, category = 'Godly', mats = { 150159, 150142 } },
  { key = 'trademasterassembly', name = 'Trademaster Assembly', outputId = 150167, category = 'Godly', mats = { 150160, 16283, 16286, 150161 } },
  { key = 'chainedessenceofkerafyrm', name = 'Chained Essence of Kerafyrm', outputId = 150218, category = 'Godly', mats = { 150160, 150167, 150222 } },
  { key = 'repurposedalert0bot', name = 'Repurposed Alert-O-Bot', outputId = 150219, category = 'Godly', mats = { 150160, 150167, 150223 } },
  { key = 'superjenkins', name = 'Super Jenkins', outputId = 150220, category = 'Godly', mats = { 150160, 150167, 150047 } },
  { key = 'goblinsuppressiondevice', name = 'Goblin Suppression Device', outputId = 150221, category = 'Godly', mats = { 150160, 150167, 150224, 150169 } },
  { key = 'advancedbosssummondevice', name = 'Advanced Boss Summon Device', outputId = 150226, category = 'Godly', mats = { 150160, 150167, 149850, 150169 } },
  { key = 'cloudychromaticgem', name = 'Cloudy Chromatic Gem', outputId = 150161, category = 'Godly', mats = { 150160, 150162, 148368 } },
  { key = 'goblinmindcontroldevice', name = 'Goblin Mind Control Device', outputId = 150163, category = 'Godly', mats = { 150160, 150162, 150167, 150206 } },
  { key = 'philosophersstone', name = 'Philosophers Stone', outputId = 150165, category = 'Godly', mats = { 150160, 150146, 150167, 150207 } },
  { key = 'goblinharmpreventionring', name = 'Goblin Harm Prevention Ring', outputId = 150164, category = 'Godly', mats = { 150160, 150169, 150167, 150161 } },
  { key = 'socketfitterxxl', name = 'Socket Fitter XXL', outputId = 150168, category = 'Godly', mats = { 150146, 150143, 150167, 150169 } },
  { key = 'stoneofgodlyagility', name = 'Stone of Godly Agility', outputId = 150202, category = 'Godly', mats = { 150160, 150208, 150151, 148551 } },
  { key = 'stoneofgodlyintelligence', name = 'Stone of Godly Intelligence', outputId = 150204, category = 'Godly', mats = { 150160, 150209, 150152, 148551 } },
  { key = 'stoneofgodlydexterity', name = 'Stone of Godly Dexterity', outputId = 150203, category = 'Godly', mats = { 150160, 150210, 150153, 148551 } },
  { key = 'stoneofgodlystrength', name = 'Stone of Godly Strength', outputId = 150205, category = 'Godly', mats = { 150160, 150211, 150154, 148551 } },
  { key = 'gnomishdeathrayx1', name = 'Gnomish Death Ray X1', outputId = 150212, category = 'Godly', mats = { 150160, 150155, 150169, 150167 } },
  { key = 'nightfall', name = 'Nightfall', outputId = 150213, category = 'Godly', mats = { 150160, 150134, 150169, 150167 } },
  { key = 'corruptedprismaticbauble', name = 'Corrupted Prismatic Bauble', outputId = 150214, category = 'Godly', mats = { 150160, 150204, 150169, 150167 } },
}

-- PEQ icon column (same as in-game Item.Icon); UI uses A_DragItem + (icon - 500)
local TRANSMUTE_ITEM_ICONS = {
  [2300] = 764,
  [2469] = 771,
  [3889] = 1147,
  [9963] = 958,
  [10012] = 767,
  [10029] = 958,
  [16283] = 1036,
  [16286] = 823,
  [20080] = 616,
  [20656] = 1130,
  [32557] = 1153,
  [34240] = 1095,
  [40619] = 2250,
  [40620] = 2252,
  [40621] = 2251,
  [40628] = 1478,
  [40629] = 1474,
  [40630] = 1496,
  [40631] = 1482,
  [40657] = 2596,
  [40658] = 2597,
  [40659] = 2598,
  [40660] = 2599,
  [40671] = 2603,
  [40687] = 2612,
  [40688] = 2613,
  [40689] = 2614,
  [40690] = 2615,
  [40691] = 2616,
  [40703] = 1649,
  [40704] = 885,
  [40716] = 2634,
  [40717] = 2635,
  [40718] = 2636,
  [40719] = 2637,
  [40720] = 2638,
  [40728] = 1386,
  [40730] = 1496,
  [40731] = 1535,
  [40748] = 2668,
  [40749] = 2669,
  [40750] = 2670,
  [40751] = 1496,
  [40752] = 2671,
  [40762] = 1478,
  [40764] = 1890,
  [40781] = 2094,
  [40782] = 2095,
  [40783] = 2090,
  [40784] = 2093,
  [40785] = 2088,
  [43974] = 2884,
  [43976] = 1445,
  [43977] = 2147,
  [43978] = 2148,
  [48972] = 3305,
  [48974] = 3318,
  [48975] = 3319,
  [48987] = 3300,
  [50490] = 3335,
  [50491] = 3336,
  [50855] = 3283,
  [50856] = 3284,
  [50857] = 3285,
  [50858] = 3286,
  [52194] = 5041,
  [52195] = 5042,
  [53358] = 3842,
  [53752] = 3386,
  [53753] = 3387,
  [54915] = 3362,
  [54918] = 3364,
  [54984] = 3592,
  [54985] = 3593,
  [56060] = 3713,
  [57379] = 3723,
  [57380] = 3718,
  [57381] = 3726,
  [57382] = 3724,
  [57474] = 3770,
  [57529] = 3793,
  [57530] = 3794,
  [57531] = 3795,
  [57601] = 2021,
  [60946] = 3810,
  [60947] = 3811,
  [61035] = 3812,
  [61955] = 3868,
  [62769] = 3931,
  [64708] = 3965,
  [64728] = 3967,
  [64729] = 3968,
  [64730] = 3969,
  [64731] = 3970,
  [64732] = 3971,
  [64733] = 3972,
  [64734] = 3974,
  [64735] = 3975,
  [64736] = 3976,
  [65589] = 1198,
  [71982] = 1406,
  [72000] = 1481,
  [77402] = 1659,
  [77464] = 1801,
  [147496] = 2261,
  [147732] = 2711,
  [147733] = 2756,
  [147734] = 2715,
  [147735] = 2709,
  [147736] = 718,
  [147737] = 2714,
  [147738] = 2712,
  [147740] = 3006,
  [147741] = 3227,
  [147743] = 2698,
  [147744] = 2748,
  [147745] = 1624,
  [147746] = 642,
  [147747] = 514,
  [147748] = 532,
  [147749] = 850,
  [147750] = 928,
  [147751] = 507,
  [147752] = 3687,
  [147753] = 2750,
  [147754] = 2720,
  [147756] = 1439,
  [147757] = 1439,
  [147758] = 2756,
  [147759] = 2709,
  [147760] = 528,
  [147761] = 2754,
  [147762] = 1457,
  [147763] = 1151,
  [147780] = 2726,
  [147781] = 2718,
  [147782] = 508,
  [147783] = 2722,
  [147784] = 2484,
  [147785] = 2708,
  [147786] = 503,
  [147787] = 1722,
  [147788] = 3220,
  [147789] = 657,
  [147790] = 798,
  [147791] = 2752,
  [147792] = 2709,
  [147793] = 954,
  [147794] = 2725,
  [147795] = 2755,
  [147796] = 2724,
  [147797] = 2276,
  [147798] = 931,
  [147799] = 507,
  [147800] = 1494,
  [147801] = 3630,
  [147802] = 4480,
  [147803] = 1208,
  [147805] = 747,
  [147806] = 621,
  [147807] = 530,
  [147808] = 671,
  [147809] = 546,
  [147810] = 545,
  [147811] = 540,
  [147812] = 641,
  [147813] = 632,
  [147814] = 526,
  [147815] = 620,
  [147816] = 543,
  [147817] = 633,
  [147818] = 630,
  [147819] = 640,
  [147820] = 931,
  [147821] = 517,
  [147822] = 1040,
  [147823] = 634,
  [147824] = 666,
  [147825] = 631,
  [147858] = 1439,
  [147859] = 614,
  [147860] = 618,
  [147861] = 1237,
  [147862] = 533,
  [147863] = 560,
  [147864] = 607,
  [147865] = 913,
  [147866] = 506,
  [147867] = 1063,
  [147868] = 663,
  [147869] = 839,
  [147870] = 668,
  [147871] = 798,
  [147872] = 964,
  [147873] = 758,
  [147875] = 1439,
  [147876] = 1439,
  [147877] = 1429,
  [147878] = 1170,
  [147879] = 519,
  [147880] = 1104,
  [147881] = 809,
  [147882] = 1283,
  [147883] = 1296,
  [147884] = 2151,
  [147896] = 1003,
  [147898] = 770,
  [147910] = 3181,
  [148026] = 963,
  [148027] = 1480,
  [148028] = 1480,
  [148029] = 1480,
  [148030] = 1480,
  [148031] = 1480,
  [148033] = 1480,
  [148034] = 1480,
  [148035] = 1480,
  [148036] = 1480,
  [148037] = 1480,
  [148038] = 1480,
  [148039] = 1480,
  [148040] = 1480,
  [148041] = 1480,
  [148055] = 1480,
  [148056] = 1480,
  [148065] = 1071,
  [148066] = 510,
  [148067] = 850,
  [148068] = 939,
  [148069] = 562,
  [148070] = 615,
  [148071] = 879,
  [148072] = 1063,
  [148073] = 528,
  [148074] = 840,
  [148075] = 841,
  [148076] = 518,
  [148077] = 776,
  [148078] = 662,
  [148079] = 798,
  [148080] = 973,
  [148081] = 676,
  [148082] = 976,
  [148083] = 1043,
  [148084] = 577,
  [148085] = 750,
  [148086] = 750,
  [148087] = 1480,
  [148089] = 1480,
  [148090] = 1480,
  [148091] = 619,
  [148094] = 678,
  [148096] = 588,
  [148097] = 1434,
  [148098] = 507,
  [148099] = 1234,
  [148100] = 1480,
  [148101] = 1480,
  [148102] = 1480,
  [148103] = 1480,
  [148104] = 1480,
  [148105] = 1480,
  [148106] = 1480,
  [148107] = 1480,
  [148108] = 1480,
  [148109] = 1480,
  [148110] = 1480,
  [148111] = 1480,
  [148112] = 1480,
  [148113] = 1480,
  [148114] = 1480,
  [148115] = 1480,
  [148116] = 1480,
  [148117] = 1480,
  [148118] = 1480,
  [148119] = 1480,
  [148123] = 901,
  [148124] = 654,
  [148165] = 865,
  [148188] = 3541,
  [148189] = 3552,
  [148190] = 3545,
  [148191] = 3573,
  [148193] = 3576,
  [148195] = 3585,
  [148197] = 3455,
  [148198] = 683,
  [148214] = 683,
  [148215] = 683,
  [148216] = 683,
  [148217] = 683,
  [148218] = 683,
  [148219] = 683,
  [148220] = 683,
  [148221] = 683,
  [148222] = 683,
  [148223] = 683,
  [148224] = 683,
  [148225] = 683,
  [148226] = 683,
  [148227] = 683,
  [148228] = 683,
  [148229] = 683,
  [148230] = 683,
  [148231] = 683,
  [148232] = 683,
  [148233] = 683,
  [148234] = 683,
  [148235] = 683,
  [148236] = 683,
  [148237] = 683,
  [148238] = 683,
  [148239] = 683,
  [148240] = 683,
  [148241] = 683,
  [148242] = 683,
  [148243] = 683,
  [148244] = 683,
  [148245] = 683,
  [148246] = 683,
  [148247] = 683,
  [148248] = 683,
  [148250] = 1480,
  [148251] = 1480,
  [148252] = 1480,
  [148253] = 1480,
  [148254] = 1480,
  [148255] = 1480,
  [148256] = 1480,
  [148257] = 1480,
  [148258] = 1480,
  [148259] = 1480,
  [148260] = 1480,
  [148261] = 1480,
  [148262] = 1480,
  [148263] = 1480,
  [148264] = 1480,
  [148265] = 1480,
  [148266] = 1480,
  [148267] = 1480,
  [148268] = 1480,
  [148269] = 1480,
  [148270] = 1479,
  [148271] = 1130,
  [148272] = 2137,
  [148273] = 2255,
  [148274] = 2002,
  [148275] = 901,
  [148276] = 2986,
  [148277] = 1966,
  [148278] = 2600,
  [148279] = 2975,
  [148280] = 1313,
  [148281] = 1203,
  [148282] = 683,
  [148283] = 1943,
  [148284] = 1956,
  [148285] = 1994,
  [148286] = 2772,
  [148287] = 1621,
  [148288] = 522,
  [148289] = 747,
  [148290] = 621,
  [148291] = 546,
  [148292] = 540,
  [148293] = 545,
  [148294] = 671,
  [148295] = 530,
  [148296] = 641,
  [148297] = 632,
  [148298] = 543,
  [148299] = 630,
  [148300] = 633,
  [148301] = 526,
  [148302] = 620,
  [148303] = 640,
  [148304] = 931,
  [148305] = 634,
  [148306] = 631,
  [148307] = 666,
  [148308] = 1040,
  [148309] = 517,
  [148310] = 2427,
  [148311] = 1288,
  [148312] = 1377,
  [148313] = 1063,
  [148363] = 1943,
  [148364] = 1956,
  [148365] = 1994,
  [148366] = 2772,
  [148368] = 2634,
  [148369] = 1151,
  [148370] = 1151,
  [148371] = 1151,
  [148372] = 1151,
  [148373] = 1151,
  [148374] = 3117,
  [148375] = 3117,
  [148376] = 3117,
  [148377] = 3117,
  [148378] = 3117,
  [148379] = 863,
  [148380] = 863,
  [148381] = 863,
  [148382] = 863,
  [148383] = 863,
  [148384] = 862,
  [148385] = 862,
  [148386] = 862,
  [148387] = 862,
  [148388] = 862,
  [148389] = 1151,
  [148390] = 3117,
  [148391] = 863,
  [148392] = 862,
  [148446] = 3117,
  [148508] = 683,
  [148509] = 683,
  [148510] = 683,
  [148511] = 683,
  [148512] = 683,
  [148513] = 683,
  [148514] = 683,
  [148515] = 683,
  [148516] = 683,
  [148517] = 683,
  [148518] = 683,
  [148519] = 683,
  [148521] = 683,
  [148522] = 683,
  [148523] = 683,
  [148524] = 683,
  [148525] = 683,
  [148526] = 683,
  [148527] = 683,
  [148528] = 683,
  [148529] = 683,
  [148530] = 683,
  [148531] = 683,
  [148532] = 683,
  [148533] = 683,
  [148534] = 683,
  [148536] = 683,
  [148537] = 683,
  [148538] = 683,
  [148539] = 683,
  [148540] = 683,
  [148541] = 683,
  [148542] = 683,
  [148543] = 683,
  [148544] = 683,
  [148545] = 1151,
  [148546] = 863,
  [148547] = 862,
  [148548] = 2000,
  [148549] = 683,
  [148550] = 683,
  [148551] = 2782,
  [148552] = 1148,
  [148553] = 513,
  [148554] = 1047,
  [148555] = 535,
  [148556] = 618,
  [148557] = 619,
  [148558] = 1475,
  [148559] = 506,
  [148561] = 548,
  [148562] = 1002,
  [148563] = 989,
  [148564] = 744,
  [148565] = 996,
  [148567] = 663,
  [148568] = 657,
  [148569] = 660,
  [148577] = 3209,
  [148578] = 668,
  [148579] = 503,
  [148580] = 938,
  [148581] = 937,
  [148588] = 683,
  [148589] = 1144,
  [148590] = 683,
  [148591] = 683,
  [148592] = 683,
  [148604] = 2847,
  [148605] = 948,
  [148606] = 946,
  [148608] = 1142,
  [148616] = 683,
  [148617] = 683,
  [148618] = 683,
  [148619] = 683,
  [148620] = 683,
  [148621] = 683,
  [148622] = 683,
  [148623] = 683,
  [148624] = 683,
  [148625] = 683,
  [148626] = 683,
  [148627] = 683,
  [148628] = 683,
  [148629] = 683,
  [148630] = 683,
  [148631] = 683,
  [148632] = 683,
  [148633] = 683,
  [148634] = 683,
  [148635] = 683,
  [148636] = 683,
  [148637] = 683,
  [148638] = 683,
  [148639] = 683,
  [148640] = 683,
  [148641] = 683,
  [148642] = 683,
  [148643] = 683,
  [148644] = 683,
  [148645] = 683,
  [148646] = 683,
  [148647] = 683,
  [148648] = 683,
  [148649] = 683,
  [148650] = 683,
  [148651] = 2000,
  [148652] = 1156,
  [148653] = 2998,
  [148654] = 2904,
  [148655] = 1082,
  [148656] = 743,
  [148657] = 6864,
  [148658] = 2903,
  [148659] = 597,
  [148696] = 1943,
  [148697] = 1956,
  [148698] = 1994,
  [148699] = 2772,
  [148700] = 1943,
  [148701] = 501,
  [148702] = 1892,
  [148703] = 2778,
  [148704] = 2513,
  [148705] = 522,
  [148706] = 1641,
  [148707] = 1042,
  [148708] = 1652,
  [148709] = 1652,
  [148710] = 1237,
  [148711] = 850,
  [148712] = 657,
  [148713] = 658,
  [148714] = 840,
  [148715] = 798,
  [148716] = 769,
  [148717] = 718,
  [148718] = 563,
  [148719] = 560,
  [148720] = 683,
  [148725] = 1063,
  [148726] = 1063,
  [148729] = 683,
  [148730] = 683,
  [148731] = 507,
  [148736] = 683,
  [148737] = 683,
  [148738] = 683,
  [148739] = 683,
  [148741] = 683,
  [148742] = 683,
  [148743] = 683,
  [148744] = 683,
  [148745] = 683,
  [148746] = 683,
  [148747] = 683,
  [148748] = 683,
  [148749] = 683,
  [148750] = 683,
  [148751] = 683,
  [148752] = 683,
  [148753] = 683,
  [148754] = 683,
  [148755] = 683,
  [148756] = 683,
  [148757] = 683,
  [148758] = 683,
  [148759] = 683,
  [148760] = 683,
  [148761] = 683,
  [148762] = 683,
  [148763] = 683,
  [148764] = 683,
  [148765] = 683,
  [148766] = 683,
  [148767] = 683,
  [148768] = 683,
  [148769] = 683,
  [148770] = 683,
  [148771] = 683,
  [148772] = 683,
  [148773] = 683,
  [148774] = 683,
  [148775] = 683,
  [148804] = 683,
  [148805] = 683,
  [148806] = 724,
  [148807] = 3539,
  [148808] = 1943,
  [148809] = 1994,
  [148810] = 1956,
  [148811] = 2772,
  [148812] = 1943,
  [148822] = 1439,
  [148823] = 1439,
  [148824] = 1439,
  [148825] = 1439,
  [148826] = 1439,
  [148827] = 1439,
  [148828] = 1439,
  [148829] = 1439,
  [148830] = 1439,
  [148831] = 1439,
  [148832] = 1439,
  [148833] = 1439,
  [148840] = 2776,
  [148841] = 2345,
  [148842] = 887,
  [148843] = 1307,
  [148844] = 1314,
  [148845] = 1063,
  [148846] = 2000,
  [148847] = 501,
  [148848] = 1892,
  [148849] = 2778,
  [148850] = 2513,
  [148851] = 522,
  [148852] = 1641,
  [148853] = 1042,
  [148854] = 1652,
  [148855] = 1652,
  [148856] = 1237,
  [148857] = 850,
  [148858] = 657,
  [148859] = 658,
  [148860] = 840,
  [148861] = 798,
  [148862] = 769,
  [148863] = 718,
  [148864] = 563,
  [148865] = 560,
  [148872] = 4133,
  [148873] = 4133,
  [148874] = 4079,
  [148875] = 4110,
  [148876] = 4100,
  [148877] = 4107,
  [148878] = 4087,
  [148879] = 4082,
  [148882] = 536,
  [148883] = 624,
  [148884] = 546,
  [148885] = 524,
  [148886] = 610,
  [148887] = 671,
  [148888] = 518,
  [148889] = 625,
  [148890] = 527,
  [148891] = 543,
  [148892] = 844,
  [148893] = 630,
  [148894] = 620,
  [148895] = 526,
  [148896] = 641,
  [148897] = 632,
  [148898] = 634,
  [148899] = 779,
  [148900] = 635,
  [148901] = 637,
  [148902] = 636,
  [148903] = 640,
  [148904] = 1126,
  [148905] = 634,
  [148906] = 525,
  [148907] = 631,
  [148908] = 1040,
  [148909] = 517,
  [148910] = 2000,
  [148913] = 1007,
  [148914] = 1945,
  [148915] = 1376,
  [148916] = 2086,
  [148917] = 1462,
  [148918] = 1243,
  [148919] = 1432,
  [148920] = 3335,
  [148921] = 1916,
  [148922] = 1319,
  [148923] = 683,
  [148924] = 683,
  [148925] = 683,
  [148926] = 683,
  [148927] = 683,
  [148928] = 683,
  [148929] = 683,
  [148930] = 683,
  [148931] = 683,
  [148932] = 683,
  [148934] = 683,
  [148935] = 683,
  [148937] = 683,
  [148938] = 683,
  [148939] = 683,
  [148940] = 683,
  [148941] = 683,
  [148943] = 683,
  [148944] = 683,
  [148945] = 683,
  [148946] = 683,
  [148947] = 683,
  [148948] = 683,
  [148949] = 683,
  [148950] = 683,
  [148951] = 683,
  [148952] = 683,
  [148953] = 683,
  [148954] = 683,
  [148955] = 683,
  [148956] = 683,
  [148957] = 683,
  [148958] = 683,
  [148959] = 683,
  [148960] = 683,
  [148962] = 2776,
  [148963] = 683,
  [148964] = 683,
  [148965] = 683,
  [148968] = 900,
  [148973] = 1003,
  [148987] = 1968,
  [148997] = 624,
  [148998] = 527,
  [148999] = 632,
  [149000] = 1126,
  [149001] = 3361,
  [149002] = 3361,
  [149003] = 3361,
  [149004] = 3361,
  [149005] = 683,
  [149006] = 683,
  [149007] = 3361,
  [149008] = 3361,
  [149009] = 3361,
  [149010] = 683,
  [149011] = 683,
  [149012] = 3361,
  [149013] = 3361,
  [149014] = 3361,
  [149015] = 3361,
  [149016] = 3361,
  [149017] = 683,
  [149018] = 683,
  [149019] = 3361,
  [149020] = 3361,
  [149021] = 3361,
  [149022] = 683,
  [149023] = 1063,
  [149024] = 683,
  [149025] = 3361,
  [149026] = 973,
  [149027] = 683,
  [149028] = 683,
  [149040] = 1077,
  [149041] = 1077,
  [149042] = 1077,
  [149043] = 1077,
  [149044] = 1077,
  [149045] = 1077,
  [149046] = 1077,
  [149048] = 2969,
  [149049] = 2001,
  [149050] = 946,
  [149072] = 2776,
  [149073] = 2345,
  [149074] = 2776,
  [149075] = 2776,
  [149088] = 536,
  [149089] = 625,
  [149090] = 641,
  [149091] = 640,
  [149092] = 2079,
  [149100] = 1439,
  [149101] = 1439,
  [149102] = 1439,
  [149103] = 1439,
  [149104] = 1439,
  [149105] = 1439,
  [149106] = 3361,
  [149107] = 3361,
  [149123] = 968,
  [149125] = 1878,
  [149126] = 1878,
  [149127] = 1878,
  [149128] = 1878,
  [149129] = 683,
  [149130] = 683,
  [149131] = 683,
  [149132] = 683,
  [149133] = 683,
  [149135] = 683,
  [149136] = 683,
  [149137] = 683,
  [149138] = 683,
  [149139] = 683,
  [149140] = 683,
  [149141] = 683,
  [149142] = 683,
  [149143] = 683,
  [149144] = 683,
  [149145] = 683,
  [149146] = 683,
  [149147] = 683,
  [149148] = 683,
  [149149] = 683,
  [149150] = 683,
  [149151] = 683,
  [149152] = 683,
  [149153] = 683,
  [149154] = 683,
  [149155] = 683,
  [149156] = 683,
  [149157] = 683,
  [149158] = 683,
  [149159] = 683,
  [149160] = 683,
  [149161] = 683,
  [149162] = 683,
  [149163] = 683,
  [149164] = 683,
  [149166] = 683,
  [149167] = 683,
  [149168] = 683,
  [149169] = 683,
  [149170] = 683,
  [149171] = 683,
  [149172] = 683,
  [149173] = 683,
  [149174] = 683,
  [149175] = 683,
  [149176] = 683,
  [149177] = 683,
  [149178] = 683,
  [149179] = 683,
  [149180] = 683,
  [149181] = 683,
  [149182] = 683,
  [149183] = 683,
  [149184] = 683,
  [149195] = 683,
  [149196] = 3361,
  [149197] = 3361,
  [149198] = 3361,
  [149199] = 3361,
  [149200] = 3361,
  [149201] = 3361,
  [149202] = 3361,
  [149203] = 3361,
  [149204] = 3361,
  [149205] = 3361,
  [149206] = 3361,
  [149207] = 3361,
  [149208] = 3361,
  [149209] = 3361,
  [149212] = 605,
  [149213] = 1164,
  [149214] = 1349,
  [149215] = 2926,
  [149216] = 3820,
  [149217] = 592,
  [149220] = 973,
  [149221] = 973,
  [149222] = 973,
  [149224] = 683,
  [149225] = 601,
  [149226] = 503,
  [149227] = 502,
  [149228] = 548,
  [149234] = 744,
  [149235] = 819,
  [149236] = 925,
  [149237] = 1445,
  [149239] = 2098,
  [149240] = 2098,
  [149241] = 2090,
  [149243] = 501,
  [149244] = 505,
  [149245] = 522,
  [149246] = 907,
  [149247] = 528,
  [149248] = 1633,
  [149249] = 3220,
  [149250] = 1622,
  [149251] = 658,
  [149252] = 841,
  [149253] = 840,
  [149254] = 3210,
  [149255] = 664,
  [149256] = 683,
  [149257] = 1491,
  [149263] = 546,
  [149264] = 524,
  [149265] = 610,
  [149266] = 671,
  [149267] = 543,
  [149268] = 844,
  [149269] = 630,
  [149270] = 620,
  [149271] = 634,
  [149272] = 779,
  [149273] = 635,
  [149274] = 637,
  [149275] = 634,
  [149276] = 525,
  [149277] = 631,
  [149278] = 1040,
  [149279] = 518,
  [149280] = 526,
  [149281] = 636,
  [149282] = 517,
  [149283] = 3361,
  [149284] = 1307,
  [149285] = 1307,
  [149286] = 1314,
  [149287] = 1314,
  [149288] = 1314,
  [149289] = 840,
  [149290] = 840,
  [149291] = 1314,
  [149292] = 1314,
  [149293] = 840,
  [149294] = 840,
  [149295] = 528,
  [149296] = 528,
  [149297] = 528,
  [149298] = 840,
  [149299] = 840,
  [149300] = 528,
  [149301] = 528,
  [149302] = 528,
  [149336] = 528,
  [149355] = 1991,
  [149359] = 864,
  [149360] = 870,
  [149361] = 865,
  [149391] = 2969,
  [149392] = 968,
  [149400] = 1306,
  [149401] = 847,
  [149403] = 1307,
  [149404] = 501,
  [149405] = 505,
  [149406] = 522,
  [149407] = 907,
  [149408] = 528,
  [149409] = 1633,
  [149410] = 3220,
  [149411] = 1622,
  [149412] = 658,
  [149413] = 841,
  [149414] = 840,
  [149415] = 3210,
  [149416] = 664,
  [149417] = 2001,
  [149419] = 620,
  [149420] = 1307,
  [149424] = 1312,
  [149426] = 1178,
  [149427] = 2345,
  [149428] = 620,
  [149439] = 2776,
  [149440] = 2345,
  [149441] = 2776,
  [149442] = 2776,
  [149447] = 3257,
  [149452] = 2178,
  [149456] = 2776,
  [149850] = 3180,
  [149860] = 1233,
  [150047] = 3099,
  [150050] = 1074,
  [150051] = 2245,
  [150052] = 4242,
  [150053] = 797,
  [150054] = 692,
  [150055] = 701,
  [150056] = 695,
  [150057] = 696,
  [150058] = 693,
  [150059] = 3094,
  [150060] = 2275,
  [150061] = 2275,
  [150062] = 2275,
  [150063] = 2275,
  [150064] = 2275,
  [150065] = 2275,
  [150066] = 2275,
  [150067] = 945,
  [150068] = 945,
  [150069] = 945,
  [150070] = 945,
  [150071] = 945,
  [150072] = 2988,
  [150073] = 2994,
  [150074] = 2275,
  [150075] = 2275,
  [150076] = 2275,
  [150077] = 2275,
  [150078] = 2275,
  [150079] = 2275,
  [150080] = 2275,
  [150081] = 2275,
  [150082] = 2275,
  [150083] = 2275,
  [150084] = 2275,
  [150085] = 2275,
  [150086] = 2275,
  [150087] = 2275,
  [150088] = 2275,
  [150089] = 2275,
  [150090] = 2275,
  [150091] = 2275,
  [150092] = 2275,
  [150093] = 2275,
  [150094] = 2275,
  [150095] = 2275,
  [150096] = 2275,
  [150097] = 2275,
  [150098] = 2275,
  [150099] = 2275,
  [150100] = 2275,
  [150101] = 2275,
  [150118] = 847,
  [150119] = 5998,
  [150120] = 1075,
  [150121] = 2247,
  [150122] = 2014,
  [150123] = 6444,
  [150124] = 945,
  [150125] = 945,
  [150126] = 945,
  [150127] = 945,
  [150128] = 701,
  [150129] = 696,
  [150130] = 695,
  [150131] = 693,
  [150132] = 6725,
  [150133] = 6864,
  [150134] = 2306,
  [150135] = 2275,
  [150136] = 2673,
  [150137] = 6365,
  [150141] = 1076,
  [150142] = 2243,
  [150143] = 2054,
  [150144] = 1476,
  [150145] = 2275,
  [150146] = 6167,
  [150147] = 5779,
  [150148] = 5780,
  [150149] = 5781,
  [150150] = 5782,
  [150151] = 6489,
  [150152] = 6489,
  [150153] = 6489,
  [150154] = 6489,
  [150155] = 6864,
  [150156] = 5027,
  [150157] = 1158,
  [150158] = 4595,
  [150159] = 6177,
  [150160] = 6480,
  [150161] = 2438,
  [150162] = 2974,
  [150163] = 3388,
  [150164] = 6566,
  [150165] = 6026,
  [150167] = 6526,
  [150168] = 5837,
  [150169] = 5823,
  [150202] = 6487,
  [150203] = 6487,
  [150204] = 6487,
  [150205] = 6487,
  [150206] = 1204,
  [150207] = 6232,
  [150208] = 5896,
  [150209] = 5897,
  [150210] = 5898,
  [150211] = 5899,
  [150212] = 735,
  [150213] = 3445,
  [150214] = 6587,
  [150215] = 2275,
  [150218] = 2604,
  [150219] = 6276,
  [150220] = 4473,
  [150221] = 2633,
  [150222] = 6760,
  [150223] = 6039,
  [150224] = 3331,
  [150226] = 3201,
}

return {
  ULTIMATE_LOOT = ULTIMATE_LOOT,
  AVATAR_LOOT = AVATAR_LOOT,
  DEMIGOD_LOOT = DEMIGOD_LOOT,
  DEVICE_RECIPES = DEVICE_RECIPES,
  TRANSMUTE_ITEM_ICONS = TRANSMUTE_ITEM_ICONS,
}
end)()

local function parseBool(s)
  if not s then
    return false
  end
  s = tostring(s):lower():gsub('%s+', '')
  return s == '1' or s == 'true' or s == 'yes' or s == 'on'
end

local function loadState()
  local path = iniPath()
  local f = io.open(path, 'r')
  if f then
    for line in f:lines() do
      if not line:find('^%s*;') then
        local dk, dv = line:match('^d(%d+)%s*=%s*(%S+)')
        if dk and dv then
          enabled['d' .. dk] = parseBool(dv)
        else
          local rk, rv = line:match('^r_(.+)%s*=%s*(%S+)$')
          if rk and rv then
            enabled['r' .. rk] = parseBool(rv)
          else
            local id, v = line:match('^(%d+)%s*=%s*(%S+)')
            if id and v then
              enabled[tonumber(id)] = parseBool(v)
            end
          end
        end
      end
    end
    f:close()
  end
end

local function saveState()
  local path = iniPath()
  local f = io.open(path, 'w')
  if not f then
    statusLine = 'Could not write ' .. path
    return
  end
  f:write('; Assistant scrolls: numeric id=0|1  |  Dust: d<itemid>=0|1  |  Device recipes: r_<key>=0|1\n')
  for _, row in ipairs(TRANSMUTE_SCROLLS) do
    f:write(string.format('%d=%d\n', row.id, enabled[row.id] and 1 or 0))
  end
  if TRANSMUTE_DEVICE_DATA then
    for _, tier in ipairs({ 'ULTIMATE_LOOT', 'AVATAR_LOOT', 'DEMIGOD_LOOT' }) do
      local lst = TRANSMUTE_DEVICE_DATA[tier]
      if lst then
        for _, row in ipairs(lst) do
          local k = 'd' .. tostring(row.id)
          f:write(string.format('d%d=%d\n', row.id, enabled[k] and 1 or 0))
        end
      end
    end
    for _, rec in ipairs(TRANSMUTE_DEVICE_DATA.DEVICE_RECIPES or {}) do
      local k = 'r' .. rec.key
      f:write(string.format('r_%s=%d\n', rec.key, enabled[k] and 1 or 0))
    end
  end
  f:close()
  dirty = false
end

local function tryParseCount(pat)
  local ok, s = pcall(function()
    return mq.parse(pat)
  end)
  if not ok or s == nil then
    return 0
  end
  s = tostring(s):gsub('^%s+', ''):gsub('%s+$', '')
  if s == '' or s == 'NULL' or s == 'null' then
    return 0
  end
  return tonumber(s) or 0
end

--- When Me.Inventory scan misses an id, ${FindItemCount} / FindItem sometimes still see it.
local function countFindItemCountByNumericId(itemId)
  local id = tonumber(itemId) or 0
  if id <= 0 then
    return 0
  end
  local s = tostring(id)
  local n = tryParseCount('${FindItemCount[=' .. s .. ']}')
  if n > 0 then
    return n
  end
  n = tryParseCount('${FindItemCount[' .. s .. ']}')
  if n > 0 then
    return n
  end
  local ok, fi = pcall(function()
    return mq.TLO.FindItem('=' .. s)
  end)
  if ok and fi and fi() then
    return tonumber(fi.Stack() or 0) or 0
  end
  return 0
end

local function countFindItemCountQuoted(displayName)
  local q = displayName:gsub('"', "'")
  return tryParseCount('${FindItemCount["' .. q .. '"]}')
end

local function countFindItemCountBracket(displayName)
  local safe = displayName:gsub('%]', '')
  return tryParseCount('${FindItemCount[=' .. safe .. ']}')
end

local function countFindItemCountPartial(displayName)
  local safe = displayName:gsub('%]', '')
  return tryParseCount('${FindItemCount[' .. safe .. ']}')
end

local function countFindItemTloExact(displayName)
  local ok, item = pcall(function()
    return mq.TLO.FindItem('=' .. displayName:gsub('%]', ''))
  end)
  if not ok or not item then
    return 0
  end
  local id = tonumber(item.ID() or 0) or 0
  if id <= 0 then
    return 0
  end
  return tonumber(item.Stack() or 0) or 0
end

--- Returns total count, and the inventory string to use with /itemnotify "=<str>"
local function probeRowInventory(row)
  local variants = {}
  local seen = {}
  local function add(v)
    if v and v ~= '' and not seen[v] then
      seen[v] = true
      table.insert(variants, v)
    end
  end
  add(row.name)
  local short = row.name:match('Transmutation Recipe:%s*(.+)$')
  if short then
    add(short:match('^%s*(.-)%s*$'))
  end

  local tryOrder = {
    countFindItemCountQuoted,
    countFindItemCountBracket,
    countFindItemCountPartial,
  }

  for _, v in ipairs(variants) do
    for _, fn in ipairs(tryOrder) do
      local c = fn(v)
      if c > 0 then
        return c, v
      end
    end
    local c = countFindItemTloExact(v)
    if c > 0 then
      return c, v
    end
  end
  return 0, row.name
end

--- Device dust rows: keyed by item id (same probe strategy as scrolls, by display name)
local invCacheDust = {}
local invHandNameDust = {}

local function refreshDeviceInventoryCache()
  if not TRANSMUTE_DEVICE_DATA then
    return
  end
  for _, tier in ipairs({ 'ULTIMATE_LOOT', 'AVATAR_LOOT', 'DEMIGOD_LOOT' }) do
    local lst = TRANSMUTE_DEVICE_DATA[tier]
    if lst then
      for _, row in ipairs(lst) do
        local faux = { id = row.id, name = row.name }
        local cnt, hand = probeRowInventory(faux)
        invCacheDust[row.id] = cnt
        invHandNameDust[row.id] = hand
      end
    end
  end
end

--- Stack qty from item member (inventory_actor also checks Count / Charges).
local function getItemStackQty(it)
  if not it then
    return 0
  end
  local qty = 0
  pcall(function()
    qty = tonumber(it.Stack() or 0) or 0
  end)
  if qty <= 0 then
    pcall(function()
      if it.Count then
        qty = tonumber(it.Count() or 0) or 0
      end
    end)
  end
  if qty <= 0 then
    pcall(function()
      if it.Charges then
        qty = tonumber(it.Charges() or 0) or 0
      end
    end)
  end
  if qty <= 0 then
    qty = 1
  end
  return qty
end

--- Count leaf items (non-containers) into id map; recurse into nested bags.
--- Require it() — same validity rule as findItemLocationById (avoids bogus /itemnotify targets).
local function addItemStackToIdMap(it, t, depth)
  depth = (depth or 0) + 1
  if depth > 12 or not it or not it() then
    return
  end
  local inner = 0
  pcall(function()
    inner = tonumber(it.Container() or 0) or 0
  end)
  if inner > 0 then
    for is = 1, inner do
      local ok, innerIt = pcall(function()
        return it.Item(is)
      end)
      if ok and innerIt and innerIt() then
        addItemStackToIdMap(innerIt, t, depth)
      end
    end
    return
  end
  local id = itemNumericId(it)
  if id > 0 then
    t[id] = (t[id] or 0) + getItemStackQty(it)
  end
end

local function rebuildInvIdCountMap()
  local t = {}
  for invSlot = 23, 34 do
    local okBag, bag = pcall(function()
      return mq.TLO.Me.Inventory(invSlot)
    end)
    -- Match inventory_actor: pack() + Container() > 0 — do not require bag.ID() (some builds leave it 0).
    if okBag and bag and bag() then
      local slots = tonumber(bag.Container() or 0) or 0
      if slots > 0 then
        for bagSlot = 1, slots do
          local okIt, it = pcall(function()
            return bag.Item(bagSlot)
          end)
          if okIt and it and it() then
            addItemStackToIdMap(it, t, 0)
          end
        end
      end
    end
  end
  for invSlot = 0, 22 do
    local ok, it = pcall(function()
      return mq.TLO.Me.Inventory(invSlot)
    end)
    if ok and it and it() then
      addItemStackToIdMap(it, t, 0)
    end
  end
  invIdCount = t
  invIdCountAtMs = timeMs()
end

--- maxAgeSec <= 0: always rebuild. Else rebuild if cache older than maxAgeSec (real-time ms).
local function ensureInvIdCountMap(maxAgeSec)
  maxAgeSec = tonumber(maxAgeSec) or 0
  local nowMs = timeMs()
  if invIdCountAtMs <= 0 or maxAgeSec <= 0 or (nowMs - invIdCountAtMs) >= (maxAgeSec * 1000) then
    rebuildInvIdCountMap()
  end
end

local function refreshInventoryCache()
  invScanGen = invScanGen + 1
  invScanAt = clock()
  eqItemIconCache = {}
  for _, row in ipairs(TRANSMUTE_SCROLLS) do
    local cnt, hand = probeRowInventory(row)
    invCache[row.id] = cnt
    invHandName[row.id] = hand
  end
  refreshDeviceInventoryCache()
  rebuildInvIdCountMap()
end

local function maybeRefreshInventory()
  if not CONFIG.invLiveScan then
    return
  end
  local interval = CONFIG.invRefreshSec or 5.0
  if clock() - invScanAt >= interval then
    refreshInventoryCache()
  end
end

local function invCountForRow(row)
  return invCache[row.id] or 0
end

local function buildCategoryGroups()
  local groups = {}
  for _, cat in ipairs(CATEGORY_ORDER) do
    groups[cat] = {}
  end
  for _, row in ipairs(TRANSMUTE_SCROLLS) do
    local cat = SCROLL_CATEGORY[row.id] or 'Unknown'
    if not groups[cat] then
      groups[cat] = {}
    end
    table.insert(groups[cat], row)
  end
  return groups
end

--- /notify pairs to click "Give" on default target window (custom UIs may differ).
local TARGET_GIVE_BUTTONS = {
  { 'TargetWindow', 'TW_Give_Button' },
  { 'TargetWindow', 'TW_Give' },
  { 'TargetWindow', 'Give_Button' },
}

local function tryTargetWindowGiveButtons()
  if not CONFIG.tryTargetWindowGive then
    return
  end
  for _, pair in ipairs(TARGET_GIVE_BUTTONS) do
    pcall(function()
      mq.cmdf('/notify %s %s leftmouseup', pair[1], pair[2])
    end)
  end
end

--- Same slot math as GiveIt: FindItem.ItemSlot / ItemSlot2 -> MQ `in packN M` (bag slot N, slot M inside that bag).
local function findItemNotifyTokenFromFindItemSlots(exactName)
  local safe = exactName:gsub('%]', '')
  local fi = nil
  pcall(function()
    fi = mq.TLO.FindItem('=' .. safe)
  end)
  if not fi or not fi() then
    local q = exactName:gsub('"', "'")
    pcall(function()
      fi = mq.TLO.FindItem('"' .. q .. '"')
    end)
  end
  if not fi or not fi() then
    return nil
  end
  local id = tonumber(fi.ID() or 0) or 0
  if id <= 0 then
    return nil
  end
  local itemSlot = tonumber(fi.ItemSlot() or -1) or -1
  local itemSlot2 = tonumber(fi.ItemSlot2() or -1) or -1
  if itemSlot < 0 then
    return nil
  end
  local pickup1 = itemSlot - 22
  local pickup2 = itemSlot2 + 1
  if pickup1 >= 1 and pickup1 <= 12 and pickup2 >= 1 then
    return string.format('in pack%d %d', pickup1, pickup2)
  end
  if itemSlot >= 0 and itemSlot <= 22 then
    return tostring(itemSlot)
  end
  return nil
end

--- Macro ${FindItem[=name]} expands to the slot token /itemnotify expects (includes bag path).
local function findItemNotifyToken(exactName)
  local safe = exactName:gsub('%]', '')
  local ok, parsed = pcall(function()
    return mq.parse('${FindItem[=' .. safe .. ']}')
  end)
  if ok and parsed and parsed ~= '' and parsed ~= 'NULL' then
    return tostring(parsed)
  end
  ok, parsed = pcall(function()
    local q = exactName:gsub('"', "'")
    return mq.parse('${FindItem["' .. q .. '"]}')
  end)
  if ok and parsed and parsed ~= '' and parsed ~= 'NULL' then
    return tostring(parsed)
  end
  return nil
end

--- Slot path for /itemnotify when FindItem parse fails (mirrors EZInventory inventory_actor layout).
local function invNormName(s)
  return (tostring(s or ''):lower()):gsub('^%s+', ''):gsub('%s+$', '')
end

local function findItemNotifyTokenFromInventoryScan(exactName)
  if not CONFIG.useInventorySlotScanFallback then
    return nil
  end
  local want = invNormName(exactName)
  -- EZInventory fast snapshot: Me.Inventory(0..22) general, 23..34 bags
  for invSlot = 0, 22 do
    local ok, it = pcall(function()
      return mq.TLO.Me.Inventory(invSlot)
    end)
    if ok and it and it() and tonumber(it.ID() or 0) > 0 then
      local cont = tonumber(it.Container() or 0) or 0
      if cont == 0 and invNormName(it.Name() or '') == want then
        return tostring(invSlot)
      end
    end
  end
  for invSlot = 23, 34 do
    local okBag, bagInv = pcall(function()
      return mq.TLO.Me.Inventory(invSlot)
    end)
    if okBag and bagInv and bagInv() then
      local topId = tonumber(bagInv.ID() or 0) or 0
      if topId > 0 then
        local cont = tonumber(bagInv.Container() or 0) or 0
        if cont == 0 and invNormName(bagInv.Name() or '') == want then
          local pidx = invSlot - 22
          if pidx >= 1 and pidx <= 12 then
            return string.format('in pack%d 1', pidx)
          end
        end
      end
      local slots = tonumber(bagInv.Container() or 0) or 0
      if slots > 0 then
        for bagSlot = 1, slots do
          local okIt, bit = pcall(function()
            return bagInv.Item(bagSlot)
          end)
          if okIt and bit and bit() and tonumber(bit.ID() or 0) > 0 then
            if invNormName(bit.Name() or '') == want then
              local pidx = invSlot - 22
              if pidx >= 1 and pidx <= 12 then
                return string.format('in pack%d %d', pidx, bagSlot)
              end
            end
          end
        end
      end
    end
  end
  return nil
end

--- ─────────────────────────────────────────────────────────────────────────
--- TARGETED BAG OPEN + PICKUP HELPERS
---
--- Strategy (one item at a time):
---   1. Scan inventory to find EXACTLY which pack (1-12) and slot the item is in.
---   2. Right-click that specific bag to open it (non-blocking — phase machine waits).
---   3. After the bag-open delay, /itemnotify in packN M leftmouseup to lift item.
---   4. After pickup delay, verify cursor has item before proceeding to give.
--- ─────────────────────────────────────────────────────────────────────────

--- Deep inventory scan: returns { packIdx=N, slotIdx=M, token="in packN M" }
--- packIdx 1-12 = bag slots (Me.Inventory 23-34). slotIdx = slot inside bag (1-based).
--- Returns nil if item not found anywhere.
local function findItemLocation(exactName)
  local want = invNormName(exactName)

  -- Try MQ TLO FindItem first (fastest path, uses MQ index)
  local fi = nil
  pcall(function() fi = mq.TLO.FindItem('=' .. exactName:gsub('%]','')) end)
  if not fi or not fi() then
    pcall(function()
      fi = mq.TLO.FindItem('"' .. exactName:gsub('"',"'") .. '"')
    end)
  end
  if fi and fi() and tonumber(fi.ID() or 0) > 0 then
    local slot  = tonumber(fi.ItemSlot()  or -1) or -1
    local slot2 = tonumber(fi.ItemSlot2() or -1) or -1
    if slot >= 23 and slot <= 34 then
      local pidx = slot - 22          -- 1-based pack index
      local sidx = slot2 >= 0 and (slot2 + 1) or 1
      return {
        packIdx = pidx,
        slotIdx = sidx,
        token   = string.format('in pack%d %d', pidx, sidx),
        source  = 'FindItem TLO',
      }
    elseif slot >= 0 and slot <= 22 then
      -- Item is in a top-level (non-bag) slot — no bag open needed
      return {
        packIdx = nil,
        slotIdx = slot,
        token   = tostring(slot),
        source  = 'top-level slot',
      }
    end
  end

  -- Fallback: brute-force scan Me.Inventory bags 23-34
  for invSlot = 23, 34 do
    local okBag, bag = pcall(function() return mq.TLO.Me.Inventory(invSlot) end)
    if okBag and bag and bag() then
      local slots = tonumber(bag.Container() or 0) or 0
      if slots > 0 then
        for bagSlot = 1, slots do
          local okIt, it = pcall(function() return bag.Item(bagSlot) end)
          if okIt and it and it() and itemNumericId(it) > 0 then
            if invNormName(it.Name() or '') == want then
              local pidx = invSlot - 22
              return {
                packIdx = pidx,
                slotIdx = bagSlot,
                token   = string.format('in pack%d %d', pidx, bagSlot),
                source  = 'inventory scan',
              }
            end
          end
        end
      end
    end
  end

  -- Also check top-level slots 0-22
  for invSlot = 0, 22 do
    local ok, it = pcall(function() return mq.TLO.Me.Inventory(invSlot) end)
    if ok and it and it() and tonumber(it.ID() or 0) > 0 then
      if invNormName(it.Name() or '') == want then
        return {
          packIdx = nil,
          slotIdx = invSlot,
          token   = tostring(invSlot),
          source  = 'top-level scan',
        }
      end
    end
  end

  return nil
end

--- Locate first stack of item id (numeric) for device dust / recipe mats.
local function findItemLocationById(wantId)
  wantId = tonumber(wantId) or 0
  if wantId <= 0 then
    return nil
  end
  for invSlot = 23, 34 do
    local okBag, bag = pcall(function()
      return mq.TLO.Me.Inventory(invSlot)
    end)
    if okBag and bag and bag() then
      local slots = tonumber(bag.Container() or 0) or 0
      if slots > 0 then
        for bagSlot = 1, slots do
          local okIt, it = pcall(function()
            return bag.Item(bagSlot)
          end)
          if okIt and it and it() and itemNumericId(it) == wantId then
            local pidx = invSlot - 22
            return {
              packIdx = pidx,
              slotIdx = bagSlot,
              token = string.format('in pack%d %d', pidx, bagSlot),
              source = 'id scan bag',
            }
          end
        end
      end
    end
  end
  for invSlot = 0, 22 do
    local ok, it = pcall(function()
      return mq.TLO.Me.Inventory(invSlot)
    end)
    if ok and it and it() and itemNumericId(it) == wantId then
      return {
        packIdx = nil,
        slotIdx = invSlot,
        token = tostring(invSlot),
        source = 'id scan top',
      }
    end
  end
  return nil
end

local function countItemIdInInventoryCached(wantId)
  wantId = tonumber(wantId) or 0
  if wantId <= 0 then
    return 0
  end
  local c = invIdCount[wantId] or 0
  if c > 0 then
    return c
  end
  return countFindItemCountByNumericId(wantId)
end

local function resolveItemNameById(itemId)
  local id = tonumber(itemId) or 0
  if id <= 0 then
    return '#0'
  end
  for invSlot = 23, 34 do
    local okBag, bag = pcall(function()
      return mq.TLO.Me.Inventory(invSlot)
    end)
    if okBag and bag and bag() then
      local slots = tonumber(bag.Container() or 0) or 0
      if slots > 0 then
        for bagSlot = 1, slots do
          local okIt, it = pcall(function()
            return bag.Item(bagSlot)
          end)
          if okIt and it and it() and itemNumericId(it) == id then
            local okn, n = pcall(function()
              return it.Name()
            end)
            if okn and n and tostring(n) ~= '' then
              return tostring(n)
            end
          end
        end
      end
    end
  end
  for invSlot = 0, 22 do
    local ok, it = pcall(function()
      return mq.TLO.Me.Inventory(invSlot)
    end)
    if ok and it and it() and itemNumericId(it) == id then
      local okn, n = pcall(function()
        return it.Name()
      end)
      if okn and n and tostring(n) ~= '' then
        return tostring(n)
      end
    end
  end
  return '#' .. tostring(id)
end

--- Icon from first bag/top slot holding this id (FindItem often has no Icon until item is seen).
local function resolveItemIconFromInventoryIdWalk(wantId)
  wantId = tonumber(wantId) or 0
  if wantId <= 0 then
    return 0
  end
  for invSlot = 23, 34 do
    local okBag, bag = pcall(function()
      return mq.TLO.Me.Inventory(invSlot)
    end)
    if okBag and bag and bag() then
      local slots = tonumber(bag.Container() or 0) or 0
      if slots > 0 then
        for bagSlot = 1, slots do
          local okIt, it = pcall(function()
            return bag.Item(bagSlot)
          end)
          if okIt and it and it() and itemNumericId(it) == wantId then
            local okic, ic = pcall(function()
              return it.Icon()
            end)
            if okic and ic then
              local n = tonumber(ic) or 0
              if n > 0 then
                return n
              end
            end
          end
        end
      end
    end
  end
  for invSlot = 0, 22 do
    local ok, it = pcall(function()
      return mq.TLO.Me.Inventory(invSlot)
    end)
    if ok and it and it() and itemNumericId(it) == wantId then
      local okic, ic = pcall(function()
        return it.Icon()
      end)
      if okic and ic then
        local n = tonumber(ic) or 0
        if n > 0 then
          return n
        end
      end
    end
  end
  return 0
end

local function tryParseItemIcon(pat)
  local ok, s = pcall(function()
    return mq.parse(pat)
  end)
  if not ok or s == nil then
    return 0
  end
  s = tostring(s):gsub('^%s+', ''):gsub('%s+$', '')
  if s == '' or s == 'NULL' or s == 'null' then
    return 0
  end
  return tonumber(s) or 0
end

--- One pass over mats: min stacks (= full sets) + per-id string (header + row always match).
local function recipeMatAggregates(rec)
  local minc = nil
  local parts = {}
  for _, mid in ipairs(rec.mats) do
    local c = countItemIdInInventoryCached(mid)
    if minc == nil or c < minc then
      minc = c
    end
    table.insert(parts, string.format('%s:%d', tostring(mid), c))
  end
  return minc or 0, table.concat(parts, '  ')
end

local function recipeInventoryMinCountFromMap(rec)
  return select(1, recipeMatAggregates(rec))
end

--- Item icon atlas (UltDev/EZInventory): A_DragItem + SetTextureCell(Icon() - 500).
local EQ_ITEM_ICON_ATLAS_OFFSET = 500
local transmuteAnimItems ---@type userdata|nil|false

local function ensureTransmuteItemAnim()
  if transmuteAnimItems == false then
    return nil
  end
  if transmuteAnimItems ~= nil then
    return transmuteAnimItems
  end
  local ok, a = pcall(function()
    return mq.FindTextureAnimation('A_DragItem')
  end)
  if ok and a then
    transmuteAnimItems = a
    return a
  end
  transmuteAnimItems = false
  return nil
end

local function eqItemIconCacheKey(itemId, displayName)
  if itemId and tonumber(itemId) and tonumber(itemId) > 0 then
    return 'i' .. tostring(itemId)
  end
  return 'n' .. tostring(displayName or '')
end

--- Returns EQ item Icon() index for texture atlas, or 0 if unknown.
--- 1) Embedded TRANSMUTE_ITEM_ICONS table (PEQ seed — works with 0 in inventory).
--- 2) mq.TLO.Item / FindItem / parse / bag scan.
local function resolveEqItemIcon(itemId, displayName)
  local ck = eqItemIconCacheKey(itemId, displayName)
  local cached = eqItemIconCache[ck]
  if cached ~= nil then
    return cached
  end
  local icon = 0
  if itemId and tonumber(itemId) and tonumber(itemId) > 0 then
    local idNum = tonumber(itemId)
    local pack = TRANSMUTE_DEVICE_DATA and TRANSMUTE_DEVICE_DATA.TRANSMUTE_ITEM_ICONS
    if pack then
      local sc = pack[idNum]
      if sc and tonumber(sc) and tonumber(sc) > 0 then
        icon = tonumber(sc)
      end
    end
    local sid = tostring(idNum)
    if icon <= 0 then
      pcall(function()
        local it = mq.TLO.Item(idNum)
        if it and it() then
          icon = tonumber(it.Icon()) or 0
        end
      end)
    end
    if icon <= 0 then
      pcall(function()
        local it = mq.TLO.Item(sid)
        if it and it() then
          icon = tonumber(it.Icon()) or 0
        end
      end)
    end
    if icon <= 0 then
      icon = tryParseItemIcon('${Item[' .. sid .. '].Icon}')
    end
    if icon <= 0 then
      pcall(function()
        local fi = mq.TLO.FindItem('=' .. sid)
        if fi and fi() then
          icon = tonumber(fi.Icon()) or 0
        end
      end)
    end
    if icon <= 0 then
      icon = tryParseItemIcon('${FindItem[=' .. sid .. '].Icon}')
    end
    if icon <= 0 then
      icon = tryParseItemIcon('${FindItem[' .. sid .. '].Icon}')
    end
    if icon <= 0 then
      icon = resolveItemIconFromInventoryIdWalk(idNum)
    end
  end
  if icon <= 0 and displayName and displayName ~= '' then
    local safe = displayName:gsub('%]', ''):gsub('=', '')
    pcall(function()
      local it = mq.TLO.Item(safe)
      if it and it() then
        icon = tonumber(it.Icon()) or 0
      end
    end)
    if icon <= 0 then
      pcall(function()
        local fi = mq.TLO.FindItem('=' .. safe)
        if fi and fi() then
          icon = tonumber(fi.Icon()) or 0
        end
      end)
    end
    if icon <= 0 then
      icon = tryParseItemIcon('${FindItem[=' .. safe .. '].Icon}')
    end
    if icon <= 0 then
      icon = tryParseItemIcon('${Item[=' .. safe .. '].Icon}')
    end
  end
  eqItemIconCache[ck] = icon
  return icon
end

local function drawTransmuteItemIcon(eqIconId, buttonId, tooltipLines, iconSize)
  iconSize = tonumber(iconSize) or 22
  local lines = tooltipLines
  if type(lines) == 'string' then
    lines = { lines }
  end
  local cx, cy = ImGui.GetCursorPos()
  local anim = ensureTransmuteItemAnim()
  local drew = false
  if anim and eqIconId and tonumber(eqIconId) and tonumber(eqIconId) > 0 then
    local cell = tonumber(eqIconId) - EQ_ITEM_ICON_ATLAS_OFFSET
    if cell >= 0 then
      anim:SetTextureCell(cell)
      ImGui.DrawTextureAnimation(anim, iconSize, iconSize)
      drew = true
    end
  end
  if not drew then
    -- Empty slot (id still in hover tooltip — avoid drawing text here; it clipped with SameLine rows)
    ImGui.Dummy(iconSize, iconSize)
  end
  ImGui.SetCursorPos(cx, cy)
  ImGui.PushStyleColor(ImGuiCol.Button, 0, 0, 0, 0)
  ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 0, 0.35, 0, 0.25)
  ImGui.PushStyleColor(ImGuiCol.ButtonActive, 0, 0.35, 0, 0.35)
  ImGui.Button('##' .. tostring(buttonId), iconSize, iconSize)
  ImGui.PopStyleColor(3)
  if lines and #lines > 0 and ImGui.IsItemHovered() then
    ImGui.BeginTooltip()
    for _, ln in ipairs(lines) do
      if ln and ln ~= '' then
        ImGui.TextUnformatted(ln)
      end
    end
    ImGui.EndTooltip()
  end
end

--- Check whether a specific bag window (by pack index 1-12) is currently open.
local function bagWindowOpen(packIdx)
  local wname = string.format('BagWnd%d', packIdx - 1)   -- BagWnd0 = pack1
  local ok, o = pcall(function() return mq.TLO.Window(wname).Open() end)
  if ok and o then return true end
  -- Some clients name them Pack1..Pack12
  local wname2 = string.format('Pack%d', packIdx)
  ok, o = pcall(function() return mq.TLO.Window(wname2).Open() end)
  return ok and o
end

--- Right-click the equipped bag container to open its window (non-blocking).
local function openBagWindow(packIdx)
  -- /itemnotify in packN rightmouseup = right-click the bag container itself
  pcall(function()
    mq.cmdf('/itemnotify in pack%d rightmouseup', packIdx)
  end)
end

--- Left-click pick up an item already located at packIdx/slotIdx.
local function fireItemPickup(token)
  pcall(function()
    -- Force stack-split behavior on pickup; plain leftmouseup can grab the whole stack
    -- on some UIs/clients, which leads to x100 hand-ins.
    mq.cmdf('/shiftkey /itemnotify %s leftmouseup', token)
  end)
end

--- Check whether the player cursor is holding an item.
local function cursorHasItem()
  local ok, v = pcall(function() return mq.TLO.Cursor() end)
  if not ok or v == nil then return false end
  local s = tostring(v)
  return s ~= '' and s ~= 'NULL' and s ~= '0'
end

--- Cursor stack size (best-effort). Returns 0 when cursor has no item.
local function cursorItemQty()
  local ok, cur = pcall(function()
    return mq.TLO.Cursor()
  end)
  if not ok or not cur then
    return 0
  end

  local qty = 0
  local okStack, stack = pcall(function()
    return cur.Stack()
  end)
  if okStack then
    qty = tonumber(stack or 0) or 0
  end
  if qty <= 0 then
    local okCount, cnt = pcall(function()
      return cur.Count()
    end)
    if okCount then
      qty = tonumber(cnt or 0) or 0
    end
  end
  if qty <= 0 then
    local okCharges, ch = pcall(function()
      return cur.Charges()
    end)
    if okCharges then
      qty = tonumber(ch or 0) or 0
    end
  end
  if qty <= 0 and cursorHasItem() then
    qty = 1
  end
  return qty
end

--- Resolve full item location for the current hand-in name.
--- Also tries the short name (after "Transmutation Recipe: ") as fallback.
local function resolvePickupToken(exactHandName)
  local loc = findItemLocation(exactHandName)
  if not loc then
    local short = exactHandName:match('Transmutation Recipe:%s*(.+)$')
    if short then
      loc = findItemLocation(short:match('^%s*(.-)%s*$'))
    end
  end
  -- Return the location table (or nil) — callers use loc.token + loc.packIdx
  return loc
end


local GIVE_WND_NAMES = { 'GiveWnd', 'givewnd', 'GIVEWND' }

local function giveWndOpen()
  for _, wname in ipairs(GIVE_WND_NAMES) do
    local ok, o = pcall(function()
      return mq.TLO.Window(wname).Open()
    end)
    if ok and o then
      return true
    end
  end
  return false
end

local function abortTurnin(msg)
  TI.active = false
  TI.phase = 0
  TI.queue = {}
  TI.currentName = nil
  TI.giveTries = 0
  TI.p1sub = 0
  TI.p2sub = 0
  TI.resolvedToken = nil
  TI.invInventoryPrimed = false
  TI.invOpenWaitTries = 0
  TI.invFallbackKeyDone = false
  TI.pickupHandName = nil
  TI.p3tries = 0
  TI.tradeTarget = 'assistant'
  TI.recipePhase = 0
  TI.recipeMatIdx = 1
  TI.recipeEntry = nil
  TI.sbPhase = 0
  TI.sbIdx = 1
  TI.sbIds = nil
  TI.qtyWndStuck = 0
  statusLine = msg or 'Aborted.'
end

local function popQueue()
  table.remove(TI.queue, 1)
  TI.currentName = nil
  TI.giveTries = 0
  TI.p2sub = 0
  TI.resolvedToken = nil
  TI.pickupHandName = nil
  TI.p3tries = 0
  TI.sbPhase = 0
  TI.sbIdx = 1
  TI.sbIds = nil
  if #TI.queue == 0 then
    TI.active = false
    TI.phase = 0
    statusLine = 'Done.'
  else
    -- Go back to phase 0 each time so the NPC is re-targeted and validated
    -- between every item hand-in (prevents stale target causing failed gives).
    TI.phase = 0
    TI.p1sub = 0
    TI.invOpenWaitTries = 0
    TI.invInventoryPrimed = true  -- inventory already open; skip DoOpen wait
    TI.nextAt = clock() + 0.25
    statusLine = string.format('Next item (%d left)...', #TI.queue)
  end
end

--- Pack flat scroll ids into scroll / scroll_batch queue entries (assistant Give batching).
local function scrollFlatToQueue(flat)
  local maxPer = tonumber(CONFIG.assistantScrollsPerGive or 4) or 4
  if maxPer < 1 then
    maxPer = 1
  end
  local q = {}
  local i = 1
  while i <= #flat do
    local batch = {}
    for _ = 1, maxPer do
      if flat[i] then
        table.insert(batch, flat[i])
        i = i + 1
      end
    end
    if #batch == 0 then
      break
    end
    if #batch == 1 then
      table.insert(q, { kind = 'scroll', id = batch[1] })
    else
      table.insert(q, { kind = 'scroll_batch', ids = batch })
    end
  end
  return q
end

local function buildAssistantQueue()
  local flat = {}
  for _, row in ipairs(TRANSMUTE_SCROLLS) do
    if enabled[row.id] then
      local c = invCountForRow(row)
      for _ = 1, c do
        table.insert(flat, row.id)
      end
    end
  end
  return scrollFlatToQueue(flat)
end

--- Assistant: one CollapsingHeader category only (Hand in on that section).
local function buildAssistantQueueForCategory(cat)
  local groups = buildCategoryGroups()
  local flat = {}
  for _, row in ipairs(groups[cat] or {}) do
    if enabled[row.id] then
      local c = invCountForRow(row)
      for _ = 1, c do
        table.insert(flat, row.id)
      end
    end
  end
  return scrollFlatToQueue(flat)
end

local function buildDustQueue(lootTable)
  local q = {}
  if not lootTable then
    return q
  end
  for _, row in ipairs(lootTable) do
    local k = 'd' .. tostring(row.id)
    if enabled[k] then
      local c = invCacheDust[row.id] or 0
      if not dustInventoryOnly or c > 0 then
        for _ = 1, c do
          table.insert(q, { kind = 'dust', itemId = row.id, name = row.name })
        end
      end
    end
  end
  return q
end

local function buildRecipeQueue()
  local q = {}
  if not TRANSMUTE_DEVICE_DATA or not TRANSMUTE_DEVICE_DATA.DEVICE_RECIPES then
    return q
  end
  -- Caller startTurnin() runs refreshInventoryCache() first (rebuilds invIdCount).
  for _, rec in ipairs(TRANSMUTE_DEVICE_DATA.DEVICE_RECIPES) do
    local k = 'r' .. rec.key
    if enabled[k] then
      local minc = recipeInventoryMinCountFromMap(rec)
      if minc >= 1 then
        local matNames = {}
        for _, mid in ipairs(rec.mats) do
          table.insert(matNames, resolveItemNameById(mid))
        end
        for _ = 1, minc do
          table.insert(q, {
            kind = 'recipe',
            key = rec.key,
            name = rec.name,
            mats = rec.mats,
            matNames = matNames,
          })
        end
      end
    end
  end
  return q
end

--- Device recipes: one category (matches CollapsingHeader / CATEGORY_ORDER).
local function buildRecipeQueueForCategory(cat)
  local q = {}
  if not TRANSMUTE_DEVICE_DATA or not TRANSMUTE_DEVICE_DATA.DEVICE_RECIPES then
    return q
  end
  for _, rec in ipairs(TRANSMUTE_DEVICE_DATA.DEVICE_RECIPES) do
    if (rec.category or 'Unknown') == cat then
      local k = 'r' .. rec.key
      if enabled[k] then
        local minc = recipeInventoryMinCountFromMap(rec)
        if minc >= 1 then
          local matNames = {}
          for _, mid in ipairs(rec.mats) do
            table.insert(matNames, resolveItemNameById(mid))
          end
          for _ = 1, minc do
            table.insert(q, {
              kind = 'recipe',
              key = rec.key,
              name = rec.name,
              mats = rec.mats,
              matNames = matNames,
            })
          end
        end
      end
    end
  end
  return q
end

--- One device recipe row (ignores Use checkbox — requires full mat set in inventory).
local function buildSingleRecipeQueue(recKey)
  local q = {}
  if not TRANSMUTE_DEVICE_DATA or not TRANSMUTE_DEVICE_DATA.DEVICE_RECIPES then
    return q
  end
  local rec = nil
  for _, r in ipairs(TRANSMUTE_DEVICE_DATA.DEVICE_RECIPES) do
    if r.key == recKey then
      rec = r
      break
    end
  end
  if not rec then
    return q
  end
  local minc = recipeInventoryMinCountFromMap(rec)
  if minc < 1 then
    return q
  end
  local matNames = {}
  for _, mid in ipairs(rec.mats) do
    table.insert(matNames, resolveItemNameById(mid))
  end
  for _ = 1, minc do
    table.insert(q, {
      kind = 'recipe',
      key = rec.key,
      name = rec.name,
      mats = rec.mats,
      matNames = matNames,
    })
  end
  return q
end

--- One assistant scroll id — all copies in inventory (ignores row checkbox).
local function buildSingleAssistantQueue(scrollId)
  local id = tonumber(scrollId) or 0
  if id <= 0 then
    return {}
  end
  local row = nil
  for _, r in ipairs(TRANSMUTE_SCROLLS) do
    if tonumber(r.id) == id then
      row = r
      break
    end
  end
  if not row then
    return {}
  end
  local c = invCountForRow(row)
  if c < 1 then
    return {}
  end
  local flat = {}
  for _ = 1, c do
    table.insert(flat, id)
  end
  return scrollFlatToQueue(flat)
end

--- One dust loot id — all copies in inventory (ignores row checkbox).
local function buildSingleDustQueue(itemId, name)
  local id = tonumber(itemId) or 0
  if id <= 0 then
    return {}
  end
  local c = invCacheDust[id] or 0
  if c < 1 then
    return {}
  end
  local q = {}
  local nm = name or ('id ' .. tostring(id))
  for _ = 1, c do
    table.insert(q, { kind = 'dust', itemId = id, name = nm })
  end
  return q
end

--- When Run is clicked but nothing is queued: explain why (esp. recipes = need every mat id).
local function recipeRunEmptyExplanation()
  if not TRANSMUTE_DEVICE_DATA or not TRANSMUTE_DEVICE_DATA.DEVICE_RECIPES then
    return 'Device data missing.'
  end
  local anyOn = false
  local lines = {}
  for _, rec in ipairs(TRANSMUTE_DEVICE_DATA.DEVICE_RECIPES) do
    local k = 'r' .. rec.key
    if enabled[k] then
      anyOn = true
      local minc = recipeInventoryMinCountFromMap(rec)
      if minc < 1 then
        local worstId, worstC = nil, math.huge
        for _, mid in ipairs(rec.mats) do
          local c = countItemIdInInventoryCached(mid)
          if c < worstC then
            worstC = c
            worstId = mid
          end
        end
        table.insert(
          lines,
          string.format('%s: blocked at id %s (have %d)', rec.name, tostring(worstId), worstC)
        )
      end
    end
  end
  if not anyOn then
    return 'No recipe checkboxes are on — enable one or more, then Run.'
  end
  if #lines == 0 then
    return 'Internal: toggles on but counts think craftable — click Rescan inventory and Run again.'
  end
  local j = math.min(3, #lines)
  local msg = table.concat(lines, ' — ', 1, j) .. (#lines > j and ' …' or '')
  if msg:find('150051', 1, true) then
    msg = msg .. ' | 150051=Arcane Crystal (not 150050 dust).'
  end
  return msg
end

--- Same as recipeRunEmptyExplanation but only recipes in `cat` (per-section Hand in).
local function recipeRunEmptyExplanationForCategory(cat)
  if not TRANSMUTE_DEVICE_DATA or not TRANSMUTE_DEVICE_DATA.DEVICE_RECIPES then
    return 'Device data missing.'
  end
  local anyOn = false
  local lines = {}
  for _, rec in ipairs(TRANSMUTE_DEVICE_DATA.DEVICE_RECIPES) do
    if (rec.category or 'Unknown') == cat then
      local k = 'r' .. rec.key
      if enabled[k] then
        anyOn = true
        local minc = recipeInventoryMinCountFromMap(rec)
        if minc < 1 then
          local worstId, worstC = nil, math.huge
          for _, mid in ipairs(rec.mats) do
            local c = countItemIdInInventoryCached(mid)
            if c < worstC then
              worstC = c
              worstId = mid
            end
          end
          table.insert(
            lines,
            string.format('%s: blocked at id %s (have %d)', rec.name, tostring(worstId), worstC)
          )
        end
      end
    end
  end
  if not anyOn then
    return 'No recipe checkboxes are on in this section — enable one or more, then Hand in.'
  end
  if #lines == 0 then
    return 'Internal: toggles on but counts think craftable — click Rescan inventory and try again.'
  end
  local j = math.min(3, #lines)
  return table.concat(lines, ' — ', 1, j) .. (#lines > j and ' …' or '')
end

--- /echo inventory id scan (debug): what MQ sees in bags + top slots vs recipe mat ids.
local function dumpInventoryIdsToEcho()
  rebuildInvIdCountMap()
  pcall(function()
    mq.cmd('/echo [Transmute] --- inventory id dump (bags 1-12 + slots 0-22) ---')
  end)
  local n = 0
  local function oneLine(label, id, qty, rawName)
    if n >= 48 then
      return
    end
    local nm = tostring(rawName or ''):gsub('[^%w%s%-%._]', '?')
    if #nm > 40 then
      nm = nm:sub(1, 37) .. '...'
    end
    pcall(function()
      mq.cmd(string.format('/echo [Transmute] %s id=%d qty=%d %s', label, id, qty, nm))
    end)
    n = n + 1
  end
  for invSlot = 23, 34 do
    local okBag, bag = pcall(function()
      return mq.TLO.Me.Inventory(invSlot)
    end)
    if okBag and bag and bag() then
      local slots = tonumber(bag.Container() or 0) or 0
      if slots > 0 then
        for bagSlot = 1, slots do
          local okIt, it = pcall(function()
            return bag.Item(bagSlot)
          end)
          if okIt and it and it() then
            local id = itemNumericId(it)
            if id > 0 then
              local nm = ''
              pcall(function()
                nm = it.Name() or ''
              end)
              oneLine(string.format('pack%d slot%d', invSlot - 22, bagSlot), id, getItemStackQty(it), nm)
            end
          end
        end
      end
    end
  end
  for invSlot = 0, 22 do
    local ok, it = pcall(function()
      return mq.TLO.Me.Inventory(invSlot)
    end)
    if ok and it and it() then
      local id = itemNumericId(it)
      if id > 0 then
        local nm = ''
        pcall(function()
          nm = it.Name() or ''
        end)
        oneLine(string.format('top slot %d', invSlot), id, getItemStackQty(it), nm)
      end
    end
  end
  pcall(function()
    mq.cmd('/echo [Transmute] --- end dump ---')
  end)
  statusLine = string.format('Dumped %d lines to MQ chat (compare ids to recipe per-id:).', n)
end

--- opts.tab: override current uiTab (assistant | dust_u | dust_a | dust_d | recipes).
--- opts.category: limit assistant or recipes queue to one CollapsingHeader section (CATEGORY_ORDER label).
--- opts.singleRecipeKey / singleAssistantScrollId / singleDustItemId (+ singleDustName): one row only; ignores checkboxes.
local function startTurnin(opts)
  opts = type(opts) == 'table' and opts or {}
  local tab = opts.tab or uiTab
  local onlyCat = opts.category
  local singleRecipeKey = opts.singleRecipeKey
  local singleAssistantScrollId = opts.singleAssistantScrollId
  local singleDustItemId = opts.singleDustItemId
  local singleDustName = opts.singleDustName

  if TI.active then
    statusLine = 'Already running.'
    return
  end
  refreshInventoryCache()
  TI.queue = {}
  TI.tradeTarget = 'assistant'

  if singleRecipeKey then
    if not TRANSMUTE_DEVICE_DATA then
      statusLine = 'Embedded device data missing or invalid. Rebuild this script from source data.'
      return
    end
    TI.queue = buildSingleRecipeQueue(singleRecipeKey)
    TI.tradeTarget = 'device'
    tab = 'recipes'
  elseif singleAssistantScrollId then
    TI.queue = buildSingleAssistantQueue(singleAssistantScrollId)
    TI.tradeTarget = 'assistant'
    tab = 'assistant'
  elseif singleDustItemId then
    TI.queue = buildSingleDustQueue(singleDustItemId, singleDustName)
    TI.tradeTarget = 'device'
  elseif tab == 'assistant' then
    if onlyCat then
      TI.queue = buildAssistantQueueForCategory(onlyCat)
    else
      TI.queue = buildAssistantQueue()
    end
    TI.tradeTarget = 'assistant'
  elseif tab == 'dust_u' then
    if not TRANSMUTE_DEVICE_DATA then
      statusLine = 'Embedded device data missing or invalid. Rebuild this script from source data.'
      return
    end
    TI.queue = buildDustQueue(TRANSMUTE_DEVICE_DATA.ULTIMATE_LOOT)
    TI.tradeTarget = 'device'
  elseif tab == 'dust_a' then
    if not TRANSMUTE_DEVICE_DATA then
      statusLine = 'Embedded device data missing or invalid. Rebuild this script from source data.'
      return
    end
    TI.queue = buildDustQueue(TRANSMUTE_DEVICE_DATA.AVATAR_LOOT)
    TI.tradeTarget = 'device'
  elseif tab == 'dust_d' then
    if not TRANSMUTE_DEVICE_DATA then
      statusLine = 'Embedded device data missing or invalid. Rebuild this script from source data.'
      return
    end
    TI.queue = buildDustQueue(TRANSMUTE_DEVICE_DATA.DEMIGOD_LOOT)
    TI.tradeTarget = 'device'
  elseif tab == 'recipes' then
    if not TRANSMUTE_DEVICE_DATA then
      statusLine = 'Embedded device data missing or invalid. Rebuild this script from source data.'
      return
    end
    if onlyCat then
      TI.queue = buildRecipeQueueForCategory(onlyCat)
    else
      TI.queue = buildRecipeQueue()
    end
    TI.tradeTarget = 'device'
  else
    statusLine = 'Unknown tab.'
    return
  end

  if #TI.queue == 0 then
    if singleRecipeKey then
      statusLine = 'Nothing queued — need at least one full mat set for this recipe (Rescan inventory).'
    elseif singleAssistantScrollId then
      statusLine = 'Nothing queued — none of this scroll in inventory.'
    elseif singleDustItemId then
      statusLine = 'Nothing queued — none of this item in inventory.'
    elseif tab == 'recipes' then
      local ex = onlyCat and recipeRunEmptyExplanationForCategory(onlyCat) or recipeRunEmptyExplanation()
      statusLine = 'Nothing queued — ' .. ex
      if CONFIG.echoWhenRecipeBlocked then
        pcall(function()
          local s = '[Transmute] ' .. ex
          if #s > 350 then
            s = s:sub(1, 347) .. '...'
          end
          mq.cmd('/echo ' .. s)
        end)
      end
    elseif tab == 'assistant' and onlyCat then
      statusLine = string.format('Nothing queued for %s — no enabled scrolls with quantity in inventory.', onlyCat)
    else
      statusLine = 'Nothing to hand in (no items or all toggles off).'
    end
    return
  end

  --- Multi-item recipes use a separate tick handler
  if TI.queue[1] and TI.queue[1].kind == 'recipe' then
    TI.active = true
    TI.phase = 0
    TI.recipePhase = 0
    TI.recipeMatIdx = 1
    TI.recipeEntry = TI.queue[1]
    TI.currentName = nil
    TI.giveTries = 0
    TI.p1sub = 0
    TI.p2sub = 0
    TI.resolvedToken = nil
    TI.invInventoryPrimed = false
    TI.invOpenWaitTries = 0
    TI.invFallbackKeyDone = false
    TI.pickupHandName = nil
    TI.p3tries = 0
    TI.sbPhase = 0
    TI.sbIdx = 1
    TI.sbIds = nil
    TI.nextAt = clock()
    statusLine = string.format('Queued %d recipe trade(s) (device).', #TI.queue)
    return
  end

  --- Multiple assistant scrolls in one Give (server consumes all in one EVENT_ITEM)
  if TI.queue[1] and TI.queue[1].kind == 'scroll_batch' then
    TI.active = true
    TI.phase = 0
    TI.tradeTarget = 'assistant'
    TI.sbPhase = 0
    TI.sbIdx = 1
    TI.sbIds = TI.queue[1].ids
    TI.recipePhase = 0
    TI.recipeMatIdx = 1
    TI.recipeEntry = nil
    TI.currentName = nil
    TI.giveTries = 0
    TI.p1sub = 0
    TI.p2sub = 0
    TI.resolvedToken = nil
    TI.invInventoryPrimed = false
    TI.invOpenWaitTries = 0
    TI.invFallbackKeyDone = false
    TI.pickupHandName = nil
    TI.p3tries = 0
    TI.nextAt = clock()
    statusLine = string.format('Queued %d scroll batch(es) (up to %d per Give).', #TI.queue, #(TI.queue[1].ids or {}))
    return
  end

  TI.active = true
  TI.phase = 0
  TI.currentName = nil
  TI.giveTries = 0
  TI.p1sub = 0
  TI.p2sub = 0
  TI.resolvedToken = nil
  TI.invInventoryPrimed = false
  TI.invOpenWaitTries = 0
  TI.invFallbackKeyDone = false
  TI.pickupHandName = nil
  TI.p3tries = 0
  TI.recipePhase = 0
  TI.recipeMatIdx = 1
  TI.recipeEntry = nil
  TI.sbPhase = 0
  TI.sbIdx = 1
  TI.sbIds = nil
  TI.nextAt = clock()
  statusLine = string.format('Queued %d hand-in(s).', #TI.queue)
end

--- Assistant: several scrolls in one Give window (same pattern as device multi-mat).
local function turninTickScrollBatch()
  if not TI.active or not TI.queue[1] or TI.queue[1].kind ~= 'scroll_batch' then
    return
  end
  local now = clock()
  if now < TI.nextAt then
    return
  end

  local ids = TI.sbIds or TI.queue[1].ids or {}
  local nscroll = #ids
  local sp = TI.sbPhase or 0

  if sp == 0 then
    local sid = tonumber(CONFIG.npcSpawnId or 0) or 0
    local subt = tostring(CONFIG.npcTarget or ''):lower()
    local needTarget = true
    if sid > 0 and targetId() == sid then
      needTarget = false
    end
    if subt ~= '' then
      local nm = cleanTargetName():lower()
      if nm:find(subt, 1, true) and targetId() > 0 and targetDistance() <= (CONFIG.maxGiveDistance or 25) then
        needTarget = false
      end
    end
    if needTarget then
      if sid > 0 then
        mq.cmdf('/target id %d', sid)
      else
        mq.cmdf('/target %s', CONFIG.npcTarget)
      end
    end
    TI.tradeTarget = 'assistant'
    TI.sbPhase = 1
    TI.nextAt = now + CONFIG.delayAfterTarget
    statusLine = 'Scroll batch: targeting assistant...'
    return
  end

  if sp == 1 then
    local ok, err = validateTargetForTrade()
    if not ok then
      abortTurnin(err)
      return
    end
    if CONFIG.faceBeforeGive then
      mq.cmd('/face')
    end
    if CONFIG.openInventoryBeforeGive and CONFIG.inventoryUseDoOpen then
      tryInventoryDoOpen()
      TI.invOpenWaitTries = 0
      TI.sbPhase = 2
      TI.nextAt = now + 0.08
      statusLine = 'Scroll batch: opening inventory...'
      return
    end
    TI.sbPhase = 3
    TI.nextAt = now + (CONFIG.delayBeforeGiveClick or 0.22)
    return
  end

  if sp == 2 then
    if inventoryMainOpen() then
      TI.sbPhase = 3
      TI.nextAt = now + (CONFIG.delayAfterInventoryOpen or 0.45)
      return
    end
    TI.invOpenWaitTries = (TI.invOpenWaitTries or 0) + 1
    if TI.invOpenWaitTries % 4 == 1 then
      tryInventoryDoOpen()
    end
    if TI.invOpenWaitTries >= (CONFIG.maxInventoryOpenWaitTries or 36) then
      TI.sbPhase = 3
      TI.nextAt = now + 0.2
      return
    end
    TI.nextAt = now + 0.05
    return
  end

  if sp == 3 then
    TI.sbIdx = 1
    TI.sbPhase = 10
    TI.p2sub = 0
    TI.nextAt = now
    statusLine = 'Scroll batch: lifting scrolls...'
    return
  end

  if sp == 10 then
    if TI.p2sub == 0 then
      local scrollId = tonumber(ids[TI.sbIdx]) or 0
      local row = SCROLL_BY_ID[scrollId]
      if scrollId <= 0 or not row then
        abortTurnin('Invalid scroll in batch.')
        return
      end
      TI.currentName = row.name
      local hand = invHandName[scrollId] or row.name
      TI.pickupHandName = hand
      local cntNow = select(1, probeRowInventory(row))
      if cntNow < 1 then
        statusLine = 'Skip (not in inventory): ' .. tostring(row.name)
        TI.sbIdx = TI.sbIdx + 1
        if TI.sbIdx > nscroll then
          abortTurnin('Batch missing scrolls in inventory.')
          return
        end
        TI.nextAt = now + 0.05
        return
      end
      local loc = resolvePickupToken(hand)
      if not loc then
        abortTurnin('Could not locate scroll: ' .. tostring(row.name))
        return
      end
      TI.resolvedToken = loc
      if loc.packIdx then
        openBagWindow(loc.packIdx)
        TI.p2sub = 1
        TI.p3tries = 0
        TI.nextAt = now + 0.15
      else
        TI.p2sub = 2
        TI.p3tries = 0
        TI.nextAt = now + 0.05
      end
      return
    end
    if TI.p2sub == 1 then
      local loc = TI.resolvedToken
      TI.p3tries = (TI.p3tries or 0) + 1
      local isOpen = loc.packIdx and bagWindowOpen(loc.packIdx)
      if isOpen then
        TI.p2sub = 2
        TI.p3tries = 0
        TI.nextAt = now + 0.08
      elseif TI.p3tries < 30 then
        if TI.p3tries % 10 == 0 then
          openBagWindow(loc.packIdx)
        end
        TI.nextAt = now + 0.08
      else
        TI.p2sub = 2
        TI.p3tries = 0
        TI.nextAt = now + 0.05
      end
      return
    end
    if TI.p2sub == 2 then
      fireItemPickup(TI.resolvedToken.token)
      TI.p2sub = 3
      TI.p3tries = 0
      TI.qtyWndStuck = 0
      local pickupDelayMs = math.max(80, math.floor(tonumber(CONFIG.delayMsAfterItemnotifyPickup) or 650))
      TI.nextAt = now + (pickupDelayMs / 1000.0)
      return
    end
    if TI.p2sub == 3 then
      if quantityWndOpen() then
        acceptQuantityWnd()
        TI.qtyWndStuck = (TI.qtyWndStuck or 0) + 1
        if TI.qtyWndStuck > 100 then
          abortTurnin('Scroll batch: QuantityWnd did not close — Accept/slider notify may not match your UI.')
          return
        end
        TI.nextAt = now + 0.1
        statusLine = 'Scroll batch: quantity window...'
        return
      end
      TI.qtyWndStuck = 0
      TI.p3tries = (TI.p3tries or 0) + 1
      if cursorHasItem() then
        TI.sbPhase = 11
        TI.p2sub = 0
        TI.p3tries = 0
        TI.nextAt = now + 0.08
      elseif TI.p3tries < 25 then
        TI.nextAt = now + 0.1
      else
        abortTurnin('Pickup timed out on scroll batch.')
      end
      return
    end
    return
  end

  if sp == 11 then
    acceptQuantityWnd()
    if quantityWndOpen() and (TI.p3tries or 0) < 20 then
      TI.p3tries = (TI.p3tries or 0) + 1
      TI.nextAt = now + 0.1
      return
    end
    TI.p3tries = 0
    TI.nextAt = now + (CONFIG.delayAfterPickupBeforeClick or 0.55)
    TI.sbPhase = 12
    return
  end

  if sp == 12 then
    if CONFIG.faceBeforeGive then
      mq.cmd('/face')
    end
    mq.cmd('/click left target')
    TI.sbPhase = 13
    TI.giveTries = 0
    TI.nextAt = now + (CONFIG.delayGiveWnd or 0.85)
    statusLine = string.format('Scroll batch: handing scroll %d/%d to NPC...', TI.sbIdx, nscroll)
    return
  end

  if sp == 13 then
    if giveWndOpen() and not cursorHasItem() then
      acceptQuantityWnd()
      TI.sbPhase = 14
      TI.nextAt = now + 0.12
      return
    end
    if giveWndOpen() and cursorHasItem() then
      -- Item bounced back from trade: put it away and skip this entry.
      mq.cmd('/autoinventory')
      TI.sbPhase = 14
      TI.giveTries = 0
      TI.nextAt = now + 0.2
      statusLine = string.format('Scroll batch: item returned, skipped scroll %d/%d.', TI.sbIdx, nscroll)
      return
    end
    TI.giveTries = (TI.giveTries or 0) + 1
    if TI.giveTries >= (CONFIG.maxGiveOpenTries or 8) then
      abortTurnin(giveFailureSummary())
      return
    end
    if CONFIG.faceBeforeGive then
      mq.cmd('/face')
    end
    mq.cmd('/click left target')
    TI.nextAt = now + (CONFIG.delayGiveWnd or 0.85)
    return
  end

  if sp == 14 then
    TI.sbIdx = (TI.sbIdx or 1) + 1
    if TI.sbIdx <= nscroll then
      TI.sbPhase = 10
      TI.p2sub = 0
      TI.nextAt = now + 0.18
      statusLine = string.format('Scroll batch: next scroll (%d/%d)...', TI.sbIdx, nscroll)
      return
    end
    TI.sbPhase = 20
    TI.nextAt = now + 0.12
    statusLine = 'Scroll batch: confirming trade...'
    return
  end

  if sp == 20 then
    local giveClicked = false
    for _, btnName in ipairs({ 'GVW_Give_Button', 'GVW_GiveButton', 'GVW_Give', 'Give_Button' }) do
      local ok, exists = pcall(function()
        return mq.TLO.Window('GiveWnd').Child(btnName).Open()
      end)
      if ok and exists then
        pcall(function()
          mq.cmdf('/notify GiveWnd %s leftmouseup', btnName)
        end)
        giveClicked = true
        break
      end
    end
    if not giveClicked then
      pcall(function()
        mq.cmd('/notify GiveWnd GVW_Give_Button leftmouseup')
      end)
    end
    TI.sbPhase = 21
    TI.nextAt = now + (CONFIG.delayAfterGive or 1.35)
    return
  end

  if sp == 21 then
    if giveWndOpen() then
      TI.p3tries = (TI.p3tries or 0) + 1
      if TI.p3tries < 4 then
        pcall(function()
          mq.cmd('/notify GiveWnd GVW_Give_Button leftmouseup')
        end)
        TI.nextAt = now + (CONFIG.delayAfterGive or 1.35)
        return
      end
      pcall(function()
        mq.cmd('/notify GiveWnd GVW_Cancel_Button leftmouseup')
      end)
      pcall(function()
        mq.cmd('/closewindow GiveWnd')
      end)
    end
    TI.p3tries = 0
    refreshInventoryCache()
    statusLine = string.format('Turned in scroll batch (%d scrolls).', nscroll)
    table.remove(TI.queue, 1)
    TI.sbPhase = 0
    TI.sbIdx = 1
    TI.sbIds = nil
    TI.resolvedToken = nil
    TI.giveTries = 0
    if #TI.queue == 0 then
      TI.active = false
      statusLine = 'All scroll batches done.'
    else
      TI.nextAt = now + 0.35
      if TI.queue[1].kind == 'scroll_batch' then
        TI.sbIds = TI.queue[1].ids
      else
        TI.phase = 0
      end
      statusLine = 'Next in queue...'
    end
    return
  end
end

--- Multi-material trades on Arcane Transmutation Device (one Give window, multiple slots).
local function turninTickRecipe()
  if not TI.active or not TI.queue[1] or TI.queue[1].kind ~= 'recipe' then
    return
  end
  local now = clock()
  if now < TI.nextAt then
    return
  end

  local entry = TI.queue[1]
  local mats = entry.mats or {}
  local nmats = #mats
  local rp = TI.recipePhase or 0

  if rp == 0 then
    local sid = tonumber(CONFIG.deviceNpcSpawnId or 0) or 0
    local subt = tostring(CONFIG.deviceNpcTarget or ''):lower()
    local needTarget = true
    if sid > 0 and targetId() == sid then
      needTarget = false
    end
    if subt ~= '' then
      local nm = cleanTargetName():lower()
      if nm:find(subt, 1, true) and targetId() > 0 and targetDistance() <= (CONFIG.maxGiveDistance or 25) then
        needTarget = false
      end
    end
    if needTarget then
      if sid > 0 then
        mq.cmdf('/target id %d', sid)
      else
        mq.cmdf('/target %s', CONFIG.deviceNpcTarget)
      end
    end
    TI.tradeTarget = 'device'
    TI.recipePhase = 1
    TI.nextAt = now + CONFIG.delayAfterTarget
    statusLine = 'Recipe: targeting device...'
    return
  end

  if rp == 1 then
    local ok, err = validateTargetForTrade()
    if not ok then
      abortTurnin(err)
      return
    end
    if CONFIG.faceBeforeGive then
      mq.cmd('/face')
    end
    if CONFIG.openInventoryBeforeGive and CONFIG.inventoryUseDoOpen then
      tryInventoryDoOpen()
      TI.invOpenWaitTries = 0
      TI.recipePhase = 2
      TI.nextAt = now + 0.08
      statusLine = 'Recipe: opening inventory...'
      return
    end
    TI.recipePhase = 3
    TI.nextAt = now + (CONFIG.delayBeforeGiveClick or 0.22)
    return
  end

  if rp == 2 then
    if inventoryMainOpen() then
      TI.recipePhase = 3
      TI.nextAt = now + (CONFIG.delayAfterInventoryOpen or 0.45)
      return
    end
    TI.invOpenWaitTries = (TI.invOpenWaitTries or 0) + 1
    if TI.invOpenWaitTries % 4 == 1 then
      tryInventoryDoOpen()
    end
    if TI.invOpenWaitTries >= (CONFIG.maxInventoryOpenWaitTries or 36) then
      TI.recipePhase = 3
      TI.nextAt = now + 0.2
      return
    end
    TI.nextAt = now + 0.05
    return
  end

  if rp == 3 then
    TI.recipeMatIdx = 1
    TI.recipePhase = 10
    TI.p2sub = 0
    TI.nextAt = now
    statusLine = 'Recipe: lifting materials...'
    return
  end

  --- rp 10: pickup current mat (TI.recipeMatIdx), nested TI.p2sub bag/pickup/cursor (same idea as scroll flow)
  if rp == 10 then
    if TI.p2sub == 0 then
      local mid = tonumber(mats[TI.recipeMatIdx]) or 0
      if mid <= 0 then
        abortTurnin('Invalid material index.')
        return
      end
      TI.currentName = resolveItemNameById(mid)
      local loc = findItemLocationById(mid)
      if not loc then
        abortTurnin('Missing material id ' .. tostring(mid) .. ' — need all reagents in inventory.')
        return
      end
      TI.resolvedToken = loc
      TI.recipeSplitRetries = 0
      if loc.packIdx then
        openBagWindow(loc.packIdx)
        TI.p2sub = 1
        TI.p3tries = 0
        TI.nextAt = now + 0.15
      else
        TI.p2sub = 2
        TI.nextAt = now + 0.05
      end
      return
    end
    if TI.p2sub == 1 then
      local loc = TI.resolvedToken
      TI.p3tries = (TI.p3tries or 0) + 1
      local isOpen = loc.packIdx and bagWindowOpen(loc.packIdx)
      if isOpen then
        TI.p2sub = 2
        TI.p3tries = 0
        TI.nextAt = now + 0.08
      elseif TI.p3tries < 30 then
        if TI.p3tries % 10 == 0 then
          openBagWindow(loc.packIdx)
        end
        TI.nextAt = now + 0.08
      else
        TI.p2sub = 2
        TI.nextAt = now + 0.05
      end
      return
    end
    if TI.p2sub == 2 then
      local loc = TI.resolvedToken
      fireItemPickup(loc.token)
      TI.p2sub = 3
      TI.p3tries = 0
      TI.qtyWndStuck = 0
      local pickupDelayMs = math.max(80, math.floor(tonumber(CONFIG.delayMsAfterItemnotifyPickup) or 650))
      TI.nextAt = now + (pickupDelayMs / 1000.0)
      return
    end
    if TI.p2sub == 3 then
      if quantityWndOpen() then
        acceptQuantityWnd()
        TI.qtyWndStuck = (TI.qtyWndStuck or 0) + 1
        if TI.qtyWndStuck > 100 then
          abortTurnin('Recipe: QuantityWnd did not close — Accept/slider notify may not match your UI.')
          return
        end
        TI.nextAt = now + 0.1
        statusLine = 'Recipe: quantity window (stack split)...'
        return
      end
      TI.qtyWndStuck = 0
      TI.p3tries = (TI.p3tries or 0) + 1
      if cursorHasItem() then
        TI.recipePhase = 11
        TI.p2sub = 0
        TI.p3tries = 0
        TI.nextAt = now + 0.08
        return
      elseif TI.p3tries < 25 then
        TI.nextAt = now + 0.1
        return
      else
        abortTurnin('Pickup timed out on recipe material.')
        return
      end
    end
    return
  end

  if rp == 11 then
    acceptQuantityWnd()
    if quantityWndOpen() and (TI.p3tries or 0) < 20 then
      TI.p3tries = (TI.p3tries or 0) + 1
      TI.nextAt = now + 0.1
      return
    end
    if cursorHasItem() then
      local cq = cursorItemQty()
      if cq > 1 then
        TI.recipeSplitRetries = (TI.recipeSplitRetries or 0) + 1
        if TI.recipeSplitRetries <= 4 then
          -- Put full stack back, then re-pick with split flow.
          mq.cmd('/autoinventory')
          TI.recipePhase = 10
          TI.p2sub = 2
          TI.p3tries = 0
          TI.qtyWndStuck = 0
          TI.nextAt = now + 0.2
          statusLine = string.format('Recipe: cursor stack=%d, retrying split (%d/4)...', cq, TI.recipeSplitRetries)
          return
        end
        abortTurnin(string.format('Recipe split failed: cursor still has qty %d after retries.', cq))
        return
      end
    end
    TI.p3tries = 0
    TI.nextAt = now + (CONFIG.delayAfterPickupBeforeClick or 0.55)
    TI.recipePhase = 12
    return
  end

  if rp == 12 then
    if CONFIG.faceBeforeGive then
      mq.cmd('/face')
    end
    mq.cmd('/click left target')
    TI.recipePhase = 13
    TI.giveTries = 0
    TI.nextAt = now + (CONFIG.delayGiveWnd or 0.85)
    statusLine = string.format('Recipe: handing material %d/%d to NPC...', TI.recipeMatIdx, nmats)
    return
  end

  if rp == 13 then
    if giveWndOpen() and not cursorHasItem() then
      acceptQuantityWnd()
      TI.recipePhase = 14
      TI.nextAt = now + 0.12
      return
    end
    if giveWndOpen() and cursorHasItem() then
      -- Item bounced back from trade: stash it and continue with next material.
      mq.cmd('/autoinventory')
      TI.recipePhase = 14
      TI.giveTries = 0
      TI.nextAt = now + 0.2
      statusLine = string.format('Recipe: material %d/%d returned, skipping this item.', TI.recipeMatIdx, nmats)
      return
    end
    TI.giveTries = (TI.giveTries or 0) + 1
    if TI.giveTries >= (CONFIG.maxGiveOpenTries or 8) then
      abortTurnin(giveFailureSummary())
      return
    end
    acceptQuantityWnd()
    if CONFIG.faceBeforeGive then
      mq.cmd('/face')
    end
    mq.cmd('/click left target')
    TI.nextAt = now + (CONFIG.delayGiveWnd or 0.85)
    return
  end

  if rp == 14 then
    TI.recipeMatIdx = (TI.recipeMatIdx or 1) + 1
    if TI.recipeMatIdx <= nmats then
      TI.recipePhase = 10
      TI.p2sub = 0
      TI.nextAt = now + 0.18
      statusLine = string.format('Recipe: next material (%d/%d)...', TI.recipeMatIdx, nmats)
      return
    end
    TI.recipePhase = 20
    TI.nextAt = now + 0.12
    statusLine = 'Recipe: confirming trade...'
    return
  end

  if rp == 20 then
    local giveClicked = false
    for _, btnName in ipairs({ 'GVW_Give_Button', 'GVW_GiveButton', 'GVW_Give', 'Give_Button' }) do
      local ok, exists = pcall(function()
        return mq.TLO.Window('GiveWnd').Child(btnName).Open()
      end)
      if ok and exists then
        pcall(function()
          mq.cmdf('/notify GiveWnd %s leftmouseup', btnName)
        end)
        giveClicked = true
        break
      end
    end
    if not giveClicked then
      pcall(function()
        mq.cmd('/notify GiveWnd GVW_Give_Button leftmouseup')
      end)
    end
    TI.recipePhase = 21
    TI.nextAt = now + (CONFIG.delayAfterGive or 1.35)
    return
  end

  if rp == 21 then
    if giveWndOpen() then
      TI.p3tries = (TI.p3tries or 0) + 1
      if TI.p3tries < 4 then
        pcall(function()
          mq.cmd('/notify GiveWnd GVW_Give_Button leftmouseup')
        end)
        TI.nextAt = now + (CONFIG.delayAfterGive or 1.35)
        return
      end
      pcall(function()
        mq.cmd('/notify GiveWnd GVW_Cancel_Button leftmouseup')
      end)
      pcall(function()
        mq.cmd('/closewindow GiveWnd')
      end)
    end
    TI.p3tries = 0
    refreshInventoryCache()
    statusLine = 'Recipe turned in: ' .. tostring(entry.name)
    table.remove(TI.queue, 1)
    TI.recipePhase = 0
    TI.recipeMatIdx = 1
    TI.resolvedToken = nil
    TI.giveTries = 0
    if #TI.queue == 0 then
      TI.active = false
      statusLine = 'All recipe trades done.'
    else
      TI.nextAt = now + 0.35
      statusLine = 'Next recipe trade...'
    end
    return
  end
end

local function turninTick()
  if not TI.active then
    return
  end
  if TI.queue[1] and TI.queue[1].kind == 'recipe' then
    turninTickRecipe()
    return
  end
  if TI.queue[1] and TI.queue[1].kind == 'scroll_batch' then
    turninTickScrollBatch()
    return
  end
  local now = clock()
  if now < TI.nextAt then
    return
  end

  if TI.phase == 0 then
    local sid = 0
    local subt = ''
    if TI.tradeTarget == 'device' then
      sid = tonumber(CONFIG.deviceNpcSpawnId or 0) or 0
      subt = tostring(CONFIG.deviceNpcTarget or ''):lower()
    else
      sid = tonumber(CONFIG.npcSpawnId or 0) or 0
      subt = tostring(CONFIG.npcTarget or ''):lower()
    end
    local needTarget = true
    if sid > 0 then
      if targetId() == sid then
        needTarget = false
      end
    elseif subt ~= '' then
      local nm = cleanTargetName():lower()
      if nm:find(subt, 1, true) and targetId() > 0 and targetDistance() <= (CONFIG.maxGiveDistance or 25) then
        needTarget = false
      end
    end
    if needTarget then
      if sid > 0 then
        mq.cmdf('/target id %d', sid)
      else
        mq.cmdf('/target %s', TI.tradeTarget == 'device' and CONFIG.deviceNpcTarget or CONFIG.npcTarget)
      end
    end
    TI.phase = 1
    TI.nextAt = now + CONFIG.delayAfterTarget
    statusLine = needTarget and 'Targeting...' or 'Target OK, next...'
  elseif TI.phase == 1 then
    if TI.p1sub == 0 then
      local ok, err = validateTargetForTrade()
      if not ok then
        abortTurnin(err)
        return
      end
      if CONFIG.faceBeforeGive then
        mq.cmd('/face')
      end
      if CONFIG.openInventoryBeforeGive and not TI.invInventoryPrimed then
        if CONFIG.inventoryUseDoOpen then
          tryInventoryDoOpen()
          TI.invOpenWaitTries = 0
          TI.invFallbackKeyDone = false
          TI.p1sub = 10
          TI.nextAt = now + 0.08
          statusLine = 'Opening inventory (DoOpen)...'
          return
        else
          mq.cmd('/keypress ' .. (CONFIG.inventoryKeypress or 'INVENTORY'))
          TI.invInventoryPrimed = true
          TI.p1sub = 1
          TI.nextAt = now + (CONFIG.delayAfterInventoryOpen or 0.45)
          statusLine = 'Opening inventory (keypress)...'
          return
        end
      end
      TI.p1sub = 1
      TI.nextAt = now + (CONFIG.delayBeforeGiveClick or 0.22)
      statusLine = 'Preparing pickup...'
      return
    end
    if TI.p1sub == 10 then
      if inventoryMainOpen() then
        TI.invInventoryPrimed = true
        TI.p1sub = 1
        TI.nextAt = now + (CONFIG.delayAfterInventoryOpen or 0.45)
        statusLine = 'Inventory open.'
        return
      end
      TI.invOpenWaitTries = TI.invOpenWaitTries + 1
      if TI.invOpenWaitTries % 4 == 1 then
        tryInventoryDoOpen()
      end
      local maxW = CONFIG.maxInventoryOpenWaitTries or 36
      if TI.invOpenWaitTries >= math.floor(maxW * 0.5) and CONFIG.inventoryFallbackKeypressOnce and not TI.invFallbackKeyDone then
        TI.invFallbackKeyDone = true
        mq.cmd('/keypress ' .. (CONFIG.inventoryKeypress or 'INVENTORY'))
      end
      if TI.invOpenWaitTries >= maxW then
        TI.invInventoryPrimed = true
        TI.p1sub = 1
        TI.nextAt = now + (CONFIG.delayBeforeGiveClick or 0.22)
        statusLine = 'Inventory wait ended — trying pickup anyway.'
        return
      end
      TI.nextAt = now + 0.05
      return
    end
    if TI.p1sub == 1 then
      TI.phase = 2
      TI.p1sub = 0
      TI.nextAt = now + 0.02
      return
    end
  elseif TI.phase == 2 then
    -- ── Phase 2: targeted single-bag open + single-item pickup ──────────────
    -- p2sub=0  validate item, locate it in inventory, open ONLY its bag window
    -- p2sub=1  wait for bag window to open (polls up to ~2s)
    -- p2sub=2  fire /itemnotify leftmouseup on the exact slot, start pickup wait
    -- p2sub=3  poll cursor until item appears (up to ~2s), then advance to phase 3
    if TI.p2sub == nil then TI.p2sub = 0 end

    if TI.p2sub == 0 then
      -- ── Sub-phase 0: validate + locate ───────────────────────────────────
      local entry = TI.queue[1]
      if not entry then
        abortTurnin('Queue empty.')
        return
      end
      local row = nil
      if entry.kind == 'scroll' then
        row = SCROLL_BY_ID[entry.id]
      elseif entry.kind == 'dust' then
        row = { id = entry.itemId, name = entry.name }
      else
        popQueue()
        return
      end
      if not row then
        popQueue()
        return
      end

      TI.currentName = row.name
      local hand = row.name
      if entry.kind == 'scroll' then
        hand = invHandName[entry.id] or row.name
      elseif entry.kind == 'dust' then
        hand = invHandNameDust[entry.itemId] or row.name
      end
      TI.pickupHandName = hand

      -- Live count check — skip if already gone from inventory
      local cntNow = select(1, probeRowInventory(row))
      if cntNow < 1 then
        statusLine = 'Skip (not in inventory): ' .. tostring(row.name)
        popQueue()
        return
      end

      -- Deep-scan to find EXACT bag and slot
      local loc = resolvePickupToken(hand)
      if not loc then
        statusLine = 'Could not locate in any bag — skipping: ' .. tostring(row.name)
        popQueue()
        return
      end
      TI.resolvedToken = loc   -- store the full location table

      if loc.packIdx then
        -- Item is inside a bag — right-click open ONLY that bag
        statusLine = string.format('Opening bag %d for: %s  [%s]', loc.packIdx, TI.currentName, loc.source)
        openBagWindow(loc.packIdx)
        TI.p2sub = 1
        TI.p3tries = 0
        TI.nextAt = now + 0.15   -- short initial wait then poll
      else
        -- Item is in a top-level slot — no bag open needed, go straight to pickup
        statusLine = 'Picking up (top-level slot): ' .. TI.currentName
        TI.p2sub = 2
        TI.p3tries = 0
        TI.nextAt = now + 0.05
      end
      return
    end

    if TI.p2sub == 1 then
      -- ── Sub-phase 1: wait for bag window to be open ───────────────────────
      local loc = TI.resolvedToken
      TI.p3tries = TI.p3tries + 1
      local isOpen = loc.packIdx and bagWindowOpen(loc.packIdx)
      if isOpen then
        -- Bag confirmed open — fire pickup
        TI.p2sub = 2
        TI.p3tries = 0
        TI.nextAt = now + 0.08
        statusLine = 'Bag open, picking up: ' .. TI.currentName
      elseif TI.p3tries < 30 then
        -- Bag not yet open — retry right-click every ~10 polls (~500ms)
        if TI.p3tries % 10 == 0 then
          openBagWindow(loc.packIdx)
        end
        TI.nextAt = now + 0.08
        statusLine = string.format('Waiting for bag %d (%d)...', loc.packIdx, TI.p3tries)
      else
        -- Bag window never opened (maybe the bag is not in that slot anymore)
        -- Fall through anyway and try the itemnotify — it may still work
        TI.p2sub = 2
        TI.p3tries = 0
        TI.nextAt = now + 0.05
        statusLine = 'Bag open timeout — trying pickup anyway: ' .. TI.currentName
      end
      return
    end

    if TI.p2sub == 2 then
      -- ── Sub-phase 2: fire /itemnotify leftmouseup on exact slot ──────────
      local loc = TI.resolvedToken
      if not loc then
        abortTurnin('Lost item location in phase 2.')
        return
      end
      statusLine = string.format('Pickup /itemnotify %s  (%s)', loc.token, loc.source)
      fireItemPickup(loc.token)
      TI.p2sub = 3
      TI.p3tries = 0
      TI.qtyWndStuck = 0
      local pickupDelayMs = math.max(80, math.floor(tonumber(CONFIG.delayMsAfterItemnotifyPickup) or 650))
      TI.nextAt = now + (pickupDelayMs / 1000.0)
      return
    end

    if TI.p2sub == 3 then
      -- ── Sub-phase 3: poll cursor until item appears ───────────────────────
      if quantityWndOpen() then
        acceptQuantityWnd()
        TI.qtyWndStuck = (TI.qtyWndStuck or 0) + 1
        if TI.qtyWndStuck > 100 then
          statusLine = 'QuantityWnd stuck — re-scanning pickup: ' .. tostring(TI.currentName)
          local loc2 = resolvePickupToken(TI.pickupHandName or '')
          if loc2 then
            TI.resolvedToken = loc2
            TI.p2sub = 2
            TI.p3tries = 0
            TI.qtyWndStuck = 0
            TI.nextAt = now + 0.15
          else
            TI.p2sub = 0
            TI.p3tries = 0
            TI.qtyWndStuck = 0
            popQueue()
          end
          return
        end
        TI.nextAt = now + 0.1
        statusLine = 'Quantity window (stack split)...'
        return
      end
      TI.qtyWndStuck = 0
      TI.p3tries = TI.p3tries + 1
      if cursorHasItem() then
        TI.p2sub = 0
        TI.p3tries = 0
        TI.phase = 3
        TI.nextAt = now + 0.1
        statusLine = 'Item on cursor — handing in: ' .. TI.currentName
      elseif TI.p3tries < 25 then
        TI.nextAt = now + 0.1
        statusLine = string.format('Waiting for item on cursor (%d/25)...', TI.p3tries)
      else
        -- Item never appeared on cursor after pickup command
        -- Rethrow if location has changed (stacked item) or truly gone
        statusLine = 'Pickup timeout — re-scanning and retrying once: ' .. tostring(TI.currentName)
        local loc2 = resolvePickupToken(TI.pickupHandName or '')
        if loc2 then
          TI.resolvedToken = loc2
          TI.p2sub = 2   -- retry the pickup with fresh location
          TI.p3tries = 0
          TI.qtyWndStuck = 0
          TI.nextAt = now + 0.1
        else
          statusLine = 'Item gone after pickup attempt — skipping: ' .. tostring(TI.currentName)
          TI.p2sub = 0
          TI.p3tries = 0
          TI.qtyWndStuck = 0
          popQueue()
        end
      end
      return
    end

  elseif TI.phase == 3 then
    -- ── Phase 3: dismiss QuantityWnd if it appeared after pickup ─────────────
    acceptQuantityWnd()
    if quantityWndOpen() and TI.p3tries < 20 then
      TI.p3tries = TI.p3tries + 1
      TI.nextAt = now + 0.1
      statusLine = 'Dismissing quantity window...'
      return
    end
    TI.p3tries = 0
    TI.phase = 4
    TI.nextAt = now + (CONFIG.delayAfterPickupBeforeClick or 0.55)
    statusLine = 'Ready to give — clicking NPC...'

  elseif TI.phase == 4 then
    -- ── Phase 4: click NPC to open GiveWnd ───────────────────────────────────
    -- Guard: make sure item is still on cursor
    if not cursorHasItem() then
      abortTurnin('Item left cursor before give. Check bag/slot access and try again.')
      return
    end
    if CONFIG.faceBeforeGive then
      mq.cmd('/face')
    end
    -- Left-click NPC with item on cursor — this should open GiveWnd
    mq.cmd('/click left target')
    TI.phase = 5
    TI.giveTries = 0
    TI.nextAt = now + (CONFIG.delayGiveWnd or 0.85)
    statusLine = 'Clicked NPC, waiting for Give window...'

  elseif TI.phase == 5 then
    -- ── Phase 5: wait/retry until GiveWnd is open ────────────────────────────
    if giveWndOpen() then
      TI.phase = 6
      TI.nextAt = now + 0.15
      statusLine = 'Give window open — placing item...'
      return
    end
    TI.giveTries = TI.giveTries + 1
    if TI.giveTries >= (CONFIG.maxGiveOpenTries or 8) then
      abortTurnin(giveFailureSummary())
      return
    end
    -- Still waiting — face NPC and click again
    if CONFIG.faceBeforeGive then mq.cmd('/face') end
    mq.cmd('/click left target')
    TI.nextAt = now + (CONFIG.delayGiveWnd or 0.85)
    statusLine = string.format('Waiting for Give window... (%d/%d)', TI.giveTries, CONFIG.maxGiveOpenTries or 8)

  elseif TI.phase == 6 then
    -- ── Phase 6: place cursor item into GiveWnd slot ─────────────────────────
    -- The item is on cursor. Left-click the first give slot to drop it in.
    -- GiveWnd slot names vary by UI — try the most common ones.
    local placed = false
    for _, slotName in ipairs({ 'GVW_Give_Slot0', 'GVW_GiveSlot0', 'GVW_Slot0',
                                 'GVW_Give_Slot', 'GVW_GiveSlot', 'Give_Slot0' }) do
      local ok, isWnd = pcall(function()
        return mq.TLO.Window('GiveWnd').Child(slotName).Open()
      end)
      if ok and isWnd then
        pcall(function()
          mq.cmdf('/notify GiveWnd %s leftmouseup', slotName)
        end)
        placed = true
        break
      end
    end
    if not placed then
      -- Fallback: click raw coordinates of slot 1 inside GiveWnd
      -- This is the most reliable method when slot names are unknown
      pcall(function() mq.cmd('/notify GiveWnd GVW_Give_Slot0 leftmouseup') end)
    end
    -- Also handle QuantityWnd that may pop up when dropping stacked item
    acceptQuantityWnd()
    TI.phase = 7
    TI.nextAt = now + 0.35
    statusLine = 'Item placed in give slot — confirming...'

  elseif TI.phase == 7 then
    -- ── Phase 7: handle QuantityWnd then verify item is in slot ──────────────
    acceptQuantityWnd()
    -- Check cursor is now empty (item successfully placed in give slot)
    if cursorHasItem() then
      -- Item still on cursor — slot placement may have failed, retry once
      TI.p3tries = (TI.p3tries or 0) + 1
      if TI.p3tries < 5 then
        pcall(function() mq.cmd('/notify GiveWnd GVW_Give_Slot0 leftmouseup') end)
        acceptQuantityWnd()
        TI.nextAt = now + 0.3
        statusLine = string.format('Retrying slot placement (%d)...', TI.p3tries)
        return
      else
        -- Item returned / still on cursor: stash it and stop processing this queue item.
        mq.cmd('/autoinventory')
        TI.p3tries = 0
        popQueue()
        TI.phase = 0
        TI.nextAt = now + 0.2
        statusLine = 'Item returned during give; auto-inventoried and skipped.'
        return
      end
    end
    TI.p3tries = 0
    TI.phase = 8
    TI.nextAt = now + 0.2
    statusLine = 'Clicking Give button...'

  elseif TI.phase == 8 then
    -- ── Phase 8: click the Give button to complete the hand-in ───────────────
    -- Try multiple possible Give button widget names for compatibility
    local giveClicked = false
    for _, btnName in ipairs({ 'GVW_Give_Button', 'GVW_GiveButton', 'GVW_Give', 'Give_Button' }) do
      local ok, exists = pcall(function()
        return mq.TLO.Window('GiveWnd').Child(btnName).Open()
      end)
      if ok and exists then
        pcall(function() mq.cmdf('/notify GiveWnd %s leftmouseup', btnName) end)
        giveClicked = true
        break
      end
    end
    if not giveClicked then
      -- Fallback: try all names blindly
      for _, btnName in ipairs({ 'GVW_Give_Button', 'GVW_GiveButton', 'GVW_Give' }) do
        pcall(function() mq.cmdf('/notify GiveWnd %s leftmouseup', btnName) end)
      end
    end
    TI.phase = 9
    TI.nextAt = now + (CONFIG.delayAfterGive or 1.35)
    statusLine = 'Give button clicked — waiting for confirmation...'

  elseif TI.phase == 9 then
    -- ── Phase 9: confirm give succeeded (GiveWnd closed = success) ───────────
    if giveWndOpen() then
      -- Window still open — give may not have fired, retry button once
      TI.p3tries = (TI.p3tries or 0) + 1
      if TI.p3tries < 4 then
        pcall(function() mq.cmd('/notify GiveWnd GVW_Give_Button leftmouseup') end)
        TI.nextAt = now + (CONFIG.delayAfterGive or 1.35)
        statusLine = string.format('Give retry (%d)...', TI.p3tries)
        return
      else
        -- Window stuck open — close it and move on
        pcall(function() mq.cmd('/notify GiveWnd GVW_Cancel_Button leftmouseup') end)
        pcall(function() mq.cmd('/closewindow GiveWnd') end)
      end
    end
    TI.p3tries = 0
    -- Rescan inventory and advance queue
    refreshInventoryCache()
    statusLine = 'Turned in: ' .. tostring(TI.currentName)
    popQueue()
  end
end

local function nameVisible(name)
  local fb = filterBuf or ''
  if fb == '' then
    return true
  end
  return name:lower():find(fb:lower(), 1, true) ~= nil
end

local function buildRecipeGroups()
  local groups = {}
  for _, cat in ipairs(CATEGORY_ORDER) do
    groups[cat] = {}
  end
  if not TRANSMUTE_DEVICE_DATA or not TRANSMUTE_DEVICE_DATA.DEVICE_RECIPES then
    return groups
  end
  for _, rec in ipairs(TRANSMUTE_DEVICE_DATA.DEVICE_RECIPES) do
    local cat = rec.category or 'Unknown'
    if not groups[cat] then
      groups[cat] = {}
    end
    table.insert(groups[cat], rec)
  end
  return groups
end

-- PocketFarm-style neon theme helpers
local function pushTransmuteTheme()
  local nc, nv = 0, 0
  local function pv(var, ...)
    ImGui.PushStyleVar(var, ...)
    nv = nv + 1
  end
  local function pc(col, ...)
    ImGui.PushStyleColor(col, ...)
    nc = nc + 1
  end

  pv(ImGuiStyleVar.WindowRounding,   6)
  pv(ImGuiStyleVar.FrameRounding,    4)
  pv(ImGuiStyleVar.ItemSpacing,      6, 4)
  pv(ImGuiStyleVar.WindowBorderSize, 1.5)
  pv(ImGuiStyleVar.FrameBorderSize,  1)
  pv(ImGuiStyleVar.ScrollbarSize,    10)

  pc(ImGuiCol.WindowBg,              0.05, 0.06, 0.07, 0.97)
  pc(ImGuiCol.ChildBg,               0.04, 0.06, 0.04, 1.00)
  pc(ImGuiCol.Border,                0.12, 0.55, 0.22, 0.70)
  pc(ImGuiCol.FrameBg,               0.04, 0.07, 0.04, 1.00)
  pc(ImGuiCol.FrameBgHovered,        0.07, 0.14, 0.07, 1.00)
  pc(ImGuiCol.TitleBg,               0.04, 0.16, 0.08, 1.00)
  pc(ImGuiCol.TitleBgActive,         0.05, 0.22, 0.10, 1.00)
  pc(ImGuiCol.Header,                0.05, 0.20, 0.09, 1.00)
  pc(ImGuiCol.HeaderHovered,         0.08, 0.30, 0.13, 1.00)
  pc(ImGuiCol.Separator,             0.10, 0.50, 0.18, 0.80)
  pc(ImGuiCol.ScrollbarBg,           0.00, 0.00, 0.00, 0.50)
  pc(ImGuiCol.ScrollbarGrab,         0.10, 0.45, 0.18, 1.00)
  pc(ImGuiCol.ScrollbarGrabHovered,  0.15, 0.65, 0.25, 1.00)
  pc(ImGuiCol.CheckMark,             0.20, 1.00, 0.40, 1.00)
  pc(ImGuiCol.SliderGrab,            0.20, 1.00, 0.40, 1.00)
  pc(ImGuiCol.Text,                  0.88, 0.92, 0.88, 1.00)
  pc(ImGuiCol.Button,                0.08, 0.28, 0.12, 1.00)
  pc(ImGuiCol.ButtonHovered,         0.12, 0.42, 0.18, 1.00)
  pc(ImGuiCol.ButtonActive,          0.16, 0.58, 0.24, 1.00)

  return nc, nv
end

local function popTransmuteTheme(nc, nv)
  if nc and nc > 0 then ImGui.PopStyleColor(nc) end
  if nv and nv > 0 then ImGui.PopStyleVar(nv) end
end

local function neonButton(label, w, h)
  ImGui.PushStyleColor(ImGuiCol.Button,        0.08, 0.28, 0.12, 1.00)
  ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 0.14, 0.50, 0.22, 1.00)
  ImGui.PushStyleColor(ImGuiCol.ButtonActive,  0.18, 0.62, 0.27, 1.00)
  ImGui.PushStyleColor(ImGuiCol.Text,          0.88, 0.95, 0.88, 1.00)
  local r = ImGui.Button(label, w or 0, h or 0)
  ImGui.PopStyleColor(4)
  return r
end

local function checkboxCompat(label, current)
  -- Render checkbox, but drive state from click detection for MQ binding stability.
  ImGui.Checkbox(label, current)
  local clicked = false
  pcall(function() clicked = ImGui.IsItemClicked() end)
  if clicked then
    local nowMs = math.floor(os.clock() * 1000)
    local last = checkboxClickAt[label] or 0
    if (nowMs - last) > 170 then
      checkboxClickAt[label] = nowMs
      return true, not current
    end
  end
  return false, current
end

--- Mode row only: draw atlas cell + tooltip. No SetCursorPos/invisible Button (SameLine tab strip + overlay is brittle in MQ ImGui).
local function drawModeTabIconOnly(itemId, tooltipLines, iconSize)
  iconSize = tonumber(iconSize) or 20
  local lines = tooltipLines
  if type(lines) == 'string' then
    lines = { lines }
  end
  local eqic = 0
  local okRes, resOrErr = pcall(function()
    return resolveEqItemIcon(itemId, nil)
  end)
  if okRes and resOrErr then
    eqic = tonumber(resOrErr) or 0
  end
  local anim = ensureTransmuteItemAnim()
  if anim and eqic > 0 then
    local cell = eqic - EQ_ITEM_ICON_ATLAS_OFFSET
    if cell >= 0 then
      local okCell = pcall(function()
        anim:SetTextureCell(cell)
      end)
      if okCell then
        ImGui.DrawTextureAnimation(anim, iconSize, iconSize)
      else
        ImGui.Dummy(iconSize, iconSize)
      end
    else
      ImGui.Dummy(iconSize, iconSize)
    end
  else
    ImGui.Dummy(iconSize, iconSize)
  end
  if lines and #lines > 0 and ImGui.IsItemHovered() then
    ImGui.BeginTooltip()
    for _, ln in ipairs(lines) do
      if ln and ln ~= '' then
        ImGui.TextUnformatted(ln)
      end
    end
    ImGui.EndTooltip()
  end
end

--- Smallest item id in a dust loot list (UI lists are effectively id-sorted; matches first row e.g. Emerald 10029).
local function firstDustLootTabIconItemId(loot)
  if not loot or #loot == 0 then
    return nil
  end
  local best = nil
  for _, row in ipairs(loot) do
    local id = tonumber(row.id)
    if id and (best == nil or id < best) then
      best = id
    end
  end
  return best
end

--- First scroll row that resolves to an atlas cell (id 1 Arcane Dust often has no Icon() — skip for a visible tab icon).
local assistantModeTabIconResolved = false
local assistantModeTabIconItemIdCached = nil
local function assistantModeTabItemId()
  if assistantModeTabIconResolved then
    return assistantModeTabIconItemIdCached
  end
  assistantModeTabIconResolved = true
  for _, row in ipairs(TRANSMUTE_SCROLLS) do
    local id = tonumber(row.id)
    if id and resolveEqItemIcon(id, row.name) > 0 then
      assistantModeTabIconItemIdCached = id
      return id
    end
  end
  assistantModeTabIconItemIdCached = tonumber(TRANSMUTE_SCROLLS[1] and TRANSMUTE_SCROLLS[1].id)
  return assistantModeTabIconItemIdCached
end

--- Item id for Mode row tab icon (aligned with first row of each tab’s list / category order).
local function modeTabRepresentativeItemId(uiTabVal)
  if uiTabVal == 'assistant' then
    return assistantModeTabItemId()
  end
  if not TRANSMUTE_DEVICE_DATA then
    return nil
  end
  if uiTabVal == 'dust_u' then
    return firstDustLootTabIconItemId(TRANSMUTE_DEVICE_DATA.ULTIMATE_LOOT)
  end
  if uiTabVal == 'dust_a' then
    return firstDustLootTabIconItemId(TRANSMUTE_DEVICE_DATA.AVATAR_LOOT)
  end
  if uiTabVal == 'dust_d' then
    return firstDustLootTabIconItemId(TRANSMUTE_DEVICE_DATA.DEMIGOD_LOOT)
  end
  if uiTabVal == 'recipes' then
    local rg = buildRecipeGroups()
    for _, cat in ipairs(CATEGORY_ORDER) do
      local recs = rg[cat]
      if recs and #recs > 0 then
        local r = recs[1]
        local oid = tonumber(r.outputId)
        if oid and oid > 0 then
          return oid
        end
        if r.mats and r.mats[1] then
          return tonumber(r.mats[1])
        end
      end
    end
  end
  return nil
end

--- Must sit after neonButton: Lua resolves locals lexically; earlier placement made neonButton a nil global.
local function drawModeTab(uiTabVal, buttonLabel, iconTooltipLines)
  ImGui.PushID('modetab_' .. tostring(uiTabVal))
  if CONFIG.modeTabItemIcons ~= false then
    local mid = modeTabRepresentativeItemId(uiTabVal)
    if mid and mid > 0 then
      local sz = tonumber(CONFIG.modeTabIconSize) or tonumber(CONFIG.recipeRowIconSize) or 20
      drawModeTabIconOnly(mid, iconTooltipLines, sz)
      ImGui.SameLine(0, 6)
    end
  end
  if neonButton(buttonLabel) then
    uiTab = uiTabVal
  end
  ImGui.PopID()
  ImGui.SameLine(0, 8)
end

local function drawUi()
  ImGui.TextWrapped(string.format(
    'Assistant NPC: %s%s  (CONFIG.npcTarget / npcSpawnId)',
    (tonumber(CONFIG.npcSpawnId or 0) or 0) > 0 and ('id ' .. tostring(CONFIG.npcSpawnId)) or ('/target ' .. tostring(CONFIG.npcTarget)),
    CONFIG.npcNameMustContain ~= '' and ('; name must contain "' .. CONFIG.npcNameMustContain .. '"') or ''
  ))
  if TRANSMUTE_DEVICE_DATA then
    ImGui.TextWrapped(string.format(
      'Device NPC: %s%s  (CONFIG.deviceNpcTarget / deviceNpcSpawnId) — dust & multi-item recipes',
      (tonumber(CONFIG.deviceNpcSpawnId or 0) or 0) > 0 and ('id ' .. tostring(CONFIG.deviceNpcSpawnId)) or ('/target ' .. tostring(CONFIG.deviceNpcTarget)),
      CONFIG.deviceNameMustContain ~= '' and ('; name must contain "' .. CONFIG.deviceNameMustContain .. '"') or ''
    ))
  else
    ImGui.TextWrapped('Device data missing — rebuild this unified Transmute.lua from source data.')
  end
  ImGui.TextWrapped(string.format(
    'Inventory scan #%d  |  live rescan: %s (every %.1fs if on). Use Rescan for a single refresh.',
    invScanGen,
    CONFIG.invLiveScan and 'ON' or 'OFF (default — no spam)',
    CONFIG.invRefreshSec or 5
  ))
  ImGui.Separator()

  ImGui.TextWrapped('Mode')
  ImGui.SameLine()
  drawModeTab('assistant', 'Assistant##tab', {
    'Assistant — scroll turn-ins (icon: first scroll in list)',
  })
  drawModeTab('dust_u', 'Dust Ultimate##tab', {
    'Dust Ultimate — sample mob from Ultimate loot table',
  })
  drawModeTab('dust_a', 'Dust Avatar##tab', {
    'Dust Avatar — sample mob from Avatar loot table',
  })
  drawModeTab('dust_d', 'Dust Demigod##tab', {
    'Dust Demigod — sample mob from Demigod loot table',
  })
  drawModeTab('recipes', 'Device recipes##tab', {
    'Device recipes — sample from first recipe row (output or mat)',
  })
  ImGui.Text(string.format('(current: %s)', uiTab))
  ImGui.Separator()

  if neonButton('Dump GiveWnd names') then
    -- Diagnostic: probe common slot/button names on whichever Give window TLO reports open.
    mq.cmd('/echo === GiveWnd child probe ==')
    local openWn = nil
    for _, wn in ipairs(GIVE_WND_NAMES) do
      local ok, o = pcall(function() return mq.TLO.Window(wn).Open() end)
      if ok and o then
        openWn = wn
        mq.cmdf('/echo   window: %s (Open)', wn)
        break
      end
    end
    if openWn then
      local childNames = {
        'GVW_Give_Slot0','GVW_GiveSlot0','GVW_Slot0','GVW_Give_Slot',
        'GVW_GiveSlot','Give_Slot0','GVW_Give_Button','GVW_GiveButton',
        'GVW_Give','Give_Button','GVW_Cancel_Button','GVW_ItemSlot',
        'GVW_ItemSlot0','GVW_TradeSlot0','GVW_ItemSlot1','GVW_Give_Slot1',
        'GVW_GiveSlot1','GVW_Slot1','GVW_ItemSlot2','GVW_TradeSlot1',
      }
      for si = 0, 8 do
        table.insert(childNames, string.format('GVW_Give_Slot%d', si))
        table.insert(childNames, string.format('GVW_ItemSlot%d', si))
      end
      for _, n in ipairs(childNames) do
        local ok, o = pcall(function() return mq.TLO.Window(openWn).Child(n).Open() end)
        if ok and o then
          mq.cmdf('/echo   FOUND: %s', n)
        end
      end
      mq.cmd('/echo === end ===')
      statusLine = 'GiveWnd dump sent to MQ chat.'
    else
      statusLine = 'Give trade window not open — open it, then click Dump.'
    end
  end
  ImGui.SameLine()
  if neonButton('Save toggles') then
    saveState()
    statusLine = 'Saved: ' .. iniPath()
  end
  ImGui.SameLine()
  if neonButton('Reload ini') then
    loadState()
    refreshInventoryCache()
    dirty = false
    statusLine = 'Reloaded ini.'
  end
  ImGui.SameLine()
  if neonButton('Rescan inventory') then
    refreshInventoryCache()
    statusLine = 'Inventory rescanned.'
  end
  ImGui.SameLine()
  if neonButton('Echo inv IDs') then
    dumpInventoryIdsToEcho()
  end
  ImGui.SameLine()
  if neonButton('All on') then
    if uiTab == 'assistant' then
      for _, row in ipairs(TRANSMUTE_SCROLLS) do
        enabled[row.id] = true
      end
    elseif uiTab == 'dust_u' and TRANSMUTE_DEVICE_DATA then
      for _, row in ipairs(TRANSMUTE_DEVICE_DATA.ULTIMATE_LOOT or {}) do
        enabled['d' .. row.id] = true
      end
    elseif uiTab == 'dust_a' and TRANSMUTE_DEVICE_DATA then
      for _, row in ipairs(TRANSMUTE_DEVICE_DATA.AVATAR_LOOT or {}) do
        enabled['d' .. row.id] = true
      end
    elseif uiTab == 'dust_d' and TRANSMUTE_DEVICE_DATA then
      for _, row in ipairs(TRANSMUTE_DEVICE_DATA.DEMIGOD_LOOT or {}) do
        enabled['d' .. row.id] = true
      end
    elseif uiTab == 'recipes' and TRANSMUTE_DEVICE_DATA then
      for _, rec in ipairs(TRANSMUTE_DEVICE_DATA.DEVICE_RECIPES or {}) do
        enabled['r' .. rec.key] = true
      end
    end
    dirty = true
  end
  ImGui.SameLine()
  if neonButton('All off') then
    if uiTab == 'assistant' then
      for _, row in ipairs(TRANSMUTE_SCROLLS) do
        enabled[row.id] = false
      end
    elseif uiTab == 'dust_u' and TRANSMUTE_DEVICE_DATA then
      for _, row in ipairs(TRANSMUTE_DEVICE_DATA.ULTIMATE_LOOT or {}) do
        enabled['d' .. row.id] = false
      end
    elseif uiTab == 'dust_a' and TRANSMUTE_DEVICE_DATA then
      for _, row in ipairs(TRANSMUTE_DEVICE_DATA.AVATAR_LOOT or {}) do
        enabled['d' .. row.id] = false
      end
    elseif uiTab == 'dust_d' and TRANSMUTE_DEVICE_DATA then
      for _, row in ipairs(TRANSMUTE_DEVICE_DATA.DEMIGOD_LOOT or {}) do
        enabled['d' .. row.id] = false
      end
    elseif uiTab == 'recipes' and TRANSMUTE_DEVICE_DATA then
      for _, rec in ipairs(TRANSMUTE_DEVICE_DATA.DEVICE_RECIPES or {}) do
        enabled['r' .. rec.key] = false
      end
    end
    dirty = true
  end

  ImGui.Separator()
  filterBuf = ImGui.InputText('Filter name', filterBuf) or filterBuf
  if uiTab == 'dust_u' or uiTab == 'dust_a' or uiTab == 'dust_d' then
    local dio = dustInventoryOnly
    local chx, nvx = checkboxCompat('##dust_inv_only', dio)
    if chx then
      dustInventoryOnly = nvx
    end
    ImGui.SameLine()
    ImGui.TextWrapped('Limit dust lists to items you currently hold (recommended).')
  end
  ImGui.TextWrapped(
    'Per-row Hand = turn in that scroll / dust item / recipe now (ignores Use checkbox; recipe needs full mat set). Section Hand in / bottom Turn in still use checkboxes for bulk. Assistant = Transmutation NPC; dust & recipes = Device NPC.'
  )

  if uiTab == 'assistant' then
    local groups = buildCategoryGroups()
    for _, cat in ipairs(CATEGORY_ORDER) do
      local rows = groups[cat]
      if rows and #rows > 0 then
        local visible = {}
        for _, row in ipairs(rows) do
          if nameVisible(row.name) then
            table.insert(visible, row)
          end
        end
        if #visible > 0 then
          local qty = 0
          for _, row in ipairs(visible) do
            qty = qty + invCountForRow(row)
          end
          local header = string.format('%s  —  %d recipe(s) shown, %d in inventory', cat, #visible, qty)
          if ImGui.CollapsingHeader(header) then
            if neonButton('Hand in##asst_hand_' .. cat:gsub('%W', '_')) then
              startTurnin({ tab = 'assistant', category = cat })
            end
            ImGui.SameLine()
            ImGui.TextWrapped(string.format('Turn in enabled scrolls in %s only (bottom Turn in = all categories).', cat))
            local rowIconSz = tonumber(CONFIG.recipeRowIconSize) or 22
            for _, row in ipairs(visible) do
              if enabled[row.id] == nil then
                enabled[row.id] = false
              end
              local sel = not not enabled[row.id]
              local n = invCountForRow(row)
              ImGui.PushID('transmute_row_' .. tostring(row.id))
              local changed, newVal = checkboxCompat('##enabled_' .. tostring(row.id), sel)
              if changed then
                enabled[row.id] = newVal
                dirty = true
              end
              ImGui.PopID()
              ImGui.SameLine()
              if CONFIG.recipeRowItemIcons then
                local ric = resolveEqItemIcon(row.id, row.name)
                drawTransmuteItemIcon(
                  ric,
                  'asst_row_' .. tostring(row.id),
                  {
                    row.name,
                    string.format('Scroll id %d  |  in inventory: %d', row.id, n),
                  },
                  rowIconSz
                )
                ImGui.SameLine(0, 6)
              end
              if neonButton('Hand##asst_q_' .. tostring(row.id), 44, 0) then
                startTurnin({ singleAssistantScrollId = row.id })
              end
              ImGui.SameLine(0, 6)
              pcall(function()
                ImGui.AlignTextToFramePadding()
              end)
              ImGui.Text(string.format('[%d] x%d  %s', row.id, n, row.name))
            end
          end
        end
      end
    end
  elseif TRANSMUTE_DEVICE_DATA and (uiTab == 'dust_u' or uiTab == 'dust_a' or uiTab == 'dust_d') then
    local loot = nil
    local title = ''
    if uiTab == 'dust_u' then
      loot = TRANSMUTE_DEVICE_DATA.ULTIMATE_LOOT
      title = 'Ultimate-tier zone loot (dust)'
    elseif uiTab == 'dust_a' then
      loot = TRANSMUTE_DEVICE_DATA.AVATAR_LOOT
      title = 'Avatar-tier zone loot (dust)'
    else
      loot = TRANSMUTE_DEVICE_DATA.DEMIGOD_LOOT
      title = 'Demigod-tier zone loot (dust)'
    end
    local visible = {}
    for _, row in ipairs(loot or {}) do
      local n = invCacheDust[row.id] or 0
      if nameVisible(row.name) and (not dustInventoryOnly or n > 0) then
        table.insert(visible, row)
      end
    end
    local qty = 0
    for _, row in ipairs(visible) do
      qty = qty + (invCacheDust[row.id] or 0)
    end
    local header = string.format('%s — %d shown, %d in inventory', title, #visible, qty)
    if ImGui.CollapsingHeader(header) then
      if neonButton('Hand in##dust_hand_' .. tostring(uiTab)) then
        startTurnin({ tab = uiTab })
      end
      ImGui.SameLine()
      ImGui.TextWrapped('Turn in enabled items on this tier (same as bottom Turn in while on this tab).')
      local rowIconSz = tonumber(CONFIG.recipeRowIconSize) or 22
      for _, row in ipairs(visible) do
        local k = 'd' .. row.id
        if enabled[k] == nil then
          enabled[k] = false
        end
        local sel = not not enabled[k]
        local n = invCacheDust[row.id] or 0
        ImGui.PushID('dust_row_' .. tostring(row.id))
        local changed, newVal = checkboxCompat('##dust_en_' .. tostring(row.id), sel)
        if changed then
          enabled[k] = newVal
          dirty = true
        end
        ImGui.PopID()
        ImGui.SameLine()
        if CONFIG.recipeRowItemIcons then
          local dic = resolveEqItemIcon(row.id, row.name)
          drawTransmuteItemIcon(
            dic,
            'dust_row_' .. tostring(row.id),
            {
              row.name,
              string.format('Dust turn-in id %d  |  in inventory: %d', row.id, n),
            },
            rowIconSz
          )
          ImGui.SameLine(0, 6)
        end
        if neonButton('Hand##dust_q_' .. tostring(row.id), 44, 0) then
          startTurnin({ singleDustItemId = row.id, singleDustName = row.name })
        end
        ImGui.SameLine(0, 6)
        pcall(function()
          ImGui.AlignTextToFramePadding()
        end)
        ImGui.Text(string.format('[%d] x%d  %s', row.id, n, row.name))
      end
    end
  elseif TRANSMUTE_DEVICE_DATA and uiTab == 'recipes' then
    ensureInvIdCountMap(CONFIG.recipeCountUiCacheSec or 0.65)
    local rg = buildRecipeGroups()
    for _, cat in ipairs(CATEGORY_ORDER) do
      local recs = rg[cat]
      if recs and #recs > 0 then
        local visible = {}
        for _, rec in ipairs(recs) do
          if nameVisible(rec.name) then
            table.insert(visible, rec)
          end
        end
        if #visible > 0 then
          local aggSets = {}
          local aggPerId = {}
          for _, rec in ipairs(visible) do
            local sets, perId = recipeMatAggregates(rec)
            aggSets[rec.key] = sets
            aggPerId[rec.key] = perId
          end
          local readyRecipes = 0
          local maxSetsAmongReady = 0
          for _, rec in ipairs(visible) do
            local sets = aggSets[rec.key] or 0
            if sets >= 1 then
              readyRecipes = readyRecipes + 1
              if sets > maxSetsAmongReady then
                maxSetsAmongReady = sets
              end
            end
          end
          local header = string.format(
            '%s — %d recipe(s) shown  |  %d with full mat(s)  |  up to %d set(s) on best row',
            cat,
            #visible,
            readyRecipes,
            maxSetsAmongReady
          )
          if ImGui.CollapsingHeader(header) then
            if neonButton('Hand in##rec_hand_' .. cat:gsub('%W', '_')) then
              startTurnin({ tab = 'recipes', category = cat })
            end
            ImGui.SameLine()
            ImGui.TextWrapped(string.format('Turn in craftable recipes in %s only (bottom Turn in = all categories).', cat))
            local sz = tonumber(CONFIG.recipeRowIconSize) or 22
            local rewardColW = CONFIG.recipeRowItemIcons and (sz + 8) or 168
            local handColW = 48
            local tblId = 'rec_tbl_' .. (cat:gsub('%W', '_'))
            local tblFlags = ImGuiTableFlags.BordersInnerV + ImGuiTableFlags.RowBg
            if ImGui.BeginTable(tblId, 5, tblFlags) then
              ImGui.TableSetupColumn('Use', ImGuiTableColumnFlags.WidthFixed, 36)
              ImGui.TableSetupColumn('Reward', ImGuiTableColumnFlags.WidthFixed, rewardColW)
              ImGui.TableSetupColumn('Hand', ImGuiTableColumnFlags.WidthFixed, handColW)
              ImGui.TableSetupColumn('Sets', ImGuiTableColumnFlags.WidthFixed, 76)
              ImGui.TableSetupColumn('Ingredients (in inventory)', ImGuiTableColumnFlags.WidthStretch)
              ImGui.TableHeadersRow()

              for _, rec in ipairs(visible) do
                local k = 'r' .. rec.key
                if enabled[k] == nil then
                  enabled[k] = false
                end
                local sel = not not enabled[k]
                local mc = aggSets[rec.key] or 0
                ImGui.TableNextRow()
                ImGui.TableNextColumn()
                ImGui.PushID('recipe_row_' .. rec.key)
                local changed, newVal = checkboxCompat('##rec_en_' .. rec.key, sel)
                if changed then
                  enabled[k] = newVal
                  dirty = true
                end
                ImGui.PopID()

                ImGui.TableNextColumn()
                if CONFIG.recipeRowItemIcons then
                  local outId = tonumber(rec.outputId) or 0
                  local outIcon = resolveEqItemIcon(outId > 0 and outId or nil, rec.name)
                  drawTransmuteItemIcon(
                    outIcon,
                    'tr_out_' .. rec.key,
                    { rec.name, 'Reward from this combine' },
                    sz
                  )
                else
                  pcall(function()
                    ImGui.AlignTextToFramePadding()
                  end)
                  ImGui.TextWrapped(rec.name)
                end

                ImGui.TableNextColumn()
                pcall(function()
                  ImGui.AlignTextToFramePadding()
                end)
                if neonButton('Hand##rec_row_' .. tostring(rec.key):gsub('%W', '_'), handColW - 4, 0) then
                  startTurnin({ singleRecipeKey = rec.key })
                end

                ImGui.TableNextColumn()
                pcall(function()
                  ImGui.AlignTextToFramePadding()
                end)
                ImGui.Text(string.format('x%d set(s)', mc))

                ImGui.TableNextColumn()
                if CONFIG.recipeRowItemIcons then
                  for mi, mid in ipairs(rec.mats) do
                    if mi > 1 then
                      ImGui.SameLine(0, 12)
                    end
                    ImGui.BeginGroup()
                    local have = countItemIdInInventoryCached(mid)
                    local mname = resolveItemNameById(mid)
                    local micon = resolveEqItemIcon(mid, nil)
                    drawTransmuteItemIcon(
                      micon,
                      'tr_mat_' .. rec.key .. '_' .. tostring(mi) .. '_' .. tostring(mid),
                      {
                        mname,
                        string.format('Ingredient id %d  |  in inventory: %d  (need 1 per set)', mid, have),
                      },
                      sz
                    )
                    ImGui.TextUnformatted(string.format(':%d', have))
                    ImGui.EndGroup()
                  end
                else
                  ImGui.TextWrapped(aggPerId[rec.key] or '')
                end
              end
              ImGui.EndTable()
            end
          end
        end
      end
    end
  end

  ImGui.Separator()
  --- Short launch label (targets CONFIG npc / device when Run is pressed).
  local runLabel = 'Turn in'
  if neonButton(runLabel) then
    startTurnin()
  end
  ImGui.SameLine()
  if neonButton('Stop') then
    abortTurnin('Stopped.')
  end

  ImGui.Spacing()
  ImGui.TextWrapped('Status: ' .. statusLine)
  if dirty then
    ImGui.TextWrapped('Unsaved toggles — click Save toggles.')
  end
  if TI.active then
    if TI.queue[1] and TI.queue[1].kind == 'recipe' then
      ImGui.TextWrapped(string.format('Running recipePhase=%d mat=%d queue=%d', TI.recipePhase or 0, TI.recipeMatIdx or 0, #TI.queue))
    elseif TI.queue[1] and TI.queue[1].kind == 'scroll_batch' then
      ImGui.TextWrapped(string.format('Running scrollBatch phase=%d idx=%d queue=%d', TI.sbPhase or 0, TI.sbIdx or 0, #TI.queue))
    else
      ImGui.TextWrapped(string.format('Running phase=%d queue=%d', TI.phase, #TI.queue))
    end
  end
end

local function render()
  --- Same as MAUI: submit the float **before** the main window so it always appears and stays clickable.
  ueqFloat.drawFloating({
    id = 'Transmute',
    resourceName = 'Transmute',
    windowTitle = 'Hide / show — Transmute',
    imageRelPath = 'transmute/ueq-transmute.png',
    sizePx = 100,
    placement = 'top_right',
    --- Stack below MAUI’s float if both use top-right (MAUI ~88px tall).
    offsetY = 96,
    fallbackLabel = 'TM',
    isAnyOpen = function()
      return uiOpen
    end,
    onClick = function()
      if uiOpen then
        if dirty then
          saveState()
        end
        uiOpen = false
      else
        uiOpen = true
      end
    end,
    tooltipHide = 'Hide Transmute window (script keeps running)',
    tooltipShow = 'Show Transmute (Assistant / Device)',
  })

  local ncolors, nvars = pushTransmuteTheme()
  local drawn = false
  if uiOpen then
    uiOpen, drawn = ImGui.Begin('Transmute — Assistant scrolls & Device (dust / recipes)', uiOpen)
    maybeRefreshInventory()
    turninTick()
    if drawn then
      local ok, err = pcall(drawUi)
      if not ok then
        pcall(function()
          ImGui.TextWrapped('Transmute UI error (Lua). See MQ echo; /lua run ... to capture stack.')
          ImGui.TextWrapped(tostring(err))
        end)
        mq.cmdf('/echo \ar[Transmute]\ax UI pcall: %s', tostring(err))
      end
    end
    ImGui.End()
  else
    maybeRefreshInventory()
    turninTick()
  end
  popTransmuteTheme(ncolors, nvars)
end

loadState()
refreshInventoryCache()
mq.imgui.init(SCRIPT_ID, render)

while not terminate do
  mq.delay(250, function()
    return terminate
  end)
end

