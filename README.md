# CooldownCollaborator

Group and raid cooldown coordinator for World of Warcraft: Midnight (12.x).

CooldownCollaborator gives your group a live shared view of every major defensive and utility cooldown — who has it, how long until it's back, and whether it's ready to assign. Works for both 5-man party and full 40-player raids with automatic layout switching.

## Features

- **Unified CD panel** — all 28 tracked spells across 13 classes in a single draggable list
- **Live countdowns** — 0.5-second refresh with green/yellow/red status coloring
- **Class color coding** — per-class stripe and name coloring so you know the owner at a glance
- **Party and raid support** — automatically tracks `party1`–`party4` in 5-mans and `raid1`–`raid40` in raids
- **Addon sync** — broadcasts observed casts to other CooldownCollaborator users after each encounter via `C_ChatInfo.SendAddonMessage` (encounter lockdown safe)
- **Draggable and lockable** — position and scale saved between sessions

## Tracked Cooldowns

Rallying Cry · Aura Mastery · Lay on Hands · Blessing of Protection · Guardian Spirit · Pain Suppression · Power Word: Barrier · Leap of Faith · Anti-Magic Zone · Raise Ally · Heroism · Bloodlust · Spirit Link Totem · Ancestral Protection Totem · Healing Tide Totem · Time Warp · Ice Block · Demonic Gateway · Revival · Life Cocoon · Tranquility · Rebirth · Innervate · Darkness · Rewind · Rescue · Zephyr · Time Dilation

## Slash Commands

| Command | Effect |
|---|---|
| `/cdc` | Toggle panel visibility |
| `/cdc lock` / `/cdc unlock` | Lock or unlock frame position |
| `/cdc reset` | Reset to default position |
| `/cdc debug` | Print all tracked cooldowns and remaining times |
| `/cdc settings` | Open the options panel |

## Compatibility

- WoW Midnight 12.0.7+
- No library dependencies
- Fully Midnight-safe: detection uses `UNIT_SPELLCAST_SUCCEEDED` on party/raid unit tokens (non-secret spellIDs), not combat log

## Design Notes

In Midnight, `C_Spell.GetSpellCooldown()` timing fields are secret values — you cannot read them to know how long a CD has left. CooldownCollaborator works around this entirely: it detects the cast event and starts a local countdown based on known base durations. This means it works correctly for every player in your group regardless of talent reductions, which are not considered.

## Author

Nelnamara — [CurseForge](https://www.curseforge.com/wow/addons/cooldowncollaborator) · [GitHub](https://github.com/Nelnamara/CooldownCollaborator)
