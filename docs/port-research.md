# CooldownCollaborator (CC) port research: Retail-only to Era / TBC / MoP / WoW: Forever

Read-only research. Nothing in the CC or CDTL3 repos was edited. Sources: CC repo (`catch-up`, v1.0.4, every .lua + TOC + CLAUDE.md), cdtl3-dev (CLAUDE.md, CDTL3.lua Compat/retailAPI/isForever, Helpers.lua readers, Group.lua RAID/BURST, Data.lua foreverChanges, TOCs, release.yml, .pkgmeta), and the spell-list-check cache (builds: Era 1.15.9.70576, Forever 1.60.1.70888, TBC 2.5.6.70577, MoP 5.5.4.70631, Retail 12.1.5.70783). I queried the SpellName / SpellCooldowns / SkillLineAbility / Talent tables directly with a script (scratchpad scan.py).

Honesty note: the warcraft.wiki.gg fetches I could do returned thin per-flavor detail (the tool summarizes pages). Where a per-client fact comes from CDTL3 ground truth it says "CDTL3". Where I could not confirm it, it is marked UNVERIFIED, with the in-game check that settles it.

---------------------------------------------------------------------------------------------------

## A. API inventory

Legend: ok = works unchanged; FIX = needs a change; UNV = unverified, needs one in-game check.
Client columns: Era 1.15.9 / TBC 2.5.6 / MoP 5.5.4 / Forever 1.60.1.

Detection pattern to copy from CDTL3.lua:15-36: `tocversion` for content (spell lists), `retailAPI = tocversion >= 110000 or isForever` for API choice (isForever = 16000..16999). Never branch API on tocversion alone (Forever reports 16xxx but has the modern engine).

### A1. Calls that break or misbehave (ranked by severity)

