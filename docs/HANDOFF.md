# Handoff: CooldownTimeline3 and CooldownCollaborator (19 Nov 2026)

Read this, then each repo's CLAUDE.md, then `docs/REVIEW_PLAN.md` here. Nothing in this file is pushed or released.

## Standing rules that bit this session

- Nothing merges, pushes or releases without his boop. Version numbers are his call.
- Pace: one build lane at a time; Sonnet for bounded lanes, Opus only for genuinely hard work; give a lane only
  the files it needs; targeted tests while working, ONE full suite per release at the end. (Broken on 19 Nov:
  three Opus lanes at once burned most of a 5-hour limit.)
- Walk sheets: no install lines, no pasted UI labels as nouns, ~15 lines, only what needs his game client.
- Don't explain causes you haven't traced; say "I don't know" and look.
- "Where is X on a site": give the URL first.

## CooldownTimeline3 (source\repos\cdtl3-dev)

- Released: 3.2.2 (17 Nov). Branch `luals-sweep` (34 commits on main, HEAD 34f4686, local, not pushed): the code
  tidy (WoW API check at 0 warnings, copied code removed, byte-identical dumps). Its walk
  `2026-11-17-tidy` passed 12 of 13; line 11 (Boss fights only) works as designed (the boss part is untested);
  line 14 (Collaborator raid rez) is still open. Waiting on his boop.
- Noted, not done: the minimap button drags wrong on a resized minimap (same code Collaborator had, R33);
  "starts when used" spells never poll charge pips (old observation, kept).
- Walk sheet: https://claude.ai/artifact/FV8n7sXuHA3VKe27K9obgp (db-backed, collection `items`; Collaborator walks
  live there too).

## CooldownCollaborator (source\repos\CooldownCollaborator)

- Released: 1.1.1. Branches (local, not pushed): `rez-fix-tidy` (tidy + Request Rez fix + Wago ID `b6XyoxKp`;
  he added the `WAGO_API_KEY` secret), `crash-fix` (round 1 only: the Essentials bar raid crash and windows
  closing on leaving a group; could ship alone as 1.1.2), and `review-build` (worktree `source\repos\cc-wt\build`,
  everything below).
- `review-build` holds the whole 18 Nov review: 33 red team + 48 feature panel cards, all marked Go by him
  (Collaborator Review List https://claude.ai/artifact/LKvL23ka5LFhQFXHkY4fUX), his 31 look picks (Collaborator
  Looks https://claude.ai/artifact/QdvWKQfJxWYo86vZjc8MXc), message format 2 (`docs/MESSAGE_FORMAT_2.md`),
  translations, Settings with six tabs, docs, and a final review's 15 fixes. Last full suite: 60/60 green (before
  the surname fix below, which passed its targeted tests).

### His walk of the review build (19 Nov, walk `2026-11-19-cc-review`): "Not impressed."

Fixed after the walk: on WoW: Forever, chat senders carry a surname ("Devilin Nyx") while UnitName gives "Devilin",
so every group message was dropped as "not from a group member" (commit 44cb756, zip
`cdtl3-dev\dist\CooldownCollaborator-1.1.1-review-2.zip`). This is probably why the dead list showed nobody and the
panel said nobody else runs it. He has not re-walked with it.

Still to do, from his notes and screenshots (his words in quotes):
1. Getting Started: "It looks TERRIBLE with no context of what each window does." Each window needs a line saying
   what it is for; the page needs a real design pass.
2. Presets: the label and wording ("'The Show'? You're just making word salad").
3. Ready alert sound picker: "a cycle button is stupid": a dropdown.
4. Profiles: "No profile picker, no default. This is a baseline addon function across all addons. FAIL." Needs a
   real profile picker with a Default profile, like every Ace addon.
5. `/cdc support`: "What is the point of this?": drop it or make it worth having (his call).
6. Rebirth's tooltip shows the highest rank, "Not the actual rank they have."
7. `/cdc roster`: "Weird chat output" (code words like "capabilities: BATTLEREZ").
8. Dead list "Not showing other player at all" and the Guild tab not showing a level-19 guildmate who runs it:
   re-check after the surname fix.
9. From the screenshots: the Lane view sits on top of the main panel at default places; the "Guild master and
   officers" button text overflows; a Guild tab showed with guild sharing off (check UI.lua's tab list); the
   bell button's icon doesn't look like a bell.
10. Lines not walked: raid (Forever raids aren't open yet), party dead-list / lastpull / post with a second player.
11. At release: version number (his call); the CurseForge translation tool needs the English phrase list
    (`Locales/enUS.lua`) imported once (his CurseForge sign-in is in this PC's Chrome; ask first); store text is
    in `docs/DESCRIPTION.md` ("Next version" changelog entry); paste into CurseForge and Wago descriptions by hand.

The overall verdict was about look and polish, so the next step is a design pass on the windows and the Settings
window with him (his rules: visual work follows a design step he drives, a look board shows several choices),
then a fix lane, then a short re-walk.

## Housekeeping

- Worktrees left: `cc-wt\build` (review-build) and `cc-wt\round1` (crash-fix). The others were removed; their
  branches stay. cdtl3-dev's old worktree `cdtl3-wt\probe-items-boss` is still there.
- Tests: `powershell -File tools\tests\runall.ps1` with `$env:FENGARI_DIR =
  'C:/Users/gwilkins/source/repos/cdtl3-dev/tools/spell-list-check/node_modules/fengari'` when run from a
  worktree. Zip a test build with the `.pkgmeta` ignore list applied (a `CooldownCollaborator` folder).
