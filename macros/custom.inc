#event CustomExp "#*#You gain party experience#*#"

#Bind ShakeLoose   /shakeloose

Sub InitCustom
	/echo InitCustom called
	/if (${Group.Leader.ID}==${Me.ID}) {
		/grouproles set ${Me} 5
	}
	|/varset MeleeDistance 400
	/ini "Loot.ini" "B" "Burled Wood" "Keep"
	/ini "Loot.ini" "C" "Crystal Harvester Mold" "Keep"
	/ini "Loot.ini" "F" "Faceted Crystal" "Keep"
	/ini "Loot.ini" "S" "Shimmering Hay" "Keep"
	/ini "Loot.ini" "T" "Tin Ore" "Keep"
	/declare bCustomInitdone int outer 1
	/declare SpotName string outer
	/declare SpotTimer timer outer
	/declare CustomName string outer
	/declare CustomTimer timer outer
	/declare CampCTimer timer outer
	/declare custoncount int outer
	/declare firstkill string outer
	/declare myoldyloc int outer
	/declare myoldxloc int outer
	/declare bFirstBanditsDone int outer 0
	/declare bForgeOnce int outer 1
	/declare bBurledOnce int outer 0
	/declare customstucktimer timer outer 0
	/declare customlastdist[6] int outer 0
	/declare DefendingKnowledgeMobList string outer
	/declare DinnerLocs[100] string outer 0
	/declare DinnerStep[100] string outer 0
	/declare CurrDinnerStep int outer 0
	/declare firstpartdone int outer
	/varset firstpartdone 0
/return

Sub Event_CustomExp
	/if (${Defined[bCustomInitdone]}==FALSE) {
		/call InitCustom
	}
	    /if (${custoncount}==0) {
		/varset firstkill ${Time}
	    }
	    /varcalc custoncount (${custoncount}+1)
	    /echo ${Time} Killed ${custoncount} mobs so far since ${firstkill}
            /echo SLAIN >> ${MyTargetName} << EXP: ${If[${Me.PctExp}<${MyExp},${Math.Calc[100-${MyExp}+${Me.PctExp}]},${Math.Calc[${Me.PctExp}-${MyExp}]}]}% AAEXP: ${If[${Me.PctAAExp}<${MyAAExp},${Math.Calc[100-${MyAAExp}+${Me.PctAAExp}]},${Math.Calc[${Me.PctAAExp}-${MyAAExp}]}]}%
            /popup SLAIN >> ${MyTargetName} << EXP: ${If[${Me.PctExp}<${MyExp},${Math.Calc[100-${MyExp}+${Me.PctExp}]},${Math.Calc[${Me.PctExp}-${MyExp}]}]}% AAEXP: ${If[${Me.PctAAExp}<${MyAAExp},${Math.Calc[100-${MyAAExp}+${Me.PctAAExp}]},${Math.Calc[${Me.PctAAExp}-${MyAAExp}]}]}%
	/doevents flush CustomExp
/return
Sub IsAnyoneInGroupOutofRange(int bShake, int therange)
	/declare gn int local 0
	/declare currdist int local 0
	/declare calcdist int local 0
	/for gn 1 to 5
		/if (${Group.Member[${gn}].Type.Equal[PC]}==TRUE && ${Group.Member[${gn}].Distance3D} > ${therange}) {
			/varset currdist ${Group.Member[${gn}].Distance3D}
			/echo ${Group.Member[${gn}].Name} is lagging behind at ${currdist}
			/squelch /bcaa //nav stop
			/if (${bShake}==0) {
				/bct ${Group.Member[${gn}].Name} //nav id ${Me.ID}
				/delay 2s
			} else {
				/varcalc calcdist ${customlastdist[${gn}]} + 20
				/if (${currdist} < ${calcdist}) {
					/beep
					/echo we are not getting anywhere time to shake loose...
					/bct ${Group.Member[${gn}].Name} //shakeloose 1
					/delay 6s
				}
			}
			/varset customlastdist[${gn}] ${Group.Member[${gn}].Distance3D}
			/return 1
		}
	/next gn
/return 0

Sub GroupContainsPCs
	/declare gn int local
	/for gn 1 to 5
		/if (${Group.Member[${gn}].Type.Equal[PC]}==TRUE) {
			/if (${Group.Member[${gn}].OtherZone}==FALSE && ${Group.Member[${gn}].Offline}==FALSE) {
				/echo we have a member in group thats here...
				/return 1
			}
		}
	/next gn
	/echo no group pcs detected...
/return 0

Sub WaitForNavToFinish2(int spawnID,int therad)
	/declare bWait int local 0
	/varset customstucktimer 0
	/declare bingroup int local 0
	/declare moveradius int local ${therad}
	/call GroupContainsPCs
	/if (${Macro.Return}==1) {
		/varset bingroup 1
	}
	/if (${SpawnCount[id ${Me.ID} loc ${Spawn[${spawnID}].X} ${Spawn[${spawnID}].Y} ${Spawn[${spawnID}].Z} radius 20]}==0) {
		/if (${Spawn[${spawnID}].LineOfSight}) {
			/if (${Spawn[${spawnID}].Distance3D} < 100) {
				/echo we are close enough to actually pull this...
				/return 1
			}
		}
		/if (${ingroup}==1) {
			/bcga //chase on
			/bcga //nav spawn id ${spawnID} | dist=20
		} else {
			/nav spawn id ${spawnID}
		}
		/delay 2s ${Navigation.Active}==TRUE
:navloop
		/if (${Spawn[${spawnID}].LineOfSight}) {
			/if (${Spawn[${spawnID}].Distance3D} < 100) {
				/echo we are close enough to actually pull this...
				/return 1
			}
		}
		/call IsAnyoneInGroupOutofRange 0 ${moveradius}
		/if (${Macro.Return}==1) {
			/if (${bWait}==0) {
				/varset customstucktimer 10s
				/varset bWait 1
			}
			/if (${customstucktimer}==0) {
				/echo Custom Timer Triggered most likely due to a character getting stuck
				|/beep
				/echo gonna try to unstick them
				/varset bWait 0
				/call IsAnyoneInGroupOutofRange 0 ${moveradius}
			}
			/delay 1
			/goto :navloop
		}
		/if (${Me.XTarget} > 0 && ${Me.XTarget[1].ID}) {
			/varset MeleeDistance ${therad}
			/echo we are under attack, lets stop and kill it.
			/if (${ingroup}==1) {
				/bcga //nav id ${Me.XTarget[1].ID}
			} else {
				/nav id ${Me.XTarget[1].ID}
			}
			/delay 2s ${Navigation.Active}==TRUE
			/delay 10s ${Navigation.Active}==FALSE
			/return 0
		}
		/if (${Navigation.Active}==TRUE) {
			/delay 1
			/goto :navloop
		}
	} else {
		/echo we think we are 20 feet from the mob...
		/return 1
	}
/return 0

Sub WaitForNavToFinish(int y,int x,int z,int therad)
	/declare bWait int local 0
	/varset customstucktimer 0
	/declare bIngroup int local 0
	/declare moveradius int local ${therad}
	/call GroupContainsPCs
	/if (${Macro.Return}==1) {
		/varset bIngroup 1
	}
	/if (${SpawnCount[id ${Me.ID} loc ${x} ${y} radius 20]}==0) {
		/if (${bIngroup}) {
			/bcaa //chase on
			/bcaa //nav locyxz ${y} ${x} ${z}
		} else {
			/chase on
			/nav locyxz ${y} ${x} ${z}
		}
		/delay 2s ${Navigation.Active}==TRUE
:navloop
		/call IsAnyoneInGroupOutofRange 0 ${moveradius}
		/if (${Macro.Return}==1) {
			/if (${bWait}==0) {
				/varset customstucktimer 10s
				/varset bWait 1
			}
			/if (${customstucktimer}==0) {
				/echo Custom Timer Triggered most likely due to a character getting stuck
				|/beep
				/echo gonna try to unstick them
				/varset bWait 0
				/call IsAnyoneInGroupOutofRange 0 ${moveradius}
			}
			/delay 5
			/goto :navloop
		}
		/if (${Me.XTarget} > 0 && ${Me.XTarget[1].ID}) {
			/varset MeleeDistance ${therad}
			/echo we are under attack, lets stop and kill it.
			/if (${bIngroup}) {
				/bcaa //nav id ${Me.XTarget[1].ID}
			} else {
				/nav id ${Me.XTarget[1].ID}
			}
			/delay 2s ${Navigation.Active}==TRUE
			/delay 10s ${Navigation.Active}==FALSE
			/return 0
		}
		/if (${Navigation.Active}==TRUE) {
			/delay 5
			/goto :navloop
		}
	} else {
		/return 1
	}
/return 0

Sub LookupKeyWord(string name)
	/if (${name.Equal[A boisterous bard]}) {
		/return music
	}
	/if (${name.Equal[A bobtailed beastlord]}) {
		/return fluffy
	}
	/if (${name.Equal[A bloodthirsty berserker]}) {
		/return vampires
	}
	/if (${name.Equal[A crafty cleric]}) {
		/return food
	}
	/if (${name.Equal[A dubious druid]}) {
		/return dead
	}
	/if (${name.Equal[An eloquent enchanter]}) {
		/return hello
	}
	/if (${name.Equal[A misunderstood magician]}) {
		/return tell
	}
	/if (${name.Equal[A mysterious monk]}) {
		/return tranquility
	}
	/if (${name.Equal[A noctilucent necromancer]}) {
		/return How
	}
	/if (${name.Equal[A peaceful paladin]}) {
		/return room
	}
	/if (${name.Equal[A rambunctious ranger]}) {
		/return old
	}
	/if (${name.Equal[A ravenous rogue]}) {
		/return fun
	}
	/if (${name.Equal[A stylish shaman]}) {
		/return drink
	}
	/if (${name.Equal[A wayward warrior]}) {
		/return mother
	}
	/if (${name.Equal[A worldly wizard]}) {
		/return name
	}
	/if (${name.Equal[a suspicious shadowknight]}) {
		/return bug
	}
/return BLAH

Sub SpeakWithGuests
	/declare i int local
	/declare cname string local
	/declare talklist[8] string local
	/echo we should speak with the guests...
	
	/for i 1 to ${SpawnCount[npc loc 4 3481 radius 50]}
		/varset talklist[${i}] ${NearestSpawn[${i}, npc loc 4 3481 radius 50].CleanName}
	/next i
	/for i 1 to 8
		/varset cname ${talklist[${i}]}
		/echo I need to talk to: [${i}] ${cname}
		/call LookupKeyWord "${cname}"
		/call DoClass "${cname}" ${Macro.Return}
	/next i
	/echo we talked to them all
/return

Sub DoClass(string name,string keyword)
	/echo we should speak with ${name} and say ${keyword} to them
	/if (${Spawn[npc ${name}].Distance3D} > 20) {
		/nav id ${Spawn[npc ${name}].ID}
		/delay 2s ${Navigation.Active}==TRUE
		/delay 30s ${Navigation.Active}==FALSE
	}
	/if (${Spawn[npc ${name}].Distance3D} < 20) {
		/target id ${Spawn[npc ${name}].ID}
		/delay 5s ${Target.ID}==${Spawn[npc ${name}].ID}
		/say ${keyword}
		/delay 1s	
	} else {
		/beep
		/echo something is wrong, we are too far away from the druid...
		/end
	}
/return

