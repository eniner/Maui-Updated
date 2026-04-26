MAUI Tools Bundle
=================

Install Target
--------------
Extract this zip into your MacroQuest / VeryVanilla Emu Release folder:

    C:\Users\<You>\AppData\Local\VeryVanilla\Emu\Release

After extraction, the folders should line up like this:

    Release\lua\maui\init.lua
    Release\lua\maui\addons\ma.lua
    Release\lua\maui\schemas\ma.lua
    Release\lua\smartloot\init.lua
    Release\lua\spawnwatch\init.lua
    Release\lua\EZInventory\init.lua
    Release\lua\muleassist\LemonAssist.lua
    Release\macros\MuleAssist.mac
    Release\config\UltimateEQAssist\Templates\...
    Release\resources\Zones.ini

Do not extract this zip into Release\lua\maui. The zip already contains top-level folders such as lua, macros, config, resources, and package. Those folders belong directly under the Release folder.

What Goes Where
---------------
Copy or merge these folders from the zip into Release:

    lua       -> Release\lua
    macros    -> Release\macros
    config    -> Release\config
    resources -> Release\resources
    package   -> Release\package

Let Windows merge folders when prompted. If it asks to replace existing MAUI/MuleAssist files, replacing is expected for this repaired bundle.

Included MAUI Tools
-------------------
This bundle includes the Lua tools registered in MAUI's Tools tab:

    EZInventory
    SmartLoot
    EZBots
    SpawnWatch
    BuffBot
    Grouper
    UltimateEQ
    ulti
    LEM
    LuaConsole
    ButtonMaster
    EZQuests
    ConditionBuilder
    ExprEvaluator

It also includes shared Lua dependencies used by these tools, including lua\mq and lua\lib.

MuleAssist / LemonAssist
------------------------
MuleAssist needs LemonAssist for the /lassist helper behavior. In this bundle it is installed here:

    Release\lua\muleassist\LemonAssist.lua
    Release\lua\muleassist\Write.lua

The included MuleAssist macro runs it with:

    /lua run muleassist/LemonAssist

Do not move LemonAssist.lua into lua\maui. It is a MuleAssist helper and should stay under lua\muleassist.

Config Files
------------
This bundle includes MAUI and tool runtime config/templates, including:

    config\MuleAssist_*.ini
    config\UltimateEQAssist_*.ini
    config\UltimateEQAssist\Templates\...
    config\KissAssist_Info.ini
    config\KissAssist_Buffs.ini
    config\EZInventory\...
    config\ButtonMaster.lua
    config\Button_Master_Theme.lua
    config\luaconsole_*.json
    config\luaconsole_*.lua
    config\smartloot_config.json

Login databases, AutoLogin files, and password/credential-looking files were intentionally not bundled.

Starting MAUI
-------------
In game, from MacroQuest chat, run:

    /lua run maui

MAUI's Tools tab can run/stop/open the included tools. If a tool shows Src:Missing, that only means MAUI's optional download-source folder is not present. The runnable destination folder is what matters for normal use; check Dst:OK.

Useful Commands
---------------
Start MAUI:

    /lua run maui

Stop MAUI:

    /lua stop maui

Start MuleAssist macro:

    /mac MuleAssist

Start LemonAssist manually if needed:

    /lua run muleassist/LemonAssist

Start LuaConsole:

    /lua run luaconsole

Notes
-----
This archive was rebuilt from the current VeryVanilla install after MAUI/MuleAssist repairs. It includes the fixed maui/init.lua, the fixed MuleAssist.mac, and the missing LemonAssist Lua helper.