-- DEV CONSOLE (RmlUi)
-- GM developer menu: sidebar navigation, command grid, dock, confirm modal.
local mq = require('mq')

local openGUI = true
local showUI = true

local GM_PREFIX = '#'

local searchText = ''
local filterText = ''
local rawCommandText = ''

local showConfirmDialog = false
local confirmPopupRequested = false
local confirmEntry = nil
local confirmParamText = ''

local lastSentCommand = '(none)'
local activeSectionIndex = 1

local function makeCmd(label, cmd, needsParam, dangerous, paramJoiner, transport)
    return {
        label = label,
        cmd = cmd,
        needsParam = needsParam or false,
        dangerous = dangerous or false,
        paramJoiner = paramJoiner,
        transport = transport or 'command',
    }
end

local sections = {
    {
        title = 'Basic GM Commands (Status 100)',
        defaultOpen = true,
        commands = {
            makeCmd('Find Item', 'fi', true),
            makeCmd('Sum Item', 'summonitem', true),
            -- Pass item id in the search/param box → #iteminfo <id> (see UltDev catalog notes).
            makeCmd('Item Info', 'iteminfo', true),
            makeCmd('Goto XYZ', 'goto', true),
            makeCmd('Zone', 'zone', true),
            makeCmd('Zone Stat', 'zonestatus', false),
            makeCmd('Set Level', 'level', true),
            makeCmd('Invul', 'invul', true),
            makeCmd('Hide Me', 'hideme', true),
            makeCmd('Stats', 'showstats', false),
            makeCmd('Freeze', 'freeze', false),
            makeCmd('Unfreeze', 'unfreeze', false),
            makeCmd('PK On', 'pkill', false),
            makeCmd('PK Off', 'unpkill', false),
            makeCmd('Guild', 'guild', true),
            makeCmd('Test Spwn', 'testspawn', false),
            makeCmd('Save', 'save', false),
            makeCmd('Mem Spell', 'memspell', true),
            makeCmd('Animate', 'doanim', true),
            makeCmd('Haste', 'haste', true),
            makeCmd('NPC Cast', 'npccast', true),
            makeCmd('Uptime', 'uptime', false),
            makeCmd('Version', 'version', false),
        },
    },
    -- Aligns with GM_COMMANDS_FROM_GMCONSOLE.txt / stock command.cpp names (mq.cmd '#…').
    {
        title = 'Stock zone commands (catalog / command.cpp)',
        commands = {
            makeCmd('Find Spell', 'find spell', true),
            makeCmd('List NPCs', 'list npcs', true),
            makeCmd('List Players', 'list players', true),
            makeCmd('List Corpses', 'list corpses', true),
            makeCmd('Cast Spell', 'castspell', true),
            makeCmd('NPC Type Spawn', 'npctypespawn', true),
            makeCmd('Count Item', 'countitem', true),
        },
    },
    {
        title = 'NPC/Corpse Management',
        commands = {
            makeCmd('List NPCs', 'ListNPCs', false),
            makeCmd('NPC Corps', 'ListNPCCorpses', false),
            makeCmd('Plyr Corps', 'ListPlayerCorpses', false),
            makeCmd('Del NPC C', 'DeleteNPCCorpses', false),
            makeCmd('Del Tgt C', 'deletecorpse', false),
            makeCmd('Del Plyr C', 'DeletePlayerCorpses', false),
        },
    },
    {
        title = 'Lead GM Commands (Status 150)',
        commands = {
            makeCmd('Summon', 'summon', true, true),
            makeCmd('Kick', 'kick', true, true),
            makeCmd('Set MOTD', 'motd', true, true),
            makeCmd('Z Shutdwn', 'zoneshutdown', true, true),
            makeCmd('Z Bootup', 'zonebootup', true, true),
            makeCmd('Lock Srv', 'lock', false, true),
            makeCmd('Unlock Srv', 'unlock', false, true),
        },
    },
    {
        title = 'Zone Management',
        commands = {
            makeCmd('Repop', 'repop', true),
            makeCmd('Reload ZC', 'reloadzctimers', false),
            makeCmd('Doors', 'doors', false),
            makeCmd('Rld Rules', 'reloadallrules', false),
        },
    },
    {
        title = 'Target/NPC Commands',
        commands = {
            makeCmd('Kill', 'kill', false),
            makeCmd('Depop', 'depop', false),
            makeCmd('Heal', 'heal', false),
            makeCmd('Spwn Add', 'npcspawnadd', false),
            makeCmd('Spwn Updt', 'npcspawnupdate', false),
            makeCmd('Repop Frc', 'repop force', false),
            makeCmd('Set Race', 'set race', true),
            makeCmd('Set Gndr', 'set gender', true),
        },
    },
    {
        title = 'Player/Character Commands',
        commands = {
            makeCmd('Plyr Info', 'player', true),
            makeCmd('GM Char', 'gmchar', true),
            makeCmd('Give Item', 'giveitem', true),
            makeCmd('Meditation', 'meditation', true),
            makeCmd('Lookup', 'lookup', true),
            makeCmd('Item Drop', 'itemdropped', true),
            makeCmd('Expedition', 'expedition', true),
            makeCmd('Create DZ', 'createdz', true),
            makeCmd('Kick Exp', 'kick exp', true),
        },
    },
    {
        title = 'GM Mode Controls',
        commands = {
            makeCmd('GM On', 'gm on', false),
            makeCmd('GM Off', 'gm off', false),
            makeCmd('Speed On', 'gmspeed on', false),
            makeCmd('Speed Off', 'gmspeed off', false),
        },
    },
    {
        title = 'Zone Controller Custom',
        defaultOpen = true,
        commands = {
            makeCmd('Quick Actions', 'viewquickactions', false, false, nil, 'say'),
            makeCmd('ZC Runtime', 'viewzcdiag', false, false, nil, 'say'),
            makeCmd('Remote Cmds', 'viewremotecommands', false, false, nil, 'say'),
            makeCmd('View Mobs', 'viewallmobs', false, false, nil, 'say'),
            makeCmd('View Tables', 'viewallloottables', false, false, nil, 'say'),
            makeCmd('View Loot', 'viewalllootdrops_0', false, false, nil, 'say'),
            makeCmd('Zone Info', 'viewzoneinfo', false, false, nil, 'say'),
            makeCmd('Ignored Mobs', 'viewignoredmobs', false, false, nil, 'say'),
            makeCmd('Depop Mobs', 'viewdepopmobs', false, false, nil, 'say'),
            makeCmd('Add Custom Mob', 'addnewcustommob', false, false, nil, 'say'),
            makeCmd('Batch Add Mobs', 'batchaddncustommobs', false, false, nil, 'say'),
            makeCmd('Add Item To Zone', 'addnewitemtozone', false, false, nil, 'say'),
            makeCmd('Remove Zone Items', 'removeallitemsfromitemtable', false, true, nil, 'say'),
            makeCmd('Save ZC Data', 'saveallchanges', false, false, nil, 'say'),
            makeCmd('Apply Updates', 'applyallchanges', false, false, nil, 'say'),
            makeCmd('Reset Updates', 'resetallchanges', false, false, nil, 'say'),
            makeCmd('Repop Bosses', 'repopallstaticbosses', false, false, nil, 'say'),
            makeCmd('Depop Bosses', 'depopallstaticbosses', false, false, nil, 'say'),
            makeCmd('Rebuff Zone', 'rebuffzone', false, false, nil, 'say'),
            makeCmd('Refresh Data', 'refreshzonedata', false, false, nil, 'say'),
            makeCmd('Add Ignore Mob', 'addnewignoremob#', true, false, '', 'say'),
            makeCmd('Add Depop Mob', 'addnewdepopmob#', true, false, '', 'say'),
            makeCmd('Remove Mob', 'removemob_', true, true, '', 'say'),
            makeCmd('Rename Mob', 'renamemob#', true, false, '', 'say'),
            makeCmd('Clone Mob', 'clonemob#', true, false, '', 'say'),
            makeCmd('Remove By Item', 'removeitembyname_', true, true, '', 'say'),
            makeCmd('Remove Ignored', 'removefromignored_', true, true, '', 'say'),
            makeCmd('Remove Depop', 'removefromdepop_', true, true, '', 'say'),
        },
    },
    {
        title = 'Zone Controller Advanced',
        commands = {
            makeCmd('Loot Tbl By Mob', 'vl_', true, false, '', 'say'),
            makeCmd('Loot Tbl Items', 'vtd_', true, false, '', 'say'),
            makeCmd('Quick Add Items', 'quickadditems_', true, false, '', 'say'),
            makeCmd('Item Details', 'viewitemdata_', true, false, '', 'say'),
            makeCmd('Type Stats', 'vts_', true, false, '', 'say'),
            makeCmd('Custom Stats', 'vcs_', true, false, '', 'say'),
            makeCmd('Final Stats', 'vfs_', true, false, '', 'say'),
            makeCmd('Assoc Tbls', 'viewallassociatedtables_', true, false, '', 'say'),
            makeCmd('Mobs By Table', 'viewmobsbyloottable_', true, false, '', 'say'),
            makeCmd('Drop List Page', 'viewalllootdrops_', true, false, '', 'say'),
            makeCmd('Remove Item All', 'removeitemfromalltables_', true, true, '', 'say'),
            makeCmd('Type Assign UI', 'vto_', true, false, '', 'say'),
            makeCmd('Custom Assign UI', 'vco_', true, false, '', 'say'),
            makeCmd('Assign Type Tbl', 'atts_', true, false, '', 'say'),
            makeCmd('Assign Cust Tbl', 'cl_', true, false, '', 'say'),
            makeCmd('Remove Type Tbl', 'rlt_', true, true, '', 'say'),
            makeCmd('Remove Cust Tbl', 'rct_', true, true, '', 'say'),
            makeCmd('Remove Loot Tbl', 'removeloottable_', true, true, '', 'say'),
            makeCmd('Create New Tbl', 'saynewloottableinfo', false, false, nil, 'say'),
            makeCmd('Create New Tbl #', '!wnt#', true, false, '', 'say'),
            makeCmd('Disp Assoc Tbls', 'displaytablesthatcanbeassociated_', true, false, '', 'say'),
            makeCmd('Add Loot Item', 'ali_', true, false, '', 'say'),
            makeCmd('Assign All Items', 'assignallitemstoloottable_', true, false, '', 'say'),
            makeCmd('Remove All TblItems', 'removeallitemsfromloottable_', true, true, '', 'say'),
            makeCmd('Add Item Id', '!additemid#', true, false, '', 'say'),
            makeCmd('Say Item Detail', 'sayitemdetails#', true, false, '', 'say'),
            makeCmd('Update Item #', '!updateitemdetails#', true, false, '', 'say'),
            makeCmd('Remove Item Data', 'removeitemdata_', true, true, '', 'say'),
            makeCmd('Type Stat +/-', 'ams#', true, false, '', 'say'),
            makeCmd('Toggle Type Stat', 'togglemobstat#', true, false, '', 'say'),
            makeCmd('Say Mob Stat', 'saymobstat#', true, false, '', 'say'),
            makeCmd('Custom Stat +/-', 'acs#', true, false, '', 'say'),
            makeCmd('Custom Stat -1', 'rcs#', true, false, '', 'say'),
            makeCmd('Toggle CStat', 'togglecustommobstat#', true, false, '', 'say'),
            makeCmd('Say CStat', 'saycustommobstat#', true, false, '', 'say'),
            makeCmd('Say Zone Info', 'sayzoneinfo#', true, false, '', 'say'),
            makeCmd('Custom Drop -', 'dclt_', true, false, '', 'say'),
            makeCmd('Custom Drop +', 'iclt_', true, false, '', 'say'),
            makeCmd('Type Drop -', 'dtlt_', true, false, '', 'say'),
            makeCmd('Type Drop +', 'itlt_', true, false, '', 'say'),
            makeCmd('Type Drop Set', 'stlt_', true, false, '', 'say'),
            makeCmd('Custom Drop Set', 'sclt_', true, false, '', 'say'),
        },
    },
    {
        title = 'Mel Flags Custom',
        defaultOpen = true,
        commands = {
            makeCmd('Hail Mel', 'Hail', false, false, nil, 'say'),
            makeCmd('Show My Flags', 'show_my_progression', false, false, nil, 'say'),
            makeCmd('Grant All Flags', 'gm_grant_all_flags', false, true, nil, 'say'),
            makeCmd('Delete All Flags', 'gm_delete_all_flags', false, true, nil, 'say'),
            makeCmd('Get Ult Charm', 'new_player_ultimate_charm', false, false, nil, 'say'),
            makeCmd('Info: Pre-Ult', 'info_pre_ultimate', false, false, nil, 'say'),
            makeCmd('Pre-Ult Tasks', 'pre_ultimate_tasks', false, false, nil, 'say'),
            makeCmd('Tasks (Alt)', 'tasks', false, false, nil, 'say'),
            makeCmd('Info: Ultimate', 'info_ultimate', false, false, nil, 'say'),
            makeCmd('Info: Avatar', 'info_avatar', false, false, nil, 'say'),
            makeCmd('Info: Demigod', 'info_demigod', false, false, nil, 'say'),
            makeCmd('Info: God', 'info_god', false, false, nil, 'say'),
            makeCmd('Req: Vanilla', 'vanilla_progression_requirements', false, false, nil, 'say'),
            makeCmd('Req: Kunark', 'kunark_progression_requirements', false, false, nil, 'say'),
            makeCmd('Req: Velious', 'velious_progression_requirements', false, false, nil, 'say'),
            makeCmd('Req: Luclin', 'luclin_progression_requirements', false, false, nil, 'say'),
            makeCmd('Req: PoP', 'pop_progression_requirements', false, false, nil, 'say'),
            makeCmd('Ult Access R1', 'Obtain Access to Ultimate Zones Rank 1', false, false, nil, 'say'),
            makeCmd('Ult Access R2', 'Obtain Access to Ultimate Zones Rank 2', false, false, nil, 'say'),
            makeCmd('Ult Access R3', 'Obtain Access to Ultimate Zones Rank 3', false, false, nil, 'say'),
            makeCmd('Ult Access R4', 'Obtain Access to Ultimate Zones Rank 4', false, false, nil, 'say'),
            makeCmd('Ult Access R5', 'Obtain Access to Ultimate Zones Rank 5', false, false, nil, 'say'),
            makeCmd('Avatar Access R1', 'Obtain Access to Avatar Zones Rank 1', false, false, nil, 'say'),
            makeCmd('Avatar Access R2', 'Obtain Access to Avatar Zones Rank 2', false, false, nil, 'say'),
            makeCmd('Avatar Access R3', 'Obtain Access to Avatar Zones Rank 3', false, false, nil, 'say'),
            makeCmd('Avatar Access R4', 'Obtain Access to Avatar Zones Rank 4', false, false, nil, 'say'),
            makeCmd('Demigod Access R1', 'Obtain Access to Demigod Zones Rank 1', false, false, nil, 'say'),
            makeCmd('Demigod Access R2', 'Obtain Access to Demigod Zones Rank 2', false, false, nil, 'say'),
            makeCmd('Demigod Access R3', 'Obtain Access to Demigod Zones Rank 3', false, false, nil, 'say'),
            makeCmd('Demigod Access R4', 'Obtain Access to Demigod Zones Rank 4', false, false, nil, 'say'),
            makeCmd('God Access R1', 'Obtain Access to God Zones Rank 1', false, false, nil, 'say'),
            makeCmd('God Access R2', 'Obtain Access to God Zones Rank 2', false, false, nil, 'say'),
            makeCmd('Ult Access T1', 'Obtain Access to Ultimate Zones Tier 1', false, false, nil, 'say'),
            makeCmd('Ult Access T2', 'Obtain Access to Ultimate Zones Tier 2', false, false, nil, 'say'),
            makeCmd('Ult Access T3', 'Obtain Access to Ultimate Zones Tier 3', false, false, nil, 'say'),
            makeCmd('Ult Access T4', 'Obtain Access to Ultimate Zones Tier 4', false, false, nil, 'say'),
            makeCmd('Ult Access T5', 'Obtain Access to Ultimate Zones Tier 5', false, false, nil, 'say'),
            makeCmd('Avatar Access T1', 'Obtain Access to Avatar Zones Tier 1', false, false, nil, 'say'),
            makeCmd('Avatar Access T2', 'Obtain Access to Avatar Zones Tier 2', false, false, nil, 'say'),
            makeCmd('Avatar Access T3', 'Obtain Access to Avatar Zones Tier 3', false, false, nil, 'say'),
            makeCmd('Avatar Access T4', 'Obtain Access to Avatar Zones Tier 4', false, false, nil, 'say'),
            makeCmd('Demigod Access T1', 'Obtain Access to Demigod Zones Tier 1', false, false, nil, 'say'),
            makeCmd('Defeat Megaladon', 'Defeat Uber Megaladon', false, false, nil, 'say'),
            makeCmd('Lost Palantir', "I've_Lost_My_Palantir_of_the_Ascended", false, false, nil, 'say'),
            makeCmd('Pal UL', 'pal_ul', false, false, nil, 'say'),
            makeCmd('TP Forge', 'teleport_to_forge', false, false, nil, 'say'),
            makeCmd('TP Phil', 'teleport_to_phil', false, false, nil, 'say'),
            makeCmd('TP Quake', 'teleport_to_quake', false, false, nil, 'say'),
            makeCmd('TP Seism', 'teleport_to_seism', false, false, nil, 'say'),
            makeCmd('TP Illuminous', 'teleport_to_illuminous', false, false, nil, 'say'),
        },
    },
    {
        title = 'Lower Guk Guide Custom',
        commands = {
            makeCmd('Hail LGuk Guide', 'Hail', false, false, nil, 'say'),
            makeCmd('Learn Zone', 'learning about the zone', false, false, nil, 'say'),
            makeCmd('Boss Drops', 'boss drops', false, false, nil, 'say'),
            makeCmd('Sebilis Key Info', 'key to Ultimate Sebilis', false, false, nil, 'say'),
        },
    },
    {
        title = 'Blackburrow Forge Custom',
        commands = {
            makeCmd('Hail Forge', 'Hail', false, false, nil, 'say'),
            makeCmd('Interesting Scrolls', 'interesting scrolls', false, false, nil, 'say'),
            makeCmd('New Armor', 'new armor', false, false, nil, 'say'),
            makeCmd('Powersource', 'powersource', false, false, nil, 'say'),
            makeCmd('Primal Weapons', 'primal weapons', false, false, nil, 'say'),
        },
    },
    {
        title = 'Guild Lobby Forge Custom',
        commands = {
            makeCmd('Hail Forge', 'Hail', false, false, nil, 'say'),
            makeCmd('Ultimate Menu', 'ultimate_weapons_menu', false, false, nil, 'say'),
            makeCmd('Ult 1.0 Info', 'ultimate_weapons_desc', false, false, nil, 'say'),
            makeCmd('Ult 1.0 How-To', 'ultimate_weapons_howto', false, false, nil, 'say'),
            makeCmd('Ult 1.5 Info', 'ultimate_ultimate_desc', false, false, nil, 'say'),
            makeCmd('Quality Chances', 'ultimate_weapons_percent', false, false, nil, 'say'),
            makeCmd('Show Ult 1.0', 'ultimate_weapons_show_base', false, false, nil, 'say'),
            makeCmd('Show Ult 1.5', 'ultimate_weapons_show_ultimate', false, false, nil, 'say'),
            makeCmd('Ultimate Credits', 'ultimate_credits', false, false, nil, 'say'),
            makeCmd('TP Aftershock', 'teleport_to_aftershock', false, false, nil, 'say'),
            makeCmd('View Materials', 'viewmaterials_', true, false, '', 'say'),
            makeCmd('View Qualities', 'viewqualities_', true, false, '', 'say'),
            makeCmd('Forge Debug', 'debug', false, false, nil, 'say'),
        },
    },
}

