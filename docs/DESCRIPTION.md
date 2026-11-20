# CooldownCollaborator

A live, shared view of your group's big defensive and utility cooldowns. See who has Bloodlust, who has a Battle Rez, who has a raid cooldown, and how long until each one is back. It works in 5-man parties and full raids, and switches its layout for you.

One download covers Retail 12.1.5, MoP Classic 5.5.4, TBC Anniversary 2.5.6, Classic Era 1.15.9 and WoW: Forever 1.60.1. Each client tracks its own spell list.

**On Retail and WoW: Forever, both players need the addon.** The game hides other players' casts there, so CooldownCollaborator shares each player's own casts with everyone else who runs it. If someone doesn't have it, it can't see them.

**On Classic Era, TBC Anniversary and MoP Classic, your groupmates don't need it for their cooldowns to show.** It reads their casts from the combat log. Ready-now announcements and flask and food status still only come from players who have it.

**Please try it in your groups!** Most of this is new since 1.1.1, on every client. Testing in all kinds of groups (dungeons, raids, battlegrounds, with friends who run it too) is encouraged and really appreciated. Let me know what you see, good or bad, at https://github.com/Nelnamara/CooldownCollaborator/issues.

## What it does

- **Cooldown panel.** Every tracked spell in one list you can drag around, with live countdowns and class colours. Running cooldowns come first, and ready ones fold into one line per spell. From 10 players it uses two columns. Dead and offline players are greyed with a mark, a ? means a guess, and dots by each name show who runs the addon. Hover a row for the game's spell tooltip. Click a row to ask that player for the spell. Teams (a list of players you pick) get their own tabs, and a Guild tab shows up if you turn guild sharing on. An icon style is there if you like icons better than text.
- **Roster scan.** It knows who can bring Bloodlust, Heroism, Time Warp, Fury of the Aspects or a Battle Rez before anyone casts anything. Classic Era and WoW: Forever have no Bloodlust or Heroism, so there's no lust lane there.
- **Essentials Bar.** A slim bar with those raid-wide resources: the first few ready providers, then "+N". It also shows Battle Rez charges, Soulstones, world buffs and a flask and food count for the group. It copes with a full raid.
- **Lane View.** Icons slide along a bar from "just used" to "ready". Ready providers line up in a row under each lane. `/cdc nexthit` sets a time, and a gold ring marks what will be back by then.
- **Request Rez.** The raid leader or an assist (or the party leader, or anyone in a 5-man) targets a dead player, and it announces which Battle Rez is ready, by name. When the raid's rez charges are gone it says so, and when the next one is back.
- **Dead list.** A window that opens when someone dies in combat. It lists the dead in the leader's order, with a Call button each and who would answer.
- **Externals strip, mana strip and burst line.** Externals show with their owner and time left. Mana spells show how many are ready, with an Ask button anyone can press. The burst line puts your big cooldowns above the group's lust and Power Infusion, with a gold band where they meet.
- **Ready alerts.** A sound, a flash on the row, an icon mid screen, or a warning a few seconds before, set per spell.
- **Plans and rotations.** A leader writes a raid plan (a spell used at a boss timer or a time into the fight) and shares it with the group. You get a prompt bar on your own planned uses from BigWigs or DBM timers. A rotation order (who goes first for a spell) shows as numbers on the rows.
- **Show presets.** Everything, Simple, Healer, Tank or DPS, so the list only shows what you want. Everything is the default.
- **Profiles and officer setups.** Save your whole setup under a name, export and import it, and let a character follow a profile. A guild officer can send a setup, and members see a box and choose Accept, Not now or Never.
- **Guild sharing.** Off by default. Turn it on and your cooldowns go out on the guild channel, and the panel gets a Guild tab.
- **Pulls and keys.** `/cdc lastpull` shows the last pull's log and `/cdc post` posts who is ready to the raid. When a key starts, it can ask the group for its cooldowns again.
- **Ready-now announcements.** When your own spell comes off cooldown, your client tells the group, so talent-shortened cooldowns don't show long on everyone else's screen.
- **Cauldrons and Feasts.** Register a shared buff once with `/cdc consumable` and it's tracked like everything else.
- **Your own spells.** Untick any default spell, or add your own in Settings.
- **Its own settings window.** It never gets in the way of your spellbook. It has six tabs: Getting Started, Display, Lists, Spells, Plans and Profiles. You can switch each window on or off, show them only in combat or at a boss, skip certain rezzers, and turn on a lighter mode that refreshes less often.
- **Translations.** Every word in the addon goes through a phrase table, ready for German, Spanish, Latin American Spanish, French, Italian, Korean, Portuguese, Russian and Chinese. A language shows in English until someone translates it, and that is done on CurseForge.
- **For other addons.** A small public feed lets other addons read who has which cooldown and when it's back.

