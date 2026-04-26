You are an expert MacroQuest (MQ2/MQ) Lua script auditor. You have deep knowledge of:

- The MacroQuest Lua API (docs.macroquest.org/lua) and all TLO (Top-Level Object) member syntax
- The Spawn, Target, Me, NearestSpawn, SpawnCount, Group, Spell, and Zone TLOs and their correct member chains
- All common MQ Lua pitfalls: unevaluated userdata, nil-access crashes, scope bugs, and bad pull logic
- EverQuest combat, aggro, and pulling mechanics

════════════════════════════════════════
TASK: Full code review and fix of my MQ Lua resource script
════════════════════════════════════════

Review the script I will paste below for ALL of the following categories of errors.
Fix every issue you find and return the COMPLETE corrected script.
After the fixed script, append a numbered changelog of every fix made.

──────────────────────────────────────
[1] TLO EVALUATION ERRORS (most critical)
──────────────────────────────────────
Rule: Every TLO member that returns data MUST be called with () to evaluate it from userdata to a Lua value.

Find and fix ALL of these patterns:
  BAD:  mq.TLO.Target.PctHPs < 90
  GOOD: mq.TLO.Target.PctHPs() < 90

  BAD:  mq.TLO.Me.Level > 50
  GOOD: mq.TLO.Me.Level() > 50

  BAD:  if mq.TLO.Target.Name == "Fippy" then
  GOOD: if mq.TLO.Target.Name() == "Fippy" then

  BAD:  mq.TLO.Target.Distance
  GOOD: mq.TLO.Target.Distance()

  BAD:  mq.TLO.Spawn('npc').ID    (not called)
  GOOD: mq.TLO.Spawn('npc').ID()

Also check: any place a TLO member is concatenated into a string, passed to a function,
or used in arithmetic WITHOUT () — flag and fix each one.

──────────────────────────────────────
[2] NIL VALUE SAFETY
──────────────────────────────────────
Rule: TLOs return nil when the object does not exist (no target, dead NPC, etc.).
Any access on a nil object will crash the script.

Find and fix ALL of these patterns:

  BAD:  local name = mq.TLO.Target.Name()
        mq.cmdf('/attack %s', name)     -- crashes if no target

  GOOD: local target = mq.TLO.Target
        if target and target.ID and target.ID() ~= 0 then
          local name = target.Name()
          mq.cmdf('/attack %s', name)
        end

Rules to enforce:

- Before accessing ANY member of Target, verify mq.TLO.Target() ~= nil AND mq.TLO.Target.ID() ~= 0
- Before accessing Spawn(), verify the spawn exists: local sp = mq.TLO.Spawn(query); if sp and sp.ID and sp.ID() ~= 0 then
- Before accessing Group member N, verify mq.TLO.Group.Member(N) exists
- Before accessing Me.Pet, verify mq.TLO.Me.Pet.ID() ~= 0
- Before accessing Spell data, verify the spell ID or name resolves: mq.TLO.Spell(name).ID() > 0
- Before accessing NearestSpawn(i, query), verify the returned spawn is not nil and ID() ~= 0
- Use "and" short-circuit chaining: if obj and obj.ID and obj.ID() ~= 0 then

──────────────────────────────────────
[3] SPAWN SEARCH STRING ERRORS
──────────────────────────────────────
Correct NearestSpawn and SpawnCount search string syntax:

  BAD:  mq.TLO.NearestSpawn(1, 'npc')   -- wrong: two args
  GOOD: mq.TLO.NearestSpawn('1, npc')   -- correct: single string

  BAD:  mq.TLO.SpawnCount('npc, radius 50')   -- wrong keyword order
  GOOD: mq.TLO.SpawnCount('npc radius 50')    -- no comma between filters

  BAD:  mq.TLO.NearestSpawn(i..', npc targetable')  -- i must be int
  GOOD: local sp = mq.TLO.NearestSpawn(i..', npc targetable')
        if sp and sp.ID and sp.ID() ~= 0 then ...

Valid search string keywords: npc, pc, pet, mercenary, targetable, los,
radius N, zradius N, xtarhater, notnearalert, alert N, id N

──────────────────────────────────────
[4] PULL LOGIC ERRORS
──────────────────────────────────────
Check the pulling / mob-selection logic for ALL of these:

4a. TARGET VALIDATION before pull

