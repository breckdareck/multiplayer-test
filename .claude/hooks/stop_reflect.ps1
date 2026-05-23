# Stop hook - self-improving drift check.
#
# Runs at end-of-turn. If subsystem code changed during this session but the
# matching CLAUDE.md was never touched, blocks the stop and asks Claude to
# either update the guide or explicitly note why no update is needed.
#
# Deterministic + free: just a `git diff` against the session-start SHA written
# by session_start_context.ps1. No LLM call per Stop.
#
# Respects stop_hook_active: nudges at most once per stop-chain, so Claude can
# never get stuck in an infinite block loop.
#
# Run standalone to test:
#   '{"session_id":"test","stop_hook_active":false}' | pwsh -NoProfile -File .claude/hooks/stop_reflect.ps1

$ErrorActionPreference = 'SilentlyContinue'

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

# --- Read hook input from stdin ----------------------------------------------
$stdin = [Console]::In.ReadToEnd()
$payload = $null
if ($stdin) { $payload = ConvertFrom-Json $stdin -ErrorAction SilentlyContinue }
$sid = $payload.session_id
$stopActive = [bool]$payload.stop_hook_active

# Already nudged this stop-chain - let Claude stop now.
if ($stopActive) { exit 0 }

# --- Locate session-start baseline -------------------------------------------
$stateDir = Join-Path $root '.claude\.session-state'
$markerPath = $null
if ($sid)                     { $markerPath = Join-Path $stateDir "$sid.json" }
if (-not (Test-Path $markerPath)) { $markerPath = Join-Path $stateDir 'last.json' }
if (-not (Test-Path $markerPath)) { exit 0 }   # No baseline -> nothing to diff.

$marker = Get-Content $markerPath -Raw | ConvertFrom-Json
$startSha = $marker.head_sha
if (-not $startSha) { exit 0 }

# --- Collect files changed since session start (committed + working tree) ----
$changed = New-Object System.Collections.Generic.HashSet[string]
$null = & git -C $root diff --name-only "$startSha" HEAD 2>$null |
    ForEach-Object { if ($_) { [void]$changed.Add($_.Replace('\','/')) } }
$null = & git -C $root status --porcelain 2>$null | ForEach-Object {
    if ($_.Length -gt 3) {
        $path = $_.Substring(3).Trim().Trim('"').Replace('\','/')
        # Rename lines look like "old -> new" - take the new path.
        if ($path -match ' -> ') { $path = ($path -split ' -> ')[-1] }
        [void]$changed.Add($path)
    }
}

if ($changed.Count -eq 0) { exit 0 }

# --- Subsystem -> CLAUDE.md mapping ------------------------------------------
# A subsystem is "dirty" if any non-doc file under it changed.
# It's "covered" if its CLAUDE.md was also touched.
$subsystems = @(
    @{ prefix = 'scripts/Networking/'; guide = 'scripts/Networking/CLAUDE.md' },
    @{ prefix = 'scripts/Components/'; guide = 'scripts/Components/CLAUDE.md' },
    @{ prefix = 'scripts/Bot/';        guide = 'scripts/Bot/CLAUDE.md' },
    @{ prefix = 'scripts/Resources/';  guide = 'scripts/Resources/CLAUDE.md' },
    @{ prefix = 'backend/';            guide = 'backend/CLAUDE.md' }
)

function Test-IsCodeChange([string]$path) {
    # Ignore docs, lockfiles, godot import sidecars, the marker itself.
    if ($path -like '*CLAUDE.md')        { return $false }
    if ($path -like '*.md')              { return $false }
    if ($path -like '*.uid')             { return $false }
    if ($path -like '*.import')          { return $false }
    if ($path -like '.claude/.session-state/*') { return $false }
    return $true
}

$drift = [ordered]@{}
foreach ($s in $subsystems) {
    $codeHits = @($changed | Where-Object { $_ -like "$($s.prefix)*" -and (Test-IsCodeChange $_) })
    if ($codeHits.Count -eq 0) { continue }
    $guideTouched = $changed.Contains($s.guide)
    if (-not $guideTouched) {
        $drift[$s.guide] = $codeHits
    }
}

# Root-level signals: autoloads, skills, new managers.
$rootGuideTouched = $changed.Contains('CLAUDE.md')
$rootSignals = @()

if ($changed.Contains('project.godot') -and -not $rootGuideTouched) {
    # Cheap proxy: any project.godot change is worth glancing at the autoload table.
    $rootSignals += 'project.godot (check autoload table in root CLAUDE.md)'
}
$newSkills = @($changed | Where-Object { $_ -match '^\.claude/skills/[^/]+/SKILL\.md$' })
if ($newSkills.Count -gt 0 -and -not $rootGuideTouched) {
    $rootSignals += "new/updated skills: $($newSkills -join ', ') (check Skills table in root CLAUDE.md + AI-LAYER.md)"
}
$managerHits = @($changed | Where-Object { $_ -like 'scripts/Managers/*' -and (Test-IsCodeChange $_) })
if ($managerHits.Count -gt 0 -and -not $rootGuideTouched) {
    $rootSignals += "scripts/Managers/ changes: $($managerHits -join ', ') (check autoload table)"
}

if ($drift.Count -eq 0 -and $rootSignals.Count -eq 0) { exit 0 }

# --- Build the block reason --------------------------------------------------
$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add('Drift check: subsystem code changed this session, but its CLAUDE.md did not.')
$lines.Add('')
foreach ($guide in $drift.Keys) {
    $files = $drift[$guide]
    $shown = $files | Select-Object -First 6
    $more  = if ($files.Count -gt 6) { " (+$($files.Count - 6) more)" } else { '' }
    $lines.Add("- $guide`n    changed: $($shown -join ', ')$more")
}
foreach ($sig in $rootSignals) {
    $lines.Add("- CLAUDE.md (root)`n    $sig")
}
$lines.Add('')
$lines.Add('For each guide above: either update it to match the new behavior, or reply with one sentence on why no update is needed (e.g. "internal refactor, public contract unchanged"). Then stop.')
$lines.Add('')
$lines.Add('Memory pass: also scan this turn for explicit user corrections or confirmations and save them under memory/ per the auto-memory rules.')

$reason = ($lines -join "`n")

# --- Emit decision -----------------------------------------------------------
$response = @{
    decision = 'block'
    reason   = $reason
} | ConvertTo-Json -Compress

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Write-Output $response
exit 0
