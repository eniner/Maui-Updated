# MAUI (UltimateEQAssist) - System README

MAUI is an ImGui-based control center for MacroQuest that is built around **MuleAssist INI and macro workflows** and includes a launcher/sync panel for companion Lua tools.

## What This System Does

- Edits MuleAssist-style INI settings through a structured UI.
- Loads/saves character profile INI files from your MQ `config` directory.
- Starts/stops/pauses the MuleAssist macro from inside the UI.
- Provides safe startup helpers (preflight checks, mini setup, validation hints).
- Includes a `Tools` tab to sync, run, stop, and open companion Lua tools.
- Includes an in-app Readme/guide with setup, command, and troubleshooting content.

## Core Runtime Model

- **Primary engine:** MuleAssist macro (`/mac muleassist ...`)
- **UI host script:** `init.lua` (this folder)
- **Schema-driven fields:** `schemas/ma.lua` (+ addon custom sections in `addons/ma.lua`)
- **Config parser:** `lib/LIP.lua`
- **Tool sync source/target model:** source folders copied into MQ `lua` tool folders

Important: MAUI is **not LEM-driven by default**. LEM is integrated as an external tool you can launch from MAUI.

## Main UI Tabs

- `UI`: Main MuleAssist configuration editor (grouped by setup/combat/buffs/heals/pet/movement/utility/spellset).
- `RAW`: Direct raw INI text editing.
- `Tools`: External tool integration panel with status + Sync/Run/Stop/Open actions.
- `Readme`: In-app operational guide and tool-specific walkthroughs.

## External Tool Integrations (Tools Tab)

MAUI can manage these scripts:

- `EZInventory`
- `SmartLoot`
- `EZBots`
- `SpawnWatch` (local-only sync behavior)
- `BuffBot`
- `Grouper`
- `HunterHud`
- `LEM`
- `LuaConsole`
- `ButtonMaster`
- `ConditionBuilder` (local-only sync behavior)
- `ExprEvaluator` (local-only sync behavior)

Each tool card shows:

- source status (`Src:OK/Missing` or local-only)
- destination status (`Dst:OK/Missing`)
- script runtime status (`RUNNING/PAUSED/STOPPED`)
- actions: `Sync`, `Run`, `Stop`, `Open`

## Commands

Start/stop MAUI:

```text
/lua run maui
/lua stop maui
```

MAUI bind:

```text
/maui
/maui show
/maui hide
/maui stop
```

## Configuration & Files

- MAUI per-character UI config:
  - `%MQ_CONFIG%/<Server>_<Character>.ini` (MAUI section, start command, selected INI, theme, etc.)
- MuleAssist profile INI:
  - `MuleAssist_<Server>_<Character>.ini` (or level-specific variants)
- Schema definitions:
  - `schemas/ma.lua`
- Macro-specific custom UI logic:
  - `addons/ma.lua`

## Key Capabilities

- Theme selection (including template/default and several custom palettes).
- Action cooldown guards for repeated high-impact UI actions.
- Safe-start checks with warning modal before macro start.
- Spell/AA/disc picker support for configurable entries.
- Import helpers for compatible INI migration workflows.
- External tool status polling and one-click orchestration.

## Included Developer Console (LuaConsole)

This workspace also includes an upgraded `luaconsole` tool (run with `/lua run luaconsole`, open with `/lc`) aimed at live debugging and test iteration. Major capabilities include:

- persistent REPL environment with multi-line eval/history
- live watches and conditional triggers
- quick inspect/explorer for MQ objects and expressions
- snippet library and quick-run workflow helpers
- event tester, profiling/benchmark helpers, and log export
- plugin hooks, share/import helpers, and layout/theme modes

## Included Bundles In This Workspace

- `maui-main/`: upstream-style MAUI reference copy and docs.
- `ProfusionMaui/`: packaged copy including MAUI + Lua tool set + macro assets.
- `ProfusionMaui.zip`: archive of the packaged bundle.

## Quick Start

1. Place `maui` folder in MQ `lua` directory (if not already there).
2. Run `/lua run maui`.
3. Select/verify your MuleAssist INI in the UI.
4. Run preflight/sanity checks.
5. Start MuleAssist from MAUI.
6. Use `Tools` tab to sync and launch companion tools as needed.

## Notes

- This UI assumes MacroQuest + ImGui environment is available and in-game.
- `luafilesystem` (`lfs`) is required; MAUI attempts `mq.PackageMan` install/fallback load.
- External tool windows may keep their own theme unless those tools expose theme hooks.