local outfitterClassOrder = {
    { id = 1, name = 'Warrior', tag = 'WAR' },
    { id = 2, name = 'Cleric', tag = 'CLR' },
    { id = 3, name = 'Paladin', tag = 'PAL' },
    { id = 4, name = 'Ranger', tag = 'RNG' },
    { id = 5, name = 'Shadowknight', tag = 'SHD' },
    { id = 6, name = 'Druid', tag = 'DRU' },
    { id = 7, name = 'Monk', tag = 'MNK' },
    { id = 8, name = 'Bard', tag = 'BRD' },
    { id = 9, name = 'Rogue', tag = 'ROG' },
    { id = 10, name = 'Shaman', tag = 'SHM' },
    { id = 11, name = 'Necromancer', tag = 'NEC' },
    { id = 12, name = 'Wizard', tag = 'WIZ' },
    { id = 13, name = 'Magician', tag = 'MAG' },
    { id = 14, name = 'Enchanter', tag = 'ENC' },
    { id = 15, name = 'Beastlord', tag = 'BST' },
    { id = 16, name = 'Berserker', tag = 'BER' },
}

local outfitterCategoryOrder = {
    { key = 'gear', label = 'Gear' },
    { key = 'perfected', label = 'Perfected' },
    { key = 'ultimate', label = 'Ultimate' },
    { key = 'epic1', label = 'Epic1Aug' },
}

