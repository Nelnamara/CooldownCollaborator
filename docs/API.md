# CooldownCollaborator public feed (CC.API)

Other addons can read who has which tracked cooldown and when it is back, and listen for cooldowns starting,
coming back, and fights ending. CooldownCollaborator sets one global when it loads:

```lua
local API = _G.CooldownCollaboratorAPI   -- nil when CooldownCollaborator is not loaded
```

All calls are safe to make at any time. Callbacks run inside `xpcall`: an error in yours is reported to the
game's error handler and never stops ours or another addon's.

## Calls

| Call | Returns |
| --- | --- |
| `API.version` | `1`. Raised only when a call or callback changes shape. |
| `API.GetGroup()` | `{ { name = "Name-Realm", class = "DRUID", spells = { { spellID, name, ready, remaining }, ... } }, ... }`: every group member the addon knows, with the tracked spells their class has (for you, the ones in your spellbook). `remaining` is seconds, `nil` when ready. |
| `API.GetCooldown(name, spellID)` | seconds until the spell is back, or `nil` when it is ready or not tracked for that player. Any rank's ID works. |
| `API.RegisterCallback(owner, event, fn)` | `true`, or `false` for an unknown event or a non-function. One callback per `owner` and event (a second replaces the first); `owner` is any value you choose, usually your addon's table. |
| `API.UnregisterCallback(owner, event)` | nothing |

## Events

| Event | Arguments | When |
| --- | --- | --- |
| `"start"` | `name, spellID, duration` | a tracked cooldown started: a cast we saw or a group member reported (the same cast reported twice within 5 s is one start) |
| `"ready"` | `name, spellID` | a cooldown that was reported with `"start"` is back (checked once a second) |
| `"end"` | `bossName, success` | a fight ended: an encounter (`bossName` and `success` true for a kill, false for a wipe) or plain combat (both `nil`) |

`name` is `Name-Realm`. Cooldowns the addon never heard about are neither listed as running nor reported.

## Example

```lua
local mine = {}
local API = _G.CooldownCollaboratorAPI
if API then
    API.RegisterCallback(mine, "ready", function(name, spellID)
        print(name, "has", spellID, "back")
    end)
end
```
