# CooldownCollaborator — CLAUDE.md

Group & raid cooldown coordinator for **WoW Midnight (12.x)**. Author: Nelnamara.
Tracks party/raid members' major defensive & utility cooldowns, an Essentials bar
(Bloodlust/Battle-Rez "ready" providers + Rez request), a Lane view, group
flask/food status, and a minimap button.

## Files
- `CooldownCollaborator.lua` — core: init, DB defaults, event frame, `RecordCooldown`, Rez logic, slash `/cdc`.
- `Data.lua` — `CC.SpellData` (tracked-spell whitelist), `CC.BuiltinConsumables`, `CC.ClassColors`.
- `Comms.lua` — addon messaging. Prefixes: `CDCOLLAB` (cooldown sync) and `CDCBUFF` (flask/food status).
- `Roster.lua` — `NotifyInspect` queue for spec detection; capability scan.
- `Essentials.lua` — the Essentials bar (ready providers + flask/food strip).
- `Lanes.lua` — Lane view (stacked provider timelines).
- `Consumables.lua` — self-poll of own flask/food auras → broadcast category presence.
- `UI.lua`, `Options.lua`, `Minimap.lua`.

## Midnight API gotchas (critical)
- `aura.spellId` / `aura.name` are **SECRET** even on `"player"`. Only safe lookup is `C_UnitAuras.GetPlayerAuraBySpellID(knownID)`. This is why flask/food tracking is peer-broadcast (each client detects its own, announces via `CDCBUFF`).
- `UNIT_SPELLCAST_SUCCEEDED.spellID` is **SECRET** for party/raid tokens — only `"player"` is safe. Other players' cooldowns arrive only via the `CDCOLLAB` addon message.
- `GetTime()` is per-client (seconds since that client's process start). Wire **secondsAgo**, not a raw timestamp; receiver re-anchors with `GetTime() - secondsAgo`.
- `RegisterUnitEvent` **overwrites** the unit filter (doesn't accumulate) — use `RegisterEvent` + manual token filtering.
- `AreOutgoingAddonChatMessagesRestricted()` is unreliable — attempt the send and queue/retry on a non-nil result code.

## Slash
`/cdc` (toggle) · `verbose` · `roster` · `debug` · `essentials` · `lanes` · `rez` · `consumable <id> <dur> <name>` · `lock`/`unlock` · `settings`

## Build / release / deploy
- BigWigs **packager runs on `v*` tag push** (GitHub Actions). Pushing `main` does NOT release.
- CurseForge API secret is named **`CURSFORGE_API_KEY`** (misspelled — missing the E — but consistent across the suite; do not "fix" it).
- Local test deploy: copy changed files to `D:\World of Warcraft\_retail_\Interface\AddOns\CooldownCollaborator\`.
- Current version: **1.0.2** (Interface 120007).

## Conventions
- **Never** append a `Co-Authored-By` trailer to commits.
- Validate Lua before deploying (`pip install luaparser`; `luaparser.ast.parse`).
