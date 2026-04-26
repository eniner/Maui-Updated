return {
	['Characters'] = {
		['E9 Profusion_Enine'] = {
			['Windows'] = {
				[1] = {
					['Sets'] = {},
					['Locked'] = false,
					['Pos'] = {
						['x'] = 10,
						['y'] = 10,
					},
					['Visible'] = true,
				},
			},
		},
	},
	['LastBackup'] = 1773329260,
	['Version'] = 7,
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
	['Buttons'] = {
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
		['Button_3'] = {
			['Label'] = 'Unpause (all)',
			['Cmd'] = '/bcaa //mqp off',
		},
	},
}