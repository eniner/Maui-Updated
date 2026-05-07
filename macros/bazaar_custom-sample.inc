| For Advanced Use Only!
|
| Allows you to add some custom functions to the bazaar.mac
| These customization will survive updates.
| 
| To enable:
| Step 1) Create a file named: bazaar_custom.inc
| Step 2) Enable in bazaarSettings.ini, set UseCustomInclude=TRUE
| Step 3) Create your custom_UseCustomInclude functions in the bazaar_custom.inc
|
| Current available sub functions are listed in this file, please do not try to make up random ones

| Runs once at the beginning of the script just after it finishes its internal setup
| To enable set script_initiate=TRUE in bazaarSettings.ini
Sub custom_script_initiate
    /call logIt "0" "Call to custom initiate function."
    |Option to resolve https://www.redguides.com/community/threads/bazaar-mac.61378/post-484186
    |Example: Runs to a random spot where i generally setup
    |Note: If you use these values it will tell everyone you use this macro.
    /if (${myLocation.Equal[TraderSide]}) {
        /nav locyx ${Math.Rand[965,1010]}.${Math.Rand[1,99]} ${Math.Rand[-700,-680]}.${Math.Rand[1,99]}
    }
    /delay 1s
    /while (${Me.Moving}) {
		/delay 1s
	}
/return

| Runs every time it runs a price scan.
| To enable set script_price_scan=TRUE in bazaarSettings.ini
Sub custom_script_price_scan
    |Option to resolve https://www.redguides.com/community/threads/bazaar-mac.61378/post-473311
    /SetWinTitle ${Me.Name} - ${Me.Platinum}
/return

| Runs if there is a new item in your /buyer mode
| To enable set script_buyer_new_item=TRUE in bazaarSettings.ini
Sub custom_script_buyer_new_item
    |Example: Have it pause and ask me to set me bazaar.ini stuff using the Lua Interface
    | https://www.redguides.com/community/threads/editbazaar-a-bazaar-ini-editor.79003/
	/lua run editBazaar.lua Bazaar.ini "${thisItem}"
	/mqpause on
/return

| Runs if there is a new item in your /trader mode
| To enable set script_trader_new_item=TRUE in bazaarSettings.ini
Sub custom_script_trader_new_item
    |Example: Have it pause and ask me to set me bazaar.ini stuff using the Lua Interface
    | https://www.redguides.com/community/threads/editbazaar-a-bazaar-ini-editor.79003/
	/lua run editBazaar.lua Bazaar.ini "${thisItem}"
	/mqpause on
/return

| Runs if there is an error during the /trader validation process
| To enable set script_trader_validationError=TRUE in bazaarSettings.ini
Sub custom_script_trader_validationError
    |Example: Pause the script so I may see what happened
    /echo Rut-ro Shaggy, Error during validation.
    /mqpause on
/return

| Allows you to customize how you want your sale price to adjust.
| You must return the value as /return ${Int[${var1}]}
| To enable set script_trader_price_controls=TRUE in bazaarSettings.ini
Sub custom_script_trader_price_controls(int var1)
    |Example: Big Daddy Rounding
    | https://www.redguides.com/community/threads/bazaar-mac.61378/page-3#post-389753
    /echo  Value Rounding Started at: (\ag${var1}\ay)
    /if (${newPrice} > 1000000) /varcalc var1 ${var1}-${Math.Calc[${var1}%100000]}
    /if (${var1} > 100000 && ${var1} < 999999) /varcalc var1 ${var1}-${Math.Calc[${var1}%10000]}
    /if (${var1} > 10000 && ${var1} < 99999) /varcalc var1 ${var1}-${Math.Calc[${var1}%1000]}
    /if (${var1} > 1000 && ${var1} < 9999) /varcalc var1 ${var1}-${Math.Calc[${var1}%100]}
    /if (${var1} > 100 && ${var1} < 999) /varcalc var1 ${var1}-${Math.Calc[${var1}%10]}
    /if (${var1} > 10 && ${var1} < 99) /varcalc var1 ${var1}-${Math.Calc[${var1}%5]}
    /echo Value Rounding Ended at: (\ag${var1}\ay)
    /return ${Int[${var1}]}
/return