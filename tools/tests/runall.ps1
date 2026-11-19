# Runs tools/tests/checks.lua, groups.lua, sync.lua and essentials.lua against every TOC (all six
# clients) and prints one RESULT line per harness and TOC, plus any FAIL or Lua
# error lines. A harness that dies before its RESULT line prints NO RESULT, so a
# crash can't pass for green.
# Needs Node 18+ and fengari from a sibling cdtl3-dev checkout
# (cdtl3-dev\tools\spell-list-check: npm install), or FENGARI_DIR.
#   powershell -File tools\tests\runall.ps1 [-Addon <addon folder>]
param([string]$Addon = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path)

$tocs = @(
    @{ Toc = 'CooldownCollaborator_Mainline.toc'; Interface = 120105 },
    @{ Toc = 'CooldownCollaborator_Mists.toc';    Interface = 50504 },
    @{ Toc = 'CooldownCollaborator_TBC.toc';      Interface = 20506 },
    @{ Toc = 'CooldownCollaborator_Vanilla.toc';  Interface = 11509 },
    @{ Toc = 'CooldownCollaborator_Camelot.toc';  Interface = 16001 },
    @{ Toc = 'CooldownCollaborator.toc';          Interface = 16001 }
)
$runner = Join-Path $PSScriptRoot 'run.js'
$harnesses = @('checks.lua', 'groups.lua', 'sync.lua', 'essentials.lua')
$bad = 0
foreach ($h in $harnesses) {
    $harness = Join-Path $PSScriptRoot $h
    foreach ($t in $tocs) {
        $out = @(& node $runner $Addon $t.Interface $harness $t.Toc 2>&1 | ForEach-Object { "$_" })
        $result = @($out | Where-Object { $_ -cmatch '^RESULT' })
        if ($result.Count -gt 0) {
            $out | Where-Object { $_ -cmatch '^RESULT|FAIL|LUA ERROR' }
            if ($result[0] -notmatch 'fails 0, lua errors 0$') { $bad++ }
        } else {
            "NO RESULT: $h $($t.Toc) (lua errors 1)"
            $out | Select-Object -Last 3 | ForEach-Object { "  FAIL $_" }
            $bad++
        }
    }
}
if ($bad -gt 0) { exit 1 }