Sub GetUsTheClosestValidMob
	/declare i int local
	/declare nearestmobdist float local 10000.0
	/declare currdist float local
	/declare nearestmobID int local 0
	/declare mobarray[200] int local
	/for i 1 to ${SpawnCount[npc radius 800 zradius 150]}
		/varset mobarray[${i}] ${NearestSpawn[${i},npc radius 800 zradius 150].ID}
	/next i
	/for i 1 to 200
		/if (${Spawn[${mobarray[${i}]}].ID}) {
			/if (${Spawn[${mobarray[${i}]}].Level} > 109 && ${Spawn[${mobarray[${i}]}].Level} < 114) {
				/if (${Spawn[${mobarray[${i}]}].CleanName.Equal[a skeletal musician]}) /continue
				/if (${Spawn[${mobarray[${i}]}].CleanName.Find[Melion Pell]}==1) /continue
				/if (${Spawn[${mobarray[${i}]}].CleanName.Find[Doorman]}==1) /continue
				/if (${Spawn[${mobarray[${i}]}].CleanName.Find[Mr.]}==1) /continue
				/if (${Navigation.PathExists[id ${mobarray[${i}]}]}) {
					/if (${Spawn[${mobarray[${i}]}].X} > -190 || (${Spawn[${mobarray[${i}]}].X} < -190 && ${Spawn[${mobarray[${i}]}].Y} < 2890)) {
						|/echo ${Spawn[${mobarray[${i}]}].Name} ${Spawn[${mobarray[${i}]}].X}
						/varset currdist ${Navigation.PathLength[id ${mobarray[${i}]}]}
						|/echo ${mobarray[${i}]} ${Spawn[${mobarray[${i}]}].Name} ${Spawn[${mobarray[${i}]}].Race} ${Navigation.PathLength[id ${mobarray[${i}]}]}
						/if (${currdist} < ${nearestmobdist}) {
							/varset nearestmobdist ${currdist}
							/varset nearestmobID ${mobarray[${i}]}
						}
					}
				}
			}
		}
	/next i
	/tar id ${nearestmobID}
	/echo nearest mob is ${nearestmobID}
/return ${nearestmobID}

Sub TradeSomething(string thething)
	/declare finditemID int local
	/while (${Cursor.ID}) {
		/echo dropping ${Cursor.ID} into inventory
		/autoinv
		/delay 1s
	}
	/varset finditemID ${FindItem[=${thething}].ID}
	/if (${finditemID}) {
		/ctrl /itemnotify "${thething}" leftmouseup
		/delay 2s ${Cursor.ID}==${finditemID}
		/delay 1s
		/click left target
		/delay 5s !${Cursor.ID}
		/delay 1s
		/delay 5s ${Window[GiveWnd].Open} && ${Window[GiveWnd].Child[GVW_MyItemSlot0].Tooltip.Equal[${thething}]}
		/if (${Window[InventoryWindow].Open}) /windowstate InventoryWindow close
		/if (${Window[GiveWnd].Open} && ${Window[GiveWnd].Child[GVW_MyItemSlot0].Tooltip.Equal[${thething}]}) {
			/echo window is open and ${thething} is there lets trade...
			/notify GiveWnd GVW_Give_Button leftmouseup
			/delay 3s ${Window[GiveWnd].Open}==FALSE
		}
	}
/return


Sub DoBerry
	/if (${Me.Hovering}) /return
	/if (${Defined[bCustomInitdone]}==FALSE) {
		/call InitCustom
	}
	/declare tempmobID int local
	/if (${Group.MasterLooter.ID}!=${Me.ID}) {
		/echo I HAVE to be the masterlooter...
		/grouproles set ${Me} 5
		/beep
		/delay 1s
	}
	/if (${Window[TaskWnd].Open}==FALSE) {
		/beep
		/echo this macro requires that the TaskWnd is open but you CAN minimize t if you like
		/windowstate TaskWnd open
		/delay 2s ${Window[TaskWnd].Open}==TRUE
	}
	/if (${Window[TaskWnd].Child[TASK_TaskList].GetCurSel}!=1) {
		/invoke ${Window[TaskWnd].Child[TASK_TaskList].Select[A Formal Dinner Party]}
		/delay 5
	}
	/if (${Task.Title.NotEqual[A Formal Dinner Party]}) {
		/echo this macro requires that the Task A Formal Dinner Party is active
		/end
	}
	/if (${Task.Leader.NotEqual[${Me}]}) {
		/echo i have to be the task leader...
		/delay 1s
		/return
	}
	/if (${Task[A Formal Dinner Party].Step.Instruction.Equal[Deliver 1 Fancy Formal Dinner Invitation to the doorman]}) {
		/echo doorman
		/nav spawn id ${Spawn[npc doorman].ID} | dist=19
		/delay 2s ${Navigation.Active}==TRUE
		/delay 30s ${Navigation.Active}==FALSE
		/target id ${Spawn[npc doorman].ID}
		/delay 2s ${Target.ID}==${Spawn[npc doorman].ID}
		/call TradeSomething "Fancy Formal Dinner Invitation"
		/delay 4s ${Task[A Formal Dinner Party].Step.Instruction.Equal[Deliver 1 Fancy Formal Dinner Invitation to the doorman]}==FALSE
	}
	/if (${Task[A Formal Dinner Party].Step.Instruction.Equal[Speak with the Guests]}) {
		/call SpeakWithGuests
	}
	/if (${Task[A Formal Dinner Party].Step.Instruction.Equal[Speak with Melion Pell]}) {
		/echo speak to pell
		/nav spawn id ${Spawn[npc Melion].ID} | dist=19
		/delay 2s ${Navigation.Active}==TRUE
		/delay 30s ${Navigation.Active}==FALSE
		/target id ${Spawn[npc Melion].ID}
		/delay 2s ${Target.ID}==${Spawn[npc Melion].ID}
		/say investigate
		/delay 4s ${Task[A Formal Dinner Party].Step.Instruction.Equal[Speak with Melion Pell]}==FALSE
		/bcga //nav id ${Me.ID}
		/delay 2s
		/echo we are sitting to shake loose from the door, sometimes chanter gets stuck...

		/bcga //sit
		/delay 1s
	}
	/if (${Group.AnyoneMissing}==TRUE) {
		/beep
		/echo groupmember gone awol need to wait for it
		/delay 1s
		/return
	}
	/if (${Me.Z} > 90 && ${Me.Z} < 200 && ${firstpartdone} < 3) {
		/if (${SpawnCount[npc loc 0 63 -1290 radius 200]}==0) {
			/beep
			/echo well looks like we are in the hallway outside stairs and ritual area is cleared...
			/varset firstpartdone 11
		}
	}
	/if (${Me.Z} > -550 && ${Me.Z} < 90 && ${firstpartdone} < 2) {
		/if (${SpawnCount[npc loc 0 63 -1290 radius 200]}==0) {
			/beep
			/echo well looks like we are at top of stairs...
			/varset firstpartdone 10
		}
	}
	/if (${Me.Z} > -1050 && ${Me.Z} < -900 && ${firstpartdone} < 2) {
		/beep
		/echo well looks like we are down stairs...
		/varset firstpartdone 2
	}
	/if (${Me.Z} < -900 && ${Me.Z} > -1060 && ${firstpartdone} < 3) {
		/beep
		/if (${SpawnCount[npc loc 0 63 -1290 radius 200]}==0) {
			/echo well looks like we are at the bottom of stairs and ritual area is cleared...
			/varset firstpartdone 10
		} else {
			/echo well looks like we are at the bottom...
			/varset firstpartdone 3
		}
	}
	/if (${Me.Z} < -1050 && ${Me.Z} > -1200 && ${firstpartdone} < 3) {
		/beep
		/if (${SpawnCount[npc loc 0 63 -1290 radius 200]}==0) {
			/echo well looks like we are in the study and ritual area is cleared...
			/varset firstpartdone 9
		} else {
			/echo well looks like we are in the study...
			/varset firstpartdone 5
		}
		/bcga //chase on
		/bcga //mqp off
		/delay 2s
	}
	/if (${Me.Z} < -1200 && ${firstpartdone} < 3) {
		/beep
		/echo well looks like we are in the ritual area...
		/varset firstpartdone 7
		/bcga //chase on
		/bcga //mqp off
		/delay 2s
	}
	/if (${Task[A Formal Dinner Party].Step.Instruction.Equal[Show Melion Pell the proof]} && ${firstpartdone}==0) {
		/call GetHostilesOnXTarget
		/if (${Macro.Return} == 0) {
			/echo doing ${Task[A Formal Dinner Party].Step.Instruction}
			/bcaa //chase on
			/call GetUsTheClosestValidMob
			/varset tempmobID ${Macro.Return}
			/if (${tempmobID}) {
				/echo We found a valid mob to kill: ${Spawn[${tempmobID}]}
				/if (${Me.Gem[${Spell[${PullWith}]}]}!=0) {
					/call WaitForNavToFinish2 ${Spawn[${tempmobID}].ID} 80
					/if (${Macro.Return}==1) {
						/echo according to WaitForNavToFinish2 we are close enough to kill this mob...
						/if (${Target.ID}!=${Spawn[${tempmobID}].ID}) {
							/target id ${Spawn[${tempmobID}].ID}
							/delay 2s ${Target.ID}==${Spawn[${tempmobID}].ID}
						}
						/cast "${PullWith}"
						/call WaitCast ${Spell[${PullWith}].MyCastTime}
					} else {
						/echo well we could not get close enough, lets try naving closer:
						/call WaitForNavToFinish ${Spawn[${tempmobID}].Y} ${Spawn[${tempmobID}].X} ${Spawn[${tempmobID}].Z} 80
					}
				} else {
					|we move all the way to the mob
					/call WaitForNavToFinish ${Spawn[${tempmobID}].Y} ${Spawn[${tempmobID}].X} ${Spawn[${tempmobID}].Z} 80
				}
			} else {
				/varset firstpartdone 1
				/if (${SpawnCount[id ${Me.ID} loc -186 2696 radius 50]}==0) {
					/echo ok we have cleared all of the upper floors except library, let head down...
					/bcga //nav door id 6 | dist=15
					/delay 2s ${Navigation.Active}==TRUE
					/delay 180s ${Navigation.Active}==FALSE
				}
			}
			/delay 1s
		}
	}
	/if (${Task[A Formal Dinner Party].Step.Instruction.Equal[Show Melion Pell the proof]} && ${firstpartdone}==1) {
		/if (${SpawnCount[id ${Me.ID} loc -186 2696 radius 50]}==0) {
			/echo need to get over to door
			/call WaitForNavToFinish 2696 -186 127 80
		}
		/bcg //mqp on
		:checkgroupvsdoor
		/echo give me a few secs to get everyone to door 6...
		/delay 5s
		/if (${Group.Member[1].ID} && ${Group.Member[1].Distance3D} > 20) {
			/bcga //nav door id 6
			/delay 2s ${Navigation.Active}==TRUE
			/delay 180s ${Navigation.Active}==FALSE
			/goto :checkgroupvsdoor
		}
		/if (${Group.Member[2].ID} && ${Group.Member[2].Distance3D} > 20) {
			/bcga //nav door id 6
			/delay 2s ${Navigation.Active}==TRUE
			/delay 180s ${Navigation.Active}==FALSE
			/goto :checkgroupvsdoor
		}
		/if (${Group.Member[3].ID} && ${Group.Member[3].Distance3D} > 20) {
			/bcga //nav door id 6
			/delay 2s ${Navigation.Active}==TRUE
			/delay 180s ${Navigation.Active}==FALSE
			/goto :checkgroupvsdoor
		}
		/if (${Group.Member[4].ID} && ${Group.Member[4].Distance3D} > 20) {
			/bcga //nav door id 6
			/delay 2s ${Navigation.Active}==TRUE
			/delay 180s ${Navigation.Active}==FALSE
			/goto :checkgroupvsdoor
		}
		/if (${Group.Member[5].ID} && ${Group.Member[5].Distance3D} > 20) {
			/bcga //nav door id 6
			/delay 2s ${Navigation.Active}==TRUE
			/delay 180s ${Navigation.Active}==FALSE
			/goto :checkgroupvsdoor
		}
		/if (${Group.Member[6].ID} && ${Group.Member[6].Distance3D} > 20) {
			/bcga //nav door id 6
			/delay 2s ${Navigation.Active}==TRUE
			/delay 180s ${Navigation.Active}==FALSE
			/goto :checkgroupvsdoor
		}
		/bcga //doort id 6
		/delay 2s ${Switch.ID}==6
		/delay 3s
		/bcga //click left door
		/varset firstpartdone 2
	}
	/if (${Task[A Formal Dinner Party].Step.Instruction.Equal[Show Melion Pell the proof]} && ${firstpartdone}==2) {
		/call ClickOurDoor 6
		/echo we are all here
		/delay 1s
		/bcga //nav locyxz 40 20 -1000
		/delay 2s ${Navigation.Active}==TRUE
		/delay 180s ${Navigation.Active}==FALSE
		/varset firstpartdone 3
		|/mqp
	}
	/if (${Task[A Formal Dinner Party].Step.Instruction.Equal[Show Melion Pell the proof]} && ${firstpartdone}==3) {
		/bcaa //chase on
		/bcg //mqp off
		/delay 3s
		/call GetHostilesOnXTarget
		/if (${Macro.Return} != 0) {
			/return
		}
		/if (${SpawnCount[id ${Me.ID} loc 40 20 radius 50]}==0) {
			/echo need to get over to door
			/call WaitForNavToFinish ${Me.Y} ${Me.X} ${Me.Z} 80
		}
		/delay 1s
		/echo we are at the bottom
		/varset firstpartdone 4
	}
	/if (${Task[A Formal Dinner Party].Step.Instruction.Equal[Show Melion Pell the proof]} && ${firstpartdone}==4) {
		/bcg //mqp on
		/delay 2s
		:checkgroupvsdoor2
		/echo give me a few secs to get everyone to door 3...
		/delay 5s
		/if (${Group.Member[1].ID} && ${Group.Member[1].Distance3D} > 20) {
			/bcga //nav locyxz 40 20 -1000
			/delay 2s ${Navigation.Active}==TRUE
			/delay 180s ${Navigation.Active}==FALSE
			/goto :checkgroupvsdoor2
		}
		/if (${Group.Member[2].ID} && ${Group.Member[2].Distance3D} > 20) {
			/bcga //nav locyxz 40 20 -1000
			/delay 2s ${Navigation.Active}==TRUE
			/delay 180s ${Navigation.Active}==FALSE
			/goto :checkgroupvsdoor2
		}
		/if (${Group.Member[3].ID} && ${Group.Member[3].Distance3D} > 20) {
			/bcga //nav locyxz 40 20 -1000
			/delay 2s ${Navigation.Active}==TRUE
			/delay 180s ${Navigation.Active}==FALSE
			/goto :checkgroupvsdoor2
		}
		/if (${Group.Member[4].ID} && ${Group.Member[4].Distance3D} > 20) {
			/bcga //nav locyxz 40 20 -1000
			/delay 2s ${Navigation.Active}==TRUE
			/delay 180s ${Navigation.Active}==FALSE
			/goto :checkgroupvsdoor2
		}
		/if (${Group.Member[5].ID} && ${Group.Member[5].Distance3D} > 20) {
			/bcga //nav locyxz 40 20 -1000
			/delay 2s ${Navigation.Active}==TRUE
			/delay 180s ${Navigation.Active}==FALSE
			/goto :checkgroupvsdoor2
		}
		/if (${Group.Member[6].ID} && ${Group.Member[6].Distance3D} > 20) {
			/bcga //nav locyxz 40 20 -1000
			/delay 2s ${Navigation.Active}==TRUE
			/delay 180s ${Navigation.Active}==FALSE
			/goto :checkgroupvsdoor2
		}
		/bcga //doort id 3
		/delay 2s ${Switch.ID}==3
		/delay 3s
		/bcga //click left door
		/call ClickOurDoor 3
		/delay 1s
		/varset firstpartdone 5
		/bcga //chase on
		/bcga //mqp off
	}
	/if (${Task[A Formal Dinner Party].Step.Instruction.Equal[Show Melion Pell the proof]} && ${firstpartdone}==5) {
		/call GetHostilesOnXTarget
		/if (${Macro.Return} == 0) {
			/echo doing ${Task[A Formal Dinner Party].Step.Instruction}
			/bcaa //chase on
			/bcga //mqp off
			/call GetUsTheClosestValidMob
			/varset tempmobID ${Macro.Return}
			/if (${tempmobID}) {
				/echo ${Spawn[${tempmobID}]}
				/if (${SpawnCount[id ${tempmobID} loc -8 -117 -1099 radius 20]}==1) {
					/echo don't wanna fall out the window...
					/echo need to pull this guy differently
					/tar id ${tempmobID}
					/delay 1s ${Target.ID}==${tempmobID}
					/bcga //nav locyxz -88 2 -1100
					/delay 5s ${Navigation.Active}==TRUE
					/delay 15s ${Navigation.Active}==FALSE
				} else {
					|/mqp
					/call WaitForNavToFinish2 ${tempmobID} 80
				}
			} else {
				/varset firstpartdone 6
				/echo study cleared...
				/itemtarget
				/delay 2s ${Ground.ID}
				/ini "${MacroQuest.Path}\Macros\FancyDInner.ini" "Study" "${Ground}" "${Ground.ID}"
			}
			/delay 1s
		}
	}
	/if (${Task[A Formal Dinner Party].Step.Instruction.Equal[Show Melion Pell the proof]} && ${firstpartdone}==6) {
		/bcg //mqp on
		/bcg //stick off
		/echo needs to kill weapon racks now...
		/bcga //target weapon object
		/delay 1s ${Target.CleanName.Equal[a weapon rack]}
		/if (${Target.CleanName.Equal[a weapon rack]}) {
			/bcga //nav id ${Target.ID}
			/delay 1s ${Navigation.Active}==TRUE
			/delay 10s ${Navigation.Active}==FALSE
			/bcga //attack on
			/delay 5s ${Target.Dead}
		}
		/if (${SpawnCount[object weapon]}==0) {
			/itemtarget
			/delay 2s ${Ground.ID}
			/ini "${MacroQuest.Path}\Macros\FancyDInner.ini" "Study" "${Ground}" "${Ground.ID}"
			/echo we can move on
			/call GetAllToDoor 9
			/delay 1s
			/call ClickOurDoor 9
			/call AllAtMyZ -1200 -1300
			/if (${Macro.Return}==1) {
				/echo we are good to go
				/varset firstpartdone 7
			}
		}
	}
	/if (${Task[A Formal Dinner Party].Step.Instruction.Equal[Show Melion Pell the proof]} && ${firstpartdone}==7) {
		/call GetHostilesOnXTarget
		/if (${Macro.Return} == 0) {
			/echo doing ${Task[A Formal Dinner Party].Step.Instruction}
			/bcaa //chase on
			/bcga //mqp off
			/call GetUsTheClosestValidMob
			/if (${Macro.Return}) {
				/echo ${Spawn[${Macro.Return}]}
				/call WaitForNavToFinish ${Spawn[${Macro.Return}].Y} ${Spawn[${Macro.Return}].X} ${Spawn[${Macro.Return}].Z} 80
			} else {
				/varset firstpartdone 8
				/echo ritual area cleared...
			}
			/delay 1s
		}
	}
	/if (${Task[A Formal Dinner Party].Step.Instruction.Equal[Show Melion Pell the proof]} && ${firstpartdone}==8) {
		/echo we can move up again ritual area is cleared...
		/bcga //chase off
		/bcga //camphere off
		/bcg //mqp on
		/itemtarget
		/delay 2s ${Ground.ID}
		/ini "${MacroQuest.Path}\Macros\FancyDInner.ini" "Ritual" "${Ground}" "${Ground.ID}"
		/call GetAllToDoor 10
		/delay 1s
		/call ClickOurDoor 10
		/call AllAtMyZ -1100 -1200
		/if (${Macro.Return}==1) {
			/echo we are in the Study again, lets move up
			/varset firstpartdone 9
		}
	}
	/if (${Task[A Formal Dinner Party].Step.Instruction.Equal[Show Melion Pell the proof]} && ${firstpartdone}==9) {
		/echo back in the study again...
		/bcga //chase off
		/bcga //camphere off
		/bcg //mqp on
		/itemtarget
		/delay 2s ${Ground.ID}
		/ini "${MacroQuest.Path}\Macros\FancyDInner.ini" "Study" "${Ground}" "${Ground.ID}"
		/bcga //nav locyxz 43 21 -1100
		/delay 1s ${Navigation.Active}==TRUE
		/delay 10s ${Navigation.Active}==FALSE
		/call GetAllToDoor 7
		/delay 1s
		/call ClickOurDoor 7
		/call AllAtMyZ -1000 -1090
		/if (${Macro.Return}==1) {
			/echo we are at the bottom Stairs again, lets move up
			/varset firstpartdone 10
		}
	}
	/if (${Task[A Formal Dinner Party].Step.Instruction.Equal[Show Melion Pell the proof]} && ${firstpartdone}==10) {
		/echo back in the stairs again...
		/bcga //chase off
		/bcga //camphere off
		/bcg //mqp on
		/bcga //nav locyxz 0 -80 -525
		/delay 1s ${Navigation.Active}==TRUE
		/delay 30s ${Navigation.Active}==FALSE
		/call GetAllToDoor 5
		/echo everyone is at door 5 now clicking it
		/delay 1s
		/call ClickOurDoor 5
		/echo we clicked it, lets make sure everyone is at my z ${Me.Z}
		/delay 2s
	:retryzloc
		/call AllAtMyZ 200 100
		/if (${Macro.Return}==1) {
			/echo we are outside stairs up top again, lets move out into the hallway
			/varset firstpartdone 11
		} else {
			/echo we are not all at my Z, wth?
			/mqp
			/goto :retryzloc
		}
	}
	/if (${Task[A Formal Dinner Party].Step.Instruction.Equal[Show Melion Pell the proof]} && ${firstpartdone}==11) {
		/echo at this point we have cleared everything we can safely clear
		/echo the last part is the library
		/echo you will need to pull that manually
		/echo you should also check your bags at this point
		/echo maybe you already have the 4 items?
		/echo if you do, just go to mellon pell and turn them in...
		/echo you can lookup ritual area and study fancy items in FancyDinner.ini
		/bcga //chase off
		/bcga //camphere off
		/bcg //mqp on
		/bcga //nav locyxz 2500 40 100
		/delay 1s ${Navigation.Active}==TRUE
		/delay 30s ${Navigation.Active}==FALSE
		/delay 3s
		/bcga //camphere on
		/bcg //mqp off
		/face heading 340
		/delay 2s
		/echo lets get the guys into halfmoon formation...
		/halfmoon 15
		/tar id ${Me.ID}
		/varset firstpartdone 12
		/echo you have the wheel captain... go pull some library mobs back here the /mqp to fight on...
		/mqp on

	}

