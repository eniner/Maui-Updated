# Extending MAUI to support other INI based macros

MAUI has been refactored a little bit to allow for it to support other macros that are **very** similar to MuleAssist (i.e. KissAssist).

## start.lua

The bulk of the implementation for MAUI lives in `start.lua` and provides functions for how to display INI sections with properties of different types, such as lists, switches, numbers or strings.
The content displayed is based on what is defined in the currently selected schema file, which defines the sections and their properties.
In addition to the generic sections, custom sections will be shown from an included macro specific `.lua` file.

## globals.lua

Among other things, `globals.lua` includes an array table of schema names which MAUI supports. This is stored in `globals.Schemas`.
Currently, this only includes `ma` for the `MuleAssist` macro.

To support other macros, step one would be adding a schema name for the macro to this table, such as `ka` for the `KissAssist` macro.

## Addons folder

The addons folder contains the macro specific implementations. For example, `MuleAssist` includes custom sections for:

1. Debug options
2. Shared lists (nofire, nomagic, mezimmune, etc.)
3. Import KA INI

In order to add macro specific implementation for a new macro, add a new file `{schema_name}.lua` where `{schema_name}` is the name which was added to `globals.Schemas` above.
For example, to add custom sections for the `KissAssist` macro, add a new file `ka.lua` to the `addons` folder.

## Schemas folder

The schemas folder contains the schema of sections and properties for the macros supported by MAUI. Currently, this only includes `ma` for the `MuleAssist` macro.

In order to add a schema for another macro, add a new file `{schema_name}.lua` where `{schema_name}` is the name which was added to `globals.Schemas` above.
For example, to add a new schema file for the `KissAssist` macro, add a new file `ka.lua` to the `schemas` folder.


## Creating the schema file in the schemas folder

Just copy one of the existing ones and fit it to the new macro being added.

- Define the INI file pattern -- this needs to be refactored some really to handle differing # of inputs to the formatted string for different macros, i.e. KA doesn't include server name while MA does.

```lua
    INI_PATTERNS = {
        ['level'] = 'MuleAssist_%s_%s_%d.ini',
        ['nolevel'] = 'MuleAssist_%s_%s.ini',
    },
```

Right now, things are hardcoded to know what pattern to use and how many variable replacements there should be:

```lua
    if currentSchema == 'ma' then
        if FileExists(mq.configDir..'/'..schema['INI_PATTERNS']['level']:format(myServer, myName, myLevel)) then
            return schema['INI_PATTERNS']['level']:format(myServer, myName, myLevel)
```

- Define the default start command.

```lua
    StartCommand = '/mac muleassist assist ${Group.MainAssist}',
```

- Define the section ordering that will be used to write the INI in a particular order.

```lua
    Sections = {
        'General',
        'DPS',
        'Heals',
        'Buffs',
        'Melee',
        'Burn',
        'Mez',
        'AE',
        'OhShit',
        'Pet',
        'Pull',
        'Aggro',
        'Bandolier',
        'Cures',
        'GoM',
        'Merc',
        'AFKTools',
        'GMail',
        'MySpells',
        'SpellSet',
    },
```

- Define each section and its control switches and properties.

```lua
    Melee={
        Controls={
            On={
                Type='SWITCH',
            },
        },
        Properties={
            AssistAt={
                Type='NUMBER',
                Min=1,
                Max=100,
                Tooltip='Mob health to assist/attack. This affects when you engage and is NOT specific to melee characters. IE pet classes will send pets at this %%.',
            },
        },
    },
```
