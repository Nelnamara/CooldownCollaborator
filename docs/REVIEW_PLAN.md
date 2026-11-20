# Review plan (18 Nov 2026)

The plan of record for the 18 Nov red team and feature panel. All 81 cards are marked Go on the
Collaborator Review List (https://claude.ai/artifact/LKvL23ka5LFhQFXHkY4fUX). The cards and their
numbers are in `docs/reviews/2026-11-18-red-team.md` (R1 to R33) and
`docs/reviews/2026-11-18-feature-panel.md` (P1 to P48). Nothing is dropped; every card is in a round below.
Builds start from the `rez-fix-tidy` branch (1.1.1 plus the tidy), which still waits for its boop.

## His notes on the list (18 Nov)

- P2, presets by role: "Should be able to choose this option". Presets are a choice in Settings; Everything
  stays the default.
- R16, Request Rez in Dungeon Finder: "WHOA - This addon spams instance chat? As in the dungeon zone global
  chat or the actual raid chat". Answered: instance chat is the group's own channel in Dungeon Finder, Raid
  Finder and battlegrounds (`/i`), never zone or global chat. The cooldown sync uses hidden addon messages
  that no player sees; the only visible line is Request Rez, when the leader presses it.
- R20, Lane view icons piling out of the window: "We should review the frames design. to be better scaled for
  raids etc." That makes the windows a design step (round 2).

## Round 1: the crash and the solo windows (a 1.1.2 if he wants it out first)

R1 (Essentials bar overflow: Lua error in raids, and the /reload start-up failure) and R18 (windows stay up
after leaving the group). Guard, not the redesign: the bar stops at what fits and never errors; leaving the
group hides all three windows.

## Round 2: look board for the windows at raid scale

Several choices per window, each drawn at 5, 20 and 40 players: the main panel, the Essentials bar and the Lane
view (R2, R19 to R22, R24 to R26 and R32 live here, and P21 party and raid layouts), plus every new on-screen
piece from the panel: P9 icon-only look, P5 greyed dead or offline owners, P3 dead list, P6 defensives tile,
P7 ready check summary, P20 hover text, P22 "You're the rez", P24 mana strip, P25 next-hit marks, P26 next
lust, P27 lust and Sated timers, P29 burst planner, P32 externals strip, P14 Getting Started tab with P23 the
CDTL3 link, P12 plan editor, P39 rotation order, P43 raid team filter, P41 guild view, P46 to P48 Classic
strips. Building these waits for his picks.

## Round 3: everything that changes no look (alongside round 2)

- Message format 2 first (one schema step): a hello with version, a state request for joiners and reloads,
  several cooldowns per message with small random delays, old 1.0 and 1.1 copies still understood. Then:
  P13 who runs it, P16 late joiner and saved timers, P35 gentler sending, P44 guessed marks, P11 battle rez
  charges shared, P41 guild channel, P42 officer setup, P15 profiles and export, P34 public feed, P12 plan
  sharing, P39 order sharing.
- Red team sync, rez and settings fixes: R4 to R17, R23, R27 to R31, R33.
- Data: R3 Intercession and Harrier's Cry, P18 tank cooldowns and Classic tools, P28 Retail Power
  Infusion, P32 Blessing of Sacrifice, R14 Stampeding Roar forms, R13 the two Classic spells CDTL3 drops.
- Behaviour: P1 sounds and flashes, P2 kinds and presets, P4 missing-provider warning, P8 click to ask,
  P10 active externals, P19 support box, P30 combat or boss only, P31 lighter mode, P33 last pull log,
  P38 post to raid chat, P40 rezzers to skip, P45 key-start reset, P17 flask by name, P47 world buffs.
- P36 translations: CurseForge localization is already on for Collaborator's project (his word, 18 Nov:
  "Translation is already on"), so it's code only: AceLocale-style phrase table and the packager's
  `--@localization(...)@` lines, as CDTL3 does.
