# CooldownCollaborator

A live, shared view of your group's big defensive and utility cooldowns. See who has Bloodlust, a Battle Rez, a raid cooldown, and how long until it is back. Works in 5-man parties and full raids, and switches layout for you.

One download covers Retail 12.1.5, MoP Classic 5.5.4, TBC Anniversary 2.5.6, Classic Era 1.15.9 and WoW: Forever 1.60.1. Each client tracks its own spell list.

**Retail and WoW: Forever: both players need the addon.** The game hides other players' casts there, so CC shares each player's own casts with other CC users. A player without CC cannot be seen by it.

**Classic Era, TBC Anniversary and MoP Classic: your groupmates don't need it for their cooldowns to show.** CC reads other players' casts from the combat log. Ready-now announcements and flask and food status still come only from players who have CC.

## What it does

- **Cooldown panel.** Tracked spells in one draggable list, with live countdowns and class colours. Retail tracks 29 spells across 11 classes. Other clients are listed under Tracked cooldowns.
- **Roster scan.** Knows who can bring Bloodlust, Heroism, Time Warp, Fury of the Aspects or a Battle Rez before anyone casts anything. Classic Era and WoW: Forever have no Bloodlust or Heroism, so there is no lust lane there.
- **Essentials Bar.** A slim bar with just those raid-wide resources, plus a flask and food count for the group.
- **Lane View.** Icons slide along a bar from "just used" to "ready".
- **Request Rez.** Raid leader or assist (or party leader) targets a dead player and announces which Battle Rez is ready, by name.
- **Ready-now announcements.** When your own spell comes off cooldown, your client tells the group, so talent-shortened cooldowns do not show long on other screens.
- **Cauldron and Feast tracking.** Register a shared buff once with `/cdc consumable`.
- **Your own spells.** Untick any default spell, or add your own in Settings.
- **Its own settings window.** It never blocks your spellbook.

## Tracked cooldowns

- **Retail (29):** Rallying Cry, Aura Mastery, Lay on Hands, Blessing of Protection, Guardian Spirit, Pain Suppression, Power Word: Barrier, Leap of Faith, Anti-Magic Zone, Raise Ally, Heroism, Bloodlust, Spirit Link Totem, Ancestral Protection Totem, Healing Tide Totem, Time Warp, Ice Block, Demonic Gateway, Revival, Life Cocoon, Tranquility, Rebirth, Innervate, Darkness, Rewind, Rescue, Zephyr, Time Dilation, Fury of the Aspects
- **MoP Classic (32):** Rallying Cry, Devotion Aura, Lay on Hands, Hand of Protection, Hand of Sacrifice, Hand of Salvation, Guardian Spirit, Pain Suppression, Power Infusion, Power Word: Barrier, Divine Hymn, Hymn of Hope, Vampiric Embrace, Anti-Magic Zone, Raise Ally, Heroism, Bloodlust, Spirit Link Totem, Healing Tide Totem, Stormlash Totem, Time Warp, Revival, Life Cocoon, Tranquility, Rebirth, Innervate, Ironbark, Stampeding Roar, Soulstone, Avert Harm, Demoralizing Banner, Skull Banner
- **TBC Anniversary (17):** Shield Wall, Challenging Shout, Lay on Hands, Blessing of Protection, Divine Intervention, Power Infusion, Pain Suppression, Lightwell, Shadowfiend, Heroism, Bloodlust, Mana Tide Totem, Misdirection, Soulstone Resurrection, Innervate, Rebirth, Tranquility
- **Classic Era (12):** Shield Wall, Challenging Shout, Lay on Hands, Blessing of Protection, Divine Intervention, Power Infusion, Lightwell, Mana Tide Totem, Soulstone Resurrection, Innervate, Rebirth, Tranquility
- **WoW: Forever (12):** the same twelve as Classic Era, with Forever's own timers (Lay on Hands 20 minutes, Shield Wall 15 minutes)

Every rank of a spell counts on Classic Era, TBC Anniversary and WoW: Forever. Each client also tracks its own flask and food buffs.

## Works with CooldownTimeline3

CC works together with the addon **CooldownTimeline3** (CDTL3), on every client both support. When both are loaded, CC adds a timer type called **Group cooldowns** to CDTL3.

- Each tracked cooldown, yours and your group's, shows as an icon with a countdown on a CDTL3 lane. It leaves when the cooldown ends or is reported ready.
- Icons go to Lane 1 by default. To pick another lane, or switch them off, open CDTL3 and go to **Filters > Defaults > Group cooldowns**.
- To see who owns each icon, turn on **Caster lane** in CDTL3 under **Lanes > (your lane) > General**. Names show in class colour under the icons.
- In CC's settings, the checkbox **Show group cooldowns on CooldownTimeline3's lanes** turns this on or off. It only appears when CDTL3 is loaded.
- CC works fine without CDTL3.

## Getting started

1. Install CooldownCollaborator. On Retail and WoW: Forever, ask your group to install it too.
2. Join a party or raid. The panel shows up on its own. Type `/cdc` to show or hide it.
3. Drag the panel where you want it, then type `/cdc lock`.
4. Type `/cdc settings` to choose which spells to track, and to change size and opacity.
5. Want the icons on CooldownTimeline3? Install it. Nothing else to do. The checkbox in CC's settings is on by default.

## Slash commands

- `/cdc` shows or hides the panel
- `/cdc lock` and `/cdc unlock` lock or unlock its position
- `/cdc reset` puts the panel back at its default position
- `/cdc settings` opens the settings window
- `/cdc essentials` shows or hides the Essentials Bar
- `/cdc lanes` shows or hides the Lane View
- `/cdc roster` lists who can bring which raid resource
- `/cdc rez` requests a Battle Rez for your dead target (leader or assist only)
- `/cdc consumable <spellID> <seconds> <name>` registers a Cauldron or Feast style buff
- `/cdc verbose` turns on detailed logging, for finding tracking problems
- `/cdc debug` prints every tracked cooldown and the group state

## Bugs and requests

Report bugs and ask for spells at https://github.com/Nelnamara/CooldownCollaborator/issues. Say which class and spell you mean.

## Changelog

### 1.1.0
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
