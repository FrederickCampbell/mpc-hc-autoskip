[CmdletBinding()]
param([string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$checks = @{
    'src/mpc-hc/MainFrm.cpp'        = 'MPC-HC AutoSkip: chapter matcher'
    'src/mpc-hc/MainFrm.h'          = 'AutoSkipChapterIfNeeded'
    'src/mpc-hc/AppSettings.h'      = 'bAutoSkipChapters'
    'src/mpc-hc/AppSettings.cpp'    = 'IDS_RS_AUTOSKIP_CHAPTER_PATTERNS'
    'src/mpc-hc/PPageAdvanced.cpp'  = 'AutoSkipChapterPatterns'
    'src/mpc-hc/PPageAdvanced.h'    = 'AUTOSKIP_CHAPTER_PATTERNS'
    'src/mpc-hc/SettingsDefines.h'  = 'IDS_RS_AUTOSKIP_CHAPTERS'
}

foreach ($item in $checks.GetEnumerator()) {
    $path = Join-Path $RepoRoot $item.Key
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Missing file: $($item.Key)"
    }
    $text = [IO.File]::ReadAllText($path)
    if (-not $text.Contains($item.Value)) {
        throw "AutoSkip verification failed in $($item.Key): missing '$($item.Value)'"
    }
}

Write-Host 'AutoSkip source markers verified.' -ForegroundColor Green
