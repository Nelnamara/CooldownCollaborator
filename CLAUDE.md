# CooldownCollaborator — CLAUDE.md

Group & raid cooldown coordinator for **WoW Midnight (12.x)** and **WoW: Forever (1.60.x)**, one package for both. Author: Nelnamara.
Tracks party/raid members' major defensive & utility cooldowns, an Essentials bar
(Bloodlust/Battle-Rez "ready" providers + Rez request), a Lane view, group
flask/food status, and a minimap button.

## Files
- `CooldownCollaborator.lua` — core: client detection (`CC.isForever`), shared helpers (`CanonicalSpellID`, `SpellRanks`, `KnowsSpell`, `ShortName`), init, DB defaults, event frame, `RecordCooldown`, Rez logic, slash `/cdc`.
- `Data.lua` — per-client tables (retail / Forever): spells, capabilities (Essentials/Lane rows), built-in consumables; the bottom picks the running client's set and builds `CC.SpellData`, `CC.SpellAlias`, `CC.CAPABILITIES`, `CC.BuiltinConsumables`. Schema in its header comment.
- `Comms.lua` — the one outgoing queue (`CC:QueueAddonMessage`: token bucket 10 / 1 per s, keyed replacement, retry) + receive. Prefixes: `CDCOLLAB` (cooldowns, known spells `K:`, requests `R:`) and `CDCBUFF` (flask/food status). Wire formats in its header.
- `Sync.lua` — known-spells reporting, state request/reply on login/reload/join, saved own cooldowns (`CooldownCollaboratorCharDB`, per character).
- `Roster.lua` — capability scan (class list, narrowed by each player's reported known spells; `talent` caps need a report); retail-only `NotifyInspect` spec queue.
- `Essentials.lua` — the Essentials bar (ready providers + flask/food strip).
- `Lanes.lua` — Lane view (stacked provider timelines).
- `Consumables.lua` — self-poll of own flask/food auras → broadcast category presence.
- `UI.lua`, `Options.lua`, `Minimap.lua`.

## Midnight API gotchas (critical)
- `aura.spellId` / `aura.name` are **SECRET** even on `"player"`. Only safe lookup is `C_UnitAuras.GetPlayerAuraBySpellID(knownID)`. This is why flask/food tracking is peer-broadcast (each client detects its own, announces via `CDCBUFF`).
- `UNIT_SPELLCAST_SUCCEEDED.spellID` is **SECRET** for party/raid tokens — only `"player"` is safe. Other players' cooldowns arrive only via the `CDCOLLAB` addon message.
- `GetTime()` is per-client (seconds since that client's process start). Wire **secondsAgo**, not a raw timestamp; receiver re-anchors with `GetTime() - secondsAgo`.
- `RegisterUnitEvent` **overwrites** the unit filter (doesn't accumulate) — use `RegisterEvent` + manual token filtering.
- `AreOutgoingAddonChatMessagesRestricted()` is unreliable — attempt the send and act on the result.
- **`SendAddonMessage` returns `Enum.SendAddonMessageResult`, never nil: 0 = Success** (and 0 is truthy in Lua). 1.0.x treated any non-nil result as failure, so every sent message was resent every 2 s forever (fixed in 1.1.0). Retry 3/8/9 and unknown codes; drop 1,2,4,5,6,7. Codes verified in Blizzard's generated API docs (`Gethe/wow-ui-source`, `live` and `forever` branches).
- `IsRaidLeader` / `IsRaidOfficer` don't exist (removed in 5.0; absent from both API docs) — use `UnitIsGroupLeader` / `UnitIsGroupAssistant`. 1.0.x's Request Rez errored inside raids because of this.
- **Group-finder groups use `INSTANCE_CHAT`** — RAID/PARTY there returns NotInGroup. Always pick the channel with `CC:GroupChatType()` (Comms.lua), for addon messages and for chat (Request Rez).
- `PLAYER_ENTERING_WORLD` fires on every loading screen; Sync.lua only requests state when `isInitialLogin` or `isReloadingUi`.
- Addon-message senders are `Name-Realm`; everything else keys players by `UnitName()` — always `CC:ShortName(sender)`.
- Auras are secret in combat (retail 12.1 and Forever): `GetPlayerAuraBySpellID` and its nil-compare go inside a `pcall`, and flask/food polling skips `InCombatLockdown()`.
- Textures ship as uncompressed 32-bit `.tga` (PNG renders as a checkerboard on 12.0.x per CDTL3); the `.png`s are source art, ignored by `.pkgmeta`.
- **12.0.7 un-secreted combat-res (and some whitelisted) cooldowns + charge counts for the `"player"`.** `CC:GetLocalReadiness(spellID)` (in `CooldownCollaborator.lua`) reads your OWN Battle-Rez/Bloodlust true cooldown + the raid Battle-Rez charge pool via `C_Spell.GetSpellCooldown`/`GetSpellCharges`, pcall-guarded; `Roster.lua:GetCapabilityStatus` prefers it for the local player and falls back to the observed-cast model when unreadable. Remote players' values stay secret → still comm-only. (v1.0.3)

## WoW: Forever (1.1.0)
- Forever = retail engine + Midnight restrictions + vanilla classes/spells **with ranks** + interface **16001**. Detect by the 16xxx band (`CC.isForever`), never `WOW_PROJECT_ID`.
- TOCs: `_Mainline.toc` (120105), `_Camelot.toc` (16001) and a plain `.toc` (16001, Forever fallback; the packager reads X-Curse-Project-ID from it). All three must list the same files and the same SavedVariables / SavedVariablesPerCharacter. Same layout as CDTL3 (see its CLAUDE.md for why).
- Every tracked spell is ONE canonical ID (lowest rank) with `ranks`; casts, saves and messages use the canonical ID (`CC:CanonicalSpellID`).
- Spec info is class-only on Forever, so no inspect queue there; talent spells are known only from each player's own `K:` report.
- Combat log is closed to addons on Forever (as on retail 12.x).
- `tools/spell-check` (repo-only) checks both clients' spell, capability and consumable tables against wago.tools game data. Run it after every patch and before every release.
- Still to confirm in game: what Forever does to addon messages during boss fights (queue retries every 2 s, unknown codes included).

## Slash
`/cdc` (toggle) · `verbose` · `roster` (shows who runs the addon + version) · `debug` · `essentials` · `lanes` · `rez` · `consumable <id> <dur> <name>` · `lock`/`unlock` · `settings`

## Build / release / deploy
- BigWigs **packager runs on `v*` tag push** (GitHub Actions). Pushing `main` does NOT release.
- CurseForge API secret is named **`CURSFORGE_API_KEY`** (misspelled — missing the E — but consistent across the suite; do not "fix" it).
- Local test deploy: copy the addon to `D:\World of Warcraft\_retail_\Interface\AddOns\CooldownCollaborator\` (retail) or `D:\World of Warcraft\_forever_\Interface\AddOns\CooldownCollaborator\` (Forever). Folder name must be exactly `CooldownCollaborator`.
- The packager (BigWigs v2) maps `_Camelot` / 16xxx to CurseForge's Forever game version.
- Current version: **1.1.0** (Interface 120105 / 16001). v1.1.0 added WoW: Forever, the send-result fix, request/reply resync, saved own cooldowns, known-spells reports. v1.0.3 added live local readiness for Battle-Rez/Bloodlust (see the combat-res gotcha above); v1.0.1 built-in consumable + flask/food strip; v1.0.2 minimap button polish.

## Conventions
- **Never** append a `Co-Authored-By` trailer to commits.
- Validate Lua before deploying (`pip install luaparser`; `luaparser.ast.parse`).
