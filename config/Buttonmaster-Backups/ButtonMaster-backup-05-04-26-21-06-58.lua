return {
	['Buttons'] = {
		['Button_3'] = {
			['Label'] = 'Unpause (all)',
			['Cmd'] = '/bcaa //mqp off',
		},
		['Button_4'] = {
			['Label'] = 'Nav Target (bca)',
			['Cmd'] = '/bca //nav id ${Target.ID}',
		},
		['Button_1'] = {
			['Label'] = 'Burn (all)',
			['Cmd'] = '/bcaa //burn\n/timed 500 /bcaa //burn',
		},
		['Button_2'] = {
			['Label'] = 'Pause (all)',
			['Cmd'] = '/bcaa //multi ; /twist off ; /mqp on',
		},
	},
	['Sets'] = {
		['Movement'] = {
			[1] = 'Button_4',
		},
		['Primary'] = {
			[1] = 'Button_1',
			[2] = 'Button_2',
			[3] = 'Button_3',
		},
	},
	['Characters'] = {
		['Ultimate EQ_Eniine'] = {
			['Windows'] = {
				[1] = {
					['Visible'] = true,
					['Locked'] = false,
					['Sets'] = {},
					['Pos'] = {
						['x'] = 10,
						['y'] = 10,
					},
				},
			},
		},
	},
	['Version'] = 7,
	['LastBackup'] = 1777943218,
}