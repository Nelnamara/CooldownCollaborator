# CooldownCollaborator

> **WoW:** Retail 12.1.5 · MoP Classic 5.5.4 · TBC Anniversary 2.5.6 · Classic Era 1.15.9 · WoW: Forever 1.60.1 · **Author:** Nelnamara

CooldownCollaborator gives your group a live shared view of every major defensive and utility cooldown — who has it, how long until it's back, and whether it's ready to assign. Works for both 5-man party and full 40-player raids with automatic layout switching. One download covers all five clients, and each client tracks its own spell list.

**Try it in your groups.** Version 1.1.0 is new on every client except Retail, and its link to CooldownTimeline3 is new everywhere. Testing in all kinds of groups (dungeons, raids, battlegrounds, with friends who run it too) is encouraged and appreciated. Tell us what you see, good or bad, in [Issues](https://github.com/Nelnamara/CooldownCollaborator/issues).

---

## Features

- **Unified CD panel** — tracked spells in a single draggable list (29 across 11 classes on Retail; each other client has its own list, see Tracked Cooldowns)
- **Roster capability scan** — knows who *can* provide Bloodlust/Heroism/Time Warp/Fury of the Aspects or a Battle Rez before anyone has cast anything, based on class (no Bloodlust or Heroism on Classic Era and WoW: Forever)
- **Essentials Bar** — slim always-visible view of just those high-value raid-wide resources, separate from the full list
- **Lane View** — alternate visual: icons slide along a bar from "just used" to "ready" instead of a text countdown
- **Request Rez** — raid leader/assist (or party leader) targets a dead player and announces which Battle Rez provider is ready, by name
- **Cauldron/Feast tracking** — register a consumable buff by spell ID once (`/cdc consumable`) and it's tracked like any other shared resource
- **Live countdowns** — 0.5-second refresh with green/yellow/red status coloring
- **Class color coding** — per-class stripe and name coloring so you know the owner at a glance
- **Party and raid support** — automatically tracks `party1`–`party4` in 5-mans and `raid1`–`raid40` in raids
- **Addon sync** — broadcasts each client's own observed casts to other CooldownCollaborator users via `C_ChatInfo.SendAddonMessage`, with automatic retry if a send fails (death/resurrect windows, encounter lockdown, throttling)
- **Standalone settings window** — not registered through Blizzard's Settings panel, so it never blocks your spellbook (a known issue with the in-game AddOns settings tab)
- **Ready-now announcements** — when your own tracked spell comes off cooldown, your client tells the group, so talent-shortened cooldowns stop showing long on other screens
- **Works with CooldownTimeline3** — group cooldowns can show as icons on CooldownTimeline3's lanes (see below)
- **Draggable and lockable** — position and scale saved between sessions

---

## Requirements

- One of: WoW Retail 12.1.5 (Midnight), MoP Classic 5.5.4, TBC Anniversary 2.5.6, Classic Era 1.15.9, or WoW: Forever 1.60.1
- No library dependencies
- CooldownTimeline3 is optional
- **Retail and WoW: Forever: both players need the addon.** The game hides other players' casts from addons there, so each client tracks its own cast and shares it. A player without the addon is invisible to it.
- **Classic Era, TBC Anniversary and MoP Classic: your groupmates don't need it for their cooldowns to show.** Other players' casts are read from the combat log. Ready-now announcements and flask/food status still come only from players who have the addon.

---

## Installation

Drop the `CooldownCollaborator` folder into your client's AddOns folder, or install via the CurseForge app. The same folder works on every client.

| Client | AddOns folder |
|---|---|
| Retail (Midnight) | `World of Warcraft\_retail_\Interface\AddOns\` |
| MoP Classic | `World of Warcraft\_classic_\Interface\AddOns\` |
| TBC Anniversary | `World of Warcraft\_anniversary_\Interface\AddOns\` |
| Classic Era | `World of Warcraft\_classic_era_\Interface\AddOns\` |
| World of Warcraft: Forever | `World of Warcraft\_forever_\Interface\AddOns\` |

Works immediately in any party or raid; `/cdc` toggles the panel.

---

## Works with CooldownTimeline3

CooldownCollaborator works together with the addon **CooldownTimeline3** (CDTL3), on every client both support. CC tracks and syncs your group's cooldowns. CDTL3 can show them on its lanes.

- When CDTL3 is loaded, CC adds a timer type called **Group cooldowns** at login.
- Each tracked cooldown, yours and your group members' (on Retail and WoW: Forever, those who run CC), then shows as an icon on a CDTL3 lane with a countdown. The icon leaves when the cooldown ends or the player reports it ready.
- Icons go to **Lane 1** by default. To pick another lane, or switch them off, open CDTL3 and go to **Filters > Defaults**, then choose **Group cooldowns**.
- To see who owns each icon, open CDTL3 and go to **Lanes > (your lane) > General** and turn on **Caster lane**. Each caster's name shows in class colour under the icon.
- In CC's settings window, the checkbox **Show group cooldowns on CooldownTimeline3's lanes** turns this on or off. It is on by default and only appears when CDTL3 is loaded.
- CC works fine without CDTL3. The link does nothing then.

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

### Settings

Open with `/cdc settings`, or right-click the minimap button. You can show or hide ready cooldowns, lock the panel, hide the minimap button, set the smallest cooldown to track (30s to 180s), and set panel opacity and scale. Default Spells lets you untick any tracked spell. Custom Spells lets you add your own by name or ID and set its cooldown length.

Any other text after `/cdc` toggles the panel.

### Tracked Cooldowns

**Retail (29):** Rallying Cry · Aura Mastery · Lay on Hands · Blessing of Protection · Guardian Spirit · Pain Suppression · Power Word: Barrier · Leap of Faith · Anti-Magic Zone · Raise Ally · Heroism · Bloodlust · Spirit Link Totem · Ancestral Protection Totem · Healing Tide Totem · Time Warp · Ice Block · Demonic Gateway · Revival · Life Cocoon · Tranquility · Rebirth · Innervate · Darkness · Rewind · Rescue · Zephyr · Time Dilation · Fury of the Aspects

**MoP Classic (32):** Rallying Cry · Devotion Aura · Lay on Hands · Hand of Protection · Hand of Sacrifice · Hand of Salvation · Guardian Spirit · Pain Suppression · Power Infusion · Power Word: Barrier · Divine Hymn · Hymn of Hope · Vampiric Embrace · Anti-Magic Zone · Raise Ally · Heroism · Bloodlust · Spirit Link Totem · Healing Tide Totem · Stormlash Totem · Time Warp · Revival · Life Cocoon · Tranquility · Rebirth · Innervate · Ironbark · Stampeding Roar · Soulstone · Avert Harm · Demoralizing Banner · Skull Banner

**TBC Anniversary (17):** Shield Wall · Challenging Shout · Lay on Hands · Blessing of Protection · Divine Intervention · Power Infusion · Pain Suppression · Lightwell · Shadowfiend · Heroism · Bloodlust · Mana Tide Totem · Misdirection · Soulstone Resurrection · Innervate · Rebirth · Tranquility

**Classic Era (12):** Shield Wall · Challenging Shout · Lay on Hands · Blessing of Protection · Divine Intervention · Power Infusion · Lightwell · Mana Tide Totem · Soulstone Resurrection · Innervate · Rebirth · Tranquility

**WoW: Forever (12):** the same twelve as Classic Era, with Forever's own timers (Lay on Hands 20 minutes, Shield Wall 15 minutes).

Every rank of a spell counts on Classic Era, TBC Anniversary and WoW: Forever. Each client also tracks its own flask and food buffs. You can add any custom spell or consumable buff in-game.

---

## Changelog

### v1.1.0
- One download now covers Retail, MoP Classic, TBC Anniversary, Classic Era and WoW: Forever
- Each client tracks its own spell list, with every rank on Classic Era, TBC Anniversary and WoW: Forever
- On Classic Era, TBC Anniversary and MoP Classic, other players' casts are read from the combat log, so groupmates don't need the addon for their cooldowns to show
- No Bloodlust or Heroism lane on Classic Era and WoW: Forever, which have neither
- Flask and food status on every client
- Works with CooldownTimeline3 on every client: group cooldowns can show on CDTL3's lanes (Settings checkbox, on by default when CDTL3 is loaded)
- Ready-now announcements: when your own tracked spell comes off cooldown it tells the group, so talent-shortened cooldowns no longer show long on other clients (older clients ignore it)
- Players are keyed by name and realm, so same-named players from different realms no longer clash
- Fixed: Evoker Fury of the Aspects is tracked again (it had the wrong spell ID)
- Fixed: the Battle Rez charge timer reads the right value
- Fixed: Anti-Magic Zone is 4 minutes
- Fixed: a sync that went through is no longer sent again, and one the game refused is retried for about half a minute
- Fixed: the minimap button sits on the rim of WoW: Forever's larger minimap, and stays there if the minimap is resized
- Fixed: `/cdc consumable` now saves a trailing `flask` or `food` as the category
- Fixed: sync uses instance chat in instance groups
- Interface 120105 (Retail 12.1.5)

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
- Initial release: shared cooldown panel (29 tracked spells across 11 classes), roster capability scan, Essentials Bar, Lane View, raid-lead Request Rez, and addon-message sync

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

## Compatibility / Midnight Notes

On Classic Era, TBC Anniversary and MoP Classic, other players' casts are also read from the combat log. Retail and WoW: Forever close it to addons.

On Retail and WoW: Forever, CC detects your own casts via `UNIT_SPELLCAST_SUCCEEDED` on the `player` token only — `spellID` is secret on `party`/`raid` tokens (confirmed by live testing), so other players' cooldowns arrive solely via the addon-message sync, never by reading their cast event.

`C_Spell.GetSpellCooldown()` timing fields are secret in Midnight, so countdowns are based on known base durations (talent reductions aren't considered) — which means they're correct for every player in your group regardless of talents. Sync messages carry elapsed-time-since-cast, not an absolute timestamp (`GetTime()` is per-client, not a shared clock), and each client re-anchors incoming data to its own clock on arrival.

---

## Author

Nelnamara — [CurseForge](https://www.curseforge.com/wow/addons/cooldowncollaborator) · [GitHub](https://github.com/Nelnamara/CooldownCollaborator)
