ROLE & CONTEXT
You are an expert MQ2 / MacroQuest Lua + ImGui UI engineer. Redesign the following EverQuest EQEmu GM Command Console init.lua into a true professional developer tool — think VS Code terminal + Sublime Text command palette meets game engine debug HUD. The current UI is a flat grid of buttons in collapsible sections. It works but looks amateurish. I want it to look and feel like something a senior tools engineer shipped.

SOURCE CODE
Rewrite the full init.lua file using MacroQuest Lua + ImGui. Keep all existing commands, sections, and logic intact — this is a visual and structural redesign only. All mq.cmd(), mq.TLO, confirmation dialogs, filter logic, raw command execution, and button profiles must remain fully functional.

LAYOUT REDESIGN — TOP BAR
Replace the current "Player: / Zone:" text lines with a compact status bar rendered using ImGui.PushStyleColor to create a dark inset strip across the top of the window. Show: [●] PlayerName (green dot = online), a | separator, Zone: ZoneName, and far right: Status 100 badge rendered in a colored rounded rect using ImDrawList:AddRectFilled. This should feel like an IDE status bar.

LAYOUT REDESIGN — LEFT SIDEBAR + MAIN PANEL
Implement a two-column split layout using ImGui.Columns(2) or a BeginChild on left + right:

- Left panel (~140px fixed width): vertical list of section names as selectable rows (ImGui.Selectable), with a small icon prefix per section (use text glyphs like [>], [#], [*], [!]). Active section highlighted. Clicking jumps to that section in the right panel or filters to it.
- Right panel (remaining width): shows only the selected section's commands as a button grid. No collapsible headers needed — the sidebar replaces them. Section title rendered as a bold header with a colored left-border accent using ImDrawList:AddRectFilled on a 3px strip.

LAYOUT REDESIGN — COMMAND INPUT DOCK
Move the command input area to a bottom-docked panel (fixed height ~110px) separated by a styled separator. Include:

- A single-line InputText for param (left ~45% width) and filter (right ~45% width) side by side on row 1.
- Raw command InputText full width on row 2, with [▶ Run] and [✕ Clear] icon buttons inline to its right.
- Below: Last sent: in muted small text using ImGui.TextDisabled.

VISUAL THEME — NEW "TERMINAL DARK" THEME
Add a 4th theme called "Terminal Dark" as the new default (set currentTheme = 4). Use these exact ImGui color values:

- WindowBg: 0.07, 0.07, 0.09, 0.98
- TitleBg / TitleBgActive: 0.10, 0.10, 0.13 / 0.13, 0.13, 0.17
- Button: 0.14, 0.14, 0.18, 1.0 — ButtonHovered: 0.22, 0.22, 0.30, 1.0 — ButtonActive: 0.30, 0.28, 0.42, 1.0
- FrameBg: 0.11, 0.11, 0.14, 1.0
- Header / HeaderHovered: 0.16, 0.16, 0.22 / 0.22, 0.22, 0.32
- Border: 0.28, 0.28, 0.38, 0.90
- Separator: 0.30, 0.30, 0.45, 1.0
- Text: 0.88, 0.88, 0.95, 1.0
- ScrollbarGrab: 0.28, 0.28, 0.40, 1.0
  Style: windowRounding=6, frameRounding=4, frameBorderSize=1, itemSpacingX=5, itemSpacingY=4

BUTTON REDESIGN
Buttons should feel like IDE action chips:

- Add a colored left-border accent (2px) using ImDrawList:AddRectFilled before each button render, keyed to section category: Basic=blue, NPC=amber, Lead=red, Zone=teal, Player=purple, ZC=green, Flags=pink.
- Dangerous commands: render button label in red text using ImGui.PushStyleColor(ImGuiCol.Text, ...) before ImGui.Button().
- Tooltip redesign: show the full #command param string in a styled tooltip box, with a second line showing the section name in muted text.
- Add a subtle keyboard shortcut hint overlay: if filterText matches exactly one command, auto-highlight that button with a yellow border accent.

CONFIRMATION DIALOG REDESIGN
Replace the plain confirm dialog with a modal overlay style: use ImGuiWindowFlags.Modal if available, or simulate with a centered fixed-size window. Header should read ⚠ Critical Command in orange text. Show the full resolved command string in a read-only InputText (so it can be copied). Execute button styled bright red, Cancel styled neutral gray.

WINDOW CONTROLS
Replace the "Window Controls" collapsible section at bottom with a title bar menu using ImGui.BeginMenuBar() / ImGui.BeginMenu(). Menus: Console (Close, Reset Inputs), Theme (list all 4 themes as radio items), Layout (Compact / Standard / Large as radio items).

WINDOW SIZING
Default window size: ImGui.SetNextWindowSize(860, 720, ImGuiCond.FirstUseEver). Add ImGuiWindowFlags.MenuBar to the main Begin() call.

CODE QUALITY

- Keep all existing local functions and variable names where possible so diffs are readable.
- Add a short -- DEV CONSOLE v2.0 header comment block.
- Group new helper functions (drawAccentBorder, renderStatusBar, renderSidebar, renderDockBottom) cleanly above renderMainDevConsole.
- Do not add any external dependencies — pure mq + ImGui only.

DELIVERABLE
Return the complete rewritten init.lua file. No truncation, no placeholders. Fully runnable drop-in replacement.
