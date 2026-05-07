| Taken from other sources and compined
| decker

	#event CombineError "#*#There was no place to put that#*#"
	#event CombineError "#*#You cannot combine these items in this container type!#*#"
	#event CombineError "#*#did not accept these items#*#"
	#event CombineError "#*#You are missing#*#"
	#event Advance "#*#You can no longer advance #*#"
	#event ContUsed "#*#Someone else is using that. Try again later.#*#"
	#event End "#*#can not afford#*#"
	#Event Skillup "#*#become better at#*#"
	#Event Salvage "You failed the combine, but you managed to recover #*#"
	#event Broke "#*#you cannot afford#*#"
	#event Broke "#*#you can't afford#*#"


| --------------------------------------------------------------------------------------------
| SUB: ChooseRecipe
| --------------------------------------------------------------------------------------------
	Sub ChooseRecipe
	/delay 1s
	/nomodkey /notify TradeskillWnd COMBW_SearchTextEdit leftmouseup
	/delay 5
	/echo Searching for Recipe
	/call Type "${ItemTo}"

|--- First Check to see if Recipe is in favorites

	/nomodkey /notify TradeskillWnd COMBW_RecipeList listselect ${Window[TradeskillWnd].Child[COMBW_RecipeList].List[${ItemTo}]}
	/delay 2
	/nomodkey /notify TradeskillWnd COMBW_RecipeList leftmouseup ${Window[TradeskillWnd].Child[COMBW_RecipeList].List[${ItemTo}]}

	/varset Checkrecipe ${Window[TradeskillWnd].Child[COMBW_RecipeList].List[${ItemTo}]}

|--- Its not in Favorites.. so lets type it in and do a search
	/if (!${Checkrecipe}) {

		/delay 1m ${Window[TradeskillWnd].Child[COMBW_SearchButton].Enabled}
		/nomodkey /notify TradeskillWnd COMBW_SearchButton leftmouseup
		/delay 10
		/nomodkey /notify TradeskillWnd COMBW_RecipeList listselect ${Window[TradeskillWnd].Child[COMBW_RecipeList].List[${ItemTo}]}
		/delay 2
		/nomodkey /notify TradeskillWnd COMBW_RecipeList leftmouseup ${Window[TradeskillWnd].Child[COMBW_RecipeList].List[${ItemTo}]}
		/varset Checkrecipe ${Window[TradeskillWnd].Child[COMBW_RecipeList].List[${ItemTo}]}

	|--- Search could not find it either so lets do a old school combine
		/if (!${Checkrecipe}) {
			/nomodkey /notify TradeskillWnd COMBW_ExperimentButton leftmouseup
			/varset NewUI 2
			/call OLDUICOMBINE
			/nomodkey /notify ${PackCode} Container_DoneButton Leftmouseup
			/return
		} else {
			/call DoCombine
		}
	} else {
		/call DoCombine
	}
	/nomodkey /notify TradeskillWnd COMBW_CloseButton Leftmouseup
	/return

|~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
| Type out the input string.
|
|~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~


| --------------------------------------------------------------------------------------------
| SUB: Type
| --------------------------------------------------------------------------------------------
	Sub Type(InStr)
	/echo trying to enter Recipe Desired
	/declare char string local
	/declare loopctr int local
	/for loopctr 1 to ${InStr.Length}
		/varset char ${InStr.Mid[${loopctr},1]}
		/if (!${char.Length}) {
			/nomodkey /keypress space chat
		} else {
			/nomodkey /keypress ${char} chat
		}
	/next loopctr
	/return

|~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
|Sub DoCombine
|
|~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
| --------------------------------------------------------------------------------------------
| SUB: DoCombine
| --------------------------------------------------------------------------------------------
	sub DoCombine
	/call ClearCursor
:Loop
	/nomodkey /notify TradeskillWnd CombineButton leftmouseup
	/delay 2s ${Cursor.ID}
	/call ClearCursor

	/doevents
	/delay 2
	/if (${EndingVar}==1) /goto :Loop
	/varset EndingVar 1

	/return

|~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
|Clear Cursor
|
|~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
| --------------------------------------------------------------------------------------------
| SUB: ClearCursor
| --------------------------------------------------------------------------------------------
	Sub ClearCursor
	/declare x int local
