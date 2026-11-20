# CooldownCollaborator

> **WoW:** Retail 12.1.5 · MoP Classic 5.5.4 · TBC Anniversary 2.5.6 · Classic Era 1.15.9 · WoW: Forever 1.60.1 · **Author:** Nelnamara

CooldownCollaborator gives your group a live shared view of every major defensive and utility cooldown — who has it, how long until it's back, and whether it's ready to assign. Works for both 5-man party and full 40-player raids with automatic layout switching. One download covers all five clients, and each client tracks its own spell list.

**Try it in your groups.** Most of this is new since 1.1.1, on every client. Testing in all kinds of groups (dungeons, raids, battlegrounds, with friends who run it too) is encouraged and appreciated. Tell us what you see, good or bad, in [Issues](https://github.com/Nelnamara/CooldownCollaborator/issues).

---

## Features

- **Unified CD panel** — one draggable list. Running cooldowns first, ready ones folded per spell, two columns from 10 players, greyed dead and offline owners, a `?` on guessed ones, version dots by each name, the next Bloodlust in the title, an icon style, an effect bar for active externals, spell tooltips, click to ask (whisper; Shift for the group). Retail tracks 43 spells, each other client has its own list (see Tracked Cooldowns)
- **Roster capability scan** — knows who *can* provide Bloodlust/Heroism/Time Warp/Fury of the Aspects or a Battle Rez before anyone has cast anything, based on class and level (no Bloodlust or Heroism on Classic Era and WoW: Forever)
- **Essentials Bar** — slim always-visible view of those raid-wide resources: the first few ready providers then "+N", Battle Rez charges, Soulstones, world buffs, and a flask/food count
- **Lane View** — icons slide along a bar from "just used" to "ready"; ready providers line up on a row under each lane; `/cdc nexthit` rings what will be back by then
- **Request Rez** — raid leader/assist (or party leader, or anyone in a 5-man) targets a dead player and announces which Battle Rez provider is ready, by name; says when the raid's charges are gone and when the next one is back
- **Dead list** — a window listing the dead in the leader's order with a Call button each; opens when someone dies in combat
- **Externals strip, mana strip, burst line** — externals with owner and time left; mana spells with how many are ready and an Ask button anyone may press; your big cooldowns above the group's lust and Power Infusion
- **Ready alerts** — per spell: sound, row and bar flash, optional icon mid screen, optional warning N seconds before
- **Raid plans and rotation order** — a leader shares a plan over the group channel; a prompt bar shows your planned uses from BigWigs or DBM timers or a time into the fight; rotation order shows as numbers on the rows
- **Teams** — a tab on the panel for the players you pick
- **Your role** — Everything (default), Basics, Healer, Tank, DPS, each saying what it tracks; or tick whole kinds of spells
- **Joined windows** — the panel, Essentials Bar and Lane View start as one block that moves together; pull one loose, drop it back to rejoin
- **Profiles and officer setups** — named profiles, export and import, per-character window places; an officer can send a setup, and members Accept, Not now or Never
- **Guild sharing** — off by default; adds a Guild tab and sends hello, state requests and states on the guild channel
- **Pulls and keys** — last pull log, post who is ready to raid chat, ask the group again when a key starts
- **Cauldron/Feast tracking** — register a consumable buff by spell ID once (`/cdc consumable`) and it's tracked like any other shared resource
- **Live countdowns** — refresh with green/yellow/red status coloring, or a lighter mode that refreshes less often
- **Class color coding** — per-class stripe and name coloring
- **Party and raid support** — tracks `party1`–`party4` in 5-mans and `raid1`–`raid40` in raids
- **Addon sync** — message format 2 (see `docs/MESSAGE_FORMAT_2.md`): hidden addon messages to your party, raid or instance group only (the guild only with guild sharing on), carrying your own cooldowns, buff status, version, battle rez charges, Soulstone placements and what leaders and officers share; late joiners and /reloads are filled in; old 1.x copies still work
- **Standalone settings window** — six tabs (Getting Started, Display, Lists, Spells, Plans, Profiles); not registered through Blizzard's Settings panel, so it never blocks your spellbook
- **Ready-now announcements** — when your own tracked spell comes off cooldown, your client tells the group
- **Works with CooldownTimeline3** — group cooldowns can show as icons on CooldownTimeline3's lanes (see below)
- **Translations** — every player-visible string goes through a phrase table (`Locales/`): deDE, esES, esMX, frFR, itIT, koKR, ptBR, ruRU, zhCN, zhTW. A language shows English until it is translated on CurseForge
- **Public feed** — other addons can read the group's cooldowns (`docs/API.md`)
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
- **`/cdc lock`** / **`/cdc unlock`** — Lock or unlock the position of the windows
- **`/cdc reset`** — Reset the panel to its default position
- **`/cdc settings`** — Open the settings window
- **`/cdc essentials`** — Toggle the Essentials Bar
- **`/cdc lanes`** — Toggle the Lane View
- **`/cdc nexthit <seconds or M:SS>`** / **`/cdc nexthit off`** — Set or clear the Lane View's look-ahead: what will be back by then gets a gold ring
- **`/cdc roster`** — Print the current roster capability scan
- **`/cdc rez`** — Call a Battle Rez on your current (dead) target. With nobody targeted it calls the top of the dead list. The party leader, a raid leader or assist, or anyone in a 5-man
- **`/cdc lastpull`** — Print the last pull's log
- **`/cdc post`** — Post who is ready to raid chat
- **`/cdc report`** — Open a box with what to paste into a new issue on GitHub
- **`/cdc tour`** — Take the tour again: one step for each window that is on, with Lock in place at the end (it also runs by itself the first time you are in a group)
- **`/cdc consumable <spellID> <seconds> <flask|food|other> <name>`** — Register a flask, food or Cauldron/Feast-style buff for tracking. `flask` and `food` count in the Flask / Food line; `other` is tracked but not counted. Leave the category out and it is guessed from the name (the word flask or food anywhere in it)
- **`/cdc consumable remove <spellID>`** — Stop tracking a consumable you added (they are also listed, with Remove buttons, on the Custom Spells tab in settings)
- **`/cdc verbose`** — Toggle detailed cast/sync logging, for diagnosing tracking issues
- **`/cdc debug`** — Print all tracked cooldowns, remaining times, and group/encounter state

### Settings

Open with `/cdc settings`, or right-click the minimap button. Six tabs: **Getting Started** (pick a window to read what it is for and see it with made-up players, Take the tour, Report a problem, the CooldownTimeline3 link), **Display** (windows on or off, lock and reset, opacity and scale, lighter mode, windows only in combat or at a boss, guild sharing), **Lists** (Essentials bar and burst line choices, rezzers to skip), **Spells** (Your role, kinds of spells, Default Spells, Custom Spells), **Plans** (the raid cooldown plan, rotation order, teams) and **Profiles** (Default, New, Copy from, Delete and Reset like every Ace addon, export and import, officer setups, layouts, last pull). Settings > Spells opens with **Your role** cards.

Any other text after `/cdc` toggles the panel.

### Tracked Cooldowns

**Retail (43):** Rallying Cry · Shield Wall · Last Stand · Challenging Shout · Aura Mastery · Lay on Hands · Blessing of Protection · Blessing of Sacrifice · Intercession · Guardian of Ancient Kings · Ardent Defender · Guardian Spirit · Pain Suppression · Power Word: Barrier · Leap of Faith · Power Infusion · Anti-Magic Zone · Raise Ally · Icebound Fortitude · Vampiric Blood · Harrier's Cry · Heroism · Bloodlust · Spirit Link Totem · Ancestral Protection Totem · Healing Tide Totem · Time Warp · Ice Block · Soulstone · Revival · Life Cocoon · Fortifying Brew · Tranquility · Rebirth · Innervate · Survival Instincts · Darkness · Metamorphosis · Rewind · Rescue · Zephyr · Time Dilation · Fury of the Aspects

**MoP Classic (41):** Rallying Cry · Skull Banner · Demoralizing Banner · Mocking Banner · Shield Wall · Last Stand · Lay on Hands · Hand of Protection · Hand of Sacrifice · Hand of Salvation · Devotion Aura · Guardian of Ancient Kings · Ardent Defender · Power Word: Barrier · Divine Hymn · Hymn of Hope · Vampiric Embrace · Guardian Spirit · Pain Suppression · Power Infusion · Anti-Magic Zone · Raise Ally · Icebound Fortitude · Vampiric Blood · Bloodlust · Heroism · Spirit Link Totem · Healing Tide Totem · Stormlash Totem · Time Warp · Soulstone · Revival · Life Cocoon · Avert Harm · Fortifying Brew · Tranquility · Ironbark · Innervate · Rebirth · Stampeding Roar · Survival Instincts

**TBC Anniversary (23):** Shield Wall · Challenging Shout · Last Stand · Lay on Hands · Divine Intervention · Blessing of Protection · Power Infusion · Pain Suppression · Shadowfiend · Lightwell · Fear Ward · Bloodlust · Heroism · Mana Tide Totem · Earth Elemental Totem · Reincarnation · Misdirection · Soulstone Resurrection · Innervate · Rebirth · Tranquility · Challenging Roar · Goblin Sapper Charge

**Classic Era (16):** Shield Wall · Challenging Shout · Last Stand · Lay on Hands · Divine Intervention · Blessing of Protection · Power Infusion · Lightwell · Mana Tide Totem · Reincarnation · Soulstone Resurrection · Innervate · Rebirth · Tranquility · Challenging Roar · Goblin Sapper Charge

**WoW: Forever (17):** the same sixteen as Classic Era, plus Fear Ward, with Forever's own timers (Lay on Hands 20 minutes, Shield Wall 15 minutes).

**Combat rez providers:** Retail: Rebirth, Raise Ally, Intercession, Soulstone. MoP Classic: Rebirth, Raise Ally, Soulstone. Classic Era, TBC Anniversary, WoW: Forever: Rebirth (Soulstone is tracked there, a stone placed beforehand). On Retail every combat rez draws from one shared charge pool; with none left nobody can be rezzed.

Every rank of a spell counts on Classic Era, TBC Anniversary and WoW: Forever. Each client also tracks its own flask and food buffs. You can add any custom spell or consumable buff in-game.

---

## Changelog

### Next version (number to be chosen)
- New main panel, dead list, externals strip, mana strip, burst line, Essentials Bar and Lane View looks (see Features)
- Ready alerts (thirty sounds, a speaker on each spell), raid plans, rotation order, teams, Your role cards, Ace-style profiles with a Default, officer setups, guild sharing
- Getting Started says what each window is for and shows it with sample players; a first-run tour; the panel, Essentials Bar and Lane View start joined
- Settings: six tabs with a Getting Started page, window on/off, combat or boss only, rezzers to skip, lighter mode
- Warlocks (Soulstone) are Battle Rez providers on Retail and MoP; Retail tracks Intercession; Request Rez knows when the raid's charges are gone
- Many more tracked spells on every client; Retail data matches 12.1.5 and Demonic Gateway is dropped
- Group sync format 2: hello, state request, shared charges and Soulstones; late joiners filled in; old copies still understood
- New commands: lastpull, post, report, tour, nexthit; `/cdc roster` in plain words
- Fixed: on WoW: Forever, groupmates whose names carry a surname were ignored; a ranked spell's tooltip shows your own rank
- Translation support (phrase table, ten languages); public feed for other addons
- Fixed: Essentials Bar overflow in raids, windows staying up after leaving the group, minimap drag scale, flask/food double count

### v1.1.1
- Fixed: you don't show as a ready Battle Rez or Bloodlust before you've learned it. Groupmates who haven't hit the level for it yet don't show either, and they pop in once they ding
- Fixed: the Lane view opens when you join a group, if you've turned it on. Turn it on while solo and `/cdc lanes` tells you it shows up once you're in a group

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
