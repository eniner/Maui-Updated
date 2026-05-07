--[[
    JeevesPorter.lua
    ─────────────────────────────────────────────────────────────────
    Targets Jeeves (Guild Hall porter NPC) and issues /say <shortname>
    to request a zone port. Zones organized by expansion up through
    Omens of War.

    Usage: /lua run JeevesPorter
    ─────────────────────────────────────────────────────────────────
    Requires: MacroQuest (MQ2), lua + ImGui bindings
    Floating button art: lua/port/ueq-port.png (Ultimate EQ Port — bundled beside this script).
--]]

local mq         = require('mq')
local ImGui      = require('ImGui')
local ueqFloat   = require('ueq_logo_float')
local t_unpack   = table.unpack or unpack

-- ─────────────────────────────────────────────────────────────────
-- STATE
-- ─────────────────────────────────────────────────────────────────
local openGUI       = true
local running       = true
local pendingSayCommand = nil
local pendingTargetNpc = nil
local groupPortMode = false
local selectedXpac  = 1   -- index into expansions table
local statusMsg     = ""
local statusTimer   = 0
local STATUS_TTL    = 4   -- seconds status message shows
local ultimateAllowedOnly = false
local ultimateAllowedZones = {}
local ultimateAllowedCount = 0
local ultimateZonesSourcePath = "embedded"
local DEFAULT_TARGET_NPC = "Jeeves"
local NPC_CFG_FILE = "port_npc_targets.cfg"
local npcTargetsByServer = {}
local currentServerKey = "default"
local currentServerName = "default"
local activeTargetNpc = DEFAULT_TARGET_NPC
local npcInputName = DEFAULT_TARGET_NPC

local function trim(s)
    s = tostring(s or "")
    s = s:gsub("^%s+", "")
    s = s:gsub("%s+$", "")
    return s
end

local function sanitizeNpcName(s)
    s = trim(s)
    s = s:gsub("[\r\n\"]", "")
    return s
end

local ULTIMATE_ALLOWED_ZONE_KEYS = {
    "acrylia","airplane","akanon","arena","bazaar","befallen","blackburrow","burningwood","cabeast","cabwest",
    "cazicthule","chardok","citymist","cobaltscar","commonlands","crystal","dalnir","dawnshroud","dreadlands","dulak",
    "echo","erudnext","everfrost","fearplane","felwitheb","fieldofbone","firiona","freportn","frozenshadow","fungusgrove",
    "gfaydark","greatdivide","grobb","growthplane","gukbottom","guktop","halas","hateplaneb","highkeep","hole",
    "jaggedpine","kael","kaesora","karnor","kurn","lakeofillomen","maiden","mistmoore","najena","necropolis",
    "nexus","nro","nurga","oggok","overthere","paludal","paw","permafrost","pofire","poknowledge",
    "potactics","potranquility","rivervale","runnyeye","scarlet","sebilis","shadowhaven","skyfire","soldunga","soldungb",
    "solrotower","sro","ssratemple","thegrey","thurgadina","timorous","trakanon","umbral","unrest","veeshan",
    "veksar","velketor","vexthal","warrens","warslikswood",
}

local function dirname(path)
    path = tostring(path or "")
    local d = path:match("^(.*)[/\\][^/\\]+$")
    return d or "."
end

local function scriptDir()
    local src = debug.getinfo(1, "S").source or ""
    if src:sub(1, 1) == "@" then
        src = src:sub(2)
    end
    return dirname(src)
end

local function tryLoadAllowedZonesFromPath(path)
    local f = io.open(path, "r")
    if not f then return 0 end
    local count = 0
    for line in f:lines() do
        local key = line:match("^%s*([a-z0-9_]+)%s*=>%s*%{")
        if key and not ultimateAllowedZones[key] then
            ultimateAllowedZones[key] = true
            count = count + 1
        end
    end
    f:close()
    if count > 0 then
        ultimateZonesSourcePath = path
    end
    return count
end

local function loadUltimateAllowedZonesFromTxt()
    ultimateAllowedZones = {}
    ultimateAllowedCount = 0
    ultimateZonesSourcePath = "embedded"

    for _, key in ipairs(ULTIMATE_ALLOWED_ZONE_KEYS) do
        key = tostring(key):lower()
        if key ~= "" and not ultimateAllowedZones[key] then
            ultimateAllowedZones[key] = true
            ultimateAllowedCount = ultimateAllowedCount + 1
        end
    end
    return ultimateAllowedCount > 0
end

local function normalizeUltimateZoneKey(zoneKey)
    zoneKey = tostring(zoneKey or ""):lower()
    if zoneKey == "hateplane" then
        return "hateplaneb"
    end
    return zoneKey
end

local function isUltimateAllowedZone(zoneKey)
    zoneKey = normalizeUltimateZoneKey(zoneKey)
    return ultimateAllowedZones[zoneKey] == true
end

local function makeServerKey(serverName)
    local key = trim(serverName):lower()
    key = key:gsub("%s+", "_")
    key = key:gsub("[^%w_%-]", "")
    if key == "" then key = "default" end
    return key
end

local function getServerName()
    local ok, serverName = pcall(function() return mq.TLO.EverQuest.Server() end)
    if ok and serverName and tostring(serverName) ~= "" then
        return tostring(serverName)
    end
    return "default"
end

