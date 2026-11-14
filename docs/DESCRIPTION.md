# CooldownCollaborator

A live, shared view of your group's big defensive and utility cooldowns. See who has Bloodlust, a Battle Rez, a raid cooldown, and how long until it is back. Works in 5-man parties and full raids, and switches layout for you.

**Both players need the addon.** CC shares each player's own casts with other CC users. A player without CC cannot be seen by it.

## What it does

- **Cooldown panel.** 29 tracked spells across 11 classes in one draggable list, with live countdowns and class colours.
- **Roster scan.** Knows who can bring Bloodlust, Heroism, Time Warp, Fury of the Aspects or a Battle Rez before anyone casts anything.
- **Essentials Bar.** A slim bar with just those raid-wide resources, plus a flask and food count for the group.
- **Lane View.** Icons slide along a bar from "just used" to "ready".
- **Request Rez.** Raid leader or assist (or party leader) targets a dead player and announces which Battle Rez is ready, by name.
- **Ready-now announcements.** When your own spell comes off cooldown, your client tells the group, so talent-shortened cooldowns do not show long on other screens.
- **Cauldron and Feast tracking.** Register a shared buff once with `/cdc consumable`.
- **Your own spells.** Untick any default spell, or add your own in Settings.
- **Its own settings window.** It never blocks your spellbook.

## Works with CooldownTimeline3

CC works together with the addon **CooldownTimeline3** (CDTL3). When both are loaded, CC adds a timer type called **Group cooldowns** to CDTL3.

- Each tracked cooldown, yours and your group's, shows as an icon with a countdown on a CDTL3 lane. It leaves when the cooldown ends or is reported ready.
- Icons go to Lane 1 by default. To pick another lane, or switch them off, open CDTL3 and go to **Filters > Defaults > Group cooldowns**.
- To see who owns each icon, turn on **Caster lane** in CDTL3 under **Lanes > (your lane) > General**. Names show in class colour under the icons.
- In CC's settings, the checkbox **Show group cooldowns on CooldownTimeline3's lanes** turns this on or off. It only appears when CDTL3 is loaded.
- CC works fine without CDTL3.

## Getting started

1. Install CooldownCollaborator. Ask your group to install it too.
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

### Next release
- Ready-now announcements: when your own tracked spell comes off cooldown it tells the group, so talent-shortened cooldowns no longer show long on other clients (older clients ignore it)
- Players are keyed by name and realm, so same-named players from different realms no longer clash
- Works with CooldownTimeline3: group cooldowns can show on CDTL3's lanes (Settings checkbox, on by default when CDTL3 is loaded)
- Interface 120105 (Retail 12.1.5)