local outfitterItemsByClass = {
    [1] = {
        gear = { 149371, 149088, 149375, 149370, 149374, 149373, 149373, 149376, 149372 },
        perfected = { 149208, 149183, 149021, 149022 },
        ultimate = { 149192, 147723, 147723 },
        epic1 = { 147576, 127930 },
    },
    [2] = {
        gear = { 149371, 149088, 149375, 149370, 149374, 149373, 149373, 149376, 149372 },
        perfected = { 149201, 149013 },
        ultimate = { 149116, 149117 },
        epic1 = { 147585, 127916 },
    },
    [3] = {
        gear = { 149371, 149088, 149375, 149370, 149374, 149373, 149373, 149376, 149372 },
        perfected = { 149202, 149012, 149011 },
        ultimate = { 149071, 149165, 149211 },
        epic1 = { 147583, 127923 },
    },
    [4] = {
        gear = { 149385, 149089, 149390, 149389, 149386, 149387, 149387, 149384, 149388 },
        perfected = { 149204, 149016 },
        ultimate = { 149121 },
        epic1 = { 147575, 127924 },
    },
    [5] = {
        gear = { 149371, 149088, 149375, 149370, 149374, 149373, 149373, 149376, 149372 },
        perfected = { 149106, 149002 },
        ultimate = { 149047, 149134, 149210, 147893, 147656, 127960 },
        epic1 = { 147582, 127927 },
    },
    [6] = {
        gear = { 149394, 149090, 149395, 149399, 149393, 149397, 149397, 149398, 149396 },
        perfected = { 149200, 149008 },
        ultimate = { 149115, 147907, 147713, 127952 },
        epic1 = { 147578, 127917 },
    },
    [7] = {
        gear = { 149394, 149090, 149395, 149399, 149393, 149397, 149397, 149398, 149396 },
        perfected = { 149207, 149182, 149019, 149017 },
        ultimate = { 149188, 149189, 147649, 147891 },
        epic1 = { 147573, 127920 },
    },
    [8] = {
        gear = { 149371, 149088, 149375, 149370, 149374, 149373, 149373, 149376, 149372 },
        perfected = { 149205, 149195, 149015 },
        ultimate = { 149122, 149194, 149238 },
        epic1 = { 147577, 127913 },
    },
    [9] = {
        gear = { 149385, 149089, 149390, 149389, 149386, 149387, 149387, 149384, 149388 },
        perfected = { 149206, 149181, 149020, 149018, 149023 },
        ultimate = { 149186, 149187 },
        epic1 = { 147574, 127925 },
    },
    [10] = {
        gear = { 149385, 149089, 149390, 149389, 149386, 149387, 149387, 149384, 149388 },
        perfected = { 149199, 149009, 149010 },
        ultimate = { 149114, 149185, 147900, 147687, 127961 },
        epic1 = { 147584, 127926 },
    },
    [11] = {
        gear = { 149377, 149091, 149378, 149382, 149381, 149380, 149380, 149379, 149383 },
        perfected = { 149196, 149003 },
        ultimate = { 149108, 147903, 147711, 127956 },
        epic1 = { 147581, 127921 },
    },
    [12] = {
        gear = { 149377, 149091, 149378, 149382, 149381, 149380, 149380, 149379, 149383 },
        perfected = { 149197, 149001 },
        ultimate = { 149112, 147905, 147702, 127963 },
        epic1 = { 147579, 127931 },
    },
    [13] = {
        gear = { 149377, 149091, 149378, 149382, 149381, 149380, 149380, 149379, 149383 },
        perfected = { 149107, 149004, 149005 },
        ultimate = { 149110, 149111, 147897, 147697, 127954 },
        epic1 = { 147588, 127919 },
    },
    [14] = {
        gear = { 149377, 149091, 149378, 149382, 149381, 149380, 149380, 149379, 149383 },
        perfected = { 149198, 149007, 149006 },
        ultimate = { 149113 },
        epic1 = { 147580, 127918 },
    },
    [15] = {
        gear = { 149394, 149090, 149395, 149399, 149393, 149397, 149397, 149398, 149396 },
        perfected = { 149203, 149173, 149014 },
        ultimate = { 149119, 149120, 147649, 147891 },
        epic1 = { 147586, 127914 },
    },
    [16] = {
        gear = { 149385, 149089, 149390, 149389, 149386, 149387, 149387, 149384, 149388 },
        perfected = { 149209, 149184, 149025, 149024 },
        ultimate = { 149190, 149191, 147908, 147723, 127950 },
        epic1 = { 147587, 127915 },
    },
}

local outfitterExtraGroupOrder = {
    'Seals and Baubles',
    'Weapon Augs',
    'Type Seven Augs',
    'Special Items',
    'Non-Vis',
    'Cloaks and Masks',
    'Trait Shield',
    'Trait Wep Bracer',
    'Stones',
    'Latest Charm',
    'Dye',
}

local outfitterExtraItems = {
    ['Seals and Baubles'] = {
        149069, 149070, 149051, 149052, 149053, 149233, 149054, 149055, 149056, 149057, 149058,
        149059, 149060, 149061, 149062, 149063, 149064, 149065, 149066, 149067, 149068,
    },
    ['Weapon Augs'] = { 149448, 149449, 149451, 149439, 149440, 149441, 149450, 149455, 149442, 149456 },
    ['Type Seven Augs'] = { 149100, 149101, 149102, 149103, 149104, 149105, 148826, 148830, 148822, 148824, 148825 },
    ['Special Items'] = { 149436, 149437, 149438, 148842, 148843, 148844, 148845 },
    ['Non-Vis'] = { 149404, 149405, 149407, 149406, 149408, 149409, 149410, 149411, 149412, 149413, 149414, 149415, 149416 },
    ['Cloaks and Masks'] = { 149290, 149289, 149288, 149287, 149286, 149285, 149284, 149300, 149296, 149297, 149295 },
    ['Trait Shield'] = { 149424, 149434, 149403, 149431, 149420, 149454 },
    ['Trait Wep Bracer'] = { 149433, 149428, 149419, 149429, 149430, 149401, 149425, 149426, 149435 },
    ['Stones'] = { 149417 },
    ['Latest Charm'] = { 149362 },
    ['Dye'] = { 32557 },
}

local aftershockGroupOrder = {
    'Utility Clickies',
    'Progression Boosters',
    'Currency Transfer',
    'Potions',
    'God Tier',
    'Credit Tokens',
}

local aftershockItems = {
    ['Utility Clickies'] = {
        149342, 149346, 149356, 149343, 149849, 149850, 149421,
        149323, 149324, 149332, 149333, 149334,
    },
    ['Progression Boosters'] = {
        149840, 148332, 148326, 148327, 147763, 147496, 148368, 147910, 148124, 148987,
    },
    ['Currency Transfer'] = {
        149843, 149325, 149326, 149327, 149328, 149329, 149423, 149841, 149842,
    },
    ['Potions'] = {
        149839, 149038, 149039, 149847, 149848, 149229, 149230, 149231, 149311, 149312, 150262,
    },
    ['God Tier'] = {
        149918, 149919, 150037, 150038, 150039, 150047, 150049,
    },
    ['Credit Tokens'] = {
        149337, 149338, 149339, 149340,
    },
}