## What it sends to your group

It sends hidden addon messages. No player sees them in chat. They go to your party, raid or instance group only, and to your guild only if you switch guild sharing on.

They carry:
- your own cooldowns and when they're ready
- your flask, food and buff status
- your addon version
- battle rez charges
- where you placed a Soulstone
- plans and rotations a leader shares
- setups an officer sends

Nothing goes outside the game. There's no chat spam. The only lines anyone sees are the rez call, asks you click, and posts you choose.

## Tracked cooldowns

Every one has a kind (battle rez, lust, raid cooldown, external, mana, personal defensive or utility), and the presets use it.

- **Retail (43):** Rallying Cry, Shield Wall, Last Stand, Challenging Shout, Aura Mastery, Lay on Hands, Blessing of Protection, Blessing of Sacrifice, Intercession, Guardian of Ancient Kings, Ardent Defender, Guardian Spirit, Pain Suppression, Power Word: Barrier, Leap of Faith, Power Infusion, Anti-Magic Zone, Raise Ally, Icebound Fortitude, Vampiric Blood, Harrier's Cry, Heroism, Bloodlust, Spirit Link Totem, Ancestral Protection Totem, Healing Tide Totem, Time Warp, Ice Block, Soulstone, Revival, Life Cocoon, Fortifying Brew, Tranquility, Rebirth, Innervate, Survival Instincts, Darkness, Metamorphosis, Rewind, Rescue, Zephyr, Time Dilation, Fury of the Aspects
- **MoP Classic (41):** Rallying Cry, Skull Banner, Demoralizing Banner, Mocking Banner, Shield Wall, Last Stand, Lay on Hands, Hand of Protection, Hand of Sacrifice, Hand of Salvation, Devotion Aura, Guardian of Ancient Kings, Ardent Defender, Power Word: Barrier, Divine Hymn, Hymn of Hope, Vampiric Embrace, Guardian Spirit, Pain Suppression, Power Infusion, Anti-Magic Zone, Raise Ally, Icebound Fortitude, Vampiric Blood, Bloodlust, Heroism, Spirit Link Totem, Healing Tide Totem, Stormlash Totem, Time Warp, Soulstone, Revival, Life Cocoon, Avert Harm, Fortifying Brew, Tranquility, Ironbark, Innervate, Rebirth, Stampeding Roar, Survival Instincts
- **TBC Anniversary (23):** Shield Wall, Challenging Shout, Last Stand, Lay on Hands, Divine Intervention, Blessing of Protection, Power Infusion, Pain Suppression, Shadowfiend, Lightwell, Fear Ward, Bloodlust, Heroism, Mana Tide Totem, Earth Elemental Totem, Reincarnation, Misdirection, Soulstone Resurrection, Innervate, Rebirth, Tranquility, Challenging Roar, Goblin Sapper Charge
- **Classic Era (16):** Shield Wall, Challenging Shout, Last Stand, Lay on Hands, Divine Intervention, Blessing of Protection, Power Infusion, Lightwell, Mana Tide Totem, Reincarnation, Soulstone Resurrection, Innervate, Rebirth, Tranquility, Challenging Roar, Goblin Sapper Charge
- **WoW: Forever (17):** the same sixteen as Classic Era, plus Fear Ward, with Forever's own timers (Lay on Hands is 20 minutes, Shield Wall is 15 minutes)

