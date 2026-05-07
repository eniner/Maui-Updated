return {
	['Version'] = 7,
	['Buttons'] = {
		['Button_4'] = {
			['Cmd'] = '/bca //nav id ${Target.ID}',
			['Label'] = 'Nav Target (bca)',
		},
		['Button_2'] = {
			['Cmd'] = '/bcaa //multi ; /twist off ; /mqp on',
			['Label'] = 'Pause (all)',
		},
		['Button_3'] = {
			['Cmd'] = '/bcaa //mqp off',
			['Label'] = 'Unpause (all)',
		},
		['Button_1'] = {
			['Cmd'] = '/bcaa //burn\n/timed 500 /bcaa //burn',
			['Label'] = 'Burn (all)',
		},
	},
	['Characters'] = {
		['Ultimate EQ_Eniine'] = {
			['Windows'] = {
				[1] = {
					['Locked'] = false,
					['Sets'] = {},
					['Visible'] = true,
					['Width'] = 76,
					['Height'] = 60,
					['Pos'] = {
						['y'] = 60,
						['x'] = 60,
					},
					['FPS'] = 0,
				},
			},
		},
		['Ultimate EQ_Enine'] = {
			['Windows'] = {
				[1] = {
					['Locked'] = false,
					['Sets'] = {},
					['Visible'] = true,
					['Pos'] = {
						['y'] = 10,
						['x'] = 10,
					},
					['FPS'] = 0,
				},
			},
		},
	},
	['Sets'] = {
		['Primary'] = {
			[1] = 'Button_1',
			[2] = 'Button_2',
			[3] = 'Button_3',
		},
		['Movement'] = {
			[1] = 'Button_4',
		},
	},
	['LastBackup'] = 1778076510,
}