# CooldownCollaborator

> **WoW:** 12.0.7+ (Midnight) · **Author:** Nelnamara

CooldownCollaborator gives your group a live shared view of every major defensive and utility cooldown — who has it, how long until it's back, and whether it's ready to assign. Works for both 5-man party and full 40-player raids with automatic layout switching.

---

## Features

- **Unified CD panel** — 29 tracked spells across 13 classes in a single draggable list
- **Roster capability scan** — knows who *can* provide Bloodlust/Heroism/Time Warp/Fury of the Aspects or a Battle Rez before anyone has cast anything, based on class
- **Essentials Bar** — slim always-visible view of just those high-value raid-wide resources, separate from the full list
- **Lane View** — alternate visual: icons slide along a bar from "just used" to "ready" instead of a text countdown
- **Request Rez** — raid leader/assist (or party leader) targets a dead player and announces which Battle Rez provider is ready, by name
- **Cauldron/Feast tracking** — register a consumable buff by spell ID once (`/cdc consumable`) and it's tracked like any other shared resource
- **Live countdowns** — 0.5-second refresh with green/yellow/red status coloring
- **Class color coding** — per-class stripe and name coloring so you know the owner at a glance
- **Party and raid support** — automatically tracks `party1`–`party4` in 5-mans and `raid1`–`raid40` in raids
- **Addon sync** — broadcasts each client's own observed casts to other CooldownCollaborator users via `C_ChatInfo.SendAddonMessage`, with automatic retry if a send fails (death/resurrect windows, encounter lockdown, throttling)
- **Standalone settings window** — not registered through Blizzard's Settings panel, so it never blocks your spellbook (a known issue with the in-game AddOns settings tab)
- **Draggable and lockable** — position and scale saved between sessions

---

## Requirements

- WoW Midnight 12.0.7+
- No library dependencies
- **Both players need the addon** — cross-client visibility only works between players who both have CooldownCollaborator installed. Each client tracks its own cast and broadcasts it; there is no way to read another player's spell cast directly (Blizzard's secret-value protections block it categorically), so a player without the addon is invisible to it.

---

## Installation

Drop the `CooldownCollaborator` folder into `World of Warcraft\_retail_\Interface\AddOns\`, or install via the CurseForge app. Works immediately in any party or raid; `/cdc` toggles the panel.

---

## Usage

### Slash Commands

- **`/cdc`** — Toggle main panel visibility
- **`/cdc lock`** / **`/cdc unlock`** — Lock or unlock frame position
- **`/cdc reset`** — Reset to default position
- **`/cdc settings`** — Open the settings window
- **`/cdc essentials`** — Toggle the Essentials Bar
- **`/cdc lanes`** — Toggle the Lane View
- **`/cdc roster`** — Print the current roster capability scan
- **`/cdc rez`** — Request Rez on your current (dead) target — leader/assist only
- **`/cdc consumable <spellID> <seconds> <name>`** — Register a Cauldron/Feast-style shared buff for tracking
- **`/cdc verbose`** — Toggle detailed cast/sync logging, for diagnosing tracking issues
- **`/cdc debug`** — Print all tracked cooldowns, remaining times, and group/encounter state

### Tracked Cooldowns

Rallying Cry · Aura Mastery · Lay on Hands · Blessing of Protection · Guardian Spirit · Pain Suppression · Power Word: Barrier · Leap of Faith · Anti-Magic Zone · Raise Ally · Heroism · Bloodlust · Spirit Link Totem · Ancestral Protection Totem · Healing Tide Totem · Time Warp · Ice Block · Demonic Gateway · Revival · Life Cocoon · Tranquility · Rebirth · Innervate · Darkness · Rewind · Rescue · Zephyr · Time Dilation · Fury of the Aspects — plus any custom spell or consumable buff you register in-game.

---

## Compatibility / Midnight Notes

Detects your own casts via `UNIT_SPELLCAST_SUCCEEDED` on the `player` token only — `spellID` is secret on `party`/`raid` tokens (confirmed by live testing), so other players' cooldowns arrive solely via the addon-message sync, never by reading their cast event.

`C_Spell.GetSpellCooldown()` timing fields are secret in Midnight, so countdowns are based on known base durations (talent reductions aren't considered) — which means they're correct for every player in your group regardless of talents. Sync messages carry elapsed-time-since-cast, not an absolute timestamp (`GetTime()` is per-client, not a shared clock), and each client re-anchors incoming data to its own clock on arrival.

---

## Changelog

### v1.0.3
- Live local readiness for Battle-Rez and Bloodlust providers — reads your own charges and cooldown directly now that those values are no longer secret on the `player` unit in 12.0.7
- Minimap button resized to the standard 24px

### v1.0.2
- Minimap button and AddOns-list icon using the addon artwork (self-contained gold ring, fixes the off-center tracking-border offset)

### v1.0.1
- Built-in consumable tracking — Well Fed and Haste/Crit flask buffs detected automatically
- Group flask/food status strip
- Spec detection refined via `NotifyInspect`

### v1.0.0
- Initial release: shared cooldown panel (29 tracked spells across 13 classes), roster capability scan, Essentials Bar, Lane View, raid-lead Request Rez, and addon-message sync

---

## Roadmap

<details>
<summary>Planned</summary>

- **Click-to-expand missing buffs** — show *which* group members are missing flask/food by name
- **Dual potion tracking** — combat/utility potion usage windows (e.g. Voidlight)
- **Consumable ranks** — quality-tiered food/flask display (legendary → quest-grade)
- **Encounter sync hardening** — broader retry coverage across death/lockdown windows
- **Per-spec capability detail** — distinguish talented Battle-Rez/Lust availability, not just class

</details>

---

## Feature Requests

<details>
<summary>How to request</summary>

Open an issue on [GitHub](https://github.com/Nelnamara/CooldownCollaborator/issues) or leave a CurseForge comment — include the class/spell you'd like tracked.

</details>

---

## Author

Nelnamara — [CurseForge](https://www.curseforge.com/wow/addons/cooldowncollaborator) · [GitHub](https://github.com/Nelnamara/CooldownCollaborator)
