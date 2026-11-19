-- English base for CooldownCollaborator. The English text is the key, so a phrase with no
-- translation shows in English. Other languages: the files beside this one, filled from the
-- CurseForge translation tool when a release is packaged. Keep this table in step with the
-- L["..."] lookups in the code (python tools/gen-enus.py rebuilds it; tools/tests/locale.lua checks it).
local L = CooldownCollaborator.NewLocale("enUS")
if not L then return end

--@localization(locale="enUS", format="lua_additive_table", same-key-is-true=true)@

-- CooldownCollaborator.lua
L["Spell %d"] = true
L["Unknown spell ID: %d"] = true
L["Added: %s (%ds)"] = true
L["No Battle Rez charges."] = true
L["No Battle Rez charges; next in %d:%02d"] = true
L["Only the raid leader or an assist can request a rez in a raid."] = true
L["Target a dead friendly player first."] = true
L["Can't read that target's name. Target a dead friendly player first."] = true
L["No living Battle Rez provider available right now."] = true
L["Battle Rez"] = true
L["%s, please %s %s!"] = true
L["windows locked."] = true
L["windows unlocked."] = true
L["position reset."] = true
L["verbose cast logging: %s"] = true
L["ON"] = true
L["OFF"] = true
L["Essentials bar: %s"] = true
L["(it shows when you're in a group)"] = true
L["Lane view: %s"] = true
L["Support: copy this into your report"] = true
L["usage: /cdc consumable <spellID> <seconds> <flask|food|other> <name>  |  /cdc consumable remove <spellID>"] = true

-- Bridge.lua
L["Group cooldowns"] = true

-- UI.lua
L["DEAD"] = true
L["OFFLINE"] = true
L["Nothing is cooling down. Ready cooldowns are hidden (Settings: Show ready cooldowns)."] = true
L["Nobody on this team has used a tracked cooldown yet."] = true
L["Nothing used yet. Your own cooldowns show here once you use one; in a group, everyone's do."] = true
L["Nobody else here runs CooldownCollaborator, so only your own cooldowns can show. Nothing has been used yet."] = true
L["Nobody else here runs CooldownCollaborator; casts seen in the combat log still show. Nothing has been used yet."] = true
L["%d of %d here run CooldownCollaborator (%s and you). Nothing has been used yet; cooldowns show once someone uses one."] = true
L["%d of %d here run CooldownCollaborator. Nothing has been used yet; cooldowns show once someone uses one."] = true
L["READY"] = true
L["Lust"] = true
L["%d of %d"] = true
L["The game didn't let that message go out just now."] = true
L["%s, %s on me please"] = true
L["%s on me please"] = true
L["Click: whisper to ask for it. Shift-click: ask in group chat."] = true
L["Post to chat"] = true
L["Says what is ready, and who has it, in group chat (the spells picked in Settings)."] = true
L["Close"] = true
L["It stays shut until /cdc or the minimap button opens it."] = true
L["Nothing used yet."] = true
L["All"] = true
L["Group"] = true
L["Guild"] = true
L["NEXT"] = true
L["+%d more running"] = true
L["+%d more spell ready"] = true
L["%d spell ready"] = true
L["+%d more spells ready"] = true
L["%d spells ready"] = true
L["Ready"] = true
L["+%d more"] = true
L["Outside your group: %d run it"] = true

-- Tooltip.lua
L["Brings a dead player back."] = true
L["For the burn: haste for the whole group, once a fight."] = true
L["For one player about to take a big hit."] = true
L["For a big hit on the whole group."] = true
L["Its owner's own life saver; it can't be given to anyone else."] = true
L["For a healer running low on mana."] = true
L["Help that isn't a heal or a shield: movement, taunts, a burst and more."] = true
L["%s and %s"] = true
L["Ready: %s"] = true
L["%s: ready as far as we know."] = true
L["%s \194\183 dead"] = true
L["%s \194\183 offline"] = true
L["%s \194\183 back in %s"] = true
L["%s \194\183 ready as far as we know"] = true
L["%s \194\183 ready"] = true
L["Its effect: %s left"] = true
L["Ready as far as we know."] = true
L["Seen in the combat log; their copy hasn't said it's back."] = true
L["Kept from before your /reload; nobody has said since."] = true
L["Doesn't run CooldownCollaborator and hasn't been seen casting."] = true
L["Runs an old 1.x copy; the current version is %s."] = true
L["Runs %s; the current version is %s."] = true
L["Old copies can undo ready-now messages."] = true

-- Alerts.lua
L["%s in %ds"] = true

-- Roster.lua
L["Bloodlust/Heroism"] = true