| # | API / code (file:line) | Era | TBC | MoP | Forever | What to do |
|---|---|---|---|---|---|---|
| 1 | `GetSpecialization()` unguarded, Roster.lua:120 (inside QueueInspectAll, called from ScanRoster on every GROUP_ROSTER_UPDATE and at Init) | FIX: nil global, hard error | FIX: same | ok (exists) | FIX: no specs; no deprecation fallbacks | Guard with CDTL3's `HasSpecs` pattern (Helpers.lua:1817: tocversion < 50000 -> no specs; then `(C_SpecializationInfo and .GetSpecialization) or GetSpecialization`). Simplest: skip the whole inspect pipeline on Era/TBC/Forever. Spec is only used for the `/cdc roster` printout and a never-read `info.spec` (comment says Evoker/Augmentation); capabilities are class-based. |
| 2 | `C_Spell.GetSpellCooldown` / `GetSpellCharges` + `cd.isActive`, CooldownCollaborator.lua:343-395 (GetLocalReadiness, LocalSpellIsReady) | FIX | FIX | FIX | ok (modern engine; isActive is 12.0.1 and in the Forever API; pcall already in place) | `isActive` is a 12.0.1 field. On a classic table it is nil, so `LocalSpellIsReady` returns `not nil` = true always and `GetLocalReadiness` returns 0 always: every own spell reads "ready", and PollLocalReady (line 399) would announce a false "ready now" 3 s after every cast. CDTL3 deliberately avoids `C_Spell` cooldown/charge on non-retailAPI clients (Helpers.lua:1002-1037, 1070-1137) and calls legacy `GetSpellCooldown(id)` -> start, duration, enabled and `GetSpellCharges`. Copy that: if `retailAPI` use C_Spell (isActive), else legacy `start+duration-GetTime()`, treating duration <= 1.5 as GCD. |
| 3 | UNIT_SPELLCAST_SUCCEEDED spellID is rank-specific, Events.lua:7, CooldownCollaborator.lua:445-457 | FIX | FIX | ok (no ranks) | FIX (ranks; CDTL3 CLAUDE.md "ranked spells on Forever") | `CC.SpellData[spellID]` keyed by one ID misses every other rank. Add a rank map (`rankToBase[rankID] = baseID`) built at load from a `ranks = {..}` field, and send the BASE id on the wire so peers with different ranks agree. CDTL3 also matches by spell NAME for the same reason (Group.lua:187). |
| 4 | `IsSpellKnownOrOverridesKnown` / `IsSpellKnown`, CooldownCollaborator.lua:347-348 | FIX (rank-1 id false if you only know rank 3) | FIX (same) | ok | FIX: both globals are nil (no deprecation fallbacks), so `known` stays false and GetLocalReadiness silently returns nil forever | Use `CDTL3.Compat`-style resolver (CDTL3.lua:52-75): `IsSpellKnown` if present else `C_SpellBook.IsSpellKnown(id, Enum.SpellBookSpellBank.Player)`; `C_SpellBook.IsSpellKnownOrInSpellBook(id, bank, true)`. For ranked spells test any id in the `ranks` list. |
| 5 | `C_ChatInfo.AreOutgoingAddonChatMessagesRestricted()` unguarded, Comms.lua:43 (only in the verbose print) | FIX (nil call when /cdc verbose is on) | FIX | FIX | UNV | Retail 12.x only. Guard `if C_ChatInfo.AreOutgoingAddonChatMessagesRestricted then`. |
| 6 | `C_ChatInfo.SendAddonMessage` return handling, Comms.lua:48-50, 71-73, Consumables.lua:184 | FIX | FIX | FIX | UNV | Code treats ANY truthy result as failure and requeues (`if result then`). Retail returns an `Enum.SendAddonMessageResult` number where 0 = Success; 0 is truthy in Lua, so even retail would requeue every send forever unless it returns nil on success (UNV which; the comment says "nil/0 == success", the code does not do that). Classic builds historically return nothing or a boolean true. Normalize: `local ok = (result == nil or result == true or result == 0 or (Enum and Enum.SendAddonMessageResult and result == Enum.SendAddonMessageResult.Success))`. Test: send in a party and watch /cdc verbose for repeated "sync send attempt". |
| 7 | `C_UnitAuras.GetPlayerAuraBySpellID`, Consumables.lua:126,145 | UNV | UNV | UNV | ok (modern) | CDTL3 confirms the Classic clients have `C_UnitAuras.GetAuraDataByIndex` (Helpers.lua:1200); `GetPlayerAuraBySpellID` I could not confirm there. Fallback: `C_UnitAuras.GetAuraDataBySpellName` / `AuraUtil.FindAuraByName` / `UnitBuff` loop, which are READABLE on Era/TBC/MoP (not secret), so classic consumable tracking can match by NAME. On Forever keep the ID lookup (auras are secret). See C. |
| 8 | `Settings.RegisterCanvasLayoutCategory` / `RegisterAddOnCategory` / `category.ID`, Options.lua:585-587 (runs in Init, any error aborts Init) | UNV | UNV | UNV | ok | CDTL3 sidesteps it (AceConfig AddToBlizOptions launcher, CDTL3.lua:1491 comment). Guard: `if Settings and Settings.RegisterCanvasLayoutCategory then ... elseif InterfaceOptions_AddCategory then InterfaceOptions_AddCategory(panel) end`. The addon already has `/cdc settings` and the minimap button, so the Blizzard panel can be skipped on any client where it errors. |
| 9 | Inspect pipeline: `NotifyInspect`, `INSPECT_READY`, `GetInspectSpecialization`, `ClearInspectPlayer`, `CheckInteractDistance`, Roster.lua:143-187, event registered CooldownCollaborator.lua:434 | exists but useless (no specs; `GetInspectSpecialization` already guarded by `and`) | same | ok (specs exist) | FIX/skip | Drop on Era/TBC/Forever; keep on MoP only if the spec label is wanted. Removes inspect throttle noise. |
| 10 | Remote casts: UNIT_SPELLCAST_SUCCEEDED for party/raid tokens (Events.lua:7; handler only accepts "player", line 455) | spellID readable (not secret), but whether the client fires the event for OTHER units is UNV | same UNV | same UNV | SECRET (modern engine, same as Retail) | See A3. Era/TBC/MoP: add the combat-log path (CDTL3's pattern). Forever: comm-only, exactly like Retail. |
| 11 | `COMBAT_LOG_EVENT_UNFILTERED` | open | open | open | CLOSED (CDTL3.lua:27-32, 3092-3099) | New code, A3. |
| 12 | `BackdropTemplate` as a literal template string + `SetBackdrop`, UI.lua:32,41; Essentials.lua:24,32; Lanes.lua:16,24; Options.lua:218,423 | ok (BackdropTemplateMixin exists on modern-engine Classics; CDTL3 still guards) | same | same | ok | Cheap hardening: `BackdropTemplateMixin and "BackdropTemplate" or nil` (CDTL3 Holders.lua:68 etc.). |
| 13 | `C_Spell.GetSpellInfo` / `GetSpellInfo`, CooldownCollaborator.lua:144-150, Options.lua:58-72 | ok (guarded, legacy global fallback) | ok | ok | name -> id lookup path (Options.lua:58 `GetSpellInfo(text)`) dead: no global; `C_Spell.GetSpellInfo` accepts a name on modern engines | Minor. Prefer `C_Spell.GetSpellInfo(text)` first, then the global. |
| 14 | ENCOUNTER_START/END, CooldownCollaborator.lua:431-432, 442-446 | UNV (CDTL3 registers them on every client, Helpers.lua:282, so harmless) | UNV | UNV | UNV | Only sets `CC.inEncounter` (used for a debug print) and a 1 s `BroadcastState` after the end. Not load-bearing. |

### A2. Calls that work unchanged on all four (spot-checked against CDTL3 usage and the Classic TOC pattern)

`UnitFullName`, `GetNormalizedRealmName`, `UnitName`, `UnitExists`, `UnitClass` (class tags are only used as table keys), `UnitIsConnected`, `UnitIsDeadOrGhost`, `IsInRaid`, `IsInGroup`, `GetNumGroupMembers`, `IsRaidLeader`, `IsRaidOfficer`, `UnitIsGroupLeader`, `SendChatMessage`, `C_Timer.After/NewTicker` (CDTL3 uses C_Timer.After on all six TOCs), `CopyTable`, `strsplit`, `tinsert`/`UISpecialFrames`, `C_ChatInfo.RegisterAddonMessagePrefix`, `CHAT_MSG_ADDON` payload (prefix, text, channel, sender; wiki lists the event for Vanilla, TBC, Mists and Forever), `GROUP_ROSTER_UPDATE`, `PLAYER_LOGIN/LOGOUT`, `ADDON_LOADED`, `SetColorTexture`, `UICheckButtonTemplate`, `UIPanelButtonTemplate`, `UIPanelCloseButton`, `OptionsSliderTemplate`, `UIPanelScrollFrameTemplate`, `InputBoxTemplate`, `GameFont*` objects, `Minimap` button code (`GetCursorPosition`, `math.atan2`). Treat as ok until a smoke load says otherwise.

Unverified but low risk: `Slider:SetObeyStepOnDrag` (Options.lua:360).

### A3. The secret / source-of-truth matrix for "who cast what"

| Client | Own casts | Other players' casts | Combat log for addons | Plan |
|---|---|---|---|---|
| Retail, Forever | `UNIT_SPELLCAST_SUCCEEDED` "player", spellID safe | spellID SECRET (SecretWhenUnitSpellCastRestricted); only via CDCOLLAB addon messages from peers running CC | closed | Unchanged model (today's CC). Forever additionally has ranks (rank map, A1 #3). |
| Era, TBC, MoP | event, spellID is a plain number (rank-specific on Era/TBC) | combat log SPELL_CAST_SUCCESS carries spellID for everyone, with srcFlags; plus CDCOLLAB peers | open | Add a CLEU listener exactly like cdtl3-dev Group.lua:1004-1011 and 178-208. |

CDTL3's combat-log pattern (copy it): `GetInfo = (C_CombatLog and C_CombatLog.GetCurrentEventInfo) or CombatLogGetCurrentEventInfo` (Group.lua:20); register `COMBAT_LOG_EVENT_UNFILTERED` only when `not retailAPI and GetInfo`, inside a pcall (CDTL3.lua:3097); in the handler read `_, sub, _, srcGUID, srcName, srcFlags = GetInfo()`; on `SPELL_CAST_SUCCESS` take `spellID, spellName = select(12, GetInfo())`; accept only party/raid player sources (`bit.band(srcFlags, COMBATLOG_OBJECT_AFFILIATION_PARTY(0x2) + RAID(0x4)) ~= 0` and `bit.band(srcFlags, COMBATLOG_OBJECT_TYPE_PLAYER(0x400)) ~= 0`); match by ID then by spell name (ranks); get class from `GetPlayerInfoByGUID` in a pcall, cached with a 10 s retry; start the timer with `startedAt = GetTime()`.

Whether the plain UNIT_SPELLCAST_SUCCEEDED event fires for party/raid tokens on the classic clients: I could not confirm (a web search found only 2007-era retail notes saying it does fire for group members). The CLEU path does not depend on the answer. UNV test: `/cdc verbose` in a party on Era with a friend casting Innervate; if the event log shows `unit=party1`, then it fires.

Double-feed hazard: on Era/TBC/MoP, CDTL3's own raid-cooldown listener (timer type `raidcds`, Group.lua:123-208, off by default) and CC's bridge type `cdcGroup` could show the same cast twice if both are on. Make CC detect `CDTL3.Group` raid casts being on, or let CC's CLEU path be the one that feeds CDTL3 and tell users to leave "Raid cooldowns" off.

### A4. Retail bugs found in passing (not part of the port, but the port must not copy them)

1. Data.lua:53 `[391215] = "Fury of the Aspects"` and Roster.lua:22 `EVOKER = { 391215 }`. In the 12.1.5 game data 391215 is "Initiative". Fury of the Aspects is 390386 (cd 300 s in the same table, and CDTL3 BURST uses 390386). The Evoker lust is never matched today.
2. CooldownCollaborator.lua:361 reads `ch.cooldownStart`; the field is `cooldownStartTime` (CDTL3 Helpers.lua:1013 comment). The charge-pool countdown for Battle Rez therefore computes a negative number and reads 0 (always "ready" once currentCharges is 0).
3. Data.lua:19 Anti-Magic Zone is 120 s; 12.1.5 table says 240 s. Several other retail rows (Rewind 0, Spirit Link 0, Ice Block 0) are 0 in SpellCooldowns because talents/charges carry the cooldown, so those are not provable from this cache; leave them.

### A5. Count of APIs needing a change per client (items from A1, FIX only; UNV counted separately)

| Client | FIX | UNV |
|---|---|---|
| Classic Era 1.15.9 | 9 (#1,2,3,4,5,6,9 drop,10 CLEU add,11) | 4 (#7,8,10,14) |
| TBC Anniversary 2.5.6 | 9 (same set) | 4 |
| MoP Classic 5.5.4 | 5 (#2,5,6,11 CLEU add, rank-free so #3 not needed) | 4 |
| WoW: Forever 1.60.1 | 6 (#1,3,4,9 drop,13,12 hardening optional) | 3 (#5,6,14) |

---------------------------------------------------------------------------------------------------

## B. Spell lists per client

Method: for each candidate name, every SpellID in that client's `SpellName` whose class is tied to it by `SkillLineAbility.ClassMask` or `Talent` (SpellID and SpellRank_0..8) was listed with its `SpellCooldowns` (difficulty 0) value = max(RecoveryTime, CategoryRecoveryTime), in seconds. Plus a direct lookup of every ID in CDTL3's RAID/BURST. "V" = id found in that client's table with that cooldown. "U" = unverified (reason given). Cooldowns are the BASE cooldown (talents/glyphs ignored), like `CC.SpellData.duration`.

18 Nov 2026 additions (review cards R3, R13, R14, P18, P28, P32), same builds and cache: the cooldown is max(`RecoveryTime`, `CategoryRecoveryTime`) as above, except a spell that holds one charge (Retail Shield Wall, Guardian of Ancient Kings, Survival Instincts, Vengeance Metamorphosis), whose length is its charge category's `SpellCategory.ChargeRecoveryTime` (its `RecoveryTime` is only the 1 to 8 s gap between uses). Icons are `SpellMisc.SpellIconFileDataID`; the class tie is `SkillLineAbility.ClassMask`, `Talent`, `TraitDefinition` or `SpecializationSpells`; provider levels are `SpellLevels.BaseLevel`. Item cooldowns come from `ItemEffect` (`CoolDownMSec` / `CategoryCoolDownMSec`), fetched from wago.tools `db2/ItemEffect/csv?build=` for the three Classic builds (it is not in the spell-list-check cache). "variant" = another ID the same spell casts with; it records under the base ID like a rank (`variants` in `Data_<client>.lua`).

CC's `minDuration` default is 60 s, so spells with a shorter base cooldown (Blessing of Sacrifice 30 s on TBC, Fear Ward 30 s on Era, Misdirection 30 s on MoP, Innervate etc. are fine) are not listed. Suggested data shape: `{ [baseID] = { name, duration, class, ranks = {id,...}, icon } }` plus a client-gated `CC.RankToBase`.

Suggested file layout, copying CDTL3's per-TOC pattern: keep `Data.lua` for shared things (class colors, consumables structure), add `Data_Retail.lua`, `Data_Era.lua`, `Data_TBC.lua`, `Data_Mists.lua`, `Data_Forever.lua`, each listed only in its own TOC (CDTL3 does this with `FlightData\<client>.lua`, TOCs `_Mainline/_Vanilla/_TBC/_Mists/_Camelot` + plain `.toc`).

### B1. Classic Era (build 1.15.9.70576; 15 tracked, all verified)

| Class | Spell | ID(s), all ranks | CD s | Status |
|---|---|---|---|---|
| Druid | Innervate | 29166 | 360 | V |
| Druid | Rebirth | 20484, 20739, 20742, 20747, 20748 | 1800 | V |
| Druid | Tranquility | 740, 8918, 9862, 9863 | 300 | V |
| Druid | Challenging Roar (tracked from 18 Nov, R13) | 5209 | 600 | V |
| Paladin | Lay on Hands | 633, 2800, 10310 | 3600 | V |
| Paladin | Divine Intervention | 19752 | 3600 | V |
| Paladin | Blessing of Protection | 1022, 5599, 10278 | 300 | V |
| Priest | Power Infusion (talent) | 10060 | 180 | V |
| Priest | Lightwell (talent) | 724, 27870, 27871 | 600 | V |
| Shaman | Mana Tide Totem (talent) | 16190, 17354, 17359 | 300 | V |
| Shaman | Reincarnation (18 Nov) | 20608 (the passive in the spellbook); the rez casts 21169, a variant | 3600 (category 1161 "Reincarnation", both IDs) | V |
| Warrior | Shield Wall | 871 | 1800 | V |
| Warrior | Challenging Shout | 1161 | 600 | V |
| Warrior | Last Stand (talent, 18 Nov) | 12975 | 600 | V |
| Warlock | Soulstone Resurrection | 20707, 20762, 20763, 20764, 20765 | 1800 | V: no SpellCooldowns row (the cooldown is the item's); `ItemEffect` gives every soulstone item's effect for these IDs `CategoryCoolDownMSec` 1800000 (category 831). `itemCooldown = true` |

Not tracked: Lust (does not exist: 2825 / 32182 are not in the Era SpellName table), Misdirection (not yet), Fear Ward (30 s < 60 s filter), Tranquilizing Shot 19801 (20 s on Era, TBC and Forever, under the filter), Mind Control 605 / 10911 / 10912 (no cooldown: RecoveryTime and CategoryRecoveryTime 0 on all three Classic builds). Goblin Sapper Charge 13241 (item 10646): no SpellCooldowns row; `ItemEffect` 98888 gives `CoolDownMSec` 300000 and a 60 s shared category (24) on Era, TBC and Forever, icon 135826, so its row would be 300 s with `itemCooldown = true`. Not added yet: an item has no class, and Settings > Default Spells lists rows only under a class header (Options.lua `CLASS_ORDER`), so it could never be unticked there. Season of Discovery rune spells ARE in the Era table with class ties and cooldowns (Pain Suppression 402004 180 s, Power Word: Barrier 425207 180 s, Rallying Cry 426490 180 s, Shadowfiend 401977 300 s): realm-specific, listed here only so nobody mistakes them for errors; treat as optional and unverified in play.
CDTL3's `RAID.era` (12 rows) is covered row-for-row: every row V except 20707 (U).

### B2. WoW: Forever (build 1.60.1.70888; 16 tracked, all verified)

Forever = Era's content with its own changes (CDTL3 Data.lua `foreverChanges` 2995-3111, `GetForeverData`). Start from B1 and apply:

| Change | Value on Forever | Status |
|---|---|---|
| Lay on Hands 633, 2800, 10310 | 1200 s (Era 3600) | V |
| Shield Wall 871 | 900 s (Era 1800) | V |
| Fear Ward 6346 | 180 s (Era 30), tracked from 18 Nov | V |
| Last Stand 12975 | 180 s (Era 600), tracked from 18 Nov | V |
| Challenging Roar 5209 | 600 s, as Era, tracked from 18 Nov | V |
| Reincarnation 20608 (rez cast 21169, a variant) | 3600 s (category 1161), as Era, tracked from 18 Nov | V |
| Mana Tide Totem | adds id 1325256 (300 s) next to 16190, 17354, 17359 | V (new id; check which one the cast reports: add all four to ranks) |
| Lightwell 724 / 27870 / 27871 | 600 s, same as Era | V |
| Rebirth (5 ranks) 1800, Tranquility (4 ranks) 300, Innervate 360, DI 3600, BoP (3 ranks) 300, PI 180, Challenging Shout 600, Challenging Roar 600 | unchanged from Era | V |
| Soulstone Resurrection 20707, 20762-20765 | 1800 | V (`ItemEffect` category cooldown 1800000, as Era) |

Forever-only class spells with a 60 s+ cooldown in the data that nobody has evaluated for CC: Priest Dark Sacrifice (1277324-1277328, 600 s), Divine Grace (1277370-1277378, 600 s), Contingency Plan (1277462, 1277634, 1277638-1277640, 600 s), Chastise (1277331-35, 120 s); Paladin Swift Judgement 1310994 (60 s, personal). They look like Forever's priest redesign; I did not decide whether they are group-relevant (owner call; needs Forever tooltips). Also on Forever: Totemic Call 437009 = 30 s (below filter), Tranquilizing Shot 19801 = 20 s (below filter), no Bloodlust/Heroism, no Time Warp. Goblin Sapper Charge: as Era (`ItemEffect` 98888, linked to item 10646 by `ItemXItemEffect`, 300 s), not added for the same reason.
Forever has no combat log and secret remote spellIDs: every non-local entry arrives only by CC addon message.

### B3. TBC Anniversary (build 2.5.6.70577; 22 tracked, all verified)

| Class | Spell | ID(s), all ranks | CD s | Status |
|---|---|---|---|---|
| Shaman | Bloodlust (Horde) | 2825 | 600 | V |
| Shaman | Heroism (Alliance) | 32182 | 600 | V |
| Shaman | Mana Tide Totem | 16190 | 300 | V |
| Shaman | Earth Elemental Totem (tracked from 18 Nov, R13) | 2062 | 1200 | V |
| Shaman | Reincarnation (18 Nov) | 20608; the rez casts 21169, a variant | 3600 (category 1161) | V |
| Druid | Innervate | 29166 | 360 | V |
| Druid | Rebirth | 20484, 20739, 20742, 20747, 20748, 26994 | 1200 | V |
| Druid | Tranquility | 740, 8918, 9862, 9863, 26983 | 600 | V |
| Druid | Challenging Roar (tracked from 18 Nov) | 5209 | 600 | V |
| Paladin | Lay on Hands | 633, 2800, 10310, 27154 | 3600 | V |
| Paladin | Divine Intervention | 19752 | 3600 | V |
| Paladin | Blessing of Protection | 1022, 5599, 10278 | 300 | V |
| Priest | Power Infusion | 10060 | 180 | V |
| Priest | Pain Suppression | 33206 | 120 | V |
| Priest | Shadowfiend | 34433 | 300 | V |
| Priest | Lightwell | 724, 27870, 27871, 28275 | 360 | V |
| Priest | Fear Ward (tracked from 18 Nov) | 6346 | 180 | V |
| Hunter | Misdirection | 34477 | 120 | V |
| Warrior | Shield Wall | 871 | 1800 | V |
| Warrior | Challenging Shout | 1161 | 600 | V |
| Warrior | Last Stand (talent, 18 Nov) | 12975 | 480 | V |
| Warlock | Soulstone Resurrection | 20707, 20762, 20763, 20764, 20765, 27239 | 1800 | V (`ItemEffect` category cooldown 1800000 for all six, category 831) |

Under 60 s, not listed: Blessing of Sacrifice 6940/20729/27147/27148 (30 s), Intervene 3411 (30 s), Tranquilizing Shot 19801 (20 s). Mind Control has no cooldown; Goblin Sapper Charge as Era (300 s item cooldown, not added). `RAID.tbc` (15 rows) is covered: every row V except 27239 (U). Note `BURST.tbc` has Bloodlust/Heroism as auras only (40 s buff), no Sated; this is the aura, not the cooldown. (The "Aura Mastery" 31821 hit for TBC is a 0 s row that CDTL3 also does not list; ignore.)

### B4. MoP Classic (build 5.5.4.70631; 41 tracked + 4 optional, all verified; 1 unverified)

No ranks on MoP. Core list (every id found with this cooldown):

| Class | Spell | ID | CD s |
|---|---|---|---|
| Warrior | Rallying Cry | 97462 | 180 |
| Warrior | Skull Banner | 114207 | 180 |
| Warrior | Demoralizing Banner | 114203 | 180 |
| Warrior | Mocking Banner (mass taunt, 18 Nov) | 114192 | 180 |
| Warrior | Shield Wall (18 Nov) | 871 | 180 |
| Warrior | Last Stand (18 Nov; Protection) | 12975 | 180 |
| Paladin | Lay on Hands | 633 | 600 |
| Paladin | Hand of Protection | 1022 | 300 |
| Paladin | Hand of Sacrifice | 6940 | 120 |
| Paladin | Hand of Salvation | 1038 | 120 |
| Paladin | Devotion Aura | 31821 | 180 |
| Paladin | Guardian of Ancient Kings (18 Nov; Protection's, not Holy's 86669 or Retribution's 86698) | 86659 | 180 |
| Paladin | Ardent Defender (18 Nov) | 31850 | 180 (CategoryRecoveryTime) |
| Priest | Power Word: Barrier | 62618 | 180 |
| Priest | Divine Hymn | 64843 | 180 |
| Priest | Hymn of Hope | 64901 | 360 |
| Priest | Vampiric Embrace | 15286 | 180 |
| Priest | Guardian Spirit | 47788 | 180 |
| Priest | Pain Suppression | 33206 | 180 |
| Priest | Power Infusion | 10060 | 120 |
| Death Knight | Anti-Magic Zone | 51052 | 120 |
| Death Knight | Raise Ally | 61999 | 600 |
| Death Knight | Icebound Fortitude (18 Nov) | 48792 | 180 |
| Death Knight | Vampiric Blood (18 Nov; Blood) | 55233 | 60 |
| Shaman | Bloodlust | 2825 | 300 |
| Shaman | Heroism | 32182 | 300 |
| Shaman | Spirit Link Totem | 98008 | 180 |
| Shaman | Healing Tide Totem | 108280 | 180 |
| Shaman | Stormlash Totem | 120668 | 300 |
| Mage | Time Warp | 80353 | 300 |
| Warlock | Soulstone | 20707 | 600 |
| Monk | Revival | 115310 | 180 |
| Monk | Life Cocoon | 116849 | 120 |
| Monk | Avert Harm | 115213 | 180 |
| Monk | Fortifying Brew (18 Nov) | 115203 | 180 |
| Druid | Tranquility | 740 | 480 |
| Druid | Ironbark | 102342 | 60 |
| Druid | Innervate | 29166 | 180 |
| Druid | Rebirth | 20484 | 600 |
| Druid | Stampeding Roar | 106898; in Bear Form it casts 77761, in Cat Form 77764 (variants, 18 Nov R14: same name, CategoryRecoveryTime 120000 and category 1257 "Stampeding Roar"; 77764 has the 1 s cat GCD) | 120 |
| Druid | Survival Instincts (18 Nov; Feral and Guardian) | 61336 | 180 |

(41 rows.) No Challenging Shout or Challenging Roar on MoP (1161 and 5209 are not in its SpellName). Optional, also V: Shattering Throw 64382 (300), Vigilance 114030 (120), Gorefiend's Grasp 108199 (60), Ancestral Guidance 108281 (120). `RAID.mop` (21 rows) is covered: all 21 V, same cooldowns.
Unverified (1): hunter pet lust 90355 (listed as "Ancient Hysteria" in CDTL3's BURST comment; the MoP table names it "Primal Rage", 360 s). It is cast by the PET, so `UNIT_SPELLCAST_SUCCEEDED` fires with unit "pet" and CC's handler only accepts "player" (CooldownCollaborator.lua:455); the CLEU path would see it as a pet source (type flag 0x1000, not 0x400), so it needs its own handling. Sated family (57724 / 57723 / 80354 / 95809) are aura-only debuffs with no cooldown, not spells to track.
Not on MoP: Time Warp exists (above); no Evoker/Demon Hunter; Retail-only Fury of the Aspects.

Ranking of unverified items overall: Soulstone cooldown on Era/TBC/Forever (item cooldown), MoP pet lust, plus the in-game behaviours flagged UNV in A.

### B5. Counts (spells tracked by default; rank ids counted once)

| Client | Tracked (18 Nov 2026) | Before |
|---|---|---|
| Retail | 43 | 29 |
| MoP Classic | 41 (+4 optional) | 32 |
| TBC Anniversary | 22 | 17 |
| Classic Era | 15 | 12 |
| WoW: Forever | 16 | 12 |

### B6. Provider spell levels (1.1.1)

The level each Battle Rez and lust spell is learned at, the `level` field in `Data_<client>.lua`: `BaseLevel` of the spell (rank 1 where there are ranks) in each build's SpellLevels table (wago.tools `db2/SpellLevels/csv?build=`, saved beside the spell-list-check cache). None of the Retail ones are talents (no TraitDefinition row), so the level is the real one there too. Re-check after a patch along with the spell lists.

| Client (build) | Rebirth 20484 | Raise Ally 61999 | Intercession 391054 | Bloodlust 2825 / Heroism 32182 | Time Warp 80353 | Fury of the Aspects 390386 | Harrier's Cry 466904 |
|---|---|---|---|---|---|---|---|
| Classic Era (1.15.9.70576) | 20 | – | – | – | – | – | – |
| WoW: Forever (1.60.1.70888) | 20 | – | – | – | – | – | – |
| TBC Anniversary (2.5.6.70577) | 20 | – | – | 70 / 70 | – | – | – |
| MoP Classic (5.5.4.70631) | 56 | 72 | – | 70 / 70 | 84 | – | – |
| Retail (12.1.5.70783) | 19 | 19 | 19 | 48 / 48 | 49 | 48 | 48 (Marksmanship only) |

### B7. Retail rows added 18 Nov 2026 (build 12.1.5.70783)

Retail's list predates section B; these are the rows the review added, checked the same way. "charge" = one charge, the length is the charge category's `ChargeRecoveryTime`.

| Class | Spell | ID | CD s | Where the number comes from | Class tie |
|---|---|---|---|---|---|
| Paladin | Intercession (Battle Rez provider) | 391054 | 600 | RecoveryTime 600000; category 26 "Resurrection (Full)", the same as Rebirth | SkillLineAbility Paladin; BaseLevel 19 |
| Hunter | Harrier's Cry (lust provider, `spec = 254`) | 466904 | 360 | RecoveryTime 360000; the same SpellCategories row (dispel, prevention) as Bloodlust, Heroism, Time Warp and Fury of the Aspects | SpecializationSpells 254 Marksmanship only; BaseLevel 48 |
| Priest | Power Infusion (P28) | 10060 | 120 | RecoveryTime 120000 | TraitDefinition (talent) |
| Paladin | Blessing of Sacrifice (P32) | 6940 | 120 | RecoveryTime 120000 | SkillLineAbility Paladin, talent |
| Warrior | Shield Wall | 871 | 180 | charge (category 1929) | TraitDefinition |
| Warrior | Last Stand | 12975 | 180 | RecoveryTime 180000 | TraitDefinition |
| Warrior | Challenging Shout (mass taunt) | 1161 | 120 | RecoveryTime 120000 | SpecializationSpells 73 Protection, talent |
| Paladin | Guardian of Ancient Kings | 86659 | 180 | charge (category 2424) | TraitDefinition |
| Paladin | Ardent Defender | 31850 | 90 | RecoveryTime 90000 | TraitDefinition |
| Death Knight | Icebound Fortitude | 48792 | 120 | RecoveryTime 120000 | TraitDefinition |
| Death Knight | Vampiric Blood | 55233 | 90 | RecoveryTime 90000 | TraitDefinition |
| Druid | Survival Instincts | 61336 | 180 | charge (category 1469) | TraitDefinition (two talent entries) |
| Monk | Fortifying Brew | 115203 | 360 | RecoveryTime 360000 | TraitDefinition 388917 shows it as 115203 |
| Demon Hunter | Metamorphosis (Vengeance) | 187827 | 120 | charge (category 2469 "Metamorphosis (Vengeance)") | SpecializationSpells 581 Vengeance |

Not on Retail: Challenging Roar, Mocking Banner. Not added: other IDs with the same names and charge categories (Guardian of Ancient Kings 212641, Survival Instincts 236156) have no class, talent or spec tie, so nothing shows a player casts them.

Hunter pet lust (not tracked): Primal Rage 264667 has the lust SpellCategories row and RecoveryTime 360000, BaseLevel 48, and is tied only to the Ferocity pet specializations (74, 535), so it is the pet's spell. A second "Primal Rage", 272678 (RecoveryTime 360000, a different SpellCategories row, no class tie), looks like the hunter-side button of Command Pet 272651 (Hunter skill line) with a Ferocity pet; nothing in these tables links the two, so that is unverified. A third 360 s "Primal Rage", 357650, has the lust row and no tie. Seeing it (untested): the hunter's own client should get `UNIT_SPELLCAST_SUCCEEDED` for "pet" with 264667, and for "player" with 272678 if that is the button (CC listens to "player" only, and whether a pet's spell ID is hidden on Midnight is unknown); other clients see nothing (no combat log on Retail, remote IDs hidden), so only the hunter's own addon could send it. A hunter counts only if their pet is a Ferocity one, which other players can't read either.

### B8. Retail's original rows, checked 18 Nov 2026 (build 12.1.5.70783)

The 29 rows Retail had before the port, checked the same way as the Classic lists for the first time. Cooldown sources as in the method note above: "one charge" means the spell holds a single charge and the length a player waits is that charge's `SpellCategory.ChargeRecoveryTime` (its own `RecoveryTime` is only the gap between uses); otherwise max(`RecoveryTime`, `CategoryRecoveryTime`) of `SpellCooldowns` difficulty 0. Icons are `SpellMisc.SpellIconFileDataID` (one row per spell). Base cooldowns only, as every row: talents are not modelled. Ancestral Protection Totem keeps its shortened name (the client's own name is indexed too).

| Class | Spell | ID | CD s | Where the cooldown comes from | Icon | Changed |
|---|---|---|---|---|---|---|
| Warrior | Rallying Cry | 97462 | 180 | RecoveryTime 180000 | 132351 | - |
| Paladin | Aura Mastery | 31821 | 180 | RecoveryTime 180000 | 135872 | - |
| Paladin | Lay on Hands | 633 | 600 | RecoveryTime 600000 | 135928 | - |
| Paladin | Blessing of Protection | 1022 | 300 | one charge: ChargeRecoveryTime 300000 (category 1392); RecoveryTime 1500 | 135964 | - |
| Priest | Guardian Spirit | 47788 | 180 | RecoveryTime 180000 | 237542 | - |
| Priest | Pain Suppression | 33206 | 180 | one charge: ChargeRecoveryTime 180000 (category 2105); RecoveryTime 1500 | 135936 | cooldown 90 -> 180 |
| Priest | Power Word: Barrier | 62618 | 180 | RecoveryTime 180000 | 253400 | icon 135940 -> 253400 |
| Priest | Leap of Faith | 73325 | 90 | one charge: ChargeRecoveryTime 90000 (category 2308); RecoveryTime 1000 | 463835 | - |
| Death Knight | Anti-Magic Zone | 51052 | 240 | RecoveryTime 240000 | 237510 | icon 135826 -> 237510 |
| Death Knight | Raise Ally | 61999 | 600 | RecoveryTime 600000 | 136143 | icon 136144 -> 136143 |
| Shaman | Heroism | 32182 | 300 | RecoveryTime 300000 | 132313 | icon 135978 -> 132313 |
| Shaman | Bloodlust | 2825 | 300 | RecoveryTime 300000 | 136012 | - |
| Shaman | Spirit Link Totem | 98008 | 180 | one charge: ChargeRecoveryTime 180000 (category 1540); RecoveryTime 0 | 237586 | - |
| Shaman | Ancestral Prot. Totem | 207399 | 300 | RecoveryTime 300000 | 136080 | icon 1038468 -> 136080 |
| Shaman | Healing Tide Totem | 108280 | 180 | RecoveryTime 180000 | 538569 | cooldown 120 -> 180 |
| Mage | Time Warp | 80353 | 300 | RecoveryTime 300000 | 458224 | icon 458223 -> 458224 |
| Mage | Ice Block | 45438 | 240 | one charge: ChargeRecoveryTime 240000 (category 1560); RecoveryTime 0 | 135841 | cooldown 300 -> 240 |
| Warlock | Demonic Gateway | 111771 | 90 | RecoveryTime 10000 | 607512 | icon 463286 -> 607512; **kept at 90: the data says 10 s** |
| Monk | Revival | 115310 | 180 | one charge: ChargeRecoveryTime 180000 (category 1933); RecoveryTime 1000 | 1020466 | icon 627485 -> 1020466 |
| Monk | Life Cocoon | 116849 | 120 | one charge: ChargeRecoveryTime 120000 (category 2198); RecoveryTime 750 | 627485 | icon 627487 -> 627485 |
| Druid | Tranquility | 740 | 180 | CategoryRecoveryTime 180000 (category 46) | 136107 | - |
| Druid | Rebirth | 20484 | 600 | CategoryRecoveryTime 600000 (category 26) | 136080 | - |
| Druid | Innervate | 29166 | 180 | RecoveryTime 180000 | 136048 | - |
| Demon Hunter | Darkness | 196718 | 300 | RecoveryTime 300000 | 1305154 | cooldown 180 -> 300; icon 1305149 -> 1305154 |
| Evoker | Rewind | 363534 | 240 | one charge: ChargeRecoveryTime 240000 (category 2035); RecoveryTime 0 | 4622474 | icon 4622462 -> 4622474 |
| Evoker | Rescue | 370665 | 60 | RecoveryTime 60000 | 4622460 | icon 4638349 -> 4622460 |
| Evoker | Zephyr | 374227 | 120 | RecoveryTime 120000 | 4630449 | icon 4643463 -> 4630449 |
| Evoker | Time Dilation | 357170 | 60 | one charge: ChargeRecoveryTime 60000 (category 2411); RecoveryTime 1000 | 4622478 | cooldown 90 -> 60; icon 4622460 -> 4622478 |
| Evoker | Fury of the Aspects | 390386 | 300 | RecoveryTime 300000 | 4723908 | - |

Left as it was: Demonic Gateway 111771. The 12.1.5 data gives it `RecoveryTime` 10000 (10 s) with no category or charge cooldown, and no Demonic Gateway ID in the data has a cooldown over 30 s (the longest, 362227 and 1214675, are 30 s). The row stays at 90 s until that is settled.


---------------------------------------------------------------------------------------------------

## C. What cannot work, or needs a different source, per client

1. Capability "Bloodlust/Heroism" (Roster.lua:16-24, Essentials, Lanes): does not exist on Era or Forever (ids not in either SpellName table). TBC: Shaman only (Bloodlust Horde 2825, Heroism Alliance 32182, both 600 s); MoP: Shaman + Mage Time Warp 80353 + hunter pet 90355; Retail: Shaman, Mage, Evoker (fix the id to 390386), hunter pet Primal Rage 264667. The capability table must be per client, and `CC.CAPABILITY_ORDER` must drop empty capabilities (Lanes.lua:49 builds one lane per key; on Era/Forever an empty Bloodlust lane and header would show "No providers" forever).
2. Capability "Battle Rez": Druid Rebirth on all four. Warlock Soulstone is a pre-placed self-resurrect buff (Era/TBC/MoP/Forever; "Soulstone Resurrection" 1800 s Era/TBC, MoP "Soulstone" 600 s). It is not a cast-on-the-dead rez, so the Rez button message ("%s, please %s %s!", CooldownCollaborator.lua:303) does not fit it; keep it out of BATTLEREZ or give it its own capability. Death Knight Raise Ally: MoP only. There is no shared raid rez-charge pool I can confirm on Era/TBC (cooldowns are per caster); MoP pool behaviour UNV. So the "charge pool" branch in GetLocalReadiness only matters on Retail/Forever.
3. Spec detection (`GetSpecialization`, `GetInspectSpecialization`, `NotifyInspect`): no specs on Era, TBC, Forever (CDTL3 Helpers.lua:1816 comment). MoP has them. The only consumer is a label; drop on three clients (A1 #1/#9). `SPEC_NAMES` (Roster.lua:38) is Retail-order; MoP spec order is not the same as the Retail table for Monk/Death Knight/others (verify against ChrSpecialization before keeping it).
4. Class tags: `DEATHKNIGHT` does not exist on Era/TBC/Forever; `MONK` not on Era/TBC/Forever; `DEMONHUNTER`/`EVOKER` not on Era/TBC/MoP/Forever. Only table keys use them (Data.lua:71-86, Options.lua:9-21, Roster.lua:38-52), so nothing errors; the Options "Default Spells" tab already skips classes with no entries (Options.lua:101).
5. Consumables (Data.lua:59-68, Consumables.lua:28-35): the built-in IDs are Midnight spells (1232585, 462187, 1230876-78, 1235057); none exists in the four target game builds that I checked by name (the cache's Well Fed 1225778/1225779 are unrelated). Classic aura IDs are different and not one-per-flask: Era/Forever flasks 17626 Flask of the Titans, 17627 Distilled Wisdom, 17628 Supreme Power, 17629 Chromatic Resistance; TBC adds 28518 Fortification, 28519 Mighty Restoration, 28520 Relentless Assault, 28521 Blinding Light, 28540 Pure Death, 42735 Chromatic Wonder; MoP flasks 105689 Spring Blossoms, 105693 Falling Leaves, 105694 Earth, 105696 Winter's Bite, 105691 Warm Sun (names verified in the cache; which are the effective flasks in 5.5.4 is UNV). "Well Fed" is dozens of ids with the same NAME (Era 19705, 19706, 19708-19711, 24799, ...; MoP has 170), so classic tracking should match aura NAME ("Well Fed", flask names) through the readable aura API instead of an ID list. On Forever auras are secret, so keep the ID path (`GetPlayerAuraBySpellID`) with the 17626-17629 ids. Elixirs are not counted by CC at all today (no category). Also the `/cdc consumable` command and `CC.SpellData[id].consumable` flow stay valid.
6. Evoker spells (Rewind, Rescue, Zephyr, Time Dilation, Fury of the Aspects): Retail only. Demon Hunter Darkness: Retail only. Time Warp: MoP+ only. Ancestral Protection Totem 207399 / Spirit Link Totem as listed: Retail/MoP only (SLT not in Era/TBC lists).
7. Forever: remote spellIDs secret and no combat log, so same comm-only model as Retail; no specs; no `IsSpellKnown*` globals; secret local cooldowns (pcall pattern already in GetLocalReadiness stays).
8. Bridge to CDTL3 (Bridge.lua): `CDTL3.RegisterTimerType / StartTimer / StopTimer` is CDTL3's own API (API.lua) and ships on all six CDTL3 TOCs, so the bridge needs no change. Group.lua documents that the Caster lane takes `cdcGroup` timers on any client.
9. Addon messages in LFG/instance groups: CC sends only PARTY / RAID (Comms.lua:22-27, 58-63, Consumables.lua:183). In an LFG/battleground group (MoP LFG/LFR/Scenarios; TBC/Era dungeon finder equivalents where present) the right channel is INSTANCE_CHAT. Same gap exists on Retail today; do not regress it, fix it in the port if cheap.
10. UI: the Rez button macro text uses RAID_WARNING and needs lead/assist; fine on all clients. `Settings.*` guard (A1 #8). Everything else UI is stock templates.

---------------------------------------------------------------------------------------------------

## D. Release workflow (BigWigs packager)

Current CC state: `.github/workflows/release.yml` triggers on `v*` tags plus `workflow_dispatch`, runs `actions/checkout@v4` (fetch-depth 0) then `BigWigsMods/packager@v2` with `CF_API_KEY: ${{ secrets.CURSFORGE_API_KEY }}`, `WAGO_API_TOKEN: ${{ secrets.WAGO_API_KEY }}`, `GITHUB_OAUTH`. `.pkgmeta` has `package-as: CooldownCollaborator` and ignores `.pkgmeta`, `.gitignore`, `.github`, `README.md`. TOCs: only `CooldownCollaborator_Mainline.toc` (Interface 120105, `X-Curse-Project-ID: 1577127`, no X-Wago-ID, `OptionalDeps: CooldownTimeline3`).

Verdict: as-is, the workflow publishes a RETAIL-ONLY package. The packager derives the game versions from the TOCs it finds; with only `_Mainline.toc` it has nothing for Era/TBC/MoP/Forever. The workflow file itself (uses `@v2`, which floats to the latest 2.x; CDTL3 CLAUDE.md says Forever mapping needs packager >= v2.6.0) needs no structural change, but the repo does:

1. Add TOCs next to `_Mainline`, copying cdtl3-dev: `CooldownCollaborator_Vanilla.toc` (Interface 11509), `_TBC.toc` (20506), `_Mists.toc` (50504), `_Camelot.toc` (16001), and an UNSUFFIXED `CooldownCollaborator.toc` (16001) as the Forever fallback (Forever loads `_Camelot`, then the plain `.toc`, never `_Mainline`; CDTL3 CLAUDE.md "Multi-version TOCs"). Keep `_Mainline.toc` 120105.
2. Put `## X-Curse-Project-ID: 1577127` (and `## X-Wago-ID` once the Wago project exists; today none, so the `WAGO_API_TOKEN` env is unused and Wago upload is skipped) in the unsuffixed `.toc` and `_Camelot.toc` and `_Mainline.toc` (CDTL3 does exactly this; the three classic TOCs carry no project id: the packager reads it from the unsuffixed one first).
3. Packager rule from CDTL3: a suffixed TOC may only carry Interface numbers of its own game type (`120105, 16001` in `_Mainline` fails the whole release). One number per TOC is safest. All TOCs must agree on `## SavedVariables: CooldownCollaboratorDB` and `## Version` (a SavedVariables mismatch silently wipes that client's profile; CDTL3 learned this).
4. Only list the client-specific data file in its own TOC (CDTL3 does `FlightData\Era.lua` etc.). The file lists otherwise stay identical.
5. `.pkgmeta`: add `CLAUDE.md` (CC's CLAUDE.md currently ships inside the package; cdtl3's `.pkgmeta` ignores `CLAUDE.md`, `docs`, `tools`, `.gitattributes`). Consider ignoring `Media/icon.png` and `Media/minimap.png` (TGAs are what the TOC/Minimap use; the PNGs are 76 KB of source art, and CDTL3 notes PNG shows as a checkerboard on Midnight). CC has no `CHANGELOG.md`/`manual-changelog` block (CDTL3's `.pkgmeta` has `manual-changelog: filename: CHANGELOG.md markup-type: markdown`); optional, otherwise the packager builds notes from git history.
6. CurseForge side: the project (1577127) must have the Classic Era, TBC, MoP and Forever game-version families available for the upload to attach; this is a project-page setting I cannot see. Also a new release prompts the hand-kept CurseForge/Wago description changelogs CDTL3 notes.
7. Workflow hygiene vs cdtl3-dev: CDTL3 pins checkout to a SHA (`actions/checkout@3d3c42e5...  # v7.0.1`) and has no `workflow_dispatch`; CC uses `@v4` and keeps `workflow_dispatch`. Not blockers. Keep the misspelled secret name `CURSFORGE_API_KEY`.
8. Interface-number hygiene: bump each TOC when its client patches (CDTL3 CLAUDE.md); `_Camelot` "may change before launch".

Suggested release smoke test before tagging: local `bash`-style package dry run (`release.sh -d -z` from BigWigsMods/packager) and confirm the zip holds all six TOCs and per-client data files, then load each TOC in a stubbed harness like cdtl3-dev `tools/tests` (the suite there loads the real addon per TOC under stubbed WoW APIs; a CC equivalent would catch A1 #1 and #8 without launching four clients).

---------------------------------------------------------------------------------------------------

## Appendix: ground-truth pointers used

- cdtl3-dev CDTL3.lua:15-36 (`isForever`, `retailAPI`), 52-75 (`Compat`), 3086-3123 (TurnOn, CLEU gating).
- cdtl3-dev Helpers.lua:996-1141 (GetSpellCharges/GetSpellCooldown with retailAPI branch), 1190-1219 (aura reader), 1816-1848 (HasSpecs/CurrentSpec).
- cdtl3-dev Group.lua:20, 123-208 (RAID lists and the CLEU raid cast path), 452-475 (BURST lists), 1004-1041 (OnLog and chain).
- cdtl3-dev Data.lua:2995-3149 (Forever changes), TOCs `CooldownTimeline3*.toc`, `.pkgmeta`, `.github/workflows/release.yml`.
- Scratch scripts (not in any repo): scan.py, diff.py, names.py, cand.json, ids.json in the scratchpad folder; they only read the spell-list-check cache.
