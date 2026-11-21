#!/bin/sh
# The Mac and Linux twin of runall.ps1: every harness against every TOC (all six clients), one RESULT line
# per harness and TOC plus any FAIL or Lua error lines. A harness that dies before its RESULT line prints
# NO RESULT, so a crash can't pass for green. Keep the two harness lists in step.
# Needs Node 18+ and fengari from a sibling cdtl3-dev checkout
# (cdtl3-dev/tools/spell-list-check: npm ci), or FENGARI_DIR.
#   sh tools/tests/runall.sh [addon folder]
here=$(cd "$(dirname "$0")" && pwd)
addon=${1:-$(cd "$here/../.." && pwd)}
runner="$here/run.js"
bad=0
for h in checks.lua groups.lua sync.lua looks.lua essentials.lua panel.lua asks.lua settings.lua final.lua locale.lua "locale.lua pseudo"; do
	hf=${h%% *}; ha=""; [ "$hf" != "$h" ] && ha=${h#* }
	for t in CooldownCollaborator_Mainline.toc:120105 CooldownCollaborator_Mists.toc:50504 CooldownCollaborator_TBC.toc:20506 \
		CooldownCollaborator_Vanilla.toc:11509 CooldownCollaborator_Camelot.toc:16001 CooldownCollaborator.toc:16001; do
		toc=${t%%:*}; iface=${t##*:}
		out=$(node "$runner" "$addon" "$iface" "$here/$hf" "$toc" $ha 2>&1)
		result=$(printf '%s\n' "$out" | grep '^RESULT' | head -1)
		if [ -n "$result" ]; then
			printf '%s\n' "$out" | grep -E '^RESULT|FAIL|LUA ERROR'
			case "$result" in *"fails 0, lua errors 0") ;; *) bad=$((bad + 1)) ;; esac
		else
			echo "NO RESULT: $h $toc (lua errors 1)"
			printf '%s\n' "$out" | tail -3 | sed 's/^/  FAIL /'
			bad=$((bad + 1))
		fi
	done
done
[ "$bad" -eq 0 ]
