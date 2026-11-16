# CooldownCollaborator

A live, shared view of your group's big defensive and utility cooldowns. See who has Bloodlust, who has a Battle Rez, who has a raid cooldown, and how long until each one is back. It works in 5-man parties and full raids, and switches its layout for you.

One download covers Retail 12.1.5, MoP Classic 5.5.4, TBC Anniversary 2.5.6, Classic Era 1.15.9 and WoW: Forever 1.60.1. Each client tracks its own spell list.

**On Retail and WoW: Forever, both players need the addon.** The game hides other players' casts there, so CooldownCollaborator shares each player's own casts with everyone else who runs it. If someone doesn't have it, it can't see them.

**On Classic Era, TBC Anniversary and MoP Classic, your groupmates don't need it for their cooldowns to show.** It reads their casts from the combat log. Ready-now announcements and flask and food status still only come from players who have it.

**Please try it in your groups!** Version 1.1.0 is new on every client except Retail, and the link to CooldownTimeline3 is new everywhere. Testing in all kinds of groups (dungeons, raids, battlegrounds, with friends who run it too) is encouraged and really appreciated. Let me know what you see, good or bad, at https://github.com/Nelnamara/CooldownCollaborator/issues.

## What it does

- **Cooldown panel.** Every tracked spell in one list you can drag around, with live countdowns and class colours. Retail tracks 29 spells across 11 classes, and the other clients are listed below.
- **Roster scan.** It knows who can bring Bloodlust, Heroism, Time Warp, Fury of the Aspects or a Battle Rez before anyone casts anything. Classic Era and WoW: Forever have no Bloodlust or Heroism, so there's no lust lane there.
- **Essentials Bar.** A slim bar with just those raid-wide resources, plus a flask and food count for the group.
- **Lane View.** Icons slide along a bar from "just used" to "ready".
- **Request Rez.** The raid leader or an assist (or the party leader) targets a dead player, and it announces which Battle Rez is ready, by name.
- **Ready-now announcements.** When your own spell comes off cooldown, your client tells the group, so talent-shortened cooldowns don't show long on everyone else's screen.
- **Cauldrons and Feasts.** Register a shared buff once with `/cdc consumable` and it's tracked like everything else.
- **Your own spells.** Untick any default spell, or add your own in Settings.
- **Its own settings window.** It never gets in the way of your spellbook.

## Tracked cooldowns

- **Retail (29):** Rallying Cry, Aura Mastery, Lay on Hands, Blessing of Protection, Guardian Spirit, Pain Suppression, Power Word: Barrier, Leap of Faith, Anti-Magic Zone, Raise Ally, Heroism, Bloodlust, Spirit Link Totem, Ancestral Protection Totem, Healing Tide Totem, Time Warp, Ice Block, Demonic Gateway, Revival, Life Cocoon, Tranquility, Rebirth, Innervate, Darkness, Rewind, Rescue, Zephyr, Time Dilation, Fury of the Aspects
- **MoP Classic (32):** Rallying Cry, Devotion Aura, Lay on Hands, Hand of Protection, Hand of Sacrifice, Hand of Salvation, Guardian Spirit, Pain Suppression, Power Infusion, Power Word: Barrier, Divine Hymn, Hymn of Hope, Vampiric Embrace, Anti-Magic Zone, Raise Ally, Heroism, Bloodlust, Spirit Link Totem, Healing Tide Totem, Stormlash Totem, Time Warp, Revival, Life Cocoon, Tranquility, Rebirth, Innervate, Ironbark, Stampeding Roar, Soulstone, Avert Harm, Demoralizing Banner, Skull Banner
- **TBC Anniversary (17):** Shield Wall, Challenging Shout, Lay on Hands, Blessing of Protection, Divine Intervention, Power Infusion, Pain Suppression, Lightwell, Shadowfiend, Heroism, Bloodlust, Mana Tide Totem, Misdirection, Soulstone Resurrection, Innervate, Rebirth, Tranquility
- **Classic Era (12):** Shield Wall, Challenging Shout, Lay on Hands, Blessing of Protection, Divine Intervention, Power Infusion, Lightwell, Mana Tide Totem, Soulstone Resurrection, Innervate, Rebirth, Tranquility
- **WoW: Forever (12):** the same twelve as Classic Era, with Forever's own timers (Lay on Hands is 20 minutes, Shield Wall is 15 minutes)