-- Mel (progression guide NPC): hand-in / chain items in quest order (UltimateEQ Perl script).
local melProgressionGroupOrder = {
    'Pre-Ult: Vanilla (Task 1)',
    'Pre-Ult: Kunark (Task 2)',
    'Pre-Ult: Velious (Task 3)',
    'Pre-Ult: Luclin (Task 4)',
    'Pre-Ult: Planes of Power (Task 5)',
    'Ultimate: Crushbone token (Rank 1)',
    'Ultimate: Guk heads (Rank 2)',
    'Ultimate: Temple of Veeshan (Rank 4)',
    'Ultimate: Kael Drakkel (Rank 5)',
    'Ultimate: Sleepers Tomb',
    'Avatar: Tier One heads',
    'Avatar: The Hole',
    'Avatar: Tower of Frozen Shadow',
    'Demigod: Veeshans Peak',
    'Demigod: Ocean of Tears / Unrest',
    'Demigod: Plane of Fear',
    'Demigod: Velketors Labyrinth',
    'God: Goblin Vault',
    'God: Crystallos (Tier 2)',
}

local melProgressionItems = {
    ['Pre-Ult: Vanilla (Task 1)'] = { 147528, 147533, 147532, 1079 },
    ['Pre-Ult: Kunark (Task 2)'] = { 147531, 147534, 147535, 147536 },
    -- Legacy 4-item set + Tunare; script also accepts 3-item set without 147541 while PoG disabled.
    ['Pre-Ult: Velious (Task 3)'] = { 147540, 147541, 147542, 147537 },
    ['Pre-Ult: Luclin (Task 4)'] = { 147543, 147544, 147545, 147538 },
    ['Pre-Ult: Planes of Power (Task 5)'] = { 147636, 147637, 147638, 147539 },
    ['Ultimate: Crushbone token (Rank 1)'] = { 147639 },
    ['Ultimate: Guk heads (Rank 2)'] = { 147800, 147801, 147802, 147803 },
    ['Ultimate: Temple of Veeshan (Rank 4)'] = { 148099 },
    ['Ultimate: Kael Drakkel (Rank 5)'] = { 148165 },
    ['Ultimate: Sleepers Tomb'] = { 149860 },
    ['Avatar: Tier One heads'] = { 148563, 148564, 148565 },
    ['Avatar: The Hole'] = { 148605 },
    ['Avatar: Tower of Frozen Shadow'] = { 148807 },
    ['Demigod: Veeshans Peak'] = { 148973 },
    ['Demigod: Ocean of Tears / Unrest'] = { 149050, 149241 },
    ['Demigod: Plane of Fear'] = { 149257 },
    ['Demigod: Velketors Labyrinth'] = { 149391 },
    ['God: Goblin Vault'] = { 149453 },
    ['God: Crystallos (Tier 2)'] = { 150048 },
}

-- Lower Guk guide NPC: informational drops + key heads.
local lowerGukGroupOrder = {
    'Zone Materials',
    'Sebilis Key Heads (UGuk + LGuk)',
    'Boss Drops - Live Side',
    'Boss Drops - Undead Side',
}

local lowerGukItems = {
    ['Zone Materials'] = { 147496, 147763 },
    ['Sebilis Key Heads (UGuk + LGuk)'] = { 147800, 147801, 147802, 147803 },
    ['Boss Drops - Live Side'] = {
        147898, 147753, 147751, 147744, 147740, 147757, 147789, 147761, 147788, 147762, 147747, 147736,
    },
    ['Boss Drops - Undead Side'] = {
        147759, 147757, 147733, 147732, 147738, 147741, 147735, 147734, 147756, 147760, 147797, 147737,
        147736, 147758, 147754, 147752, 147748, 147745, 147749, 147750, 147746,
    },
}

-- Blackburrow Forge NPC: scroll teaching, avatar armor crafting, powersource and primal upgrades.
local blackburrowForgeGroupOrder = {
    'Spell / Discipline Scrolls',
    'Avatar Armor Reagents and Molds',
    'Avatar Armor Crafted Results',
    'Powersource Upgrade Path',
    'Primal Weapon Upgrade Path',
}

local blackburrowForgeItems = {
    ['Spell / Discipline Scrolls'] = {
        148508, 148509, 148510, 148511, 148512, 148513, 148514, 148515, 148516, 148517, 148518, 148519,
        148520, 148521, 148522, 148523, 148524, 148525, 148526, 148527, 148528, 148529, 148530, 148531,
        148532, 148533, 148534, 148535, 148536, 148537, 148538, 148539, 148540, 148541, 148542, 148543,
        148544, 148549, 148550, 148588, 148590, 148591, 148592, 148616, 148730, 148738, 149224,
    },
    ['Avatar Armor Reagents and Molds'] = {
        148367, 148368, 148369, 148370, 148371, 148372, 148373, 148389, 148545, 148374, 148375, 148376,
        148377, 148378, 148390, 148446, 148379, 148380, 148381, 148382, 148383, 148391, 148546, 148384,
        148385, 148386, 148387, 148388, 148392, 148547,
    },
    ['Avatar Armor Crafted Results'] = {
        148395, 148396, 148397, 148398, 148399, 148400, 148401, 148402, 148403, 148404, 148405, 148406,
        148407, 148408, 148409, 148410, 148411, 148412, 148413, 148414, 148415, 148416, 148417, 148418,
        148419, 148420, 148421, 148422, 148423, 148424, 148425, 148426, 148427, 148428, 148429, 148430,
        148431, 148432, 148433, 148434, 148435, 148436, 148437, 148438, 148439, 148440, 148441, 148442,
        148443, 148444, 148445, 148447, 148448, 148449, 148450, 148451, 148452, 148453, 148454, 148455,
        148456, 148457, 148458, 148459, 148460, 148461, 148462, 148463, 148464, 148465, 148466, 148467,
        148468, 148469, 148470, 148471, 148472, 148473, 148474, 148475, 148476, 148477, 148478, 148479,
        148480, 148481, 148482, 148483, 148484, 148485, 148486, 148487, 148488, 148489, 148490, 148491,
        148492, 148493, 148494, 148495, 148496, 148497, 148498, 148499, 148500, 148501, 148502, 148503,
        148504, 148505, 148506, 148507,
    },
    ['Powersource Upgrade Path'] = {
        148563, 148564, 148565, 148315, 148316, 148317, 148318, 148319, 148321, 148582, 148583, 148584,
        148585, 148586, 148587,
    },
    ['Primal Weapon Upgrade Path'] = {
        148331, 148589, 148188, 148189, 148190, 148191, 148193, 148195, 148197, 148570, 148571, 148572,
        148573, 148574, 148575, 148576,
    },
}

-- Guild Lobby Forge NPC is mostly dynamic (craft hash driven), but these are fixed hand-in anchors.
local guildLobbyForgeGroupOrder = {
    'Ultimate Weapon Core Materials',
    'Crushbone Unlock Gate',
}

local guildLobbyForgeItems = {
    ['Ultimate Weapon Core Materials'] = { 147763, 147496 },
    ['Crushbone Unlock Gate'] = { 147639 },
}

local outfitterItemNameById = {}
local outfitterItemIconById = {}
local outfitterItemClassById = {}
local outfitterItemSlotById = {}
local outfitterItemLevelById = {}
local outfitterCatalogLoaded = false
local outfitterCatalogLoadAttempted = false
local outfitterCatalogNextRetryAt = 0
local outfitterCatalogBridgeTried = false
local outfitterCatalogBridge = nil
local outfitterCatalogBridgeJson = nil
local outfitterCatalogBridgeSettings = nil
local EQ_ICON_OFFSET = 500
local animItems = mq.FindTextureAnimation('A_DragItem')

local classIdToTag = {}
for _, c in ipairs(outfitterClassOrder) do
    classIdToTag[c.id] = c.tag
end

local classNameToTag = {
    WARRIOR = 'WAR', CLERIC = 'CLR', PALADIN = 'PAL', RANGER = 'RNG',
    SHADOWKNIGHT = 'SHD', DRUID = 'DRU', MONK = 'MNK', BARD = 'BRD',
    ROGUE = 'ROG', SHAMAN = 'SHM', NECROMANCER = 'NEC', WIZARD = 'WIZ',
    MAGICIAN = 'MAG', ENCHANTER = 'ENC', BEASTLORD = 'BST', BERSERKER = 'BER',
}

local function normalizeClassToken(token)
    local t = tostring(token or ''):upper():gsub('[%s%-_]', '')
    return classNameToTag[t] or t
end