local function saveNpcConfig()
    local f = io.open(NPC_CFG_FILE, "w")
    if not f then return false end
    local keys = {}
    for k in pairs(npcTargetsByServer) do
        keys[#keys + 1] = k
    end
    table.sort(keys)
    for _, k in ipairs(keys) do
        local v = sanitizeNpcName(npcTargetsByServer[k] or "")
        f:write(string.format("%s=%s\n", k, v))
    end
    f:close()
    return true
end

local function loadNpcConfig()
    npcTargetsByServer = {}
    local f = io.open(NPC_CFG_FILE, "r")
    if not f then return end
    for line in f:lines() do
        local k, v = line:match("^([^=]+)=(.*)$")
        if k then
            k = trim(k)
            v = sanitizeNpcName(v)
            if k ~= "" then
                npcTargetsByServer[k] = v
            end
        end
    end
    f:close()
end

local function refreshServerNpcContext(force)
    local serverName = getServerName()
    local serverKey = makeServerKey(serverName)
    if not force and serverKey == currentServerKey then return end
    currentServerName = serverName
    currentServerKey = serverKey
    local saved = npcTargetsByServer[currentServerKey]
    if saved == nil then
        saved = DEFAULT_TARGET_NPC
    end
    activeTargetNpc = sanitizeNpcName(saved)
    npcInputName = activeTargetNpc
end

-- ─────────────────────────────────────────────────────────────────
-- EXPANSION / ZONE DATA
-- Key  = short zone name sent via /say
-- Label = button text displayed in the UI
-- ─────────────────────────────────────────────────────────────────
local expansions = {

    -------------------------------------------------------------------------
    {
        name = "Classic EQ",
        color = { 0.85, 0.75, 0.35, 1.0 },   -- warm gold
        zones = {
            -- Cities & Hubs
            { label = "S Qeynos",       key = "qeynos"       },
            { label = "N Qeynos",       key = "qeynos2"      },
            { label = "Surefall Glade", key = "qrg"          },
            { label = "Qeynos Hills",   key = "qeytoqrg"     },
            { label = "N Freeport",     key = "freportn"      },
            { label = "W Freeport",     key = "freportw"      },
            { label = "E Freeport",     key = "freporte"      },
            { label = "Halas",          key = "halas"         },
            { label = "Grobb",          key = "grobb"         },
            { label = "Oggok",          key = "oggok"         },
            { label = "Neriak FQ",      key = "neriaka"       },
            { label = "Neriak Commons", key = "neriakb"       },
            { label = "Neriak 3rd Gt",  key = "neriakc"       },
            { label = "Erudin",         key = "erudnext"      },
            { label = "Erudin Palace",  key = "erudnint"      },
            { label = "Paineel",        key = "paineel"       },
            { label = "Ak'Anon",        key = "akanon"        },
            { label = "Kaladim N",      key = "kaladima"      },
            { label = "Kaladim S",      key = "kaladimb"      },
            { label = "Felwithe N",     key = "felwithea"     },
            { label = "Felwithe S",     key = "felwitheb"     },
            -- Outdoor
            { label = "W Commonlands",  key = "commons"       },
            { label = "E Commonlands",  key = "ecommons"      },
            { label = "W Karana",       key = "qey2hh1"       },
            { label = "N Karana",       key = "northkarana"   },
            { label = "S Karana",       key = "southkarana"   },
            { label = "E Karana",       key = "eastkarana"    },
            { label = "Kithicor",       key = "kithicor"      },
            { label = "Highpass Hold",  key = "highpass"      },
            { label = "Nektulos",       key = "nektulos"      },
            { label = "N Ro",           key = "nro"           },
            { label = "S Ro",           key = "sro"           },
            { label = "Oasis of Marr",  key = "oasis"         },
            { label = "Toxxulia",       key = "tox"           },
            { label = "Innothule",      key = "innothule"     },
            { label = "The Feerrott",   key = "feerrott"      },
            { label = "Lavastorm",      key = "lavastorm"     },
            { label = "Misty Thicket",  key = "misty"         },
            { label = "Everfrost",      key = "everfrost"     },
            { label = "Steamfont",      key = "steamfont"     },
            { label = "Butcherblock",   key = "butcher"       },
            { label = "Ocean of Tears", key = "oot"           },
            { label = "Dagnor's Cld",   key = "cauldron"      },
            { label = "Rathe Mtn",      key = "rathemtn"      },
            { label = "Lake Rathe",     key = "lakerathe"     },
            { label = "Stonebrunt",     key = "stonebrunt"    },
            -- Dungeons
            { label = "Befallen",       key = "befallen"      },
            { label = "Blackburrow",    key = "blackburrow"   },
            { label = "Crushbone",      key = "crushbone"     },
            { label = "RunnyEye",       key = "runnyeye"      },
            { label = "Unrest",         key = "unrest"        },
            { label = "Mistmoore",      key = "mistmoore"     },
            { label = "Najena",         key = "najena"        },
            { label = "Kedge Keep",     key = "kedge"         },
            { label = "Upper Guk",      key = "guktop"        },
            { label = "Lower Guk",      key = "gukbottom"     },
            { label = "Permafrost",     key = "permafrost"    },
            { label = "The Hole",       key = "hole"          },
            { label = "Sol Eye",        key = "soldunga"      },
            { label = "Nagafen's Lair", key = "soldungb"      },
            { label = "Kerra Isle",     key = "kerraridge"    },
            { label = "Gorge/Xorbb",    key = "beholder"      },
            { label = "Infected Paw",   key = "paw"           },
            -- Planes
            { label = "Plane of Sky",   key = "airplane"      },
            { label = "Plane of Fear",  key = "fearplane"     },
            { label = "Plane of Hate",  key = "hateplane"     },
            -- Misc
            { label = "PoK",            key = "poknowledge"   },
            { label = "Bazaar",         key = "bazaar"        },
            { label = "Guild Lobby",    key = "guildlobby"    },
            { label = "Erud's Crossing",key = "erudsxing"     },
            { label = "Jaggedpine",     key = "jaggedpine"    },
            { label = "Nedaria's Ldg",  key = "nedaria"       },
        },
    },

    -------------------------------------------------------------------------
    {
        name = "Ruins of Kunark",
        color = { 0.65, 0.85, 0.45, 1.0 },   -- jungle green
        zones = {
            { label = "Field of Bone",  key = "fieldofbone"   },
            { label = "Warsliks Wood",  key = "warslikswood"  },
            { label = "W Cabilis",      key = "cabwest"       },
            { label = "E Cabilis",      key = "cabeast"       },
            { label = "Swamp NHope",    key = "swampofnohope" },
            { label = "Firiona Vie",    key = "firiona"       },
            { label = "Lake Ill Omen",  key = "lakeofillomen" },
            { label = "Dreadlands",     key = "dreadlands"    },
            { label = "Burning Wood",   key = "burningwood"   },
            { label = "Kaesora",        key = "kaesora"       },
            { label = "Old Sebilis",    key = "sebilis"       },
            { label = "City of Mist",   key = "citymist"      },
            { label = "Skyfire Mtn",    key = "skyfire"       },
            { label = "Frontier Mtn",   key = "frontiermtns"  },
            { label = "The Overthere",  key = "overthere"     },
            { label = "Emerald Jungle", key = "emeraldjungle" },
            { label = "Trakanon Teeth", key = "trakanon"      },
            { label = "Timorous Deep",  key = "timorous"      },
            { label = "Kurn's Tower",   key = "kurn"          },
            { label = "Karnor's Castle",key = "karnor"        },
            { label = "Chardok",        key = "chardok"       },
            { label = "Dalnir",         key = "dalnir"        },
            { label = "Howling Stones", key = "charasis"      },
            { label = "Mines of Nurga", key = "nurga"         },
            { label = "Veeshan's Peak", key = "veeshan"       },
            { label = "Veksar",         key = "veksar"        },
            { label = "Temple of Droga",key = "droga"         },
        },
    },

    -------------------------------------------------------------------------
    {
        name = "Scars of Velious",
        color = { 0.55, 0.80, 0.95, 1.0 },   -- ice blue
        zones = {
            { label = "Iceclad Ocean",  key = "iceclad"       },
            { label = "Tower Frz Shad", key = "frozenshadow"  },
            { label = "Velketor's Lab", key = "velketor"      },
            { label = "Kael Drakkal",   key = "kal"           },
            { label = "Skyshrine",      key = "skyshrine"     },
            { label = "Thurgadin",      key = "thurgadina"    },
            { label = "Icewell Keep",   key = "thurgadinb"    },
            { label = "Eastern Wastes", key = "eastwastes"    },
            { label = "Cobalt Scar",    key = "cobaltscar"    },
            { label = "Great Divide",   key = "greatdivide"   },
            { label = "Wakening Land",  key = "wakening"      },
            { label = "Western Wastes", key = "westwastes"    },
            { label = "Crystal Cavern", key = "crystal"       },
            { label = "Dragon Necro",   key = "necropolis"    },
            { label = "Temple Veeshan", key = "templeveeshan" },
            { label = "Siren's Grotto", key = "sirens"        },
            { label = "Plane Mischief", key = "mischiefplane" },
            { label = "Plane Growth",   key = "growthplane"   },
            { label = "Sleeper's Tomb", key = "sleeper"       },
        },
    },

    -------------------------------------------------------------------------
    {
        name = "Shadows of Luclin",
        color = { 0.75, 0.55, 0.95, 1.0 },   -- deep purple
        zones = {
            { label = "Shadow Haven",   key = "shadowhaven"   },
            { label = "The Nexus",      key = "nexus"         },
            { label = "Echo Caverns",   key = "echo"          },
            { label = "Acrylia Cavern", key = "acrylia"       },
            { label = "Shar Vahl",      key = "sharvahl"      },
            { label = "Paludal Cavern", key = "paludal"       },
            { label = "Fungus Grove",   key = "fungusgrove"   },
            { label = "Vex Thal",       key = "vexthal"       },
            { label = "Sanctus Seru",   key = "sseru"         },
            { label = "Katta Castellum",key = "katta"         },
            { label = "Netherbian",     key = "netherbian"    },
            { label = "Ssraeshza Tmpl", key = "ssratemple"    },
            { label = "Grieg's End",    key = "griegsend"     },
            { label = "The Deep",       key = "thedeep"       },
            { label = "Shadeweaver's",  key = "shadeweaver"   },
            { label = "Hollowshade",    key = "hollowshade"   },
            { label = "Grimling Forest",key = "grimling"       },
            { label = "Marus Seru",     key = "mseru"         },
            { label = "Mons Letalis",   key = "letalis"       },
            { label = "Twilight Sea",   key = "twilight"      },
            { label = "The Grey",       key = "thegrey"       },
            { label = "Tenebrous Mtn",  key = "tenebrous"     },
            { label = "Maiden's Eye",   key = "maiden"        },
            { label = "Dawnshroud",     key = "dawnshroud"    },
            { label = "Scarlet Desert", key = "scarlet"       },
            { label = "Umbral Plains",  key = "umbral"        },
            { label = "Akheva Ruins",   key = "akheva"        },
        },
    },

    -------------------------------------------------------------------------
    {
        name = "Planes of Power",
        color = { 0.95, 0.60, 0.25, 1.0 },   -- blazing orange
        zones = {
            { label = "PoK",            key = "poknowledge"   },
            { label = "Plane Tranq",    key = "potranquility" },
            { label = "Plane Justice",  key = "pojustice"     },
            { label = "Plane Nightmare",key = "ponightmare"   },
            { label = "Nightmare (B)",  key = "nightmareb"    },
            { label = "Plane Disease",  key = "podisease"     },
            { label = "Plane Innovate", key = "poinnovation"  },
            { label = "Plane Torment",  key = "potorment"     },
            { label = "Plane Valor",    key = "povalor"       },
            { label = "Bastion Thunder",key = "bothunder"     },
            { label = "Plane Storms",   key = "postorms"      },
            { label = "Halls of Honor", key = "hohonora"      },
            { label = "Halls Honor (B)",key = "hohonorb"      },
            { label = "Sol Ro Tower",   key = "solrotower"    },
            { label = "Plane of War",   key = "powar"         },
            { label = "Drunder Tactics",key = "potactics"     },
            { label = "Plane of Air",   key = "poair"         },
            { label = "Plane of Water", key = "powater"       },
            { label = "Plane of Fire",  key = "pofire"        },
            { label = "Plane Earth (A)",key = "poeartha"      },
            { label = "Plane Earth (B)",key = "poearthb"      },
            { label = "Plane Time (A)", key = "potimea"       },
            { label = "Plane Time (B)", key = "potimeb"       },
            { label = "Codecay",        key = "codecay"       },
        },
    },

    -------------------------------------------------------------------------
    {
        name = "Legacy of Ykesha",
        color = { 0.50, 0.85, 0.70, 1.0 },   -- teal
        zones = {
            { label = "Gulf Gunthak",   key = "gunthak"       },
            { label = "Dulak's Harbor", key = "dulak"         },
            { label = "Torgiran Mines", key = "torgiran"      },
            { label = "Crypt of Nadox", key = "nadox"         },
            { label = "Hate's Fury",    key = "hatesfury"     },
        },
    },

    -------------------------------------------------------------------------
    {
        name = "Lost Dungeons",
        color = { 0.90, 0.45, 0.45, 1.0 },   -- dungeon red
        zones = {
            -- Guk series
            { label = "Guk: Lost Souls",   key = "guka"   },
            { label = "Guk: Drown Crypt",  key = "gukb"   },
            { label = "Guk: Anc Aqueduct", key = "gukc"   },
            { label = "Guk: Mushroom Grv", key = "gukd"   },
            { label = "Guk: Forebod Pris", key = "guke"   },
            { label = "Guk: Chapel Witn",  key = "gukf"   },
            { label = "Guk: Root Garden",  key = "gukg"   },
            { label = "Guk: Accurs Sanct", key = "gukh"   },
            -- Ruj series
            { label = "Ruj: Blood Quarr",  key = "ruja"   },
            { label = "Ruj: Halls War",    key = "rujb"   },
            { label = "Ruj: Wind Bridges", key = "rujc"   },
            { label = "Ruj: Gladiator",    key = "rujd"   },
            { label = "Ruj: Drudge Hollo", key = "ruje"   },
            { label = "Ruj: Taskmaster",   key = "rujf"   },
            { label = "Ruj: Hidden Vale",  key = "rujg"   },
            { label = "Ruj: Blazing Forge",key = "rujh"   },
            { label = "Ruj: Arena Chance", key = "ruji"   },
            { label = "Ruj: Barracks War", key = "rujj"   },
            -- Tak series
            { label = "Tak: Sunken Lib",   key = "taka"   },
            { label = "Tak: Shifting Twr", key = "takb"   },
            { label = "Tak: Fading Tmpl",  key = "takc"   },
            { label = "Tak: Royal Obs",    key = "takd"   },
            { label = "Tak: River Recol",  key = "take"   },
            { label = "Tak: Sandfall Cor", key = "takf"   },
            { label = "Tak: Balancing Ch", key = "takg"   },
            { label = "Tak: Sweeping Td",  key = "takh"   },
            { label = "Tak: Antiq Palace", key = "taki"   },
            { label = "Tak: Prismatic Cor",key = "takj"   },
            -- Mir series
            { label = "Mir: Silent Gallery",key = "mira"  },
            { label = "Mir: Maw Menagerie",key = "mirb"   },
            { label = "Mir: Spider Den",   key = "mirc"   },
            { label = "Mir: Hushed Banq",  key = "mird"   },
            { label = "Mir: Frosted Halls",key = "mire"   },
            { label = "Mir: Forgot Waste", key = "mirf"   },
            { label = "Mir: Heart Menag",  key = "mirg"   },
            { label = "Mir: Morbid Lab",   key = "mirh"   },
            { label = "Mir: Theater Imp",  key = "miri"   },
            { label = "Mir: Grand Library",key = "mirj"   },
            -- MMC series
            { label = "MMC: Forlorn Cav",  key = "mmca"   },
            { label = "MMC: Dreary Grotto",key = "mmcb"   },
            { label = "MMC: Invoked Stone",key = "mmcc"   },
            { label = "MMC: Etern Afflict",key = "mmcd"   },
            { label = "MMC: Sepulcher Dm", key = "mmce"   },
            { label = "MMC: Ritual Summ",  key = "mmcf"   },
            { label = "MMC: Cesspits",     key = "mmcg"   },
            { label = "MMC: Aisles Blood", key = "mmch"   },
            { label = "MMC: Halls Sanguin",key = "mmci"   },
            { label = "MMC: Infernal Sanc",key = "mmcj"   },
        },
    },

    -------------------------------------------------------------------------
    {
        name = "Gates of Discord",
        color = { 0.55, 0.65, 0.90, 1.0 },   -- discord blue
        zones = {
            { label = "Abysmal Sea",    key = "abysmal"       },
            { label = "Natimbi",        key = "natimbi"       },
            { label = "Qinimi",         key = "qinimi"        },
            { label = "Riwwi",          key = "riwwi"         },
            { label = "Barindu",        key = "barindu"       },
            { label = "Ferubi",         key = "ferubi"        },
            { label = "SNihilia Pool",  key = "snpool"        },
            { label = "SNihilia Lair",  key = "snlair"        },
            { label = "SNihilia Plant", key = "snplant"       },
            { label = "SNihilia Crem",  key = "sncrematory"   },
            { label = "Tipt",           key = "tipt"          },
            { label = "Vxed",           key = "vxed"          },
            { label = "Yxtta",          key = "yxtta"         },
            { label = "Uqua",           key = "uqua"          },
            { label = "Kod'Taz",        key = "kodtaz"        },
            { label = "Ikkinz",         key = "ikkinz"        },
            { label = "Qvic",           key = "qvic"          },
            { label = "Qvic Hidden",    key = "qvicb"         },
            { label = "Inktu'Ta",       key = "inktuta"       },
            { label = "Txevu",          key = "txevu"         },
            { label = "Tacvi",          key = "tacvi"         },
        },
    },

    -------------------------------------------------------------------------
    {
        name = "Omens of War",
        color = { 0.95, 0.40, 0.40, 1.0 },   -- blood red
        zones = {
            { label = "Dranik's Scar",  key = "draniksscar"       },
            { label = "Wall of Slghtr", key = "wallofslaughter"   },
            { label = "Bloodfields",    key = "bloodfields"       },
            { label = "Nobles Causey",  key = "causeway"          },
            { label = "Harbingers Spr", key = "harbingers"        },
            { label = "Muramite PG",    key = "provinggrounds"    },
            { label = "MPG (A)",        key = "chambersa"         },
            { label = "MPG (B)",        key = "chambersb"         },
            { label = "MPG (C)",        key = "chambersc"         },
            { label = "MPG (D)",        key = "chambersd"         },
            { label = "MPG (E)",        key = "chamberse"         },
            { label = "MPG (F)",        key = "chambersf"         },
            { label = "Riftseeker Sn",  key = "riftseekers"       },
            { label = "Anguish",        key = "anguish"           },
            { label = "Ruined Dranik",  key = "dranik"            },
            { label = "Dranik Cat (A)", key = "dranikcatacombsa"  },
            { label = "Dranik Cat (B)", key = "dranikcatacombsb"  },
            { label = "Dranik Cat (C)", key = "dranikcatacombsc"  },
            { label = "Dranik Sew (A)", key = "draniksewersa"     },
            { label = "Dranik Sew (B)", key = "draniksewersb"     },
            { label = "Dranik Sew (C)", key = "draniksewersc"     },
            { label = "D Hollows (A)",  key = "dranikhollowsa"    },
            { label = "D Hollows (B)",  key = "dranikhollowsb"    },
            { label = "D Hollows (C)",  key = "dranikhollowsc"    },
            { label = "D Hollows (D)",  key = "dranikhollowsd"    },
            { label = "D Hollows (E)",  key = "dranikhollowse"    },
            { label = "D Hollows (F)",  key = "dranikhollowsf"    },
            { label = "D Hollows (G)",  key = "dranikhollowsg"    },
            { label = "D Hollows (H)",  key = "dranikhollowsh"    },
            { label = "D Hollows (I)",  key = "dranikhollowsi"    },
            { label = "D Hollows (J)",  key = "dranikhollowsj"    },
        },
    },

    -------------------------------------------------------------------------
    {
        name = "Ultimate Tier (Quake)",
        color = { 0.95, 0.70, 0.30, 1.0 },
        npc = "Quake",
        zones = {
            { label = "Crushbone",            key = "send_crushbone",                group_key = "send_group_crushbone",                allow_key = "crushbone"   },
            { label = "Upper Guk (Lane)",     key = "go_upper_guk",                  group_key = "go_upper_guk",                        allow_key = "guktop"      },
            { label = "Lower Guk (Lane)",     key = "go_lower_guk",                  group_key = "go_lower_guk",                        allow_key = "gukbottom"   },
            { label = "Sebilis (Lane)",       key = "go_sebilis",                    group_key = "go_sebilis",                          allow_key = "sebilis"     },
            { label = "Temple of Veeshan",    key = "send_temple_of_veeshan",        group_key = "send_group_temple_of_veeshan",        allow_key = "templeveeshan" },
            { label = "Kael Drakkel",         key = "send_kael_drakkel",             group_key = "send_group_kael_drakkel",             allow_key = "kael"        },
            { label = "Sleeper's Tomb",       key = "send_sleepers_tomb",            group_key = "send_group_sleepers_tomb",            allow_key = "sleeper"     },
        },
    },

    -------------------------------------------------------------------------
    {
        name = "Avatar Tier (Quake)",
        color = { 0.85, 0.52, 0.92, 1.0 },
        npc = "Quake",
        zones = {
            { label = "Blackburrow",          key = "send_blackburrow",              group_key = "send_group_blackburrow",              allow_key = "blackburrow" },
            { label = "Mistmoore",            key = "send_mistmoore",                group_key = "send_group_mistmoore",                allow_key = "mistmoore"   },
            { label = "Solusek A",            key = "send_solusek_a",                group_key = "send_group_solusek_a",                allow_key = "soldunga"    },
            { label = "The Hole (Lane)",      key = "go_the_hole",                   group_key = "go_the_hole",                         allow_key = "hole"        },
            { label = "ToFS (Lane)",          key = "go_tower_of_frozen_shadow",     group_key = "go_tower_of_frozen_shadow",           allow_key = "frozenshadow" },
            { label = "Veeshan's Peak",       key = "send_veeshans_peak",            group_key = "send_group_veeshans_peak",            allow_key = "veeshan"     },
        },
    },

    -------------------------------------------------------------------------
    {
        name = "Demigod Tier (Seism)",
        color = { 0.45, 0.90, 0.85, 1.0 },
        npc = "Seism",
        zones = {
            { label = "Ocean of Tears (Lane)",      key = "go_ocean_of_tears",            group_key = "go_ocean_of_tears",            allow_key = "oot"         },
            { label = "Unrest (Lane)",              key = "go_unrest",                    group_key = "go_unrest",                    allow_key = "unrest"      },
            { label = "Plane of Fear",              key = "send_plane_of_fear",           group_key = "send_group_plane_of_fear",     allow_key = "fearplane"   },
            { label = "Velketor's Lab (Lane)",      key = "go_velketor_labyrinth",        group_key = "go_velketor_labyrinth",        allow_key = "velketor"    },
            { label = "Treasure Goblin Vault",      key = "send_treasure_goblin_vault",   group_key = "send_group_treasure_goblin_vault", allow_key = "bertoxtemple" },
        },
    },

    -------------------------------------------------------------------------
    {
        name = "God Tier (Seism)",
        color = { 0.50, 0.80, 1.00, 1.0 },
        npc = "Harbinger of Dread",
        zones = {
            { label = "The Elddar Forest",    key = "send_elddar_forest",         group_key = "send_group_elddar_forest",         allow_key = "elddar"      },
            { label = "Old Kurns Tower",      key = "send_old_kurn",              group_key = "send_group_old_kurn",              allow_key = "oldkurn"     },
            { label = "Crystallos",           key = "send_crystallos",            group_key = "send_group_crystallos",            allow_key = "crystallos"  },
        },
    },

    -------------------------------------------------------------------------
    {
        name = "God Expeditions (Seism)",
        color = { 0.35, 0.78, 0.95, 1.0 },
        npc = "Harbinger of Dread",
        zones = {
            { label = "Caverns of Exile",     key = "go_sol_dungeon_c",           group_key = "go_sol_dungeon_c",           allow_key = "soldungc" },
            { label = "Bloodmoon Keep",       key = "go_bloodmoon_keep",          group_key = "go_bloodmoon_keep",          allow_key = "bloodmoon" },
        },
    },
}

-- ─────────────────────────────────────────────────────────────────
-- HELPERS
-- ─────────────────────────────────────────────────────────────────

local function targetPortNpc(targetOverride)
    local targetName = sanitizeNpcName(targetOverride or activeTargetNpc)
    if targetName == "" then
        return false
    end
    mq.cmdf('/target "%s"', targetName)
    mq.delay(300)
    local tgt = mq.TLO.Target.Name()
    if tgt and tgt:lower():find(targetName:lower(), 1, true) then
        return true
    end
    return false
end

local function buildZoneSayCommand(zone, sendGroup)
    if type(zone) ~= "table" then
        return nil
    end
    local key = tostring(zone.key or "")
    local cmd = tostring(zone.cmd or "")
    local groupCmd = tostring(zone.group_cmd or "")
    local groupKey = tostring(zone.group_key or "")

    if sendGroup then
        if groupCmd ~= "" then return groupCmd end
        if groupKey ~= "" then return groupKey end
        if key:match("^send_group_") then return key end
        if key:match("^send_") then return "send_group_" .. key:sub(6) end
        if cmd:match("^send_group_") then return cmd end
        if cmd:match("^send_") then return "send_group_" .. cmd:sub(6) end
        if key ~= "" then return "send_group_" .. key end
        if cmd ~= "" then return "send_group_" .. cmd end
        return nil
    end

    if cmd ~= "" then return cmd end
    if key ~= "" then return key end
    return nil
end

local function requestPort(zone, sendGroup, targetNpcName)
    local sayCommand = buildZoneSayCommand(zone, sendGroup)
    if not sayCommand or sayCommand == "" then
        statusMsg = "ERROR: Invalid zone key."
        statusTimer = STATUS_TTL
        return
    end
    pendingSayCommand = sayCommand
    pendingTargetNpc = sanitizeNpcName(targetNpcName or activeTargetNpc)
    statusMsg = string.format("Queued: /say %s", sayCommand)
    statusTimer = STATUS_TTL
end

local function processPendingPort()
    if not pendingSayCommand then return end
    local sayCommand = pendingSayCommand
    local targetNpcName = pendingTargetNpc
    pendingSayCommand = nil
    pendingTargetNpc = nil

    -- Runs in main loop thread; mq.delay is safe here.
    if not targetPortNpc(targetNpcName) then
        if sanitizeNpcName(targetNpcName or activeTargetNpc) == "" then
            statusMsg = "ERROR: Target NPC is blank. Set and save an NPC name."
        else
            statusMsg = string.format('ERROR: Could not find "%s" nearby!', sanitizeNpcName(targetNpcName or activeTargetNpc))
        end
        statusTimer = STATUS_TTL
        return
    end

    mq.cmdf('/say %s', sayCommand)
    statusMsg = string.format("Sent:  /say %s", sayCommand)
    statusTimer = STATUS_TTL
end

-- ─────────────────────────────────────────────────────────────────
-- IMGUI RENDER
-- ─────────────────────────────────────────────────────────────────

-- Accent colours
local COL_HEADER_BG    = { 0.12, 0.13, 0.16, 1.00 }
local COL_PANEL_BG     = { 0.09, 0.10, 0.13, 0.97 }
local COL_XPAC_SEL     = { 0.18, 0.22, 0.30, 1.00 }
local COL_XPAC_HOVER   = { 0.22, 0.27, 0.37, 1.00 }
local COL_STATUS_OK    = { 0.35, 0.85, 0.45, 1.0  }
local COL_STATUS_ERR   = { 0.95, 0.30, 0.30, 1.0  }
local COL_DIVIDER      = { 0.25, 0.28, 0.35, 1.0  }

local function pushBtnStyle(r, g, b)
    ImGui.PushStyleColor(ImGuiCol.Button,        r*0.55, g*0.55, b*0.55, 1.0)
    ImGui.PushStyleColor(ImGuiCol.ButtonHovered, r*0.80, g*0.80, b*0.80, 1.0)
    ImGui.PushStyleColor(ImGuiCol.ButtonActive,  r,      g,      b,      1.0)
end

local function popBtnStyle()
    ImGui.PopStyleColor(3)
end

local function uiInputTextValue(label, currentValue)
    local a, b = ImGui.InputText(label, tostring(currentValue or ""))
    if type(a) == "string" and type(b) == "boolean" then
        return a, b
    end
    if type(a) == "boolean" and type(b) == "string" then
        return b, a
    end
    if type(a) == "string" then
        return a, a ~= tostring(currentValue or "")
    end
    return tostring(currentValue or ""), false
end

local function renderGUI()
    --- Same pattern as MAUI / Transmute: float submits first; hides only the big window.
    ueqFloat.drawFloating({
        id = 'JeevesPorter',
        resourceName = 'Jeeves Porter',
        windowTitle = 'Hide / show — Jeeves Porter',
        imageRelPath = 'port/ueq-port.png',
        sizePx = 100,
        placement = 'top_right',
        offsetY = 184,
        fallbackLabel = 'PRT',
        isAnyOpen = function()
            return openGUI == true
        end,
        onClick = function()
            openGUI = not openGUI
        end,
        tooltipHide = 'Hide Jeeves Porter window (script keeps running)',
        tooltipShow = 'Show Jeeves Porter — guild hall ports',
    })

    if not openGUI then
        return
    end

    -- ── Window setup ──────────────────────────────────────────────
    ImGui.SetNextWindowSize(820, 560, ImGuiCond.FirstUseEver)
    local panelBg = COL_PANEL_BG
    local headerBg = COL_HEADER_BG
    if ultimateAllowedOnly then
        panelBg = { 0.06, 0.11, 0.10, 0.97 }
        headerBg = { 0.08, 0.22, 0.18, 1.00 }
    end
    ImGui.PushStyleColor(ImGuiCol.WindowBg,       t_unpack(panelBg))
    ImGui.PushStyleColor(ImGuiCol.TitleBgActive,  t_unpack(headerBg))
    ImGui.PushStyleColor(ImGuiCol.TitleBg,        t_unpack(headerBg))
    ImGui.PushStyleVar(ImGuiStyleVar.WindowRounding, 8.0)
    ImGui.PushStyleVar(ImGuiStyleVar.FrameRounding,  5.0)

    -- Compatibility note:
    -- In some MQ Lua ImGui builds, Begin() returns only one boolean and
    -- does not support the isOpen out-param pattern.
    local visible = ImGui.Begin("Jeeves Porter##JeevesPorter")

    ImGui.PopStyleColor(3)
    ImGui.PopStyleVar(2)

    local drawOK, drawErr = xpcall(function()
    if not visible then return end

    -- ── Title bar area ────────────────────────────────────────────
    ImGui.PushStyleColor(ImGuiCol.Text, 1.0, 0.85, 0.40, 1.0)
    ImGui.SetWindowFontScale(1.22)
    ImGui.Text("  JEEVES  PORTER")
    ImGui.SetWindowFontScale(1.0)
    ImGui.PopStyleColor()

    refreshServerNpcContext(false)

    ImGui.SameLine()
    -- Target NPC indicator
    local selectedExpansionForNpc = expansions[selectedXpac] or {}
    local targetNpcDisplay = sanitizeNpcName(selectedExpansionForNpc.npc or activeTargetNpc)
    local targetNpcNear = false
    if targetNpcDisplay ~= "" then
        local search = string.format('npc radius 200 "%s"', targetNpcDisplay)
        targetNpcNear = mq.TLO.Spawn(search).ID() ~= nil
    end
    if targetNpcNear then
        ImGui.PushStyleColor(ImGuiCol.Text, t_unpack(COL_STATUS_OK))
        ImGui.Text("  NPC in range")
    else
        ImGui.PushStyleColor(ImGuiCol.Text, 0.60, 0.60, 0.60, 1.0)
        if targetNpcDisplay == "" then
            ImGui.Text("  NPC not set")
        else
            ImGui.Text("  NPC not detected")
        end
    end
    ImGui.PopStyleColor()

    ImGui.Spacing()
    ImGui.PushStyleColor(ImGuiCol.Text, 0.75, 0.78, 0.85, 1.0)
    ImGui.Text(string.format(" Server: %s", currentServerName))
    ImGui.PopStyleColor()
    ImGui.SameLine()
    ImGui.Text("NPC:")
    ImGui.SameLine()
    local newNpcInput, npcChanged = uiInputTextValue("##targetNpcInput", npcInputName)
    if npcChanged then
        npcInputName = sanitizeNpcName(newNpcInput)
    end
    ImGui.SameLine()
    if ImGui.Button("Save NPC##saveTargetNpc") then
        local cleaned = sanitizeNpcName(npcInputName)
        npcTargetsByServer[currentServerKey] = cleaned
        activeTargetNpc = cleaned
        if saveNpcConfig() then
            if cleaned == "" then
                statusMsg = string.format("Saved blank NPC for %s", currentServerName)
            else
                statusMsg = string.format('Saved NPC "%s" for %s', cleaned, currentServerName)
            end
        else
            statusMsg = "ERROR: Failed to save NPC config file."
        end
        statusTimer = STATUS_TTL
    end
    ImGui.SameLine()
    if ImGui.Button("Clear##clearTargetNpcInput") then
        npcInputName = ""
    end
    ImGui.SameLine()
    if ImGui.Button("Default##defaultTargetNpc") then
        npcTargetsByServer[currentServerKey] = nil
        activeTargetNpc = DEFAULT_TARGET_NPC
        npcInputName = DEFAULT_TARGET_NPC
        if saveNpcConfig() then
            statusMsg = string.format('Reset default NPC "%s" for %s', DEFAULT_TARGET_NPC, currentServerName)
        else
            statusMsg = "ERROR: Failed to save NPC config file."
        end
        statusTimer = STATUS_TTL
    end

    ImGui.PushStyleColor(ImGuiCol.Separator, t_unpack(COL_DIVIDER))
    ImGui.Separator()
    ImGui.PopStyleColor()

    local modeLabel = ultimateAllowedOnly and "Mode: UltimateEQ Allowed Only" or "Mode: PEQ Full List"
    if ImGui.Button(modeLabel .. "##zoneModeToggle", 255, 24) then
        ultimateAllowedOnly = not ultimateAllowedOnly
    end
    ImGui.SameLine()
    ImGui.PushStyleColor(ImGuiCol.Text, 0.70, 0.75, 0.82, 1.0)
    ImGui.Text(string.format("Allowed zones (built-in): %d", ultimateAllowedCount))
    ImGui.PopStyleColor()
    ImGui.Spacing()

    -- ── Two‑column layout: left sidebar + right zone grid ─────────
    ImGui.Columns(2, "##mainCols", false)
    ImGui.SetColumnWidth(0, 175)

    -- LEFT: Expansion selector ─────────────────────────────────────
    ImGui.PushStyleVar(ImGuiStyleVar.ItemSpacing, 4, 3)
    ImGui.Spacing()
    ImGui.PushStyleColor(ImGuiCol.Text, 0.70, 0.75, 0.85, 1.0)
    ImGui.Text(" EXPANSION")
    ImGui.PopStyleColor()
    ImGui.Spacing()

    for i, xpac in ipairs(expansions) do
        local isSelected = (selectedXpac == i)
        local cr, cg, cb = xpac.color[1], xpac.color[2], xpac.color[3]

        if isSelected then
            ImGui.PushStyleColor(ImGuiCol.Header,        cr*0.30, cg*0.30, cb*0.30, 1.0)
            ImGui.PushStyleColor(ImGuiCol.HeaderHovered, cr*0.40, cg*0.40, cb*0.40, 1.0)
            ImGui.PushStyleColor(ImGuiCol.HeaderActive,  cr*0.45, cg*0.45, cb*0.45, 1.0)
            ImGui.PushStyleColor(ImGuiCol.Text, cr, cg, cb, 1.0)
        else
            ImGui.PushStyleColor(ImGuiCol.Header,        t_unpack(COL_XPAC_SEL))
            ImGui.PushStyleColor(ImGuiCol.HeaderHovered, t_unpack(COL_XPAC_HOVER))
            ImGui.PushStyleColor(ImGuiCol.HeaderActive,  0.25, 0.30, 0.42, 1.0)
            ImGui.PushStyleColor(ImGuiCol.Text, 0.80, 0.82, 0.88, 1.0)
        end

        if ImGui.Selectable(" " .. xpac.name, isSelected,
            ImGuiSelectableFlags.None, 160, 22) then
            selectedXpac = i
        end
        ImGui.PopStyleColor(4)
    end
    ImGui.PopStyleVar()

    -- RIGHT: Zone buttons ──────────────────────────────────────────
    ImGui.NextColumn()

    local xpac   = expansions[selectedXpac]
    local cr, cg, cb = xpac.color[1], xpac.color[2], xpac.color[3]

    -- Expansion label
    ImGui.Spacing()
    ImGui.PushStyleColor(ImGuiCol.Text, cr, cg, cb, 1.0)
    ImGui.SetWindowFontScale(1.10)
    ImGui.Text("  " .. xpac.name)
    ImGui.SetWindowFontScale(1.0)
    ImGui.PopStyleColor()

    ImGui.PushStyleColor(ImGuiCol.Separator, cr*0.50, cg*0.50, cb*0.50, 1.0)
    ImGui.Separator()
    ImGui.PopStyleColor()
    ImGui.Spacing()

    local inGroup = false
    do
        local okGroup, groupCount = pcall(function() return mq.TLO.Group() end)
        inGroup = okGroup and (tonumber(groupCount) or 0) > 0
    end
    local groupLeader = ""
    if inGroup then
        local okLeader, leaderName = pcall(function() return mq.TLO.Group.Leader() end)
        if okLeader and leaderName then
            groupLeader = tostring(leaderName)
        end
    end
    local myName = ""
    do
        local okClean, cleanName = pcall(function() return mq.TLO.Me.CleanName() end)
        if okClean and cleanName and tostring(cleanName) ~= "" then
            myName = tostring(cleanName)
        else
            local okName, plainName = pcall(function() return mq.TLO.Me.Name() end)
            if okName and plainName then
                myName = tostring(plainName)
            end
        end
    end
    local canGroupPort = inGroup and groupLeader ~= "" and myName ~= "" and groupLeader:lower() == myName:lower()
    local groupToggleLabel = (groupPortMode and "[X] " or "[ ] ") .. "Group Port On Click"
    if ImGui.Button(groupToggleLabel .. "##groupPortModeToggle") then
        groupPortMode = not groupPortMode
    end
    ImGui.SameLine()
    ImGui.PushStyleColor(ImGuiCol.Text, 0.65, 0.65, 0.65, 1.0)
    if canGroupPort then
        ImGui.Text("(leader ready)")
    else
        ImGui.Text("(leader required)")
    end
    ImGui.PopStyleColor()
    ImGui.Spacing()

    -- Zone buttons in a scrollable child
    ImGui.PushStyleColor(ImGuiCol.ChildBg, 0.08, 0.09, 0.12, 1.0)
    ImGui.BeginChild("##zoneScroll", 0, -38, false)

    pushBtnStyle(cr, cg, cb)
    ImGui.PushStyleVar(ImGuiStyleVar.ItemSpacing,   6,  6)
    ImGui.PushStyleVar(ImGuiStyleVar.FramePadding,  8,  5)

    local colCount  = 4
    local btnWidth  = 144
    local counter   = 0

    local drawnZoneCount = 0
    local okZoneDraw, zoneErr = pcall(function()
        for _, zone in ipairs(xpac.zones or {}) do
            local zoneLabel = tostring(zone.label or "Unknown Zone")
            local zoneKey = tostring(zone.key or "")
            local zoneTargetNpc = sanitizeNpcName(zone.npc or xpac.npc or activeTargetNpc)
            local allowKey = tostring(zone.allow_key or zoneKey)
            local zoneAllowed = (not ultimateAllowedOnly) or isUltimateAllowedZone(allowKey)
            if zoneAllowed then
                local widgetId = zoneLabel .. "##" .. (zoneKey ~= "" and zoneKey or ("invalid_" .. tostring(counter)))

                if counter > 0 and counter % colCount ~= 0 then
                    ImGui.SameLine()
                end
                if ImGui.Button(widgetId, btnWidth, 26) and zoneKey ~= "" then
                    if groupPortMode and not canGroupPort then
                        statusMsg = "ERROR: Group Port needs group leader."
                        statusTimer = STATUS_TTL
                    else
                        requestPort(zone, groupPortMode and canGroupPort, zoneTargetNpc)
                    end
                end
                -- Tooltip showing the exact short name that will be /say'd
                if ImGui.IsItemHovered() then
                    ImGui.BeginTooltip()
                    ImGui.PushStyleColor(ImGuiCol.Text, 0.90, 0.90, 0.60, 1.0)
                    local previewCmd = buildZoneSayCommand(zone, groupPortMode and canGroupPort)
                    ImGui.Text("/say " .. (previewCmd or "<missing key>"))
                    ImGui.Text("Target NPC: " .. (zoneTargetNpc ~= "" and zoneTargetNpc or "<none>"))
                    ImGui.PopStyleColor()
                    ImGui.EndTooltip()
                end
                counter = counter + 1
                drawnZoneCount = drawnZoneCount + 1
            end
        end
    end)

    ImGui.PopStyleVar(2)
    popBtnStyle()
    ImGui.EndChild()
    ImGui.PopStyleColor()

    if not okZoneDraw then
        statusMsg = "ERROR: UI draw failed, see MQ chat."
        statusTimer = STATUS_TTL
        mq.cmdf('/echo [JeevesPorter] UI draw error: %s', tostring(zoneErr))
    elseif ultimateAllowedOnly and drawnZoneCount == 0 then
        ImGui.PushStyleColor(ImGuiCol.Text, 0.75, 0.75, 0.75, 1.0)
        ImGui.Text("No allowed zones for this expansion in Ultimate mode.")
        ImGui.PopStyleColor()
    end

    -- ── Status bar ────────────────────────────────────────────────
    ImGui.Spacing()
    ImGui.PushStyleColor(ImGuiCol.Separator, t_unpack(COL_DIVIDER))
    ImGui.Separator()
    ImGui.PopStyleColor()

    if statusTimer > 0 then
        local isErr = statusMsg:find("^ERROR")
        if isErr then
            ImGui.PushStyleColor(ImGuiCol.Text, t_unpack(COL_STATUS_ERR))
        else
            ImGui.PushStyleColor(ImGuiCol.Text, t_unpack(COL_STATUS_OK))
        end
        ImGui.Text("  " .. statusMsg)
        ImGui.PopStyleColor()
    else
        ImGui.PushStyleColor(ImGuiCol.Text, 0.45, 0.48, 0.55, 1.0)
        if groupPortMode and canGroupPort then
            ImGui.Text("  Group mode: button click sends your group.")
        else
            ImGui.Text("  Click a zone button to have your target NPC port you there.")
        end
        ImGui.PopStyleColor()
    end

    ImGui.Columns(1)
    end, debug.traceback)

    local endOK, endErr = pcall(ImGui.End)
    if not endOK then
        mq.cmdf('/echo [JeevesPorter] ImGui.End error: %s', tostring(endErr))
    end

    if not drawOK then
        statusMsg = "ERROR: UI draw failed, see MQ chat."
        statusTimer = STATUS_TTL
        mq.cmdf('/echo [JeevesPorter] renderGUI error: %s', tostring(drawErr))
    end
end

-- ─────────────────────────────────────────────────────────────────
-- MAIN LOOP
-- ─────────────────────────────────────────────────────────────────

loadNpcConfig()
refreshServerNpcContext(true)
local allowedLoaded = loadUltimateAllowedZonesFromTxt()

mq.imgui.init("JeevesPorter", renderGUI)

mq.bind('/jeevesporter', function()
    openGUI = not openGUI
end)

mq.bind('/jeevesporterquit', function()
    running = false
end)

mq.cmdf('/echo [JeevesPorter] Loaded. NPC for %s: "%s". Toggle UI: floating logo or /jeevesporter; unload: /jeevesporterquit',
    currentServerName, sanitizeNpcName(activeTargetNpc))
if not allowedLoaded then
    mq.cmd('/echo [JeevesPorter] WARNING: Could not build embedded allowed-zone list.')
else
    mq.cmdf('/echo [JeevesPorter] Loaded %d embedded allowed zones (%s).', ultimateAllowedCount, ultimateZonesSourcePath)
end

local lastTime = os.time()
while running do
    processPendingPort()

    local now = os.time()
    local dt  = now - lastTime
    lastTime  = now

    if statusTimer > 0 then
        statusTimer = statusTimer - dt
        if statusTimer < 0 then statusTimer = 0 end
    end

    mq.delay(100)
end

mq.cmd('/echo [JeevesPorter] Window closed. Exiting.')