/return


Sub GetAllToDoor(int doorID)
	/declare i int local
	/declare allhere int local 1
	/doortarget id ${doorID}
	/delay 2s ${Switch.ID}==${doorID}
	:movetodooragain
	/varset allhere 1
	/for i 0 to 5
		/if (${Group.Member[${i}].Type.Equal[PC]}==TRUE) {
			/if (${doorID}==5) {
				/if (${Group.Member[${i}].Z} > 100) {
					/continue
				}
			}
			/if (${doorID}==9) {
				/if (${Group.Member[${i}].Z} < -1202) {
					/continue
				}
			}
			/if (${doorID}==10) {
				/if (${Group.Member[${i}].Z} > -1201) {
					/continue
				}
			}
			/if (${Math.Distance[${Group.Member[${i}].Y},${Group.Member[${i}].X},${Group.Member[${i}].Z}:${Switch.Y},${Switch.X},${Switch.Z}]} > 25) {
				/if (${doorID}==5) {
					/bct ${Group.Member[${i}].Name} //nav locyxz 0 -80 -525
				} else /if (${doorID}==7) {
					/bct ${Group.Member[${i}].Name} //nav locyxz 43 21 -1100
				} else {
					/bct ${Group.Member[${i}].Name} //nav door id ${doorID}
				}
				/varset allhere 0
			}
		}
	/next i
	/if (${allhere}==0) {
		/echo movetodooragain
		/delay 5s
		/goto :movetodooragain
	}
	/echo we are all at ${Switch}
/return

Sub AllAtMyZ(int myzbottom, int myztop)
	/declare i int local
	/declare allhere int local 1
	/varset allhere 1
	/for i 1 to 5
		/if (${Group.Member[${i}].Type.Equal[PC]}==TRUE) {
			/if (${Group.Member[${i}].Z} < ${myzbottom} && ${Group.Member[${i}].Z} > ${myztop}) {
				/echo ${Group.Member[${i}]} is at my z
			} else {
				/beep
				/echo ${Group.Member[${i}]} is NOT at my z
				/return 0
			}
		}
	/next i
/return 1

Sub ClickOurDoor(int doorID)
	/bcga //doort id ${doorID}
	/delay 2s ${Switch.ID}==${doorID}
	/bcga //click left door
	/delay 2s
/return