:auto_inv
	/if (${Cursor.ID}) {
		/if (${Cursor.Container}) {
			/for x 1 to 8
				/if (!${InvSlot[pack${x}].Item.Container}) /nomodkey /itemnotify pack${x} leftmouseup
			/next x
		} else {
			/timed 5 /autoinventory
		}
		/goto :auto_inv
	}
	/return

|~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
|Sub OLD UI COMBINE
|~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
| --------------------------------------------------------------------------------------------
| SUB: OLDUICOMBINE
| --------------------------------------------------------------------------------------------
	Sub OLDUICOMBINE
	/echo recipe not found yet .. Going old school

	/call OpenPacks
	/call cleanPack "${Container}"

:Begin
	/doevents
	/if (${EndingVar}==1) {
		/call ClearCursor
		/for i 1 to 10
			/call AddComp "${Component[${i}]}" ${i}
		/next i
		/delay ${Math.Calc[${DelayMult}*1]}s
		/call OldDoCombine
		/doevents
		/goto :Begin
	}
	/return

|~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
| Movement Sub
|~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~


| --------------------------------------------------------------------------------------------
| SUB: Movement
| --------------------------------------------------------------------------------------------
	Sub Movement(Start,Finish,Door)
	/declare Location int inner
	/for Location ${Start} to ${Finish}
	:MoveLoop
		/face nolook loc ${LocArray[${Location}]}
		/if (${Math.Distance[${LocArray[${Location}]}]}>4) {
			/nomodkey /keypress forward hold
			/face nolook loc ${LocArray[${Location}]}

			/if (${Location}==${Door}) {
				/nomodkey /keypress USE
				/nomodkey /keypress USE
			}
		}
		/if (${Math.Distance[${LocArray[${Location}]}]}<=4) {
			/nomodkey /keypress forward
			/goto :next
		}
		/goto :MoveLoop
	:next
	/next Location
	/return

|~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
|Sub Add Components
|~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
| --------------------------------------------------------------------------------------------
| SUB: AddComp
| --------------------------------------------------------------------------------------------
	sub AddComp(CompName, PackSlot)
	/if (${CompName.Equal[NOTFOUND]}) /return

	/if (!${FindItem[=${CompName}].ID}) {
		/echo Could not find ${CompName} in inventory
		/beep
		/varset EndingVar 2
		/return
	}

:Loop
	/nomodkey /ctrl /itemnotify ${FindItem[=${CompName}].InvSlot} leftmouseup

	/if (!${Cursor.ID}) {
		/delay ${Math.Calc[${DelayMult}*1]}s
		/goto :Loop
	}

	/if (${PackCode.Equal[Enviro]}) {
		/nomodkey /itemnotify ${InvSlot[enviro${PackSlot}]} leftmouseup
	} else {
		/nomodkey /itemnotify in ${PackCode} ${PackSlot} leftmouseup
	}
	/doevents
	/return

|~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
|Sub Do the Combine
|~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
| --------------------------------------------------------------------------------------------
| SUB: OldDoCombine
| --------------------------------------------------------------------------------------------
	sub OldDoCombine
	/combine ${PackCode}
	/doevents
	/delay ${Math.Calc[${DelayMult}*1]}s
	/delay 5s ${Cursor.ID}
	/Call ClearCursor
	/doevents
	/return

|~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
|Read INI file for Loc array
|~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~


| --------------------------------------------------------------------------------------------
| SUB: ReadINIA
| --------------------------------------------------------------------------------------------
	Sub ReadINIA(FileName,SectionName)
	/echo Attempting to Read Section "${SectionName}" Zone Information from ${FileName}...

	/if (${Ini[${FileName},${SectionName},-1,NO].Equal[NO]}) {
		/echo "${SectionName}" is not a Valid Section for FILE:${FileName}, ending macro...

		/return
	}
	/declare nValues     int local
	/declare nArray      int local  0

|~~~~~~~~~~~~~~~~~~~~~~ Locs ~~~~~~~~~~~~~~~~~
	/Varset nValues ${Ini[${FileName},${SectionName},Value]}
	/echo ${nValues} Locs
:MakeArraylo
	/if (!${nValues}) /return
	/if (${nValues}) {
		/echo Declaring Loc Array...
		/declare LocArray[${nValues}]  string outer
	}
	/for nArray 1 to ${nValues}
		/varset LocArray[${nArray}] ${Ini[${FileName},${SectionName},Loc${nArray}]}
		/echo  loc ${nArray} defined ${LocArray[${nArray}]}

	/next nArray

	/echo "${SectionName}" Zone Information Read Successfully from ${FileName}...

	/return