Every rank of a spell counts on Classic Era, TBC Anniversary and WoW: Forever. Each client also tracks its own flask and food buffs.

## Works with CooldownTimeline3

CooldownCollaborator works with my other addon, **CooldownTimeline3** (CDTL3), on every client both of them support. When both are loaded, it adds a timer type called **Group cooldowns** to CDTL3.

- Every tracked cooldown, yours and your group's, shows up as an icon with a countdown on a CDTL3 lane. It goes away when the cooldown ends or the player reports it ready.
- Icons go to Lane 1. To pick another lane, or turn them off, open CDTL3 and go to **Filters › Defaults › Group cooldowns**.
- To see whose icon is whose, turn on **Caster lane** in CDTL3 under **Lanes › (your lane) › General**. Names show in class colour under the icons.
- In CooldownCollaborator's settings, the **Show group cooldowns on CooldownTimeline3's lanes** box turns this on or off. It only shows up when CDTL3 is loaded.
- CooldownCollaborator works just fine without CDTL3.

## Getting started

1. Install CooldownCollaborator. On Retail and WoW: Forever, get your group to install it too.
2. Join a party or raid. The panel shows up on its own. Type `/cdc` to show or hide it.
3. Drag the panel where you want it, then type `/cdc lock`.
4. Type `/cdc settings` to pick which spells to track and change the size and opacity.
5. Want the icons on CooldownTimeline3? Just install it. There's nothing else to do, since the box in the settings is on by default.

## Slash commands

- `/cdc` shows or hides the panel
- `/cdc lock` and `/cdc unlock` lock or unlock its position
- `/cdc reset` puts the panel back where it started
- `/cdc settings` opens the settings window
- `/cdc essentials` shows or hides the Essentials Bar
- `/cdc lanes` shows or hides the Lane View
- `/cdc roster` lists who can bring which raid resource
- `/cdc rez` asks for a Battle Rez on your dead target (leader or assist only)
- `/cdc consumable <spellID> <seconds> <name>` registers a Cauldron or Feast style buff
- `/cdc verbose` turns on detailed logging, for tracking down problems
- `/cdc debug` prints every tracked cooldown and the group state

## Bugs and requests

Found a bug, or want a spell added? Open an issue at https://github.com/Nelnamara/CooldownCollaborator/issues and tell me which class and spell you mean.

## Changelog

### 1.1.1
- Fixed: you don't show as a ready Battle Rez or Bloodlust before you've learned it. Groupmates who haven't hit the level for it yet don't show either, and they pop in once they ding
- Fixed: the Lane view opens when you join a group, if you've turned it on. Turn it on while solo and `/cdc lanes` tells you it shows up once you're in a group

### 1.1.0
- One download now covers Retail, MoP Classic, TBC Anniversary, Classic Era and WoW: Forever
- Each client tracks its own spell list, with every rank on Classic Era, TBC Anniversary and WoW: Forever
- On Classic Era, TBC Anniversary and MoP Classic, other players' casts are read from the combat log, so your groupmates don't need the addon for their cooldowns to show
- No Bloodlust or Heroism lane on Classic Era and WoW: Forever, since they have neither
- Flask and food status on every client
- Works with CooldownTimeline3 on every client. Group cooldowns can show on CDTL3's lanes (a box in Settings, on by default when CDTL3 is loaded)
- Ready-now announcements. When your own tracked spell comes off cooldown it tells the group, so talent-shortened cooldowns don't show long on other people's screens anymore (older versions just ignore it)
- Players are tracked by name and realm, so two players with the same name from different realms don't get mixed up
- Fixed: Evoker Fury of the Aspects is tracked again (it had the wrong spell ID)
- Fixed: the Battle Rez charge timer reads the right value
- Fixed: Anti-Magic Zone is 4 minutes
- Fixed: a sync that went through doesn't get sent again, and one the game refused gets retried for about half a minute
- Fixed: the minimap button sits on the edge of WoW: Forever's bigger minimap, and stays there if the minimap is resized
- Fixed: `/cdc consumable` saves a `flask` or `food` at the end as the category
- Fixed: sync uses instance chat in instance groups
- Interface 120105 (Retail 12.1.5)

### Older versions

The full history is in the README on GitHub: https://github.com/Nelnamara/CooldownCollaborator
