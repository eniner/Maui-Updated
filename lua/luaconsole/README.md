# LuaConsole Pro (MQNext)

LuaConsole Pro is a full in-game Lua REPL and observability dashboard for MacroQuest / MQNext.

It combines:
- persistent REPL evaluation
- multi-line chunk support
- history and pretty printing
- watch/trigger/plot monitoring
- inspect tools and snippet workflows
- benchmark/profiling helpers
- export/import/share tools
- a plugin API and event bus for external Lua scripts

## Core Capabilities

### REPL Engine
- Persistent environment across evals (variables/functions survive until script restart or reset by user code).
- Multi-line continuation based on compile completeness (`<eof>` handling).
- Expression-first eval (`return <expr>`) fallback to chunk execution.
- `xpcall + traceback` error handling.
- Pretty-printer for tables/userdata with recursion handling.
- Safety layer for dangerous APIs (blocked `os.execute`, `os.exit`, `io.popen`, etc.).

### Console UI
- ImGui window toggle (`/luaconsole`, `/lc`).
- Colored output with filter/search.
- Input editor with Enter eval and Shift+Enter newline.
- Copy/Clear/Save/Load/Export controls.
- Autocomplete popup and TAB cycling.

### Observability
- Live Watches table (label, expression, value, last updated, eval time).
- Conditional Triggers (rising edge + cooldown + optional combat-only mode).
- Live numeric plots (`PlotLines`) with rolling sample buffers.
- Quick inspect snapshots (`Me`, `Target`, `Cursor`, `Group Avg`) and tree view.

### Workflow & Automation
- Snippet library with built-in starter snippets and one-click run.
- Event tester panel.
- Benchmark panel (avg/min/max/stddev/memory delta).
- Output export and share bundle import/export.
- Task modes (`combat`, `merc`, `nav`, `repl`, `monitor`).

### Reliability & Persistence
- Settings persistence (theme/layout/history/top ratio/toggles).
- Session save/load JSON.
- Autosave snapshots with restore prompt.
- Per-character file scoping for all persisted files.
- Remote eval file watcher for external editor workflows.

## Tabs / Panels

Default tabs include:
- `Console`: main REPL output + input.
- `Watches`: watch table + plots.
- `Snippets`: add/edit/run snippets.
- `Inspect`: expression inspect and tree explorer.
- `Logs`: dedicated filtered/searchable log view.
- `Observability`: combined watches/triggers/inspect/plots.
- `Workflow`: snippets/events/quick commands.
- `Systems`: combat/nav/merc/macro bridge utilities.
- `Settings`: performance, benchmark, theme/layout, share, plugin hooks.

External scripts can register additional custom tabs through the API.

## File Persistence

Stored under `mq.configDir` (and character-scoped when enabled):
- `luaconsole_settings.lua`
- `luaconsole_session.json`
- `luaconsole_watches.json`
- `luaconsole_triggers.json`
- `luaconsole_snippets.json`
- `luaconsole_share.json`
- `luaconsole_state.json`
- `luaconsole_autosave.json`
- `luaconsole_remote_eval.lua`
- `luaconsole_log.txt`

## Plugin API (External Script Interop)

This script exposes a module:

```lua
local console = require('luaconsole')
```

Available API functions:
- `console.log(text, level)`
- `console.watch_add(expr, label)`
- `console.watch_remove(id)`
- `console.trigger_add(condition, action, cooldownMs, combatOnly)`
- `console.trigger_remove(id)`
- `console.run_snippet(nameOrIndex)`
- `console.inspect_push(value, label)`
- `console.tab_register(name, callback, owner)`
- `console.tab_unregister(id)`
- `console.subscribe(eventName, callback, owner)`
- `console.unsubscribe(subId)`
- `console.publish(eventName, payload)`
- `console.state` (shared internal state table)

### Event Bus Events Emitted
- `eval_completed`
- `watch_changed`
- `trigger_fired`

Example:

```lua
local console = require('luaconsole')

console.log('external script online', 'ok')
console.watch_add('Me.PctHPs()', 'My HP')

local subId = console.subscribe('trigger_fired', function(payload)
    console.log('trigger fired: '..tostring(payload.id), 'warn')
end, 'my_script')

local tabId = console.tab_register('My Tool', function(state)
    ImGui.Text('Hello from custom tab')
end, 'my_script')
```

## Remote Eval Workflow

When remote eval is enabled, the console polls `luaconsole_remote_eval.lua`.
If file contents change and are non-empty, the new contents are evaluated as a chunk.

This supports editor-driven loop:
- edit file in VSCode
- save
- console evaluates updated text automatically

## Notes

- If running on Lua 5.4 environments, unpack compatibility is handled internally.
- Main tick loop is protected with `xpcall`; runtime faults are logged to console.
- For command syntax and examples, see `COMMANDS.md`.
