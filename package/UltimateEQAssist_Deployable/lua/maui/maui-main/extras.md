Other INIs
- Lemons_Info.ini
    - ColdMobs=mobname,mobname,zoneshortname
    - DiseaseMobs
    - FireMobs
    - MagicMobs
    - PoisonMobs
    - SlowMobs
    - MezImmune
- KissAssist_Buffs.ini
    - MobsToPull
    - MobsToPullSecondary
    - MobsToIgnore
    - MobsToBurn
- MuleAssistOOGBuffs.ini


    /call LoadIni General Role                  string      Assist
    /call LoadIni General CampRadius            int         30
    /call LoadIni General CampRadiusExceed      int         400
    /call LoadIni General ReturnToCamp          int         0
    /call LoadIni General ReturnToCampAccuracy  int         10
    /call LoadIni General ChaseAssist           int         0
    /call LoadIni General ChaseDistance         int         25
    /call LoadIni General BuffWhileChasing		bool		1
    /call LoadIni General MedOn                 int         1
    /call LoadIni General MedStart              string         20
    /call LoadIni General LootOn                int         0
    /call LoadIni General RezAcceptOn           string      0|96
    /call LoadIni General AcceptInvitesOn       int         1
    /call LoadIni General GroupWatchOn          string      0
    /call LoadIni General CastingInterruptOn    int         0
    /call LoadIni General TheWinTitle			string	    NULL
    /call LoadIni General GemStuckHelp          string      "Sometimes the spellgems get stuck in a foreverloop, casting an altability that has a cast time will unstick it, this is an eq bug."
    /call LoadIni General GemStuckAbility       string	    NULL
    /call LoadIni General MiscGem               int         8
    /call LoadIni General MiscGemLW             int         0
    /call LoadIni General MiscGemRemem          int         1
    /call LoadIni General HoTTOn                int         0
    /call LoadIni General CampfireOn            int         0 
    /call LoadIni General GroupEscapeOn     int         0
    /call LoadIni General DPSMeter              int         1
    /call LoadIni General Scatter               int         0
    |/call LoadIni General ConditionsOn          int         2
    /call LoadIni General MoveCloserIfNoLOS     int         0
    /call LoadIni General CheerPeople			int			0
    /call LoadIni General CastRetries			int			3
    /call LoadIni General IRCOn                 int         0
    /call LoadIni General EQBCOn                string      0
    /call LoadIni General DanNetOn              string      0
    /call LoadIni General DanNetDelay           int         20
    /call LoadIni General SwitchWithMA			bool		FALSE
    /call LoadIni General TravelOnHorse			bool		FALSE


    /call LoadIni SpellSet LoadSpellSet          int         0
    /call LoadIni SpellSet SpellSetName          string      "MuleAssist"   


    /call LoadIni Buffs BuffsOn                 int         0
    /call LoadIni Buffs BuffsCOn                int         0          NULL         FALSE          ${ConditionsFileName}
    /call LoadIni Buffs BuffsSize               int         40
    /call LoadIni Buffs Buffs                   string      NULL       Buffs        BuffsCond      ${IniFileName} ${ConditionsFileName}
    /call LoadIni Buffs RebuffOn                int         1
    /call LoadIni Buffs CheckBuffsTimer         int         10
    /call LoadIni Buffs PowerSource             string      NULL
    /call LoadIni Buffs BegOn					string			0
    /call LoadIni Buffs BegSize					int			1
    /call LoadIni Buffs BegPermissionHelp		string		"Valid options are |raid|guild|fellowship|all|tell|group"
    /call LoadIni Buffs BegPermission			string		NULL
    /call LoadIni Buffs BegHelp					string		"Spellname|alias1,alias2,alias3 etc"
    /call LoadIni Buffs Beg						string		NULL		Beg			NULL			${IniFileName}
    /call LoadIni Buffs BuffCacheingDelay		int			300


    /call LoadIni Melee AssistAt                string         95
    /call LoadIni Melee MeleeOn             int         1
    /call LoadIni Melee MeleeOn             int         0
    /call LoadIni Melee FaceMobOn               int         1
    /call LoadIni Melee MeleeDistance           string         30
    /call LoadIni Melee StickHow                string      "snaproll rear"
    /call LoadIni Melee AutoFireOn              string         0
    /call LoadIni Melee UseMQ2Melee             int         1
    /call LoadIni Melee DismountDuringFights    int         0
    /call LoadIni Melee BeforeCombat        string      "Cast Before Melee Disc"
    /call LoadIni Melee AutoHide            int         1
    /call LoadIni Melee RogueTimerEight     string         Daggerslice
    /call LoadIni Melee TankAllMobs 			bool 		FALSE


    /call LoadIni GoM GoMOn                 int         1
    /call LoadIni GoM GoMSHelp              string       "Format - Spell|Target, MA Me or Mob, i.e. Rampaging Servant Rk. II|Mob"
    /call LoadIni GoM GoMCOn                int         0          NULL         FALSE          ${ConditionsFileName}
    /call LoadIni GoM GoMSize               int         4
    /call LoadIni GoM GoM              string      NULL       GoM     GoMCond        ${IniFileName} ${ConditionsFileName} 


    /call LoadIni GMail GMailHelp              string       "Events currently support - Dead,GM,Level,Named,Leftgroup,Say,Tell"
    /call LoadIni GMail GMailOn                int         0
    /call LoadIni GMail GMailSize              int         5
    /call LoadIni GMail GMail                  string        NULL       GMail


    /call LoadIni AE AEOn                       int         0
    /call LoadIni AE AESize                     int         20
    /call LoadIni AE AERadius                   int         50
    /call LoadIni AE AE                         string      NULL        AE


    /call LoadIni DPS DPSOn                     int         0
    /call LoadIni DPS DPSCOn                    int         0           NULL          FALSE           ${ConditionsFileName}
    /call LoadIni DPS DPSSize                   int         40
    /call LoadIni DPS DPSSkip                   int         1
    /call LoadIni DPS DPSInterval               int         2
    /call LoadIni DPS DPS                       string      NULL        DPS           DPSCond        ${IniFileName} ${ConditionsFileName}
    /call LoadIni DPS DebuffAllOn               int         0
    /call LoadIni DPS StayAwayToCast			bool		FALSE


    /call LoadIni Bandolier BandolierOn         int         0    
    /call LoadIni Bandolier BandolierCOn        int         0           NULL          FALSE           ${ConditionsFileName}
    /call LoadIni Bandolier BandolierSize       int	    2
    /call LoadIni Bandolier BandolierPull       string	    1HS
    /call LoadIni Bandolier Bandolier           string      NULL        Bandolier           BandolierCond        ${IniFileName} ${ConditionsFileName}


    /call LoadIni OhShit OhShitOn         int         0    
    /call LoadIni OhShit OhShitCOn        int         0           NULL          FALSE           ${ConditionsFileName}
    /call LoadIni OhShit OhShitSize          int	        10
    /call LoadIni OhShit       OhShit           string      NULL        OhShit        OhShitCond    ${IniFileName} ${ConditionsFileName}


    /call LoadIni Aggro AggroOn                 int         0
    /call LoadIni Aggro AggroCOn				int         0           NULL          FALSE           ${ConditionsFileName}
    /call LoadIni Aggro AggroSize           int         10
    /call LoadIni Aggro Aggro                   string      NULL        Aggro         AggroCond      ${IniFileName} ${ConditionsFileName}


    /call LoadIni General TwistOn           int         0
    /call LoadIni General TwistMed          string         "Mana song gem"
    /call LoadIni General TwistWhat         string      "Twist order here"
    /call LoadIni Melee MeleeTwistOn        int         0
    /call LoadIni Melee MeleeTwistWhat      string      "DPS twist order here"
    /call LoadIni Pull PullTwistOn          int         0


    /call LoadIni Heals Help                    string      "Format Spell|% to heal at i.e. Devout Light Rk. II|50"
    /call LoadIni Heals HealsOn                 int         0
    /call LoadIni Heals HealsCOn                int         0           NULL          FALSE           ${ConditionsFileName}
    /call LoadIni Heals	InterruptHeals			int			100
    /call LoadIni Heals HealsSize				int         40
    /call LoadIni Heals Heals                   string      NULL        Heals         HealsCond      ${IniFileName} ${ConditionsFileName} 
    /call LoadIni Heals XTarHeal                string      0
    /call LoadIni Heals AutoRezOn           int         0
    /call LoadIni Heals AutoRezWith         string      "Your Rez Item/AA/Spell"
    /call LoadIni Heals HealGroupPetsOn         int         0


    /call LoadIni Cures CuresOn                 int         0
    /call LoadIni Cures CuresSize               int         10
    /call LoadIni Cures Cures                   string      NULL        Cures
    /call LoadIni Cures Cures                   string      NULL       Cures        CuresCond      ${IniFileName} ${ConditionsFileName}


    /call LoadIni Pet PetOn                 int         0
    /call LoadIni Pet PetSpell              string      "YourPetSpell"
    /if (${Select[${Me.Class.ShortName},BST,MAG,NEC]})  /call LoadIni Pet PetFocus   string  "NULL"
    /call LoadIni Pet PetShrinkOn           int         0
    /call LoadIni Pet PetShrinkSpell        string      "Tiny Companion"
    /call LoadIni Pet PetBuffsOn            int         0
    /call LoadIni Pet PetBuffsSize          int         8
    /call LoadIni Pet PetBuffs              string      NULL        PetBuffs
    /call LoadIni Pet PetCombatOn           int         1
    /call LoadIni Pet PetAssistAt           string         95          
    /call LoadIni Pet PetToysSize           int         6
    /call LoadIni Pet PetToysOn         int         0
    /call LoadIni Pet PetToys           string      NULL        PetToys
    /call LoadIni Pet PetToysGave       string      NULL
    /call LoadIni Pet PetBreakMezSpell    string      NULL
    /call LoadIni Pet PetRampPullWait       int         0  
    /call LoadIni Pet PetSuspend            int         0
    /call LoadIni Pet MoveWhenHit           int         0
    /call LoadIni Pet PetHoldOn             int         1
    /call LoadIni Pet PetForceHealOnMed     int         0
    /call LoadIni Pet PetBehind             bool         TRUE


    /call LoadIni Mez MezOn                 int         0
    /call LoadIni Mez MezRadius             int         50
    /call LoadIni Mez MezMinLevel           int         "Min Mez Spell Level"
    /call LoadIni Mez MezMaxLevel           int         "Max Mez Spell Level"
    /call LoadIni Mez MezStopHPs            int         80
    /call LoadIni Mez MezSpell              string      "Your Mez Spell"
    /call LoadIni Mez MezAESpell            string      "Your AE Mez Spell|0"
    /call LoadIni "${ZoneName}" MezImmune string "List up to 10 mobs. Use full names i.e. a green snake,a blue tiger,a wide eye ooze or NULL" NULL False ${InfoFileName}


    /call LoadIni Burn  BurnCOn                 int         0           Null          FALSE            ${ConditionsFileName}
    /call LoadIni Burn  BurnSize                int         40
    /call LoadIni Burn  BurnText                string      "Burn this"
    /call LoadIni Burn  BurnAllNamed            int         0
    /call LoadIni Burn  Burn                    string      NULL        Burn          BurnCond        ${IniFileName} ${ConditionsFileName}
    /call LoadIni Burn  UseTribute              int         0


    /call LoadIni Pull PullWith                 string      "Melee"
    /call LoadIni Pull PullMeleeStick           int         0
    /call LoadIni Pull MaxRadius                int         350
    /call LoadIni Pull MaxZRange                int         50
    /call LoadIni Pull CheckForMemblurredMobsInCamp                 int         0
    /call LoadIni Pull PullWait                 int         5
    /call LoadIni Pull PullCond					string 		TRUE
    /call LoadIni Pull PrePullCond				string 		TRUE
    /call LoadIni "${ZoneName}" MobsToPull 		string 		"List up to 25 mobs. Use full names i.e. a green snake,a blue tiger,a wide eye ooze or ALL for all mobs" NULL False ${InfoFileName}
    /call LoadIni "${ZoneName}" MobsToPullSecondary string 	NULL 	NULL False ${InfoFileName}
    /call LoadIni "${ZoneName}" MobsToIgnore 	string 		"List up to 25 mobs. Use full names i.e. a green snake,a blue tiger,a wide eye ooze or NULL" NULL False ${InfoFileName}
    /call LoadIni "${ZoneName}" MobsToBurn 		string 		"List up to 10 mobs. Use full names i.e. Beget Cube,Helias,Raze or NULL" Null False ${InfoFileName}
    /call LoadIni "${ZoneName}" PullPath 		string 		"Place holder for path file. Not yet impletmented." NULL False ${InfoFileName}
    /call LoadIni Pull PullRoleToggle           int         0
    /call LoadIni Pull ChainPull                int         0
    /call LoadIni Pull ChainPullHP              int         90
    /call LoadIni Pull ChainPullPause           string      30|2
    /call LoadIni Pull PullLevel                string      0|0
    /call LoadIni Pull PullArcWidth             string      0
    /call LoadIni Pull PullNamedsFirst          int         0
    /call LoadIni Pull ActNatural               int         1
    /call LoadIni Pull UseCalm                  int         0
    /call LoadIni Pull CalmWith                 string      Harmony
    /call LoadIni Pull CalmRadius               int      	50
    /call LoadIni Pull GrabDeadGroupMembers     int         1


    /call LoadIni AFKTools AFKHelp              string      "AFKGMAction=0 Off, 1 Pause Macro, 2 End Macro, 3 Unload MQ2, 4 Quit Game"
    /call LoadIni AFKTools AFKToolsOn           int         1
    /call LoadIni AFKTools AFKGMAction          int         1
    /call LoadIni AFKTools AFKPCRadius          int         500
    /call LoadIni AFKTools CampOnDeath          int         0
    /call LoadIni AFKTools ClickBacktoCamp      int         0
    /call LoadIni AFKTools BeepOnNamed		    int         0


    /call LoadIni Rogue RogCorpseRetrieval		bool		FALSE
    /call LoadIni Rogue RogCorpseRadius			int			500


    /call LoadIni Merc Help                     string      "To use: Turn off Auto Assist in Manage Mercenary Window"
    /call LoadIni Merc MercOn                   int         0
    /call LoadIni Merc MercAssistAt             int         92


    /call LoadIni MySpells Gem${GemNum} string NULL
