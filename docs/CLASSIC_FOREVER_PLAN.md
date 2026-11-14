# CooldownCollaborator 1.1.0: Classic Era, TBC Anniversary, MoP Classic and WoW: Forever

One package for every client, like CooldownTimeline3. Facts, file:line references and spell tables: `docs/port-research.md` (sections A–D). This page is the build spec.

## Clients
| Client | TOC | Interface | Other players' casts come from |
|---|---|---|---|
| Retail | `_Mainline` | 120105 | CC addon messages only (unchanged) |
| MoP Classic | `_Mists` | 50504 | combat log + CC addon messages |
| TBC Anniversary | `_TBC` | 20506 | combat log + CC addon messages |
| Classic Era | `_Vanilla` | 11509 | combat log + CC addon messages |
| WoW: Forever | `_Camelot` + unsuffixed `.toc` | 16001 | CC addon messages only (secret spell IDs, no combat log) |

Client detection copies CDTL3.lua: `tocversion` for content, `retailAPI = tocversion >= 110000 or isForever` for API choice, `isForever` = 16000–16999. Never pick an API by interface number alone.

## Build
1. **TOCs and packaging.** Add the four TOCs plus the unsuffixed Forever fallback; one Interface number each; identical `SavedVariables` and `Version` (1.1.0) everywhere; `X-Curse-Project-ID: 1577127` in the unsuffixed, `_Camelot` and `_Mainline` TOCs. Each TOC lists only its own client's spell data file. `.pkgmeta` also ignores `CLAUDE.md` and the `.png` source art.
2. **Spell data per client.** `Data.lua` keeps shared things; spell lists move to `Data_Retail.lua`, `Data_Mists.lua`, `Data_TBC.lua`, `Data_Era.lua`, `Data_Forever.lua`, using the verified rows in research section B (core lists; leave out the "optional" rows and Forever's unevaluated priest spells). Entries are keyed by a base ID with a `ranks = {...}` list; a rank map built at load turns any rank's ID into the base ID, and only base IDs go on the wire. Soulstone stays a tracked spell, never a Battle Rez provider.
3. **Capabilities per client.** Lust and Battle Rez providers come from the client's data (Era and Forever have no lust; Raise Ally is MoP and Retail; hunter pet lust only where verified). A capability with no possible provider on this client has no lane, header or Essentials slot.
4. **API fixes** (research A1): no `GetSpecialization`/inspect work outside Retail (spec is only a label); legacy `GetSpellCooldown`/`GetSpellCharges` where `retailAPI` is false (no `isActive` there); `IsSpellKnown` through a `C_SpellBook` fallback on Forever, any rank counts; guard `AreOutgoingAddonChatMessagesRestricted` and the `Settings` panel registration; `BackdropTemplate` only where it exists; spell lookup by name through `C_Spell.GetSpellInfo` first.
5. **Combat log path** (Era, TBC, MoP): register `COMBAT_LOG_EVENT_UNFILTERED` only where `retailAPI` is false and the API exists, inside a pcall; on `SPELL_CAST_SUCCESS` from a party or raid player, match by ID then by name, record it like a synced cast (class from `GetPlayerInfoByGUID` in a pcall). A cast heard both ways is recorded once.
6. **Addon messages, all clients:** treat `nil`, `true`, `0` and `Enum.SendAddonMessageResult.Success` as sent (today any truthy result requeues, so `0` loops); use `INSTANCE_CHAT` in instance groups.
7. **Consumables:** Retail unchanged. Era, TBC and MoP match flask and Well Fed auras by name through the readable aura API. Forever reads the flask IDs 17626–17629 and the Well Fed IDs through `C_UnitAuras.GetPlayerAuraBySpellID` (auras are secret there).
8. **Retail fixes found in passing:** Fury of the Aspects is 390386 (not 391215, which is "Initiative"); the Battle Rez charge field is `cooldownStartTime`; Anti-Magic Zone is 240 s in the 12.1.5 data.
9. **Tests** (`tools/tests`, kept in the repo): load every TOC under stubbed APIs for its client (fengari, reusing cdtl3-dev's runner and stubs) with zero Lua errors, and check: a rank ID records as its base; a party member's combat-log cast records once on Era, TBC and MoP and is ignored on Forever and Retail; an addon message round trip; no lust lane on Era and Forever; the CDTL3 bridge starts and stops a timer against a stubbed CDTL3 API.

## CDTL3 side (cdtl3-dev)
On Era, TBC and MoP, CDTL3's own raid cooldown listener (Group.lua, "Track raid cooldowns") stands down while CooldownCollaborator's "Group cooldowns" type is registered and switched on, so a cast never shows twice.

## Not in 1.1.0
Optional spells (Challenging Roar, Fear Ward, Earth Elemental, banners and the like), Forever's new priest spells until someone reads their tooltips, the MoP hunter pet lust unless verified, spec labels on MoP, a Wago listing (the project doesn't exist yet).

## Gates before release
- **Tests green on all six TOCs**, then the owner's Retail and Forever walk (Classic Era, TBC and MoP are covered by the tests only, unless he has those clients).
- **A second player** for real group sync; otherwise it ships on the tests plus solo walks.
- **CurseForge** must accept the Classic and Forever game versions for project 1577127: the release run's log shows it; a refusal fails only that upload.
- **His boop** for both releases; nothing is pushed or tagged before it.
