local progression = {}

progression.fundamentals = {
    { id = '1.0', label = '1.0 Getting Started' },
    { id = '2.0', label = '2.0 Server Rules' },
    { id = '3.0', label = '3.0 MacroQuest Setup' },
    { id = '4.0', label = '4.0 EQ Built-In Macros' },
    { id = '5.0', label = '5.0 Credits, AA, and Power Growth' },
}

progression.tier_order = {
    '11.1', '11.2', '11.3', '11.4', '11.5', '11.6', '11.7', '11.8', '11.9',
    '11.10', '11.11', '11.12', '11.13', '11.14', '11.15',
}

progression.progression_tiers = {
    { id = '11.1', label = '11.1 Pre-Ultimate Progression' },
    { id = '11.2', label = '11.2 Ultimate Rank 1 Access' },
    { id = '11.3', label = '11.3 Ultimate Rank 2 Access' },
    { id = '11.4', label = '11.4 Ultimate Rank 3 Access' },
    { id = '11.5', label = '11.5 Ultimate Rank 4 Access' },
    { id = '11.6', label = '11.6 Ultimate Rank 5 Access' },
    { id = '11.7', label = '11.7 Avatar Rank 1 Access' },
    { id = '11.8', label = '11.8 Avatar Rank 2 Access' },
    { id = '11.9', label = '11.9 Avatar Rank 3 Access' },
    { id = '11.10', label = '11.10 Avatar Rank 4 Access' },
    { id = '11.11', label = '11.11 Demigod Rank 1 Access' },
    { id = '11.12', label = '11.12 Demigod Rank 2 Access' },
    { id = '11.13', label = '11.13 Demigod Rank 3 Access' },
    { id = '11.14', label = '11.14 Demigod Rank 4 Access' },
    { id = '11.15', label = '11.15 God Progression Access' },
}

progression.optional_raids = {
    { id = '12.0', label = '12.0 Optional / Expedition Content' },
}

progression.custom_systems = {
    { id = '7.0', label = '7.0 Ultimate Charm Path' },
    { id = '8.0', label = '8.0 Server Commands' },
    { id = '14.0', label = '14.0 Zone Access and Instances' },
    { id = '9.0', label = '9.0 Ultimate Weapons and Gambling' },
    { id = '10.0', label = '10.0 God Tier Leveling (71-75)' },
    { id = '23.0', label = '23.0 Master Progress Tracker' },
}

progression.tiers = {
    ['11.1'] = { name = 'Pre-Ultimate Progression', task = 'Vanilla through PoP hand-ins', cmd = 'Talk to Mel in Guild Lobby', giver = 'Mel' },
    ['11.2'] = { name = 'Ultimate Rank 1', task = 'Complete Crushbone challenge', cmd = '#createdz crushbone', giver = 'Mel / Quake / Forge' },
    ['11.3'] = { name = 'Ultimate Rank 2', task = 'Unlock Sebilis', cmd = 'guktop + gukbottom access', giver = 'Mel / Quake' },
    ['11.4'] = { name = 'Ultimate Rank 3', task = 'Unlock Temple of Veeshan', cmd = 'Talk to Forge and Quake', giver = 'Mel / Forge / Quake' },
    ['11.5'] = { name = 'Ultimate Rank 4', task = 'Unlock Kael Drakkel', cmd = 'Kael instance via Quake', giver = 'Mel / Quake' },
    ['11.6'] = { name = 'Ultimate Rank 5', task = 'Unlock Sleeper\'s Tomb', cmd = 'Static sleeper access via Quake', giver = 'Mel / Quake' },
    ['11.7'] = { name = 'Avatar Rank 1', task = 'Unlock Blackburrow / Mistmoore / Solusek A', cmd = 'Static avatar zones via Quake', giver = 'Mel / Quake / Arch Magus Phil' },
    ['11.8'] = { name = 'Avatar Rank 2', task = 'Unlock The Hole', cmd = 'Static hole access via Quake', giver = 'Mel / Quake' },
    ['11.9'] = { name = 'Avatar Rank 3', task = 'Unlock Tower of Frozen Shadow', cmd = 'Static frozenshadow via Quake', giver = 'Mel / Quake / Measel' },
    ['11.10'] = { name = 'Avatar Rank 4', task = 'Unlock Veeshan\'s Peak', cmd = 'Veeshan instance via Quake', giver = 'Mel / Quake' },
    ['11.11'] = { name = 'Demigod Rank 1', task = 'Unlock Ocean of Tears / Unrest', cmd = 'Static oot + unrest via Seism', giver = 'Mel / Seism' },
    ['11.12'] = { name = 'Demigod Rank 2', task = 'Unlock Plane of Fear', cmd = 'Plane of Fear instance via Seism', giver = 'Mel / Seism / Cloud / Arch Magus Phil' },
    ['11.13'] = { name = 'Demigod Rank 3', task = 'Unlock Velketor\'s Labyrinth', cmd = 'Static velketor via Seism', giver = 'Mel / Seism' },
    ['11.14'] = { name = 'Demigod Rank 4', task = 'Unlock Treasure Goblin Vault', cmd = 'Vault instance via Seism', giver = 'Mel / Seism / Farnsworth' },
    ['11.15'] = { name = 'God Progression', task = 'God access, levels 71-75, Crystallos, God Tier 2', cmd = 'Elddar / Kurn / Crystallos via Seism', giver = 'Mel / Illuminous / Seism' },
}

return progression