Sub DoCleet
	/if (${Defined[bCustomInitdone]}==FALSE) {
		/call InitCustom
	}
	/if (${Group.MasterLooter.ID}!=${Me.ID}) {
		/echo I HAVE to be the masterlooter...
		/grouproles set ${Me} 5
		/beep
		/delay 1s
	}
	/if (${Window[TaskWnd].Open}==FALSE) {
		/beep
		/echo this macro requires that the TaskWnd is open but you CAN minimize t if you like
		/windowstate TaskWnd open
		/delay 2s ${Window[TaskWnd].Open}==TRUE
	}
	/if (${Window[TaskWnd].Child[TASK_TaskList].GetCurSel}!=1) {
		/invoke ${Window[TaskWnd].Child[TASK_TaskList].Select[Sprucing up Shakey]}
		/delay 5
	}
	/if (${Task.Title.NotEqual[Sprucing Up Shakey]}) {
		/echo this macro requires that the Task Sprucing Up Shakey is active
		/end
	}
	/if (${Task.Leader.NotEqual[${Me}]}) {
		/return
	}
	|need to clear this so we can loot it again at the end...
	/if (${Task[0].Step.Instruction.Equal[Speak with Cleet Miller at his Farm]}) {
		/if (${FindItemCount[Shimmering Hay]}) {
			/itemnotify "Shimmering Hay" leftmouseup
			/delay 1s ${Cursor.ID}
			/destroyitem
		}
	}
	/if (${Group.AnyoneMissing}==TRUE) {
		/beep
		/echo groupmember gone awol need to wait for it
		/delay 1s
		/return
	}
	/if (${Task[0].Step.Instruction.Equal[Speak with Cleet Miller at his Farm]}) {
		/echo doing ${Task[0].Step.Instruction}
		/call WaitForNavToFinish -2200 -4140 0  400
		/if (${Macro.Return}==1) {
			/tar id ${Spawn[npc Cleet Miller].ID}
			/echo now hail cleet
			/keypress h
			/say till
		}
	} else /if (${Task[0].Step.Instruction.Equal[Loot Burled Wood]} && ${Me.XTarget}==0) {
		/if (${bBurledOnce}==0) {
			/varset bBurledOnce 1
			/call WaitForNavToFinish -2253 -4020 0 400
		}
		/echo doing ${Task[0].Step.Instruction}
		/bcaa //chase on
		/tar npc treant
		/delay 1s ${Target.ID}
		/echo treant aquired navigating to ${Target.Y} ${Target.X} ${Target.Z}
		/call WaitForNavToFinish ${Target.Y} ${Target.X} ${Target.Z} 400
		|/if (${Macro.Return}==1) {
			/bcaa //Stick 5
			/bcaa //attack on
		|}
	} else /if (${Task[0].Step.Instruction.Equal[Loot Tin Ore]} && ${Me.XTarget}==0) {
		/echo doing ${Task[0].Step.Instruction}
		/bcaa //chase on
		/tar npc goblin
		/call WaitForNavToFinish ${Target.Y} ${Target.X} ${Target.Z} 400
		|/if (${Macro.Return}==1) {
			/bcaa //Stick 5
			/bcaa //attack on
		|}
	} else /if (${Task[0].Step.Instruction.Equal[Loot Faceted Crystal]} && ${Me.XTarget}==0) {
		/echo doing ${Task[0].Step.Instruction}
		/if (${SpawnCount[npc bandit loc -7058 905 radius 100]}!=0) {
			/call WaitForNavToFinish 1089 -7220 36 400
			/if (${Macro.Return}==1) {
				/tar npc bandit
				/echo everyone is here we can attack
				/bcaa //Stick 5
				/bcaa //attack on
				/delay 10s ${Target.Distance3D} < 20 && ${Me.XTarget}
			}
		} else {
			/bcaa //chase on
			/tar npc bandit
			/call WaitForNavToFinish ${Target.Y} ${Target.X} ${Target.Z} 400
			|/if (${Macro.Return}==1) {
				/bcaa //Stick
				/bcaa //attack on
				/delay 10s ${Target.Distance3D} < 20 && ${Me.XTarget}
			|}
		}
	} else /if (${Task[0].Step.Instruction.Equal[Obtain a Crystal Harvester Mold from Spinner]} && ${Me.XTarget}==0) {
		/echo doing ${Task[0].Step.Instruction}
		/call WaitForNavToFinish -1450 -12775 4 400
		/if (${Macro.Return}==1) {
			/echo everyone is here we can attack spinner, unpause when he attacks
			/tar npc spinner
			/say enemy
		}
	} else /if (${Task[0].Step.Instruction.Find[Combine the Burled Wood]}==1 && ${Me.XTarget}==0) {
		/echo doing ${Task[0].Step.Instruction}
		/call WaitForNavToFinish -1436 -12885 6 400
		/if (${Macro.Return}==1) {
			/declare comb int local 1
			/if (!${Window[TradeskillWnd].Open}) {
				/itemtarget forge
				/click left item
			} else {
				/beep
				/beep
				/echo everyone is here we can combine the things
			:waitforharvester
				/if (${Window[TradeskillWnd].Open}) {
					/invoke ${Window[TradeSkillWnd].Child[COMBW_ExperimentButton].LeftMouseUp}
					/delay 2s ${Window[ContainerWindow]}==TRUE
				}
				/if (${Window[ContainerWindow]}) {
					/echo waiting 4 seconds before we start dropping stuff into forge...
					/delay 4s
					/for comb 1 to 6
						/echo [${comb}] Trying to pick up 1 Burled Wood 
						/ctrl /itemnotify "Burled Wood" leftmouseup
						/delay 5s ${Cursor.ID}==85459
						/delay 1s
						/if (${Cursor.ID}!=85459) {
							/beep
							/echo pickup failed, please pick it up manually
							/mqp
						}
						/itemnotify enviro${comb} leftmouseup
						/delay 5s !${Cursor.ID}
						/delay 5
						/if (${Cursor.ID}) {
							/beep
							/echo drop in forge failed, please drop it in there manually
							/mqp
						}
					/next comb
					/for comb 7 to 8
						/echo [${comb}] Trying to pick up 1 Tin Ore 
						/ctrl /itemnotify "Tin Ore" leftmouseup
						/delay 5s ${Cursor.ID}==85460
						/delay 1s
						/if (${Cursor.ID}!=85460) {
							/beep
							/echo pickup failed, please pick it up manually
							/mqp
						}
						/itemnotify enviro${comb} leftmouseup
						/delay 5s !${Cursor.ID}
						/delay 5
						/if (${Cursor.ID}) {
							/beep
							/echo drop in forge failed, please drop it in there manually
							/mqp
						}
					/next comb
					/echo [${comb}] Trying to pick up 1 Faceted Crystal
					/itemnotify "Faceted Crystal" leftmouseup
					/delay 5s ${Cursor.ID}==85461
					/delay 1s
					/if (${Cursor.ID}!=85461) {
						/beep
						/echo pickup failed, please pick it up manually
						/mqp
					}
					/itemnotify enviro9 leftmouseup
					/delay 5s !${Cursor.ID}
					/delay 5
					/if (${Cursor.ID}) {
						/beep
						/echo drop in forge failed, please drop it in there manually
						/mqp
					}
					/itemnotify "Crystal Harvester Mold" leftmouseup
					/delay 5s ${Cursor.ID}==85462
					/delay 1s
					/if (${Cursor.ID}!=85462) {
						/beep
						/echo pickup failed, please pick it up manually
						/mqp
					}
					/itemnotify enviro10 leftmouseup
					/delay 5s !${Cursor.ID}
					/delay 1s
					/if (${Cursor.ID}) {
						/beep
						/echo drop in forge failed, please drop it in there manually
						/mqp
					}
					/combine ContainerWindow
					/delay 5s ${Cursor.ID}==85464
					/delay 1s
					/if (${Cursor.ID}!=85464) {
						/beep
						/echo combine failed, please do it manually
						/mqp
					}
					/windowstate ContainerWindow close
				}
				/if (${FindItemCount[=Crystal Harvester]}==0) {
					/beep
					/delay 5s
					/echo [${Time}] waiting for you to create the Crystal Harvester
					/goto :waitforharvester
				}
				/echo we got it! time to move on.
				/autoinv
				/delay 1s
			}
		}
	} else /if (${Task[0].Step.Instruction.Find[Attempt to till the rocky soil]}==1 && ${Me.XTarget}==0) {
		/if (${bForgeOnce}==1) {
			/declare shortest int local 0
			/declare sn int local 0
			/declare distold int local 100000
			/declare tempsorter[5] int local
			/declare sorter[5] int local
			/varset sorter[1] ${Math.Distance[${Me.Y},${Me.X}:-1105,-12969]}
			/varset sorter[2] ${Math.Distance[${Me.Y},${Me.X}:-1704,-8707]}
			/varset sorter[3] ${Math.Distance[${Me.Y},${Me.X}:-2083,-5541]}
			/varset sorter[4] ${Math.Distance[${Me.Y},${Me.X}:-2340,-4250]}
			/for sn 1 to 4
				/if (${sorter[${sn}]} < ${distold}) {
					|/echo ${sorter[${sn}]} < ${distold}
					/varset distold ${sorter[${sn}]}
					/varset bForgeOnce ${sn}
				}
			/next sn
			/echo we need to go to waypoint ${bForgeOnce}
		}
		|/mqp on
		/if (${bForgeOnce}==1) {
			/echo need to get away from that stupid tarp we get stuck in
			/varset bForgeOnce 2
			/nav locyxz -1105 -12969 73
			/delay 2s ${Navigation.Active}==TRUE
			/delay 10s ${Navigation.Active}==FALSE
			/bcaa //chase on
			/bcaa //nav id ${Me.ID}
			/delay 2s
			/echo at waypoint 1
			/beep
			/return
		}
		/if (${bForgeOnce}==2) {
			/echo going to waypoint 2
			/call WaitForNavToFinish -1704 -8707 0 400
			/if (${Macro.Return}==1) {
				/echo at waypoint 2
				/beep
				/varset bForgeOnce 3
				/return
			}
			/return
		}
		/if (${bForgeOnce}==3) {
			/echo going to waypoint 3
			/call WaitForNavToFinish -2083 -5541 0 400
			/if (${Macro.Return}==1) {
				/echo at waypoint 3
				/beep
				/varset bForgeOnce 4
				/return
			}
			/return
		}
		/echo doing ${Task[0].Step.Instruction}
		/call WaitForNavToFinish -2340 -4250 0 400
		/if (${Macro.Return}==1) {
			/tar id ${Spawn[untilled].ID}
			/delay 1s
			/useitem "Crystal Harvester"
			/delay 5s
			/echo we have arrived at ${Target} get the shimmering hay from it.
		}
	} else /if (${Task[0].Step.Instruction.Find[Return to Cleet to discuss]}==1 && ${Me.XTarget}==0) {
		/echo doing ${Task[0].Step.Instruction}
		/call WaitForNavToFinish -2261 -4176 0 400
		/if (${Macro.Return}==1) {
			/tar npc cleet
			/keypress h
		}
	} else /if (${Task[0].Step.Instruction.Find[Question Chief Goonda]}==1 && ${Me.XTarget}==0) {
		/echo doing ${Task[0].Step.Instruction}
		/call WaitForNavToFinish -595 -9148 48 400
		/if (${Macro.Return}==1) {
			/tar npc goond
			/keypress h
			/echo we have arrived at ${Target} unpause when done
		}
	} else /if (${FindItemCount[85463]}==0 && ${Task[0].Step.Instruction.Find[Bring an immaculate]}==1 && ${Me.XTarget}==0) {
		/echo time to ${Task[0].Step.Instruction}
		/declare liondist int local 0
		/declare wolfdist int local 0
		/declare beardist int local 0
		/bcaa //chase on
		/varset liondist ${Spawn[npc lion].Distance3D}
		/varset wolfdist ${Spawn[npc wolf].Distance3D}
		/varset beardist ${Spawn[npc bear].Distance3D}
		/if (${liondist}!=0 && ${wolfdist}!=0 && ${beardist}!=0 && ${liondist} < ${wolfdist} && ${liondist} < ${beardist}) {
			/tar npc lion
		} else /if (${liondist}!=0 && ${wolfdist}!=0 && ${beardist}!=0 && ${wolfdist} < ${liondist} && ${wolfdist} < ${beardist}) {
			/tar npc wolf
		} else  /if (${liondist}!=0 && ${wolfdist}!=0 && ${beardist}!=0 && ${beardist} < ${liondist} && ${beardist} < ${wolfdist}) {
			/tar npc bear
		} else {
			|whatever, im not gonna spend time on checking every single scenario
			/tar npc lion
		}
		/delay 1s ${Target.ID}
		/echo ${Target} aquired navigating to ${Target.Y} ${Target.X} ${Target.Z}
		/call WaitForNavToFinish ${Target.Y} ${Target.X} ${Target.Z} 400
		/echo we arrived lets attack it
		/bcaa //Stick 5
		/bcaa //attack on
	} else /if (${FindItemCount[85463]}>=1 && ${Task[0].Step.Instruction.Find[Bring an immaculate]}==1 && ${Me.XTarget}==0) {
		/echo time to ${Task[0].Step.Instruction}
		/call WaitForNavToFinish -582 -8853 108 400
		/if (${Macro.Return}==1) {
			/bcg //camphere on
			:checkpet
			/if (${Pet.ID} && ${Pet.Stance.NotEqual[GUARD]}) {
				/echo its important that our pet stays put otherwise it will attack the spirit outside of camp and we dont want that.
				/pet guard
				/delay 3s ${Pet.Stance.Equal[GUARD]}
				/pet ghold on
				/delay 1s
				/beep
				/goto :checkpet
			}
			/halfmoon 10
			/tar npc goond
			/delay 1s
			/echo time to go down and give goonda the pelt then come back with the spirit so we can fight up here
			/nav id ${Target.ID}
			/delay 2s ${Navigation.Active}==TRUE
			/delay 20s ${Navigation.Active}==FALSE
			|/keypress h
			:waitforgivepelt
			/if (${Cursor.ID} && ${Cursor.ID}!=85463) {
				/autoinv
				/delay 1s ${Cursor.ID}==FALSE
			}
			/if (!${Cursor.ID} && ${Window[GiveWnd].Open}==FALSE) {
				/itemnotify #85463 leftmouseup
				/delay 2s ${Cursor.ID}
			}
			/if (${Window[GiveWnd].Open}==FALSE && ${Cursor.ID}==85463) {
				/click left target
				/delay 2s ${Window[GiveWnd].Open}==TRUE
				/beep
			}
			/if (${Window[GiveWnd].Open}) {
				/if (${Window[InventoryWindow].Open}) /windowstate InventoryWindow close
				/echo [${Time}] Give the pelt to Goonda
				/notify GiveWnd GVW_Give_Button leftmouseup
				/delay 3s
				/beep
				/goto :waitforgivepelt
			}
			/bcg //mqp on
			/echo we gave the pelt now lets pull the spirit up to the guys
			/delay 5s ${Task[0].Step.Instruction.Find[Prove your worth]}==1
			/delay 5s ${Me.XTarget} > 0
			/bcaa //nav locyxz -582 -8853 108
			/delay 2s ${Navigation.Active}==TRUE
			/delay 10s ${Navigation.Active}==FALSE
			/beep
			/echo what happens now?
			/echo we should be back at camp and spirit should be comming for us...
			:waitforspirit
			/if (${Spawn[npc ancient].Distance} > 50) {
				/delay 1s
				/echo still waiting for spirit to get here ${Spawn[npc ancient].Distance}
				/goto :waitforspirit
			}
			/if (${Pet.ID} && ${Pet.Stance.NotEqual[FOLLOW]}) {
				/pet follow
				/delay 3s ${Pet.Stance.Equal[FOLLOW]}
				/pet ghold off
				/delay 5
			}
			/bcaa //mqp off
			/tar npc ancient
			|/stick 5
			/attack on
		}
	} else /if (${Task[0].Step.Instruction.Find[Prove your worth]}==1 && ${Me.XTarget}==0) {
		/echo time to ${Task[0].Step.Instruction}
		/delay 1
	} else /if (${Task[0].Step.Instruction.Find[Give the Crystal Harvester]}==1 && ${Me.XTarget}==0) {
		/echo time to ${Task[0].Step.Instruction}
		/target clear
		/chase on
		/bcaa //switchnow
		/echo waiting for An Ancient Spirit to go back to his spot.
		/delay 3s
		/tar npc spirit
		/delay 1s ${Target.ID}
		/delay 60s ${Spawn[npc loc -9137 -689 55 radius 10].ID}==${Target.ID}
		/nav locyxz -595 -9148 48
		/delay 2s ${Navigation.Active}==TRUE
		/delay 20s ${Navigation.Active}==FALSE
		/nav id ${Spawn[npc ancient].ID}
		/delay 2s ${Navigation.Active}==TRUE
		/delay 10s ${Navigation.Active}==FALSE
		/echo now go down and give the spirit the harvester
		/itemnotify "Crystal Harvester" leftmouseup
		/if (!${Target.ID}) {
			/tar npc spirit
		}
		/delay 2s ${Cursor.ID}
		/stick 5
		/delay 5s ${Target.Distance} < 20
		/click left target
		/beep
		:waitforspirittogetharv
		/if (${Window[GiveWnd].Open} && ${Window[GiveWnd].Child[GVW_MyItemSlot0].Tooltip.Equal[Crystal Harvester]}) {
			/notify GiveWnd GVW_Give_Button leftmouseup
			/delay 1s
		}
		/beep
		/if (${Window[InventoryWindow].Open}) /windowstate InventoryWindow close
		/if (${FindItemCount[=Enchanted Crystal Harvester]}==0) {
			/if (${Target.CleanName.Find[an ancient spirit]}==1) {
				/if (${Target.Distance} > 20) {
					/nav id  ${Target.ID}
					/delay 2s ${Navigation.Active}==TRUE
					/delay 10s ${Navigation.Active}==FALSE
				}
				/if (${Target.Distance} < 20 && ${Cursor.ID}==85464) {
					/click left target
				}
				/echo [${Time}] give the Crystal Harvester to the ancient spirit
				/delay 3s
			} else {
				/tar npc ancient
				/delay 1s ${Target.ID}
			}			
			/goto :waitforspirittogetharv
		}
		/autoinv
		/delay 1s
		/nav locyxz -609 -9191 49
		/delay 2s ${Navigation.Active}==TRUE
		/delay 20s ${Navigation.Active}==FALSE
		/nav locyxz -582 -8853 108
		/delay 2s ${Navigation.Active}==TRUE
		/delay 20s ${Navigation.Active}==FALSE
		/echo ok we got it, time to move on
	} else /if (${Task[0].Step.Instruction.Find[Till the rocky soil]}==1 && ${Me.XTarget}==0) {
		/target clear
		/if (${Pet.ID} && ${Pet.Stance.NotEqual[FOLLOW]}) {
			/pet follow
			/delay 1s ${Pet.Stance.Equal[FOLLOW]}
		}
		/echo time to ${Task[0].Step.Instruction}
		/call WaitForNavToFinish -2340 -4250 0 400
		/if (${Macro.Return}==1) {
			/tar id ${Spawn[untilled].ID}
			/delay 1s ${Target.ID}
			/echo we have arrived at ${Target} now get the shimmering hay from it
			/useitem "Enchanted Crystal Harvester"
			/delay 2s
		}
		/if (${AdvLoot.SList[1].Name.Equal[Shimmering Hay]}) {
			/advloot shared "Shimmering Hay" ag
			/delay 1s
			/advloot shared "Shimmering Hay" giveto ${Me}
			/delay 1s
		}
	} else /if (${Task[0].Step.Instruction.Find[Tell Cleet Miller of your success]}==1 && ${Me.XTarget}==0) {
		/echo time to ${Task[0].Step.Instruction}
		/call WaitForNavToFinish -2261 -4176 0 400
		/if (${Macro.Return}==1) {
			/tar npc cleet
			/keypress h
			/echo we have arrived completed all steps now go out and look for the bigger belt and wee'er harvester
			/mqp on
		}
	}
