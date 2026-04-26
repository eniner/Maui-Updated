return {
	['LastBackup'] = 1774272321,
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
		['Button_1'] = {
			['labelMidY'] = 14,
			['CachedLastRan'] = 107946.01999999999,
			['labelMidX'] = 15,
			['CachedCoolDownTimer'] = 0,
			['CachedToggleLocked'] = false,
			['Label'] = 'Burn (all)',
			['CachedCountDown'] = 0,
			['Cmd'] = '/bcaa //burn\n/timed 500 /bcaa //burn',
		},
		['Button_4'] = {
			['labelMidY'] = 6,
			['CachedLastRan'] = 141960.077,
			['labelMidX'] = 9,
			['CachedCoolDownTimer'] = 0,
			['CachedToggleLocked'] = false,
			['Label'] = 'Nav Target (bca)',
			['CachedCountDown'] = 0,
			['Cmd'] = '/bca //nav id ${Target.ID}',
		},
		['Button_2'] = {
			['labelMidY'] = 14,
			['CachedLastRan'] = 107946.01999999999,
			['labelMidX'] = 10,
			['CachedCoolDownTimer'] = 0,
			['CachedToggleLocked'] = false,
			['Label'] = 'Pause (all)',
			['CachedCountDown'] = 0,
			['Cmd'] = '/bcaa //multi ; /twist off ; /mqp on',
		},
		['Button_3'] = {
			['labelMidY'] = 14,
			['CachedLastRan'] = 107946.01999999999,
			['labelMidX'] = 2,
			['CachedCoolDownTimer'] = 0,
			['CachedToggleLocked'] = false,
			['Label'] = 'Unpause (all)',
			['CachedCountDown'] = 0,
			['Cmd'] = '/bcaa //mqp off',
		},
	},
	['Version'] = 7,
	['Characters'] = {
		['E9 Profusion_Enine'] = {
			['Windows'] = {
				[1] = {
					['AdvTooltips'] = true,
					['PerCharacterPositioning'] = false,
					['Visible'] = false,
					['Width'] = 344,
					['HideScrollbar'] = false,
					['Pos'] = {
						['y'] = 60,
						['x'] = 61,
					},
					['FPS'] = 0,
					['Theme'] = 'UltimateEQAssist',
					['Locked'] = false,
					['HideTitleBar'] = false,
					['Sets'] = {
						[1] = 'Primary',
						[2] = 'Movement',
					},
					['Font'] = 10,
					['ButtonSize'] = 6,
					['Height'] = 377,
					['CompactMode'] = false,
				},
			},
		},
		['UltEQTest_Eniine'] = {
			['Windows'] = {
				[1] = {
					['Height'] = 377,
					['Theme'] = 'UltimateEQAssist',
					['Locked'] = false,
					['Visible'] = false,
					['FPS'] = 0,
					['Sets'] = {
						[1] = 'Movement',
					},
					['Pos'] = {
						['y'] = 60,
						['x'] = 61,
					},
					['Width'] = 344,
				},
			},
		},
		['EZ (Linux) x4 Exp_Diggz'] = {
			['Windows'] = {
				[1] = {
					['Locked'] = false,
					['Sets'] = {},
					['FPS'] = 0,
					['Pos'] = {
						['y'] = 10,
						['x'] = 10,
					},
					['Visible'] = true,
				},
			},
		},
	},
}