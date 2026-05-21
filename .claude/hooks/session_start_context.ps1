# SessionStart hook - prints a short orientation block for this repo.
# Claude Code injects this script's stdout into the session context, so Claude
# starts already knowing the core invariant, where the subsystem guides are, and
# which guides cover the current uncommitted work.
#
# Run standalone to test:  pwsh -NoProfile -File .claude/hooks/session_start_context.ps1

$ErrorActionPreference = 'SilentlyContinue'

# Repo root = two levels up from this script (.claude/hooks/).
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

$out = [System.Collections.Generic.List[string]]::new()
$out.Add('## Orientation - multiplayer-test (Godot 4 multiplayer RPG)')
$out.Add('')
$out.Add('Server-authoritative: the server owns all state; clients send intent via RPCs.')
$out.Add('Read the root CLAUDE.md, then the CLAUDE.md in whichever subsystem you edit.')
$out.Add('Account/character persistence needs the backend up (docker-compose up -d).')
$out.Add('Content work follows skills: add-ability, add-buff, add-item, add-enemy, add-map, add-backend-endpoint.')
$out.Add('')

# Subsystem CLAUDE.md guides that currently exist (a self-maintaining index).
$guides = @()
foreach ($area in @('scripts', 'backend')) {
    $dir = Join-Path $root $area
    if (Test-Path $dir) {
        Get-ChildItem -Path $dir -Recurse -Filter 'CLAUDE.md' -File |
            ForEach-Object { $guides += $_.DirectoryName.Substring($root.Length + 1).Replace('\', '/') }
    }
}
if ($guides.Count -gt 0) {
    $out.Add("Subsystem guides: $($guides -join ', ')")
}

# Map uncommitted changes to the subsystem guide(s) they touch.
$changed = @(git -C $root status --porcelain 2>$null |
    Where-Object { $_.Length -gt 3 } |
    ForEach-Object { $_.Substring(3).Trim().Trim('"').Replace('\', '/') })
if ($changed.Count -gt 0) {
    $active = @($guides | Where-Object { $g = $_; @($changed | Where-Object { $_ -like "$g/*" }).Count -gt 0 })
    if ($active.Count -gt 0) {
        $out.Add("Uncommitted changes are in: $($active -join ', ') - load those guides first.")
    }
}

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$out -join "`n" | Write-Output
exit 0
