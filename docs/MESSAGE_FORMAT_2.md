# Message format 2 (CooldownCollaborator, 18 Nov 2026)

The schema step for round 3 of docs/REVIEW_PLAN.md. Every sync feature builds on this. Goals: say who runs the
addon and which version (P13), fill in a joiner or a /reload at once (P16, R4), send gently in big raids (P35),
stop forged or relayed cooldowns (R11, R10), and leave room for the guild, plan and setup messages (P41, P42,
P12, P39, P11). Old copies (1.0.x, 1.1.x) must keep working beside new ones.

Built on the `review-sync` branch (19 Nov 2026): Comms.lua holds the wire, the queue and the receivers. Where
the build differs from the first draft of this page, the text below says what was built, and "Changes from the
draft" at the end lists each difference and why.

## What stays

- Prefixes `CDCOLLAB` (cooldowns) and `CDCBUFF` (flask and food).
- A cast is still announced as the 1.x line `spellID:secondsAgo:name:class`, and ready-now as `R:spellID`. Both
  old and new copies read them, so a mixed group keeps working. (Casts come one at a time, so batching them
  gains nothing; the batch below is for state.)
- `CDCBUFF` `flask:N:food:N` stays as is.

## New kinds (CDCOLLAB, a letter then `:`; old copies drop them: `tonumber("H")` is nil)

All new messages start `<kind>:2:` (2 = format version). Fields are `:`-separated; lists use `,` inside an entry
and `;` between entries. One message is at most 255 bytes; longer content is split as described under Chunks.

| Kind | Body | Sent when | Answer |
|---|---|---|---|
| `H` hello | `H:2:<addonVersion>:<client>` (client = `retail`, `mists`, `tbc`, `era`, `forever`) | on joining a group, on login or /reload while grouped (after a random 1 to 3 s wait), and as part of the answer to a `Q` | none |
| `Q` state request | `Q:2` | right after your own hello on join, login or /reload | each member who runs format 2 answers with `H`, `S` and `CDCBUFF`, after a random 0 to 3 s wait. One answer per member per 10 s: a request inside the 10 s is answered when they are up, and an `S` still waiting in the queue answers any request that arrives meanwhile |
| `S` state | `S:2:<class>:<id>,<secondsAgo>;<id>,<secondsAgo>;...` (a list too long for one message: every part but the last ends `;+`) | in answer to `Q`; right after your own `Q` on join, login or /reload (so the group hears what you have running); and at every boss end (with the per-spell 1.x lines as well while a 1.x copy is in the group) | none |
| `C` battle rez charges | `C:2:<charges>:<max>:<secondsToNext>` (whole seconds; `C:2:0:0:0` = the pool is gone) | by a player who can read the raid's charge pool (their own rez spell), when it changes, after a random 0 to 1.5 s; skipped when another reader has just said the same | none |
| `T` Soulstone placed | `T:2:<Name-Realm>:<secondsAgo>` (the target; one decimal) | Retail and Forever only: by the warlock when its own Soulstone lands on a living group member (also in the answer to `Q`, on joining and at a boss end while the stone lasts). Era, TBC and MoP see it in the combat log, so nothing is sent there | none |
| `P` plan / order | `P:2:<planId>:<part>/<parts>:<data>` | when a leader shares a raid cooldown plan or a rotation order | none |
| `O` officer setup | `O:2:<setupId>:<part>/<parts>:<data>` | guild channel only, when an officer sends a setup | the member's own Accept / Not now / Never |