/return
Sub KnowledgeFindMobToPull
	/echo [${Time}] Looking for mobs within 200 feet of us to pull...
	/delay 1s
	/declare PullMobID int local
	/declare i int local
	/declare j int local
	/declare localMobCount int local
	/declare localMobName string local
	/varset localMobCount ${SpawnCount[npc radius 200 targetable]}
	/if (${localMobCount}) {
		/for i 1 to ${localMobCount}
			/varset PullMobID ${NearestSpawn[${i},npc radius 200 targetable].ID}
			/if (${PullMobID}) {
				/varset localMobName ${Spawn[${PullMobID}].DisplayName}
				/if (${localMobName.Equal[a righteous knight]}) {
					/continue
				}
				/if (${DefendingKnowledgeMobList.Find[${localMobName}]}) {
					/echo Found ${localMobName} to pull 
					/return ${PullMobID}
				}
				|/for j 1 to 26
					|/if (${localMobName.Find[${DefendingKnowledgeMobList.Arg[${j},,]}]}) {
					|	/echo Found ${localMobName} to pull 
					|	/return ${PullMobID}
					|}
				|/next j
			}
		/next i
	}
/return 0

Sub InitMoblist
	/varset DefendingKnowledgeMobList "Chargy the Charger,Diaku Elite Conqueror,Grollikthania,Kerkinic the Enforcer,The Faceless Soulflayer,a burning spirit,a cackling pyromaniac,a corpse caller,a corpse squatter,a corrosive ooze,a disease spreader,a doomfire marcher,a dripping plaguebringer,a fiery golem,a grime scraper,a limb remover,a small snapper,a snapping tormentor,a toxic nibbler,a vile digester,a war wraith,a wild subjugator,a zek initiate,an armed merchant,an earthcrafted striker"