- P37 store page: the "what it sends to the group" line goes in docs/DESCRIPTION.md, and Collaborator gets a
  Wago project (18 Nov: he first asked "WTF we need a wago project for.", then "Our stats for CDTL say
  otherwise"). The project already existed (Wago ID `b6XyoxKp`, 0 downloads on 18 Nov); the ID is in the
  unsuffixed, `_Camelot` and `_Mainline` TOCs since 00b5ce4, and he added the `WAGO_API_KEY` secret on 18 Nov,
  so the next release uploads to Wago too. Done.

## Combat rez rules (his words, 19 Nov)

"a soul stone and raise ally still count as a combat rez", and on Retail: Soulstone can be placed on a living
ally beforehand or cast on a dead player in combat; Raise Ally works for every Death Knight spec from level 19;
in raids and Mythic+ every combat rez (Rebirth, Intercession, Raise Ally, Soulstone) draws from one shared
charge pool, and with no charges left nobody can be rezzed, a placed Soulstone included, until a charge comes
back. What the build does with that:
- Warlocks are Battle Rez providers on Retail and MoP (Soulstone cast on the dead). Era, TBC and Forever keep
  Soulstone tracked only (a stone placed beforehand).
- P46 (who has a Soulstone) and P48 (every way back) apply on Retail too. Other players' buffs are hidden there
  in combat, so the warlock's client says who it stoned (a message-format-2 kind).
- At zero charges the Essentials bar and Request Rez say "no charges, next in M:SS" instead of naming a rezzer,
  and a placed stone shows as waiting on a charge (P11 and the charges message).

## Build order (his "Gooooooooo.", 18 Nov)

Worktrees under `source\repos\cc-wt\`, each cut from `rez-fix-tidy`:
1. Now: `crash-fix` (round 1: R1, R18), `review-data` (R3, R13, R14, P18, P28, P32 and the spec rule for
   Harrier's Cry), `review-fixes` (R16, R17, R23, R24, R26 to R31, R33) and the look board
   (`tools/look-board/index.html`, published for his picks).
2. Then, on an integration branch with those merged: the sync lane on `docs/MESSAGE_FORMAT_2.md` (R4 to R12,
   R15, P11 data, P13 data, P16, P35, P44 data).
3. Then two lanes: behaviour (P1 sounds, P2, P4 chat line, P8, P10 data, P19, P30, P31, P33, P38, P40, P45) and
   format-2 features (P12 and P39 sharing, P15, P34, P41 data, P42).
4. After his look picks: the window and new-piece builds (round 2 list).
5. Last, once the code has settled: P36 translations, then docs (DESCRIPTION, README, CHANGELOG, CLAUDE.md).

## Look picks (19 Nov, Collaborator Looks board https://claude.ai/artifact/QdvWKQfJxWYo86vZjc8MXc)

Every item picked, none "None of these". The drawings are in `tools/look-board/index.html` (section id = item).
- Windows: main panel Running first, with his note "Running First + Two columns" (both together); Essentials bar
  Top three, then +N; Lane view Ready row under each lane; layouts Party and raid, by themselves.
- Pieces: icon look Icon row; dead or offline Greyed with a mark; dead list Dead list window; defensives tile
  Pips; ready check Banner on the bar; missing lust or rez Count on the heading; ready flash Row flash, plus his
  note "Icon mid screen as additional option"; active external Effect bar on the row; guessed Question mark;
  who runs it Marks by each name; hover Game tooltip plus a line; you're the rez Line at the top; mana Icon strip
  with Ask, his note "Anyone should be able to ask for the mana spell especially the one in need"; next hit
  Rings, no line; next lust In the panel's title; lust and Sated Two bars; burst Shared time line; externals
  Icon strip; Getting Started Window pictures; plan Boss timer rows; rotation Numbers on the rows; raid team Team
  tabs; guild view Guild tab on the panel; Soulstones Line on the bar; world buffs Who lacks it; every way back
  Icons by kind; Battle Rez charges Pips.

## Status (19 Nov)

Steps 1 and 2 are done and merged on `review-build` (worktree `cc-wt/build`): round 1, the fixes, the spell data
(Retail corrected to 12.1.5, Demonic Gateway dropped, Soulstone a rez provider on Retail and MoP) and the sync
lane (format 2 with H, Q, S, C and T kinds). Full suite 18 RESULT lines, all green.

Picks are in, so step 3 and step 4 are regrouped by file, three look lanes at once from `review-build`:
- `look-panel`: the main panel picks, Tooltip.lua, Alerts.lua (P1), click to ask (P8), the guild channel
  (P41), team tabs (P43), rotation numbers (P39), next lust in the title (P26), and `kind` / `effect` on the
  Data rows.
- `look-essentials`: the Essentials bar picks, P4, P7, P11, P17, P22, P27, P46, P47, P48, the defensives tile (P6).
- `look-lanes`: the Lane view pick, next-hit rings (P25), and the new windows: dead list (P3), externals (P32),
  mana with Ask for anyone (P24), burst (P29), the plan runtime (P12).
Then one settings lane (Options.lua): Getting Started window pictures (P14, P23), presets and kinds (P2), every
new setting's control, the plan and rotation editors, teams, rezzers to skip (P40), combat or boss only (P30),
lighter mode (P31), profiles and export (P15), officer setups (P42), the support box (P19), layouts (P21), the
last pull log (P33), post to raid chat (P38), key-start reset (P45), the public feed (P34), and the Sapper row.
Then translations (P36), docs, the walk.

## Settings pass picks (19 Nov, after his walk "Not impressed.")

Board: Collaborator Settings Looks https://claude.ai/artifact/4ra62cPHKZjGbMcwxnpk98 (`tools/look-board/settings.html`,
picks in its db collection `picks`). His notes in quotes.
- Getting Started: Pick and see, plus the tour: "Pick and see + 3 step tour (Or more steps since there are multiple windows)".
- Choosing spells: Role cards, headed "Your role" (Simple renamed Basics): "Role cards + ticks by kind if desired".
- Alert sound: Dropdown and Test: "More sound options" (CDTL3's checked Blizzard sound list, Media.lua).
- Profiles: like every Ace addon (Reset, Current profile, New, Copy from, Delete; every character starts on Default).
- Button rows: buttons sized to their words, wrapping.
- Bell: Speaker icon (opens the spell's alert box, which holds the sound dropdown: "Sound picker?").
- /cdc support: Report a problem (`/cdc report`, plain sentences, where to paste it, button on Getting Started).
- Window places: the main panel, Essentials bar and Lane view start joined and move together.
Plain fixes in the same lane: Rebirth tooltip shows the rank the player has, plain words in /cdc roster, no Guild tab
with guild sharing off, and why the Lane view landed on the main panel.

## Then

One walk of everything, a review pass, and the release on his boop.

Built on review-build (19 to 20 Nov, on the Mac): the plain fixes, the Settings controls, the joined windows and
Getting Started with the tour, in four lanes; then one full suite and a re-walk on his Forever install.