`S` lists only the sender's own cooldowns that are still running, flasks and food included (a ready spell is left
out: absence means ready). `secondsAgo` has one decimal. On receipt each listed entry replaces what the receiver
holds for that sender (the sender's own word). A built-in spell of the sender's that the receiver holds as
running but the whole list leaves out is set ready; two kinds are left to run out instead: a timer from the
combat log (the sender's copy may be older and not track that spell) and a custom spell (the sender may not have
it). The receiver's `CC.rezCharges = { charges, max, nextAt, from }` comes from `C`.

## The combat rez pool and Soulstones (19 Nov additions)

- In raids and Mythic+ every combat rez (Rebirth, Intercession, Raise Ally and, on Retail and MoP, Soulstone)
  uses one charge pool. Readers are a player's own Battle Rez spell and, on Retail and MoP, a warlock's
  Soulstone. `CC:RezPool()` gives the pool counted on to now (a recharge that has come due adds its charge).
  When it is known and empty, nobody can be brought back, a placed Soulstone included: every Battle Rez entry
  of `GetCapabilityStatus` carries `noCharges = true` (data only; the bar's look comes later), and Request Rez
  prints "No Battle Rez charges; next in M:SS" instead of naming a rezzer.
- `T` belongs to its sender, the warlock: the body names the stone's target, which must be a current group
  member; `secondsAgo` must lie in 0 .. the buff's length. Every copy keeps `CC.stones[target] = { from,
  placedAt, duration }`; `duration` is the buff's length in the game data (SpellDuration: 900 s on Retail and
  MoP, 1800 s on Era, TBC and Forever; a `buff` field on the Soulstone data row wins). One stone per warlock: a
  new one replaces their last. The warlock's own copy takes the target as the cast starts
  (`UNIT_SPELLCAST_SENT`: the cast's target name, else a friendly player targeted, else the warlock itself, all
  in a pcall) and records it when the cast lands on someone living; a Soulstone on the dead is a rez, not a
  placement. Era, TBC and MoP record other warlocks' stones from the combat log's `SPELL_CAST_SUCCESS` target.
  Stones are saved with the timers and pruned when their target leaves the group or the buff runs out.

## Who a cooldown belongs to

- A format 2 message always belongs to its sender (the game's Name-Realm). Nothing in a body can name someone
  else. A 1.x `R:spellID` is the sender's own too.
- A 1.x cast line is accepted only when its bare name is the sender's own name. Old 1.0.1 to 1.0.3 copies relayed
  other players' state with someone else's name; those relays are dropped (that relay is what undid ready-nows,
  R10, and what let a hand-made message pin a cooldown on another player, R11).
- `secondsAgo` must lie in 0 .. the spell's duration; a negative, huge or not-a-number value is dropped, not
  stored (in `S` an entry must be `<digits>,<digits and a point>`).
- Messages are accepted only from the group channels (`PARTY`, `RAID`, `INSTANCE_CHAT`) and only from a current
  group member; whispers are ignored, and so are our own messages coming back. `GUILD` is read only for `O`,
  into its own table, never into the group's.

## A copy's version

`CC.peers[name] = { version, client, proto = 2, heardAt }` from hellos (a hello of a later format, `H:3:...`, is
recorded the same way with its number). A member heard sending 1.x lines (a cast or `R:`) but no hello is
`proto = 1`. A member who leaves the group is forgotten. That table drives: who runs it (P13, `/cdc roster`
prints the version, "old version" for an older one or a 1.x copy, "no hello" for a member no copy was heard
from), whether a boss end still sends 1.x lines (only while a `proto = 1` member is in the group), and the
guessed marks (P44: `GetCapabilityStatus` sets `guessed = true` for a provider with no hello, no cast seen and no
combat-log cast: "ready as far as we know").

## Sending gently

All CDCOLLAB and CDCBUFF sends go through one queue: at most one message every 0.25 s per channel (an attempt
the game refuses counts), answers jittered as above, the same text on the same channel again within 1 s dropped,
and the 1.x retry rule kept (a send the game refuses is tried again every 2 s, 15 times at most). A message is
built when it goes out, so waiting in the queue doesn't age its `secondsAgo`. After a boss ends, ready-nows the
game refused during that fight are re-sent once, for spells still ready (R9). Nothing is queued while solo: a
cast made solo reaches the group in the `S` sent on joining.

## Chunks

`P` and `O` data is the same text encoding the profile export uses (P15): a version, then key=value pairs,
escaped for `:` `;` `,`. Split into parts of at most 200 bytes of data; the receiver keeps parts for 30 s and
uses the content only when all parts of one id have arrived: `CC.payloads[kind][sender][id] = { data, at }`
(ids are letters, digits, `_` and `-`, 32 at most; 64 parts at most). Nothing reads them yet.

## Saved timers (R4, P16)

At logout or /reload every running timer is saved as a real clock time: `db.timers = { wall = time(), clock =
GetTime(), players = { [Name-Realm] = { class, spells = { [id] = time() it was used } } }, stones = { [target] =
{ from, at = time() placed, duration } } }`. At login ours come
back at once and a groupmate's once they are in the group (for a minute after login); after a /reload, where
`GetTime()` has gone on, the saved clock pair gives the exact time, otherwise `time()` gives it to the second. A
restored time never beats a live message: any cast line or `S` entry that differs from it by more than 0.25 s
replaces it, and an `S` that leaves it out sets it ready. The game writes saved data only at logout or /reload,
so after a crash only what the group answers to our `Q` comes back.

## Changes from the draft

- Hellos are answered through the state request. The draft answered a hello from someone not heard before; a
  joiner (or a /reload) always sends `Q` right after `H`, so the answer to `Q` now carries `H` too. That way a
  /reload, whose sender the others heard before, still learns everyone's version, and nobody answers the
  answers.
- The joiner also sends its own `S` (and `CDCBUFF`) after its `Q`: the draft's `Q` only filled in the joiner, not
  the group about the joiner's own running cooldowns (or a cast made while solo).
- One answer per 10 s defers a later request to the end of the 10 s instead of dropping it, so a second joiner
  inside the window still gets an answer.
- `S` at a boss end is sent always, also when a 1.x copy is in the group (then with the 1.x lines too), so the
  absence rule clears anything the fight held back.
- `S` gained the `;+` continuation, so "absence means ready" still holds for a list split over messages.
- `C` gained `C:2:0:0:0` for the end of the pool, and readers skip a repeat of what another reader just sent.
- The saved-timer format (`db.timers`) is new; the draft only named the goal.
