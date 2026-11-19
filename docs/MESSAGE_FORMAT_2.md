# Message format 2 (CooldownCollaborator, 18 Nov 2026)

The schema step for round 3 of docs/REVIEW_PLAN.md. Every sync feature builds on this. Goals: say who runs the
addon and which version (P13), fill in a joiner or a /reload at once (P16, R4), send gently in big raids (P35),
stop forged or relayed cooldowns (R11, R10), and leave room for the guild, plan and setup messages (P41, P42,
P12, P39, P11). Old copies (1.0.x, 1.1.x) must keep working beside new ones.

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
| `H` hello | `H:2:<addonVersion>:<client>` (client = `retail`, `mists`, `tbc`, `era`, `forever`) | on joining a group, on login or /reload while grouped, and once in answer to a hello from someone not heard before (after a random 0 to 2 s wait) | none |
| `Q` state request | `Q:2` | right after your own hello on join, login or /reload | each member who runs format 2 answers with `S` and re-sends `CDCBUFF`, after a random 0 to 3 s wait (one answer per member per 10 s however many requests arrive) |
| `S` state | `S:2:<class>:<id>,<secondsAgo>;<id>,<secondsAgo>;...` | in answer to `Q`, and at a boss end (replacing the per-spell 1.x lines when no 1.x copy is in the group) | none |
| `C` battle rez charges | `C:2:<charges>:<max>:<secondsToNext>` | by a player who can read the raid's charge pool (their own rez spell), when it changes | none |
| `P` plan / order | `P:2:<planId>:<part>/<parts>:<data>` | when a leader shares a raid cooldown plan or a rotation order | none |
| `O` officer setup | `O:2:<setupId>:<part>/<parts>:<data>` | guild channel only, when an officer sends a setup | the member's own Accept / Not now / Never |

`S` lists only the sender's own cooldowns that are still running (a ready spell is left out: absence means ready).
`secondsAgo` has one decimal.

## Who a cooldown belongs to

- A format 2 message always belongs to its sender (the game's Name-Realm). Nothing in a body can name someone
  else.
- A 1.x cast line is accepted only when its bare name is the sender's own name. Old 1.0.1 to 1.0.3 copies relayed
  other players' state with someone else's name; those relays are dropped (that relay is what undid ready-nows,
  R10, and what let a hand-made message pin a cooldown on another player, R11).
- `secondsAgo` is clamped to 0 .. the spell's duration; a negative or huge value is dropped, not stored.
- Messages are accepted only from the group channels (`PARTY`, `RAID`, `INSTANCE_CHAT`) and only from a current
  group member; whispers are ignored. `GUILD` is read only by the guild features, into their own table, never
  into the group's.

## A copy's version

`CC.peers[name] = { version, client, proto = 2, heardAt }` from hellos. A member heard sending 1.x lines but no
hello is `proto = 1`. That table drives: who runs it (P13), "old version" notes, whether a boss end still sends
1.x lines (only while a `proto = 1` member is in the group), and the guessed marks (P44: a provider with no
hello, no cast seen and no combat-log cast is "ready as far as we know").

## Sending gently

All CDCOLLAB and CDCBUFF sends go through one queue: at most one message every 0.25 s per channel, answers and
hellos jittered as above, a repeat of the same message within 1 s dropped, and the 1.x retry rule kept (a send
the game refuses is tried again every 2 s, 15 times at most). After a boss ends, refused ready-nows from that
fight are re-sent once (R9).

## Chunks

`P` and `O` data is the same text encoding the profile export uses (P15): a version, then key=value pairs,
escaped for `:` `;` `,`. Split into parts of at most 200 bytes of data; the receiver keeps parts for 30 s and
uses the content only when all parts of one id have arrived.