|~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
|Sub Event Container being used
|~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
| --------------------------------------------------------------------------------------------
| SUB: Event_ContUsed
| --------------------------------------------------------------------------------------------
	Sub Event_ContUsed
	/echo Container in use. Waiting 1 Minute, or until no PCs are nearby and trying again.
	/delay 1m ${SpawnCount[pc radius 50]}<=1
	/doevents
	/return

|~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
|Sub Event Combine error
|~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
| --------------------------------------------------------------------------------------------
| SUB: Event_CombineError
| --------------------------------------------------------------------------------------------
	Sub Event_CombineError
	/varset EndingVar 2
	/return

|~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
|Sub Event End
|~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
| --------------------------------------------------------------------------------------------
| SUB: Event_End
| --------------------------------------------------------------------------------------------
	Sub Event_End
	/call Ending
	/return


| --------------------------------------------------------------------------------------------
| SUB: Ending
| --------------------------------------------------------------------------------------------
	Sub Ending
	/echo macro ending
	/end
	/return

|~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
|Sub READ Ini File
|~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
| --------------------------------------------------------------------------------------------
| SUB: ReadIni
| --------------------------------------------------------------------------------------------
	Sub ReadIni(RecipeName)

	/echo Running ${RecipeName} recipe

	/if (${Ini["${Filename}","${RecipeName}",-1,"NOTFOUND"].Equal["NOTFOUND"]}) {
		/echo Recipe ${RecipeName} not found
		/endmacro
	}

	/varset Container ${Ini[${Filename},${RecipeName},Cont,Enviro]}

	/if (${Container.Equal[Enviro]}) {
		/varset PackCode Enviro
	} else {
		/varset PackCode ${FindItem[=${Container}].InvSlot}

		/if (${PackCode.Equal[NULL]}) {
			/echo Could not find container ${Container}
			/varset EndingVar 2
			/return
		}
	| pack1 = 22, ... , pack8 = 29
		/varset PackCode pack${Math.Calc[${PackCode}-22].Int}
	}

	/for i 1 to 10
		/varset Component[${i}] ${Ini[${Filename},${RecipeName},Comp${Math.Calc[${i}-1].Int},NOTFOUND]}

	/next i
	/return

|~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
|Sub Event Salvage
|~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
| --------------------------------------------------------------------------------------------
| SUB: Event_Salvage
| --------------------------------------------------------------------------------------------
	Sub Event_Salvage

	/if (${NewUI}==2) /call cleanPack "${Container}"

	/return


| --------------------------------------------------------------------------------------------
| SUB: Sell
| --------------------------------------------------------------------------------------------
	Sub Sell(string ItemToSell)

	/declare OldMoney int Inner

	/call ClearCursor

	/if (${ItemToSell.Equal[NULL]})  /return

:Finding
	/if (${FindItemCount[=${ItemToSell}]}) {
		/nomodkey /itemnotify ${FindItem[=${ItemToSell}].InvSlot} leftmouseup
		/if (${SelectedItem.ID}==${FindItem[=${ItemToSell}].ID}) {
			/delay 1
			/varset OldMoney ${Me.Cash}
			/nomodkey /shift /notify MerchantWnd MW_Sell_Button leftmouseup
			/delay 2s (${Me.Cash}!=${OldMoney})
		}

		/goto :Finding
	}

	/echo No more ${ItemToSell} to sell!!!
	/return


| --------------------------------------------------------------------------------------------
| SUB: OpenPacks
| --------------------------------------------------------------------------------------------
	Sub OpenPacks
	/declare bag int local 0
	/if (!${Window[InventoryWindow].Open}) /nomodkey /keypress inventory
	/delay 3s ${Window[InventoryWindow].Open}
	/for bag 1 to 8
		/if (!${Window[Pack${bag}].Open}) /nomodkey /itemnotify pack${bag} rightmouseup
		/delay 3s ${Window[Pack${bag}].Open}
		/if (${Window[TradeskillWnd].Open}) /nomodkey /notify TradeskillWnd ExperimentButton leftmouseup
		/delay 5s !${Window[TradeskillWnd].Open}
	/next bag
	/return