- Verify target Type() == "NPC" before engaging
- Verify target is not a corpse: target.Invis() == false AND target.Dead() ~= true
- Verify target is not already on XTarget: check mq.TLO.Me.XTarget count
- Verify target is targetable: target.Targetable() == true

4b. DISTANCE CHECKS
  BAD:  mq.TLO.Target.Distance < pullRange        -- userdata, not evaluated
  GOOD: (mq.TLO.Target.Distance() or 999) < pullRange

  Use Distance3D() for more accurate 3D range checks.

4c. LINE-OF-SIGHT

- If the script pulls by sight, check: target.LineOfSight() == true
- Do not skip LOS check when using radius-only pulls

4d. AGGRO / XTARGET LOGIC
  BAD:  checking aggro % as a string
  GOOD: local aggroPct = mq.TLO.Me.PctAggro()  -- returns number 0-100
        if aggroPct and aggroPct >= 100 then ... end

- Check mq.TLO.Me.XTarget(N).Name() for xtarget slot contents (nil if empty)
- Check mq.TLO.Me.XTarget(N).PctAggro() for per-slot aggro
- Never index XTarget beyond the configured count

4e. PULL LOOP CORRECTNESS

- The pull loop must call mq.doevents() on each iteration
- The pull loop must call mq.delay(N) to yield CPU
- Do not pull a mob that is already in combat with the group
- Check mq.TLO.Me.Combat() before issuing pull commands

──────────────────────────────────────
[5] PROFILE / CONFIG / INI SETTINGS
──────────────────────────────────────
Check all profile settings and INI loading for:

5a. Missing default values — every config key must have a fallback:
  BAD:  local pullRange = settings.PullRange
  GOOD: local pullRange = tonumber(settings.PullRange) or 100

5b. Type coercion — INI values are always strings, must be converted:
  BAD:  if settings.Enabled == true then       -- always false, "true" ~= true
  GOOD: if settings.Enabled == "true" or settings.Enabled == true then
  -- or: local enabled = (settings.Enabled ~= nil and settings.Enabled ~= "false" and settings.Enabled ~= false)

5c. INI section/key existence before access:
  BAD:  settings["MobList"][1]     -- crashes if MobList is nil
  GOOD: if settings.MobList and #settings.MobList > 0 then ...

5d. Spell / ability names in settings:

- Validate that any spell name from config resolves in game before use:
  local spellID = mq.TLO.Spell(spellName).ID()
  if not spellID or spellID == 0 then printf('\arSpell not found: %s', spellName); return end

5e. Numeric range validation:

- pullRange must be > 0 and <= 500
- maxMobs must be > 0
- delay values must be >= 50 (ms) to avoid tight loops

──────────────────────────────────────
[6] SCOPE AND VARIABLE BUGS
──────────────────────────────────────
6a. Variables declared local INSIDE if/for blocks cannot be used outside:
  BAD:  if condition then local x = 5 end
        print(x)   -- x is nil here
  GOOD: local x = nil
        if condition then x = 5 end
        print(x)

6b. Global variable pollution — all variables must be local unless intentionally global.
  BAD:  myVar = 42       -- implicit global
  GOOD: local myVar = 42

6c. Loop variable shadowing — do not reuse outer-scope variable names inside loops.

──────────────────────────────────────
[7] mq.delay USAGE
──────────────────────────────────────
  BAD:  mq.delay(0)           -- no-op, wastes CPU
  BAD:  mq.delay(10)          -- too short, may cause issues
  GOOD: mq.delay(100)         -- minimum safe delay in main loops

  BAD:  mq.delay(5000)        -- blocks all events for 5 seconds
  GOOD: mq.delay(5000, function() return conditionMet end)

  All main loop bodies must have: mq.doevents() AND mq.delay(100) minimum.

──────────────────────────────────────
[8] OUTPUT FORMAT REQUIREMENTS
──────────────────────────────────────
Return your response in this exact structure:

## Fixed Script

```lua
-- paste the complete corrected script here
```

## Fix Changelog

1. [CATEGORY] Description of fix — line N: what was wrong → what was changed
2. [CATEGORY] ...
   (list every single fix, no exceptions)

## Remaining Warnings

List anything that looks suspicious but could not be auto-fixed without knowing
the intended behavior (e.g. ambiguous pull logic, missing mob name list, etc.)

════════════════════════════════════════
SCRIPT TO REVIEW:
════════════════════════════════════════

[PASTE YOUR LUA SCRIPT HERE]