/return
Sub DoHorn
	/if (${Defined[bCustomInitdone]}==FALSE) {
		/call InitCustom
		/call InitMoblist
		|/echo ${DefendingKnowledgeMobList}
		|/end
	}
	/if (${Window[TaskWnd].Open}==FALSE) {
		/beep
		/echo this macro requires that the TaskWnd is open but you CAN minimize t if you like
		/windowstate TaskWnd open
		/delay 2s ${Window[TaskWnd].Open}==TRUE
		/invoke ${Window[TaskWnd].Child[TASK_TaskList].Select[Defending Knowledge]}
		/delay 5
	}
	/if (${Task.Title.NotEqual[Defending Knowledge]}) {
		/echo this macro requires that the Task Defending Knowledge is active and selected in task window
		/end
	}
	/if (${Task.Leader.NotEqual[${Me}]}) {
		/return
	}
	/if (${Group.AnyoneMissing}==TRUE) {
		/echo groupmember gone awol need to wait for it
		/delay 1s
		/return
	}
	/if (${Task[0].Step.Instruction.Find[Speak with Bjerg Sen the Tranquil]}==1 && ${Me.XTarget}==0) {
		/bcga //chase on
		/echo doing ${Task[0].Step.Instruction}
		/call WaitForNavToFinish ${Spawn[npc Bjerg].Y} ${Spawn[npc Bjerg].X} ${Spawn[npc Bjerg].Z} 80
		/if (${Macro.Return}==1) {
			/tar id ${Spawn[npc Bjerg].ID}
			/echo now hail Bjerg
			/keypress h
			/say Plane of Knowledge
		}
	} else /if (${Task[0].Step.Instruction.Find[(Optional) Receive]}==1 && ${Me.XTarget}==0) {
		/echo doing ${Task[0].Step.Instruction}
		/call WaitForNavToFinish 808 -1121 -817 80
		/if (${Macro.Return}==1) {
			/tar id ${Spawn[npc Varlman].ID}
			/echo now hail Varlman
			/keypress h
			/say receive
		}
	} else /if (${Task[0].Step.Instruction.Find[(Optional) Prevent]}==1 && ${Me.XTarget}==0) {
		/if (${Task[0].Objective[5].Instruction.Find[? ? ?]}==1) {
			/echo doing ${Task[0].Objective[4].Instruction}
			/call WaitForNavToFinish 711 -1310 -876 80
			/if (${Macro.Return}==1) {
				/face heading 90
				/bcga //camphere on
				/delay 2s
				/halfmoon 10
				/delay 2s
				/call BlowHorn
			}
		} else /if (${Task[0].Objective[5].Status.Equal[Done]}) {
			/if (${Task[0].Objective[6].Status.NotEqual[Done]}) {
				/echo doing ${Task[0].Objective[6].Instruction}
				/call BlowHorn
			}
		}
		/if (${Task[0].Objective[7].Status.Equal[Done]}) {
			/if (${Task[0].Objective[8].Status.NotEqual[Done]}) {
				/echo doing ${Task[0].Objective[8].Instruction}
				/call BlowHorn
			}
		}
		/if (${Task[0].Objective[9].Status.Equal[Done]}) {
			/if (${Task[0].Objective[10].Status.NotEqual[Done]}) {
				/echo doing ${Task[0].Objective[10].Instruction}
				/call BlowHorn
			}
		}
		/if (${Task[0].Objective[11].Status.Equal[Done]}) {
			/if (${Task[0].Objective[12].Status.NotEqual[Done]}) {
				/echo doing ${Task[0].Objective[12].Instruction}
				/call BlowHorn
			}
		}
	} else /if (${Task[0].Step.Instruction.Find[(Optional) Speak]}==1 && ${Me.XTarget}==0) {
		/delay 30s ${SpawnCount[npc varlman loc -1118 822 radius 50]}==1
		/nav id ${Spawn[npc varlman].ID}
		/delay 2s ${Navigation.Active}==TRUE
		/delay 20s ${Navigation.Active}==FALSE
		/tar id ${Spawn[npc varlman].ID}
		/delay 2s ${Target.ID}==${Spawn[npc varlman].ID}
		/delay 1s
		/keypress h
		/delay 1s
	} else /if (${Task[0].Objective[15].Status.Equal[Done]}) {
		/if (${SpawnCount[a tranquil]}==1) {
			/bcg //mqp on
			/delay 2s
			/tar a tranquil
			/delay 1s
			/nav target
			/delay 2s ${Navigation.Active}==TRUE
			/delay 20s ${Navigation.Active}==FALSE
			/beep
			/echo u are in front of the chest now, type /open to open it and give the horn to whoever...
			/mqp on
		}
	}
	/if (${Me.XTarget} && !${Me.Combat}) {
		/echo not in combat need to be...
		/call GetClosestXTargetMob
		/if (${Macro.Return}!=0) {
			/tar id ${Macro.Return}
			/delay 1s ${Target.ID}==${Macro.Return}
			/nav target
			/delay 2s ${Navigation.Active}==TRUE
			/delay 20s ${Navigation.Active}==FALSE
			/attack on
		}
	}
	/if (${Me.Level} == 110 && !${Me.XTarget} && !${Me.Combat} && ${Bool[${Task[0].Objective[2].Status.Equal[Done]}]}==TRUE) {
		|we can fight all mobs at once...
		/if (${Task[0].Objective[5].Status.NotEqual[0/12]}==TRUE && ${Task[0].Objective[6].Status.Equal[0/1]}) {
			/echo step 6 pulling more mobs we are 110 we can take them... doing ${Task[0].Objective[6].Instruction}
			/call BlowHorn
		} else /if (${Task[0].Objective[7].Status.NotEqual[0/4]}==TRUE && ${Task[0].Objective[8].Status.Equal[0/1]}) {
			/echo step 8 pulling more mobs we are 110 we can take them... doing ${Task[0].Objective[8].Instruction}
			/call BlowHorn
		} else /if (${Task[0].Objective[9].Status.NotEqual[0/8]}==TRUE && ${Task[0].Objective[10].Status.Equal[0/1]}) {
			/echo step 10 pulling more mobs we are 110 we can take them... doing ${Task[0].Objective[10].Instruction}
			/call BlowHorn
		} else /if (${Task[0].Objective[11].Status.NotEqual[0/8]}==TRUE && ${Task[0].Objective[12].Status.Equal[0/1]}) {
			/echo step 12 pulling more mobs we are 110 we can take them... doing ${Task[0].Objective[12].Instruction}
			/call BlowHorn
		}
	}
	/if (${Bool[${Task[0].Objective[4].Status.Equal[Done]}]}==TRUE && ${Bool[${Task[0].Objective[13].Status.Equal[Done]}]}==FALSE && !${Me.XTarget} && !${Me.Combat}) {
		/call KnowledgeFindMobToPull
		/if (${Macro.Return}) {
			/tar id ${Macro.Return}
			/delay 1s ${Target.ID}==${Macro.Return}
			/nav target
			/delay 2s ${Navigation.Active}==TRUE
			/delay 20s ${Navigation.Active}==FALSE
			/attack on
			/delay 1s
		}
	}
/return

Sub GetClosestXTargetMob
	/declare olddist int local 100000
	/declare lastid int local 0
	/declare i int local
	/for i 1 to 13
            /if (${Me.XTarget[${i}].ID} && ${Me.XTarget[${i}].TargetType.Equal[Auto Hater]} && ${Me.XTarget[${i}].Type.Equal[NPC]} && ${Me.XTarget[${i}].Distance3D} < ${olddist}) {
                /varset olddist ${Me.XTarget[${i}].Distance3D}
		/varset lastid ${Me.XTarget[${i}].ID}
            }
       /next i
/return ${lastid}

Sub BlowHorn
	/nav locyxz 683 -1182 -850
	/delay 2s ${Navigation.Active}==TRUE
	/delay 20s ${Navigation.Active}==FALSE
	/doortarget
	/delay 1s
	/click left door
	/delay 5
	/nav locyxz 711 -1310 -876
	/delay 2s ${Navigation.Active}==TRUE
	/delay 20s ${Navigation.Active}==FALSE
/return