| --------------------------------------------------------------------------------------------
| SUB: ClosePacks
| --------------------------------------------------------------------------------------------
	Sub ClosePacks
	/declare bag int local 0
	/if (!${Window[InventoryWindow].Open}) /nomodkey /keypress inventory
	/delay 3s ${Window[InventoryWindow].Open}
	/for bag 1 to 8
		/if (${Window[Pack${bag}].Open}) /nomodkey /itemnotify pack${bag} rightmouseup
		/delay 3s !${Window[Pack${bag}].Open}
	/next bag
	/if (${Window[InventoryWindow].Open}) /nomodkey /keypress inventory
	/delay 3s !${Window[InventoryWindow].Open}
	/return


| --------------------------------------------------------------------------------------------
| SUB: cleanPack
| --------------------------------------------------------------------------------------------
	sub cleanPack(string PackName)
	/echo Please Wait ...... Cleaning out ${PackName} container
	/declare iSlot int local
	/declare iCount int local
	/declare PackNumber string local

	/call ClearCursor

	/if (${PackName.Equal[Enviro]}) {
		/varset PackNumber e
	} else {
		/varset PackNumber ${FindItem[=${PackName}].InvSlot.ID}
		/if (${PackNumber}) {
			/varcalc PackNumber ${PackNumber}-21
			/varset PackNumber ${PackNumber.Arg[0,.]}
		} else {
			/echo Could not find container in your inventory
			/echo Contanier name = ${PackName}
			/endmacro
		}
	}
	/if (${PackNumber.Equal[e]}) {
		/for iSlot 1 to 10
			/nomodkey /shiftkey /itemnotify enviro${iSlot} leftmouseup
			/delay 1s
			/autoinv
		/next iSlot

	} else {

		/if (${Me.Inventory[Pack${PackNumber}].Container}==0) {
			/return
		}

		/for iSlot 1 to ${Me.Inventory[Pack${PackNumber}].Container}
		| Quit if the pack is empty
			/if (${Me.Inventory[Pack${PackNumber}].Container}==0) {
				/return
			}

			/if (${Me.Inventory[Pack${PackNumber}].Item[${iSlot}].ID}!=NULL) {
				/varset iCount ${Me.Inventory[Pack${PackNumber}].Items}
				/nomodkey /shiftkey /itemnotify in pack${PackNumber} ${iSlot} leftmouseup
				/delay 5s ${Cursor.ID}
				/timed 5 /autoinv
				/delay 5s !${Cursor.ID}
				/if (${Me.Inventory[Pack${PackNumber}].Items}==${iCount}) {
					/echo Unable to empty container.
					/endmacro
				}
			}
		/next iSlot
	}
	/echo Done Cleaning ${PackName} Container. Thank you for waiting!
	/return


| --------------------------------------------------------------------------------------------
| SUB: Buy
| --------------------------------------------------------------------------------------------
	Sub Buy(item ItemToBuy, int amount)
	/echo Buying ${ItemToBuy}!
	/declare QTY int Inner
	/declare l2 local int

|---SMALL delay to allow the MERCHANT Window to populate

	/delay ${Math.Calc[${DelayMult}*2]}s

	/varset QTY ${Math.Calc[${amount}-${FindItemCount[${ItemToBuy}]}]}
	/delay 1s
	/if (${FindItemCount[${ItemToBuy}]}>= ${amount}) {
		/echo Done!
		/return
	}
	/varset l2 ${Window[MerchantWnd].Child[ItemList].List[=${ItemToBuy},2]}
	/if (!${l2}) {
		/echo couldn't find ${ItemToBuy}
		/endm
	} else {
		/notify MerchantWnd ItemList listselect ${l2}
		/notify MerchantWnd ItemList leftmouse ${l2}
		/delay 2

	}

	/echo Buying ${ItemToBuy} Till I get ${amount}
:Loop

	/if (${QTY}>19) {
		/buyitem 20
		/delay 1s
		/doevents
		/varset QTY ${Math.Calc[${amount}-${FindItemCount[${ItemToBuy}]}]}
		/goto :Loop
	} ELSE {
		/if (${QTY}>0 && ${QTY}<20) {
			/buyitem ${QTY}
			/delay 1s
			/varset QTY ${Math.Calc[${amount}-${FindItemCount[${ItemToBuy}]}]}
		}
	}
	/if (${QTY}==0) {
		/echo Done!
		/return
	}
	/goto :Loop

	/return


| --------------------------------------------------------------------------------------------
| SUB: Event_Broke
| --------------------------------------------------------------------------------------------
	Sub Event_Broke
	/echo Error: You are out of money!
	/beep
	/endmacro
	/return
|  [+++  Formatted by MQ2fusing tabs for indents +++]