-- Essentials.lua
L["lust"] = true
L["no charges %s"] = true
L["no charges"] = true
L["Dead: can't use it now."] = true
L["Offline."] = true
L["cooling: %s"] = true
L["Defensives"] = true
L["Defensives: %d of %d ready"] = true
L["Essentials"] = true
L["Rez"] = true
L["Target a dead player, then click to announce"] = true
L["which Battle Rez provider should rez them."] = true
L["+%d more, %d ready"] = true
L["+%d more, next %s"] = true
L["Bloodlust"] = true
L["Sated"] = true
L["%s on the dead"] = true
L["%s: %d ready"] = true
L["Soulstones placed: %d"] = true
L["Reincarnation (yours): %s"] = true
L["ready"] = true
L["Soulstones %d"] = true
L["tank %d"] = true
L["healer %d"] = true
L["on %s"] = true
L["%s's runs out in %s"] = true
L["Ready check"] = true
L["Pull in %d"] = true
L["Pull timer"] = true
L["none"] = true
L["rez charges"] = true
L["rez"] = true
L["externals"] = true
L["You're the %s, the only one"] = true
L["You're a %s, one of %d"] = true
L["%s: %d missing"] = true
L["and %d more"] = true
L["%d not known (they don't run CooldownCollaborator)"] = true
L["Post to raid"] = true
L["Post to party"] = true
L["Post to instance"] = true
L["Post to group"] = true
L["Missing %s (%d): "] = true
L["; %d not known"] = true

-- Lanes.lua
L["next hit cleared."] = true
L["usage: /cdc nexthit <seconds or M:SS>  |  /cdc nexthit off"] = true
L["next hit in %s: cooldowns back by then get a gold ring on the Lane view."] = true
L["next hit in %s: cooldowns back by then get a gold ring on the Lane view (it's off: /cdc lanes)."] = true
L["Lanes"] = true
L["Lane view: OFF (/cdc lanes brings it back)"] = true
L["none ready"] = true
L["next hit %s"] = true

-- DeadList.lua
L["Healer"] = true
L["Tank"] = true
L["Damage"] = true
L["Call"] = true
L["Dead list"] = true
L["Nobody living has a Battle Rez ready"] = true
L["Answers: %s, %s |cFF4DFF4DREADY|r"] = true
L["Dead (%d), in your order"] = true
L["Dead (%d)"] = true

-- Strips.lua
L["Externals"] = true
L["Mana"] = true
L["asked %s for %s."] = true
L["Nobody else in the group has a mana spell ready."] = true
L["Ask"] = true
L["Whisper %s:"] = true

-- Burst.lua
L["You"] = true
L["now"] = true

-- Plan.lua
L["Only the group's leader or a raid assist can share a plan."] = true
L["That plan is too long to share."] = true
L["%s shared the raid plan \"%s\" (%d rows)."] = true

-- Consumables.lua
L["Dragonslayer"] = true
L["Rallying Cry of the Dragonslayer"] = true
L["Zandalar"] = true
L["Spirit of Zandalar"] = true
L["Songflower"] = true
L["Songflower Serenade"] = true
L["Warchief's Blessing"] = true
L["Dire Maul"] = true
L["Dire Maul buffs"] = true
L["Protection potion"] = true
L["Elixir"] = true
L["Flask"] = true
L["Food"] = true
L["Consumable %d"] = true
L["tracking consumable: %s (%ds)%s"] = true
L["no consumable you added has spell ID %d (the built-in ones can't be removed)."] = true
L["stopped tracking consumable: %s"] = true

-- Minimap.lua
L["Left-click: Toggle panel"] = true
L["Right-click: Open settings"] = true
L["Drag: Reposition button"] = true

-- Setups.lua
L["%d default spell ticked or unticked (%d unticked afterwards)"] = true
L["%d default spells ticked or unticked (%d unticked afterwards)"] = true
L["%d custom spell added or removed (%d afterwards)"] = true
L["%d custom spells added or removed (%d afterwards)"] = true
L["%d ready alert added or removed (%d afterwards)"] = true
L["%d ready alerts added or removed (%d afterwards)"] = true
L["%d window moved"] = true
L["%d windows moved"] = true
L["Nothing changes: this is what you have now."] = true
L["Import"] = true
L["Import a setup: paste it here"] = true
L["That isn't a CooldownCollaborator setup."] = true
L["It will change:\n- %s\nClick Import again to do it."] = true
L["Setup imported. Settings > Profiles can undo it."] = true
L["Only a guild officer can send a setup to the guild."] = true
L["That setup is too long to send."] = true
L["Accept"] = true
L["Not now"] = true
L["Never"] = true
L["%s%s sent a setup to the guild.\nIt will change:\n- %s\n\nAccept it, not now, or never from this person?"] = true
L["Setup from %s accepted. Settings > Profiles can undo it."] = true
L["%d tracked cooldown used"] = true
L["%d tracked cooldowns used"] = true
L["No pull logged yet."] = true
L["Last pull (%s): %s, %s."] = true
L["Last pull: %s, %s."] = true
L["Join a group first."] = true
L["Nothing to post for the spells picked."] = true
L["%s %s: %s. /cdc lastpull to see them."] = true
L["Fight"] = true
L["kill"] = true
L["wipe"] = true