Sub GetUsTheClosestHobbyMob
	/declare i int local
	/declare nearestmobdist float local 10000.0
	/declare currdist float local
	/declare nearestmobID int local 0
	/declare mobarray[200] int local
	/declare mobtokillfound int local 0
	/declare mobtokill string local
	/if (${mobtokillfound}==0 && ${Task[This Ain't Right].Objective[Kill Tiny Elephants.].Status.NotEqual[Done]}) {
		/echo we should Kill Tiny Elephants
		/varset mobtokill "Tiny Elephant"
		/varset mobtokillfound 1
	}
	/if (${mobtokillfound}==0 && ${Task[This Ain't Right].Objective[Kill Cannibalistic Gingerbread Men.].Status.NotEqual[Done]}) {
		/echo we should Kill Cannibalistic Gingerbread Men
		/varset mobtokill "Cannibalistic"
		/varset mobtokillfound 1
	}
	/if (${mobtokillfound}==0 && ${Task[This Ain't Right].Objective[Kill Grugglemumps.].Status.NotEqual[Done]}) {
		/echo we should Kill Grugglemumps
		/varset mobtokill "Grugglemump"
		/varset mobtokillfound 1
	}
	/if (${mobtokillfound}==0 && ${Task[This Ain't Right].Objective[Kill Edwin, the Gingerbread Man.].Status.NotEqual[Done]}) {
		/echo we should Kill Edwin, the Gingerbread Man.
		/varset mobtokill "Destroyer"
		/varset mobtokillfound 1
	}
	/if (${mobtokillfound}==0 && ${Task[This Ain't Right].Objective[Kill the World's Tiniest Giant.].Status.NotEqual[Done]}) {
		/echo we should Kill the World's Tiniest Giant
		/varset mobtokill "Tiniest Giant"
		/varset mobtokillfound 1
	}

	/echo mobtokill = ${mobtokill}
	/for i 1 to ${SpawnCount[npc ${mobtokill}]}
		/varset mobarray[${i}] ${NearestSpawn[${i},npc ${mobtokill}].ID}
	/next i
	/for i 1 to 200
		/if (${Spawn[${mobarray[${i}]}].ID}) {
			/if (${Navigation.PathExists[id ${mobarray[${i}]}]}) {
				|/echo ${Spawn[${mobarray[${i}]}].Name} ${Spawn[${mobarray[${i}]}].X}
				/varset currdist ${Navigation.PathLength[id ${mobarray[${i}]}]}
				|/echo ${mobarray[${i}]} ${Spawn[${mobarray[${i}]}].Name} ${Spawn[${mobarray[${i}]}].Race} ${Navigation.PathLength[id ${mobarray[${i}]}]}
				/if (${currdist} < ${nearestmobdist}) {
					/varset nearestmobdist ${currdist}
					/varset nearestmobID ${mobarray[${i}]}
				}
			}
		}
	/next i
	/tar id ${nearestmobID}
	/echo nearest mob is ${nearestmobID}
/return ${nearestmobID}

Sub DoHobby
	/if (${Defined[bCustomInitdone]}==FALSE) {
		/echo doing hobby
		/call InitCustom
	}
	/if (${Group.MasterLooter.ID}!=${Me.ID}) {
		/echo I HAVE to be the masterlooter...
		/grouproles set ${Me} 5
		/beep
		/delay 1s
	}
	/if (${Window[TaskWnd].Open}==FALSE) {
		/beep
		/echo this macro requires that the TaskWnd is open but you CAN minimize t if you like
		/windowstate TaskWnd open
		/delay 2s ${Window[TaskWnd].Open}==TRUE
	}
	/if (${Window[TaskWnd].Child[TASK_TaskList].GetCurSel}!=1) {
		/invoke ${Window[TaskWnd].Child[TASK_TaskList].Select[This Ain't Right]}
		/delay 5
	}
	/if (${Task.Title.Find[This Ain't Right]}!=1) {
		/echo this macro requires that the Task This Ain't Right is active
		/end
	}
	/if (${Task.Leader.NotEqual[${Me}]}) {
		/echo i have to be the task leader...
		/delay 1s
		/return
	}
	/if (${Task[This Ain't Right].Step.Instruction.Equal[Hail Bobo Gleemaker.]}) {
		/echo Hail Bobo Gleemaker.
		/nav spawn id ${Spawn[npc Gleemaker].ID} | dist=19
		/delay 2s ${Navigation.Active}==TRUE
		/delay 30s ${Navigation.Active}==FALSE
		/target id ${Spawn[npc Gleemaker].ID}
		/delay 2s ${Target.ID}==${Spawn[npc Gleemaker].ID}
		/keypress hail
		/delay 4s ${Task[This Ain't Right].Step.Instruction.Equal[Hail Bobo Gleemaker.]}==FALSE
		/return
	}
	/if (${Task[This Ain't Right].Objective[10].Instruction.Equal[? ? ?]} && ${Task[This Ain't Right].Objective[1].Status.Equal[Done]}) {
		/call GetHostilesOnXTarget
		/if (${Macro.Return} == 0) {
			/echo doing ${Task[This Ain't Right].Step.Instruction}
			/call GroupContainsPCs
			/if (${Macro.Return}==1) {
				/bcga //chase on
			} else {
				/chase on
			}
			/declare localmob int local
			/call GetUsTheClosestHobbyMob
			/varset localmob ${Macro.Return}
			/if (${localmob}) {
				/echo Lets go kill ${Spawn[${localmob}]}
				/if (${Me.Gem[${Spell[${PullWith}]}]}!=0) {
					/echo we have ${PullWith} memed
					/call WaitForNavToFinish2 ${Spawn[${localmob}].ID} 100
					/if (${Macro.Return}==1) {
						/if (${Target.ID}!=${Spawn[${Macro.Return}].ID}) {
							/target id ${Spawn[${Macro.Return}].ID}
							/delay 2s ${Target.ID}==${Spawn[${Macro.Return}].ID}
						}
						/cast "${PullWith}"
						/call WaitCast ${Spell[${PullWith}].MyCastTime}
					}
				} else {
					|we move all the way to the mob
					/call WaitForNavToFinish ${Spawn[${Macro.Return}].Y} ${Spawn[${Macro.Return}].X} ${Spawn[${Macro.Return}].Z} 100
				}
			}
		}
	}
	/if (${Task[This Ain't Right].Step.Instruction.Equal[Give the Tiny Elephant Trunk to Bobo Gleemaker.]}) {
		/call GroupContainsPCs
		/if (${Macro.Return}==1) {
			/bcga //chase on
		} else {
			/chase on
		}
		/echo Give Tiny Elephant Trunk to Bobo Gleemaker.
		/nav spawn id ${Spawn[npc Gleemaker].ID} | dist=19
		/delay 2s ${Navigation.Active}==TRUE
		/delay 30s ${Navigation.Active}==FALSE
		/target id ${Spawn[npc Gleemaker].ID}
		/delay 2s ${Target.ID}==${Spawn[npc Gleemaker].ID}
		/call TradeSomething "Tiny Elephant Trunk"
		/delay 4s ${Task[This Ain't Right].Step.Instruction.Equal[Give the Tiny Elephant Trunk to Bobo Gleemaker.]}==FALSE
		/return
	}
	/if (${Task[This Ain't Right].Step.Instruction.Equal[Give the Gingerbread Man Spleen to Bobo Gleemaker.]}) {
		/call GroupContainsPCs
		/if (${Macro.Return}==1) {
			/bcga //chase on
		} else {
			/chase on
		}
		/echo Give the Gingerbread Man Spleen to Bobo Gleemaker.
		/nav spawn id ${Spawn[npc Gleemaker].ID} | dist=19
		/delay 2s ${Navigation.Active}==TRUE
		/delay 30s ${Navigation.Active}==FALSE
		/target id ${Spawn[npc Gleemaker].ID}
		/delay 2s ${Target.ID}==${Spawn[npc Gleemaker].ID}
		/call TradeSomething "Gingerbread Man Spleen"
		/delay 4s ${Task[This Ain't Right].Step.Instruction.Equal[Give the Gingerbread Man Spleen to Bobo Gleemaker.]}==FALSE
		/return
	}	
	/if (${Task[This Ain't Right].Step.Instruction.Equal[Give the Grugglemump Hide to Bobo Gleemaker.]}) {
		/call GroupContainsPCs
		/if (${Macro.Return}==1) {
			/bcga //chase on
		} else {
			/chase on
		}
		/echo Give the Grugglemump Hide to Bobo Gleemaker.
		/nav spawn id ${Spawn[npc Gleemaker].ID} | dist=19
		/delay 2s ${Navigation.Active}==TRUE
		/delay 30s ${Navigation.Active}==FALSE
		/target id ${Spawn[npc Gleemaker].ID}
		/delay 2s ${Target.ID}==${Spawn[npc Gleemaker].ID}
		|yes it has the wrong name...
		/call TradeSomething "Grugglegump Hide"
		/delay 4s ${Task[This Ain't Right].Step.Instruction.Equal[Give the Grugglemump Hide to Bobo Gleemaker.]}==FALSE
		/return
	}
	/if (${Task[This Ain't Right].Step.Instruction.Equal[Speak with Bobo Gleemaker.]}) {
		/echo Speak with Bobo Gleemaker.
		/nav spawn id ${Spawn[npc Gleemaker].ID} | dist=19
		/delay 2s ${Navigation.Active}==TRUE
		/delay 30s ${Navigation.Active}==FALSE
		/target id ${Spawn[npc Gleemaker].ID}
		/delay 2s ${Target.ID}==${Spawn[npc Gleemaker].ID}
		/keypress hail
		/delay 4s ${Task[This Ain't Right].Step.Instruction.Equal[Speak with Bobo Gleemaker.]}==FALSE
		/return
	}
	/if (${Task[This Ain't Right].Step.Instruction.Equal[Answer the Riddle Master's riddle.]}) {
		/echo Answer the Riddle Master's riddle.
		/nav spawn id ${Spawn[npc Riddle].ID} | dist=19
		/delay 2s ${Navigation.Active}==TRUE
		/delay 30s ${Navigation.Active}==FALSE
		/target id ${Spawn[npc Riddle].ID}
		/delay 2s ${Target.ID}==${Spawn[npc Riddle].ID}
		/say bee
		/delay 4s ${Task[This Ain't Right].Step.Instruction.Equal[Answer the Riddle Master's riddle.]}==FALSE
		/return
	}
	/if (${Task[This Ain't Right].Step.Instruction.Equal[Speak with Bristlebane.]}) {
		/echo Speak with Bristlebane.
		/nav spawn id ${Spawn[npc Bristlebane].ID} | dist=19
		/delay 2s ${Navigation.Active}==TRUE
		/delay 30s ${Navigation.Active}==FALSE
		/target id ${Spawn[npc Bristlebane].ID}
		/delay 2s ${Target.ID}==${Spawn[npc Bristlebane].ID}
		/keypress hail
		/delay 4s ${Task[This Ain't Right].Step.Instruction.Equal[Speak with Bristlebane.]}==FALSE
		/return
	}
	/if (${Task[This Ain't Right].Step.Instruction.Equal[Loot the Ornate Chest.]}) {
		/beep
		/echo time to loot the chest congrats...
		/echo type /open and when you have looted the hobby horse unpause macro with /mqp
		/target ornate
		/mqp
	}
	/if (${Task[This Ain't Right].Step.Instruction.Equal[Talk to Bobo again.]}) {
		/echo Talk to Bobo again.
		/nav spawn id ${Spawn[npc Gleemaker].ID} | dist=19
		/delay 2s ${Navigation.Active}==TRUE
		/delay 30s ${Navigation.Active}==FALSE
		/target id ${Spawn[npc Gleemaker].ID}
		/delay 2s ${Target.ID}==${Spawn[npc Gleemaker].ID}
		/keypress hail
		/delay 4s ${Task[This Ain't Right].Step.Instruction.Equal[Talk to Bobo again.]}==FALSE
		/end
	}
	/delay 1
/return

Sub DarknessFindMobToPull(string Mobname)
	/echo [${Time}] Looking for ${Mobname} to kill.
	/delay 1s
	/declare PullMobID int local
	/declare i int local
	/declare j int local
	/declare localMobCount int local
	/declare localMobName string local
	/varset localMobCount ${SpawnCount[npc ${Mobname} targetable]}
	/if (${localMobCount}) {
		/for i 1 to ${localMobCount}
			/varset PullMobID ${NearestSpawn[${i},npc ${Mobname} targetable].ID}
			/if (${PullMobID}) {
				/if (${Navigation.PathExists[id ${PullMobID}]}) {
					/varset localMobName ${Spawn[${PullMobID}].DisplayName}
					/echo Found ${localMobName} to pull 
					/return ${PullMobID}
				}
			}
		/next i
	}
/return 0

Sub DoDarknessHowls
	/if (${Defined[bCustomInitdone]}==FALSE) {
		/echo doing The Darkness Howls
		/call InitCustom
	}
	/if (${Group.MasterLooter.ID}!=${Me.ID}) {
		/echo I HAVE to be the masterlooter...
		/grouproles set ${Me} 5
		/beep
		/delay 1s
	}
	/if (${Window[TaskWnd].Open}==FALSE) {
		/beep
		/echo this macro requires that the TaskWnd is open but you CAN minimize t if you like
		/windowstate TaskWnd open
		/delay 2s ${Window[TaskWnd].Open}==TRUE
	}
	/if (${Window[TaskWnd].Child[TASK_TaskList].GetCurSel}!=1) {
		/invoke ${Window[TaskWnd].Child[TASK_TaskList].Select[The Darkness Howls]}
		/delay 5
	}
	/if (${Task.Title.Find[The Darkness Howls]}!=1) {
		/echo this macro requires that the Task The Darkness Howls is active
		/end
	}
	/if (${Task.Leader.NotEqual[${Me}]}) {
		/echo i have to be the task leader...
		/delay 1s
		/return
	}
	/if (${Task[The Darkness Howls].Step.Instruction.Equal[Drive the raiders from the front gate.]}) {
			/if (${firstpartdone}==0) {
				/bcga //chase on
				/bcga //dismount
				/if (${SpawnCount[id ${Me.ID} loc 280 89 2 radius 20]}==0) {
					/call WaitForNavToFinish 89 280 2 200
				} else {
					/echo setting firstpartdone to 1 in ${Task[The Darkness Howls].Step.Instruction}
					/varset firstpartdone 1
				}
			}
		|}
	}
	/if (${Task[The Darkness Howls].Step.Instruction.Equal[Drive the raiders from the front gate.]} && ${firstpartdone}==1) {
		/call GetHostilesOnXTarget
		/if (${Macro.Return} == 0) {
			/declare tempmobID int local
			/echo doing ${Task[The Darkness Howls].Step.Instruction}
			/bcga //chase on
			/bcga //dismount
			/call DarknessFindMobToPull raider
			/varset tempmobID ${Macro.Return}
			/if (${tempmobID}) {
				/echo We found a valid mob to kill: ${Spawn[${tempmobID}]}
				/if (${Me.Gem[${Spell[${PullWith}]}]}!=0) {
					/call WaitForNavToFinish2 ${Spawn[${tempmobID}].ID} 100
					/if (${Macro.Return}==1) {
						/echo according to WaitForNavToFinish2 we are close enough to kill this mob...
						/if (${Target.ID}!=${Spawn[${tempmobID}].ID}) {
							/target id ${Spawn[${tempmobID}].ID}
							/delay 2s ${Target.ID}==${Spawn[${tempmobID}].ID}
						}
						/cast "${PullWith}"
						/call WaitCast ${Spell[${PullWith}].MyCastTime}
					} else {
						/echo well we could not get close enough, lets try naving closer:
						/call WaitForNavToFinish ${Spawn[${tempmobID}].Y} ${Spawn[${tempmobID}].X} ${Spawn[${tempmobID}].Z} 50
					}
				} else {
					/echo we move all the way to the mob
					/call WaitForNavToFinish ${Spawn[${tempmobID}].Y} ${Spawn[${tempmobID}].X} ${Spawn[${tempmobID}].Z} 50
				}
			} else {
				/echo no pullable mobs found
			}
			/delay 1s
		} else {
			/squelch /groupinfo followme off
		}
	}
	/if (${Task[The Darkness Howls].Step[Some orcweres are climbing the mountain toward The Maker!].Status.Equal[0/8]}) {
		/echo setting firstpartdone to 1 in ${Task[The Darkness Howls].Step.Instruction} because Status is 0/8
		/varset firstpartdone 1
		/delay 2s
	}
	/if (${Task[The Darkness Howls].Step.Instruction.Equal[Some orcweres are climbing the mountain toward The Maker!]}) {
		/if (${firstpartdone}==0) {
			/varset firstpartdone 1
		}
		/if (${firstpartdone}==1) {
			|/echo doing ${Task[The Darkness Howls].Step.Instruction}
			/bcga //chase on
			/bcga //dismount
			/if (${SpawnCount[id ${Me.ID} loc -289 872 206 radius 20]}==0) {
				/call WaitForNavToFinish 872 -289 206 150
			} else {
				/echo setting firstpartdone to 2 in ${Task[The Darkness Howls].Step.Instruction}
				/varset firstpartdone 2
			}
		}
	}
	/if (${Task[The Darkness Howls].Step.Instruction.Equal[Some orcweres are climbing the mountain toward The Maker!]} && ${firstpartdone}==2) {
		/call GetHostilesOnXTarget
		/if (${Macro.Return} == 0) {
			/declare tempmobID int local
			/echo doing ${Task[The Darkness Howls].Step.Instruction}
			/bcga //chase on
			/bcga //dismount
			/call DarknessFindMobToPull climber
			/varset tempmobID ${Macro.Return}
			/if (${tempmobID}) {
				/echo We found a valid mob to kill: ${Spawn[${tempmobID}]}
				/if (${Me.Gem[${Spell[${PullWith}]}]}!=0) {
					/call WaitForNavToFinish2 ${Spawn[${tempmobID}].ID} 100
					/if (${Macro.Return}==1) {
						/echo according to WaitForNavToFinish2 we are close enough to kill this mob...
						/if (${Target.ID}!=${Spawn[${tempmobID}].ID}) {
							/target id ${Spawn[${tempmobID}].ID}
							/delay 2s ${Target.ID}==${Spawn[${tempmobID}].ID}
						}
						/cast "${PullWith}"
						/call WaitCast ${Spell[${PullWith}].MyCastTime}
					} else {
						/echo well we could not get close enough, lets try naving closer:
						/call WaitForNavToFinish ${Spawn[${tempmobID}].Y} ${Spawn[${tempmobID}].X} ${Spawn[${tempmobID}].Z} 100
					}
				} else {
					/echo we move all the way to the mob
					/call WaitForNavToFinish ${Spawn[${tempmobID}].Y} ${Spawn[${tempmobID}].X} ${Spawn[${tempmobID}].Z} 100
				}
			} else {
				/echo no pullable mobs found
			}
			/delay 1s
		} else {
			/squelch /groupinfo followme off
		}
	}
	/if (${Task[The Darkness Howls].Step[Stop the orcwere infiltrators that have climbed over the wall in the east.].Status.Equal[0/10]}) {
		/echo setting firstpartdone to 2 in ${Task[The Darkness Howls].Step.Instruction} because Status is 0/10
		/varset firstpartdone 2
		/delay 2s
	}
	/if (${Task[The Darkness Howls].Step.Instruction.Equal[Stop the orcwere infiltrators that have climbed over the wall in the east.]}) {
		/if (${firstpartdone}==0) {
			/varset firstpartdone 2
		}
		/if (${firstpartdone}==2) {
			|/echo doing ${Task[The Darkness Howls].Step.Instruction}
			/bcga //chase on
			/bcga //dismount
			/if (${SpawnCount[id ${Me.ID} loc -550 742 -14 radius 20]}==0) {
				/call WaitForNavToFinish 742 -550 -14 200
			} else {
				/echo setting firstpartdone to 3 in ${Task[The Darkness Howls].Step.Instruction}
				/varset firstpartdone 3
			}
		}
	}
	/if (${Task[The Darkness Howls].Step.Instruction.Equal[Stop the orcwere infiltrators that have climbed over the wall in the east.]} && ${firstpartdone}==3) {
		/call GetHostilesOnXTarget
		/if (${Macro.Return} == 0) {
			/groupinfo followme on
			/declare tempmobID int local
			/echo doing ${Task[The Darkness Howls].Step.Instruction}
			/bcga //chase on
			/bcga //dismount
			/call DarknessFindMobToPull infiltrator
			/varset tempmobID ${Macro.Return}
			/if (${tempmobID}) {
				/echo We found a valid mob to kill: ${Spawn[${tempmobID}]}
				/if (${Me.Gem[${Spell[${PullWith}]}]}!=0) {
					/call WaitForNavToFinish2 ${Spawn[${tempmobID}].ID} 50
					/if (${Macro.Return}==1) {
						/echo according to WaitForNavToFinish2 we are close enough to kill this mob...
						/if (${Target.ID}!=${Spawn[${tempmobID}].ID}) {
							/target id ${Spawn[${tempmobID}].ID}
							/delay 2s ${Target.ID}==${Spawn[${tempmobID}].ID}
						}
						/cast "${PullWith}"
						/call WaitCast ${Spell[${PullWith}].MyCastTime}
					} else {
						/echo well we could not get close enough, lets try naving closer:
						/call WaitForNavToFinish ${Spawn[${tempmobID}].Y} ${Spawn[${tempmobID}].X} ${Spawn[${tempmobID}].Z} 50
					}
				} else {
					/echo we move all the way to the mob
					/call WaitForNavToFinish ${Spawn[${tempmobID}].Y} ${Spawn[${tempmobID}].X} ${Spawn[${tempmobID}].Z} 50
				}
			} else {
				/echo no pullable mobs found
			}
			/delay 1s
		} else {
			/squelch /groupinfo followme off
		}
	}
	/if (${Task[The Darkness Howls].Step[Keep the orcweres after our supplies! They are ravaging the landing area!].Status.Equal[0/10]}) {
		/echo setting firstpartdone to 3 in ${Task[The Darkness Howls].Step.Instruction} because Status is 0/10
		/varset firstpartdone 3
		/delay 2s
	}
	/if (${Task[The Darkness Howls].Step.Instruction.Equal[Keep the orcweres after our supplies! They are ravaging the landing area!]}) {
		/if (${firstpartdone}==0) {
			/varset firstpartdone 3
		}
		/if (${firstpartdone}==3) {
			|/echo doing ${Task[The Darkness Howls].Step.Instruction}
			/bcga //chase on
			/bcga //dismount
			/if (${SpawnCount[id ${Me.ID} loc -2 1042 169 radius 20]}==0) {
				/call WaitForNavToFinish 1042 -2 169 200
			} else {
				/echo setting firstpartdone to 4 in ${Task[The Darkness Howls].Step.Instruction}
				/varset firstpartdone 4
			}
		}
	}
	/if (${Task[The Darkness Howls].Step.Instruction.Equal[Keep the orcweres after our supplies! They are ravaging the landing area!]} && ${firstpartdone}==4) {
		/call GetHostilesOnXTarget
		/if (${Macro.Return} == 0) {
			/declare tempmobID int local
			/echo doing ${Task[The Darkness Howls].Step.Instruction}
			/bcga //chase on
			/bcga //dismount
			/call DarknessFindMobToPull ravager
			/varset tempmobID ${Macro.Return}
			/if (${tempmobID}) {
				/echo We found a valid mob to kill: ${Spawn[${tempmobID}]}
				/if (${Me.Gem[${Spell[${PullWith}]}]}!=0) {
					/call WaitForNavToFinish2 ${Spawn[${tempmobID}].ID} 50
					/if (${Macro.Return}==1) {
						/echo according to WaitForNavToFinish2 we are close enough to kill this mob...
						/if (${Target.ID}!=${Spawn[${tempmobID}].ID}) {
							/target id ${Spawn[${tempmobID}].ID}
							/delay 2s ${Target.ID}==${Spawn[${tempmobID}].ID}
						}
						/cast "${PullWith}"
						/call WaitCast ${Spell[${PullWith}].MyCastTime}
					} else {
						/echo well we could not get close enough, lets try naving closer:
						/call WaitForNavToFinish ${Spawn[${tempmobID}].Y} ${Spawn[${tempmobID}].X} ${Spawn[${tempmobID}].Z} 50
					}
				} else {
					/echo we move all the way to the mob
					/call WaitForNavToFinish ${Spawn[${tempmobID}].Y} ${Spawn[${tempmobID}].X} ${Spawn[${tempmobID}].Z} 50
				}
			} else {
				/echo no pullable mobs found
			}
			/delay 1s
		} else {
			/squelch /groupinfo followme off
		}
	}
	/if (${Task[The Darkness Howls].Step[That was too close. Press them back into their homes. Kill the howlers. Take the fight to them!].Status.Equal[0/5]} && ${firstpartdone} < 4) {
		/echo setting firstpartdone to 4 in ${Task[The Darkness Howls].Step.Instruction} because Status is 0/5
		/varset firstpartdone 4
		/delay 2s
	}
	/if (${Task[The Darkness Howls].Step.Instruction.Equal[That was too close. Press them back into their homes. Kill the howlers. Take the fight to them!]} && ${firstpartdone} < 5) {
		/if (${firstpartdone}==0) {
			/varset firstpartdone 4
		}
		/if (${firstpartdone}==4) {
			/bcga //chase on
			/bcga //dismount
			/if (${SpawnCount[id ${Me.ID} loc 7 -189 3 radius 20]}==0) {
				/call WaitForNavToFinish -189 7 3 200
			} else {
				/echo setting firstpartdone to 5 in ${Task[The Darkness Howls].Step.Instruction}
				/varset firstpartdone 5
			}
		}
	}
	/if (${Task[The Darkness Howls].Step.Instruction.Equal[That was too close. Press them back into their homes. Kill the howlers. Take the fight to them!]} && ${firstpartdone}==5) {
		/if (${SpawnCount[npc Grash]}) {
			/call GetHostilesOnXTarget
			/if (${Macro.Return} == 0) {
				/if (${Bool[${Plugin[mq2autoloot]}]}==TRUE) /autoloot turn off
				/echo named spawn IS UP, lets go kill it.
				/bcga //chase on
				/bcga //dismount
				/call WaitForNavToFinish2 ${Spawn[npc Grash].ID} 150
			} else {
				/squelch /groupinfo followme off
			}
			/return
		}
		/call GetHostilesOnXTarget
		/if (${Macro.Return} == 0) {
			/groupinfo followme on
			/declare tempmobID int local
			/echo doing ${Task[The Darkness Howls].Step.Instruction}
			/bcga //chase on
			/bcga //dismount
			/call DarknessFindMobToPull howler
			/varset tempmobID ${Macro.Return}
			/if (${tempmobID}) {
				/echo We found a valid mob to kill: ${Spawn[${tempmobID}]}
				/if (${Me.Gem[${Spell[${PullWith}]}]}!=0) {
					/call WaitForNavToFinish2 ${Spawn[${tempmobID}].ID} 50
					/if (${Macro.Return}==1) {
						/echo according to WaitForNavToFinish2 we are close enough to kill this mob...
						/if (${Target.ID}!=${Spawn[${tempmobID}].ID}) {
							/target id ${Spawn[${tempmobID}].ID}
							/delay 2s ${Target.ID}==${Spawn[${tempmobID}].ID}
						}
						/cast "${PullWith}"
						/call WaitCast ${Spell[${PullWith}].MyCastTime}
					} else {
						/echo well we could not get close enough, lets try naving closer:
						/call WaitForNavToFinish ${Spawn[${tempmobID}].Y} ${Spawn[${tempmobID}].X} ${Spawn[${tempmobID}].Z} 50
					}
				} else {
					/echo we move all the way to the mob
					/call WaitForNavToFinish ${Spawn[${tempmobID}].Y} ${Spawn[${tempmobID}].X} ${Spawn[${tempmobID}].Z} 50
				}
			} else {
				/echo no pullable mobs found
			}
			/delay 1s
		} else {
			/squelch /groupinfo followme off
		}
	}
	/if (${Task[The Darkness Howls].Step.Instruction.Equal[Open the chest.]}) {
		/groupinfo followme on
		/if (${Spawn[object a rusty old].ID}) {
			/if (${Spawn[object a rusty old].Distance3D} > 20) {
				/tar id ${Spawn[object a rusty old].ID}
				/delay 2s ${Target.ID}==${Spawn[object a rusty old].ID}
				/if (${Target.ID}==${Spawn[object a rusty old].ID}) {
					/call WaitForNavToFinish ${Target.Y} ${Target.X} ${Target.Z} 100
				}
			} else {
				/if (${Bool[${Plugin[mq2autoloot]}]}==TRUE) /autoloot turn off
				/echo we are at chest, type /open
				/tar id ${Spawn[object a rusty old].ID}
				/delay 2s ${Target.ID}==${Spawn[object a rusty old].ID}
				/end
			}
		}
		/delay 1s
	}
	/delay 1
/return

Sub Custom
	/if (${Zone.ShortName.Equal[qey2hh1_mission]}) {
		/call DoCleet
		/return
	}
	/if (${Zone.ShortName.Equal[potranquility_errand]}) {
		/call DoHorn
		/return
	}
	/if (${Zone.ShortName.Equal[dreadspire_mission]}) {
		/call DoBerry
		/return
	}
	/if (${Zone.ShortName.Equal[PoKnowledge_Mission1L]}) {
		/call DoHobby
		/return
	}
	/if (${Zone.ShortName.Equal[gnomemtn_errand]}) {
		/call DoDarknessHowls
		/return
	}

/return

Sub DoTheTrade
	/if (${Window[TradeWnd].Open} && !${Window[TradeWnd].MyTradeReady}) {
		/notify TradeWnd TRDW_Trade_Button leftmouseup
		/delay 2s ${Window[TradeWnd].MyTradeReady}==TRUE
		/echo waiting for ${Target} to click trade
		/delay 120s ${Window[TradeWnd].Open}==FALSE
		/if (!${Window[TradeWnd].Open}) {
			/echo he clicked trade...
		} else {
			/echo crap he is not clicking trade
			/end
		}
	}
/return
Sub CountTradeSlots
	/declare m int local
	/declare numslots int local 0
	/for m 0 to 7
		/if (${Window[TradeWnd].Child[TRDW_TradeSlot${m}].Tooltip.Length}) {
			/varcalc numslots ${numslots} + 1
		}
	/next m
/return ${numslots}

Sub TradeSafeTarget(int targid)
	/echo [TradeSafeTarget] im supposed to locate ${targid} now
	/declare thetargetid int local
	/varset thetargetid ${targid}
:saferetarget
	/if (${Target.ID} && ${Target.ID}==${thetargetid}) /return
	/if (${thetargetid}) {
		/if (${Spawn[${thetargetid}].Distance}<200) {
			/echo Targeting ${Spawn[${thetargetid}]}
			/target id ${thetargetid}
			/delay 1s ${Target.ID}==${thetargetid}
		}
	}
	/if (!${Target.ID}) {
		/echo [SafeTarget] couldnt find a target, retrying
		/delay 1s
		/goto :saferetarget
	}
/return

Sub ClericInGroup
	/declare gn int local 0
	/for gn 1 to 5
		/if (${Group.Member[${gn}].Class.Name.Equal[Cleric]}==TRUE) {
			/return ${gn}
		}
	/next gn
/return 0