local function classMaskToText(mask)
    local m = tonumber(mask) or 0
    if m <= 0 then return nil end
    local tags = {}
    for i = 1, 16 do
        local bit = 2 ^ (i - 1)
        if (m % (bit * 2)) >= bit then
            tags[#tags + 1] = classIdToTag[i] or tostring(i)
        end
    end
    if #tags == 0 then return nil end
    if #tags == 16 then return 'ALL' end
    return table.concat(tags, '/')
end

local function classesToText(raw)
    if type(raw) == 'number' then
        return classMaskToText(raw)
    end
    if type(raw) == 'string' then
        local s = tostring(raw)
        if s == '' then return nil end
        local asNum = tonumber(s)
        if asNum then
            return classMaskToText(asNum)
        end
        local up = s:upper()
        if up == 'ALL' then return 'ALL' end
        local tags = {}
        for tok in s:gmatch('[^,%s/|]+') do
            tags[#tags + 1] = normalizeClassToken(tok)
        end
        if #tags == 0 then return nil end
        return table.concat(tags, '/')
    end
    if type(raw) == 'table' then
        local tags = {}
        for _, v in ipairs(raw) do
            tags[#tags + 1] = normalizeClassToken(v)
        end
        if #tags == 0 then return nil end
        return table.concat(tags, '/')
    end
    return nil
end

local function slotsToText(raw)
    if type(raw) == 'string' then
        local s = tostring(raw):gsub('^%s+', ''):gsub('%s+$', '')
        if s ~= '' then
            return s
        end
        return nil
    end
    if type(raw) == 'table' then
        local vals = {}
        for _, v in ipairs(raw) do
            local t = tostring(v or ''):gsub('^%s+', ''):gsub('%s+$', '')
            if t ~= '' then
                vals[#vals + 1] = t
            end
        end
        if #vals > 0 then
            return table.concat(vals, '/')
        end
    end
    return nil
end

local function drawItemIcon()
end

local function loadOutfitterItemNames()
    local now = os.clock()
    if outfitterCatalogLoaded and next(outfitterItemNameById) ~= nil then
        return
    end
    if outfitterCatalogLoadAttempted and now < outfitterCatalogNextRetryAt then
        return
    end
    outfitterCatalogLoadAttempted = true

    local function collectOutfitterIds()
        local ids, seen = {}, {}
        for _, classItems in pairs(outfitterItemsByClass) do
            for _, category in ipairs(outfitterCategoryOrder) do
                for _, itemId in ipairs(classItems[category.key] or {}) do
                    if not seen[itemId] then
                        seen[itemId] = true
                        ids[#ids + 1] = itemId
                    end
                end
            end
        end
        for _, groupName in ipairs(outfitterExtraGroupOrder) do
            for _, itemId in ipairs(outfitterExtraItems[groupName] or {}) do
                if not seen[itemId] then
                    seen[itemId] = true
                    ids[#ids + 1] = itemId
                end
            end
        end
        for _, groupName in ipairs(aftershockGroupOrder) do
            for _, itemId in ipairs(aftershockItems[groupName] or {}) do
                if not seen[itemId] then
                    seen[itemId] = true
                    ids[#ids + 1] = itemId
                end
            end
        end
        for _, groupName in ipairs(melProgressionGroupOrder) do
            for _, itemId in ipairs(melProgressionItems[groupName] or {}) do
                if not seen[itemId] then
                    seen[itemId] = true
                    ids[#ids + 1] = itemId
                end
            end
        end
        for _, groupName in ipairs(lowerGukGroupOrder) do
            for _, itemId in ipairs(lowerGukItems[groupName] or {}) do
                if not seen[itemId] then
                    seen[itemId] = true
                    ids[#ids + 1] = itemId
                end
            end
        end
        for _, groupName in ipairs(blackburrowForgeGroupOrder) do
            for _, itemId in ipairs(blackburrowForgeItems[groupName] or {}) do
                if not seen[itemId] then
                    seen[itemId] = true
                    ids[#ids + 1] = itemId
                end
            end
        end
        for _, groupName in ipairs(guildLobbyForgeGroupOrder) do
            for _, itemId in ipairs(guildLobbyForgeItems[groupName] or {}) do
                if not seen[itemId] then
                    seen[itemId] = true
                    ids[#ids + 1] = itemId
                end
            end
        end
        return ids
    end

    local function normalizePath(path)
        return tostring(path or ''):gsub('\\', '/')
    end

    local function dirName(path)
        local p = normalizePath(path)
        return p:match('^(.*)/[^/]+$') or '.'
    end

    local function fileExists(path)
        local f = io.open(path, 'r')
        if f then
            f:close()
            return true
        end
        return false
    end

    local function loadRowsFromCatalog(path, ids)
        local f = io.open(path, 'r')
        if not f then return false end
        local text = f:read('*a')
        f:close()
        if not text or text == '' then
            return false
        end

        local wanted = {}
        for _, rawId in ipairs(ids) do
            local itemId = tonumber(rawId)
            if itemId and itemId > 0 then
                wanted[itemId] = true
            end
        end

        local loadedAny = false
        -- Fast direct extraction from the catalog row format:
        -- {"id":149373,"name":"Ultimate Avatar Bracer (Demigod)","icon":671,...}
        for idText, nameText, iconText in text:gmatch('"id"%s*:%s*(%d+)%s*,%s*"name"%s*:%s*"(.-)"%s*,%s*"icon"%s*:%s*(%d+)') do
            local itemId = tonumber(idText)
            if itemId and wanted[itemId] and not outfitterItemNameById[itemId] then
                local safeName = tostring(nameText or ''):gsub('\\"', '"'):gsub('\\\\', '\\')
                outfitterItemNameById[itemId] = safeName
                outfitterItemIconById[itemId] = tonumber(iconText) or 0
                outfitterItemLevelById[itemId] = 75
                loadedAny = true
            end
        end
        return loadedAny
    end

    outfitterItemNameById = {}
    outfitterItemIconById = {}
    outfitterItemClassById = {}
    outfitterItemSlotById = {}
    outfitterItemLevelById = {}

    local ids = collectOutfitterIds()
    local scriptDir = dirName((debug.getinfo(1, 'S').source or ''):gsub('^@', ''))
    local luaDir = normalizePath(mq.luaDir or scriptDir)
    local configDir = normalizePath(mq.configDir or '')

    local candidatePaths = {
        scriptDir .. '/UltDev/catalog/PEQ/items.json',
        scriptDir .. '/UltDev/catalog/Ultimate_EQ/items.json',
        luaDir .. '/UltDev/catalog/PEQ/items.json',
        luaDir .. '/UltDev/catalog/Ultimate_EQ/items.json',
        configDir ~= '' and (configDir .. '/UltDev/catalog/PEQ/items.json') or nil,
        configDir ~= '' and (configDir .. '/UltDev/catalog/Ultimate_EQ/items.json') or nil,
    }

    local loadedAny = false
    for _, p in ipairs(candidatePaths) do
        if p and fileExists(p) then
            loadedAny = loadRowsFromCatalog(p, ids)
            if loadedAny then
                break
            end
        end
    end

    outfitterCatalogLoaded = loadedAny
    if loadedAny then
        outfitterCatalogNextRetryAt = math.huge
    else
        outfitterCatalogNextRetryAt = now + 10
    end
end

local function getOutfitterItemName(itemId)
    loadOutfitterItemNames()
    local id = tonumber(itemId) or 0
    local name = outfitterItemNameById[id]
    if name and name ~= '' then
        return name
    end
    return ('Item %d'):format(id)
end

local function getOutfitterItemIcon(itemId)
    loadOutfitterItemNames()
    local id = tonumber(itemId) or 0
    return tonumber(outfitterItemIconById[id]) or 0
end

local function getOutfitterItemClassText(itemId, defaultClassText)
    loadOutfitterItemNames()
    local id = tonumber(itemId) or 0
    return outfitterItemClassById[id] or defaultClassText or '?'
end

local function getOutfitterItemSlotText(itemId)
    loadOutfitterItemNames()
    local id = tonumber(itemId) or 0
    return outfitterItemSlotById[id] or '?'
end

local function getOutfitterItemLevel(itemId)
    loadOutfitterItemNames()
    local id = tonumber(itemId) or 0
    return tonumber(outfitterItemLevelById[id]) or 75
end

local function buildOutfitterSection(commandToken)
    local commands = {}
    local sectionLabel = commandToken == 'giveitem' and 'Give' or 'Summon'
    local groupOrder = {}

    for _, classDef in ipairs(outfitterClassOrder) do
        groupOrder[#groupOrder + 1] = classDef.name
        local classItems = outfitterItemsByClass[classDef.id] or {}
        for _, category in ipairs(outfitterCategoryOrder) do
            local items = classItems[category.key] or {}
            for itemIndex, itemId in ipairs(items) do
                local itemName = getOutfitterItemName(itemId)
                local lvl = getOutfitterItemLevel(itemId)
                local classText = classDef.tag
                local label = ('%s | L%d | %s (%d)##%s_%d_%s_%d_%d'):format(
                    classText, lvl, itemName, itemId, commandToken, classDef.id, category.key, itemIndex, itemId
                )
                local cmd = ('%s %d'):format(commandToken, itemId)
                local entry = makeCmd(label, cmd, false, false, nil, 'say')
                entry.group = classDef.name
                entry.groupId = classDef.id
                entry.itemIconId = getOutfitterItemIcon(itemId)
                entry.slotText = getOutfitterItemSlotText(itemId)
                commands[#commands + 1] = entry
            end
        end
    end

    return {
        title = ('Outfitter By Class - %s (/say #%s id)'):format(sectionLabel, commandToken),
        useClassDropdowns = true,
        groupOrder = groupOrder,
        commands = commands,
    }
end

local function buildOutfitterExtrasSection(commandToken)
    local commands = {}
    local sectionLabel = commandToken == 'giveitem' and 'Give' or 'Summon'

    for _, groupName in ipairs(outfitterExtraGroupOrder) do
        local items = outfitterExtraItems[groupName] or {}
        for itemIndex, itemId in ipairs(items) do
            local itemName = getOutfitterItemName(itemId)
            local lvl = getOutfitterItemLevel(itemId)
            local classText = getOutfitterItemClassText(itemId, 'ALL')
            local label = ('%s | L%d | %s (%d)##%s_%s_%d_%d'):format(
                classText, lvl, itemName, itemId, commandToken, groupName:gsub('%s+', '_'), itemIndex, itemId
            )
            local cmd = ('%s %d'):format(commandToken, itemId)
            local entry = makeCmd(label, cmd, false, false, nil, 'say')
            entry.group = groupName
            entry.itemIconId = getOutfitterItemIcon(itemId)
            entry.slotText = getOutfitterItemSlotText(itemId)
            commands[#commands + 1] = entry
        end
    end

    return {
        title = ('Outfitter Extras - %s (/say #%s id)'):format(sectionLabel, commandToken),
        useClassDropdowns = true,
        groupOrder = outfitterExtraGroupOrder,
        commands = commands,
    }
end

local function buildAftershockSection(commandToken)
    local commands = {}
    local sectionLabel = commandToken == 'giveitem' and 'Give' or 'Summon'

    for _, groupName in ipairs(aftershockGroupOrder) do
        local items = aftershockItems[groupName] or {}
        for itemIndex, itemId in ipairs(items) do
            local itemName = getOutfitterItemName(itemId)
            local lvl = getOutfitterItemLevel(itemId)
            local classText = getOutfitterItemClassText(itemId, 'ALL')
            local label = ('%s | L%d | %s (%d)##aftershock_%s_%s_%d_%d'):format(
                classText, lvl, itemName, itemId, commandToken, groupName:gsub('%s+', '_'), itemIndex, itemId
            )
            local cmd = ('%s %d'):format(commandToken, itemId)
            local entry = makeCmd(label, cmd, false, false, nil, 'say')
            entry.group = groupName
            entry.itemIconId = getOutfitterItemIcon(itemId)
            commands[#commands + 1] = entry
        end
    end

    return {
        title = ('Aftershock Items - %s (/say #%s id)'):format(sectionLabel, commandToken),
        useClassDropdowns = true,
        groupOrder = aftershockGroupOrder,
        commands = commands,
    }
end

local function buildMelProgressionSection(commandToken)
    local commands = {}
    local sectionLabel = commandToken == 'giveitem' and 'Give' or 'Summon'

    for _, groupName in ipairs(melProgressionGroupOrder) do
        local items = melProgressionItems[groupName] or {}
        for itemIndex, itemId in ipairs(items) do
            local itemName = getOutfitterItemName(itemId)
            local lvl = getOutfitterItemLevel(itemId)
            local classText = getOutfitterItemClassText(itemId, 'ALL')
            local label = ('%s | L%d | %s (%d)##mel_%s_%s_%d_%d'):format(
                classText, lvl, itemName, itemId, commandToken, groupName:gsub('%s+', '_'), itemIndex, itemId
            )
            local cmd = ('%s %d'):format(commandToken, itemId)
            local entry = makeCmd(label, cmd, false, false, nil, 'say')
            entry.group = groupName
            entry.itemIconId = getOutfitterItemIcon(itemId)
            commands[#commands + 1] = entry
        end
    end

    return {
        title = ('Mel Progression - %s (/say #%s id)'):format(sectionLabel, commandToken),
        useClassDropdowns = true,
        groupOrder = melProgressionGroupOrder,
        commands = commands,
    }
end

local function buildLowerGukSection(commandToken)
    local commands = {}
    local sectionLabel = commandToken == 'giveitem' and 'Give' or 'Summon'

    for _, groupName in ipairs(lowerGukGroupOrder) do
        local items = lowerGukItems[groupName] or {}
        for itemIndex, itemId in ipairs(items) do
            local itemName = getOutfitterItemName(itemId)
            local lvl = getOutfitterItemLevel(itemId)
            local classText = getOutfitterItemClassText(itemId, 'ALL')
            local label = ('%s | L%d | %s (%d)##lowerguk_%s_%s_%d_%d'):format(
                classText, lvl, itemName, itemId, commandToken, groupName:gsub('%s+', '_'), itemIndex, itemId
            )
            local cmd = ('%s %d'):format(commandToken, itemId)
            local entry = makeCmd(label, cmd, false, false, nil, 'say')
            entry.group = groupName
            entry.itemIconId = getOutfitterItemIcon(itemId)
            commands[#commands + 1] = entry
        end
    end

    return {
        title = ('Lower Guk Guide Items - %s (/say #%s id)'):format(sectionLabel, commandToken),
        useClassDropdowns = true,
        groupOrder = lowerGukGroupOrder,
        commands = commands,
    }
end

local function buildBlackburrowForgeSection(commandToken)
    local commands = {}
    local sectionLabel = commandToken == 'giveitem' and 'Give' or 'Summon'

    for _, groupName in ipairs(blackburrowForgeGroupOrder) do
        local items = blackburrowForgeItems[groupName] or {}
        for itemIndex, itemId in ipairs(items) do
            local itemName = getOutfitterItemName(itemId)
            local lvl = getOutfitterItemLevel(itemId)
            local classText = getOutfitterItemClassText(itemId, 'ALL')
            local label = ('%s | L%d | %s (%d)##bbforge_%s_%s_%d_%d'):format(
                classText, lvl, itemName, itemId, commandToken, groupName:gsub('%s+', '_'), itemIndex, itemId
            )
            local cmd = ('%s %d'):format(commandToken, itemId)
            local entry = makeCmd(label, cmd, false, false, nil, 'say')
            entry.group = groupName
            entry.itemIconId = getOutfitterItemIcon(itemId)
            commands[#commands + 1] = entry
        end
    end

    return {
        title = ('Blackburrow Forge Items - %s (/say #%s id)'):format(sectionLabel, commandToken),
        useClassDropdowns = true,
        groupOrder = blackburrowForgeGroupOrder,
        commands = commands,
    }
end

local function buildGuildLobbyForgeSection(commandToken)
    local commands = {}
    local sectionLabel = commandToken == 'giveitem' and 'Give' or 'Summon'

    for _, groupName in ipairs(guildLobbyForgeGroupOrder) do
        local items = guildLobbyForgeItems[groupName] or {}
        for itemIndex, itemId in ipairs(items) do
            local itemName = getOutfitterItemName(itemId)
            local lvl = getOutfitterItemLevel(itemId)
            local classText = getOutfitterItemClassText(itemId, 'ALL')
            local label = ('%s | L%d | %s (%d)##glforge_%s_%s_%d_%d'):format(
                classText, lvl, itemName, itemId, commandToken, groupName:gsub('%s+', '_'), itemIndex, itemId
            )
            local cmd = ('%s %d'):format(commandToken, itemId)
            local entry = makeCmd(label, cmd, false, false, nil, 'say')
            entry.group = groupName
            entry.itemIconId = getOutfitterItemIcon(itemId)
            commands[#commands + 1] = entry
        end
    end

    return {
        title = ('Guild Lobby Forge Items - %s (/say #%s id)'):format(sectionLabel, commandToken),
        useClassDropdowns = true,
        groupOrder = guildLobbyForgeGroupOrder,
        commands = commands,
    }
end

local function refreshOutfitterSections()
    loadOutfitterItemNames()
    local kept = {}
    for _, section in ipairs(sections) do
        local title = tostring(section.title or '')
        -- Strip regenerated sidebar blocks so async catalog refresh does not duplicate them.
        if not title:find('^Outfitter ')
            and not title:find('^Aftershock ')
            and not title:find('^Mel ')
            and not title:find('^Lower Guk ')
            and not title:find('^Blackburrow Forge ')
            and not title:find('^Guild Lobby Forge ') then
            kept[#kept + 1] = section
        end
    end
    sections = kept
    sections[#sections + 1] = buildOutfitterSection('summonitem')
    sections[#sections + 1] = buildOutfitterSection('giveitem')
    sections[#sections + 1] = buildOutfitterExtrasSection('summonitem')
    sections[#sections + 1] = buildOutfitterExtrasSection('giveitem')
    sections[#sections + 1] = buildAftershockSection('summonitem')
    sections[#sections + 1] = buildAftershockSection('giveitem')
    sections[#sections + 1] = buildMelProgressionSection('summonitem')
    sections[#sections + 1] = buildMelProgressionSection('giveitem')
    sections[#sections + 1] = buildLowerGukSection('summonitem')
    sections[#sections + 1] = buildLowerGukSection('giveitem')
    sections[#sections + 1] = buildBlackburrowForgeSection('summonitem')
    sections[#sections + 1] = buildBlackburrowForgeSection('giveitem')
    sections[#sections + 1] = buildGuildLobbyForgeSection('summonitem')
    sections[#sections + 1] = buildGuildLobbyForgeSection('giveitem')
end
refreshOutfitterSections()

local customSayPatterns = {
    '^hail$',
    '^viewquickactions$',
    '^viewzcdiag$',
    '^viewremotecommands$',
    '^viewallmobs$',
    '^viewignoredmobs$',
    '^viewdepopmobs$',
    '^viewzoneinfo$',
    '^viewallloottables$',
    '^viewalllootdrops_%d+$',
    '^saveallchanges$',
    '^applyallchanges$',
    '^resetallchanges$',
    '^repopallstaticbosses$',
    '^depopallstaticbosses$',
    '^rebuffzone$',
    '^refreshzonedata$',
    '^addnewcustommob$',
    '^batchaddncustommobs$',
    '^removeallitemsfromitemtable$',
    '^addnewitemtozone$',
    '^show_my_progression$',
    '^gm_grant_all_flags$',
    '^gm_delete_all_flags$',
    '^new_player_ultimate_charm$',
    '^info_pre_ultimate$',
    '^pre_ultimate_tasks$',
    '^tasks$',
    '^info_ultimate$',
    '^info_avatar$',
    '^info_demigod$',
    '^info_god$',
    '^vanilla_progression_requirements$',
    '^kunark_progression_requirements$',
    '^velious_progression_requirements$',
    '^luclin_progression_requirements$',
    '^pop_progression_requirements$',
    '^obtain access to ultimate zones rank [1-5]$',
    '^obtain access to avatar zones rank [1-4]$',
    '^obtain access to demigod zones rank [1-4]$',
    '^obtain access to god zones rank [1-2]$',
    '^obtain access to ultimate zones tier [1-5]$',
    '^obtain access to avatar zones tier [1-4]$',
    '^obtain access to demigod zones tier 1$',
    '^defeat uber megaladon$',
    "^i've_lost_my_palantir_of_the_ascended$",
    '^pal_ul$',
    '^teleport_to_forge$',
    '^teleport_to_phil$',
    '^teleport_to_quake$',
    '^teleport_to_seism$',
    '^teleport_to_illuminous$',
    '^learning about the zone$',
    '^boss drops$',
    '^key to ultimate sebilis$',
    '^interesting scrolls$',
    '^new armor$',
    '^powersource$',
    '^primal weapons$',
    '^ultimate_weapons_menu$',
    '^ultimate_weapons_desc$',
    '^ultimate_weapons_howto$',
    '^ultimate_ultimate_desc$',
    '^ultimate_weapons_percent$',
    '^ultimate_weapons_show_base$',
    '^ultimate_weapons_show_ultimate$',
    '^ultimate_credits$',
    '^teleport_to_aftershock$',
    '^viewmaterials_.+',
    '^viewqualities_.+',
    '^debug$',
    '^removemob_.+',
    '^renamemob#.+',
    '^!whispermobname#.+',
    '^clonemob#.+',
    '^!whisperclonename#.+',
    '^removeitembyname_.+',
    '^removefromignored_.+',
    '^removefromdepop_.+',
    '^dbad_.+',
    '^setnewcustommobtype#.+',
    '^!addnewmob#.+',
    '^addnewignoremob#.+',
    '^!addignoremob#.+',
    '^addnewdepopmob#.+',
    '^!adddepopmob#.+',
    '^vl_.+',
    '^vtd_.+',
    '^quickadditems_.+',
    '^viewitemdata_.+',
    '^vts_.+',
    '^vcs_.+',
    '^vfs_.+',
    '^viewallassociatedtables_.+',
    '^viewmobsbyloottable_.+',
    '^removeitemfromalltables_.+',
    '^viewalllootdrops_.+',
    '^ams#.+',
    '^togglemobstat#.+',
    '^saymobstat#.+',
    '^!whispermobstat#.+',
    '^acs#.+',
    '^rcs#.+',
    '^togglecustommobstat#.+',
    '^saycustommobstat#.+',
    '^!whispercustommobstat#.+',
    '^sayzoneinfo#.+',
    '^!whisperzoneinfo#.+',
    '^vco_.+',
    '^vto_.+',
    '^cl_.+',
    '^atts_.+',
    '^dclt_.+',
    '^iclt_.+',
    '^dtlt_.+',
    '^itlt_.+',
    '^stlt_.+',
    '^sclt_.+',
    '^saynewloottableinfo$',
    '^!wnt#.+',
    '^displaytablesthatcanbeassociated_.+',
    '^ali_.+',
    '^assignallitemstoloottable_.+',
    '^removeallitemsfromloottable_.+',
    '^!additemid#.+',
    '^sayitemdetails#.+',
    '^!updateitemdetails#.+',
    '^removeitemdata_.+',
    '^rlt_.+',
    '^rct_.+',
    '^removeloottable_.+',
}

local function normalizeForCustomSay(raw)
    local normalized = (raw or ''):gsub('^%s*#%s*', ''):gsub('^%s+', ''):gsub('%s+$', '')
    local lower = normalized:lower()
    for _, p in ipairs(customSayPatterns) do
        if lower:match(p) then
            return true, normalized
        end
    end
    return false, normalized
end


local function buildFullCommand(entry, paramValue)
    local base = entry.cmd or ''
    local full = GM_PREFIX .. base

    if entry.needsParam then
        local value = paramValue or ''
        local joiner = entry.paramJoiner

        if joiner == nil then
            joiner = ' '
        end

        if value ~= '' then
            if joiner ~= '' then
                full = full .. joiner .. value
            else
                full = full .. value
            end
        end
    end

    return full
end

local function sendCommand(entry, fullCommand)
    lastSentCommand = fullCommand
    print('[GMConsole] Sending: ' .. fullCommand)
    if entry and entry.transport == 'say' then
        mq.cmdf('/say %s', fullCommand)
        return
    end

    mq.cmd(fullCommand)
end

local function executeEntry(entry)
    if not entry then return end

    if entry.dangerous then
        confirmEntry = entry
        confirmParamText = ''
        showConfirmDialog = true
        confirmPopupRequested = false
        return
    end

    local fullCommand = buildFullCommand(entry, searchText)
    sendCommand(entry, fullCommand)
end

local function runRawCommand()
    local txt = rawCommandText or ''
    if txt == '' then
        return
    end

    local isCustomSay, normalized = normalizeForCustomSay(txt)
    if isCustomSay then
        local customSay = normalized
        if customSay:sub(1, 1) ~= '#' then
            customSay = '#' .. customSay
        end
        mq.cmdf('/say %s', customSay)
        return
    end

    if txt:sub(1, 1) == '#' then
        mq.cmd(txt)
    else
        mq.cmd('#' .. txt)
    end
end

local function executeConfirmedCommand()
    if not confirmEntry then
        showConfirmDialog = false
        return
    end

    local param = confirmEntry.needsParam and confirmParamText or searchText
    local fullCommand = buildFullCommand(confirmEntry, param)
    sendCommand(confirmEntry, fullCommand)

    showConfirmDialog = false
    confirmEntry = nil
    confirmParamText = ''
    confirmPopupRequested = false
end

local function commandMatchesFilter(entry)
    if filterText == '' then
        return true
    end

    local needle = string.lower(filterText:gsub('^%s+', ''):gsub('%s+$', ''))
    local label = string.lower(entry.label or '')
    local cmd = string.lower(entry.cmd or '')
    return string.find(label, needle, 1, true) ~= nil or string.find(cmd, needle, 1, true) ~= nil
end

local sectionCategoryColors = {
    Basic = { 0.30, 0.58, 1.00, 1.00 },
    NPC = { 0.90, 0.66, 0.24, 1.00 },
    Lead = { 0.92, 0.32, 0.32, 1.00 },
    Zone = { 0.20, 0.74, 0.72, 1.00 },
    Player = { 0.64, 0.44, 0.95, 1.00 },
    ZC = { 0.36, 0.80, 0.42, 1.00 },
    Flags = { 0.95, 0.46, 0.68, 1.00 },
}

local sectionCategoryIcons = {
    Basic = '[>]',
    NPC = '[#]',
    Lead = '[!]',
    Zone = '[*]',
    Player = '[>]',
    ZC = '[#]',
    Flags = '[*]',
}

local function sectionCategoryForTitle(title)
    local t = (title or ''):lower()
    if t:find('zone controller', 1, true) then return 'ZC' end
    if t:find('lead gm', 1, true) then return 'Lead' end
    if t:find('flags', 1, true) then return 'Flags' end
    if t:find('player', 1, true) then return 'Player' end
    if t:find('zone management', 1, true) then return 'Zone' end
    if t:find('stock zone', 1, true) then return 'Basic' end
    if t:find('npc', 1, true) or t:find('corpse', 1, true) or t:find('target', 1, true) then return 'NPC' end
    return 'Basic'
end

local function ensureSectionMeta()
    for i, section in ipairs(sections) do
        section.category = section.category or sectionCategoryForTitle(section.title)
        section.icon = section.icon or sectionCategoryIcons[section.category] or '[>]'
        section.index = i
    end
    if activeSectionIndex < 1 or activeSectionIndex > #sections then
        activeSectionIndex = 1
    end
end

local function getSectionAccentColor(section)
    local c = sectionCategoryColors[section.category or 'Basic'] or sectionCategoryColors.Basic
    return c[1], c[2], c[3], c[4]
end

local function buildTooltipCommandString(entry)
    local tipPrefix = entry.transport == 'say' and '/say ' or '#'
    local tip = tipPrefix .. (entry.cmd or '')
    if entry.needsParam then
        tip = tip .. (entry.paramJoiner == '' and '<param>' or ' <param>')
    end
    if entry.dangerous then
        tip = tip .. '  [confirmation required]'
    end
    return tip
end

local function getSingleExactMatch(commands)
    local needle = (filterText or ''):gsub('^%s+', ''):gsub('%s+$', ''):lower()
    if needle == '' then
        return nil
    end

    local matchCount = 0
    local singleMatch = nil
    for _, entry in ipairs(commands) do
        if commandMatchesFilter(entry) then
            local label = (entry.label or ''):lower()
            local cmd = (entry.cmd or ''):lower()
            if label == needle or cmd == needle then
                matchCount = matchCount + 1
                singleMatch = entry
            end
        end
    end

    if matchCount == 1 then
        return singleMatch
    end
    return nil
end

-----------------------------------------------------------------------
-- RmlUi shell
-----------------------------------------------------------------------
local rmlui = require('rmlui')

local CAT_ICON = {
    Basic = 'CMD',
    NPC = 'NPC',
    Lead = 'GM',
    Zone = 'ZN',
    Player = 'PC',
    ZC = 'ZC',
    Flags = 'FLG',
}

local UI = {
    win = nil,
    next_update = 0,
    nav_n = -1,
    cmd_n = -1,
    visible = {},
    section_sig = '',
}

local function esc(s)
    s = tostring(s or '')
    return s:gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;'):gsub('"', '&quot;')
end

local function display_label(label)
    return (label or ''):gsub('##.*$', '')
end

local function ensure_win()
    if UI.win and UI.win:is_open() then return UI.win end
    local win, err = rmlui.open('GMConsole', 'gmconsole/ui/console.rml', {
        width = 980, height = 720, autoclose = true,
    })
    if not win then
        print('[GMConsole] RmlUi open failed: ' .. tostring(err))
        return nil
    end
    -- Always reload so RCSS/RML edits on disk apply (rml_open skips reload when path matches).
    pcall(function() win:reload() end)
    win:theme('violet')
    UI.win = win
    UI.nav_n, UI.cmd_n, UI.section_sig = -1, -1, ''
    UI.opened_at = (mq.gettime and mq.gettime() or (os.time() * 1000))
    return win
end

local function visible_commands(section)
    local out = {}
    if not section or not section.commands then return out end
    for _, entry in ipairs(section.commands) do
        if commandMatchesFilter(entry) then
            out[#out + 1] = entry
        end
    end
    return out
end

local function update_nav(win)
    ensureSectionMeta()
    if UI.nav_n ~= #sections then
        local parts = {}
        for i, section in ipairs(sections) do
            local cat = section.category or 'Basic'
            local ico = CAT_ICON[cat] or CAT_ICON.Basic
            parts[i] = string.format(
                '<div id="nav%d" class="nav-item cat-%s" action="nav:%d"><span class="nav-ico">%s</span><span id="nav%dl" class="nav-label">%s</span><span id="nav%dn" class="nav-n">%d</span></div>',
                i, cat, i, ico, i, esc(section.title), i, #(section.commands or {}))
        end
        win.cache = {}
        win:rml('nav', table.concat(parts))
        UI.nav_n = #sections
        UI.cmd_n = -1
    end
    for i, section in ipairs(sections) do
        win:class('nav' .. i, 'on', i == activeSectionIndex)
        win:text('nav' .. i .. 'n', tostring(#(section.commands or {})))
    end
end

local function update_cmds(win)
    local section = sections[activeSectionIndex] or sections[1]
    if not section then return end
    local rows = visible_commands(section)
    UI.visible = rows
    local exact = getSingleExactMatch(section.commands)
    local exact_cmd = exact and exact.cmd or nil

    win:text('sec_title', section.title or 'Commands')
    win:text('sec_meta', string.format('%d shown / %d', #rows, #(section.commands or {})))
    local r, g, b = getSectionAccentColor(section)
    win:style('sec_accent', 'background-color', string.format('#%02x%02x%02x',
        math.floor(r * 255), math.floor(g * 255), math.floor(b * 255)))
    win:class('main', 'is-empty', #rows == 0)

    local n = math.min(#rows, 240)
    local sig = tostring(activeSectionIndex) .. '|' .. filterText .. '|' .. tostring(n) .. '|' .. tostring(#rows)
    if sig ~= UI.section_sig or n ~= UI.cmd_n then
        local parts = {}
        for i = 1, n do
            local entry = rows[i]
            local cls = 'cmd'
            if entry.dangerous then cls = cls .. ' danger' end
            if entry.needsParam then cls = cls .. ' need' end
            if entry.transport == 'say' then cls = cls .. ' say' end
            if exact_cmd and entry.cmd == exact_cmd then cls = cls .. ' exact' end
            local tip = esc(buildTooltipCommandString(entry))
            local lab = esc(display_label(entry.label))
            parts[i] = '<div id="cmd' .. i .. '" class="' .. cls .. '" action="cmd:' .. i
                .. '" title="' .. tip .. '">' .. lab .. '</div>'
        end
        if #rows > n then
            parts[#parts + 1] = '<div class="cmd">+ ' .. tostring(#rows - n) .. ' more (narrow filter)</div>'
        end
        win.cache = {}
        win:rml('cmd_grid', table.concat(parts))
        UI.cmd_n = n
        UI.section_sig = sig
    else
        for i = 1, n do
            local entry = rows[i]
            win:class('cmd' .. i, 'exact', exact_cmd ~= nil and entry.cmd == exact_cmd)
        end
    end
end

local function update_status(win)
    local player = tostring((mq.TLO.Me.CleanName and mq.TLO.Me.CleanName()) or mq.TLO.Me.Name() or 'Player')
    local zone = tostring(mq.TLO.Zone.ShortName() or '?')
    win:text('st_player', player)
    win:text('st_zone', 'Zone: ' .. zone)
    win:text('st_badge', 'DEV')
    win:text('st_count', string.format('%d sections', #sections))
    win:text('last_sent', lastSentCommand or 'none')
end

local function update_confirm(win)
    win:class('confirm', 'show', showConfirmDialog == true)
    if not showConfirmDialog or not confirmEntry then return end
    local resolved = buildFullCommand(confirmEntry, confirmEntry.needsParam and confirmParamText or searchText)
    win:text('confirm_cmd', resolved)
    win:class('confirm_param_wrap', 'show', confirmEntry.needsParam == true)
    -- confirm_param_wrap uses display via field always; hide with style if needed
    if confirmEntry.needsParam then
        win:style('confirm_param_wrap', 'display', 'flex')
    else
        win:style('confirm_param_wrap', 'display', 'none')
    end
end

local function refresh_catalog_if_needed()
    local hadCatalog = outfitterCatalogLoaded
    if not outfitterCatalogLoaded then
        loadOutfitterItemNames()
    end
    if (not hadCatalog) and outfitterCatalogLoaded then
        refreshOutfitterSections()
        ensureSectionMeta()
        UI.nav_n = -1
        UI.cmd_n = -1
        UI.section_sig = ''
    end
end

local function handle(ev)
    local a = ev.action or ''
    if ev.type == 'change' then
        if ev.id == 'param' then
            searchText = ev.value or ''
        elseif ev.id == 'filter' then
            filterText = ev.value or ''
            UI.section_sig = ''
            UI.next_update = 0
        elseif ev.id == 'raw' then
            rawCommandText = ev.value or ''
        elseif ev.id == 'confirm_param' then
            confirmParamText = ev.value or ''
            UI.next_update = 0
        end
        return
    end
    if ev.type ~= 'click' and ev.type ~= 'dblclick' then return end

    if a == 'window:close' then
        local now = mq.gettime and mq.gettime() or (os.time() * 1000)
        -- Ignore close for a moment after open (mouse-up on the X when the window appears under the cursor).
        if UI.opened_at and (now - UI.opened_at) < 600 then
            if UI.win then UI.win:show(true) end
            print('[GMConsole] Ignored accidental close on open.')
            return
        end
        openGUI = false
        return
    end
    if a == 'raw:run' then
        runRawCommand()
        UI.next_update = 0
        return
    end
    if a == 'raw:clear' then
        searchText, filterText, rawCommandText, confirmParamText = '', '', '', ''
        if UI.win then
            UI.win:set_value('param', '')
            UI.win:set_value('filter', '')
            UI.win:set_value('raw', '')
        end
        UI.section_sig = ''
        UI.next_update = 0
        return
    end
    if a == 'confirm:yes' then
        executeConfirmedCommand()
        UI.next_update = 0
        return
    end
    if a == 'confirm:no' then
        showConfirmDialog = false
        confirmEntry = nil
        confirmParamText = ''
        UI.next_update = 0
        return
    end

    local nav = tonumber(a:match('^nav:(%d+)$'))
    if nav then
        activeSectionIndex = nav
        UI.section_sig = ''
        UI.next_update = 0
        return
    end

    local ci = tonumber(a:match('^cmd:(%d+)$'))
    if ci and UI.visible[ci] then
        executeEntry(UI.visible[ci])
        UI.next_update = 0
    end
end

local function update()
    local win = ensure_win()
    if not win then return end
    refresh_catalog_if_needed()
    ensureSectionMeta()
    update_status(win)
    update_nav(win)
    update_cmds(win)
    update_confirm(win)
end

local function tick()
    local win = ensure_win()
    if not win then
        mq.delay(500)
        return
    end
    if not win:is_open() then
        UI.win = nil
        mq.delay(100)
        return
    end
    for ev in win:events() do
        local ok, err = pcall(handle, ev)
        if not ok then print('[GMConsole] event: ' .. tostring(err)) end
    end
    win:show(true)

    local t = mq.gettime and mq.gettime() or (os.time() * 1000)
    if t >= UI.next_update then
        UI.next_update = t + 200
        local ok, err = pcall(update)
        if not ok then
            print('[GMConsole] update: ' .. tostring(err))
            UI.next_update = t + 1000
        end
    end
end

print('[GMConsole] RmlUi console loaded. Close window or /lua stop gmconsole to exit.')

local function cleanup()
    pcall(function() rmlui.close_all() end)
    print('[GMConsole] stopped.')
end

local ok, err = pcall(function()
    while openGUI do
        local tok, terr = pcall(tick)
        if not tok then
            print('[GMConsole] tick: ' .. tostring(terr))
            mq.delay(500)
        else
            mq.delay(16)
        end
    end
end)
if not ok and err then print('[GMConsole] stop: ' .. tostring(err)) end
cleanup()