Every rank of a spell counts on Classic Era, TBC Anniversary and WoW: Forever. Each client also tracks its own flask and food buffs. World buffs, protection potions and elixirs are counted for the group.

**Combat rez providers**
- Retail: Rebirth, Raise Ally, Intercession and Soulstone
- MoP Classic: Rebirth, Raise Ally and Soulstone
- Classic Era, TBC Anniversary and WoW: Forever: Rebirth. Soulstone is tracked there, but it's a stone you place beforehand.

On Retail, every combat rez draws from the raid's one pool of charges. With none left nobody can be rezzed until one comes back, and the bar and Request Rez say so.

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
4. Type `/cdc settings`. The Getting Started tab walks you through it. Pick a show preset, choose which spells to track, and change the size and opacity.
5. Want the icons on CooldownTimeline3? Just install it. There's nothing else to do, since the box in the settings is on by default.

## Slash commands

- `/cdc` shows or hides the panel
- `/cdc lock` and `/cdc unlock` lock or unlock the windows
- `/cdc reset` puts the panel back where it started
- `/cdc settings` opens the settings window
- `/cdc essentials` shows or hides the Essentials Bar
- `/cdc lanes` shows or hides the Lane View
- `/cdc nexthit <seconds or M:SS>` sets the Lane View's look-ahead, and `/cdc nexthit off` clears it
- `/cdc roster` lists who can bring which raid resource
- `/cdc rez` calls a Battle Rez on your dead target. With nobody targeted it calls the top of the dead list
- `/cdc lastpull` shows the last pull's log
- `/cdc post` posts who is ready to the raid
- `/cdc report` opens a box with what to paste into a new issue on GitHub
- `/cdc consumable <spellID> <seconds> <name>` registers a Cauldron or Feast style buff, and `/cdc consumable remove <spellID>` removes it
- `/cdc verbose` turns on detailed logging, for tracking down problems
- `/cdc debug` prints every tracked cooldown and the group state

## Bugs and requests

Found a bug, or want a spell added? Open an issue at https://github.com/Nelnamara/CooldownCollaborator/issues and tell me which class and spell you mean.

## Changelog

### Next version
- New main panel: running cooldowns first, ready ones folded per spell, two columns from 10 players, greyed dead and offline players, spell tooltips, click a row to ask, team tabs, rotation numbers and an icon style
- New windows and strips: a dead list with a Call button each, an externals strip, a mana strip anyone can Ask from, and a burst line
- The Essentials Bar shows the first few providers then "+N", with Battle Rez charges, Soulstones and world buffs. A big raid no longer breaks it
- Lane View: ready providers line up under each lane, and `/cdc nexthit` rings what will be back
- Ready alerts per spell: a sound, a flash, an icon mid screen or an early warning
- Raid plans and rotation order a leader can share, with prompts from BigWigs or DBM timers
- Show presets (Everything, Simple, Healer, Tank, DPS), plus profiles, export and import, and setups an officer can send
- Guild sharing, off by default, with a Guild tab
- Settings has six tabs and a Getting Started page. Windows can show only in combat or at a boss, you can skip rezzers, and there's a lighter mode
- Warlocks count as Battle Rez providers on Retail and MoP (Soulstone). Paladins and Marksmanship hunters count too, and Retail tracks Intercession
- Request Rez says when the raid's rez charges are gone and when the next one is back. Soulstones you place are shared
- Many more tracked spells on every client. Retail's older cooldowns and icons match 12.1.5, and Demonic Gateway is no longer tracked
- Group sync is gentler and fills in joiners and /reloads. Old copies of the addon still work
- New commands: `/cdc lastpull`, `/cdc post`, `/cdc support` and `/cdc nexthit`
- Translation support, with a phrase table for ten languages besides English
- A public feed for other addons
- Fixed: windows close when you leave the group
- Fixed: Request Rez uses the group's own channel and only names a dead friendly player
- Fixed: the flask and food count no longer counts you twice in a raid

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
