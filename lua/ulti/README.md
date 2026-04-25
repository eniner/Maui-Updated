# Ultimate EQ Help Menu

## What This Is
This is a MacroQuest Lua + ImGui in-game help interface for UltimateEQ.
It provides:
- A full progression tracker from Pre-Ultimate through God progression.
- NPC and item reference pages based on live server quest scripts/docs.
- Zone access, command, and system references.
- Theme and text-color customization with persistent settings.

## Run
```text
/lua run pro
```

## Main Files
- `init.lua`: main window, sidebar, auto-track event hooks, and UI settings.
- `content.lua`: page renderers, progression tracker logic, and theme page.
- `data_progression.lua`: sidebar models and progression tier metadata.
- `data_*.lua`: content pages (NPCs, commands, systems, items, etc.).
- `pro_settings.lua`: saved theme/text/autotrack settings.
- `tier_progress_tracker.lua`: saved progression step checkboxes.

## Notes
- Progress tracking is tied to tier IDs `11.1` through `11.15`.
- Auto-track supports kill/loot/hail/turn-in keyword matching from chat events.
- If `data_zone_names.lua` fails to load, other pages continue to function.
