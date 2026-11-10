# spell-check

Checks `Data.lua` against each client's own game data (DB2 tables from [wago.tools](https://wago.tools)).
It loads the real `Data.lua` in fengari (a Lua VM in Node) once per client, with `CC = { isForever = <bool> }`,
so what it checks is exactly what the addon builds.

## Run it (after every patch)

```
cd tools/spell-check
npm install          # first time only
node check.js        # both clients
node check.js forever
```

Exit code: 0 clean, 1 findings, 2 error (download or Lua failure).

1. Put the new build numbers in `builds.json` (`forever`: newest 1.60.x build; `retail`: newest 12.x build on wago.tools).
2. Run `node check.js`. Tables are cached in `cache/<build>/` (git-ignored); `--refresh` re-downloads.
3. Fix `Data.lua` for every finding and run again. Use `--src <folder>` to check another copy of the addon.

## What it reports (per client)

- spell IDs (canonical and every rank) missing from the game
- name mismatches; ranks that are not the same spell name as the canonical one
- cooldown mismatches: `max(RecoveryTime, CategoryRecoveryTime)` in SpellCooldowns (difficulty 0), ms to s.
  Item-use spells with no spell cooldown (Soulstone) use the item's own or category cooldown from ItemEffect.
- icon mismatches (SpellMisc.SpellIconFileDataID), class mismatches (SpellClassOptions)
- Forever only: the `talent` flag against the Talent table
- consumables: IDs missing, duration against the aura's SpellDuration
- capability IDs that are not canonical spell IDs of a spell of that class

## Retail is checked more loosely

Retail stores many cooldowns at runtime (charges, talents, category cooldowns), so SpellCooldowns is only
trusted when it holds a real value over 10 s, icons are not compared, and consumables with no data duration
are skipped (`relaxed` in `builds.json`). `nameAliases` lists deliberate display names
(`207399` is shown as "Ancestral Prot. Totem").
